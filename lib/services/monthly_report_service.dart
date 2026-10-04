import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/custom_category.dart';
import '../utils/formatters.dart';
import 'notification_center.dart';

/// Sends the monthly auto-report: a summary of last month's spending,
/// shown once per calendar month on app start.
///
/// Sends nothing if last month had no expenses (the prefs flag is still
/// updated so the check is not repeated). Called from main.dart on app
/// start; the exact [MonthlyReportService.maybeSend] signature is part of
/// the cross-agent contract and must be kept.
class MonthlyReportService {
  MonthlyReportService._();

  static const _prefsKey = 'last_report_month';

  static const _monthNamesEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const _monthNamesBn = [
    'জানুয়ারি',
    'ফেব্রুয়ারি',
    'মার্চ',
    'এপ্রিল',
    'মে',
    'জুন',
    'জুলাই',
    'আগস্ট',
    'সেপ্টেম্বর',
    'অক্টোবর',
    'নভেম্বর',
    'ডিসেম্বর',
  ];

  static Future<void> maybeSend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final currentKey = '${now.year}-${now.month}';
      if (prefs.getString(_prefsKey) == currentKey) return;

      // Last month's range. DateTime rolls month 0 back to last December.
      final firstOfThisMonth = DateTime(now.year, now.month, 1);
      final lastMonth = DateTime(firstOfThisMonth.year,
          firstOfThisMonth.month - 1, 1);

      final expenses = await DatabaseHelper.instance.getAllExpenses();
      final inMonth = expenses
          .where((e) =>
              e.date.year == lastMonth.year && e.date.month == lastMonth.month)
          .toList();
      final total = inMonth.fold<double>(0, (sum, e) => sum + e.amount);
      if (total <= 0) {
        await prefs.setString(_prefsKey, currentKey);
        return;
      }

      final sums = <String, double>{};
      for (final e in inMonth) {
        sums[e.categoryId] = (sums[e.categoryId] ?? 0) + e.amount;
      }
      String topId = '';
      double topSum = -1;
      sums.forEach((id, sum) {
        if (sum > topSum) {
          topSum = sum;
          topId = id;
        }
      });

      final lang = await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final monthIdx = lastMonth.month - 1;
      final monthName = lang == 'bn'
          ? _monthNamesBn[monthIdx]
          : _monthNamesEn[monthIdx];
      // Same resolver as reports_screen.dart: custom category names with
      // emoji fall back to the localized built-in name.
      final topCat = CustomCategoryRegistry.displayName(topId, lang);

      final title = AppStrings.get('monthly_report_title', lang);
      final body = AppStrings.get('monthly_report_body', lang)
          .replaceAll('{month}', monthName)
          .replaceAll('{total}', formatMoney(total))
          .replaceAll('{top}', topCat);

      try {
        // push() logs to the in-app center AND fires the tray notification
        // via NotificationCenter.systemNotify (wired to
        // NotificationService.showNow in main.dart).
        await NotificationCenter.push(
          title: title,
          body: body,
          type: 'report',
          dedupeKey: 'monthly_report_$currentKey',
        );
      } catch (_) {}

      await prefs.setString(_prefsKey, currentKey);
    } catch (_) {
      // Must never crash startup.
    }
  }
}
