import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/app_notification.dart';

/// In-app notification center.
///
/// [push] persists the entry in SQLite (so it survives restarts and shows
/// in the Notifications screen) and, when wired, also fires a system
/// notification. The system hook is assigned in main.dart after
/// [NotificationService.init] completes — kept as a callback (instead of
/// a direct import) to avoid an import cycle between the two services.
class NotificationCenter {
  NotificationCenter._();

  /// Fires a system (tray) notification for a pushed entry. Set by main.dart.
  static Future<void> Function({
    required String title,
    required String body,
  })? systemNotify;

  /// Live unread count for the home-screen bell badge.
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static Future<void> refreshUnread() async {
    try {
      unreadCount.value =
          await DatabaseHelper.instance.unreadNotificationCount();
    } catch (_) {
      // Badge is best-effort; never crash the caller.
    }
  }

  /// Saves a notification and fires the system notification.
  /// When [dedupeKey] is given, at most one entry per (type, dedupeKey)
  /// is stored per day — repeat triggers are silently skipped.
  static Future<void> push({
    required String title,
    required String body,
    String type = 'info',
    String? dedupeKey,
  }) async {
    try {
      final db = DatabaseHelper.instance;
      if (dedupeKey != null && dedupeKey.isNotEmpty) {
        if (await db.hasNotificationToday(type, dedupeKey)) return;
      }
      await db.insertNotification(
        title: title,
        body: body,
        type: type,
        dedupe: dedupeKey,
      );
      await refreshUnread();
    } catch (_) {
      return;
    }
    try {
      await systemNotify?.call(title: title, body: body);
    } catch (_) {}
  }

  static Future<List<AppNotification>> list({int limit = 100}) async {
    return DatabaseHelper.instance.getNotifications(limit: limit);
  }

  static Future<void> markRead(int id) async {
    await DatabaseHelper.instance.markNotificationRead(id);
    await refreshUnread();
  }

  static Future<void> markAllRead() async {
    await DatabaseHelper.instance.markAllNotificationsRead();
    await refreshUnread();
  }

  static Future<void> clearAll() async {
    await DatabaseHelper.instance.clearNotifications();
    await refreshUnread();
  }
}
