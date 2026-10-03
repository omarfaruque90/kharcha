import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../widgets/calculator_pad.dart';
import 'add_expense_screen.dart';

/// Calculator as a bottom sheet (opened from home). The result can be
/// sent straight to Add Expense.
class CalculatorSheet extends StatefulWidget {
  const CalculatorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CalculatorSheet(),
    );
  }

  @override
  State<CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<CalculatorSheet> {
  double? _result;

  String get _resultText {
    final r = _result;
    if (r == null) return '0';
    return r.truncateToDouble() == r
        ? r.toStringAsFixed(0)
        : r.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'calculator_title'),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _resultText,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CalculatorPad(
            onResult: (v) => setState(() => _result = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _result == null
                  ? null
                  : () {
                      final v = _result!;
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddExpenseScreen(
                            initialAmount: v.truncateToDouble() == v
                                ? v.toStringAsFixed(0)
                                : v.toString(),
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'calc_add_expense')),
            ),
          ),
        ],
      ),
    );
  }
}
