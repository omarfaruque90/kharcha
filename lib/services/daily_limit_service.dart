import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../providers/expense_provider.dart';
import '../utils/formatters.dart';
import 'notification_center.dart';

/// Daily spending-limit alarm.
///
/// The limit is stored in settings under 'daily_limit' (plain string,
/// parsed to double; missing/0/negative = disabled). Call [check] after
/// the expense list finishes loading on startup and again after each new
/// expense is saved.
///
/// Alerts fire at most once per calendar day — the prefs key
/// 'last_limit_alert' holds the yyyy-MM-dd of the last fired alert.
/// Must never throw: it runs on the startup path and on expense save.
class DailyLimitService {
  DailyLimitService._();

  static const _settingKey = 'daily_limit';
  static const _alertKey = 'last_limit_alert';

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<void> check(ExpenseProvider expenses) async {
    try {
      final raw = await DatabaseHelper.instance.getSetting(_settingKey);
      final limit = double.tryParse((raw ?? '').trim()) ?? 0;
      if (limit <= 0) return;

      final prefs = await SharedPreferences.getInstance();
      final todayKey = _dayKey(DateTime.now());
      if (prefs.getString(_alertKey) == todayKey) return;

      double total = 0;
      for (final e in expenses.expenses) {
        if (_dayKey(e.date) == todayKey) {
          total += e.bdtAmount ?? e.amount;
        }
      }
      if (total <= limit) return;

      final lang = await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final title = lang == 'bn'
          ? '⚠️ দৈনিক লিমিট পার হয়ে গেছে!'
          : '⚠️ Daily limit crossed!';
      final body = lang == 'bn'
          ? 'আজ: ${formatMoney(total)} / লিমিট ${formatMoney(limit)}'
          : 'Today: ${formatMoney(total)} / limit ${formatMoney(limit)}';

      try {
        // push() logs to the in-app center AND fires the tray notification
        // via NotificationCenter.systemNotify (wired to
        // NotificationService.showNow in main.dart) — no separate showNow
        // call here, or the phone would get two tray notifications.
        await NotificationCenter.push(
          title: title,
          body: body,
          type: 'alert',
          dedupeKey: 'daily_limit_$todayKey',
        );
      } catch (_) {}

      await prefs.setString(_alertKey, todayKey);
    } catch (_) {
      // Must never crash startup or expense save.
    }
  }
}
