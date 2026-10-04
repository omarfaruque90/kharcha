import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/expense_tile.dart';
import '../widgets/motion.dart';
import '../widgets/smart_search.dart';

/// History tab: where/how much was spent. The day-grouped expense list
/// lives here (it used to be on the home screen).
class HistoryScreen extends StatefulWidget {
  final VoidCallback? onAddPressed;

  const HistoryScreen({super.key, this.onAddPressed});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _categoryId; // null = all categories

  String _dayHeader(DateTime day, String lang) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return tr(context, 'day_today');
    if (day == today.subtract(const Duration(days: 1))) {
      return tr(context, 'day_yesterday');
    }
    return DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final expenses = context.watch<ExpenseProvider>();
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final theme = Theme.of(context);

    final filtered = expenses.filtered(categoryId: _categoryId);
    final groups = <DateTime, List<Expense>>{};
    for (final e in filtered) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      (groups[d] ??= []).add(e);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'nav_history')),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SmartSearch(),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tr(context, 'all')),
                      selected: _categoryId == null,
                      onSelected: (_) => setState(() => _categoryId = null),
                    ),
                  ),
                  for (final c in CustomCategoryRegistry
                      .visibleBuiltinCategories())
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(AppStrings.categoryName(c.id, lang)),
                        avatar: Icon(c.icon, size: 16),
                        selected: _categoryId == c.id,
                        onSelected: (_) => setState(() =>
                            _categoryId = _categoryId == c.id ? null : c.id),
                      ),
                    ),
                  for (final cc in CustomCategoryRegistry.all)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(cc.name),
                        avatar: cc.emoji.isNotEmpty
                            ? Text(cc.emoji,
                                style: const TextStyle(fontSize: 16))
                            : const Icon(Icons.label_rounded, size: 16),
                        selected: _categoryId == cc.id,
                        onSelected: (_) => setState(() =>
                            _categoryId = _categoryId == cc.id ? null : cc.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (days.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        size: 44,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'no_expenses'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        tr(context, 'no_expenses_sub'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: widget.onAddPressed,
                      icon: const Icon(Icons.add),
                      label: Text(tr(context, 'add_expense')),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final day = days[i];
                  final items = groups[day]!;
                  final dayTotal = items.fold(
                      0.0, (sum, e) => sum + (e.bdtAmount ?? e.amount));
                  return StaggeredEntrance(
                    key: ValueKey('day-${day.millisecondsSinceEpoch}'),
                    delayMs: (i * 70).clamp(0, 280).toInt(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 16, 20, 6),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _dayHeader(day, lang),
                                style:
                                    theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                formatMoney(dayTotal),
                                style:
                                    theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.4,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final e in items) ExpenseTile(expense: e),
                      ],
                    ),
                  );
                },
                childCount: days.length,
              ),
            ),
          // Clearance so the bottom bar never covers the last row.
          const SliverToBoxAdapter(
            child: SizedBox(height: 120),
          ),
        ],
      ),
    );
  }
}
