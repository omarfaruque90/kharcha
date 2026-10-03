import 'dart:convert';

import '../db/database_helper.dart';
import '../models/budget.dart';
import '../providers/money_provider.dart';

/// Package BP — Budget carry-forward.
///
/// When the `carry_forward` setting is on ('1'), unused budget from the
/// last processed month rolls into the current month: for every category
/// budget of the previous month, the unspent amount
/// (`limitAmount − spent`) is added on top of the current month's budget
/// for that category.
///
/// [maybeRollover] is idempotent: a second call in the same month is a
/// no-op because `carry_last_month` already equals the current month key.
/// The badge data ("↪ ৳X carried") is persisted as JSON in the
/// `carried_map` setting ({categoryId: amount}) for the current month;
/// the budget screen can read it to render badges.
class CarryForwardService {
  static const String settingEnabled = 'carry_forward';
  static const String settingLastMonth = 'carry_last_month';
  static const String settingCarriedMap = 'carried_map';

  /// Roles over unused last-month budgets into this month's budgets.
  /// Best-effort: all errors are swallowed so startup never breaks.
  static Future<void> maybeRollover() async {
    try {
      final db = DatabaseHelper.instance;

      // Disabled by default ('0').
      final enabled = (await db.getSetting(settingEnabled) ?? '0') == '1';
      if (!enabled) return;

      final now = DateTime.now();
      final currentKey = monthKeyOf(now);
      final lastKey = await db.getSetting(settingLastMonth);

      // Already rolled over this month -> no-op (idempotent).
      if (lastKey == currentKey) return;
      // Clock moved backwards -> never roll over, leave the stored key.
      if (lastKey != null &&
          lastKey.isNotEmpty &&
          lastKey.compareTo(currentKey) > 0) {
        return;
      }

      // First run ever (or setting freshly enabled): establish the
      // baseline without rolling anything over, so we don't fabricate
      // carry amounts from a month we never measured.
      if (lastKey == null || lastKey.isEmpty) {
        await db.setSetting(settingLastMonth, currentKey);
        return;
      }

      final sourceBudgets = await db.getBudgetsForMonth(lastKey);
      if (sourceBudgets.isEmpty) {
        await db.setSetting(settingLastMonth, currentKey);
        return;
      }

      // Total spent per category in the source month.
      final spentByCategory = <String, double>{};
      for (final expense in await db.getAllExpenses()) {
        if (monthKeyOf(expense.date) != lastKey) continue;
        final amount = expense.bdtAmount ?? expense.amount;
        spentByCategory[expense.categoryId] =
            (spentByCategory[expense.categoryId] ?? 0) + amount;
      }

      final currentBudgets = await db.getBudgetsForMonth(currentKey);
      final currentByCategory = <String, Budget>{};
      for (final b in currentBudgets) {
        currentByCategory[b.categoryId] = b;
      }

      final carried = <String, double>{};
      for (final budget in sourceBudgets) {
        final spent = spentByCategory[budget.categoryId] ?? 0.0;
        final unused = _round2(budget.limitAmount - spent);
        if (unused <= 0) continue;

        final existing = currentByCategory[budget.categoryId];
        final merged = _round2((existing?.limitAmount ?? 0) + unused);

        // One budget per (categoryId, monthKey): delete then insert merged.
        if (existing?.id != null) {
          await db.deleteBudget(existing!.id!);
        }
        await db.insertBudget(
          Budget(
            id: Budget.newId(),
            categoryId: budget.categoryId,
            monthKey: currentKey,
            limitAmount: merged,
          ),
        );
        carried[budget.categoryId] = unused;
      }

      // Persist the badge data for the budget screen, then stamp the key
      // last so a crash mid-rollover retries next launch.
      await db.setSetting(settingCarriedMap, jsonEncode(carried));
      await db.setSetting(settingLastMonth, currentKey);
    } catch (_) {
      // Best-effort: never break startup.
    }
  }

  /// Reads back the carried amounts for the current month
  /// ({categoryId: amount}). Empty map when none were rolled over.
  static Future<Map<String, double>> carriedMap() async {
    try {
      final raw =
          await DatabaseHelper.instance.getSetting(settingCarriedMap);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(
            k.toString(),
            (v as num?)?.toDouble() ?? 0.0,
          ));
    } catch (_) {
      return {};
    }
  }

  static double _round2(double v) => (v * 100).round() / 100;
}
