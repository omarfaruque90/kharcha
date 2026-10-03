import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../db/database_helper.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_center.dart';
import '../theme/design_tokens.dart';
import '../utils/formatters.dart';
import '../widgets/expense_tile.dart';
import '../widgets/hero_balance_card.dart';
import '../widgets/motion.dart';
import '../widgets/smart_search.dart';
import '../widgets/spending_insights.dart';
import '../widgets/budget_forecast_card.dart';
import 'budget_screen.dart';
import 'calendar_screen.dart';
import 'debts_screen.dart';
import 'goals_screen.dart';
import 'income_screen.dart';
import 'notifications_screen.dart';
import 'receipts_screen.dart';
import 'recurring_screen.dart';
import 'reminder_screen.dart';
import 'reports_screen.dart';
import 'split_bill_screen.dart';
import 'subscriptions_screen.dart';
import 'templates_screen.dart';
import 'wishlist_screen.dart';
import 'salary_screen.dart';
import 'voice_report_screen.dart';
import 'achievements_screen.dart';
import 'challenge_screen.dart';
import 'cash_screen.dart';
import 'emergency_screen.dart';
import 'fuel_screen.dart';
import 'shopping_screen.dart';
import 'gifts_screen.dart';
import 'projects_screen.dart';
import 'expense_map_screen.dart';
import 'medical_screen.dart';
import 'converter_screen.dart';
import 'tip_screen.dart';
import 'budget_planner_screen.dart';
import 'ai_chat_screen.dart';
import 'leaderboard_screen.dart';
import 'public_templates_screen.dart';
import 'tax_helper_screen.dart';
import 'dues_screen.dart';
import 'places_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onAddPressed;

  const HomeScreen({super.key, this.onAddPressed});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// One money-tool shortcut: icon, label key, and the screen it opens.
class _ToolDef {
  final IconData icon;
  final String labelKey;
  final Widget Function() build;

  const _ToolDef(this.icon, this.labelKey, this.build);
}

/// A section of the money-tools grid: Bangla-first header + tools.
class _ToolSection {
  final String titleKey;
  final IconData icon;
  final List<_ToolDef> tools;

  const _ToolSection(this.titleKey, this.icon, this.tools);
}

