import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/custom_category.dart';

/// Displays a category's icon: custom emoji for user-created categories,
/// built-in icon otherwise.
class CategoryIcon extends StatelessWidget {
  final String categoryId;
  final double size;
  final Color? color;

  const CategoryIcon({
    super.key,
    required this.categoryId,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final custom = CustomCategoryRegistry.byId(categoryId);
    final emoji =
        (custom?.emoji.isNotEmpty == true) ? custom!.emoji : null;
    if (emoji != null) {
      return Text(emoji, style: TextStyle(fontSize: size));
    }
    final cat = categoryById(categoryId);
    return Icon(cat.icon, size: size, color: color ?? cat.color);
  }
}
