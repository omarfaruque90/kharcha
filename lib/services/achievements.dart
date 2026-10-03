import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/expense.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Badge definition: id, icon, and localization keys for title/desc.
class AchievementDef {
  final String id;
  final IconData icon;
  final String titleKey;
  final String descKey;

  const AchievementDef({
    required this.id,
    required this.icon,
    required this.titleKey,
    required this.descKey,
  });
}

/// Badge context shared by all rule checks (built once per checkAll run).
class _CheckContext {
  final List<Expense> expenses;
  final double thisMonthTotal;
  final double? monthlyBudgetLimit;
  final bool ocrUsed;

  _CheckContext({
    required this.expenses,
    required this.thisMonthTotal,
    required this.monthlyBudgetLimit,
    required this.ocrUsed,
  });
}

/// Achievements / badges system.
///
/// Call [checkAll] at app startup and after an expense is added; it
/// unlocks newly earned badges, fires a system notification + an in-app
/// notification-center entry, and returns the newly unlocked badge ids.
class Achievements {
  Achievements._();

  /// Mirrors MoneyProvider.monthlyBudgetCategoryId — the special category
  /// id used for the overall monthly spending limit in the budgets table.
  static const String _monthlyBudgetCategoryId = '__monthly_total__';

  static const List<AchievementDef> all = [
    AchievementDef(
      id: 'first_expense',
      icon: Icons.emoji_events,
      titleKey: 'ach_first',
      descKey: 'ach_first_d',
    ),
    AchievementDef(
      id: 'streak_7',
      icon: Icons.local_fire_department,
      titleKey: 'ach_streak7',
      descKey: 'ach_streak7_d',
    ),
    AchievementDef(
      id: 'saver',
      icon: Icons.savings,
      titleKey: 'ach_saver',
      descKey: 'ach_saver_d',
    ),
    AchievementDef(
      id: 'century',
      icon: Icons.military_tech,
      titleKey: 'ach_century',
      descKey: 'ach_century_d',
    ),
    AchievementDef(
      id: 'ocr_user',
      icon: Icons.document_scanner,
      titleKey: 'ach_ocr',
      descKey: 'ach_ocr_d',
    ),
    AchievementDef(
      id: 'early_bird',
      icon: Icons.wb_sunny,
      titleKey: 'ach_early',
      descKey: 'ach_early_d',
    ),
  ];

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static bool _rule(String id, _CheckContext c) {
    switch (id) {
      case 'first_expense':
        return c.expenses.isNotEmpty;
      case 'streak_7':
        return _hasStreak(c.expenses, 7);
      case 'saver':
        // Spent something this month, stayed under a positive budget limit.
        return c.monthlyBudgetLimit != null &&
            c.monthlyBudgetLimit! > 0 &&
            c.thisMonthTotal > 0 &&
            c.thisMonthTotal < c.monthlyBudgetLimit!;
      case 'century':
        return c.expenses.length >= 100;
      case 'ocr_user':
        return c.ocrUsed;
      case 'early_bird':
        return c.expenses.any((e) => e.date.hour < 7);
      default:
        return false;
    }
  }

  /// True when the user logged expenses on [days] consecutive calendar days.
  static bool _hasStreak(List<Expense> expenses, int days) {
    if (expenses.isEmpty) return false;
    final daySet = <DateTime>{
      for (final e in expenses) DateTime(e.date.year, e.date.month, e.date.day),
    };
    final sorted = daySet.toList()..sort();
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].difference(sorted[i - 1]).inDays == 1) {
        run++;
        if (run >= days) return true;
      } else {
        run = 1;
      }
    }
    return false;
  }

  /// Checks every locked badge against the current data. Unlocks new
  /// badges (persists via DatabaseHelper, fires a notification and an
  /// in-app notification-center entry) and returns the newly unlocked ids.
  static Future<List<String>> checkAll() async {
    final newlyUnlocked = <String>[];
    try {
      final db = DatabaseHelper.instance;
      final unlocked = await db.getUnlockedAchievements();
      final expenses = await db.getAllExpenses();
      final now = DateTime.now();
      final monthKey = _monthKey(now);

      double? budgetLimit;
      try {
        final budgets = await db.getBudgetsForMonth(monthKey);
        for (final b in budgets) {
          if (b.categoryId == _monthlyBudgetCategoryId) {
            budgetLimit = b.limitAmount;
            break;
          }
        }
      } catch (_) {
        // Budget read is best-effort; saver just won't unlock this run.
      }

      final monthTotal = expenses
          .where((e) => e.date.year == now.year && e.date.month == now.month)
          .fold(0.0, (sum, e) => sum + e.amount);

      final ocrUsed = (await db.getSetting('ocr_used')) == '1';
      final lang = await db.getSetting('language') ?? 'bn';

      final ctx = _CheckContext(
        expenses: expenses,
        thisMonthTotal: monthTotal,
        monthlyBudgetLimit: budgetLimit,
        ocrUsed: ocrUsed,
      );

      for (final def in all) {
        try {
          if (unlocked.contains(def.id)) continue;
          if (!_rule(def.id, ctx)) continue;
          await db.unlockAchievement(def.id);
          newlyUnlocked.add(def.id);
          final title = AppStrings.get(def.titleKey, lang);
          final body =
              '🏆 ${AppStrings.get('ach_unlocked', lang)}: $title';
          await NotificationService.showNow(title: title, body: body);
          await NotificationCenter.push(
            title: title,
            body: body,
            type: 'achievement',
            dedupeKey: 'ach:${def.id}',
          );
        } catch (_) {
          // One badge must never break the rest.
        }
      }
    } catch (_) {
      // Achievements must never crash the caller.
    }
    return newlyUnlocked;
  }
}
