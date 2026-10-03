import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../services/currency_service.dart';
import '../widgets/motion.dart';

/// Tiny currency converter (Package AT).
///
/// Reuses [CurrencyService.rates] (BDT per 1 unit; live-cached when available,
/// bundled fallback otherwise). Conversion: amount / fromRate * toRate.
class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final TextEditingController _amountCtrl = TextEditingController();
  String _from = 'USD';
  String _to = 'BDT';

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  double get _converted {
    final rates = CurrencyService.rates;
    final fromRate = rates[_from] ?? 1.0;
    final toRate = rates[_to] ?? 1.0;
    if (fromRate <= 0) return 0;
    return _amount / fromRate * toRate;
  }

  String _fmt(double v) =>
      NumberFormat('#,##0.##', 'en_US').format(v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final gold = dark ? kGoldLight : kGoldDark;
    final symbol = CurrencyService.symbols[_to] ?? '';
    final result = _converted;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'conv_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StaggeredEntrance(
            child: TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: tr(context, 'conv_amount'),
                hintText: '0',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 16),
          StaggeredEntrance(
            delayMs: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _currencyField(
                    context,
                    tr(context, 'conv_from'),
                    _from,
                    (v) => setState(() => _from = v!),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                  child: IconButton(
                    tooltip: tr(context, 'conv_swap'),
                    onPressed: () => setState(() {
                      final tmp = _from;
                      _from = _to;
                      _to = tmp;
                    }),
                    icon: const Icon(Icons.swap_horiz),
                    color: gold,
                  ),
                ),
                Expanded(
                  child: _currencyField(
                    context,
                    tr(context, 'conv_to'),
                    _to,
                    (v) => setState(() => _to = v!),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          StaggeredEntrance(
            delayMs: 160,
            child: Column(
              children: [
                Text(
                  tr(context, 'conv_result').toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: gold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$symbol ${_fmt(result)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: gold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_from → $_to',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _currencyField(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    final codes = CurrencyService.supported;
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final code in codes)
          DropdownMenuItem(
            value: code,
            child: Text(
              '$code ${CurrencyService.symbols[code] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
