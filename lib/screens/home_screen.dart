import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/brand_gradient_card.dart';
import '../widgets/expense_tile.dart';
import '../widgets/motion.dart';
import '../widgets/summary_card.dart';
import 'budget_screen.dart';
import 'goals_screen.dart';
import 'income_screen.dart';
import 'recurring_screen.dart';
import 'reminder_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onAddPressed;

  const HomeScreen({super.key, this.onAddPressed});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryId; // null = all categories

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
    final money = context.watch<MoneyProvider>();
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final theme = Theme.of(context);

    final filtered = expenses.filtered(query: _query, categoryId: _categoryId);
    final groups = <DateTime, List<Expense>>{};
    for (final e in filtered) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      (groups[d] ??= []).add(e);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Khorcha'),
            Text(tr(context, 'tagline'), style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: lang == 'bn' ? 'English' : 'বাংলা',
            icon: const Icon(Icons.translate),
            onPressed: () => settings.setLanguage(lang == 'bn' ? 'en' : 'bn'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: StaggeredEntrance(
                    delayMs: 0,
                    child: SummaryCard(
                      title: tr(context, 'today'),
                      amount: expenses.totalOn(DateTime.now()),
                      icon: Icons.today,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StaggeredEntrance(
                    delayMs: 90,
                    child: SummaryCard(
                      title: tr(context, 'this_week'),
                      amount: expenses.totalThisWeek(),
                      icon: Icons.date_range,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StaggeredEntrance(
                    delayMs: 180,
                    child: SummaryCard(
                      title: tr(context, 'this_month'),
                      amount: expenses.totalThisMonth(),
                      icon: Icons.calendar_month,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: StaggeredEntrance(
              delayMs: 240,
              child: _BalanceCard(
                balance: money.incomeForMonth(monthKeyOf(DateTime.now())) -
                    expenses.totalThisMonth(),
              ),
            ),
          ),
          Builder(
            builder: (context) {
              final key = monthKeyOf(DateTime.now());
              final budget = money.monthlyBudgetFor(key);
              if (budget == null || budget.limitAmount <= 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: StaggeredEntrance(
                  delayMs: 300,
                  child: _MonthlyBudgetProgress(
                    spent: expenses.totalThisMonth(),
                    limit: budget.limitAmount,
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr(context, 'money_tools'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                _MoneyShortcut(
                  icon: Icons.account_balance_wallet_outlined,
                  label: tr(context, 'budget_title'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BudgetScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MoneyShortcut(
                  icon: Icons.trending_up,
                  label: tr(context, 'income_title'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const IncomeScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MoneyShortcut(
                  icon: Icons.event_repeat_outlined,
                  label: tr(context, 'recurring_title'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RecurringScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MoneyShortcut(
                  icon: Icons.savings_outlined,
                  label: tr(context, 'goals_title'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const GoalsScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MoneyShortcut(
                  icon: Icons.notifications_none_outlined,
                  label: tr(context, 'reminder_title'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReminderScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: tr(context, 'search_hint'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
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
                for (final c in kCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(AppStrings.categoryName(c.id, lang)),
                      avatar: Icon(c.icon, size: 16),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(
                        () => _categoryId = _categoryId == c.id ? null : c.id,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: days.isEmpty
                ? Center(
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 40),
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
                  )
                : ListView.builder(
                    itemCount: days.length,
                    itemBuilder: (ctx, i) {
                      final day = days[i];
                      final items = groups[day]!;
                      final dayTotal =
                          items.fold(0.0, (sum, e) => sum + e.amount);
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
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Text(
                                    formatMoney(dayTotal),
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
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
                  ),
          ),
        ],
      ),
    );
  }
}

/// Full-width monthly balance card (income − expense): rich deep-green
/// hero with gold accents and large elegant balance typography.
class _BalanceCard extends StatelessWidget {
  final double balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BrandGradientCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: kGold.withValues(alpha: 0.45),
              ),
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: kGold,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'balance_title'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                    color: kGoldLight.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatMoney(balance),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Monthly budget progress bar on the home screen.
/// Only rendered when the user has set an overall monthly budget.
class _MonthlyBudgetProgress extends StatelessWidget {
  final double spent;
  final double limit;

  const _MonthlyBudgetProgress({
    required this.spent,
    required this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = (spent / limit).clamp(0.0, 1.0);
    final over = spent > limit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.savings_outlined,
                      size: 18, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, 'monthly_budget'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Text(
                  '${formatMoney(spent)} / ${formatMoney(limit)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: over ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  over ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One shortcut tile in the home "Money tools" row.
class _MoneyShortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MoneyShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableScale(
      onTap: onTap,
      child: Card(
        child: Container(
          width: 108,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                    icon, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
