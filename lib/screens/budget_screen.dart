import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/carry_forward_service.dart';
import '../services/public_templates_service.dart';
import '../services/voice_budget_parser.dart';
import '../utils/formatters.dart';
import '../widgets/category_dialogs.dart';
import '../widgets/motion.dart';

/// Monthly per-category spending limits: set/edit budgets, see spent vs
/// limit with progress bars, and get warned at 80% / when exceeded.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  /// Carried-forward leftover per category (BP: carry-forward), loaded
  /// once per screen open.
  Map<String, double> _carried = {};

  /// Cached future — avoids re-querying the DB on every rebuild.
  Future<Map<String, double>>? _spentFuture;
  String? _spentKey;

  @override
  void initState() {
    super.initState();
    _loadCarried();
  }

  Future<void> _loadCarried() async {
    try {
      final m = await CarryForwardService.carriedMap();
      if (mounted) setState(() => _carried = m);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final lang = context.watch<SettingsProvider>().language;
    final key = monthKeyOf(DateTime.now());
    // Cache the future per month key — don't re-query on every rebuild.
    if (_spentKey != key) {
      _spentKey = key;
      _spentFuture = money.expenseForMonth(key);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'budget_title')),
        actions: [
          // BI: publish this month's budgets as a public template.
          TextButton.icon(
            onPressed: () async {
              final money = context.read<MoneyProvider>();
              final budgets = money.budgetsForMonth(key);
              if (budgets.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr(context, 'pt_share_empty'))),
                );
                return;
              }
              final nameCtrl = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr(ctx, 'pt_share_name_title')),
                  content: TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: tr(ctx, 'pt_share_name_hint'),
                    ),
                    autofocus: true,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(tr(ctx, 'cancel')),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(ctx).pop(nameCtrl.text.trim()),
                      child: Text(tr(ctx, 'pt_share')),
                    ),
                  ],
                ),
              );
              nameCtrl.dispose();
              if (name == null || name.isEmpty || !context.mounted) return;
              final user = AuthService.instance.currentUser;
              final author = (user?.displayName?.isNotEmpty == true)
                  ? user!.displayName!
                  : (user?.email ?? tr(context, 'auth_guest_label'));
              try {
                final ok = await PublicTemplatesService.instance
                    .publish(name, budgets, author);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(tr(context,
                            ok ? 'pt_shared' : 'pt_share_failed'))),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr(context, 'pt_share_failed'))),
                  );
                }
              }
            },
            icon: const Icon(Icons.ios_share_outlined),
            label: Text(tr(context, 'pt_share')),
          ),
          IconButton(
            icon: const Icon(Icons.mic_outlined),
            tooltip: tr(context, 'voice_budget_title'),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => VoiceBudgetDialog(monthKey: key),
            ),
          ),
        ],
      ),
      floatingActionButton: money.budgetsForMonth(key).isEmpty
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _showBudgetDialog(context, key, null),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'budget_set')),
      ),
      body: FutureBuilder<Map<String, double>>(
        future: _spentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final spent = snapshot.data ?? <String, double>{};
          final budgets = money.budgetsForMonth(key);
          final warnings = budgets.where((b) {
            final s = spent[b.categoryId] ?? 0;
            return b.limitAmount > 0 && s / b.limitAmount >= 0.8;
          }).toList(growable: false);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              StaggeredEntrance(
                child: _MonthlyBudgetCard(
                  monthKey: key,
                  totalSpent: spent.values.fold(0.0, (a, b) => a + b),
                ),
              ),
              if (warnings.isNotEmpty)
                StaggeredEntrance(
                  child: _WarningBanner(
                    budgets: warnings,
                    spent: spent,
                    lang: lang,
                  ),
                ),
              if (budgets.isEmpty)
                StaggeredEntrance(
                  child: _EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: tr(context, 'no_budgets'),
                    subtitle: tr(context, 'no_budgets_sub'),
                    ctaLabel: tr(context, 'budget_set'),
                    onAdd: () =>
                        _showBudgetDialog(context, key, null),
                  ),
                ),
              for (var i = 0; i < budgets.length; i++)
                StaggeredEntrance(
                  key: ValueKey('budget-${budgets[i].id}'),
                  delayMs: (i * 60).clamp(0, 240).toInt(),
                  child: _BudgetCard(
                    budget: budgets[i],
                    spent: spent[budgets[i].categoryId] ?? 0,
                    carried: _carried[budgets[i].categoryId] ?? 0,
                    lang: lang,
                    onTap: () => _showBudgetDialog(
                        context, key, budgets[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showBudgetDialog(
      BuildContext context, String monthKey, Budget? existing) {
    showDialog(
      context: context,
      builder: (_) => _BudgetDialog(monthKey: monthKey, existing: existing),
    );
  }
}

/// Overall monthly spending-limit card shown at the top of the budget
/// screen. Tapping opens the set/edit dialog.
class _MonthlyBudgetCard extends StatelessWidget {
  final String monthKey;
  final double totalSpent;

  const _MonthlyBudgetCard({
    required this.monthKey,
    required this.totalSpent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = context.watch<MoneyProvider>();
    final budget = money.monthlyBudgetFor(monthKey);
    final limit = budget?.limitAmount ?? 0;
    final ratio = limit > 0 ? (totalSpent / limit).clamp(0.0, 1.0) : 0.0;
    final over = limit > 0 && totalSpent > limit;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _MonthlyBudgetDialog(
            monthKey: monthKey,
            existing: budget,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.savings_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, 'monthly_budget'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          tr(context, 'monthly_budget_sub'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (limit <= 0)
                    FilledButton.tonal(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _MonthlyBudgetDialog(
                          monthKey: monthKey,
                          existing: budget,
                        ),
                      ),
                      child: Text(tr(context, 'monthly_budget_set')),
                    )
                  else
                    IconButton(
                      tooltip: tr(context, 'budget_edit'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _MonthlyBudgetDialog(
                          monthKey: monthKey,
                          existing: budget,
                        ),
                      ),
                    ),
                ],
              ),
              if (limit > 0) ...[
                const SizedBox(height: 12),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (ctx, t, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (ratio * t).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        over
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${formatMoney(totalSpent)} / ${formatMoney(limit)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: over ? theme.colorScheme.error : null,
                      ),
                    ),
                    Text(
                      '${(ratio * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog for setting/editing/removing the overall monthly budget.
class _MonthlyBudgetDialog extends StatefulWidget {
  final String monthKey;
  final Budget? existing;

  const _MonthlyBudgetDialog({required this.monthKey, this.existing});

  @override
  State<_MonthlyBudgetDialog> createState() => _MonthlyBudgetDialogState();
}

class _MonthlyBudgetDialogState extends State<_MonthlyBudgetDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.existing != null && widget.existing!.limitAmount > 0
          ? widget.existing!.limitAmount.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'monthly_budget')),
      content: TextField(
        controller: _ctrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
        decoration: InputDecoration(
          hintText: tr(context, 'monthly_budget_hint'),
          prefixText: '৳ ',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () async {
              await context
                  .read<MoneyProvider>()
                  .setMonthlyBudget(widget.monthKey, 0);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(
              tr(context, 'monthly_budget_remove'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () async {
            final v = double.tryParse(_ctrl.text.trim());
            if (v == null || v <= 0) return;
            await context
                .read<MoneyProvider>()
                .setMonthlyBudget(widget.monthKey, v);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}

/// Amber/red banner listing budgets at >=80% (amber) or exceeded (red).
class _WarningBanner extends StatelessWidget {
  final List<Budget> budgets;
  final Map<String, double> spent;
  final String lang;

  const _WarningBanner({
    required this.budgets,
    required this.spent,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final anyExceeded = budgets.any((b) {
      final s = spent[b.categoryId] ?? 0;
      return b.limitAmount > 0 && s > b.limitAmount;
    });
    // "Near limit" banner: gold-tinted surface + gold text, readable
    // in both themes.
    final bg = anyExceeded
        ? theme.colorScheme.errorContainer
        : kGold.withValues(alpha: isDark ? 0.22 : 0.16);
    final fg = anyExceeded
        ? theme.colorScheme.onErrorContainer
        : isDark
            ? kGoldLight
            : kGoldDark;
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: fg),
                const SizedBox(width: 8),
                Text(
                  anyExceeded
                      ? tr(context, 'budget_exceeded')
                      : tr(context, 'budget_near_limit'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final b in budgets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${CustomCategoryRegistry.displayName(b.categoryId, lang)} — '
                  '${formatMoney(spent[b.categoryId] ?? 0)} / '
                  '${formatMoney(b.limitAmount)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final double spent;
  final double carried;
  final String lang;
  final VoidCallback onTap;

  const _BudgetCard({
    required this.budget,
    required this.spent,
    this.carried = 0,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = categoryById(budget.categoryId);
    final ratio = budget.limitAmount > 0 ? spent / budget.limitAmount : 0.0;
    Color colorFor(double r) => r >= 1
        ? theme.colorScheme.error
        : r >= 0.8
            ? const Color(0xFFF9A825)
            : theme.colorScheme.primary;
    return PressableScale(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          // Bars + numbers count up on open (~800ms, easeOutCubic).
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (ctx, t, _) {
              final ar = ratio * t;
              final barColor = colorFor(ar);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: cat.color.withValues(alpha: 0.15),
                        child: Icon(cat.icon, color: cat.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              CustomCategoryRegistry.displayName(
                                  budget.categoryId, lang),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${tr(context, 'spent')}: ${formatMoney(spent * t)} / '
                              '${formatMoney(budget.limitAmount)}',
                              style: theme.textTheme.bodyMedium,
                            ),
                            // BP: subtle badge when leftover was carried
                            // into this month's budget for this category.
                            if (carried > 0)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kGold.withValues(alpha: 0.18),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    tr(context, 'carried_badge')
                                        .replaceAll('{amount}',
                                            formatMoney(carried)),
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${(ar * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: barColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ar.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ratio >= 1
                        ? tr(context, 'budget_exceeded')
                        : '${tr(context, 'remaining')}: '
                            '${formatMoney(budget.limitAmount - spent)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ratio >= 1
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          ratio >= 1 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(ctaLabel),
          ),
        ],
      ),
    );
  }
}

/// Dialog to add (pick a category + limit) or edit (change limit/delete)
/// a budget for [monthKey].
class _BudgetDialog extends StatefulWidget {
  final String monthKey;
  final Budget? existing;

  const _BudgetDialog({required this.monthKey, this.existing});

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  late String _categoryId;
  int _catNonce = 0;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final visible = CustomCategoryRegistry.visibleBuiltinCategories();
    _categoryId = existing?.categoryId ??
        (visible.isNotEmpty ? visible.first.id : kCategories.first.id);
    if (existing != null) {
      _amountCtrl.text = existing.limitAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  /// (id, icon, label) for the category dropdown: visible built-ins +
  /// customs, plus the currently-selected id even when hidden (edit mode).
  List<(String, Widget, String)> _budgetDialogItems(String lang) {
    final items = <(String, Widget, String)>[];
    final seen = <String>{};
    for (final c in CustomCategoryRegistry.visibleBuiltinCategories()) {
      seen.add(c.id);
      items.add((
        c.id,
        Icon(c.icon, size: 18, color: c.color),
        CustomCategoryRegistry.displayName(c.id, lang),
      ));
    }
    for (final cc in CustomCategoryRegistry.all) {
      seen.add(cc.id);
      items.add((
        cc.id,
        cc.emoji.isNotEmpty
            ? Text(cc.emoji, style: const TextStyle(fontSize: 18))
            : const Icon(Icons.label_rounded, size: 18),
        cc.name,
      ));
    }
    // Editing a budget whose category is now hidden: keep it selectable.
    if (!seen.contains(_categoryId)) {
      final custom = CustomCategoryRegistry.byId(_categoryId);
      items.add((
        _categoryId,
        custom != null
            ? Text(custom.emoji, style: const TextStyle(fontSize: 18))
            : const Icon(Icons.label_rounded, size: 18),
        CustomCategoryRegistry.displayName(_categoryId, lang),
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final existing = widget.existing;
    return AlertDialog(
      title: Text(
        tr(context, existing == null ? 'budget_set' : 'budget_edit'),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('cat-$_categoryId-$_catNonce'),
              initialValue: _categoryId,
              decoration: InputDecoration(
                labelText: tr(context, 'category'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in _budgetDialogItems(lang))
                  DropdownMenuItem(
                    value: c.$1,
                    child: Row(
                      children: [
                        c.$2,
                        const SizedBox(width: 8),
                        Flexible(child: Text(c.$3)),
                      ],
                    ),
                  ),
                DropdownMenuItem(
                  value: '__add_new__',
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline,
                          size: 18, color: kGoldDark),
                      const SizedBox(width: 8),
                      Text(tr(context, 'add_category')),
                    ],
                  ),
                ),
              ],
              onChanged: existing == null
                  ? (v) async {
                      if (v == '__add_new__') {
                        final id = await showAddCategoryDialog(context);
                        if (!mounted) return;
                        setState(() {
                          _catNonce++;
                          if (id != null) _categoryId = id;
                        });
                        return;
                      }
                      setState(() => _categoryId = v ?? _categoryId);
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: InputDecoration(
                labelText: tr(context, 'limit'),
                prefixText: '৳ ',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return tr(context, 'err_amount_invalid');
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (existing != null)
          TextButton.icon(
            onPressed: () async {
              final money = context.read<MoneyProvider>();
              await money.removeBudget(existing.id!);
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr(context, 'msg_deleted'))),
                );
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(tr(context, 'delete')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final amount = double.parse(_amountCtrl.text.trim());
            final money = context.read<MoneyProvider>();
            if (existing == null) {
              await money.upsertBudget(Budget(
                categoryId: _categoryId,
                monthKey: widget.monthKey,
                limitAmount: amount,
              ));
            } else {
              await money.updateBudget(
                existing.copyWith(limitAmount: amount),
              );
            }
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(context, 'msg_saved'))),
              );
            }
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}

/// BT: voice budget setup dialog. Listens via speech_to_text, parses
/// "<category> budget <amount>" (Bangla + English), shows the parsed
/// result and confirms one-tap budget save.
class VoiceBudgetDialog extends StatefulWidget {
  final String monthKey;
  const VoiceBudgetDialog({super.key, required this.monthKey});

  @override
  State<VoiceBudgetDialog> createState() => _VoiceBudgetDialogState();
}

class _VoiceBudgetDialogState extends State<VoiceBudgetDialog> {
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  String _heard = '';
  VoiceBudgetResult? _parsed;
  String? _pickedCategoryId;

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    bool available = false;
    try {
      available = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'notListening' || s == 'done') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    } catch (_) {
      available = false;
    }
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'voice_error'))),
        );
      }
      return;
    }
    if (!mounted) return;
    final lang = context.read<SettingsProvider>().language;
    setState(() {
      _listening = true;
      _heard = '';
      _parsed = null;
      _pickedCategoryId = null;
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: lang == 'bn' ? 'bn_BD' : 'en_US',
        listenFor: const Duration(seconds: 12),
        partialResults: true,
      ),
      onResult: (r) {
        final words = r.recognizedWords.trim();
        if (!mounted || words.isEmpty) return;
        setState(() {
          _heard = words;
          // Live parse on partial results too.
          _parsed = VoiceBudgetParser.parse(words, lang);
        });
        if (r.finalResult) {
          _speech.stop();
          setState(() => _listening = false);
        }
      },
    );
  }

  Future<void> _confirm() async {
    final parsed = _parsed;
    final categoryId = parsed?.categoryId ?? _pickedCategoryId;
    final amount = parsed?.amount;
    if (categoryId == null || categoryId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'voice_budget_no_category'))),
      );
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'voice_budget_no_amount'))),
      );
      return;
    }
    final money = context.read<MoneyProvider>();
    await money.upsertBudget(Budget(
      categoryId: categoryId,
      monthKey: widget.monthKey,
      limitAmount: amount,
    ));
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'msg_saved'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final parsed = _parsed;
    final categoryId = parsed?.categoryId ?? _pickedCategoryId;
    final amount = parsed?.amount;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(tr(context, 'voice_budget_title')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(context, 'voice_budget_hint'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Live transcript.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                _heard.isEmpty
                    ? tr(context, 'voice_budget_tap_mic')
                    : '“$_heard”',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            if (parsed != null) ...[
              Row(
                children: [
                  const Icon(Icons.category_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: categoryId != null
                        ? Text(
                            CustomCategoryRegistry.displayName(
                                categoryId, lang),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : Text(tr(context, 'voice_budget_no_category')),
                  ),
                  if (categoryId == null)
                    TextButton(
                      onPressed: () async {
                        final picked = await showDialog<String>(
                          context: context,
                          builder: (c) => SimpleDialog(
                            title: Text(tr(c, 'category')),
                            children: [
                              for (final c2 in CustomCategoryRegistry
                                  .visibleBuiltinCategories())
                                SimpleDialogOption(
                                  onPressed: () =>
                                      Navigator.pop(c, c2.id),
                                  child: Text(
                                    CustomCategoryRegistry.displayName(
                                        c2.id, lang),
                                  ),
                                ),
                              for (final cc in CustomCategoryRegistry.all)
                                SimpleDialogOption(
                                  onPressed: () =>
                                      Navigator.pop(c, cc.id),
                                  child: Text(cc.name),
                                ),
                            ],
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() => _pickedCategoryId = picked);
                        }
                      },
                      child: Text(tr(context, 'voice_budget_pick')),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    amount != null && amount > 0
                        ? formatMoney(amount)
                        : tr(context, 'voice_budget_no_amount'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _toggleMic,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(tr(context,
                  _listening ? 'voice_budget_stop' : 'voice_budget_listen')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: (categoryId != null && amount != null && amount > 0)
              ? _confirm
              : null,
          child: Text(tr(context, 'voice_budget_confirm')),
        ),
      ],
    );
  }
}
