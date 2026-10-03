import '../db/database_helper.dart';

/// Package BG — smart auto-categorize that learns from the user's history.
///
/// Every time an expense is saved, [learn] tokenizes the note and records
/// each word → category association (with a count) in the `category_learning`
/// table. When the user types a note later, [suggest] tokenizes it and asks
/// the DB for the category with the highest accumulated word-count score.
///
/// Bangla notes are fully supported: tokenization keeps Unicode letters
/// (`[\p{L}\p{N}]`), so "ধানমন্ডি লেকে খাবার" tokenizes cleanly.
class CategoryLearner {
  CategoryLearner._();

  /// Common low-signal words dropped before learning/suggesting.
  static const Set<String> _stopwords = {
    'the', 'and', 'for', 'with', 'a', 'an', 'of', 'to', 'in', 'on', 'at',
    'এর', 'থেকে', 'করে', 'আর', 'সাথে', 'জন্য',
  };

  /// Lowercase, split on non-alphanumeric (Unicode-aware), drop short
  /// tokens and stopwords.
  static List<String> tokenize(String text) {
    final matches = RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(
      text.toLowerCase(),
    );
    return matches
        .map((m) => m.group(0))
        .whereType<String>()
        .where((t) => t.length >= 3 && !_stopwords.contains(t))
        .toList(growable: false);
  }

  /// Suggest a category id based on a note, or null when nothing is known.
  static Future<String?> suggest(String note) async {
    try {
      final tokens = tokenize(note);
      if (tokens.isEmpty) return null;
      return await DatabaseHelper.instance.suggestCategoryForWords(tokens);
    } catch (_) {
      return null;
    }
  }

  /// Record the note's tokens against [categoryId]. Call on every expense
  /// save so the model keeps learning.
  static Future<void> learn(String note, String categoryId) async {
    try {
      if (note.trim().isEmpty || categoryId.trim().isEmpty) return;
      for (final token in tokenize(note)) {
        await DatabaseHelper.instance.learnCategoryWord(token, categoryId);
      }
    } catch (_) {
      // Learning is best-effort; never block a save.
    }
  }
}
