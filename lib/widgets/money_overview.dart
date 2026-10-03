import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/cash_entry.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// Wallet ids for the money overview (besides hand cash + lent).
const _walletIds = ['bkash', 'nagad', 'rocket', 'upay', 'card', 'bank'];

/// Brand-ish colors for mobile banking wallets.
const _walletColors = {
  'bkash': Color(0xFFE2136E), // bKash pink
  'nagad': Color(0xFFF6921E), // Nagad orange
  'rocket': Color(0xFF8C3494), // Rocket purple
  'upay': Color(0xFF00A651), // Upay green
  'card': Color(0xFF2563EB), // card blue
  'bank': Color(0xFF0E7C5B), // bank green
};

/// "My Money" overview: hand cash + mobile banking (bKash/Nagad/Rocket/Upay)
/// + card + other bank + lent out = total assets, plus daily average.
/// Shown on home.
class MoneyOverviewCard extends StatefulWidget {
  const MoneyOverviewCard({super.key});

  @override
  State<MoneyOverviewCard> createState() => _MoneyOverviewCardState();
}

class _MoneyOverviewCardState extends State<MoneyOverviewCard> {
  double _cash = 0;
  Map<String, double> _wallets = {};
  double _lent = 0;
  bool _loading = true;
  bool _mobileExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, double>> _readWallets() async {
    final db = DatabaseHelper.instance;
    final out = {for (final id in _walletIds) id: 0.0};
    try {
      final raw = await db.getSetting('wallet_balances');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final id in _walletIds) {
          final v = map[id];
          if (v is num) out[id] = v.toDouble();
        }
      } else {
        // Migrate the old single bank_balance value.
        final old = await db.getSetting('bank_balance');
        final v = double.tryParse(old ?? '');
        if (v != null) out['bank'] = v;
      }
    } catch (_) {}
    return out;
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final cash = await db.getCashBalance();
      final wallets = await _readWallets();
      final debts = await db.getDebts();
      final lent = debts
          .where((d) => d.kind == 'lent' && !d.settled)
          .fold<double>(0, (s, d) => s + d.amount);
      if (mounted) {
        setState(() {
          _cash = cash;
          _wallets = wallets;
          _lent = lent;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editWallet(String id, String label) async {
    final current = _wallets[id] ?? 0;
    final ctrl = TextEditingController(
      text: current.truncateToDouble() == current
          ? current.toStringAsFixed(0)
          : current.toString(),
    );
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(label),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr(dctx, 'wallet_balance_hint'),
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
    final updated = Map<String, double>.from(_wallets)..[id] = value;
    await DatabaseHelper.instance
        .setSetting('wallet_balances', jsonEncode(updated));
    _load();
  }

  Future<void> _editCash(BuildContext context, double current) async {
    final ctrl = TextEditingController(
      text: current.truncateToDouble() == current
          ? current.toStringAsFixed(0)
          : current.toString(),
    );
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'cash_set_balance')),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr(dctx, 'cash_new_balance'),
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
    if (value == null) return;
    if (!mounted) return;
    final diff = value - current;
    if (diff.abs() < 0.005) return;
    final adjustNote = tr(context, 'cash_adjust');
    await DatabaseHelper.instance.insertCashEntry(CashEntry(
      id: CashEntry.newId(),
      amount: diff.abs(),
      type: diff > 0 ? 'in' : 'out',
      note: adjustNote,
      date: DateTime.now(),
    ));
    _load();
  }

  String _walletLabel(String id, String lang) {
    switch (id) {
      case 'bkash':
        return 'bKash';
      case 'nagad':
        return 'Nagad';
      case 'rocket':
        return 'Rocket';
      case 'upay':
        return 'Upay';
      case 'card':
        return tr(context, 'wallet_card');
      case 'bank':
        return tr(context, 'wallet_bank');
      default:
        return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final expenses = context.watch<ExpenseProvider>();

    final now = DateTime.now();

    final mobileTotal = ['bkash', 'nagad', 'rocket', 'upay']
        .fold<double>(0, (s, id) => s + (_wallets[id] ?? 0));
    final total =
        _cash + mobileTotal + (_wallets['card'] ?? 0) + (_wallets['bank'] ?? 0) + _lent;

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
                // Total assets at top.
                Text(
                  tr(context, 'money_total'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  formatMoney(total),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Divider(height: 20),
                // Hand cash (editable).
                _row(
                  context,
                  icon: Icons.wallet_outlined,
                  iconColor: kGold,
                  label: tr(context, 'cash_wallet'),
                  value: _cash,
                  theme: theme,
                  onEdit: () => _editCash(context, _cash),
                ),
                // Mobile banking group (expandable).
                InkWell(
                  onTap: () =>
                      setState(() => _mobileExpanded = !_mobileExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(Icons.smartphone_outlined,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(tr(context, 'wallet_mobile'))),
                        Text(
                          formatMoney(mobileTotal),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _mobileExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_mobileExpanded)
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Column(
                      children: [
                        for (final id in [
                          'bkash',
                          'nagad',
                          'rocket',
                          'upay'
                        ])
                          _row(
                            context,
                            icon: Icons.circle,
                            iconColor: _walletColors[id],
                            iconSize: 10,
                            label: _walletLabel(id, lang),
                            value: _wallets[id] ?? 0,
                            theme: theme,
                            onEdit: () =>
                                _editWallet(id, _walletLabel(id, lang)),
                          ),
                      ],
                    ),
                  ),
                // Card.
                _row(
                  context,
                  icon: Icons.credit_card_outlined,
                  iconColor: _walletColors['card'],
                  label: _walletLabel('card', lang),
                  value: _wallets['card'] ?? 0,
                  theme: theme,
                  onEdit: () =>
                      _editWallet('card', _walletLabel('card', lang)),
                ),
                // Other bank.
                _row(
                  context,
                  icon: Icons.account_balance_outlined,
                  iconColor: _walletColors['bank'],
                  label: _walletLabel('bank', lang),
                  value: _wallets['bank'] ?? 0,
                  theme: theme,
                  onEdit: () =>
                      _editWallet('bank', _walletLabel('bank', lang)),
                ),
                // Lent out.
                _row(
                  context,
                  icon: Icons.handshake_outlined,
                  label: tr(context, 'money_lent_out'),
                  value: _lent,
                  theme: theme,
                ),
                const Divider(height: 20),
                // Today / this week / this month spending.
                Row(
                  children: [
                    _spentStat(
                      context,
                      theme: theme,
                      label: tr(context, 'money_today'),
                      value: expenses.totalOn(now),
                    ),
                    _spentStat(
                      context,
                      theme: theme,
                      label: tr(context, 'money_week'),
                      value: expenses.totalThisWeek(),
                    ),
                    _spentStat(
                      context,
                      theme: theme,
                      label: tr(context, 'money_month'),
                      value: expenses.totalThisMonth(),
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

  Widget _row(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    double iconSize = 18,
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
              size: iconSize,
              color: iconColor ?? theme.colorScheme.onSurfaceVariant),
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

  Widget _spentStat(
    BuildContext context, {
    required ThemeData theme,
    required String label,
    required double value,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatMoney(value),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
