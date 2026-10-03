import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/salary_rule.dart';
import '../models/savings_goal.dart';
import '../models/wishlist_item.dart';
import '../providers/money_provider.dart';
import '../widgets/motion.dart';

/// Salary planner (Package O): monthly salary amount + salary day, plus
/// distribution rules that auto-split the salary into savings goals and
/// wishlist items on salary day (see SalaryService.checkSalaryDay).
class SalaryScreen extends StatefulWidget {
  const SalaryScreen({super.key});

  @override
  State<SalaryScreen> createState() => _SalaryScreenState();
}

class _SalaryScreenState extends State<SalaryScreen> {
  final _amountCtrl = TextEditingController();
  int? _day;
  List<SalaryRule> _rules = [];
  List<WishlistItem> _wishlist = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final db = DatabaseHelper.instance;
      final amount = await db.getSetting('salary_amount');
      final day = int.tryParse(await db.getSetting('salary_day') ?? '');
      final rules = await db.getSalaryRules();
      final wishlist = await db.getWishlist();
      if (!mounted) return;
      setState(() {
        _amountCtrl.text = amount ?? '';
        _day = (day != null && day >= 1 && day <= 31) ? day : null;
        _rules = rules;
        _wishlist = wishlist;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0 || _day == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'err_amount_invalid'))),
        );
      }
      return;
    }
    await DatabaseHelper.instance.setSetting('salary_amount', '$amount');
    await DatabaseHelper.instance.setSetting('salary_day', '$_day');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'msg_saved'))),
      );
    }
  }

  double _totalPercent() =>
      _rules.fold(0.0, (sum, r) => sum + r.percent);

  String _targetLabel(SalaryRule r, List<SavingsGoal> goals) {
    switch (r.targetType) {
      case 'savings':
        final match = goals.where((g) => g.id == r.targetId);
        if (match.isEmpty) return tr(context, 'salary_target_savings');
        final title = match.first.title.trim();
        return title.isEmpty
            ? tr(context, 'salary_target_savings')
            : title;
      case 'wishlist':
        final match = _wishlist.where((w) => w.id == r.targetId);
        if (match.isEmpty) return tr(context, 'salary_target_wishlist');
        final item = match.first;
        final label = '${item.emoji} ${item.name}'.trim();
        return label.isEmpty
            ? tr(context, 'salary_target_wishlist')
            : label;
      default:
        return tr(context, 'salary_target_budget');
    }
  }

  IconData _targetIcon(String type) {
    switch (type) {
      case 'savings':
        return Icons.savings_outlined;
      case 'wishlist':
        return Icons.card_giftcard_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Future<void> _openDialog([SalaryRule? existing]) async {
    final otherTotal = _rules
        .where((r) => r.id != existing?.id)
        .fold(0.0, (sum, r) => sum + r.percent);
    await showDialog(
      context: context,
      builder: (_) => _SalaryRuleDialog(
        existing: existing,
        otherTotal: otherTotal,
        wishlistItems: _wishlist,
      ),
    );
    await _reload();
  }

  void _confirmDelete(SalaryRule r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'salary_delete_title')),
        content: Text(tr(ctx, 'delete_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteSalaryRule(r.id!);
              await _reload();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(tr(ctx, 'msg_deleted'))),
                );
              }
            },
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goals = context.watch<MoneyProvider>().goals;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'salary_title')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(),
        backgroundColor: kGold,
        foregroundColor: kDeepGreenDark,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _SettingsCard(
                    amountCtrl: _amountCtrl,
                    day: _day,
                    onDayChanged: (v) => setState(() => _day = v),
                    onSave: _saveSettings,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Text(
                      tr(context, 'salary_rules'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_rules.isEmpty)
                    _EmptyView(onAdd: () => _openDialog())
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _rules.length,
                      itemBuilder: (context, i) {
                        final r = _rules[i];
                        return StaggeredEntrance(
                          key: ValueKey('salary-rule-${r.id}'),
                          delayMs: (i * 50).clamp(0, 250).toInt(),
                          child: _RuleCard(
                            rule: r,
                            targetLabel: _targetLabel(r, goals),
                            onEdit: () => _openDialog(r),
                            onDelete: () => _confirmDelete(r),
                          ),
                        );
                      },
                    ),
                  if (_rules.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tr(context, 'salary_total'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_totalPercent().toStringAsFixed(_totalPercent().truncateToDouble() == _totalPercent() ? 0 : 1)}%',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: kGoldDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Salary amount + salary day (1-31) card.
class _SettingsCard extends StatelessWidget {
  final TextEditingController amountCtrl;
  final int? day;
  final ValueChanged<int?> onDayChanged;
  final VoidCallback onSave;

  const _SettingsCard({
    required this.amountCtrl,
    required this.day,
    required this.onDayChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: amountCtrl,
              decoration: InputDecoration(
                labelText: tr(context, 'salary_amount'),
                hintText: tr(context, 'salary_amount_hint'),
                prefixText: '৳ ',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: day,
              decoration: InputDecoration(
                labelText: tr(context, 'salary_day'),
                border: const OutlineInputBorder(),
              ),
              items: List.generate(
                31,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('${i + 1}'),
                ),
              ),
              onChanged: onDayChanged,
            ),
            const SizedBox(height: 12),
            PressableScale(
              child: FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(tr(context, 'salary_save_settings')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'salary_no_rules'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                tr(context, 'salary_no_rules_sub'),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'salary_add_rule')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final SalaryRule rule;
  final String targetLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleCard({
    required this.rule,
    required this.targetLabel,
    required this.onEdit,
    required this.onDelete,
  });

  IconData _icon() {
    switch (rule.targetType) {
      case 'savings':
        return Icons.savings_outlined;
      case 'wishlist':
        return Icons.card_giftcard_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = rule.percent;
    return Card(
      child: InkWell(
        onTap: onEdit,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: kGold.withValues(alpha: 0.15),
                child: Icon(_icon(), color: kGoldDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pct.toStringAsFixed(pct.truncateToDouble() == pct ? 0 : 1)}% • $targetLabel',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit dialog: name, percent, target type (savings goal picker /
/// wishlist item picker / budget = no transfer).
class _SalaryRuleDialog extends StatefulWidget {
  final SalaryRule? existing;

  /// Sum of all other rules' percents — used to enforce the 100% cap.
  final double otherTotal;
  final List<WishlistItem> wishlistItems;

  const _SalaryRuleDialog({
    this.existing,
    required this.otherTotal,
    required this.wishlistItems,
  });

  @override
  State<_SalaryRuleDialog> createState() => _SalaryRuleDialogState();
}

class _SalaryRuleDialogState extends State<_SalaryRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _percentCtrl = TextEditingController();
  late String _type;
  String? _targetId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl.text = existing?.name ?? '';
    _percentCtrl.text = existing != null
        ? (existing.percent.truncateToDouble() == existing.percent
            ? existing.percent.toStringAsFixed(0)
            : existing.percent.toString())
        : '';
    _type = existing?.targetType ?? 'savings';
    _targetId =
        (existing != null && existing.targetId.isNotEmpty) ? existing.targetId : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _percentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final percent = double.parse(_percentCtrl.text.trim());

    if (_type != 'budget' && _targetId == null) {
      setState(() => _error = tr(context, 'salary_err_target'));
      return;
    }
    if (widget.otherTotal + percent > 100) {
      setState(() => _error = tr(context, 'salary_err_total'));
      return;
    }

    final db = DatabaseHelper.instance;
    final existing = widget.existing;
    if (existing == null) {
      await db.insertSalaryRule(SalaryRule(
        id: SalaryRule.newId(),
        name: _nameCtrl.text.trim(),
        percent: percent,
        targetType: _type,
        targetId: _type == 'budget' ? '' : (_targetId ?? ''),
      ));
    } else {
      await db.updateSalaryRule(existing.copyWith(
        name: _nameCtrl.text.trim(),
        percent: percent,
        targetType: _type,
        targetId: _type == 'budget' ? '' : (_targetId ?? ''),
        updatedAt: DateTime.now(),
      ));
    }
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'msg_saved'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<MoneyProvider>().goals;
    return AlertDialog(
      title: Text(tr(context,
          widget.existing == null ? 'salary_add_rule' : 'salary_edit_rule')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'salary_rule_name'),
                  hintText: tr(context, 'salary_rule_name_hint'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? tr(context, 'err_title_empty')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _percentCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'salary_percent'),
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n < 1 || n > 100) {
                    return tr(context, 'salary_err_percent');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: InputDecoration(
                  labelText: tr(context, 'salary_target_type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'savings',
                    child: Text(tr(context, 'salary_target_savings')),
                  ),
                  DropdownMenuItem(
                    value: 'wishlist',
                    child: Text(tr(context, 'salary_target_wishlist')),
                  ),
                  DropdownMenuItem(
                    value: 'budget',
                    child: Text(tr(context, 'salary_target_budget')),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _type = v ?? _type),
              ),
              if (_type == 'savings') ...[
                const SizedBox(height: 12),
                if (goals.isEmpty)
                  Text(
                    tr(context, 'salary_no_goals'),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  DropdownButtonFormField<String>(
                    value: goals.any((g) => g.id == _targetId)
                        ? _targetId
                        : null,
                    decoration: InputDecoration(
                      labelText: tr(context, 'salary_pick_goal'),
                      border: const OutlineInputBorder(),
                    ),
                    items: goals
                        .map((g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(
                                  '${g.emoji} ${g.title}'.trim().isEmpty
                                      ? tr(context, 'salary_target_savings')
                                      : '${g.emoji} ${g.title}'.trim()),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _targetId = v),
                  ),
              ],
              if (_type == 'wishlist') ...[
                const SizedBox(height: 12),
                if (widget.wishlistItems.isEmpty)
                  Text(
                    tr(context, 'salary_no_wishlist'),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  DropdownButtonFormField<String>(
                    value: widget.wishlistItems
                            .any((w) => w.id == _targetId)
                        ? _targetId
                        : null,
                    decoration: InputDecoration(
                      labelText: tr(context, 'salary_pick_wishlist'),
                      border: const OutlineInputBorder(),
                    ),
                    items: widget.wishlistItems
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text('${w.emoji} ${w.name}'.trim()),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _targetId = v),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}
