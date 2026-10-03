import 'package:home_widget/home_widget.dart';

import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';

/// Pushes Khorcha totals to the Android home widget.
///
/// The native [ExpenseWidgetProvider] reads these keys from shared prefs on
/// every update: 'khorcha_today', 'khorcha_month', 'khorcha_balance'.
///
/// Call [refresh] whenever totals change — after an expense is added,
/// edited, deleted, or synced (see hook points in lib/providers/).
class HomeWidgetService {
  HomeWidgetService._();

  /// Saves the formatted totals and asks the native widget to redraw.
  static Future<void> refresh({
    required double today,
    required double month,
    required double balance,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>('khorcha_today', formatMoney(today));
      await HomeWidget.saveWidgetData<String>('khorcha_month', formatMoney(month));
      await HomeWidget.saveWidgetData<String>('khorcha_balance', formatMoney(balance));
      await HomeWidget.updateWidget(
        androidName: 'ExpenseWidgetProvider',
        qualifiedAndroidName: 'com.kharcha.app.ExpenseWidgetProvider',
      );
    } catch (e) {
      // Widget is best-effort: never let a widget failure break expense flows.
      // ignore: avoid_print
      print('HomeWidgetService.refresh failed: $e');
    }
  }

  /// Derives today/month/balance from the live providers and refreshes.
  /// Called on a debounce whenever either provider notifies.
  static Future<void> refreshFrom(
      ExpenseProvider expenses, MoneyProvider money) async {
    try {
      final now = DateTime.now();
      final today = expenses.totalOn(now);
      final month = expenses.totalThisMonth();
      final balance = money.incomeForMonth(monthKeyOf(now)) - month;
      await refresh(today: today, month: month, balance: balance);
    } catch (_) {}
  }
}
