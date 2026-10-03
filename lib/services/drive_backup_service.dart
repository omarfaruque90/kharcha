import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

/// Google Drive auto-backup (appDataFolder — private to the app).
///
/// Uses the Google account from google_sign_in with incremental consent for
/// the drive.appdata scope (requested only when the user enables the
/// feature). Guest users (no Google account) cannot use Drive backup.
class DriveBackupService {
  DriveBackupService._();

  static const String _autoKey = 'drive_auto_backup';
  static const String _lastKey = 'drive_last_backup';
  static const Duration _interval = Duration(days: 7);

  /// Whether the user enabled auto backup.
  static Future<bool> isAutoEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoKey, value);
    } catch (_) {}
  }

  /// Last successful Drive backup time, or null.
  static Future<DateTime?> lastBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_lastKey);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveLastBackup(DateTime when) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastKey, when.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// HTTP client injecting the Drive access token.
  static http.Client _authedClient(String token) =>
      _BearerClient(token);

  /// Returns an authorized Drive API client.
  /// When [interactive] is true the user may be asked to sign in / grant
  /// the drive.appdata scope; otherwise returns null silently when auth
  /// isn't available without interaction (background use).
  static Future<drive.DriveApi?> _driveApi(
      {required bool interactive}) async {
    try {
      await GoogleSignIn.instance.initialize();
      var account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) {
        if (!interactive) return null;
        account = await GoogleSignIn.instance.authenticate();
      }
      final authz = interactive
          ? await account.authorizationClient
              .authorizeScopes([drive.DriveApi.driveAppdataScope])
          : await account.authorizationClient
              .authorizationForScopes([drive.DriveApi.driveAppdataScope]);
      if (authz == null) return null;
      return drive.DriveApi(_authedClient(authz.accessToken));
    } catch (_) {
      return null;
    }
  }

  /// Uploads a fresh backup JSON to appDataFolder. Returns true on success.
  /// Throws [DriveAuthException] when auth was declined/unavailable so the
  /// caller can toggle the feature off.
  static Future<bool> backupNow({bool interactive = true}) async {
    final api = await _driveApi(interactive: interactive);
    if (api == null) throw DriveAuthException();
    try {
      final json = await BackupService.generateBackupJson();
      final bytes = utf8.encode(json);
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final meta = drive.File()
        ..name = 'khorcha-backup-$stamp.json'
        ..parents = ['appDataFolder']
        ..mimeType = 'application/json';
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );
      await api.files.create(meta, uploadMedia: media);
      await _saveLastBackup(DateTime.now());
      return true;
    } catch (e) {
      if (e is DriveAuthException) rethrow;
      return false;
    }
  }

  /// Downloads the newest backup from appDataFolder and merges it.
  /// Returns rows written, -1 on failure.
  static Future<int> restoreLatest() async {
    final api = await _driveApi(interactive: true);
    if (api == null) throw DriveAuthException();
    try {
      final list = await api.files.list(
        spaces: 'appDataFolder',
        orderBy: 'createdTime desc',
        pageSize: 1,
        $fields: 'files(id, name)',
      );
      final files = list.files;
      if (files == null || files.isEmpty) return -1;
      final id = files.first.id;
      if (id == null) return -1;
      final media = await api.files.get(
        id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return await BackupService.restoreFromJson(utf8.decode(bytes));
    } catch (e) {
      if (e is DriveAuthException) rethrow;
      return -1;
    }
  }

  /// Weekly auto-backup. Silent: only runs when enabled, due, and
  /// authorized without user interaction. Safe to call from the
  /// background WorkManager task or app start.
  static Future<void> autoBackupIfDue() async {
    try {
      if (!await isAutoEnabled()) return;
      final last = await lastBackup();
      if (last != null &&
          DateTime.now().difference(last) < _interval) {
        return;
      }
      final ok = await backupNow(interactive: false);
      if (!ok) {
        // Don't disable on a transient network failure — only auth
        // problems throw DriveAuthException.
      }
    } on DriveAuthException {
      // Scope revoked in background: turn the feature off quietly.
      await setAutoEnabled(false);
    } catch (_) {}
  }
}

/// Thrown when Drive auth is declined, revoked, or unavailable.
class DriveAuthException implements Exception {}

/// Minimal http client adding a Bearer token to every request.
class _BearerClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  _BearerClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
