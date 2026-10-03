import '../l10n/app_strings.dart';
import '../models/category.dart';

/// BT: parses voice input like "food budget 5000" or
/// "খাবার বাজেট পাঁচ হাজার" into a category + amount.
class VoiceBudgetResult {
  final String? categoryId;
  final double? amount;
  const VoiceBudgetResult({this.categoryId, this.amount});
}

class VoiceBudgetParser {
  static const _bnDigits = '০১২৩৪৫৬৭৮৯';

  static const Map<String, int> _bnWords = {
    'শূন্য': 0, 'এক': 1, 'দুই': 2, 'তিন': 3, 'চার': 4,
    'পাঁচ': 5, 'ছয়': 6, 'সাত': 7, 'আট': 8, 'নয়': 9,
    'দশ': 10, 'এগারো': 11, 'বারো': 12, 'তেরো': 13, 'চৌদ্দ': 14,
    'পনেরো': 15, 'ষোলো': 16, 'সতেরো': 17, 'আঠারো': 18, 'ঊনিশ': 19,
    'বিশ': 20, 'ত্রিশ': 30, 'চল্লিশ': 40, 'পঞ্চাশ': 50,
    'ষাট': 60, 'সত্তর': 70, 'আশি': 80, 'নব্বই': 90,
    'শত': 100, 'শ': 100, 'হাজার': 1000, 'লাখ': 100000,
    'লক্ষ': 100000, 'কোটি': 10000000,
    // English words
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
    'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
    'ten': 10, 'hundred': 100, 'thousand': 1000, 'lakh': 100000,
  };

  /// Normalizes Bangla digits to ASCII digits.
  static String normalizeDigits(String text) {
    final buf = StringBuffer();
    for (final ch in text.split('')) {
      final idx = _bnDigits.indexOf(ch);
      buf.write(idx >= 0 ? idx.toString() : ch);
    }
    return buf.toString();
  }

  static VoiceBudgetResult parse(String text, String lang) {
    // Parsing runs on raw voice/STT text — never let it throw.
    try {
      return _parse(text, lang);
    } catch (_) {
      return const VoiceBudgetResult();
    }
  }

  static VoiceBudgetResult _parse(String text, String lang) {
    final normalized = normalizeDigits(text.toLowerCase());

    // 1) Category: match any built-in category name (en + bn).
    String? categoryId;
    for (final c in kCategories) {
      final enName = AppStrings.categoryName(c.id, 'en').toLowerCase();
      final bnName = AppStrings.categoryName(c.id, 'bn');
      if (enName.isNotEmpty && normalized.contains(enName)) {
        categoryId = c.id;
        break;
      }
      if (bnName.isNotEmpty && text.contains(bnName)) {
        categoryId = c.id;
        break;
      }
      // Also match the raw category id (e.g. "food").
      if (normalized.contains(c.id.toLowerCase())) {
        categoryId = c.id;
        break;
      }
    }

    // 2) Amount: prefer digit sequences, else Bangla/English number words.
    double? amount;
    final digitMatch =
        RegExp(r'\d[\d,]*').firstMatch(normalized);
    final digitText = digitMatch?.group(0)?.replaceAll(',', '');
    if (digitText != null && digitText.isNotEmpty) {
      amount = double.tryParse(digitText);
    } else {
      amount = _parseWords(normalized);
    }

    return VoiceBudgetResult(categoryId: categoryId, amount: amount);
  }

  /// Parses phrases like "পাঁচ হাজার" or "five thousand".
  static double? _parseWords(String text) {
    final tokens = text
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[^\p{L}]', unicode: true), ''))
        .where((t) => t.isNotEmpty)
        .toList();
    double total = 0;
    double current = 0;
    var found = false;
    for (final t in tokens) {
      final v = _bnWords[t];
      if (v == null) continue;
      found = true;
      if (v >= 100) {
        // Multiplier: "পাঁচ হাজার" -> (5 or 1) * 1000.
        current = ((current == 0 ? 1 : current) * v).toDouble();
        total += current;
        current = 0;
      } else {
        current += v;
      }
    }
    total += current;
    return found && total > 0 ? total : null;
  }
}
