import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/savings_goal.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
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
      body: goals.isEmpty
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
                            borderRadius: const BorderRadius.circular(8),
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
    );
  }

  void _confirmDelete(BuildContext context, SavingsGoal goal) {
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
              await ctx.read<MoneyProvider>().removeGoal(goal.id!);
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
      _targetCtrl.text = existing.targetAmount.toStringAsFixed(0);
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
    final picked = await showDatePicker(
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
            if (!_formKey.currentState!.validate()) return;
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
            if (!_formKey.currentState!.validate()) return;
            await context.read<MoneyProvider>().addSavings(
                  widget.goal.id!,
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
