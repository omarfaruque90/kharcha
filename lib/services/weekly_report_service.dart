import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/custom_category.dart';
import '../utils/formatters.dart';
import 'notification_center.dart';

/// Weekly auto-report: summarizes LAST week's spending (total + top
/// category + % delta vs the week before), shown once per calendar week.
///
/// Weeks run Monday..Sunday. The prefs key 'last_weekly_report' stores the
/// date (yyyy-MM-dd) of the current week's Monday; once a new Monday is
/// seen, last week's numbers are computed and the key is updated.
/// Sends nothing if last week had no expenses (the prefs flag is still
/// updated so the check is not repeated). Can run from the app or from
/// the WorkManager background task — must never throw.
class WeeklyReportService {
  WeeklyReportService._();

  static const _prefsKey = 'last_weekly_report';

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<void> maybeSend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Monday of the current week.
      final thisMonday = today.subtract(Duration(days: today.weekday - 1));
      final weekKey = _dayKey(thisMonday);
      if (prefs.getString(_prefsKey) == weekKey) return;

      final lastMonday = thisMonday.subtract(const Duration(days: 7));
      final prevMonday = lastMonday.subtract(const Duration(days: 7));

      bool inRange(DateTime d, DateTime from, DateTime to) =>
          !d.isBefore(from) && d.isBefore(to);

      final expenses = await DatabaseHelper.instance.getAllExpenses();
      final lastWeek = expenses
          .where((e) => inRange(e.date, lastMonday, thisMonday))
          .toList();
      final lastTotal = lastWeek.fold<double>(
          0, (sum, e) => sum + (e.bdtAmount ?? e.amount));
      if (lastTotal <= 0) {
        await prefs.setString(_prefsKey, weekKey);
        return;
      }

      final sums = <String, double>{};
      for (final e in lastWeek) {
        sums[e.categoryId] =
            (sums[e.categoryId] ?? 0) + (e.bdtAmount ?? e.amount);
      }
      String topId = '';
      double topSum = -1;
      sums.forEach((id, sum) {
        if (sum > topSum) {
          topSum = sum;
          topId = id;
        }
      });

      final prevTotal = expenses
          .where((e) => inRange(e.date, prevMonday, lastMonday))
          .fold<double>(0, (sum, e) => sum + (e.bdtAmount ?? e.amount));

      String? deltaText;
      if (prevTotal > 0) {
        final pct = ((lastTotal - prevTotal) / prevTotal * 100).round();
        deltaText = '${pct >= 0 ? '+' : ''}$pct%';
      }

      final lang = await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      // Same resolver as monthly_report_service / reports_screen.dart:
      // custom category names with emoji fall back to the localized
      // built-in name.
      final topCat = CustomCategoryRegistry.displayName(topId, lang);
      final title = lang == 'bn' ? '📊 সাপ্তাহিক রিপোর্ট' : '📊 Weekly report';
      final body = lang == 'bn'
          ? 'গত সপ্তাহ: ${formatMoney(lastTotal)} · টপ: $topCat'
              '${deltaText != null ? ' ($deltaText আগের সপ্তাহের তুলনায়)' : ''}'
          : 'Last week: ${formatMoney(lastTotal)} · top: $topCat'
              '${deltaText != null ? ' ($deltaText vs prior week)' : ''}';

      try {
        // push() logs to the in-app center AND fires the tray notification
        // via NotificationCenter.systemNotify (wired to
        // NotificationService.showNow in main.dart). Note: in the
        // WorkManager background isolate systemNotify is NOT wired, so a
        // background-triggered report only lands in the in-app center —
        // see the wiring note in the report.
        await NotificationCenter.push(
          title: title,
          body: body,
          type: 'report',
          dedupeKey: 'weekly_report_$weekKey',
        );
      } catch (_) {}

      await prefs.setString(_prefsKey, weekKey);
    } catch (_) {
      // Must never crash startup / the background worker.
    }
  }
}
