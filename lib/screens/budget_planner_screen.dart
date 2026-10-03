import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Manual budget planner — nothing is pre-set.
/// The user adds categories themselves and sets each amount by hand,
/// then one-tap "Apply as budgets" replaces this month's budgets.
class BudgetPlannerScreen extends StatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  State<BudgetPlannerScreen> createState() => _BudgetPlannerScreenState();
}

class _PlanItem {
  final String categoryId;
  double amount = 0;
  _PlanItem(this.categoryId);
}

class _BudgetPlannerScreenState extends State<BudgetPlannerScreen> {
  final _incomeCtrl = TextEditingController();
  final List<_PlanItem> _items = [];
  bool _applying = false;

  @override
  void dispose() {
    _incomeCtrl.dispose();
    super.dispose();
  }

  double get _income => double.tryParse(_incomeCtrl.text) ?? 0;
  double get _planned => _items.fold(0.0, (a, s) => a + s.amount);

  /// Fixed slider max from income only — never shifts while dragging,
  /// so the slider stays fully manual and predictable.
  double _sliderMax(_PlanItem s) {
    final m = _income > 0 ? _income : 10000.0;
    // Always allow at least the current amount.
    return s.amount > m ? s.amount * 1.2 : m;
  }

  /// Tap the amount to type an exact value.
  Future<void> _editAmount(_PlanItem s) async {
    final lang = context.read<SettingsProvider>().language;
    final ctrl = TextEditingController(
        text: s.amount > 0 ? s.amount.toStringAsFixed(0) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(CustomCategoryRegistry.displayName(
            s.categoryId, lang)),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '৳ '),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppStrings.get('cancel', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                c, double.tryParse(ctrl.text.trim()) ?? 0),
            child: Text(AppStrings.get('save', lang)),
          ),
        ],
      ),
    );
    if (result != null && result >= 0 && mounted) {
      setState(() => s.amount = result);
    }
  }

  List<String> _availableCategories() {
    final added = _items.map((e) => e.categoryId).toSet();
    return [
      ...CustomCategoryRegistry.visibleBuiltinCategories()
          .map((c) => c.id),
      ...CustomCategoryRegistry.all.map((c) => c.id),
    ].where((id) => !added.contains(id)).toList();
  }

  Future<void> _addCategory() async {
    final lang = context.read<SettingsProvider>().language;
    final available = _availableCategories();
    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_btr(lang, 'bp_all_added'))),
        );
      }
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _btr(lang, 'bp_pick_category'),
                style: Theme.of(c).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            for (final id in available)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: categoryById(id)
                        .color
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    categoryById(id).icon,
                    size: 18,
                    color: categoryById(id).color,
                  ),
                ),
                title: Text(
                    CustomCategoryRegistry.displayName(id, lang)),
                onTap: () => Navigator.pop(c, id),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _items.add(_PlanItem(picked)));
    }
  }

  /// Deletes this month's budgets and inserts the planner amounts.
  Future<void> _apply() async {
    if (_applying || _items.isEmpty) return;
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
      for (final s in _items) {
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
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      decoration: InputDecoration(
                        prefixText: '৳ ',
                        hintText: _btr(lang, 'bp_income_hint'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_btr(lang, 'bp_planned')}: ${formatMoney(_planned)}',
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
          // Add-category button.
          StaggeredEntrance(
            delayMs: 60,
            child: OutlinedButton.icon(
              onPressed: _addCategory,
              icon: const Icon(Icons.add),
              label: Text(_btr(lang, 'bp_add_category')),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Manual category rows.
          if (_items.isEmpty)
            StaggeredEntrance(
              delayMs: 120,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.tune,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _btr(lang, 'bp_empty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            StaggeredEntrance(
              delayMs: 120,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        _sliderRow(lang, theme, _items[i], i),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_items.isNotEmpty)
            StaggeredEntrance(
              delayMs: 180,
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
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
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

  Widget _sliderRow(
      String lang, ThemeData theme, _PlanItem s, int index) {
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
              child: Text(
                CustomCategoryRegistry.displayName(
                    s.categoryId, lang),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _editAmount(s),
              child: Text(
                formatMoney(s.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kGold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () =>
                  setState(() => _items.removeAt(index)),
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
          onChanged: (v) => setState(() {
            s.amount = (v / 10).round() * 10.0;
          }),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Budget planner strings.
// ---------------------------------------------------------------------------
const Map<String, Map<String, String>> _bpStrings = {
  'en': {
    'bp_title': 'Budget Planner',
    'bp_income_label': 'Monthly income',
    'bp_income_hint': 'Enter your monthly income',
    'bp_planned': 'Planned',
    'bp_add_category': 'Add category',
    'bp_pick_category': 'Choose a category',
    'bp_empty':
        'No categories yet.\nTap "Add category" and set your own budget for each.',
    'bp_all_added': 'All categories are already added.',
    'bp_apply': 'Apply as budgets',
    'bp_applied': 'Budgets applied for {month}.',
  },
  'bn': {
    'bp_title': 'বাজেট প্ল্যানার',
    'bp_income_label': 'মাসিক আয়',
    'bp_income_hint': 'আপনার মাসিক আয় লিখুন',
    'bp_planned': 'পরিকল্পিত',
    'bp_add_category': 'ক্যাটাগরি যোগ করুন',
    'bp_pick_category': 'একটি ক্যাটাগরি বেছে নিন',
    'bp_empty':
        'এখনো কোনো ক্যাটাগরি নেই।\n"ক্যাটাগরি যোগ করুন" চাপুন এবং নিজে বাজেট ঠিক করুন।',
    'bp_all_added': 'সব ক্যাটাগরি ইতিমধ্যে যোগ করা হয়েছে।',
    'bp_apply': 'বাজেট হিসেবে প্রয়োগ করুন',
    'bp_applied': '{month} মাসের বাজেট প্রয়োগ হয়েছে।',
  },
};

String _btr(String lang, String key) =>
    _bpStrings[lang]?[key] ?? _bpStrings['en']![key] ?? key;
