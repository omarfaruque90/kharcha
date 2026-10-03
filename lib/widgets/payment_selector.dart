import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/custom_payment.dart';
import '../providers/settings_provider.dart';

/// Hierarchical payment-method picker.
///
/// Level 1 chips: Cash | Mobile Banking | Card | Other.
/// Mobile Banking reveals level 2: bKash | Nagad | Rocket.
/// Other reveals a text field; previously used custom labels appear as
/// reusable suggestion chips.
///
/// Stored values: "cash", "card", "mobile_banking:bKash",
/// "mobile_banking:Nagad", "mobile_banking:Rocket", "other:<custom label>".
/// Legacy v3 value "bkash" is normalized to "mobile_banking:bKash".
///
/// Custom labels are NOT upserted here — the parent screen upserts them on
/// save (via upsertCustomPaymentByLabel) so usage counts stay accurate.
class PaymentSelector extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const PaymentSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<PaymentSelector> createState() => _PaymentSelectorState();
}

const List<String> _level1Methods = ['cash', 'mobile_banking', 'card', 'other'];
const List<String> _mobileMethods = ['bKash', 'Nagad', 'Rocket'];

class _PaymentSelectorState extends State<PaymentSelector> {
  late String _level1;
  String _mobile = 'bKash';
  late TextEditingController _customCtrl;
  late final Future<List<CustomPayment>> _recentFuture;

  @override
  void initState() {
    super.initState();
    _level1 = 'cash';
    _parse(widget.value);
    _customCtrl =
        TextEditingController(text: _customLabelOf(widget.value));
    _recentFuture = DatabaseHelper.instance.getMostUsedPayments(6);
  }

  static String _customLabelOf(String value) =>
      value.startsWith('other:') ? value.substring('other:'.length) : '';

  void _parse(String value) {
    final v = value == 'bkash' ? 'mobile_banking:bKash' : value;
    final parts = v.split(':');
    _level1 = _level1Methods.contains(parts[0]) ? parts[0] : 'cash';
    if (_level1 == 'mobile_banking') {
      _mobile = parts.length > 1 && _mobileMethods.contains(parts[1])
          ? parts[1]
          : 'bKash';
    }
  }

  @override
  void didUpdateWidget(PaymentSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      setState(() {
        _parse(widget.value);
        _customCtrl.text = _customLabelOf(widget.value);
      });
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  String _compose() {
    switch (_level1) {
      case 'mobile_banking':
        return 'mobile_banking:$_mobile';
      case 'other':
        final t = _customCtrl.text.trim();
        return t.isEmpty ? 'other' : 'other:$t';
      default:
        return _level1;
    }
  }

  String _mobileLabel(String method, String lang) {
    switch (method) {
      case 'Nagad':
        return AppStrings.get('pm_nagad', lang);
      case 'Rocket':
        return AppStrings.get('pm_rocket', lang);
      default:
        return AppStrings.paymentName('bkash', lang);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in _level1Methods)
              ChoiceChip(
                label: Text(AppStrings.paymentName(m, lang)),
                selected: _level1 == m,
                onSelected: (_) {
                  setState(() => _level1 = m);
                  widget.onChanged(_compose());
                },
              ),
          ],
        ),
        if (_level1 == 'mobile_banking') ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final m in _mobileMethods)
                ChoiceChip(
                  label: Text(_mobileLabel(m, lang)),
                  selected: _mobile == m,
                  onSelected: (_) {
                    setState(() => _mobile = m);
                    widget.onChanged(_compose());
                  },
                ),
            ],
          ),
        ],
        if (_level1 == 'other') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customCtrl,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: tr(context, 'payment_other_hint'),
              prefixIcon: const Icon(Icons.account_balance_outlined),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => widget.onChanged(_compose()),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<CustomPayment>>(
            future: _recentFuture,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <CustomPayment>[];
              if (items.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'payment_recent'),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in items)
                        ActionChip(
                          label: Text(p.label),
                          onPressed: () {
                            _customCtrl.text = p.label;
                            widget.onChanged(_compose());
                          },
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
