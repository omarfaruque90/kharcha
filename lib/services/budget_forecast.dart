import '../models/budget.dart';
import '../models/expense.dart';

/// One predictive-budget warning: a category whose current spend pace
/// projects past its monthly budget limit.
class ForecastWarning {
  final String categoryId;
  final double spent;
  final double projected;
  final Budget budget;

  const ForecastWarning({
    required this.categoryId,
    required this.spent,
    required this.projected,
    required this.budget,
  });
}

/// Pure on-device budget forecasting: projects each budgeted category's
/// month-end spend from its current pace and flags overshoot risk.
///
/// `projected = spent / daysElapsed * daysInMonth`.
/// No DB access — callers pass already-loaded data, so this is trivially
/// testable.
class BudgetForecast {
  BudgetForecast._();

  static List<ForecastWarning> forecast({
    required List<Expense> monthExpenses,
    required List<Budget> budgets,
    required DateTime now,
  }) {
    // Pure arithmetic on caller-supplied data, but this runs inside a
    // widget build — never let it throw.
    try {
      return _forecast(
        monthExpenses: monthExpenses,
        budgets: budgets,
        now: now,
      );
    } catch (_) {
      return const [];
    }
  }

  static List<ForecastWarning> _forecast({
    required List<Expense> monthExpenses,
    required List<Budget> budgets,
    required DateTime now,
  }) {
    if (budgets.isEmpty || monthExpenses.isEmpty) return const [];

    final spentByCat = <String, double>{};
    for (final e in monthExpenses) {
      spentByCat[e.categoryId] =
          (spentByCat[e.categoryId] ?? 0) + (e.bdtAmount ?? e.amount);
    }

    final daysElapsed = now.day;
    if (daysElapsed <= 0) return const [];
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    final warnings = <ForecastWarning>[];
    for (final b in budgets) {
      final spent = spentByCat[b.categoryId] ?? 0;
      if (spent <= 0) continue;
      final projected = spent / daysElapsed * daysInMonth;
      if (projected > b.limitAmount) {
        warnings.add(ForecastWarning(
          categoryId: b.categoryId,
          spent: spent,
          projected: projected,
          budget: b,
        ));
      }
    }
    return warnings;
  }
}
