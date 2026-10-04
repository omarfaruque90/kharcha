import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/expense_template.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import 'category_dialogs.dart';
import 'motion.dart';

/// Quick expense templates: one-tap chips that instantly log a pre-set
/// expense (amount + category + payment method + note).
///
/// Tap → adds the expense immediately via [ExpenseProvider.add] and shows
/// a toast. Long-press → confirm dialog to delete the template.
/// The trailing dashed "+" tile opens the create dialog.
///
/// Template storage is owned by Package A:
/// `DatabaseHelper.instance.getTemplates()/insertTemplate()/deleteTemplate()`.
class QuickTemplates extends StatefulWidget {
  /// Optional hook so the parent can refresh after a mutation.
  final VoidCallback? onChanged;

  const QuickTemplates({super.key, this.onChanged});

  @override
  State<QuickTemplates> createState() => _QuickTemplatesState();
}

class _QuickTemplatesState extends State<QuickTemplates> {
  List<ExpenseTemplate> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var items = await DatabaseHelper.instance.getTemplates();
      // First run: seed 2 demo templates so the user sees how it works.
      // Everything else in the app stays manual — no other defaults.
      if (items.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (!(prefs.getBool('demo_templates_seeded') ?? false)) {
          await _seedDemoTemplates();
          await prefs.setBool('demo_templates_seeded', true);
          items = await DatabaseHelper.instance.getTemplates();
        }
      }
      if (!mounted) return;
      setState(() {
        _templates = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// 2 demo templates — the only pre-set content in the app.
  Future<void> _seedDemoTemplates() async {
    final demos = [
      ExpenseTemplate(
        id: ExpenseTemplate.newId(),
        name: tr(context, 'template_lunch'),
        amount: 150,
        categoryId: 'food',
        payment: 'cash',
        emoji: '🍽️',
        updatedAt: DateTime.now(),
      ),
      ExpenseTemplate(
        id: ExpenseTemplate.newId(),
        name: tr(context, 'template_transport'),
        amount: 100,
        categoryId: 'transport',
        payment: 'cash',
        emoji: '🚌',
        updatedAt: DateTime.now(),
      ),
    ];
    for (final t in demos) {
      await DatabaseHelper.instance.insertTemplate(t);
    }
  }

  void _notifyChanged() => widget.onChanged?.call();

  /// Guards against double-tap creating duplicate expenses.
  final Set<String?> _applying = {};

  /// One-tap add: logs the expense instantly, no form.
  Future<void> _applyTemplate(ExpenseTemplate t) async {
    if (!_applying.add(t.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    try {
      await provider.add(
        Expense(
          amount: t.amount,
          categoryId: t.categoryId.isEmpty ? 'others' : t.categoryId,
          date: DateTime.now(),
          note: t.name,
          paymentMethod: t.payment.isEmpty ? 'cash' : t.payment,
        ),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr(context, 'tpl_added'))),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr(context, 'tpl_failed'))),
      );
    } finally {
      _applying.remove(t.id);
    }
  }

