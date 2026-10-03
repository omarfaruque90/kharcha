import '../l10n/app_strings.dart';
import 'category.dart';
import 'custom_category.dart';

/// The structured meaning of a natural-language expense query.
class ParsedQuery {
  /// Start of the queried range (inclusive, start of day).
  final DateTime from;

  /// End of the queried range (inclusive, end of day).
  final DateTime to;

  /// Category id filter, or null for all categories.
  final String? categoryId;

  /// True when the user asked for their balance (date/category ignored).
  final bool asksBalance;

  const ParsedQuery({
    required this.from,
    required this.to,
    this.categoryId,
    this.asksBalance = false,
  });
}

/// Parses Bangla/English natural-language expense queries such as
/// "আজকে কত খরচ হয়েছে", "গত মাসে খাবারে কত গেল", "my balance".
///
/// Never throws — on any failure it falls back to the current month.
class ExpenseQueryParser {
  ExpenseQueryParser._();

  static ParsedQuery parse(String input, String lang) {
    try {
      return _parse(input, lang);
    } catch (_) {
      return _thisMonthRange();
    }
  }

  static ParsedQuery _parse(String input, String lang) {
    final q = input.toLowerCase().trim();
    final now = DateTime.now();

    // --- Balance? (date/category are ignored in that case) ---
    if (_isBalanceQuery(q)) {
      final range = _thisMonthRange();
      return ParsedQuery(from: range.from, to: range.to, asksBalance: true);
    }

    // --- Date range ---
    ParsedQuery range;
    if (q.contains('today') || q.contains('আজ')) {
      range = _dayRange(now);
    } else if (q.contains('yesterday') || q.contains('গতকাল')) {
      range = _dayRange(now.subtract(const Duration(days: 1)));
    } else if (q.contains('this week') || q.contains('এই সপ্তাহ')) {
      range = _weekRange(now, 0);
    } else if (q.contains('last week') || q.contains('গত সপ্তাহ')) {
      range = _weekRange(now, -1);
    } else if (q.contains('this month') ||
        q.contains('এই মাস') ||
        q.contains('চলতি মাস')) {
      range = _monthRange(now.year, now.month);
    } else if (q.contains('last month') || q.contains('গত মাস')) {
      range = _monthRange(now.year, now.month - 1);
    } else {
      final namedMonth = _matchMonthName(q);
      if (namedMonth != null) {
        var year = now.year;
        if (namedMonth > now.month) year -= 1; // e.g. ডিসেম্বর in October
        range = _monthRange(year, namedMonth);
      } else {
        range = _thisMonthRange();
      }
    }

    // --- Category (built-ins in both langs + user-created categories) ---
    final categoryId = _matchCategory(q);

    return ParsedQuery(
      from: range.from,
      to: range.to,
      categoryId: categoryId,
    );
  }

  // ------------------------------------------------------------------
  // Balance keywords: balance / ব্যালেন্স / "koto ache" (banglish).
  // ------------------------------------------------------------------
  static bool _isBalanceQuery(String q) {
    return q.contains('balance') ||
        q.contains('ব্যালেন্স') ||
        q.contains('koto ache') ||
        q.contains('koto achhe') ||
        q.contains('koto ase');
  }

  // ------------------------------------------------------------------
  // Ranges. `from` = start of day, `to` = end of day (inclusive).
  // ------------------------------------------------------------------
  static ParsedQuery _thisMonthRange() {
    final now = DateTime.now();
    return _monthRange(now.year, now.month);
  }

  static ParsedQuery _dayRange(DateTime day) {
    return ParsedQuery(
      from: DateTime(day.year, day.month, day.day),
      to: DateTime(day.year, day.month, day.day, 23, 59, 59),
    );
  }

  static ParsedQuery _monthRange(int year, int month) {
    return ParsedQuery(
      from: DateTime(year, month, 1),
      // DateTime normalizes out-of-range months (13 → Jan next year).
      to: DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1)),
    );
  }

  /// [offset] 0 = this week (Mon–Sun), -1 = last week.
  static ParsedQuery _weekRange(DateTime now, int offset) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final start = monday.add(Duration(days: offset * 7));
    final end = start.add(const Duration(days: 6));
    return ParsedQuery(
      from: start,
      to: DateTime(end.year, end.month, end.day, 23, 59, 59),
    );
  }

  // ------------------------------------------------------------------
  // Month names: English (full + short, except ambiguous "may") and Bangla.
  // ------------------------------------------------------------------
  static const Map<String, int> _monthNames = {
    'january': 1, 'jan': 1,
    'february': 2, 'feb': 2,
    'march': 3, 'mar': 3,
    'april': 4, 'apr': 4,
    'may': 5,
    'june': 6, 'jun': 6,
    'july': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9, 'sept': 9,
    'october': 10, 'oct': 10,
    'november': 11, 'nov': 11,
    'december': 12, 'dec': 12,
    'জানুয়ারি': 1, 'জানুয়ারী': 1,
    'ফেব্রুয়ারি': 2, 'ফেব্রুয়ারী': 2,
    'মার্চ': 3,
    'এপ্রিল': 4,
    'মে': 5,
    'জুন': 6,
    'জুলাই': 7,
    'আগস্ট': 8,
    'সেপ্টেম্বর': 9,
    'অক্টোবর': 10,
    'নভেম্বর': 11,
    'ডিসেম্বর': 12,
  };

  /// English month-name regexes, compiled once instead of on every parse.
  static final Map<String, RegExp> _monthRegexes = {
    for (final entry in _monthNames.entries)
      if (entry.key.codeUnits.first < 128)
        entry.key: RegExp('\\b${RegExp.escape(entry.key)}\\b'),
  };

  static int? _matchMonthName(String q) {
    for (final entry in _monthNames.entries) {
      final name = entry.key;
      if (name.codeUnits.first < 128) {
        // English: word-boundary match so "mar" doesn't hit "march" first
        // (full names are checked first since iteration order favors them).
        final pattern = _monthRegexes[name];
        if (pattern != null && pattern.hasMatch(q)) {
          return entry.value;
        }
      } else {
        if (q.contains(name)) return entry.value;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Category names: built-ins (AppStrings, both langs) + custom names.
  // Longest match wins so "food court" beats "food".
  // ------------------------------------------------------------------
  static String? _matchCategory(String q) {
    String? bestId;
    var bestLen = 0;

    void consider(String? id, String name) {
      final n = name.trim().toLowerCase();
      if (n.isEmpty || n.length < bestLen) return;
      if (q.contains(n) && n.length > bestLen) {
        bestLen = n.length;
        bestId = id;
      }
    }

    for (final c in kCategories) {
      consider(c.id, AppStrings.categoryName(c.id, 'en'));
      consider(c.id, AppStrings.categoryName(c.id, 'bn'));
    }
    for (final custom in CustomCategoryRegistry.all) {
      consider(custom.id, custom.name);
    }
    return bestId;
  }
}
