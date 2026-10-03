import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/challenge.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// No-spend challenge roll-up (Package Z).
///
/// [checkDaily] is safe to call on every app start: it counts zero-expense
/// days since the last check, grows the streak on clean days only (an
/// expense day never resets or fails the challenge), completes the
/// challenge at a 7-day streak with a success notification, and ends
/// challenges whose window has passed. Everything is best-effort —
/// failures never crash the caller.
///
/// This file codes against the coordinator-provided pieces:
///   - `class Challenge` (models/challenge.dart): fields `id` (String?),
///     `type`, `start`, `end`, `streak`, `active`.
///   - `DatabaseHelper.instance.getActiveChallenge()`
///   - `DatabaseHelper.instance.insertChallenge(Challenge)` → Future<String>
///   - `DatabaseHelper.instance.updateChallenge(Challenge)` → Future<int>
class ChallengeService {
  ChallengeService._();

  /// Prefs key holding the last yyyy-MM-dd date this roll-up ran.
  static const String _lastCheckKey = 'challenge_last_check';

  /// Written when a challenge deactivates so the screen can show a
  /// history line even though only the active challenge is queryable.
  static const String _lastWonKey = 'challenge_last_won';
  static const String _lastStreakKey = 'challenge_last_streak';

  static String _key(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Daily roll-up. Call once at startup (and after starting a challenge).
  static Future<void> checkDaily() async {
    try {
      final db = DatabaseHelper.instance;
      final Challenge? challenge = await db.getActiveChallenge();
      if (challenge == null || !challenge.active) return;

      final today = _dayOnly(DateTime.now());
      final startDay = _dayOnly(challenge.start);
      final endDay = _dayOnly(challenge.end);

      // Window passed without reaching 7 → the challenge simply ends.
      if (today.isAfter(endDay)) {
        challenge.active = false;
        await db.updateChallenge(challenge);
        await _saveLastResult(won: false, streak: challenge.streak);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastKey = prefs.getString(_lastCheckKey);
      DateTime cursor;
      if (lastKey != null) {
        final parts = lastKey.split('-');
        cursor = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        ).add(const Duration(days: 1));
      } else {
        // First roll-up for this challenge: walk from its start day.
        cursor = startDay;
      }
      if (cursor.isBefore(startDay)) cursor = startDay;

      var streak = challenge.streak;
      if (!cursor.isAfter(today)) {
        final expenses = await db.getAllExpenses();
        while (!cursor.isAfter(today)) {
          var spent = false;
          for (final e in expenses) {
            final d = e.date;
            if (d.year == cursor.year &&
                d.month == cursor.month &&
                d.day == cursor.day) {
              spent = true;
              break;
            }
          }
          // Clean day → streak grows. Expense day → streak stays as-is;
          // the challenge never auto-fails.
          if (!spent) streak++;
          if (streak >= 7) break;
          cursor = cursor.add(const Duration(days: 1));
        }
      }

      await prefs.setString(_lastCheckKey, _key(today));

      if (streak >= 7) {
        challenge.streak = 7;
        challenge.active = false;
        await db.updateChallenge(challenge);
        await _saveLastResult(won: true, streak: 7);
        await _notifySuccess(today);
      } else if (streak != challenge.streak) {
        challenge.streak = streak;
        await db.updateChallenge(challenge);
      }
    } catch (_) {
      // Roll-up must never crash startup.
    }
  }

  /// Set of yyyy-MM-dd keys inside [start]..[end] that have at least one
  /// expense. Used by the challenge screen to render the 7 day cells.
  static Future<Set<String>> spentDayKeys(
      DateTime start, DateTime end) async {
    try {
      final expenses = await DatabaseHelper.instance.getAllExpenses();
      final s = _dayOnly(start);
      final e = _dayOnly(end);
      final out = <String>{};
      for (final ex in expenses) {
        final d = _dayOnly(ex.date);
        if (!d.isBefore(s) && !d.isAfter(e)) out.add(_key(d));
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveLastResult({
    required bool won,
    required int streak,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lastWonKey, won);
      await prefs.setInt(_lastStreakKey, streak);
    } catch (_) {}
  }

  /// Reads the last finished challenge result for the history line.
  /// Returns null when no challenge has finished yet on this device.
  static Future<({bool won, int streak})?> lastResult() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_lastWonKey)) return null;
      return (
        won: prefs.getBool(_lastWonKey) ?? false,
        streak: prefs.getInt(_lastStreakKey) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _notifySuccess(DateTime today) async {
    try {
      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final title = AppStrings.get('notif_challenge_title', lang);
      final body = AppStrings.get('notif_challenge_body', lang);
      await NotificationService.showNow(title: title, body: body);
      await NotificationCenter.push(
        title: title,
        body: body,
        type: 'challenge',
        dedupeKey: 'challenge_complete:${_key(today)}',
      );
    } catch (_) {}
  }
}
