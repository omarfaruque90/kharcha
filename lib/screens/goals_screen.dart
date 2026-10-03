import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/savings_goal.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/branded_date_picker.dart';
import '../widgets/motion.dart';

/// Savings goals with progress bars, "add savings" increments and
/// deadline display.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final theme = Theme.of(context);
    final lang = context.watch<SettingsProvider>().language;
    final goals = money.goals;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'goals_title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _GoalDialog(),
        ),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'goal_add')),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: _StreakCard(),
          ),
          Expanded(
            child: goals.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.savings_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(context, 'no_goals'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            tr(context, 'no_goals_sub'),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const _GoalDialog(),
                          ),
                          icon: const Icon(Icons.add),
                          label: Text(tr(context, 'goal_add')),
                        ),
                      ],
                    ),
                  )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: goals.length,
              itemBuilder: (context, i) {
                final goal = goals[i];
                final ratio = goal.targetAmount > 0
                    ? goal.savedAmount / goal.targetAmount
                    : 0.0;
                final done = ratio >= 1;
                return StaggeredEntrance(
                  key: ValueKey('goal-${goal.id}'),
                  delayMs: (i * 60).clamp(0, 240).toInt(),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.secondary.withValues(
                                  alpha: 0.15,
                                ),
                                child: Text(
                                  goal.emoji.isEmpty ? '💰' : goal.emoji,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      goal.title,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (goal.deadline != null)
                                      Text(
                                        '${tr(context, 'goal_deadline_short')}: '
                                        '${DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(goal.deadline!)}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                              if (done)
                                Chip(
                                  label: Text(tr(context, 'goal_completed')),
                                  backgroundColor: theme
                                      .colorScheme.secondaryContainer,
                                ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) =>
                                      _GoalDialog(existing: goal),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    _confirmDelete(context, goal),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: ratio.clamp(0.0, 1.0),
                              minHeight: 10,
                              backgroundColor: theme
                                  .colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                done
                                    ? theme.colorScheme.secondary
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${formatMoney(goal.savedAmount)} / '
                                '${formatMoney(goal.targetAmount)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${(ratio * 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) =>
                                    _AddSavingsDialog(goal: goal),
                              ),
                              icon: const Icon(Icons.add),
                              label: Text(
                                  tr(context, 'goal_add_savings')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, SavingsGoal goal) {
    final id = goal.id;
    if (id == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_goal_title')),
        content: Text(tr(ctx, 'delete_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await ctx.read<MoneyProvider>().removeGoal(id);
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
}

/// Monthly savings streak card (Package BB).
///
/// A month counts as "saved" when (income - expense) > 0. Computed from
/// existing provider data only — no new tables. Light by design: a single
/// pass over incomes and expenses per build, then 12 cheap lookups.
class _StreakCard extends StatelessWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final expenses = context.watch<ExpenseProvider>().expenses;
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final locale = lang == 'bn' ? 'bn' : 'en';
    final isDark = theme.brightness == Brightness.dark;
    final gold = isDark ? kGoldLight : kGoldDark;
    final grey = theme.colorScheme.outline.withValues(alpha: 0.4);

    // --- compute once per build -----------------------------------------
    final now = DateTime.now();
    // Last 12 calendar months, oldest first.
    final months =
        List.generate(12, (i) => DateTime(now.year, now.month - 11 + i));

    final incomeByMonth = <String, double>{};
    for (final income in money.incomes) {
      final key = monthKeyOf(income.date);
      incomeByMonth[key] = (incomeByMonth[key] ?? 0) + income.amount;
    }
    final expenseByMonth = <String, double>{};
    for (final e in expenses) {
      final key = monthKeyOf(e.date);
      expenseByMonth[key] =
          (expenseByMonth[key] ?? 0) + (e.bdtAmount ?? e.amount);
    }

    final nets = <double>[];
    final saved = <bool>[];
    for (final m in months) {
      final key = monthKeyOf(m);
      final net = (incomeByMonth[key] ?? 0) - (expenseByMonth[key] ?? 0);
      nets.add(net);
      saved.add(net > 0);
    }

    // Current streak: consecutive saved months ending this month. If this
    // month is not saved yet, count back from last month instead.
    var current = 0;
    var start = saved.length - 1;
    if (!saved[start]) start -= 1;
    for (var i = start; i >= 0 && saved[i]; i--) {
      current++;
    }

    // Best streak: longest run inside the 12-month window.
    var best = 0;
    var run = 0;
    for (final s in saved) {
      if (s) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'streak_title'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    context,
                    '🔥',
                    tr(context, 'streak_current'),
                    current,
                    gold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statTile(
                    context,
                    '🏆',
                    tr(context, 'streak_best'),
                    best,
                    gold,
                  ),
                ),
              ],
            ),
            if (current == 0 && best == 0) ...[
              const SizedBox(height: 8),
              Text(
                tr(context, 'streak_empty_hint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              tr(context, 'streak_history'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 12; i++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${DateFormat.yMMM(locale).format(months[i])}: '
                          "${saved[i] ? '✓' : '✗'} ${formatMoney(nets[i])}",
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: saved[i] ? gold : grey,
                              border: saved[i]
                                  ? null
                                  : Border.all(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.5),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat.MMM(locale).format(months[i]),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              color: saved[i]
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.outline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(
    BuildContext context,
    String emoji,
    String label,
    int value,
    Color accent,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji $label',
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$value',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                tr(context, 'streak_unit_months'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dialog to add or edit a savings goal.
class _GoalDialog extends StatefulWidget {
  final SavingsGoal? existing;

  const _GoalDialog({this.existing});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleCtrl.text = existing.title;
      // Keep decimals (see income edit dialog) — rounding here would
      // corrupt the stored target on save.
      final target = existing.targetAmount;
      _targetCtrl.text = target.truncateToDouble() == target
          ? target.toStringAsFixed(0)
          : target.toString();
      _emojiCtrl.text = existing.emoji;
      _deadline = existing.deadline;
    } else {
      _emojiCtrl.text = '💰';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final lang = context.read<SettingsProvider>().language;
    final now = DateTime.now();
    final picked = await showBrandedDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      locale: Locale(lang),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return AlertDialog(
      title: Text(
        tr(context, widget.existing == null ? 'goal_add' : 'goal_edit'),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: TextFormField(
                      controller: _emojiCtrl,
                      decoration: InputDecoration(
                        labelText: tr(context, 'goal_emoji'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        labelText: tr(context, 'goal_title_label'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? tr(context, 'err_title_empty')
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _targetCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'goal_target'),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  _deadline == null
                      ? tr(context, 'goal_deadline')
                      : DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en')
                          .format(_deadline!),
                ),
                trailing: _deadline == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _deadline = null),
                      ),
                onTap: _pickDeadline,
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
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final money = context.read<MoneyProvider>();
            final existing = widget.existing;
            if (existing == null) {
              await money.addGoal(SavingsGoal(
                title: _titleCtrl.text.trim(),
                targetAmount: double.parse(_targetCtrl.text.trim()),
                deadline: _deadline,
                emoji: _emojiCtrl.text.trim().isEmpty
                    ? '💰'
                    : _emojiCtrl.text.trim(),
              ));
            } else {
              await money.updateGoal(existing.copyWith(
                title: _titleCtrl.text.trim(),
                targetAmount: double.parse(_targetCtrl.text.trim()),
                deadline: _deadline,
                clearDeadline: _deadline == null,
                emoji: _emojiCtrl.text.trim().isEmpty
                    ? '💰'
                    : _emojiCtrl.text.trim(),
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

/// Dialog to add savings to a goal (increments savedAmount).
class _AddSavingsDialog extends StatefulWidget {
  final SavingsGoal goal;

  const _AddSavingsDialog({required this.goal});

  @override
  State<_AddSavingsDialog> createState() => _AddSavingsDialogState();
}

class _AddSavingsDialogState extends State<_AddSavingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'goal_add_savings')),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _amountCtrl,
          autofocus: true,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () async {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final id = widget.goal.id;
            if (id == null) return;
            await context.read<MoneyProvider>().addSavings(
                  id,
                  double.parse(_amountCtrl.text.trim()),
                );
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
