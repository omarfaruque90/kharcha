import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Discount calculator tool: original price + discount % → final price + savings.
class DiscountToolScreen extends StatefulWidget {
  const DiscountToolScreen({super.key});

  @override
  State<DiscountToolScreen> createState() => _DiscountToolScreenState();
}

class _DiscountToolScreenState extends State<DiscountToolScreen> {
  final _priceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  double _finalPrice = 0;
  double _savings = 0;
  bool _calculated = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final discount = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    if (price <= 0 || discount < 0 || discount > 100) {
      setState(() => _calculated = false);
      return;
    }
    setState(() {
      _savings = price * discount / 100;
      _finalPrice = price - _savings;
      _calculated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'discount_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StaggeredEntrance(
            child: TextField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(context, 'discount_price'),
                prefixText: '৳ ',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _calculate(),
            ),
          ),
          const SizedBox(height: 16),
          StaggeredEntrance(
            delayMs: 60,
            child: TextField(
              controller: _discountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(context, 'discount_percent'),
                suffixText: '%',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _calculate(),
            ),
          ),
          const SizedBox(height: 24),
          if (_calculated) ...[
            StaggeredEntrance(
              delayMs: 120,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _resultRow(
                        context,
                        tr(context, 'discount_final'),
                        formatMoney(_finalPrice),
                        theme.colorScheme.primary,
                        true,
                      ),
                      const Divider(height: 24),
                      _resultRow(
                        context,
                        tr(context, 'discount_savings'),
                        formatMoney(_savings),
                        Colors.green,
                        false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(BuildContext context, String label, String value,
      Color color, bool big) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
