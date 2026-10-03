import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/branded_date_picker.dart';
import '../widgets/motion.dart';

/// Subscriptions tracker (Package D): CRUD + active toggle + "mark paid"
/// (records an expense and advances the next due date).
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  List<AppSubscription> _subs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final items = await DatabaseHelper.instance.getSubscriptions();
      items.sort((a, b) => a.nextDue.compareTo(b.nextDue));
      if (mounted) setState(() => _subs = items);
    } catch (_) {
      // List stays empty on failure.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _advance(DateTime due, String cycle) {
    final now = DateTime.now();
    var base = _day(due);
    final today = _day(now);
    if (base.isBefore(today)) base = today;
    return cycle == 'yearly'
        ? DateTime(base.year + 1, base.month, base.day)
        : DateTime(base.year, base.month + 1, base.day);
  }

  double _monthlyCost() {
    var total = 0.0;
    for (final s in _subs) {
      if (!s.active) continue;
      total += s.cycle == 'yearly' ? s.amount / 12 : s.amount;
    }
    return total;
  }

  Future<void> _toggle(AppSubscription s, bool v) async {
    final updated = s.copyWith(active: v, updatedAt: DateTime.now());
    await DatabaseHelper.instance.updateSubscription(updated);
    final i = _subs.indexWhere((e) => e.id == s.id);
    if (i >= 0) _subs[i] = updated;
    if (mounted) setState(() {});
  }

  Future<void> _markPaid(AppSubscription s) async {
    final now = DateTime.now();
    await context.read<ExpenseProvider>().add(
          Expense(
            amount: s.amount,
            categoryId: 'bills',
            date: now,
            note: 'Subscription: ${s.name}',
            paymentMethod: 'cash',
          ),
        );
    s = s.copyWith(nextDue: _advance(s.nextDue, s.cycle), updatedAt: now);
    await DatabaseHelper.instance.updateSubscription(s);
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'subs_paid_msg'))),
      );
    }
  }

  void _confirmDelete(AppSubscription s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_subs_title')),
        content: Text(tr(ctx, 'delete_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteSubscription(s.id!);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'subs_title')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (_) => const _SubscriptionDialog(),
          );
          await _reload();
        },
        backgroundColor: kGold,
        foregroundColor: kDeepGreenDark,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _subs.isEmpty
                    ? _EmptyView(onAdd: () async {
                        await showDialog(
                          context: context,
                          builder: (_) => const _SubscriptionDialog(),
                        );
                        await _reload();
                      })
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _subs.length,
                          itemBuilder: (context, i) {
                            final s = _subs[i];
                            return StaggeredEntrance(
                              key: ValueKey('sub-${s.id}'),
                              delayMs: (i * 50).clamp(0, 250).toInt(),
                              child: _SubscriptionCard(
                                s: s,
                                onToggle: (v) => _toggle(s, v),
                                onPaid: () => _markPaid(s),
                                onEdit: () async {
                                  await showDialog(
                                    context: context,
                                    builder: (_) =>
                                        _SubscriptionDialog(existing: s),
                                  );
                                  await _reload();
                                },
                                onDelete: () => _confirmDelete(s),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          if (_subs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                      color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr(context, 'subs_monthly_cost'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    formatMoney(_monthlyCost()),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: kGoldDark,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final Future<void> Function() onAdd;

  const _EmptyView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.subscriptions_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(tr(context, 'no_subs'),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              tr(context, 'no_subs_sub'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(tr(context, 'subs_add')),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final AppSubscription s;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPaid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SubscriptionCard({
    required this.s,
    required this.onToggle,
    required this.onPaid,
    required this.onEdit,
    required this.onDelete,
  });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<SettingsProvider>().language;
    final due = _day(s.nextDue);
    final today = _day(DateTime.now());
    final days = due.difference(today).inDays;
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(s.nextDue);
    final cycleLabel =
        tr(context, s.cycle == 'yearly' ? 'subs_yearly' : 'subs_monthly');

    Color badgeBg;
    Color badgeFg;
    String badgeText;
    if (days < 0) {
      badgeBg = Colors.red.withValues(alpha: 0.15);
      badgeFg = Colors.red.shade700;
      badgeText = tr(context, 'subs_overdue_in')
          .replaceAll('{n}', '${-days}');
    } else if (days == 0) {
      badgeBg = Colors.red.withValues(alpha: 0.15);
      badgeFg = Colors.red.shade700;
      badgeText = tr(context, 'subs_due_today');
    } else if (days <= 3) {
      badgeBg = Colors.red.withValues(alpha: 0.15);
      badgeFg = Colors.red.shade700;
      badgeText =
          tr(context, 'subs_days_left').replaceAll('{n}', '$days');
    } else if (days <= 7) {
      badgeBg = kGold.withValues(alpha: 0.18);
      badgeFg = theme.brightness == Brightness.dark ? kGold : kGoldDark;
      badgeText =
          tr(context, 'subs_days_left').replaceAll('{n}', '$days');
    } else {
      badgeBg = theme.colorScheme.outline.withValues(alpha: 0.18);
      badgeFg = theme.colorScheme.outline;
      badgeText =
          tr(context, 'subs_days_left').replaceAll('{n}', '$days');
    }

    final leading = s.emoji.trim().isNotEmpty
        ? Text(s.emoji.trim(), style: const TextStyle(fontSize: 26))
        : Icon(Icons.subscriptions_outlined, color: kGoldDark);

    return Card(
      child: InkWell(
        onTap: onEdit,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: kGold.withValues(alpha: 0.15),
                    child: leading,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatMoney(s.amount)} • $cycleLabel',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${tr(context, 'subs_next_due')}: $dateLabel',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Chip(
                              label: Text(
                                badgeText,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: badgeFg,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: badgeBg,
                              side: BorderSide.none,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Switch(value: s.active, onChanged: onToggle),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: PressableScale(
                  child: FilledButton.tonalIcon(
                    onPressed: onPaid,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(tr(context, 'subs_mark_paid')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit dialog: name, amount, billing cycle, next-due date, emoji.
class _SubscriptionDialog extends StatefulWidget {
  final AppSubscription? existing;

  const _SubscriptionDialog({this.existing});

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  late String _cycle;
  late DateTime _nextDue;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl.text = existing?.name ?? '';
    _amountCtrl.text =
        existing != null ? existing.amount.toStringAsFixed(0) : '';
    _emojiCtrl.text = existing?.emoji ?? '';
    _cycle = existing?.cycle ?? 'monthly';
    _nextDue = existing?.nextDue ?? DateTime.now();
    _active = existing?.active ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final lang = context.read<SettingsProvider>().language;
    final picked = await showBrandedDatePicker(
      context: context,
      initialDate: _nextDue,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10),
      locale: Locale(lang == 'bn' ? 'bn' : 'en'),
    );
    if (picked != null && mounted) {
      setState(() => _nextDue = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return AlertDialog(
      title: Text(tr(context,
          widget.existing == null ? 'subs_add' : 'subs_edit')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'subs_name'),
                  hintText: tr(context, 'subs_name_hint'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? tr(context, 'err_title_empty')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'amount'),
                  prefixText: '৳ ',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) {
                    return tr(context, 'err_amount_invalid');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _cycle,
                decoration: InputDecoration(
                  labelText: tr(context, 'subs_cycle'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'monthly',
                    child: Text(tr(context, 'subs_monthly')),
                  ),
                  DropdownMenuItem(
                    value: 'yearly',
                    child: Text(tr(context, 'subs_yearly')),
                  ),
                ],
                onChanged: (v) => setState(() => _cycle = v ?? _cycle),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        '${tr(context, 'subs_next_due')}: '
                        '${DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(_nextDue)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emojiCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'subs_emoji'),
                  hintText: '🎬',
                  border: const OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'active')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
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
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final db = DatabaseHelper.instance;
            final existing = widget.existing;
            if (existing == null) {
              await db.insertSubscription(AppSubscription(
                id: AppSubscription.newId(),
                name: _nameCtrl.text.trim(),
                amount: double.parse(_amountCtrl.text.trim()),
                cycle: _cycle,
                nextDue: _nextDue,
                emoji: _emojiCtrl.text.trim(),
                active: _active,
              ));
            } else {
              await db.updateSubscription(existing.copyWith(
                name: _nameCtrl.text.trim(),
                amount: double.parse(_amountCtrl.text.trim()),
                cycle: _cycle,
                nextDue: _nextDue,
                emoji: _emojiCtrl.text.trim(),
                active: _active,
                updatedAt: DateTime.now(),
              ));
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
