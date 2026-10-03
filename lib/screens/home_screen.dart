import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
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
  const HomeScreen({super.key});

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
            const Text('Kharcha'),
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: StaggeredEntrance(
              delayMs: 240,
              child: _BalanceCard(
                balance: money.incomeForMonth(monthKeyOf(DateTime.now())) -
                    expenses.totalThisMonth(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr(context, 'money_tools'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(context, 'no_expenses'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            tr(context, 'no_expenses_sub'),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
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
                                  const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _dayHeader(day, lang),
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    formatMoney(dayTotal),
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
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

/// Full-width monthly balance card (income − expense), gold-accented.
class _BalanceCard extends StatelessWidget {
  final double balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BrandGradientCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet,
              color: theme.colorScheme.onSecondaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            tr(context, 'balance_title'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const Spacer(),
          Text(
            formatMoney(balance),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
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
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
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
