/// Package AJ: AI budget planner logic.
///
/// Suggests per-category monthly budgets from the 50/30/20 rule, adjusted
/// upward by each category's average actual spend over the last 3 months:
/// `suggested = max(50/30/20 share, 3-month average)`.
///
/// Category buckets:
/// - needs: food, transport, bills, health, education (share the 50%)
/// - wants: shopping, entertainment, travel + any custom/unknown id
///   (share the 30%)
/// - savings: pseudo-entry for the 20% target — displayed but never stored
///   as a budget (there is no expense category for it).
class BudgetSuggestion {
  final String categoryId;

  /// 'needs' | 'wants' | 'savings'.
  final String bucket;

  /// The 50/30/20 share of the monthly income for this category.
  final double ruleShare;

  /// Average monthly spend over the last 3 months (0 when no history).
  final double threeMonthAvg;

  /// User-adjustable amount (starts at max(ruleShare, threeMonthAvg)).
  double amount;

  BudgetSuggestion({
    required this.categoryId,
    required this.bucket,
    required this.ruleShare,
    required this.threeMonthAvg,
    required this.amount,
  });
}

class BudgetPlannerService {
  /// Pseudo category id for the savings target row (never persisted).
  static const String savingsId = '__savings__';

  /// Built-in categories treated as needs (50% of income, split evenly).
  static const Set<String> needs = {
    'food',
    'transport',
    'bills',
    'health',
    'education',
  };

  /// Built-in categories treated as wants (30% of income, split evenly).
  /// Custom user-created categories and 'travel' also land here.
  static const Set<String> wants = {
    'shopping',
    'entertainment',
    'travel',
  };

  static String bucketOf(String categoryId) {
    if (categoryId == savingsId) return 'savings';
    return needs.contains(categoryId) ? 'needs' : 'wants';
  }

  /// Builds suggestions for [categoryIds] (built-ins + user-created).
  /// [avg3m] maps category id → average monthly spend over the last
  /// 3 calendar months (before the current one).
  static List<BudgetSuggestion> suggest({
    required double monthlyIncome,
    required List<String> categoryIds,
    required Map<String, double> avg3m,
  }) {
    final income = monthlyIncome < 0 ? 0.0 : monthlyIncome;
    // Dedupe: the same id must never get two budget rows.
    final ids = categoryIds.toSet().toList();
    final needIds = ids.where((id) => needs.contains(id)).toList();
    final wantIds = ids.where((id) => !needs.contains(id)).toList();

    final perNeed =
        needIds.isEmpty ? 0.0 : income * 0.50 / needIds.length;
    final perWant =
        wantIds.isEmpty ? 0.0 : income * 0.30 / wantIds.length;

    final out = <BudgetSuggestion>[];
    for (final id in needIds) {
      out.add(_forCategory(id, 'needs', perNeed, avg3m));
    }
    for (final id in wantIds) {
      out.add(_forCategory(id, 'wants', perWant, avg3m));
    }
    final savings = income * 0.20;
    out.add(BudgetSuggestion(
      categoryId: savingsId,
      bucket: 'savings',
      ruleShare: savings,
      threeMonthAvg: 0,
      amount: _round10(savings),
    ));
    return out;
  }

  static BudgetSuggestion _forCategory(
    String id,
    String bucket,
    double ruleShare,
    Map<String, double> avg3m,
  ) {
    final avg = avg3m[id] ?? 0.0;
    final amount = ruleShare > avg ? ruleShare : avg;
    return BudgetSuggestion(
      categoryId: id,
      bucket: bucket,
      ruleShare: ruleShare,
      threeMonthAvg: avg,
      amount: _round10(amount),
    );
  }

  static double _round10(double v) => (v / 10).round() * 10.0;
}
