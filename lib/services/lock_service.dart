import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../db/database_helper.dart';

/// App lock: a SHA-256 hashed PIN kept in secure storage, with an optional
/// biometric (fingerprint/face) shortcut. The on/off flag lives in the
/// settings table; the PIN hash never touches SQLite or the cloud.
class LockService {
  LockService._();
  static final LockService instance = LockService._();

  static const String _pinHashKey = 'kharcha_app_lock_pin';
  static const String _enabledKey = 'app_lock_enabled';
  static const String _bioKey = 'app_lock_biometric';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _auth = LocalAuthentication();

  /// True when the user enabled the lock AND a PIN is stored.
  Future<bool> isLockEnabled() async {
    final flag = await DatabaseHelper.instance.getSetting(_enabledKey);
    if (flag != '1') return false;
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinHashKey, value: _hash(pin));
    await DatabaseHelper.instance.setSetting(_enabledKey, '1');
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _pinHashKey);
    await DatabaseHelper.instance.setSetting(_enabledKey, '0');
    await DatabaseHelper.instance.setSetting(_bioKey, '0');
  }

  /// M17: rate-limiting state (in-memory + persisted timestamp).
  static const _failKey = 'lock_fail_count';
  static const _lockoutKey = 'lock_lockout_until';

  /// Seconds to wait after N failed attempts (exponential backoff).
  Future<int> lockoutRemaining() async {
    try {
      final until =
          await DatabaseHelper.instance.getSetting(_lockoutKey);
      if (until == null || until.isEmpty) return 0;
      final ms = int.tryParse(until) ?? 0;
      final remaining =
          (ms - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
      return remaining > 0 ? remaining : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> verifyPin(String pin) async {
    // M17: enforce lockout.
    if (await lockoutRemaining() > 0) return false;
    final hash = await _storage.read(key: _pinHashKey);
    if (hash == null || hash.isEmpty) return false;
    final ok = _constantTimeEquals(hash, _hash(pin));
    try {
      final db = DatabaseHelper.instance;
      if (ok) {
        await db.setSetting(_failKey, '0');
        await db.setSetting(_lockoutKey, '');
      } else {
        final raw = await db.getSetting(_failKey);
        final fails = (int.tryParse(raw ?? '') ?? 0) + 1;
        await db.setSetting(_failKey, '$fails');
        // Exponential backoff: 30s, 60s, 120s, ... capped at 15 min.
        if (fails >= 5) {
          final backoffSecs =
              (30 * (1 << (fails - 5))).clamp(30, 900);
          final until = DateTime.now().millisecondsSinceEpoch +
              backoffSecs * 1000;
          await db.setSetting(_lockoutKey, '$until');
        }
      }
    } catch (_) {}
    return ok;
  }

  Future<bool> isBiometricEnabled() async {
    return await DatabaseHelper.instance.getSetting(_bioKey) == '1';
  }

  Future<void> setBiometricEnabled(bool value) async {
    await DatabaseHelper.instance
        .setSetting(_bioKey, value ? '1' : '0');
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics &&
          await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Returns true when the user authenticates successfully.
  Future<bool> authenticateBiometric(String localizedReason) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  String _hash(String pin) {
    // Domain-separated so the hash is useless outside this app.
    return sha256.convert(utf8.encode('kharcha-pin-v1:$pin')).toString();
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
