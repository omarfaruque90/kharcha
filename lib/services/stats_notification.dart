import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../utils/formatters.dart';
import 'quick_add_notification.dart';

/// Package BQ — persistent daily/monthly spend stats notification.
///
/// Shows ONE ongoing (pinned), LOW-priority, silent notification:
///   "আজ ৳350 • এই মাস ৳12,400"   (bn)
///   "Today ৳350 • Month ৳12,400"   (en)
/// Fixed id 9004 (9001 = update check, 9002/9003 = quick-add).
/// Tap payload: 'open_app' — the coordinator routes it like any other
/// open-app tap.
///
/// DESIGN DECISIONS (read before wiring):
/// - refresh() reads the totals from [DatabaseHelper] itself via two
///   aggregate queries (today + current month). Callers just call
///   StatsNotification.refresh() — no totals to pass around.
/// - Own [FlutterLocalNotificationsPlugin] instance (like
///   quick_add_notification.dart and the update-check worker), because
///   NotificationService._plugin is private and showNow() has no ongoing
///   support. The WorkManager background isolate needs its own instance
///   anyway, since isolates can't share plugin instances.
/// - Native-side caveat: the notification-response callback that was
///   registered LAST wins on Android. At startup, call init() AFTER
///   NotificationService.init() and after QuickAddNotification's init.
///   This init's callback forwards EVERY response (including actionIds)
///   to [QuickAddNotification.routeResponse], which handles quick-add
///   action buttons and forwards all other taps via
///   [QuickAddNotification.onBodyTap] (the coordinator wires that to
///   NotificationService.onTap).
/// - Default state is ENABLED (setting key 'stats_notif' defaults to '1'
///   when unset). setEnabled(false) persists '0' and cancels the
///   notification; refresh() also cancels when disabled, so a stale
///   notification can never linger.
class StatsNotification {
  StatsNotification._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Fixed id for the ongoing stats notification. NOTE: 9001 is already
  /// used by the update-check worker's one-shot notification and
  /// 9002/9003 by quick-add — do NOT reuse them.
  static const int notifId = 9004;
  static const String channelId = 'khorcha_stats';
  static const String _settingKey = 'stats_notif';

  /// Initializes the plugin + low-priority silent channel. Idempotent.
  /// Public so the coordinator can control init ORDER at startup
  /// (must run after NotificationService.init(), see class doc).
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(
        settings: initSettings,
        // Registered LAST at startup, so this wins natively. Forward the
        // full response (actionId included) to QuickAdd's router.
        onDidReceiveNotificationResponse: (resp) {
          QuickAddNotification.routeResponse(resp);
        },
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      const channel = AndroidNotificationChannel(
        channelId,
        'Khorcha Stats',
        description: 'Ongoing daily/monthly spend summary',
        importance: Importance.low,
      );
      await android?.createNotificationChannel(channel);
    } catch (_) {
      // Stats must never crash the caller.
    }
  }

  /// Re-reads today's + this month's expense totals and shows/updates
  /// the ongoing notification. No-op when disabled (also cancels any
  /// stale notification first). Best-effort: never throws.
  static Future<void> refresh() async {
    try {
      if (!await isEnabled()) {
        await cancel();
        return;
      }
      await init();
      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';

      final today = await _totalForToday();
      final month = await _totalForMonth();

      final title =
          AppStrings.get('stats_notif_title', lang) == 'stats_notif_title'
              ? (lang == 'bn' ? 'খরচের সারসংক্ষেপ' : 'Khorcha')
              : AppStrings.get('stats_notif_title', lang);

      var body = AppStrings.get('stats_notif_body', lang);
      if (!body.contains('{today}') || !body.contains('{month}')) {
        // tr keys not yet wired in app_strings.dart (coordinator owns that
        // file): fall back to the inline template so the feature works.
        body = lang == 'bn'
            ? 'আজ {today} • এই মাস {month}'
            : 'Today {today} • Month {month}';
      }
      body = body
          .replaceAll('{today}', formatMoney(today))
          .replaceAll('{month}', formatMoney(month));

      await _plugin.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Khorcha Stats',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            showWhen: false,
            playSound: false,
            enableVibration: false,
            onlyAlertOnce: true,
          ),
        ),
        payload: 'open_app',
      );
    } catch (_) {
      // Best-effort; never crash the caller.
    }
  }

  /// Enables/disables the persistent stats notification. Disabling also
  /// cancels the currently shown notification. Best-effort.
  static Future<void> setEnabled(bool enabled) async {
    try {
      await DatabaseHelper.instance
          .setSetting(_settingKey, enabled ? '1' : '0');
      if (!enabled) {
        await cancel();
      } else {
        await refresh();
      }
    } catch (_) {}
  }

  /// True when the setting is unset (default ON) or '1'.
  static Future<bool> isEnabled() async {
    try {
      final v = await DatabaseHelper.instance.getSetting(_settingKey);
      return v != '0';
    } catch (_) {
      return true;
    }
  }

  /// Cancels the ongoing stats notification, if any. Best-effort.
  static Future<void> cancel() async {
    try {
      await _plugin.cancel(id: notifId);
    } catch (_) {}
  }

  /// Sum of today's expenses (bdt_amount preferred, amount fallback).
  /// expenses.date is an ISO8601 local-time TEXT column, so lexicographic
  /// day-boundary ranges work without datetime parsing.
  static Future<double> _totalForToday() async {
    try {
      final now = DateTime.now();
      final start = _dayKey(now);
      final end = _dayKey(now.add(const Duration(days: 1)));
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery(
        'SELECT SUM(COALESCE(bdt_amount, amount)) AS t FROM expenses '
        'WHERE date >= ? AND date < ?',
        [start, end],
      );
      return (rows.first['t'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Sum of this calendar month's expenses.
  static Future<double> _totalForMonth() async {
    try {
      final now = DateTime.now();
      final start = _dayKey(DateTime(now.year, now.month, 1));
      final end = _dayKey(DateTime(now.year, now.month + 1, 1));
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery(
        'SELECT SUM(COALESCE(bdt_amount, amount)) AS t FROM expenses '
        'WHERE date >= ? AND date < ?',
        [start, end],
      );
      return (rows.first['t'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
