import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../providers/settings_provider.dart';
import '../widgets/category_dialogs.dart';
import '../widgets/motion.dart';

/// Manage categories: hide/show built-ins, add/delete custom ones.
/// History (expenses, reports) keeps resolving hidden categories —
/// hiding only removes them from pickers.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<CustomCategory> _customCats = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final cats = await DatabaseHelper.instance.getCustomCategories();
    CustomCategoryRegistry.setAll(cats);
    if (mounted) setState(() => _customCats = cats);
  }

  Future<void> _addCategory() async {
    final id = await showAddCategoryDialog(context);
    if (id != null) _reload();
  }

  Future<void> _deleteCustom(CustomCategory cat) async {
    if (!await showDeleteCategoryDialog(context)) return;
    await deleteCustomCategoryAndRefresh(cat.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'customize_categories')),
        actions: [
          IconButton(
            tooltip: tr(context, 'add_category'),
            icon: const Icon(Icons.add),
            onPressed: _addCategory,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StaggeredEntrance(
            child: _SectionHeader(
              icon: Icons.category_outlined,
              title: tr(context, 'builtin_categories'),
            ),
          ),
          const SizedBox(height: 8),
          for (final c in kCategories)
            StaggeredEntrance(
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(c.icon, color: c.color, size: 22),
                  ),
                  title: Text(AppStrings.categoryName(c.id, lang)),
                  subtitle: CustomCategoryRegistry.isHidden(c.id)
                      ? Text(
                          tr(context, 'hidden_from_pickers'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        )
                      : null,
                  trailing: IconButton(
                    tooltip: tr(context,
                        CustomCategoryRegistry.isHidden(c.id) ? 'show' : 'hide'),
                    icon: Icon(
                      CustomCategoryRegistry.isHidden(c.id)
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: CustomCategoryRegistry.isHidden(c.id)
                          ? theme.colorScheme.outline
                          : kGoldDark,
                    ),
                    onPressed: () async {
                      await CustomCategoryRegistry.toggleBuiltin(c.id);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          StaggeredEntrance(
            child: _SectionHeader(
              icon: Icons.star_outline,
              title: tr(context, 'my_categories'),
            ),
          ),
          const SizedBox(height: 8),
          if (_customCats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                tr(context, 'no_custom_categories'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          for (final cc in _customCats)
            StaggeredEntrance(
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kCustomCategoryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: cc.emoji.isNotEmpty
                        ? Text(cc.emoji,
                            style: const TextStyle(fontSize: 22))
                        : const Icon(Icons.label_rounded,
                            color: kCustomCategoryColor, size: 22),
                  ),
                  title: Text(cc.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr(context, 'edit_category_title'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final saved = await showEditCategoryDialog(
                              context, cc);
                          if (saved == true && context.mounted) {
                            await _reload();
                          }
                        },
                      ),
                      IconButton(
                        tooltip: tr(context, 'delete'),
                        icon: Icon(Icons.delete_outline,
                            color: theme.colorScheme.error),
                        onPressed: () => _deleteCustom(cc),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCategory,
        backgroundColor: kGold,
        foregroundColor: kDeepGreenDark,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'add_category')),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 18, color: dark ? kGoldLight : kGoldDark),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: dark ? kGoldLight : kGoldDark,
          ),
        ),
      ],
    );
  }
}
