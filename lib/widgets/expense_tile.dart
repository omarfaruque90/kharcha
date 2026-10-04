import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/add_expense_screen.dart';
import '../services/currency_service.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// One row in the expense list. iOS mail-style row: category icon in a
/// rounded tinted square, 15px semibold title, 13px secondary subtitle,
/// 16px semibold amount right-aligned. Tap to edit, swipe left to delete.
class ExpenseTile extends StatelessWidget {
  final Expense expense;

  const ExpenseTile({super.key, required this.expense});

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_title')),
        content: Text(tr(ctx, 'delete_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final cat = categoryById(expense.categoryId);
    final custom = CustomCategoryRegistry.byId(expense.categoryId);
    final theme = Theme.of(context);
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(expense.date);
    final subtitle = StringBuffer(
      '${AppStrings.paymentName(expense.paymentMethod, lang)} • $dateLabel',
    );
    if (expense.note.isNotEmpty) {
      subtitle.write('\n${expense.note}');
    }

    return Dismissible(
      key: ValueKey('expense-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        final id = expense.id;
        if (id == null) return;
        context.read<ExpenseProvider>().remove(id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('msg_deleted', lang))),
        );
      },
      child: PressableScale(
        pressedScale: 0.98,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          minVerticalPadding: 2,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: custom != null && custom.emoji.isNotEmpty
                ? Text(custom.emoji, style: const TextStyle(fontSize: 20))
                : Icon(cat.icon, color: cat.color, size: 20),
          ),
          title: Text(
            CustomCategoryRegistry.displayName(expense.categoryId, lang),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            subtitle.toString(),
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(expense.bdtAmount ?? expense.amount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: theme.colorScheme.primary,
                ),
              ),
              // Package V: original amount in the entry currency.
              if (expense.currency != 'BDT')
                Text(
                  '(${CurrencyService.symbols[expense.currency] ?? expense.currency}${_trimOriginal(expense.amount)})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddExpenseScreen(expense: expense),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Compact display of a non-BDT original amount: 10 → "10", 10.5 → "10.5".
String _trimOriginal(double value) {
  final whole = value.truncateToDouble() == value;
  return whole ? value.toStringAsFixed(0) : value.toString();
}
