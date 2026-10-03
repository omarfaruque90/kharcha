import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/custom_category.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';

/// Package BL: share a pretty text summary of a month's spending via the
/// system share sheet. WhatsApp, Messenger, etc. all appear in the sheet,
/// so no per-app SDK is needed.
class ShareSummaryService {
  ShareSummaryService._();

  /// Builds the month summary in the user's language and opens the
  /// platform share sheet with it.
  ///
  /// Example (Bangla):
  ///   📊 Khorcha — October 2026
  ///   💸 খরচ: ৳12,400
  ///   🏆 Top: Food ৳4,200 | Transport ৳2,100 | Shopping ৳1,800
  ///   💰 সঞ্চয়: ৳3,600
  static Future<void> shareMonthSummary(
      BuildContext context, DateTime month) async {
    try {
      final lang =
          Provider.of<SettingsProvider>(context, listen: false).language;

      final expenses = (await DatabaseHelper.instance.getAllExpenses())
          .where((e) =>
              e.date.year == month.year && e.date.month == month.month)
          .toList();
      final incomes = (await DatabaseHelper.instance.getAllIncomes())
          .where((i) =>
              i.date.year == month.year && i.date.month == month.month)
          .toList();

      final totalExpense =
          expenses.fold<double>(0, (sum, e) => sum + e.amount);
      final totalIncome = incomes.fold<double>(0, (sum, i) => sum + i.amount);

      // Header keeps the English month label in both languages, matching the
      // shared design (e.g. "Khorcha — October 2026").
      final monthLabel = monthLong(month, 'en');
      final buf = StringBuffer('📊 Khorcha — $monthLabel\n');

      if (totalExpense <= 0 && totalIncome <= 0) {
        buf.writeln(AppStrings.get('share_summary_empty', lang));
      } else {
        buf.writeln(
            '💸 ${AppStrings.get('share_summary_expense', lang)}: ${formatMoney(totalExpense)}');

        final byCat = <String, double>{};
        for (final e in expenses) {
          byCat[e.categoryId] = (byCat[e.categoryId] ?? 0) + e.amount;
        }
        final top = byCat.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (top.isNotEmpty) {
          final parts = top.take(3).map((c) =>
              '${CustomCategoryRegistry.displayName(c.key, 'en')} ${formatMoney(c.value)}');
          buf.writeln(
              '🏆 ${AppStrings.get('share_summary_top', lang)}: ${parts.join(' | ')}');
        }

        // Savings = income − expense. Shown only when income was tracked;
        // otherwise a negative number would read as "negative savings".
        if (totalIncome > 0) {
          final savings = totalIncome - totalExpense;
          buf.writeln(
              '💰 ${AppStrings.get('share_summary_savings', lang)}: ${formatMoney(savings)}');
        }
      }

      await SharePlus.instance.share(
        ShareParams(text: buf.toString().trimRight()),
      );
    } catch (_) {
      // Sharing must never crash the calling screen.
    }
  }
}
