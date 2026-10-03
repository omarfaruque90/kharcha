import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import 'notification_center.dart';

/// Bill-reminder notifications (v4 system features).
///
/// Schedules a monthly 9:00 AM local-time notification for every active
/// bill reminder, using timezone-aware scheduling so daylight/zone changes
/// don't shift the fire time.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _channelId = 'bill_reminders';
  static const String _alertsChannelId = 'kharcha_alerts';

  /// Must be called once at startup, before scheduling.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      tzdata.initializeTimeZones();
      try {
        final String zoneName =
            (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.setLocalLocation(tz.getLocation(zoneName));
      } catch (_) {
        // tz.local stays UTC — scheduling still works, just offset.
      }

      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(settings: initSettings);

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      const channel = AndroidNotificationChannel(
        _channelId,
        'Bill Reminders',
        description: 'Monthly bill reminder notifications',
        importance: Importance.high,
      );
      await android?.createNotificationChannel(channel);
      const alertsChannel = AndroidNotificationChannel(
        _alertsChannelId,
        'Khorcha Alerts',
        description: 'Budget warnings and expense alerts',
        importance: Importance.high,
      );
      await android?.createNotificationChannel(alertsChannel);
      // Runtime permission on Android 13+. Best-effort: denied means the
      // feature silently stays off.
      await android?.requestNotificationsPermission();
    } catch (_) {
      // Notifications must never crash startup.
    }
  }

  /// Fires an immediate high-priority notification. Used by the
  /// in-app notification center for budget warnings, recurring-expense
  /// alerts, etc. Best-effort: no-op before [init] or on failure.
  static Future<void> showNow({
    required String title,
    required String body,
  }) async {
    try {
      if (!_initialized) return;
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _alertsChannelId,
            'Khorcha Alerts',
            importance: Importance.high,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Re-schedules every active bill reminder for its next monthly fire
  /// time (dayOfMonth at 9:00 AM). Safe to call on every app start.
  static Future<void> scheduleBillReminders() async {
    try {
      final reminders =
          await DatabaseHelper.instance.getActiveBillReminders();
      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final now = tz.TZDateTime.now(tz.local);
      for (final r in reminders) {
        final id = (r.id ?? r.title).hashCode & 0x7fffffff;
        await _plugin.cancel(id: id);
        final day = _clampDay(r.dayOfMonth, now.year, now.month);
        var scheduled = tz.TZDateTime(tz.local, now.year, now.month, day, 9);
        if (!scheduled.isAfter(now)) {
          final next = DateTime(now.year, now.month + 1, 1);
          final nextDay = _clampDay(r.dayOfMonth, next.year, next.month);
          scheduled =
              tz.TZDateTime(tz.local, next.year, next.month, nextDay, 9);
        }
        final body = AppStrings.get('notif_bill_body', lang)
            .replaceAll('{title}', r.title)
            .replaceAll('{amount}', r.amount.toStringAsFixed(0));
        // A reminder due today also lands in the in-app notification
        // center (deduped per day) so the user sees it inside the app.
        final today = DateTime(now.year, now.month, now.day);
        if (scheduled.year == today.year &&
            scheduled.month == today.month &&
            scheduled.day == today.day) {
          await NotificationCenter.push(
            title: AppStrings.get('notif_bill_title', lang),
            body: body,
            type: 'bill_reminder',
            dedupeKey:
                '${r.id ?? r.title}:${today.toIso8601String().substring(0, 10)}',
          );
        }
        await _plugin.zonedSchedule(
          id: id,
          title: AppStrings.get('notif_bill_title', lang),
          body: body,
          scheduledDate: scheduled,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Bill Reminders',
              importance: Importance.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
        );
      }
    } catch (_) {
      // Best-effort; never crash the caller.
    }
  }

  /// Cancels all scheduled bill reminders (e.g. when the last one is
  /// deleted). The next app start re-schedules the rest anyway.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static int _clampDay(int day, int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day.clamp(1, lastDay).toInt();
  }
}
