import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// Periodic background update check.
///
/// Runs even when the app is closed (WorkManager, ~every 12h, only with
/// network). When a newer version is published in the public
/// kharcha-updates repo, the phone gets a direct system notification
/// telling the user to update. Tapping it opens the app, which then
/// shows the normal update dialog on startup.
///
/// NOTE: on MIUI/Xiaomi the user must allow "Autostart" for Khorcha,
/// otherwise the system kills background work.
class UpdateCheckWorker {
  static const String taskName = 'khorcha-update-check';
  static const String _versionJsonUrl =
      'https://raw.githubusercontent.com/omarfaruque90/kharcha-updates/main/version.json';
  static const String _notifiedKey = 'update_last_notified_tag';

  /// Schedules the periodic check. Safe to call on every app start —
  /// WorkManager keeps a single schedule for the unique name.
  static Future<void> schedule() async {
    try {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        'khorcha-update-check-unique',
        taskName,
        frequency: const Duration(hours: 12),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
      );
    } catch (_) {}
  }

  /// One-shot check right after scheduling (cheap, network-gated).
  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName('khorcha-update-check-unique');
    } catch (_) {}
  }
}

/// Must be top-level for the background isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == UpdateCheckWorker.taskName) {
      await _runUpdateCheck();
    }
    return Future.value(true);
  });
}

Future<void> _runUpdateCheck() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final pkg = await PackageInfo.fromPlatform();
    final local = _parseVersion(pkg.version);
    if (local == null) return;

    final resp = await http
        .get(Uri.parse(UpdateCheckWorker._versionJsonUrl))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return;
    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) return;

    final tag = (data['tag'] as String? ?? '').trim();
    final version = (data['version'] as String? ?? '').trim();
    if (tag.isEmpty || version.isEmpty) return;
    final remote = _parseVersion(version);
    if (remote == null || !_isNewer(remote, local)) return;

    // Don't nag twice for the same release.
    if (prefs.getString(UpdateCheckWorker._notifiedKey) == tag) return;
    await prefs.setString(UpdateCheckWorker._notifiedKey, tag);

    await _showUpdateNotification(version);
  } catch (_) {}
}

List<int>? _parseVersion(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(v.trim());
  if (m == null) return null;
  return [
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3) ?? '0'),
  ];
}

bool _isNewer(List<int> remote, List<int> local) {
  for (var i = 0; i < 3; i++) {
    if (remote[i] != local[i]) return remote[i] > local[i];
  }
  return false;
}

/// Local plugin instance for the background isolate — the main isolate's
/// NotificationService instance is not reachable from here.
Future<void> _showUpdateNotification(String version) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
    await plugin.show(
      9001,
      'Khorcha আপডেট এসেছে',
      'নতুন ভার্সন v$version এসেছে। আপডেট করতে এখানে ট্যাপ করো।',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'khorcha_updates',
          'Khorcha Updates',
          channelDescription: 'Notun app version ashle janiye dey',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'app_update',
    );
  } catch (_) {}
}
