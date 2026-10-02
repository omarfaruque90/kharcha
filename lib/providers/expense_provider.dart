import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/expense.dart';

/// Total spending for one calendar month.
class MonthlyTotal {
  final DateTime month;
  final double total;

  MonthlyTotal(this.month, this.total);
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
    _expenses.add(expense.copyWith(id: id));
    _sort();
    notifyListeners();
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
    await DatabaseHelper.instance.deleteExpense(id);
    _expenses.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void _sort() {
    _expenses.sort((a, b) => b.date.compareTo(a.date));
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  double totalOn(DateTime day) {
    final d = _day(day);
    return _expenses
        .where((e) => _day(e.date) == d)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double totalThisWeek() {
    final now = DateTime.now();
    final start = _day(now.subtract(Duration(days: now.weekday - 1)));
    final end = start.add(const Duration(days: 7));
    return _expenses
        .where((e) => !e.date.isBefore(start) && e.date.isBefore(end))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double totalThisMonth() {
    final now = DateTime.now();
    return _expenses
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .fold(0.0, (sum, e) => sum + e.amount);
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
          .fold(0.0, (sum, e) => sum + e.amount);
      return MonthlyTotal(month, total);
    });
  }

  /// Spending per category id for a given calendar month.
  Map<String, double> totalsByCategory(DateTime month) {
    final map = <String, double>{};
    for (final e in _expenses) {
      if (e.date.year == month.year && e.date.month == month.month) {
        map[e.categoryId] = (map[e.categoryId] ?? 0) + e.amount;
      }
    }
    return map;
  }
}
