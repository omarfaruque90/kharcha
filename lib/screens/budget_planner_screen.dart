import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/budget_planner_service.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Package AJ: AI budget planner.
///
/// Takes a monthly income, suggests per-category budgets via the 50/30/20
/// rule adjusted by the last-3-month actuals, lets the user tweak each with
/// a slider, then one-tap "Apply as budgets" replaces this month's budgets.
class BudgetPlannerScreen extends StatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  State<BudgetPlannerScreen> createState() => _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends State<BudgetPlannerScreen> {
  final _incomeCtrl = TextEditingController();
  List<BudgetSuggestion> _suggestions = [];
  bool _initialized = false;
  bool _applying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final now = DateTime.now();
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final money = context.read<MoneyProvider>();
    final expenses = context.read<ExpenseProvider>();

    // Average monthly spend per category over the previous 3 months.
    final avg3m = <String, double>{};
    for (var i = 1; i <= 3; i++) {
      final m = DateTime(now.year, now.month - i);
      for (final e in expenses.totalsByCategory(m).entries) {
        avg3m[e.key] = (avg3m[e.key] ?? 0) + e.value / 3;
      }
    }

    // Prefill income from this month's recorded income (editable).
    final income = money.incomeForMonth(monthKey);
    if (income > 0) {
      _incomeCtrl.text = income.toStringAsFixed(0);
    }
    _rebuild(income);
  }

  @override
  void dispose() {
    _incomeCtrl.dispose();
    super.dispose();
  }

  List<String> _categoryIds() => [
        ...kCategories.map((c) => c.id),
        ...CustomCategoryRegistry.all.map((c) => c.id),
      ];

  Map<String, double> _avg3m() {
    final now = DateTime.now();
    final expenses = context.read<ExpenseProvider>();
    final avg3m = <String, double>{};
    for (var i = 1; i <= 3; i++) {
      final m = DateTime(now.year, now.month - i);
      for (final e in expenses.totalsByCategory(m).entries) {
        avg3m[e.key] = (avg3m[e.key] ?? 0) + e.value / 3;
      }
    }
    return avg3m;
  }

  void _rebuild(double income) {
    setState(() {
      _suggestions = BudgetPlannerService.suggest(
        monthlyIncome: income,
        categoryIds: _categoryIds(),
        avg3m: _avg3m(),
      );
    });
  }

  double get _income => double.tryParse(_incomeCtrl.text) ?? 0;

  double _bucketTotal(String bucket) => _suggestions
      .where((s) => s.bucket == bucket)
      .fold(0.0, (sum, s) => sum + s.amount);

  double _sliderMax(BudgetSuggestion s) {
    final base = _income * 0.6;
    final m = s.amount * 1.6 > base ? s.amount * 1.6 : base;
    return m <= 0 ? 1000.0 : m;
  }

  /// Deletes this month's budgets and inserts the planner amounts.
  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);
    final lang = context.read<SettingsProvider>().language;
    try {
      final now = DateTime.now();
      final monthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final money = context.read<MoneyProvider>();

      for (final b in money.budgetsForMonth(monthKey)) {
        await money.removeBudget(b.id!);
      }
      for (final s in _suggestions) {
        if (s.categoryId == BudgetPlannerService.savingsId) continue;
        if (s.amount <= 0) continue;
        await money.upsertBudget(Budget(
          id: Budget.newId(),
          categoryId: s.categoryId,
          monthKey: monthKey,
          limitAmount: s.amount,
        ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_btr(lang, 'bp_applied')
                .replaceAll('{month}', monthLong(now, lang))),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final needs = _suggestions.where((s) => s.bucket == 'needs').toList();
    final wants = _suggestions.where((s) => s.bucket == 'wants').toList();
    final savings = _suggestions.where((s) => s.bucket == 'savings').toList();
    final planned = needs.fold(0.0, (a, s) => a + s.amount) +
        wants.fold(0.0, (a, s) => a + s.amount);

    return Scaffold(
      appBar: AppBar(title: Text(_btr(lang, 'bp_title'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          StaggeredEntrance(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _btr(lang, 'bp_income_label'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _incomeCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: '৳ ',
                        hintText: _btr(lang, 'bp_income_hint'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          _rebuild(double.tryParse(v) ?? 0),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_btr(lang, 'bp_planned')}: ${formatMoney(planned)}'
                      ' (${_btr(lang, 'bp_of_income')})',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            delayMs: 60,
            child: _bucketChips(lang, theme),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            delayMs: 120,
            child: _sectionCard(
              lang,
              theme,
              title: _btr(lang, 'bp_needs'),
              target: _income * 0.50,
              total: _bucketTotal('needs'),
              items: needs,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            delayMs: 180,
            child: _sectionCard(
              lang,
              theme,
              title: _btr(lang, 'bp_wants'),
              target: _income * 0.30,
              total: _bucketTotal('wants'),
              items: wants,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            delayMs: 240,
            child: _sectionCard(
              lang,
              theme,
              title: _btr(lang, 'bp_savings'),
              target: _income * 0.20,
              total: _bucketTotal('savings'),
              items: savings,
              note: _btr(lang, 'bp_savings_note'),
            ),
          ),
          const SizedBox(height: 16),
          StaggeredEntrance(
            delayMs: 300,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kGold, kGoldLight],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: kGold.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _applying ? null : _apply,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _applying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: kDeepGreenDark,
                              ),
                            )
                          : Text(
                              _btr(lang, 'bp_apply'),
                              style: const TextStyle(
                                color: kDeepGreenDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bucketChips(String lang, ThemeData theme) {
    Widget chip(String label, double value, double target) {
      final over = target > 0 && value > target;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: over
                  ? Colors.red.withValues(alpha: 0.5)
                  : kGold.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatMoney(value),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: over ? Colors.red : kGold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(_btr(lang, 'bp_needs'), _bucketTotal('needs'), _income * 0.50),
        const SizedBox(width: 8),
        chip(_btr(lang, 'bp_wants'), _bucketTotal('wants'), _income * 0.30),
        const SizedBox(width: 8),
        chip(_btr(lang, 'bp_savings'), _bucketTotal('savings'),
            _income * 0.20),
      ],
    );
  }

  Widget _sectionCard(
    String lang,
    ThemeData theme, {
    required String title,
    required double target,
    required double total,
    required List<BudgetSuggestion> items,
    String? note,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${formatMoney(total)} / ${formatMoney(target)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: total > target && target > 0
                        ? Colors.red
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++)
              _sliderRow(lang, theme, items[i]),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow(
      String lang, ThemeData theme, BudgetSuggestion s) {
    final cat = categoryById(s.categoryId);
    final max = _sliderMax(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(cat.icon, size: 18, color: cat.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.categoryId == BudgetPlannerService.savingsId
                        ? _btr(lang, 'bp_savings')
                        : CustomCategoryRegistry.displayName(
                            s.categoryId, lang),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (s.threeMonthAvg > 0)
                    Text(
                      '${_btr(lang, 'bp_avg_3m')}: '
                      '${formatMoney(s.threeMonthAvg)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              formatMoney(s.amount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: kGold,
              ),
            ),
          ],
        ),
        Slider(
          value: s.amount.clamp(0.0, max),
          min: 0,
          max: max,
          divisions: 100,
          activeColor: kGold,
          inactiveColor:
              theme.colorScheme.outline.withValues(alpha: 0.3),
          label: formatMoney(s.amount),
          onChanged: (v) => setState(() => s.amount = (v / 10).round() * 10.0),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Package AJ: proposed AppStrings keys — add them to
// lib/l10n/app_strings.dart ('en'/'bn' maps); the local map keeps the screen
// working until then. (Same pattern as Package U's _yrStrings.)
// ---------------------------------------------------------------------------
const Map<String, Map<String, String>> _bpStrings = {
  'en': {
    'bp_title': 'AI Budget Planner',
    'bp_income_label': 'Monthly income',
    'bp_income_hint': 'Enter your monthly income',
    'bp_planned': 'Planned',
    'bp_of_income': 'of income',
    'bp_needs': 'Needs (50%)',
    'bp_wants': 'Wants (30%)',
    'bp_savings': 'Savings (20%)',
    'bp_savings_note': 'Suggested savings — not stored as a budget.',
    'bp_avg_3m': '3-month avg',
    'bp_apply': 'Apply as budgets',
    'bp_applied': 'Budgets applied for {month}.',
  },
  'bn': {
    'bp_title': 'এআই বাজেট প্ল্যানার',
    'bp_income_label': 'মাসিক আয়',
    'bp_income_hint': 'আপনার মাসিক আয় লিখুন',
    'bp_planned': 'পরিকল্পিত',
    'bp_of_income': 'আয়ের',
    'bp_needs': 'প্রয়োজন (৫০%)',
    'bp_wants': 'চাহিদা (৩০%)',
    'bp_savings': 'সঞ্চয় (২০%)',
    'bp_savings_note': 'প্রস্তাবিত সঞ্চয় — বাজেট হিসেবে সংরক্ষণ হয় না।',
    'bp_avg_3m': '৩ মাসের গড়',
    'bp_apply': 'বাজেট হিসেবে প্রয়োগ করুন',
    'bp_applied': '{month} মাসের বাজেট প্রয়োগ হয়েছে।',
  },
};

String _btr(String lang, String key) =>
    _bpStrings[lang]?[key] ?? _bpStrings['en']![key] ?? key;
