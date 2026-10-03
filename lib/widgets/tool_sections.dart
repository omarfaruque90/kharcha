import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import 'motion.dart';
import '../screens/budget_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/debts_screen.dart';
import '../screens/goals_screen.dart';
import '../screens/income_screen.dart';
import '../screens/receipts_screen.dart';
import '../screens/recurring_screen.dart';
import '../screens/reminder_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/split_bill_screen.dart';
import '../screens/subscriptions_screen.dart';
import '../screens/templates_screen.dart';
import '../screens/wishlist_screen.dart';
import '../screens/salary_screen.dart';
import '../screens/voice_report_screen.dart';
import '../screens/achievements_screen.dart';
import '../screens/challenge_screen.dart';
import '../screens/cash_screen.dart';
import '../screens/emergency_screen.dart';
import '../screens/fuel_screen.dart';
import '../screens/shopping_screen.dart';
import '../screens/gifts_screen.dart';
import '../screens/projects_screen.dart';
import '../screens/expense_map_screen.dart';
import '../screens/medical_screen.dart';
import '../screens/converter_screen.dart';
import '../screens/tip_screen.dart';
import '../screens/budget_planner_screen.dart';
import '../screens/ai_chat_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/public_templates_screen.dart';
import '../screens/tax_helper_screen.dart';
import '../screens/dues_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/places_screen.dart';

/// One money-tool shortcut: icon, label key, and the screen it opens.
class ToolDef {
  final IconData icon;
  final String labelKey;
  final Widget Function() build;

  const ToolDef(this.icon, this.labelKey, this.build);
}

/// A section of the money-tools grid: Bangla-first header + tools.
class ToolSection {
  final String titleKey;
  final IconData icon;
  final List<ToolDef> tools;

  const ToolSection(this.titleKey, this.icon, this.tools);
}

/// All 34 money-tool shortcuts, reorganized into four sections
/// (nothing dropped, nothing renamed — only grouped). Plus a Reports
/// shortcut in Insights.
List<ToolSection> toolSections() => [
      ToolSection(
        'tools_section_track',
        Icons.track_changes_outlined,
        [
          ToolDef(Icons.handshake_outlined, 'debts_title',
              () => const DebtsScreen()),
          ToolDef(Icons.people_outline, 'split_title',
              () => const SplitBillScreen()),
          ToolDef(Icons.subscriptions_outlined, 'subs_title',
              () => const SubscriptionsScreen()),
          ToolDef(Icons.calendar_month_outlined, 'cal_title',
              () => const CalendarScreen()),
          ToolDef(Icons.receipt_long_outlined, 'receipts_title',
              () => const ReceiptsScreen()),
          ToolDef(Icons.event_note_outlined, 'dues_title',
              () => const DuesScreen()),
          ToolDef(Icons.notifications_none_outlined, 'reminder_title',
              () => const ReminderScreen()),
        ],
      ),
      ToolSection(
        'tools_section_plan',
        Icons.edit_calendar_outlined,
        [
          ToolDef(Icons.account_balance_wallet_outlined, 'budget_title',
              () => const BudgetScreen()),
          ToolDef(Icons.trending_up, 'income_title',
              () => const IncomeScreen()),
          ToolDef(Icons.event_repeat_outlined, 'recurring_title',
              () => const RecurringScreen()),
          ToolDef(Icons.savings_outlined, 'goals_title',
              () => const GoalsScreen()),
          ToolDef(Icons.card_giftcard_outlined, 'wish_title',
              () => const WishlistScreen()),
          ToolDef(Icons.bolt_outlined, 'tpl_title',
              () => const TemplatesScreen()),
          ToolDef(Icons.payments_outlined, 'salary_title',
              () => const SalaryScreen()),
          ToolDef(Icons.auto_awesome_outlined, 'bp_title',
              () => const BudgetPlannerScreen()),
        ],
      ),
      ToolSection(
        'tools_section_insights',
        Icons.insights_outlined,
        [
          ToolDef(Icons.chat_bubble_outline, 'ai_title',
              () => const AiChatScreen()),
          ToolDef(Icons.mic_outlined, 'voice_title',
              () => const VoiceReportScreen()),
          ToolDef(Icons.bar_chart_outlined, 'nav_reports',
              () => const ReportsScreen()),
        ],
      ),
      ToolSection(
        'tools_section_tools',
        Icons.handyman_outlined,
        [
          ToolDef(Icons.note_alt_outlined, 'notes_title',
              () => const NotesScreen()),
          ToolDef(Icons.currency_exchange_outlined, 'conv_title',
              () => const ConverterScreen()),
          ToolDef(Icons.percent_outlined, 'tip_title',
              () => const TipScreen()),
          ToolDef(Icons.local_gas_station_outlined, 'fuel_title',
              () => const FuelScreen()),
          ToolDef(Icons.shopping_cart_outlined, 'shop_title',
              () => const ShoppingScreen()),
          ToolDef(Icons.card_giftcard_outlined, 'gift_title',
              () => const GiftsScreen()),
          ToolDef(Icons.wallet_outlined, 'cash_title',
              () => const CashScreen()),
          ToolDef(Icons.shield_outlined, 'vault_title',
              () => const EmergencyScreen()),
          ToolDef(Icons.medical_services_outlined, 'medical_title',
              () => const MedicalScreen()),
          ToolDef(Icons.work_outline, 'projects_title',
              () => const ProjectsScreen()),
          ToolDef(Icons.map_outlined, 'expense_map_title',
              () => const ExpenseMapScreen()),
          ToolDef(Icons.timer_outlined, 'challenge_title',
              () => const ChallengeScreen()),
          ToolDef(Icons.emoji_events_outlined, 'ach_title',
              () => const AchievementsScreen()),
          ToolDef(Icons.location_on_outlined, 'places_title',
              () => const PlacesScreen()),
          ToolDef(Icons.leaderboard_outlined, 'leaderboard_title',
              () => const LeaderboardScreen()),
          ToolDef(Icons.public_outlined, 'templates_public',
              () => const PublicTemplatesScreen()),
          ToolDef(Icons.receipt_long_outlined, 'tax_title',
              () => const TaxHelperScreen()),
        ],
      ),
    ];

/// One tile in the money-tools grid: icon + short text label
/// (never icon-only), comfortably above the 48dp touch target.
class ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ToolTile({
    super.key,
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
