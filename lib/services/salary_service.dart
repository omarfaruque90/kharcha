import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/income.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Salary-day automation (Package O).
///
/// When the user's salary day arrives, the monthly salary is recorded as
/// income once and fanned out to savings goals / wishlist items according
/// to the user's salary rules.
class SalaryService {
  SalaryService._();

  /// Checks whether today is salary day and, if so, processes the monthly
  /// salary exactly once (guarded by the `salary_paid_yyyyMM` setting).
  ///
  /// Salary amount/day come from the settings keys `salary_amount` and
  /// `salary_day`. The salary is logged as income through [money]; shares
  /// go to savings goals via [MoneyProvider.addSavings] and to wishlist
  /// items via [DatabaseHelper.updateWishlist]. [expenses] is accepted for
  /// wiring symmetry with other startup checks.
  static Future<void> checkSalaryDay(
      ExpenseProvider expenses, MoneyProvider money) async {
    try {
      final db = DatabaseHelper.instance;
      final lang = await db.getSetting('language') ?? 'bn';
      final now = DateTime.now();

      final salaryDay = int.tryParse(await db.getSetting('salary_day') ?? '');
      final salary =
          double.tryParse(await db.getSetting('salary_amount') ?? '');
      if (salaryDay == null ||
          salaryDay < 1 ||
          salaryDay > 31 ||
          salary == null ||
          salary <= 0) {
        return;
      }
      if (now.day != salaryDay) return;

      final monthKey =
          'salary_paid_${now.year}${now.month.toString().padLeft(2, '0')}';
      if ((await db.getSetting(monthKey)) == '1') return;

      // 1) Record the salary as income.
      await money.addIncome(Income(
        amount: salary,
        source: AppStrings.get('salary_income_source', lang),
        date: now,
        note: '',
      ));

      // 2) Fan out per rule: share = salary * percent / 100.
      var distributed = 0.0;
      for (final rule in await db.getSalaryRules()) {
        final share = salary * rule.percent / 100;
        if (share <= 0) continue;
        if (rule.targetType == 'savings') {
          await money.addSavings(rule.targetId, share);
          distributed += share;
        } else if (rule.targetType == 'wishlist') {
          final items = await db.getWishlist();
          final idx = items.indexWhere((w) => w.id == rule.targetId);
          if (idx != -1) {
            final item = items[idx];
            await db.updateWishlist(
              item.copyWith(saved: item.saved + share, updatedAt: now),
            );
            distributed += share;
          }
        }
        // 'budget' shares simply stay in the monthly budget — nothing to do.
      }

      await db.setSetting(monthKey, '1');

      final title = AppStrings.get('salary_received_title', lang);
      final body = AppStrings.get('salary_received_body', lang)
          .replaceAll('{amount}', formatMoney(distributed));
      await NotificationService.showNow(title: title, body: body);
      await NotificationCenter.push(
        title: title,
        body: body,
        type: 'salary',
        dedupeKey: monthKey,
      );
    } catch (_) {
      // Salary automation must never crash startup.
    }
  }
}
