import 'dart:convert';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/cash_entry.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../providers/money_provider.dart';
import '../providers/total_balance_provider.dart';
import 'notification_center.dart';

/// Auto-generates real expenses / incomes from active recurring templates,
/// once per calendar month.
///
/// Called from main.dart on app start; the exact
/// [RecurringService.processDue] signature is part of the cross-agent
/// contract and must be kept.
class RecurringService {
  /// For every active template whose [lastAddedMonth] is not the current
  /// month and whose day-of-month has arrived (or passed): inserts a real
  /// expense (or income, when the template's [RecurringExpense.kind] is
  /// 'income') and stamps the template with the current month key.
  ///
  /// Each auto-added entry also pushes a notification-center entry
  /// (deduped per template per month) so the user sees what was added.
  static Future<void> processDue() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final currentKey = monthKeyOf(now);
    final active = await db.getActiveRecurringExpenses();
    final lang = await db.getSetting('language') ?? 'bn';
    for (final template in active) {
      if (template.lastAddedMonth == currentKey) continue;
      if (template.dayOfMonth > now.day) continue;

      // Clamp the day for short months (e.g. Feb 30 -> Feb 28/29).
      final lastDayOfMonth = DateTime(now.year, now.month + 1, 0).day;
      final day = template.dayOfMonth > lastDayOfMonth
          ? lastDayOfMonth
          : template.dayOfMonth;

      final label = template.label.trim();
      final isIncome = template.kind == 'income';

      if (isIncome) {
        // Income template: auto-add a real income record. Uses the DB
        // directly, mirroring the expense path below — MoneyProvider is
        // created in main.dart and is not reachable from this static,
        // signature-locked service.
        await db.insertIncome(Income(
          amount: template.amount,
          source: label.isEmpty
              ? AppStrings.get('income_title', lang)
              : label,
          date: DateTime(now.year, now.month, day),
          note: 'Recurring',
        ));
      } else {
        final note = label.isEmpty
            ? template.note
            : '🔁 $label${template.note.trim().isEmpty ? '' : ' — ${template.note.trim()}'}';

        await db.insertExpense(Expense(
          amount: template.amount,
          categoryId: template.categoryId,
          date: DateTime(now.year, now.month, day),
          note: note,
          paymentMethod: template.paymentMethod,
        ));
        // Deduct from wallet (mirrors ExpenseProvider.add wallet logic).
        await _deductWallet(db, template.paymentMethod, template.amount);
      }
      await db.updateRecurringExpense(
        template.copyWith(lastAddedMonth: currentKey),
      );

      // Notify (best-effort; never break the loop).
      try {
        final whole =
            template.amount.truncateToDouble() == template.amount;
        final amountStr = whole
            ? template.amount.toStringAsFixed(0)
            : template.amount.toString();
        await NotificationCenter.push(
          title: AppStrings.get(
            isIncome
                ? 'notif_recurring_income_title'
                : 'notif_recurring_title',
            lang,
          ),
          body: AppStrings.get(
            isIncome ? 'notif_recurring_income_body' : 'notif_recurring_body',
            lang,
          )
              .replaceAll(
                '{label}',
                label.isEmpty
                    ? AppStrings.get(
                        isIncome ? 'income_title' : 'recurring_title', lang)
                    : label,
              )
              .replaceAll('{amount}', amountStr),
          type: 'recurring',
          dedupeKey: '${template.id}:$currentKey',
        );
      } catch (_) {}
    }
  }

  /// Deducts an expense amount from the matching wallet.
  /// Mirrors TotalBalanceProvider.deductForExpense for the static context.
  static Future<void> _deductWallet(
      DatabaseHelper db, String paymentMethod, double amount) async {
    if (amount <= 0) return;
    try {
      final w = TotalBalanceProvider.walletForPayment(paymentMethod);
      if (w == null) return;
      if (w == 'cash') {
        await db.insertCashEntry(CashEntry(
          id: CashEntry.newId(),
          amount: amount,
          type: 'out',
          note: 'recurring',
          date: DateTime.now(),
        ));
      } else {
        final raw = await db.getSetting('wallet_balances');
        final map = <String, double>{};
        if (raw != null && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            decoded.forEach((k, v) {
              map[k] = (v as num).toDouble();
            });
          } catch (_) {}
        }
        map[w] = (map[w] ?? 0) - amount;
        await db.setSetting('wallet_balances', jsonEncode(map));
      }
    } catch (_) {}
  }
}
