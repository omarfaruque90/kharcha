import 'package:flutter/material.dart';

import 'custom_category.dart';

/// Expense category with its icon and brand color.
class ExpenseCategory {
  final String id;
  final IconData icon;
  final Color color;

  const ExpenseCategory({
    required this.id,
    required this.icon,
    required this.color,
  });
}

/// Built-in categories shown in the add-expense grid and filters.
/// ('others' was removed — users now create their own categories via
/// the "+ Add new category" tile.)
const List<ExpenseCategory> kCategories = [
  ExpenseCategory(id: 'food', icon: Icons.restaurant, color: Color(0xFFEF6C00)),
  ExpenseCategory(
      id: 'transport', icon: Icons.directions_bus, color: Color(0xFF1976D2)),
  ExpenseCategory(
      id: 'shopping', icon: Icons.shopping_bag, color: Color(0xFF7B1FA2)),
  ExpenseCategory(id: 'bills', icon: Icons.receipt_long, color: Color(0xFF00838F)),
  ExpenseCategory(id: 'health', icon: Icons.favorite, color: Color(0xFFC2185B)),
  ExpenseCategory(id: 'entertainment', icon: Icons.movie, color: Color(0xFF5D4037)),
  ExpenseCategory(id: 'education', icon: Icons.school, color: Color(0xFF388E3C)),
  // Package AQ: first-class pet categories.
  ExpenseCategory(id: 'pet_food', icon: Icons.pets, color: Color(0xFF2E7D32)),
  ExpenseCategory(
      id: 'vet', icon: Icons.local_hospital, color: Color(0xFFD32F2F)),
];

/// Legacy fallback for expenses saved with the old 'others' id.
const ExpenseCategory _othersFallback = ExpenseCategory(
  id: 'others',
  icon: Icons.category,
  color: Color(0xFF616161),
);

/// Gold tile used for user-created categories.
const Color kCustomCategoryColor = Color(0xFFD4AF37);

/// Returns the category for [id]:
/// - built-in → its entry,
/// - user-created (in [CustomCategoryRegistry]) → a gold tile,
/// - anything else (e.g. legacy 'others') → the legacy fallback.
ExpenseCategory categoryById(String id) {
  if (CustomCategoryRegistry.byId(id) != null) {
    return ExpenseCategory(
      id: id,
      icon: Icons.label_rounded,
      color: kCustomCategoryColor,
    );
  }
  return kCategories.firstWhere(
    (c) => c.id == id,
    orElse: () => _othersFallback,
  );
}
