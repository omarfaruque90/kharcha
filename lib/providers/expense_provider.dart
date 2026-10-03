import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/cash_entry.dart';
import '../models/expense.dart';
import '../services/anomaly_service.dart';
import '../services/category_learner.dart';
import '../services/daily_limit_service.dart';
import '../services/stats_notification.dart';

/// Total spending for one calendar month.
class MonthlyTotal {
  final DateTime month;
  final double total;

  const MonthlyTotal(this.month, this.total);
}

/// Holds all expenses in memory (newest first) and exposes aggregates.
class ExpenseProvider extends ChangeNotifier {
  final List<Expense> _expenses = [];
  bool _loaded = false;

  List<Expense> get expenses => List.unmodifiable(_expenses);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final items = await DatabaseHelper.instance.getAllExpenses();
    _expenses
      ..clear()
      ..addAll(items);
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(Expense expense) async {
    final id = await DatabaseHelper.instance.insertExpense(expense);
    final saved = expense.copyWith(id: id);
    _expenses.add(saved);
    _sort();
    notifyListeners();
    // Package AL: cash payments decrement the cash ledger.
    if (saved.paymentMethod == 'cash') {
      try {
        await DatabaseHelper.instance.insertCashEntry(CashEntry(
          id: CashEntry.newId(),
          amount: saved.bdtAmount ?? saved.amount,
          type: 'out',
          date: saved.date,
          note: saved.note,
        ));
      } catch (_) {}
    }
    // Post-save intelligence (all best-effort, never break the save flow):
    // BE anomaly detection, AV daily-limit alarm, BG category learning,
    // BQ stats notification refresh.
    AnomalyService.checkExpense(saved);
    DailyLimitService.check(this);
    CategoryLearner.learn(saved.note, saved.categoryId);
    StatsNotification.refresh();
  }

