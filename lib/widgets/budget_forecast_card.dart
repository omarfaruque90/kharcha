import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/budget.dart';
import '../models/custom_category.dart';
import '../models/category.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart' show monthKeyOf;
import '../providers/settings_provider.dart';
import '../services/budget_forecast.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// Predictive budget warnings card for the home screen.
///
/// Forecasts each budgeted category's month-end spend from its current
/// pace (see [BudgetForecast]) and shows up to three warnings for
/// categories projected to exceed their budget. Renders
/// [SizedBox.shrink] when there is nothing to warn about.
class BudgetForecastCard extends StatefulWidget {
  const BudgetForecastCard({super.key});

  @override
  State<BudgetForecastCard> createState() => _BudgetForecastCardState();
}

class _BudgetForecastCardState extends State<BudgetForecastCard> {
  /// Fetched ONCE in initState. Creating the future inside build would
  /// re-run the DB query on every rebuild (and reset the FutureBuilder
  /// to its empty state each time).
  late final Future<List<Budget>> _budgetsFuture;

  @override
  void initState() {
    super.initState();
    _budgetsFuture =
        DatabaseHelper.instance.getBudgetsForMonth(monthKeyOf(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final expenses = context.watch<ExpenseProvider>().expenses;
    final lang = context.watch<SettingsProvider>().language;
    final now = DateTime.now();

    return FutureBuilder<List<Budget>>(
      future: _budgetsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final budgets = snapshot.data!;

        final monthExpenses = expenses
            .where((e) => e.date.year == now.year && e.date.month == now.month)
            .toList();
        final warnings = BudgetForecast.forecast(
          monthExpenses: monthExpenses,
          budgets: budgets,
          now: now,
        ).take(3).toList();
        if (warnings.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return StaggeredEntrance(
          delayMs: 220,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.red.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        tr(context, 'forecast_title'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final w in warnings)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: _categoryIcon(w.categoryId),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _warningText(context, lang, w),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Category icon: user emoji for custom categories, otherwise the
  /// built-in icon — same pattern as [ExpenseTile].
  Widget _categoryIcon(String categoryId) {
    final custom = CustomCategoryRegistry.byId(categoryId);
    if (custom != null && custom.emoji.isNotEmpty) {
      return Text(custom.emoji, style: const TextStyle(fontSize: 18));
    }
    final cat = categoryById(categoryId);
    return Icon(cat.icon, size: 17, color: kGoldDark);
  }

  String _warningText(
    BuildContext context,
    String lang,
    ForecastWarning w,
  ) {
    var s = tr(context, 'forecast_over');
    s = s.replaceAll('{cat}', CustomCategoryRegistry.displayName(w.categoryId, lang));
    s = s.replaceAll('{projected}', formatMoney(w.projected));
    s = s.replaceAll('{budget}', formatMoney(w.budget.limitAmount));
    return s;
  }
}
