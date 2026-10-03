import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../services/lock_service.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Package BC — Emergency fund vault.
///
/// The screen is biometric-gated: on open it asks for the device
/// biometric via [LockService.authenticateBiometric]. If authentication
/// fails (or the device has no biometrics), a locked state is shown with
/// a "try again" button — the vault amount and history stay hidden.
///
/// Add/Withdraw update the stored amount via
/// [DatabaseHelper.setEmergencyFund] and append a row to the ledger via
/// [DatabaseHelper.addEmergencyLedger] (id 'vault', type 'in'/'out').
///
/// REQUIRES (coordinator): DatabaseHelper.getEmergencyLedger() — see the
/// wiring report for the exact method to add.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  double _amount = 0;
  List<Map<String, dynamic>> _ledger = [];
  bool _loading = true;
  bool _unlocked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _gate());
  }

  Future<void> _reload() async {
    final db = DatabaseHelper.instance;
    try {
      final amount = await db.getEmergencyFund();
      final ledger = await db.getEmergencyLedger();
      if (!mounted) return;
      setState(() {
        _amount = amount;
        _ledger = ledger;
      });
    } catch (_) {
      // Keep whatever was last loaded.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Biometric gate. A failure (or cancellation) leaves [_unlocked] false
  /// and the locked state stays visible.
  Future<void> _gate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await LockService.instance.authenticateBiometric(
      tr(context, 'vault_unlock_reason'),
    );
    if (!mounted) return;
    setState(() {
      _unlocked = ok;
      _checking = false;
    });
  }

  Future<void> _openMove({required bool isAdd}) async {
    final result = await showDialog<_VaultDialogResult>(
      context: context,
      builder: (_) => _VaultDialog(
        isAdd: isAdd,
        currentAmount: _amount,
      ),
    );
    if (result == null) return;
    final db = DatabaseHelper.instance;
    // clamp() returns num; toDouble() keeps the double parameter type happy.
    final newAmount = isAdd
        ? _amount + result.amount
        : (_amount - result.amount).clamp(0.0, double.infinity).toDouble();
    try {
      await db.setEmergencyFund(newAmount);
      await db.addEmergencyLedger(
          'vault', result.amount, isAdd ? 'in' : 'out', result.reason);
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'tpl_failed'))),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                tr(context, isAdd ? 'vault_added' : 'vault_withdrawn'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'vault_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_unlocked
              ? _LockedView(
                  checking: _checking,
                  onRetry: _gate,
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    // Index 0 = vault card, 1 = history title, the rest are
                    // the ledger rows (or a single empty-state row).
                    itemCount: (_ledger.isEmpty ? 1 : _ledger.length) + 2,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _VaultCard(
                            amount: _amount,
                            onAdd: () => _openMove(isAdd: true),
                            onWithdraw: () =>
                                _openMove(isAdd: false),
                          ),
                        );
                      }
                      if (i == 1) {
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: 8),
                          child: Text(
                            tr(context, 'vault_history'),
                            style: theme.textTheme.titleSmall
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      if (_ledger.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history_outlined,
                                size: 48,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                tr(context, 'vault_no_history'),
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                        );
                      }
                      final row = _ledger[i - 2];
                      final isIn = row['type'] == 'in';
                      final signColor = isIn
                          ? const Color(0xFF10B981)
                          : Colors.redAccent;
                      final date =
                          DateTime.fromMillisecondsSinceEpoch(
                              (row['date'] as num?)?.toInt() ?? 0);
                      final note =
                          row['note']?.toString().trim() ?? '';
                      final amount =
                          (row['amount'] as num?)?.toDouble() ?? 0;
                      return StaggeredEntrance(
                        key: ValueKey(
                            'vault-${row['id']}-${i - 2}'),
                        delayMs:
                            ((i - 2) * 40).clamp(0, 200).toInt(),
                        child: Card(
                          margin: const EdgeInsets.only(
                              bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  signColor.withValues(
                                      alpha: 0.15),
                              child: Icon(
                                isIn
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: signColor,
                              ),
                            ),
                            title: Text(
                              '${isIn ? '+' : '−'}${formatMoney(amount)}',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.bold),
                            ),
                            subtitle: Text(
                              note.isNotEmpty
                                  ? note
                                  : tr(context, isIn ? 'vault_in' : 'vault_out'),
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              DateFormat('d MMM y, h:mm a')
                                  .format(date),
                              style:
                                  theme.textTheme.bodySmall,
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

/// Shown when biometric authentication fails or is unavailable.
class _LockedView extends StatelessWidget {
  final bool checking;
  final VoidCallback onRetry;

  const _LockedView({required this.checking, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: kGold.withValues(alpha: 0.15),
              child: const Icon(Icons.lock_outline,
                  size: 40, color: kGoldDark),
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'vault_locked'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'vault_locked_sub'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            PressableScale(
              child: FilledButton.icon(
                onPressed: checking ? null : onRetry,
                icon: checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(tr(context, 'vault_unlock_btn')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vault summary card with the current amount and Add / Withdraw actions.
class _VaultCard extends StatelessWidget {
  final double amount;
  final VoidCallback onAdd;
  final VoidCallback onWithdraw;

  const _VaultCard({
    required this.amount,
    required this.onAdd,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return StaggeredEntrance(
      child: Card(
        color: isDark ? kDeepGreenCard : kDeepGreen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_outlined,
                      color: kGold, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    tr(context, 'vault_title'),
                    style:
                        theme.textTheme.titleMedium?.copyWith(
                      color: kGoldLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TweenAnimationBuilder<double>(
                tween:
                    Tween<double>(begin: 0, end: amount),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  formatMoney(value),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PressableScale(
                      child: FilledButton.icon(
                        onPressed: onAdd,
                        style: FilledButton.styleFrom(
                          backgroundColor: kGold,
                          foregroundColor: kDeepGreenDark,
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(tr(context, 'vault_add')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PressableScale(
                      child: OutlinedButton.icon(
                        onPressed: amount > 0 ? onWithdraw : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kGoldLight,
                          side: const BorderSide(color: kGold),
                        ),
                        icon:
                            const Icon(Icons.remove),
                        label: Text(
                            tr(context, 'vault_withdraw')),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultDialogResult {
  final double amount;
  final String reason;

  _VaultDialogResult(this.amount, this.reason);
}

/// Amount + reason dialog for vault Add / Withdraw.
class _VaultDialog extends StatefulWidget {
  final bool isAdd;
  final double currentAmount;

  const _VaultDialog({
    required this.isAdd,
    required this.currentAmount,
  });

  @override
  State<_VaultDialog> createState() => _VaultDialogState();
}

class _VaultDialogState extends State<_VaultDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context,
          widget.isAdd ? 'vault_add_title' : 'vault_withdraw_title')),
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
                if (!widget.isAdd &&
                    n > widget.currentAmount) {
                  return tr(context, 'vault_err_over');
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonCtrl,
              decoration: InputDecoration(
                labelText: tr(context, 'note'),
                hintText: tr(context, 'vault_reason_hint'),
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
            Navigator.of(context).pop(_VaultDialogResult(
              double.parse(_amountCtrl.text.trim()),
              _reasonCtrl.text.trim(),
            ));
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}
