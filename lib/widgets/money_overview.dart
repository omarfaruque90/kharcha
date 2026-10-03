import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/debt.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// "My Money" overview: cash + bank + lent out = total assets,
/// plus daily average spending. Shown on home.
class MoneyOverviewCard extends StatefulWidget {
  const MoneyOverviewCard({super.key});

  @override
  State<MoneyOverviewCard> createState() => _MoneyOverviewCardState();
}

class _MoneyOverviewCardState extends State<MoneyOverviewCard> {
  double _cash = 0;
  double _bank = 0;
  double _lent = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final cash = await db.getCashBalance();
      final bankStr = await db.getSetting('bank_balance');
      final debts = await db.getDebts();
      final lent = debts
          .where((d) => d.kind == 'lent' && !d.settled)
          .fold<double>(0, (s, d) => s + d.amount);
      if (mounted) {
        setState(() {
          _cash = cash;
          _bank = double.tryParse(bankStr ?? '') ?? 0;
          _lent = lent;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editBank() async {
    final lang = context.read<SettingsProvider>().language;
    final ctrl = TextEditingController(
      text: _bank.truncateToDouble() == _bank
          ? _bank.toStringAsFixed(0)
          : _bank.toString(),
    );
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'bank_balance_title')),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr(dctx, 'bank_balance_hint'),
              border: const OutlineInputBorder(),
              prefixText: '৳ ',
            ),
            validator: (v) {
              final d = double.tryParse((v ?? '').trim());
              if (d == null || d < 0) return tr(dctx, 'cash_invalid');
              return null;
            },
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
                Navigator.of(dctx).pop(double.parse(ctrl.text.trim()));
              }
            },
            child: Text(tr(dctx, 'save')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || !mounted) return;
    await DatabaseHelper.instance.setSetting('bank_balance', '$value');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final expenses = context.watch<ExpenseProvider>();

    // Daily average: this month's spend / days elapsed.
    final now = DateTime.now();
    final daysElapsed = now.day;
    final monthSpent = expenses.totalThisMonth();
    final dailyAvg = daysElapsed > 0 ? monthSpent / daysElapsed : 0.0;

    final total = _cash + _bank + _lent;

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
                      tr(context, 'money_overview'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined, size: 20),
                    tooltip: tr(context, 'refresh'),
                    onPressed: _load,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ))
              else ...[
                _row(
                  context,
                  icon: Icons.wallet_outlined,
                  label: tr(context, 'cash_wallet'),
                  value: _cash,
                  theme: theme,
                ),
                _row(
                  context,
                  icon: Icons.account_balance_outlined,
                  label: tr(context, 'bank_balance_title'),
                  value: _bank,
                  theme: theme,
                  onEdit: _editBank,
                ),
                _row(
                  context,
                  icon: Icons.handshake_outlined,
                  label: tr(context, 'money_lent_out'),
                  value: _lent,
                  theme: theme,
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(context, 'money_total'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(total),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.today_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(context, 'money_daily_avg'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        '${formatMoney(dailyAvg)}${tr(context, 'per_day')}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required ThemeData theme,
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            formatMoney(value),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
