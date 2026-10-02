import '../db/database_helper.dart';
import '../models/expense.dart';
import '../providers/money_provider.dart';

/// Auto-generates real expenses from active recurring templates, once per
/// calendar month.
///
/// Called from main.dart on app start; the exact
/// [RecurringService.processDue] signature is part of the cross-agent
/// contract and must be kept.
class RecurringService {
  /// For every active template whose [lastAddedMonth] is not the current
  /// month and whose day-of-month has arrived (or passed): inserts a real
  /// expense and stamps the template with the current month key.
  static Future<void> processDue() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final currentKey = monthKeyOf(now);
    final active = await db.getActiveRecurringExpenses();
    for (final template in active) {
      if (template.lastAddedMonth == currentKey) continue;
      if (template.dayOfMonth > now.day) continue;

      // Clamp the day for short months (e.g. Feb 30 -> Feb 28/29).
      final lastDayOfMonth = DateTime(now.year, now.month + 1, 0).day;
      final day = template.dayOfMonth > lastDayOfMonth
          ? lastDayOfMonth
          : template.dayOfMonth;

      final label = template.label.trim();
      final note = label.isEmpty
          ? template.note
          : '🔁 $label${template.note.trim().isEmpty ? '' : ' — ${template.note.trim()}'}';

      await db.insertExpense(Expense(
        amount: template.amount,
        categoryId: template.categoryId,
        date: DateTime(now.year, now.month, day),
        note: note,
        paymentMethod: template.paymentMethod,
      ));
      await db.updateRecurringExpense(
        template.copyWith(lastAddedMonth: currentKey),
      );
    }
  }
}
