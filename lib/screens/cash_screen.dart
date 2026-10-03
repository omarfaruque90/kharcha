import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/cash_entry.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Package AL — Cash in hand (wallet).
///
/// Shows the current wallet balance (sum of the cash ledger) and the
/// movement history. "Add cash" inserts a type='in' entry; cash expenses
/// recorded through the add-expense flow auto-insert a type='out' entry —
/// that hook lives in ExpenseProvider (see wiring report), not here.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  double _balance = 0;
  List<CashEntry> _ledger = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final db = DatabaseHelper.instance;
    try {
      final balance = await db.getCashBalance();
      final ledger = await db.getCashLedger();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _ledger = ledger;
      });
    } catch (_) {
      // Balance stays at whatever was last loaded.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddCash() async {
    final result = await showDialog<_CashDialogResult>(
      context: context,
      builder: (_) => const _CashDialog(),
    );
    if (result == null) return;
    try {
      await DatabaseHelper.instance.insertCashEntry(CashEntry(
        id: CashEntry.newId(),
        amount: result.amount,
        type: 'in',
        date: DateTime.now(),
        note: result.note,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'tpl_failed'))),
        );
      }
      return;
    }
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cash_added'))),
      );
    }
  }

  /// Sets the wallet balance directly: inserts an adjustment entry
  /// for the difference between the current and the entered balance.
  Future<void> _openSetBalance() async {
    final ctrl = TextEditingController(
      text: _balance.truncateToDouble() == _balance
          ? _balance.toStringAsFixed(0)
          : _balance.toString(),
    );
    final formKey = GlobalKey<FormState>();
    final newBalance = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'cash_set_balance')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(dctx, 'cash_current')
                    .replaceAll('{amount}', formatMoney(_balance)),
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
                  labelText: tr(dctx, 'cash_new_balance'),
                  border: const OutlineInputBorder(),
                  prefixText: '৳ ',
                ),
                validator: (v) {
                  final d = double.tryParse((v ?? '').trim());
                  if (d == null || d < 0) {
                    return tr(dctx, 'cash_invalid');
                  }
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
    if (newBalance == null || !mounted) return;
    final diff = newBalance - _balance;
    if (diff.abs() < 0.005) return; // No change.
    try {
      await DatabaseHelper.instance.insertCashEntry(CashEntry(
        id: CashEntry.newId(),
        amount: diff.abs(),
        type: diff > 0 ? 'in' : 'out',
        date: DateTime.now(),
        note: tr(context, 'cash_adjust_note'),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'tpl_failed'))),
        );
      }
      return;
    }
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'cash_balance_set')
              .replaceAll('{amount}', formatMoney(newBalance))),
        ),
      );
    }
  }

  void _confirmDelete(CashEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'cash_delete_title')),
        content: Text(tr(ctx, 'delete_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              try {
                if (entry.id != null) {
                  await DatabaseHelper.instance.deleteCashEntry(entry.id!);
                }
                await _reload();
              } catch (_) {
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(tr(ctx, 'tpl_failed'))),
                  );
                }
                return;
              }
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
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'cash_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                // Index 0 = wallet header, 1 = history title, the rest are
                // the ledger rows (or a single empty-state row).
                itemCount: (_ledger.isEmpty ? 1 : _ledger.length) + 2,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: StaggeredEntrance(
                        child: Card(
                          color: isDark ? kDeepGreenCard : kDeepGreen,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.wallet_outlined,
                                        color: kGold, size: 28),
                                    const SizedBox(width: 12),
                                    Text(
                                      tr(context, 'cash_wallet'),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        color: kGoldLight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                      begin: 0, end: _balance),
                                  duration: const Duration(
                                      milliseconds: 700),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, _) => Text(
                                    formatMoney(value),
                                    style: theme
                                        .textTheme.headlineMedium
                                        ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                PressableScale(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: _openAddCash,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: kGold,
                                            foregroundColor:
                                                kDeepGreenDark,
                                          ),
                                          icon: const Icon(Icons.add),
                                          label: Text(
                                              tr(context, 'cash_add')),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _openSetBalance,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: kGold,
                                            side: const BorderSide(
                                                color: kGold),
                                          ),
                                          icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18),
                                          label: Text(tr(context,
                                              'cash_set_balance')),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  if (i == 1) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        tr(context, 'cash_history'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    );
                  }
                  if (_ledger.isEmpty) {
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(context, 'cash_no_entries'),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32),
                            child: Text(
                              tr(context, 'cash_no_entries_sub'),
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final e = _ledger[i - 2];
                  final isIn = e.type == 'in';
                  final signColor = isIn
                      ? const Color(0xFF10B981)
                      : Colors.redAccent;
                  return StaggeredEntrance(
                    key: ValueKey('cash-${e.id}'),
                    delayMs: ((i - 2) * 40).clamp(0, 200).toInt(),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: signColor.withValues(
                              alpha: 0.15),
                          child: Icon(
                            isIn
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: signColor,
                          ),
                        ),
                        title: Text(
                          '${isIn ? '+' : '−'}${formatMoney(e.amount)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          e.note.trim().isNotEmpty
                              ? e.note.trim()
                              : tr(context,
                                  isIn ? 'cash_in' : 'cash_out'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('d MMM, h:mm a')
                                  .format(e.date),
                              style: theme.textTheme.bodySmall,
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline),
                              onPressed: () => _confirmDelete(e),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CashDialogResult {
  final double amount;
  final String note;

  _CashDialogResult(this.amount, this.note);
}

/// Amount + note dialog for adding cash to the wallet.
class _CashDialog extends StatefulWidget {
  const _CashDialog();

  @override
  State<_CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends State<_CashDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'cash_add')),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: tr(context, 'note'),
                hintText: tr(context, 'note_hint'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(_CashDialogResult(
              double.parse(_amountCtrl.text.trim()),
              _noteCtrl.text.trim(),
            ));
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}
