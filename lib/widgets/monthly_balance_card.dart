import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../theme/design_tokens.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// Monthly starting balance: how much money the user had at the start of
/// the month, minus what was spent = remaining. Tap to set/edit.
class MonthlyBalanceCard extends StatefulWidget {
  const MonthlyBalanceCard({super.key});

  @override
  State<MonthlyBalanceCard> createState() => _MonthlyBalanceCardState();
}

class _MonthlyBalanceCardState extends State<MonthlyBalanceCard> {
  double? _startBalance;
  bool _loading = true;

  String get _key => 'month_start_${monthKeyOf(DateTime.now())}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw =
          await DatabaseHelper.instance.getSetting(_key);
      final v = double.tryParse(raw ?? '');
      if (mounted) {
        setState(() {
          _startBalance = v;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final current = _startBalance ?? 0;
    final ctrl = TextEditingController(
      text: current.truncateToDouble() == current
          ? current.toStringAsFixed(0)
          : current.toString(),
    );
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'month_start_title')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(dctx, 'month_start_hint'),
                style: Theme.of(dctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(dctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr(dctx, 'month_start_amount'),
                  border: const OutlineInputBorder(),
                  prefixText: '৳ ',
                ),
                validator: (v) {
                  final d = double.tryParse((v ?? '').trim());
                  if (d == null || d < 0) return tr(dctx, 'cash_invalid');
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(tr(dctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dctx)
                    .pop(double.parse(ctrl.text.trim()));
              }
            },
            child: Text(tr(dctx, 'save')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || !mounted) return;
    await DatabaseHelper.instance.setSetting(_key, '$value');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expenses = context.watch<ExpenseProvider>();
    final spent = expenses.totalThisMonth();

    return StaggeredEntrance(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'month_start_title'),
                      style: KIOS.sectionTitle(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: KIOS.secondaryText(context),
                    tooltip: tr(context, 'month_start_title'),
                    onPressed: _edit,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ))
              else if (_startBalance == null) ...[
                Text(
                  tr(context, 'month_start_empty'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.add),
                    label: Text(tr(context, 'month_start_set')),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    _stat(
                      context,
                      label: tr(context, 'month_start_had'),
                      value: _startBalance!,
                      theme: theme,
                    ),
                    _stat(
                      context,
                      label: tr(context, 'month_start_spent'),
                      value: spent,
                      theme: theme,
                      color: theme.colorScheme.error,
                    ),
                    _stat(
                      context,
                      label: tr(context, 'month_start_left'),
                      value: _startBalance! - spent,
                      theme: theme,
                      color: (_startBalance! - spent) >= 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _startBalance! > 0
                        ? (spent / _startBalance!).clamp(0.0, 1.0)
                        : 0,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      spent > _startBalance!
                          ? theme.colorScheme.error
                          : kGold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, 'month_start_pct').replaceAll(
                      '{p}',
                      _startBalance! > 0
                          ? '${(spent / _startBalance! * 100).round()}'
                          : '0'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(
    BuildContext context, {
    required String label,
    required double value,
    required ThemeData theme,
    Color? color,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: KIOS.secondaryText(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatMoney(value),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
