import '../l10n/app_strings.dart';
import 'category.dart';

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

  // ------------------- built-in hide/show -------------------

  /// Ids of built-in categories the user hid from pickers.
  /// History (expenses, reports, exports) still resolves hidden ids —
  /// only pickers filter them out.
  static final Set<String> _hidden = {};

  /// Called once at startup with the persisted list (see main.dart).
  static void setHidden(Iterable<String> ids) {
    _hidden
      ..clear()
      ..addAll(ids);
  }

  static List<String> get hiddenIds => _hidden.toList();

  static bool isHidden(String id) => _hidden.contains(id);

  /// Built-ins minus hidden ones — use this in every category PICKER.
  static List<ExpenseCategory> visibleBuiltinCategories() =>
      kCategories.where((c) => !_hidden.contains(c.id)).toList();

  /// Persist hook, wired in main.dart (avoids a db import cycle).
  static Future<void> Function(List<String> hidden)? onHiddenChanged;

  static Future<void> _persist() async {
    try {
      await onHiddenChanged?.call(_hidden.toList());
    } catch (_) {}
  }

  static Future<void> hideBuiltin(String id) async {
    _hidden.add(id);
    await _persist();
  }

  static Future<void> unhideBuiltin(String id) async {
    _hidden.remove(id);
    await _persist();
  }

  static Future<void> toggleBuiltin(String id) async {
    if (_hidden.contains(id)) {
      _hidden.remove(id);
    } else {
      _hidden.add(id);
    }
    await _persist();
  }
}
