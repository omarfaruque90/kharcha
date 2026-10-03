import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/recurring_expense.dart';

/// Recurring expense auto-detection (Package BM).
///
/// Scans the last 90 days of expenses and suggests a recurring template for
/// any note that repeats across at least 2 different months with amounts
/// within ±5% of the median. The parent agent decides when to call
/// [detect] (once per month at most, guarded by the
/// `recurring_detect_month` pref) and is responsible for showing the
/// confirmation dialog + strings — see the wiring snippet in the task handoff.
///
/// Everything here is wrapped in try/catch: detection must never break
/// startup.
class RecurringCandidate {
  /// The normalized display note, e.g. "Netflix".
  final String note;

  /// Median amount across the matching occurrences.
  final double amount;

  final String categoryId;
  final String paymentMethod;

  /// Number of matching occurrences in the window.
  final int occurrences;

  /// Most common day-of-month across occurrences (1-31). Used as the
  /// template's [RecurringExpense.dayOfMonth].
  final int dayOfMonth;

  const RecurringCandidate({
    required this.note,
    required this.amount,
    required this.categoryId,
    required this.paymentMethod,
    required this.occurrences,
    required this.dayOfMonth,
  });
}

class RecurringDetectService {
  RecurringDetectService._();

  /// SharedPreferences key holding the `yyyy-MM` key of the month in which
  /// the suggestion dialog was last shown. Dialog shows at most once/month.
  static const prefsMonthKey = 'recurring_detect_month';

  /// Look-back window in days.
  static const _windowDays = 90;

  /// Max occurrences per note to count toward a candidate.
  static const _maxCandidates = 5;

  /// True when the suggestion dialog was already shown for the current month.
  static Future<bool> wasShownThisMonth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(prefsMonthKey);
      return stored == _monthKey(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Records that the suggestion dialog was shown for the current month.
  static Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsMonthKey, _monthKey(DateTime.now()));
    } catch (_) {}
  }

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String _normalize(String s) => s.trim().toLowerCase();

  static double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  /// Finds recurring candidates from the last 90 days of expenses.
  ///
  /// Groups expenses by normalized note (lowercase, trimmed; empty notes
  /// skipped). A group becomes a candidate when it has ≥2 occurrences in
  /// different months and every amount is within ±5% of the group median.
  /// Notes that already have a recurring template (matching template label)
  /// are excluded. Capped at 5 candidates.
  static Future<List<RecurringCandidate>> detect() async {
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: _windowDays));

      final expenses = await db.getAllExpenses();

      // Group by normalized note.
      final Map<String, List<_Occurrence>> groups = {};
      for (final e in expenses) {
        if (e.date.isBefore(cutoff)) continue;
        final norm = _normalize(e.note);
        if (norm.isEmpty) continue;
        groups.putIfAbsent(norm, () => []).add(_Occurrence(
              note: e.note.trim(),
              amount: e.amount,
              categoryId: e.categoryId,
              paymentMethod: e.paymentMethod,
              date: e.date,
            ));
      }

      // Notes that already have a recurring rule — never suggest again.
      final existing = await db.getAllRecurringExpenses();
      final existingNotes =
          existing.map((r) => _normalize(r.label)).toSet();

      final candidates = <RecurringCandidate>[];
      for (final entry in groups.entries) {
        if (candidates.length >= _maxCandidates) break;
        final occs = entry.value;

        // ≥2 occurrences in *different* months.
        final months = occs
            .map((o) => _monthKey(o.date))
            .toSet();
        if (months.length < 2) continue;

        // Amounts within ±5% of the median.
        final median = _median(occs.map((o) => o.amount).toList());
        if (median <= 0) continue;
        final withinBand = occs.every(
          (o) => (o.amount - median).abs() / median <= 0.05,
        );
        if (!withinBand) continue;

        // Already covered by an existing rule?
        if (existingNotes.contains(entry.key)) continue;

        // Most common categoryId / paymentMethod / dayOfMonth in the group.
        final categoryId = _mode(occs.map((o) => o.categoryId).toList());
        final paymentMethod = _mode(occs.map((o) => o.paymentMethod).toList());
        final dayOfMonth =
            _modeInt(occs.map((o) => o.date.day).toList());

        candidates.add(RecurringCandidate(
          note: occs.first.note,
          amount: median,
          categoryId: categoryId ?? 'others',
          paymentMethod: paymentMethod ?? 'cash',
          occurrences: occs.length,
          dayOfMonth: dayOfMonth,
        ));
      }
      return candidates;
    } catch (_) {
      return const [];
    }
  }

  /// Creates a recurring template from an accepted candidate and syncs it
  /// to Firestore via [DatabaseHelper.insertRecurringExpense].
  static Future<void> createFromCandidate(RecurringCandidate c) async {
    try {
      final db = DatabaseHelper.instance;
      final template = RecurringExpense(
        id: RecurringExpense.newId(),
        amount: c.amount,
        categoryId: c.categoryId,
        label: c.note,
        dayOfMonth: c.dayOfMonth,
        paymentMethod: c.paymentMethod,
        note: c.note,
        active: true,
        kind: 'expense',
      );
      await db.insertRecurringExpense(template);
    } catch (_) {}
  }

  static String? _mode(List<String> values) {
    if (values.isEmpty) return null;
    final counts = <String, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    return counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  static int _modeInt(List<int> values) {
    if (values.isEmpty) return 1;
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final day = counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    return day.clamp(1, 31);
  }
}

class _Occurrence {
  final String note;
  final double amount;
  final String categoryId;
  final String paymentMethod;
  final DateTime date;

  const _Occurrence({
    required this.note,
    required this.amount,
    required this.categoryId,
    required this.paymentMethod,
    required this.date,
  });
}
