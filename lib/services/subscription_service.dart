import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/app_subscription.dart';
import '../utils/formatters.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Subscription due checks (Package D).
///
/// [checkDue] is meant to be called on app start (the coordinator wires it
/// in). For every active subscription whose [AppSubscription.nextDue] is
/// within the next 3 days (overdue included), it fires one system
/// notification and logs one entry in the in-app notification center —
/// once per subscription per due date (tracked in shared_preferences).
/// Best-effort: any failure is swallowed so startup never breaks.
class SubscriptionService {
  SubscriptionService._();

  static Future<void> checkDue() async {
    try {
      final db = DatabaseHelper.instance;
      final lang = await db.getSetting('language') ?? 'bn';
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final prefs = await SharedPreferences.getInstance();
      final subs = await db.getSubscriptions();

      for (final AppSubscription s in subs) {
        if (!s.active || s.id == null) continue;
        final due = DateTime(s.nextDue.year, s.nextDue.month, s.nextDue.day);
        final days = due.difference(today).inDays;
        if (days > 3) continue;

        final dueKey =
            '${due.year.toString().padLeft(4, '0')}'
            '${due.month.toString().padLeft(2, '0')}'
            '${due.day.toString().padLeft(2, '0')}';
        final prefKey = 'sub_notified_${s.id}_$dueKey';
        if (prefs.getBool(prefKey) == true) continue;

        final amount = formatMoney(s.amount);
        final title = AppStrings.get('notif_subs_title', lang);
        String body;
        if (days < 0) {
          body = AppStrings.get('notif_subs_body_overdue', lang)
              .replaceAll('{name}', s.name)
              .replaceAll('{amount}', amount)
              .replaceAll('{n}', '${-days}');
        } else {
          body = AppStrings.get('notif_subs_body', lang)
              .replaceAll('{name}', s.name)
              .replaceAll('{amount}', amount)
              .replaceAll('{n}', '$days');
        }

        await NotificationService.showNow(title: title, body: body);
        await NotificationCenter.push(
          title: title,
          body: body,
          type: 'subscription',
          dedupeKey: 'subscription:${s.id}:$dueKey',
        );
        await prefs.setBool(prefKey, true);
      }
    } catch (_) {
      // Due checks must never crash the caller.
    }
  }
}
