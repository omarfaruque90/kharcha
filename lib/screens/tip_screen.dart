import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Tiny tip calculator (Package AU): bill amount, tip % slider (0–30),
/// split stepper (1–20); shows tip, total and per-person — big and gold.
class TipScreen extends StatefulWidget {
  const TipScreen({super.key});

  @override
  State<TipScreen> createState() => _TipScreenState();
}

class _TipScreenState extends State<TipScreen> {
  final TextEditingController _billCtrl = TextEditingController();
  double _percent = 10;
  int _people = 1;

  @override
  void dispose() {
    _billCtrl.dispose();
    super.dispose();
  }

  double get _bill => double.tryParse(_billCtrl.text.trim()) ?? 0;
  double get _tip => _bill * _percent / 100;
  double get _total => _bill + _tip;
  double get _perPerson => _people > 0 ? _total / _people : 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final gold = dark ? kGoldLight : kGoldDark;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'tip_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StaggeredEntrance(
            child: TextField(
              controller: _billCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: tr(context, 'tip_bill'),
                prefixText: '৳ ',
                prefixStyle: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 24),
          StaggeredEntrance(
            delayMs: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tr(context, 'tip_rate').replaceAll(
                        '{p}',
                        _percent.toStringAsFixed(
                            _percent.truncateToDouble() == _percent ? 0 : 1),
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      formatMoney(_tip),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: gold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _percent,
                  min: 0,
                  max: 30,
                  divisions: 60,
                  activeColor: gold,
                  label:
                      '${_percent.toStringAsFixed(_percent.truncateToDouble() == _percent ? 0 : 1)}%',
                  onChanged: (v) => setState(() => _percent = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            delayMs: 140,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'tip_people'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _people > 1
                      ? () => setState(() => _people--)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$_people',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: gold,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _people < 20
                      ? () => setState(() => _people++)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          StaggeredEntrance(
            delayMs: 200,
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    _resultRow(
                      context,
                      tr(context, 'tip_tip_amount'),
                      formatMoney(_tip),
                      theme,
                      gold,
                      big: false,
                    ),
                    const SizedBox(height: 10),
                    _resultRow(
                      context,
                      tr(context, 'tip_total'),
                      formatMoney(_total),
                      theme,
                      gold,
                      big: true,
                    ),
                    if (_people > 1) ...[
                      const Divider(height: 28),
                      _resultRow(
                        context,
                        tr(context, 'tip_per_person'),
                        formatMoney(_perPerson),
                        theme,
                        gold,
                        big: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(
    BuildContext context,
    String label,
    String value,
    ThemeData theme,
    Color gold, {
    required bool big,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: (big
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.titleLarge)
              ?.copyWith(
            fontWeight: FontWeight.w800,
            color: gold,
          ),
        ),
      ],
    );
  }
}
