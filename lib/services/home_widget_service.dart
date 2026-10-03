import 'package:home_widget/home_widget.dart';

import '../db/database_helper.dart';
import '../models/savings_goal.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';

/// Pushes Khorcha totals to the Android home widget.
///
/// The native [ExpenseWidgetProvider] reads these keys from shared prefs on
/// every update: 'khorcha_today', 'khorcha_month', 'khorcha_balance',
/// 'khorcha_debts', 'khorcha_goal'.
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
    String debts = '—',
    String goal = '—',
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>('khorcha_today', formatMoney(today));
      await HomeWidget.saveWidgetData<String>('khorcha_month', formatMoney(month));
      await HomeWidget.saveWidgetData<String>('khorcha_balance', formatMoney(balance));
      await HomeWidget.saveWidgetData<String>('khorcha_debts', debts);
      await HomeWidget.saveWidgetData<String>('khorcha_goal', goal);
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

  /// Derives today/month/balance/debts/goal from the live providers and
  /// the local database, then refreshes. Called on a debounce whenever
  /// either provider notifies.
  static Future<void> refreshFrom(
      ExpenseProvider expenses, MoneyProvider money) async {
    try {
      final now = DateTime.now();
      final today = expenses.totalOn(now);
      final month = expenses.totalThisMonth();
      final balance = money.incomeForMonth(monthKeyOf(now)) - month;
      final debts = await _debtsSummary();
      final goal = await _goalSummary();
      await refresh(
          today: today, month: month, balance: balance, debts: debts, goal: goal);
    } catch (_) {}
  }

  /// Net unsettled debt position: total lent minus total borrowed.
  /// Returns e.g. "৳500 পাবো" (user will receive), "৳200 দেবো" (user owes),
  /// "৳0" when settled out, or "—" on failure.
  static Future<String> _debtsSummary() async {
    try {
      final debts = await DatabaseHelper.instance.getDebts(settled: false);
      var net = 0.0;
      for (final d in debts) {
        net += d.kind == 'lent' ? d.amount : -d.amount;
      }
      if (net == 0) return formatMoney(0);
      final word = net > 0 ? 'পাবো' : 'দেবো';
      return '${formatMoney(net.abs())} $word';
    } catch (_) {
      return '—';
    }
  }

  /// Top savings goal by progress (saved/target). Returns e.g. "ভ্রমণ 45%",
  /// or "—" when there are no goals or the query fails.
  static Future<String> _goalSummary() async {
    try {
      final goals = await DatabaseHelper.instance.getAllSavingsGoals();
      if (goals.isEmpty) return '—';
      SavingsGoal? top;
      var best = -1.0;
      for (final g in goals) {
        final pct = g.targetAmount > 0 ? g.savedAmount / g.targetAmount : 0.0;
        if (pct > best) {
          best = pct;
          top = g;
        }
      }
      if (top == null) return '—';
      final pctInt = (best.clamp(0.0, 1.0) * 100).round();
      return '${top.title} $pctInt%';
    } catch (_) {
      return '—';
    }
  }

  /// Valid widget style values.
  static const List<String> widgetStyles = [
    'compact',
    'detailed',
    'minimal',
    'debts_goals',
  ];

  /// Persists the chosen home-widget style and asks the native widget to
  /// redraw with the matching layout. [style] must be one of [widgetStyles].
  /// Unknown values fall back to 'detailed' in the native provider.
  static Future<void> setStyle(String style) async {
    try {
      await HomeWidget.saveWidgetData<String>('widget_style', style);
      await HomeWidget.updateWidget(
        androidName: 'ExpenseWidgetProvider',
        qualifiedAndroidName: 'com.kharcha.app.ExpenseWidgetProvider',
      );
    } catch (e) {
      // Widget is best-effort: never let a widget failure break settings.
      // ignore: avoid_print
      print('HomeWidgetService.setStyle failed: $e');
    }
  }
}
