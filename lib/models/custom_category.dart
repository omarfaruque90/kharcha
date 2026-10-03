import '../l10n/app_strings.dart';

/// A user-created expense category, stored locally in SQLite
/// (`custom_categories`). The user types the name and an emoji manually
/// (e.g. "Pet" + 🐶); the emoji is rendered as the category's icon.
class CustomCategory {
  final String id;
  final String name;
  final String emoji;

  const CustomCategory({
    required this.id,
    required this.name,
    this.emoji = '',
  });

  factory CustomCategory.fromMap(Map<String, dynamic> map) {
    return CustomCategory(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      emoji: map['emoji'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
      };
}

/// In-memory registry for user-created categories, populated from SQLite
/// at startup (see main.dart) and refreshed whenever categories change.
///
/// Display code (expense tiles, reports, filters, export) consults this
/// so custom categories render with their name + emoji without async
/// plumbing in every widget.
class CustomCategoryRegistry {
  CustomCategoryRegistry._();

  static final Map<String, CustomCategory> _byId = {};

  static void setAll(Iterable<CustomCategory> categories) {
    _byId
      ..clear()
      ..addEntries(categories.map((c) => MapEntry(c.id, c)));
  }

  static CustomCategory? byId(String id) => _byId[id];

  static List<CustomCategory> get all => _byId.values.toList();

  /// Display label for any category id: the custom name for user-made
  /// categories, otherwise the localized built-in name.
  static String displayName(String id, String lang) {
    final custom = _byId[id];
    if (custom != null) return custom.name;
    return AppStrings.categoryName(id, lang);
  }
}
