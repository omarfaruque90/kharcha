import 'package:flutter/material.dart';

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
  ExpenseCategory(id: 'others', icon: Icons.category, color: Color(0xFF616161)),
];

/// Returns the category for [id], falling back to "others".
ExpenseCategory categoryById(String id) {
  return kCategories.firstWhere(
    (c) => c.id == id,
    orElse: () => kCategories.last,
  );
}
