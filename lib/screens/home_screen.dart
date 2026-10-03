import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../db/database_helper.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_center.dart';
import '../utils/formatters.dart';
import '../widgets/expense_tile.dart';
import '../widgets/hero_balance_card.dart';
import '../widgets/calculator_sheet.dart';
import '../widgets/money_overview.dart';
import '../widgets/monthly_balance_card.dart';
import '../widgets/motion.dart';
import '../widgets/smart_search.dart';
import '../widgets/spending_insights.dart';
import '../widgets/budget_forecast_card.dart';
import 'ai_chat_screen.dart';
import 'achievements_screen.dart';
import 'budget_planner_screen.dart';
import 'budget_screen.dart';
import 'calendar_screen.dart';
import 'cash_screen.dart';
import 'goals_screen.dart';
import 'leaderboard_screen.dart';
import 'notes_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'wishlist_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onAddPressed;

  const HomeScreen({super.key, this.onAddPressed});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _categoryId; // null = all categories

  @override
  void initState() {
    super.initState();
    // Prime the notification bell badge.
    NotificationCenter.refreshUnread();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// BS: long-press on the AppBar title for quick profile switching.
  Future<void> _quickProfileSwitch(BuildContext context) async {
    final profiles = await DatabaseHelper.getProfiles();
    if (profiles.length < 2 || !context.mounted) return;
    final current = DatabaseHelper.instance.activeProfile;
    await showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'profile_switch')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in profiles)
              ListTile(
                dense: true,
                leading: Icon(
                  p == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Theme.of(dctx).colorScheme.primary,
                ),
                title: Text(p == 'personal'
                    ? tr(dctx, 'profile_personal')
                    : p),
                onTap: () async {
                  Navigator.pop(dctx);
                  if (p == current) return;
                  await DatabaseHelper.instance.setProfile(p);
                  if (!context.mounted) return;
                  await context.read<ExpenseProvider>().load();
                  if (!context.mounted) return;
                  await context.read<MoneyProvider>().load();
                  if (!context.mounted) return;
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
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

    final filtered = expenses.filtered(categoryId: _categoryId);
    final groups = <DateTime, List<Expense>>{};
    for (final e in filtered) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      (groups[d] ??= []).add(e);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final monthKey = monthKeyOf(DateTime.now());
    final balance =
        money.incomeForMonth(monthKey) - expenses.totalThisMonth();
    final budget = money.monthlyBudgetFor(monthKey);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr(context, 'nav_settings'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SettingsScreen(),
            ),
          ),
        ),
        title: GestureDetector(
          onLongPress: () => _quickProfileSwitch(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Khorcha'),
              Text(tr(context, 'tagline'), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: NotificationCenter.unreadCount,
            builder: (context, count, _) {
              return IconButton(
                tooltip: tr(context, 'notifications'),
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 99 ? '99+' : '$count'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  await NotificationCenter.refreshUnread();
                },
              );
            },
          ),
          IconButton(
            tooltip: tr(context, 'ai_title'),
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AiChatScreen(),
              ),
            ),
          ),
        ],
      ),
      // Add lives in the bottom nav — no duplicate FAB.
      body: CustomScrollView(
        slivers: [
          // Premium hero: balance count-up + quick stats.
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: StaggeredEntrance(
                child: HeroBalanceCard(
                  balance: balance,
                  todaySpent: expenses.totalOn(DateTime.now()),
                  weekSpent: expenses.totalThisWeek(),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: MoneyOverviewCard(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: MonthlyBalanceCard(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SpendingInsights(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BudgetForecastCard(),
            ),
          ),
          // Quick shortcuts the user wants pinned on home.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
              child: SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 16),
                  children: [
                    _QuickShortcut(
                      icon: Icons.calculate_outlined,
                      labelKey: 'calculator_title',
                      onTap: () => CalculatorSheet.show(context),
                    ),
                    _QuickShortcut(
                      icon: Icons.calendar_month_outlined,
                      labelKey: 'cal_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CalendarScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.note_alt_outlined,
                      labelKey: 'notes_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotesScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.emoji_events_outlined,
                      labelKey: 'ach_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AchievementsScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.leaderboard_outlined,
                      labelKey: 'leaderboard_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LeaderboardScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.wallet_outlined,
                      labelKey: 'cash_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CashScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.card_giftcard_outlined,
                      labelKey: 'wish_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WishlistScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.savings_outlined,
                      labelKey: 'goals_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const GoalsScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.account_balance_wallet_outlined,
                      labelKey: 'budget_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BudgetScreen()),
                      ),
                    ),
                    _QuickShortcut(
                      icon: Icons.auto_awesome_outlined,
                      labelKey: 'bp_title',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BudgetPlannerScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (budget != null && budget.limitAmount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: StaggeredEntrance(
                  delayMs: 120,
                  child: _MonthlyBudgetProgress(
                    spent: expenses.totalThisMonth(),
                    limit: budget.limitAmount,
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
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
                      onSelected: (_) =>
                          setState(() => _categoryId = null),
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
                        onSelected: (_) => setState(
                          () =>
                              _categoryId = _categoryId == c.id ? null : c.id,
                        ),
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
                        onSelected: (_) => setState(
                          () => _categoryId =
                              _categoryId == cc.id ? null : cc.id,
                        ),
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
                childCount: days.length,
              ),
            ),
          // Clearance so the gold FAB never covers the last row.
          const SliverToBoxAdapter(
            child: SizedBox(height: 88),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal shortcut tile pinned on the home screen.
class _QuickShortcut extends StatelessWidget {
  final IconData icon;
  final String labelKey;
  final VoidCallback onTap;

  const _QuickShortcut({
    required this.icon,
    required this.labelKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: kGold.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kGoldDark, size: 20),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  tr(context, labelKey),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