  Future<void> update(Expense expense) async {
    await DatabaseHelper.instance.updateExpense(expense);
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index != -1) {
      _expenses[index] = expense;
    }
    _sort();
    notifyListeners();
  }

  /// Replaces the whole in-memory list (used after a cloud pull).
  Future<void> replaceAll(List<Expense> expenses) async {
    _expenses
      ..clear()
      ..addAll(expenses);
    _sort();
    _loaded = true;
    notifyListeners();
  }

  Future<void> remove(String id) async {
    // Capture before deleting so a cash expense can be refunded to the
    // cash ledger after the delete succeeds.
    Expense? removed;
    try {
      removed = _expenses.firstWhere((e) => e.id == id);
    } catch (_) {
      removed = null;
    }
    await DatabaseHelper.instance.deleteExpense(id);
    _expenses.removeWhere((e) => e.id == id);
    notifyListeners();
    // Package AL: refund a removed cash expense back into the cash ledger.
    if (removed != null && removed.paymentMethod == 'cash') {
      try {
        await DatabaseHelper.instance.insertCashEntry(CashEntry(
          id: CashEntry.newId(),
          amount: removed.bdtAmount ?? removed.amount,
          type: 'in',
          date: DateTime.now(),
          note: removed.note,
        ));
      } catch (_) {}
    }
  }

  void _sort() {
    _expenses.sort((a, b) => b.date.compareTo(a.date));
  }

  /// Deletes all expenses in [month]. Returns the count removed.
  /// Used to clean up test/try entries from Reports.
  Future<int> removeForMonth(DateTime month) async {
    final ids = _expenses
        .where((e) => e.date.year == month.year && e.date.month == month.month)
        .map((e) => e.id)
        .whereType<String>()
        .toList();
    for (final id in ids) {
      try {
        await DatabaseHelper.instance.deleteExpense(id);
      } catch (_) {}
    }
    _expenses.removeWhere((e) =>
        e.date.year == month.year && e.date.month == month.month);
    notifyListeners();
    return ids.length;
  }

  /// Deletes all expenses of [categoryId] in [month]. Returns count removed.
  Future<int> removeForCategoryMonth(String categoryId, DateTime month) async {
    final ids = _expenses
        .where((e) =>
            e.categoryId == categoryId &&
            e.date.year == month.year &&
            e.date.month == month.month)
        .map((e) => e.id)
        .whereType<String>()
        .toList();
    for (final id in ids) {
      try {
        await DatabaseHelper.instance.deleteExpense(id);
      } catch (_) {}
    }
    _expenses.removeWhere((e) =>
        e.categoryId == categoryId &&
        e.date.year == month.year &&
        e.date.month == month.month);
    notifyListeners();
    return ids.length;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  double totalOn(DateTime day) {
    final d = _day(day);
    return _expenses
        .where((e) => _day(e.date) == d)
        .fold(0.0, (sum, e) => sum + (e.bdtAmount ?? e.amount));
  }

  double totalThisWeek() {
    final now = DateTime.now();
    final start = _day(now.subtract(Duration(days: now.weekday - 1)));
    final end = start.add(const Duration(days: 7));
    return _expenses
        .where((e) => !e.date.isBefore(start) && e.date.isBefore(end))
        .fold(0.0, (sum, e) => sum + (e.bdtAmount ?? e.amount));
  }

  double totalThisMonth() {
    final now = DateTime.now();
    return _expenses
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .fold(0.0, (sum, e) => sum + (e.bdtAmount ?? e.amount));
  }

  /// Expenses matching [query] (note text) and optional [categoryId],
  /// still ordered newest first.
  List<Expense> filtered({String query = '', String? categoryId}) {
    final q = query.trim().toLowerCase();
    return _expenses.where((e) {
      final matchesQuery = q.isEmpty || e.note.toLowerCase().contains(q);
      final matchesCategory = categoryId == null || e.categoryId == categoryId;
      return matchesQuery && matchesCategory;
    }).toList();
  }

  /// Totals for the last 6 calendar months, oldest first.
  List<MonthlyTotal> last6Months() {
    final now = DateTime.now();
    return List.generate(6, (i) {
      final month = DateTime(now.year, now.month - 5 + i);
      final total = _expenses
          .where(
              (e) => e.date.year == month.year && e.date.month == month.month)
          .fold(0.0, (sum, e) => sum + (e.bdtAmount ?? e.amount));
      return MonthlyTotal(month, total);
    });
  }

  /// Spending per category id for a given calendar month.
  Map<String, double> totalsByCategory(DateTime month) {
    final map = <String, double>{};
    for (final e in _expenses) {
      if (e.date.year == month.year && e.date.month == month.month) {
        map[e.categoryId] = (map[e.categoryId] ?? 0) + (e.bdtAmount ?? e.amount);
      }
    }
    return map;
  }

  /// Category totals for an arbitrary [start]..[end] range (inclusive).
  Map<String, double> totalsByCategoryRange(DateTime start, DateTime end) {
    final map = <String, double>{};
    for (final e in _expenses) {
      if (!e.date.isBefore(start) && !e.date.isAfter(end)) {
        map[e.categoryId] = (map[e.categoryId] ?? 0) + (e.bdtAmount ?? e.amount);
      }
    }
    return map;
  }

  /// Deletes all expenses in [start]..[end]. Returns the count removed.
  Future<int> removeForRange(DateTime start, DateTime end) async {
    final ids = _expenses
        .where((e) => !e.date.isBefore(start) && !e.date.isAfter(end))
        .map((e) => e.id)
        .toList();
    for (final id in ids) {
      try {
        await DatabaseHelper.instance.deleteExpense(id);
      } catch (_) {}
    }
    _expenses.removeWhere(
        (e) => !e.date.isBefore(start) && !e.date.isAfter(end));
    notifyListeners();
    return ids.length;
  }

  /// Deletes all expenses of [categoryId] in [start]..[end]. Returns count.
  Future<int> removeForCategoryRange(
      String categoryId, DateTime start, DateTime end) async {
    final ids = _expenses
        .where((e) =>
            e.categoryId == categoryId &&
            !e.date.isBefore(start) &&
            !e.date.isAfter(end))
        .map((e) => e.id)
        .toList();
    for (final id in ids) {
      try {
        await DatabaseHelper.instance.deleteExpense(id);
      } catch (_) {}
    }
    _expenses.removeWhere((e) =>
        e.categoryId == categoryId &&
        !e.date.isBefore(start) &&
        !e.date.isAfter(end));
    notifyListeners();
    return ids.length;
  }
}
