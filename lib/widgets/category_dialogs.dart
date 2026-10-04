import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/custom_category.dart';

/// Shared category dialogs used by every picker in the app
/// (add-expense grid, budget dialog, recurring dialog, templates).
///
/// Returns the new category id when the user saves, null otherwise.
Future<String?> showAddCategoryDialog(BuildContext context) async {
  final nameCtrl = TextEditingController();
  final emojiCtrl = TextEditingController();
  var confirmed = false;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'new_category_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr(ctx, 'category_name'),
              hintText: tr(ctx, 'category_name_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emojiCtrl,
            decoration: InputDecoration(
              labelText: tr(ctx, 'goal_emoji'),
              hintText: '🎮',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr(ctx, 'cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (nameCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(tr(ctx, 'err_name_empty'))),
              );
              return;
            }
            confirmed = true;
            Navigator.pop(ctx);
          },
          child: Text(tr(ctx, 'save')),
        ),
      ],
    ),
  );
  final name = nameCtrl.text.trim();
  final emoji = emojiCtrl.text.trim();
  nameCtrl.dispose();
  emojiCtrl.dispose();
  if (!confirmed || name.isEmpty) return null;
  try {
    final id =
        await DatabaseHelper.instance.insertCustomCategory(name, emoji);
    final cats = await DatabaseHelper.instance.getCustomCategories();
    CustomCategoryRegistry.setAll(cats);
    return id;
  } catch (_) {
    return null;
  }
}

/// Edit dialog for a custom category — change name and emoji.
/// Returns true if saved, false/null otherwise.
Future<bool?> showEditCategoryDialog(
    BuildContext context, CustomCategory category) async {
  final nameCtrl = TextEditingController(text: category.name);
  final emojiCtrl = TextEditingController(text: category.emoji);
  var confirmed = false;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'edit_category_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr(ctx, 'category_name'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emojiCtrl,
            decoration: InputDecoration(
              labelText: tr(ctx, 'goal_emoji'),
              hintText: '🎮',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr(ctx, 'cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (nameCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(tr(ctx, 'err_name_empty'))),
              );
              return;
            }
            confirmed = true;
            Navigator.pop(ctx);
          },
          child: Text(tr(ctx, 'save')),
        ),
      ],
    ),
  );
  final name = nameCtrl.text.trim();
  final emoji = emojiCtrl.text.trim();
  nameCtrl.dispose();
  emojiCtrl.dispose();
  if (!confirmed || name.isEmpty) return null;
  try {
    await DatabaseHelper.instance.updateCustomCategory(
      category.id,
      name,
      emoji,
    );
    final cats = await DatabaseHelper.instance.getCustomCategories();
    CustomCategoryRegistry.setAll(cats);
    return true;
  } catch (_) {
    return false;
  }
}

/// Confirm dialog for hiding a built-in category from pickers.
/// Returns true when the user confirmed.
Future<bool> showHideCategoryDialog(
    BuildContext context, String label) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'hide_category_title')),
      content: Text(
          tr(ctx, 'hide_category_msg').replaceFirst('{name}', label)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr(ctx, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr(ctx, 'hide')),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Confirm dialog for deleting a custom category.
/// Returns true when the user confirmed.
Future<bool> showDeleteCategoryDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, 'delete_category_title')),
      content: Text(tr(ctx, 'delete_category_msg')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr(ctx, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr(ctx, 'delete')),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Deletes a custom category and refreshes the registry.
/// Returns true on success.
Future<bool> deleteCustomCategoryAndRefresh(String id) async {
  try {
    await DatabaseHelper.instance.deleteCustomCategory(id);
    final cats = await DatabaseHelper.instance.getCustomCategories();
    CustomCategoryRegistry.setAll(cats);
    return true;
  } catch (_) {
    return false;
  }
}