/// All 34 money-tool shortcuts (33 originals + Reports), reorganized into four sections
/// (nothing dropped, nothing renamed — only grouped). Plus a Reports
/// shortcut in Insights.
List<_ToolSection> _toolSections() => [
      _ToolSection(
        'tools_section_track',
        Icons.track_changes_outlined,
        [
          _ToolDef(Icons.handshake_outlined, 'debts_title',
              () => const DebtsScreen()),
          _ToolDef(Icons.people_outline, 'split_title',
              () => const SplitBillScreen()),
          _ToolDef(Icons.subscriptions_outlined, 'subs_title',
              () => const SubscriptionsScreen()),
          _ToolDef(Icons.calendar_month_outlined, 'cal_title',
              () => const CalendarScreen()),
          _ToolDef(Icons.receipt_long_outlined, 'receipts_title',
              () => const ReceiptsScreen()),
          _ToolDef(Icons.event_note_outlined, 'dues_title',
              () => const DuesScreen()),
          _ToolDef(Icons.notifications_none_outlined, 'reminder_title',
              () => const ReminderScreen()),
        ],
      ),
      _ToolSection(
        'tools_section_plan',
        Icons.edit_calendar_outlined,
        [
          _ToolDef(Icons.account_balance_wallet_outlined, 'budget_title',
              () => const BudgetScreen()),
          _ToolDef(Icons.trending_up, 'income_title',
              () => const IncomeScreen()),
          _ToolDef(Icons.event_repeat_outlined, 'recurring_title',
              () => const RecurringScreen()),
          _ToolDef(Icons.savings_outlined, 'goals_title',
              () => const GoalsScreen()),
          _ToolDef(Icons.card_giftcard_outlined, 'wish_title',
              () => const WishlistScreen()),
          _ToolDef(Icons.bolt_outlined, 'tpl_title',
              () => const TemplatesScreen()),
          _ToolDef(Icons.payments_outlined, 'salary_title',
              () => const SalaryScreen()),
          _ToolDef(Icons.auto_awesome_outlined, 'bp_title',
              () => const BudgetPlannerScreen()),
        ],
      ),
      _ToolSection(
        'tools_section_insights',
        Icons.insights_outlined,
        [
          _ToolDef(Icons.chat_bubble_outline, 'ai_title',
              () => const AiChatScreen()),
          _ToolDef(Icons.mic_outlined, 'voice_title',
              () => const VoiceReportScreen()),
          _ToolDef(Icons.bar_chart_outlined, 'nav_reports',
              () => const ReportsScreen()),
        ],
      ),
      _ToolSection(
        'tools_section_tools',
        Icons.handyman_outlined,
        [
          _ToolDef(Icons.currency_exchange_outlined, 'conv_title',
              () => const ConverterScreen()),
          _ToolDef(Icons.percent_outlined, 'tip_title',
              () => const TipScreen()),
          _ToolDef(Icons.local_gas_station_outlined, 'fuel_title',
              () => const FuelScreen()),
          _ToolDef(Icons.shopping_cart_outlined, 'shop_title',
              () => const ShoppingScreen()),
          _ToolDef(Icons.card_giftcard_outlined, 'gift_title',
              () => const GiftsScreen()),
          _ToolDef(Icons.wallet_outlined, 'cash_title',
              () => const CashScreen()),
          _ToolDef(Icons.shield_outlined, 'vault_title',
              () => const EmergencyScreen()),
          _ToolDef(Icons.medical_services_outlined, 'medical_title',
              () => const MedicalScreen()),
          _ToolDef(Icons.work_outline, 'projects_title',
              () => const ProjectsScreen()),
          _ToolDef(Icons.map_outlined, 'expense_map_title',
              () => const ExpenseMapScreen()),
          _ToolDef(Icons.timer_outlined, 'challenge_title',
              () => const ChallengeScreen()),
          _ToolDef(Icons.emoji_events_outlined, 'ach_title',
              () => const AchievementsScreen()),
          _ToolDef(Icons.location_on_outlined, 'places_title',
              () => const PlacesScreen()),
          _ToolDef(Icons.leaderboard_outlined, 'leaderboard_title',
              () => const LeaderboardScreen()),
          _ToolDef(Icons.public_outlined, 'templates_public',
              () => const PublicTemplatesScreen()),
          _ToolDef(Icons.receipt_long_outlined, 'tax_title',
              () => const TaxHelperScreen()),
        ],
      ),
    ];

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
            tooltip: lang == 'bn' ? 'English' : 'বাংলা',
            icon: const Icon(Icons.translate),
            onPressed: () => settings.setLanguage(lang == 'bn' ? 'en' : 'bn'),
          ),
        ],
      ),
      // Prominent gold add-expense button: always one tap away.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAddPressed,
        backgroundColor: kGold,
        foregroundColor: kDeepGreenDark,
        icon: const Icon(Icons.add),
        label: Text(
          tr(context, 'add_expense'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
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
              child: SpendingInsights(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BudgetForecastCard(),
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
          // Money tools: sectioned grid (Bangla-first headers).
          for (final section in _toolSections()) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: KSection.header(
                  context,
                  icon: section.icon,
                  title: tr(context, section.titleKey),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.85,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final tool = section.tools[i];
                    return StaggeredEntrance(
                      key: ValueKey('${section.titleKey}-$i'),
                      delayMs: (i * 35).clamp(0, 300).toInt(),
                      child: _ToolTile(
                        icon: tool.icon,
                        label: tr(context, tool.labelKey),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => tool.build()),
                        ),
                      ),
                    );
                  },
                  childCount: section.tools.length,
                ),
              ),
            ),
          ],
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
                  for (final c in kCategories)
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

/// One tile in the money-tools grid: icon + short text label
/// (never icon-only), comfortably above the 48dp touch target.
class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolTile({
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
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KSpacing.xs,
            vertical: 10,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(KRadius.chip),
                ),
                child:
                    Icon(icon, color: theme.colorScheme.primary, size: 22),
              ),
              const SizedBox(height: 6),
              // Flexible keeps long labels (e.g. "পুনরাবৃত্ত খরচ")
              // inside the tile instead of overflowing it.
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                    fontSize: 10.5,
                    height: 1.25,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
