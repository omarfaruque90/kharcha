import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/bill_reminder.dart';
import '../models/budget.dart';
import '../models/custom_payment.dart';
import '../models/custom_place.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/recurring_expense.dart';
import '../models/savings_goal.dart';
import '../services/sync_service.dart';

/// SQLite storage for expenses, incomes, budgets, recurring templates,
/// savings goals, custom labels, bill reminders and simple key-value
/// app settings.
///
/// v2 schema: expense ids are TEXT UUIDs (shared with Firestore) plus an
/// `updatedAt` column for last-write-wins sync merging. v1 databases
/// (INTEGER AUTOINCREMENT ids) are migrated automatically.
///
/// v3 schema: new tables incomes, budgets, recurring_expenses,
/// savings_goals, custom_places, custom_payment_methods, bill_reminders
/// (all UUID ids + updatedAt), and `expenses.receiptPath TEXT` for an
/// optional attached receipt photo path.
class DatabaseHelper {
  DatabaseHelper._private();

  static final DatabaseHelper instance = DatabaseHelper._private();

  static Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final created = await _open();
    _db = created;
    return created;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'kharcha.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await _createExpensesTable(db);
        await _createSettingsTable(db);
        await _createV3Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateV2ToV3(db);
        }
      },
    );
  }

  Future<void> _createExpensesTable(Database db) async {
    await db.execute('''
      CREATE TABLE expenses(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        categoryId TEXT NOT NULL,
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        paymentMethod TEXT NOT NULL DEFAULT 'cash',
        receiptPath TEXT,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// v3 tables. Called from onCreate (fresh installs) and onUpgrade (v2->v3).
  /// CREATE TABLE IF NOT EXISTS keeps it idempotent.
  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS incomes(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        source TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets(
        id TEXT PRIMARY KEY,
        categoryId TEXT NOT NULL,
        monthKey TEXT NOT NULL,
        limitAmount REAL NOT NULL,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_expenses(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        categoryId TEXT NOT NULL,
        label TEXT NOT NULL DEFAULT '',
        dayOfMonth INTEGER NOT NULL DEFAULT 1,
        paymentMethod TEXT NOT NULL DEFAULT 'cash',
        note TEXT NOT NULL DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1,
        lastAddedMonth TEXT,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS savings_goals(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        targetAmount REAL NOT NULL,
        savedAmount REAL NOT NULL DEFAULT 0,
        deadline TEXT,
        emoji TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_places(
        id TEXT PRIMARY KEY,
        label TEXT NOT NULL UNIQUE,
        emoji TEXT NOT NULL DEFAULT '',
        usageCount INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_payment_methods(
        id TEXT PRIMARY KEY,
        label TEXT NOT NULL UNIQUE,
        usageCount INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bill_reminders(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL,
        dayOfMonth INTEGER NOT NULL DEFAULT 1,
        note TEXT NOT NULL DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// v2 -> v3: create the new tables and add `expenses.receiptPath`.
  /// The ALTER is guarded so re-running the migration never crashes.
  Future<void> _migrateV2ToV3(Database db) async {
    await _createV3Tables(db);
    try {
      await db.execute('ALTER TABLE expenses ADD COLUMN receiptPath TEXT');
    } catch (_) {
      // Column already exists (e.g. partial upgrade) — safe to ignore.
    }
  }

  /// v1 -> v2: INTEGER AUTOINCREMENT ids become TEXT UUIDs; every row gets
  /// an `updatedAt` stamp. Settings table is untouched.
  Future<void> _migrateV1ToV2(Database db) async {
    final oldRows = await db.query('expenses');
    await db.execute('ALTER TABLE expenses RENAME TO expenses_v1');
    await _createExpensesTable(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final row in oldRows) {
      batch.insert('expenses', {
        'id': const Uuid().v4(),
        'amount': row['amount'],
        'categoryId': row['categoryId'],
        'date': row['date'],
        'note': row['note'] ?? '',
        'paymentMethod': row['paymentMethod'] ?? 'cash',
        'updatedAt': now,
      });
    }
    await batch.commit(noResult: true);
    await db.execute('DROP TABLE expenses_v1');
  }

  /// Local insert: assigns a UUID id and fresh updatedAt, writes SQLite,
  /// then pushes to Firestore (no-op when logged out or applying remote).
  /// Returns the expense id.
  Future<String> insertExpense(Expense expense) async {
    final db = await database;
    final id = expense.id ?? const Uuid().v4();
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await db.insert('expenses', {
      'id': id,
      'amount': expense.amount,
      'categoryId': expense.categoryId,
      'date': expense.date.toIso8601String(),
      'note': expense.note,
      'paymentMethod': expense.paymentMethod,
      'updatedAt': updatedAt,
    });
    if (!SyncService.instance.applyingRemote) {
      await SyncService.instance.pushExpense(
        expense.copyWith(
          id: id,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
        ),
      );
    }
    return id;
  }

  Future<List<Expense>> getAllExpenses() async {
    final db = await database;
    final rows = await db.query('expenses', orderBy: 'date DESC');
    return rows.map(Expense.fromMap).toList();
  }

  /// Local update: bumps updatedAt, writes SQLite, then pushes to Firestore.
  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    final count = await db.update(
      'expenses',
      {
        'amount': expense.amount,
        'categoryId': expense.categoryId,
        'date': expense.date.toIso8601String(),
        'note': expense.note,
        'paymentMethod': expense.paymentMethod,
        'updatedAt': updatedAt,
      },
      where: 'id = ?',
      whereArgs: [expense.id],
    );
    if (!SyncService.instance.applyingRemote) {
      await SyncService.instance.pushExpense(
        expense.copyWith(
          updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
        ),
      );
    }
    return count;
  }

  /// Local delete: removes the row, then deletes the Firestore doc.
  Future<int> deleteExpense(String id) async {
    final db = await database;
    final count =
        await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    if (!SyncService.instance.applyingRemote) {
      await SyncService.instance.pushDelete(id);
    }
    return count;
  }

  /// Upserts a remote expense into SQLite without touching the cloud.
  /// The caller (SyncService) holds the [SyncService.applyingRemote] guard.
  Future<void> upsertExpense(Expense expense) async {
    final db = await database;
    await db.insert(
      'expenses',
      expense.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a row for a remote delete without touching the cloud.
  Future<void> deleteExpenseLocal(String id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  /// Wipes all local expenses without touching the cloud (logout).
  Future<void> wipeLocalExpenses() async {
    final db = await database;
    await db.delete('expenses');
  }

  // ------------------------------------------------------------------
  // Generic CRUD for the v3 tables (id + updatedAt pattern, local-only
  // for now; Firestore sync is wired per-table in a later phase).
  // ------------------------------------------------------------------

  Future<String> _insertRecord(String table, Map<String, dynamic> map) async {
    final db = await database;
    final id = map['id'] as String? ?? const Uuid().v4();
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      table,
      {...map, 'id': id, 'updatedAt': updatedAt},
    );
    return id;
  }

  Future<int> _updateRecord(
      String table, String id, Map<String, dynamic> values) async {
    final db = await database;
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      table,
      {...values, 'updatedAt': updatedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> _deleteRecord(String table, String id) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------ incomes ----------------------------

  Future<String> insertIncome(Income income) async {
    final db = await database;
    final id = income.id ?? const Uuid().v4();
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await db.insert('incomes', {
      'id': id,
      'amount': income.amount,
      'source': income.source,
      'date': income.date.toIso8601String(),
      'note': income.note,
      'updatedAt': updatedAt,
    });
    return id;
  }

  Future<List<Income>> getAllIncomes() async {
    final db = await database;
    final rows = await db.query('incomes', orderBy: 'date DESC');
    return rows.map(Income.fromMap).toList();
  }

  Future<int> updateIncome(Income income) =>
      _updateRecord('incomes', income.id!, {
        'amount': income.amount,
        'source': income.source,
        'date': income.date.toIso8601String(),
        'note': income.note,
      });

  Future<int> deleteIncome(String id) => _deleteRecord('incomes', id);

  Future<void> upsertIncome(Income income) async {
    final db = await database;
    await db.insert(
      'incomes',
      income.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> wipeLocalIncomes() async {
    final db = await database;
    await db.delete('incomes');
  }

  // ------------------------------ budgets ----------------------------

  Future<String> insertBudget(Budget budget) =>
      _insertRecord('budgets', budget.toMap());

  /// All budgets for one month (monthKey `yyyy-MM`), ordered by limit.
  Future<List<Budget>> getBudgetsForMonth(String monthKey) async {
    final db = await database;
    final rows = await db.query(
      'budgets',
      where: 'monthKey = ?',
      whereArgs: [monthKey],
      orderBy: 'limitAmount DESC',
    );
    return rows.map(Budget.fromMap).toList();
  }

  Future<List<Budget>> getAllBudgets() async {
    final db = await database;
    final rows =
        await db.query('budgets', orderBy: 'monthKey DESC, limitAmount DESC');
    return rows.map(Budget.fromMap).toList();
  }

  /// One budget per (categoryId, monthKey); replaces any existing row.
  Future<String> upsertBudget(Budget budget) async {
    final db = await database;
    final existing = await db.query(
      'budgets',
      columns: ['id'],
      where: 'categoryId = ? AND monthKey = ?',
      whereArgs: [budget.categoryId, budget.monthKey],
      limit: 1,
    );
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as String;
      await db.update(
        'budgets',
        {'limitAmount': budget.limitAmount, 'updatedAt': updatedAt},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return _insertRecord('budgets', budget.toMap());
  }

  Future<int> updateBudget(Budget budget) => _updateRecord('budgets',
      budget.id!, {
    'categoryId': budget.categoryId,
    'monthKey': budget.monthKey,
    'limitAmount': budget.limitAmount,
  });

  Future<int> deleteBudget(String id) => _deleteRecord('budgets', id);

  // ------------------------- recurring expenses ----------------------

  Future<String> insertRecurringExpense(RecurringExpense r) =>
      _insertRecord('recurring_expenses', r.toMap());

  Future<List<RecurringExpense>> getAllRecurringExpenses() async {
    final db = await database;
    final rows =
        await db.query('recurring_expenses', orderBy: 'dayOfMonth ASC');
    return rows.map(RecurringExpense.fromMap).toList();
  }

  Future<List<RecurringExpense>> getActiveRecurringExpenses() async {
    final db = await database;
    final rows = await db.query(
      'recurring_expenses',
      where: 'active = 1',
      orderBy: 'dayOfMonth ASC',
    );
    return rows.map(RecurringExpense.fromMap).toList();
  }

  Future<int> updateRecurringExpense(RecurringExpense r) =>
      _updateRecord('recurring_expenses', r.id!, {
        'amount': r.amount,
        'categoryId': r.categoryId,
        'label': r.label,
        'dayOfMonth': r.dayOfMonth,
        'paymentMethod': r.paymentMethod,
        'note': r.note,
        'active': r.active ? 1 : 0,
        'lastAddedMonth': r.lastAddedMonth,
      });

  Future<int> deleteRecurringExpense(String id) =>
      _deleteRecord('recurring_expenses', id);

  // ----------------------------- savings goals -----------------------

  Future<String> insertSavingsGoal(SavingsGoal goal) =>
      _insertRecord('savings_goals', goal.toMap());

  Future<List<SavingsGoal>> getAllSavingsGoals() async {
    final db = await database;
    final rows =
        await db.query('savings_goals', orderBy: 'targetAmount DESC');
    return rows.map(SavingsGoal.fromMap).toList();
  }

  Future<int> updateSavingsGoal(SavingsGoal goal) =>
      _updateRecord('savings_goals', goal.id!, {
        'title': goal.title,
        'targetAmount': goal.targetAmount,
        'savedAmount': goal.savedAmount,
        'deadline': goal.deadline?.toIso8601String(),
        'emoji': goal.emoji,
      });

  Future<int> deleteSavingsGoal(String id) =>
      _deleteRecord('savings_goals', id);

  // ----------------------------- custom places -----------------------

  Future<String> insertCustomPlace(CustomPlace place) =>
      _insertRecord('custom_places', place.toMap());

  Future<List<CustomPlace>> getAllCustomPlaces() async {
    final db = await database;
    final rows = await db.query('custom_places', orderBy: 'label ASC');
    return rows.map(CustomPlace.fromMap).toList();
  }

  /// Most-used places first — drives the suggestion list.
  Future<List<CustomPlace>> getMostUsedPlaces(int limit) async {
    final db = await database;
    final rows = await db.query(
      'custom_places',
      orderBy: 'usageCount DESC, label ASC',
      limit: limit,
    );
    return rows.map(CustomPlace.fromMap).toList();
  }

  /// Inserts a new label or bumps usageCount when it already exists.
  /// Returns the row id.
  Future<String> upsertCustomPlaceByLabel(String label,
      {String emoji = ''}) async {
    final db = await database;
    final trimmed = label.trim();
    final existing = await db.query(
      'custom_places',
      columns: ['id', 'usageCount', 'emoji'],
      where: 'label = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing.isNotEmpty) {
      final row = existing.first;
      final id = row['id'] as String;
      final updates = <String, dynamic>{
        'usageCount': ((row['usageCount'] as num?)?.toInt() ?? 0) + 1,
        'updatedAt': now,
      };
      if (emoji.isNotEmpty && (row['emoji'] as String? ?? '').isEmpty) {
        updates['emoji'] = emoji;
      }
      await db.update('custom_places', updates,
          where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return _insertRecord('custom_places', {
      'label': trimmed,
      'emoji': emoji,
      'usageCount': 1,
    });
  }

  Future<int> deleteCustomPlace(String id) =>
      _deleteRecord('custom_places', id);

  // --------------------------- custom payments -----------------------

  Future<String> insertCustomPayment(CustomPayment payment) =>
      _insertRecord('custom_payment_methods', payment.toMap());

  Future<List<CustomPayment>> getAllCustomPayments() async {
    final db = await database;
    final rows =
        await db.query('custom_payment_methods', orderBy: 'label ASC');
    return rows.map(CustomPayment.fromMap).toList();
  }

  /// Most-used payment methods first — drives the suggestion list.
  Future<List<CustomPayment>> getMostUsedPayments(int limit) async {
    final db = await database;
    final rows = await db.query(
      'custom_payment_methods',
      orderBy: 'usageCount DESC, label ASC',
      limit: limit,
    );
    return rows.map(CustomPayment.fromMap).toList();
  }

  /// Inserts a new label or bumps usageCount when it already exists.
  /// Returns the row id.
  Future<String> upsertCustomPaymentByLabel(String label) async {
    final db = await database;
    final trimmed = label.trim();
    final existing = await db.query(
      'custom_payment_methods',
      columns: ['id', 'usageCount'],
      where: 'label = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing.isNotEmpty) {
      final row = existing.first;
      final id = row['id'] as String;
      await db.update(
        'custom_payment_methods',
        {
          'usageCount': ((row['usageCount'] as num?)?.toInt() ?? 0) + 1,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return _insertRecord('custom_payment_methods', {
      'label': trimmed,
      'usageCount': 1,
    });
  }

  Future<int> deleteCustomPayment(String id) =>
      _deleteRecord('custom_payment_methods', id);

  // ---------------------------- bill reminders -----------------------

  Future<String> insertBillReminder(BillReminder reminder) =>
      _insertRecord('bill_reminders', reminder.toMap());

  Future<List<BillReminder>> getAllBillReminders() async {
    final db = await database;
    final rows =
        await db.query('bill_reminders', orderBy: 'dayOfMonth ASC');
    return rows.map(BillReminder.fromMap).toList();
  }

  Future<List<BillReminder>> getActiveBillReminders() async {
    final db = await database;
    final rows = await db.query(
      'bill_reminders',
      where: 'active = 1',
      orderBy: 'dayOfMonth ASC',
    );
    return rows.map(BillReminder.fromMap).toList();
  }

  Future<int> updateBillReminder(BillReminder reminder) =>
      _updateRecord('bill_reminders', reminder.id!, {
        'title': reminder.title,
        'amount': reminder.amount,
        'dayOfMonth': reminder.dayOfMonth,
        'note': reminder.note,
        'active': reminder.active ? 1 : 0,
      });

  Future<int> deleteBillReminder(String id) =>
      _deleteRecord('bill_reminders', id);

  // ------------------------------- settings --------------------------

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
