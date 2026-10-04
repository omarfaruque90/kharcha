import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../providers/total_balance_provider.dart';
import '../theme/design_tokens.dart';
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
    final secondary = KIOS.secondaryText(context);
    const walletIds = ['bkash', 'nagad', 'rocket', 'upay'];

    return StaggeredEntrance(
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // iOS section header: 20px semibold.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'money_overview'),
                      style: KIOS.sectionTitle(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined, size: 20),
                    color: secondary,
                    tooltip: tr(context, 'refresh'),
                    onPressed: () =>
                        context.read<TotalBalanceProvider>().refresh(),
                  ),
                ],
              ),
            ),
            if (!tb.isLoaded)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else ...[
              _hairline(context),
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
              _hairline(context),
              // Mobile banking group (expandable).
              InkWell(
                onTap: () =>
                    setState(() => _mobileExpanded = !_mobileExpanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.smartphone_outlined,
                          size: 20, color: secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr(context, 'wallet_mobile'),
                          style: KIOS.rowLabel(context),
                        ),
                      ),
                      Text(
                        formatMoney(mobileTotal),
                        style: KIOS.rowLabel(context),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _mobileExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: secondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_mobileExpanded)
                for (var i = 0; i < walletIds.length; i++) ...[
                  // 30 (indent) + 10 (dot) + 12 (gap) = 52, aligned
                  // with the other row dividers.
                  _hairline(context, indent: 22),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: _row(
                      context,
                      icon: Icons.circle,
                      iconColor: _walletColors[walletIds[i]],
                      iconSize: 10,
                      label: _walletLabel(context, walletIds[i]),
                      value: tb.walletOf(walletIds[i]),
                      theme: theme,
                      padding:
                          const EdgeInsets.fromLTRB(0, 10, 16, 10),
                      onEdit: () async {
                        final v = await _askAmount(
                          context,
                          _walletLabel(context, walletIds[i]),
                          tr(context, 'wallet_balance_hint'),
                          tb.walletOf(walletIds[i]),
                        );
                        if (v != null && context.mounted) {
                          await context
                              .read<TotalBalanceProvider>()
                              .setWallet(walletIds[i], v);
                        }
                      },
                    ),
                  ),
                ],
              _hairline(context),
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
              _hairline(context),
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
              _hairline(context),
              // Lent out (auto from debts).
              _row(
                context,
                icon: Icons.handshake_outlined,
                label: tr(context, 'money_lent_out'),
                value: tb.lentOut,
                theme: theme,
              ),
              _hairline(context),
              // Borrowed (auto from debts).
              _row(
                context,
                icon: Icons.call_received_outlined,
                label: tr(context, 'money_borrowed'),
                value: tb.borrowed,
                theme: theme,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  /// iOS hairline divider between grouped rows.
  Widget _hairline(BuildContext context, {double indent = 52}) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      color: KIOS.separator(context),
    );
  }

  /// iOS grouped list row: 20px icon, 15px semibold label and value.
  Widget _row(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    double iconSize = 20,
    required String label,
    required double value,
    required ThemeData theme,
    EdgeInsetsGeometry padding =
        const EdgeInsets.fromLTRB(16, 12, 16, 12),
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Icon(icon,
              size: iconSize,
              color: iconColor ?? KIOS.secondaryText(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: KIOS.rowLabel(context)),
          ),
          Text(
            formatMoney(value),
            style: KIOS.rowLabel(context),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
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
