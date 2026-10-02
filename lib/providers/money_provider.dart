import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/bill_reminder.dart';
import '../models/budget.dart';
import '../models/income.dart';
import '../models/recurring_expense.dart';
import '../models/savings_goal.dart';

/// `yyyy-MM` key for a calendar month, e.g. `"2026-10"`.
String monthKeyOf(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  return '${date.year}-$m';
}

/// Holds incomes, budgets, recurring templates, savings goals and bill
/// reminders in memory and exposes monthly aggregates.
///
/// Must be registered in the app's MultiProvider before use.
class MoneyProvider extends ChangeNotifier {
  final List<Income> _incomes = [];
  final List<Budget> _budgets = [];
  final List<RecurringExpense> _recurring = [];
  final List<SavingsGoal> _goals = [];
  final List<BillReminder> _reminders = [];
  bool _loaded = false;

  List<Income> get incomes => List.unmodifiable(_incomes);
  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<RecurringExpense> get recurring => List.unmodifiable(_recurring);
  List<SavingsGoal> get goals => List.unmodifiable(_goals);
  List<BillReminder> get reminders => List.unmodifiable(_reminders);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final db = DatabaseHelper.instance;
    final results = await Future.wait([
      db.getAllIncomes(),
      db.getAllBudgets(),
      db.getAllRecurringExpenses(),
      db.getAllSavingsGoals(),
      db.getAllBillReminders(),
    ]);
    _incomes
      ..clear()
      ..addAll(results[0] as List<Income>);
    _budgets
      ..clear()
      ..addAll(results[1] as List<Budget>);
    _recurring
      ..clear()
      ..addAll(results[2] as List<RecurringExpense>);
    _goals
      ..clear()
      ..addAll(results[3] as List<SavingsGoal>);
    _reminders
      ..clear()
      ..addAll(results[4] as List<BillReminder>);
    _loaded = true;
    notifyListeners();
  }

  // ------------------------------- incomes ----------------------------

  Future<void> addIncome(Income income) async {
    final id = await DatabaseHelper.instance.insertIncome(income);
    _incomes.add(income.copyWith(id: id));
    _sortIncomes();
    notifyListeners();
  }

  Future<void> updateIncome(Income income) async {
    await DatabaseHelper.instance.updateIncome(income);
    final index = _incomes.indexWhere((e) => e.id == income.id);
    if (index != -1) {
      _incomes[index] = income;
      _sortIncomes();
    }
    notifyListeners();
  }

  Future<void> removeIncome(String id) async {
    await DatabaseHelper.instance.deleteIncome(id);
    _incomes.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void _sortIncomes() {
    _incomes.sort((a, b) => b.date.compareTo(a.date));
  }

  /// All incomes recorded in [monthKey] (`yyyy-MM`), newest first.
  List<Income> incomesForMonth(String monthKey) {
    return _incomes
        .where((i) => monthKeyOf(i.date) == monthKey)
        .toList(growable: false);
  }

  /// Total income for [monthKey] (`yyyy-MM`).
  double incomeForMonth(String monthKey) {
    return incomesForMonth(monthKey).fold(0.0, (sum, i) => sum + i.amount);
  }

  // ------------------------------- budgets ----------------------------

  /// Creates or replaces the budget for (categoryId, monthKey).
  Future<void> upsertBudget(Budget budget) async {
    final id = await DatabaseHelper.instance.upsertBudget(budget);
    final withId = budget.copyWith(id: id);
    final index = _budgets.indexWhere((b) => b.id == id);
    if (index != -1) {
      _budgets[index] = withId;
    } else {
      _budgets.add(withId);
    }
    notifyListeners();
  }

  Future<void> updateBudget(Budget budget) async {
    await DatabaseHelper.instance.updateBudget(budget);
    final index = _budgets.indexWhere((b) => b.id == budget.id);
    if (index != -1) {
      _budgets[index] = budget;
    }
    notifyListeners();
  }

  Future<void> removeBudget(String id) async {
    await DatabaseHelper.instance.deleteBudget(id);
    _budgets.removeWhere((b) => b.id == id);
    notifyListeners();
  }

  /// All budgets for [monthKey] (`yyyy-MM`).
  List<Budget> budgetsForMonth(String monthKey) {
    return _budgets.where((b) => b.monthKey == monthKey).toList(
          growable: false,
        );
  }

  /// The budget for one category in one month, or null when unset.
  Budget? budgetFor(String categoryId, String monthKey) {
    for (final b in _budgets) {
      if (b.categoryId == categoryId && b.monthKey == monthKey) return b;
    }
    return null;
  }

  /// Total expenses for [monthKey], queried from SQLite directly and
  /// grouped by category id.
  Future<Map<String, double>> expenseForMonth(String monthKey) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'expenses',
      columns: ['categoryId', 'amount'],
      where: 'substr(date, 1, 7) = ?',
      whereArgs: [monthKey],
    );
    final map = <String, double>{};
    for (final row in rows) {
      final categoryId = row['categoryId'] as String;
      final amount = (row['amount'] as num).toDouble();
      map[categoryId] = (map[categoryId] ?? 0) + amount;
    }
    return map;
  }

  // -------------------------- recurring expenses ----------------------

  Future<void> addRecurring(RecurringExpense recurring) async {
    final id =
        await DatabaseHelper.instance.insertRecurringExpense(recurring);
    _recurring.add(recurring.copyWith(id: id));
    _sortRecurring();
    notifyListeners();
  }

  Future<void> updateRecurring(RecurringExpense recurring) async {
    await DatabaseHelper.instance.updateRecurringExpense(recurring);
    final index = _recurring.indexWhere((r) => r.id == recurring.id);
    if (index != -1) {
      _recurring[index] = recurring;
      _sortRecurring();
    }
    notifyListeners();
  }

  Future<void> toggleRecurring(String id, bool active) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final updated = _recurring[index].copyWith(active: active);
    await updateRecurring(updated);
  }

  Future<void> removeRecurring(String id) async {
    await DatabaseHelper.instance.deleteRecurringExpense(id);
    _recurring.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  void _sortRecurring() {
    _recurring.sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
  }

  // ----------------------------- savings goals ------------------------

  Future<void> addGoal(SavingsGoal goal) async {
    final id = await DatabaseHelper.instance.insertSavingsGoal(goal);
    _goals.add(goal.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateGoal(SavingsGoal goal) async {
    await DatabaseHelper.instance.updateSavingsGoal(goal);
    final index = _goals.indexWhere((g) => g.id == goal.id);
    if (index != -1) {
      _goals[index] = goal;
    }
    notifyListeners();
  }

  /// Adds [amount] to the goal's saved amount (capped at nothing — the
  /// goal can exceed its target).
  Future<void> addSavings(String id, double amount) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;
    final updated =
        _goals[index].copyWith(savedAmount: _goals[index].savedAmount + amount);
    await updateGoal(updated);
  }

  Future<void> removeGoal(String id) async {
    await DatabaseHelper.instance.deleteSavingsGoal(id);
    _goals.removeWhere((g) => g.id == id);
    notifyListeners();
  }

  // ---------------------------- bill reminders ------------------------

  Future<void> addReminder(BillReminder reminder) async {
    final id = await DatabaseHelper.instance.insertBillReminder(reminder);
    _reminders.add(reminder.copyWith(id: id));
    _sortReminders();
    notifyListeners();
  }

  Future<void> updateReminder(BillReminder reminder) async {
    await DatabaseHelper.instance.updateBillReminder(reminder);
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index != -1) {
      _reminders[index] = reminder;
      _sortReminders();
    }
    notifyListeners();
  }

  Future<void> toggleReminder(String id, bool active) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) return;
    await updateReminder(_reminders[index].copyWith(active: active));
  }

  Future<void> removeReminder(String id) async {
    await DatabaseHelper.instance.deleteBillReminder(id);
    _reminders.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  void _sortReminders() {
    _reminders.sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
  }
}
