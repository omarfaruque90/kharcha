import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/expense.dart';
import '../services/sync_service.dart';

/// SQLite storage for expenses and simple key-value app settings.
///
/// v2 schema: expense ids are TEXT UUIDs (shared with Firestore) plus an
/// `updatedAt` column for last-write-wins sync merging. v1 databases
/// (INTEGER AUTOINCREMENT ids) are migrated automatically.
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
      version: 2,
      onCreate: (db, version) async {
        await _createExpensesTable(db);
        await _createSettingsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
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
        'id': Uuid().v4(),
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
    final id = expense.id ?? Uuid().v4();
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
