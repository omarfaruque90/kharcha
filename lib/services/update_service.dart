import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';

/// Details of a newer GitHub release.
class UpdateInfo {
  final String tag;
  final String version;
  final String changelog;
  final String apkUrl;

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.changelog,
    required this.apkUrl,
  });
}

/// In-app update system (v4).
///
/// Checks `api.github.com/repos/omarfaruque90/kharcha/releases/latest`,
/// compares the release tag numerically (major.minor.patch, build number
/// ignored) against the installed version, and — on user approval —
/// downloads the release APK and hands it to the Android package installer.
///
/// Safety notes:
/// - Updating never signs the user out: Firebase Auth persists its session
///   in app-private storage that survives APK updates, and AuthGate only
///   reacts to `authStateChanges`. Nothing here touches auth state.
/// - No data is wiped: the APK ships the same debug keystore signature, so
///   Android treats it as an update (not a reinstall), and SQLite upgrades
///   only ever add tables/columns via `onUpgrade`.
class UpdateService {
  static const String _releasesUrl =
      'https://api.github.com/repos/omarfaruque90/kharcha/releases/latest';
  static const String _promptedKey = 'update_last_prompted_tag';

  /// Returns release info when a newer version exists, else null.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final local = _parseVersion(pkg.version);
      if (local == null) return null;
      final resp = await http
          .get(
            Uri.parse(_releasesUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) return null;

      final tag = (data['tag_name'] as String? ?? '').trim();
      final clean = tag.startsWith('v') ? tag.substring(1) : tag;
      final remote = _parseVersion(clean);
      if (remote == null || !_isNewer(remote, local)) return null;

      String? apkUrl;
      final assets = data['assets'];
      if (assets is List) {
        final apkAssets = <Map<String, String>>[];
        for (final a in assets) {
          if (a is Map) {
            final name = (a['name'] as String? ?? '').toLowerCase();
            final url = a['browser_download_url'] as String?;
            if (name.endsWith('.apk') && url != null && url.isNotEmpty) {
              apkAssets.add({'name': name, 'url': url});
            }
          }
        }
        apkUrl = await _pickApkForDevice(apkAssets);
      }
      if (apkUrl == null || apkUrl.isEmpty) return null;
      final body = (data['body'] as String? ?? '').trim();
      return UpdateInfo(
        tag: tag,
        version: clean,
        changelog: body,
        apkUrl: apkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the device's supported ABIs via the native channel.
  /// Empty list when the channel is unavailable (e.g. tests).
  static Future<List<String>> _deviceAbis() async {
    try {
      const channel = MethodChannel('com.kharcha.app/device');
      final abis =
          await channel.invokeMethod<List<dynamic>>('getSupportedAbis');
      return abis?.map((e) => e.toString()).toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Picks the smallest correct APK for this device from the release assets.
  /// Prefers a split-per-ABI build matching the device's ABIs; falls back to
  /// the first APK (universal build) when detection fails or nothing matches.
  static Future<String?> _pickApkForDevice(
      List<Map<String, String>> apkAssets) async {
    if (apkAssets.isEmpty) return null;
    final abis = await _deviceAbis();
    if (abis.isNotEmpty) {
      for (final abi in abis) {
        final needle = abi.toLowerCase();
        for (final a in apkAssets) {
          if (a['name']!.contains(needle)) return a['url'];
        }
      }
    }
    return apkAssets.first['url'];
  }

  /// Streams the APK to the cache dir, reporting 0..1 progress, then opens
  /// it so the system package installer takes over.
  static Future<void> downloadAndInstall(
    String apkUrl,
    void Function(double progress) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'kharcha-update.apk'));
    if (await file.exists()) await file.delete();
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request);
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }
      onProgress(1);
      await OpenFilex.open(file.path);
    } finally {
      client.close();
    }
  }

  /// Startup entry point: checks once; shows the update dialog unless this
  /// exact tag was already dismissed with "Later".
  static Future<void> maybePromptOnStartup(
      GlobalKey<NavigatorState> navKey) async {
    final info = await checkForUpdate();
    if (info == null) return;
    final prompted = await DatabaseHelper.instance.getSetting(_promptedKey);
    if (prompted == info.tag) return;
    final ctx = navKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showUpdateDialog(
      ctx,
      info,
      onLater: () =>
          DatabaseHelper.instance.setSetting(_promptedKey, info.tag),
    );
  }

  /// Shows the "new version" dialog with a changelog snippet.
  /// [onLater] runs when the user dismisses without updating.
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateInfo info, {
    Future<void> Function()? onLater,
  }) async {
    final raw = info.changelog;
    final snippet =
        raw.length > 300 ? '${raw.substring(0, 300)}…' : raw;
    final update = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.system_update, color: kGold, size: 32),
        title: Text('${tr(dctx, 'update_title')} v${info.version}'),
        content: SingleChildScrollView(
          child: Text(
            snippet.isEmpty
                ? tr(dctx, 'update_no_notes')
                : snippet,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(tr(dctx, 'update_later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(tr(dctx, 'update_now')),
          ),
        ],
      ),
    );
    if (update == true) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateProgressDialog(info: info),
      );
    } else {
      await onLater?.call();
    }
  }

  static List<int>? _parseVersion(String v) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
    if (m == null) return null;
    return [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    ];
  }

  static bool _isNewer(List<int> remote, List<int> local) {
    for (var i = 0; i < 3; i++) {
      if (remote[i] != local[i]) return remote[i] > local[i];
    }
    return false;
  }
}

/// Modal progress dialog: downloads the APK, then fires the installer.
class _UpdateProgressDialog extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateProgressDialog({required this.info});

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await UpdateService.downloadAndInstall(
        widget.info.apkUrl,
        (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'update_downloading')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
          ),
          const SizedBox(height: 12),
          Text('${(_progress * 100).toStringAsFixed(0)}%'),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              tr(context, 'update_failed'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_failed)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'close')),
          ),
      ],
    );
  }
}
