import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Gift occasion reminders (Package AR).
///
/// [checkUpcoming] reads stored gifts, computes the next anniversary
/// of each gift's occasion (month/day), and for occasions within the
/// next 7 days fires both an immediate system notification and an
/// in-app notification-center entry. Entries are deduped per
/// (person, occasion, occurrence-date) so a repeat call stays silent.
///
/// Safe to call on every app start and from the periodic background
/// worker; all failures are swallowed.
class GiftReminderService {
  GiftReminderService._();

  static const int _windowDays = 7;

  /// Notifies for gift occasions whose next anniversary falls within
  /// the next [_windowDays] days.
  static Future<void> checkUpcoming() async {
    try {
      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final gifts = await DatabaseHelper.instance.getGifts();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // One reminder per (person, occasion): prefer the most recent gift.
      final seen = <String>{};
      final upcoming = <_Upcoming>[];
      final sorted = [...gifts]
        ..sort((a, b) => b.date.compareTo(a.date));
      for (final g in sorted) {
        if (g.person.trim().isEmpty || g.occasion.trim().isEmpty) continue;
        final key = '${g.person.trim().toLowerCase()}'
            '::${g.occasion.trim().toLowerCase()}';
        if (seen.contains(key)) continue;
        seen.add(key);
        final next = _nextOccurrence(g.date, today);
        final diff = next.difference(today).inDays;
        if (diff >= 0 && diff <= _windowDays) {
          upcoming.add(_Upcoming(
            person: g.person.trim(),
            occasion: g.occasion.trim(),
            daysAway: diff,
            date: next,
          ));
        }
      }

      for (final u in upcoming) {
        final title = AppStrings.get('gift_reminder_title', lang);
        final body = _bodyFor(lang, u);
        final dedupe =
            'gift:${u.person}:${u.occasion}:${u.date.toIso8601String().substring(0, 10)}';
        try {
          await NotificationService.showNow(title: title, body: body);
        } catch (_) {}
        await NotificationCenter.push(
          title: title,
          body: body,
          type: 'gift_reminder',
          dedupeKey: dedupe,
        );
      }
    } catch (_) {
      // Reminders must never crash startup or the worker.
    }
  }

  static String _bodyFor(String lang, _Upcoming u) {
    String key;
    if (u.daysAway == 0) {
      key = 'gift_reminder_body_today';
    } else if (u.daysAway == 1) {
      key = 'gift_reminder_body_tomorrow';
    } else {
      key = 'gift_reminder_body_days';
    }
    return AppStrings.get(key, lang)
        .replaceAll('{person}', u.person)
        .replaceAll('{occasion}', u.occasion)
        .replaceAll('{days}', u.daysAway.toString());
  }

  /// Next anniversary (month/day) of [original] on/after [today].
  static DateTime _nextOccurrence(DateTime original, DateTime today) {
    var year = today.year;
    var candidate = _validDate(year, original.month, original.day);
    if (candidate.isBefore(today)) {
      candidate = _validDate(year + 1, original.month, original.day);
    }
    return candidate;
  }

  /// Clamps the day to the month's last day (e.g. Feb 29 → Feb 28).
  static DateTime _validDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay).toInt());
  }
}

class _Upcoming {
  final String person;
  final String occasion;
  final int daysAway;
  final DateTime date;

  const _Upcoming({
    required this.person,
    required this.occasion,
    required this.daysAway,
    required this.date,
  });
}
