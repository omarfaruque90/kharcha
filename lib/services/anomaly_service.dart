import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/expense.dart';
import '../utils/formatters.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Anomaly detection (Package BE): flags a single expense that is unusually
/// large compared to its category's recent history.
///
/// A notification fires when the expense's BDT amount exceeds 3× the
/// category's 90-day average (the expense itself excluded). Needs at least
/// 5 historical samples in the window, otherwise stays silent.
///
/// Call [checkExpense] right after an expense is added (see expense_provider)
/// or at startup for the latest expense. Everything is wrapped in try/catch:
/// anomaly detection must never break the add-expense flow.
class AnomalyService {
  AnomalyService._();

  /// Minimum past samples in the window before a verdict is made.
  static const _minSamples = 5;

  /// Fire when the expense is more than this multiple of the average.
  static const _threshold = 3.0;

  /// Look-back window for the category average.
  static const _windowDays = 90;

  static Future<void> checkExpense(Expense e) async {
    try {
      final expenseId = e.id ?? '';

      // Cheap per-expense guard: never notify twice for the same expense.
      final prefs = await SharedPreferences.getInstance();
      final guardKey = 'last_anomaly_$expenseId';
      if (expenseId.isNotEmpty && prefs.getBool(guardKey) == true) return;

      final db = await DatabaseHelper.instance.database;
      final cutoff =
          DateTime.now().subtract(const Duration(days: _windowDays));

      // Single aggregate query: AVG + COUNT, excluding the new expense.
      // bdt_amount is null for pre-migration rows; COALESCE falls back to
      // the raw amount so historical data stays meaningful.
      Map<String, Object?> row;
      try {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS c, AVG(COALESCE(bdt_amount, amount)) AS a '
          'FROM expenses '
          'WHERE categoryId = ? AND date >= ? AND id != ?',
          [e.categoryId, cutoff.toIso8601String(), expenseId],
        );
        row = rows.first;
      } catch (_) {
        // Fallback for DBs missing the bdt_amount column.
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS c, AVG(amount) AS a '
          'FROM expenses '
          'WHERE categoryId = ? AND date >= ? AND id != ?',
          [e.categoryId, cutoff.toIso8601String(), expenseId],
        );
        row = rows.first;
      }

      final count = (row['c'] as num?)?.toInt() ?? 0;
      if (count < _minSamples) return;
      final avg = (row['a'] as num?)?.toDouble() ?? 0;
      if (avg <= 0) return;

      final amount = e.bdtAmount ?? e.amount;
      if (amount <= _threshold * avg) return;

      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final catName = AppStrings.categoryName(e.categoryId, lang);
      final title = AppStrings.get('anomaly_title', lang);
      final body = AppStrings.get('anomaly_body', lang)
          .replaceAll('{category}', catName)
          .replaceAll('{amount}', formatMoney(amount))
          .replaceAll('{avg}', formatMoney(avg));

      if (expenseId.isNotEmpty) {
        await prefs.setBool(guardKey, true);
      }

      // Log to the in-app center (fires the tray notification too via the
      // systemNotify hook wired in main.dart)...
      try {
        await NotificationCenter.push(
          title: title,
          body: body,
          type: 'anomaly',
        );
      } catch (_) {}
      // ...and fire the tray notification directly as well.
      try {
        await NotificationService.showNow(title: title, body: body);
      } catch (_) {}
    } catch (_) {
      // Anomaly detection is best-effort; never crash the caller.
    }
  }
}