  Future<void> _confirmDelete(ExpenseTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'tpl_delete_title')),
        content: Text(tr(ctx, 'tpl_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok == true && t.id != null) {
      await DatabaseHelper.instance.deleteTemplate(t.id!);
      await _load();
      _notifyChanged();
    }
  }

  Future<void> _showCreateDialog() async {
    final lang = context.read<SettingsProvider>().language;
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final emojiCtrl = TextEditingController();
    String categoryId =
        CustomCategoryRegistry.visibleBuiltinCategories().isNotEmpty
            ? CustomCategoryRegistry.visibleBuiltinCategories().first.id
            : 'food';
    String payment = 'cash';
    int catNonce = 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(tr(ctx, 'tpl_new_title')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: tr(ctx, 'tpl_name'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: tr(ctx, 'amount'),
                      prefixText: '৳ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('tplcat-$categoryId-$catNonce'),
                    initialValue: categoryId,
                    decoration: InputDecoration(
                      labelText: tr(ctx, 'category'),
                    ),
                    items: [
                      for (final c in CustomCategoryRegistry
                          .visibleBuiltinCategories())
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(AppStrings.categoryName(c.id, lang)),
                        ),
                      for (final c in CustomCategoryRegistry.all)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                              '${c.emoji.isNotEmpty ? '${c.emoji} ' : ''}${c.name}'),
                        ),
                      DropdownMenuItem(
                        value: '__add_new__',
                        child: Text('+ ${tr(ctx, 'add_category')}'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == '__add_new__') {
                        final id = await showAddCategoryDialog(ctx);
                        setDialogState(() {
                          catNonce++;
                          if (id != null) categoryId = id;
                        });
                        return;
                      }
                      if (v != null) setDialogState(() => categoryId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: payment,
                    decoration: InputDecoration(
                      labelText: tr(ctx, 'payment_method'),
                    ),
                    items: [
                      for (final m in const [
                        'cash',
                        'mobile_banking',
                        'card',
                        'other'
                      ])
                        DropdownMenuItem(
                          value: m,
                          child: Text(AppStrings.paymentName(m, lang)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => payment = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emojiCtrl,
                    decoration: InputDecoration(
                      labelText: tr(ctx, 'tpl_emoji'),
                      hintText: '🍔',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tr(ctx, 'cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(tr(ctx, 'save')),
              ),
            ],
          );
        },
      ),
    );

    final name = nameCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim());
    if (result != true) return;
    if (name.isEmpty || amount == null || amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'tpl_invalid'))),
      );
      return;
    }

    await DatabaseHelper.instance.insertTemplate(
      ExpenseTemplate(
        id: ExpenseTemplate.newId(),
        name: name,
        amount: amount,
        categoryId: categoryId,
        payment: payment,
        emoji: emojiCtrl.text.trim(),
        updatedAt: DateTime.now(),
      ),
    );
    await _load();
    _notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    if (_loading) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_templates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr(context, 'tpl_empty'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: _templates.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              if (i == _templates.length) {
                return _AddTile(
                  dark: dark,
                  onTap: _showCreateDialog,
                );
              }
              return _TemplateCard(
                template: _templates[i],
                dark: dark,
                onTap: () => _applyTemplate(_templates[i]),
                onLongPress: () => _confirmDelete(_templates[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One template chip: emoji/icon, name, formatted amount.
class _TemplateCard extends StatelessWidget {
  final ExpenseTemplate template;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TemplateCard({
    required this.template,
    required this.dark,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = categoryById(template.categoryId);
    final custom = CustomCategoryRegistry.byId(template.categoryId);

    final leading = (template.emoji.isNotEmpty || custom != null)
        ? Text(
            template.emoji.isNotEmpty ? template.emoji : (custom?.emoji ?? ''),
            style: const TextStyle(fontSize: 26),
          )
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(cat.icon, color: cat.color, size: 22),
          );

    return GestureDetector(
      onLongPress: onLongPress,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 128,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: dark ? kDeepGreenCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: kGold.withValues(alpha: dark ? 0.35 : 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(height: 6),
              Text(
                template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatMoney(template.amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dark ? kGoldLight : kGoldDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trailing dashed "+" tile that opens the create dialog.
class _AddTile extends StatelessWidget {
  final bool dark;
  final VoidCallback onTap;

  const _AddTile({required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableScale(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: (dark ? kGoldLight : kGoldDark).withValues(alpha: 0.7),
          radius: 16,
        ),
        child: Container(
          width: 72,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                color: dark ? kGoldLight : kGoldDark,
                size: 28,
              ),
              const SizedBox(height: 2),
              Text(
                tr(context, 'tpl_add'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: dark ? kGoldLight : kGoldDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded-rectangle dashed border used by [_AddTile].
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, this.radius = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0;
    const gap = 4.0;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double dist = 0;
      while (dist < metric.length) {
        final len = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, len), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
