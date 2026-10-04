import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../providers/total_balance_provider.dart';
import '../utils/formatters.dart';
import 'motion.dart';

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
/// + card + other bank + lent out = total assets, plus today/week/month
/// spending. Reads from [TotalBalanceProvider] so the home hero agrees.
class MoneyOverviewCard extends StatefulWidget {
  const MoneyOverviewCard({super.key});

  @override
  State<MoneyOverviewCard> createState() => _MoneyOverviewCardState();
}

class _MoneyOverviewCardState extends State<MoneyOverviewCard> {
  bool _mobileExpanded = false;

  Future<double?> _askAmount(
      BuildContext context, String title, String hint, double current) async {
    final ctrl = TextEditingController(
      text: current.truncateToDouble() == current
          ? current.toStringAsFixed(0)
          : current.toString(),
    );
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: hint,
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
    return value;
  }

  String _walletLabel(BuildContext context, String id) {
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
    final theme = Theme.of(context);
    final tb = context.watch<TotalBalanceProvider>();

    final mobileTotal = ['bkash', 'nagad', 'rocket', 'upay']
        .fold<double>(0, (s, id) => s + tb.walletOf(id));

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
                    onPressed: () =>
                        context.read<TotalBalanceProvider>().refresh(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!tb.isLoaded)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ))
              else ...[
                const Divider(height: 8),
                // Hand cash (editable via ledger adjustment).
                _row(
                  context,
                  icon: Icons.wallet_outlined,
                  iconColor: kGold,
                  label: tr(context, 'cash_wallet'),
                  value: tb.cash,
                  theme: theme,
                  onEdit: () async {
                    final v = await _askAmount(
                      context,
                      tr(context, 'cash_set_balance'),
                      tr(context, 'cash_new_balance'),
                      tb.cash,
                    );
                    if (v != null && context.mounted) {
                      await context.read<TotalBalanceProvider>().setCash(v);
                    }
                  },
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
                            label: _walletLabel(context, id),
                            value: tb.walletOf(id),
                            theme: theme,
                            onEdit: () async {
                              final v = await _askAmount(
                                context,
                                _walletLabel(context, id),
                                tr(context, 'wallet_balance_hint'),
                                tb.walletOf(id),
                              );
                              if (v != null && context.mounted) {
                                await context
                                    .read<TotalBalanceProvider>()
                                    .setWallet(id, v);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                // Card.
                _row(
                  context,
                  icon: Icons.credit_card_outlined,
                  iconColor: _walletColors['card'],
                  label: _walletLabel(context, 'card'),
                  value: tb.walletOf('card'),
                  theme: theme,
                  onEdit: () async {
                    final v = await _askAmount(
                      context,
                      _walletLabel(context, 'card'),
                      tr(context, 'wallet_balance_hint'),
                      tb.walletOf('card'),
                    );
                    if (v != null && context.mounted) {
                      await context
                          .read<TotalBalanceProvider>()
                          .setWallet('card', v);
                    }
                  },
                ),
                // Other bank.
                _row(
                  context,
                  icon: Icons.account_balance_outlined,
                  iconColor: _walletColors['bank'],
                  label: _walletLabel(context, 'bank'),
                  value: tb.walletOf('bank'),
                  theme: theme,
                  onEdit: () async {
                    final v = await _askAmount(
                      context,
                      _walletLabel(context, 'bank'),
                      tr(context, 'wallet_balance_hint'),
                      tb.walletOf('bank'),
                    );
                    if (v != null && context.mounted) {
                      await context
                          .read<TotalBalanceProvider>()
                          .setWallet('bank', v);
                    }
                  },
                ),
                // Lent out (auto from debts).
                _row(
                  context,
                  icon: Icons.handshake_outlined,
                  label: tr(context, 'money_lent_out'),
                  value: tb.lentOut,
                  theme: theme,
                ),
                // Borrowed (auto from debts).
                _row(
                  context,
                  icon: Icons.call_received_outlined,
                  label: tr(context, 'money_borrowed'),
                  value: tb.borrowed,
                  theme: theme,
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
}
