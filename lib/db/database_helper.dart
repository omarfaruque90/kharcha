import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/bill_reminder.dart';
import '../models/budget.dart';
import '../models/cash_entry.dart';
import '../models/fuel_log.dart';
import '../models/gift.dart';
import '../models/project.dart';
import '../models/shopping_item.dart';
import '../models/challenge.dart';
import '../models/app_notification.dart';
import '../models/custom_category.dart';
import '../models/custom_payment.dart';
import '../models/custom_place.dart';
import '../models/debt.dart';
import '../models/expense.dart';
import '../models/expense_template.dart';
import '../models/income.dart';
import '../models/recurring_expense.dart';
import '../models/salary_rule.dart';
import '../models/savings_goal.dart';
import '../models/subscription.dart';
import '../models/wishlist_item.dart';
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
///
/// v4 schema: adds `expenses.place TEXT` — the custom "where" label for the
/// Others category (e.g. "Dhanmondi Lake 🎮").
///
/// v5 schema: adds `custom_categories` (user-created expense categories,
/// local-only) and `notifications` (in-app notification center entries).
///
/// v6 schema: adds `debts` (money lent/borrowed tracking), `subscriptions`
/// (recurring subscription reminders), `templates` (quick-add expense
/// presets) and `wishlist` (items the user is saving up for). All UUID ids
/// + updatedAt, following the v3 table pattern.
///
/// v7 schema: no table changes — adds indexes on frequently-queried
/// columns (expenses.date, expenses.categoryId, expenses.project_id,
/// debts.date, subscriptions.next_due, notifications.time,
/// budgets.monthKey, cash_ledger/fuel_logs/gifts .date). Existing
/// databases get them via onUpgrade (oldVersion < 7).
class DatabaseHelper {
  DatabaseHelper._private();

  static final DatabaseHelper instance = DatabaseHelper._private();

  static Database? _db;

  /// BS (multi-profile): active profile name. 'personal' is the default and
  /// the only profile that syncs to Firestore. Each profile gets its own
  /// SQLite file, so categories/debts/etc. are per-profile automatically.
  String _profile = 'personal';

  String get activeProfile => _profile;
  bool get isPersonalProfile => _profile == 'personal';

  static String dbFileNameFor(String profile) {
    if (profile == 'personal') return 'kharcha.db';
    final safe =
        profile.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').toLowerCase();
    final clipped = safe.isEmpty ? 'x' : safe.substring(0, safe.length > 24 ? 24 : safe.length);
    return 'kharcha_$clipped.db';
  }

  /// Loads the persisted active profile (call once at startup before first
  /// [database] use).
  Future<void> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString('active_profile');
      if (p != null && p.trim().isNotEmpty) _profile = p.trim();
    } catch (_) {}
  }

  /// Switches profile: closes the current DB; the next [database] access
  /// reopens the profile's own file.
  Future<void> setProfile(String name) async {
    final target = name.trim().isEmpty ? 'personal' : name.trim();
    if (target == _profile) return;
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _profile = target;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_profile', target);
    } catch (_) {}
  }

  /// All known profiles (personal first). Stored in SharedPreferences so the
  /// list survives outside any single profile DB.
  static Future<List<String>> getProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('profiles') ?? <String>[];
      final out = <String>['personal'];
      for (final p in list) {
        if (p != 'personal' && !out.contains(p)) out.add(p);
      }
      return out;
    } catch (_) {
      return <String>['personal'];
    }
  }

  static Future<void> addProfile(String name) async {
    final n = name.trim();
    if (n.isEmpty || n == 'personal') return;
    final profiles = await getProfiles();
    if (profiles.contains(n)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('profiles', [...profiles.skip(1), n]);
    } catch (_) {}
  }

  /// Deletes a profile and its database file. Cannot delete 'personal'.
  static Future<void> deleteProfile(String name) async {
    if (name == 'personal') return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, dbFileNameFor(name)));
      if (await file.exists()) await file.delete();
      final prefs = await SharedPreferences.getInstance();
      final profiles = await getProfiles();
      profiles.remove(name);
      await prefs.setStringList('profiles', profiles.skip(1).toList());
      if (instance._profile == name) await instance.setProfile('personal');
    } catch (_) {}
  }

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final created = await _open();
    _db = created;
    return created;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, dbFileNameFor(_profile));
    return openDatabase(
      path,
      version: 9,
      onCreate: (db, version) async {
        await _createExpensesTable(db);
        await _createSettingsTable(db);
        await _createV3Tables(db);
        await _createV5Tables(db);
        await _createV6Tables(db);
        await _applyV6Alters(db);
        await _createIndexes(db);
        await _createV8Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateV2ToV3(db);
        }
        if (oldVersion < 4) {
          await _migrateV3ToV4(db);
        }
        if (oldVersion < 5) {
          await _createV5Tables(db);
        }
        if (oldVersion < 6) {
          await _createV6Tables(db);
          await _applyV6Alters(db);
        }
        if (oldVersion < 7) {
          await _createIndexes(db);
        }
        if (oldVersion < 8) {
          await _createV8Tables(db);
        }
        if (oldVersion < 9) {
          // PRAGMA-guarded: safe to re-run if a previous upgrade
          // was interrupted mid-way.
          final info =
              await db.rawQuery('PRAGMA table_info(shopping_items)');
          final exists = info.any((c) => c['name'] == 'unit');
          if (!exists) {
            await db.execute(
                "ALTER TABLE shopping_items ADD COLUMN unit TEXT NOT NULL DEFAULT 'pcs'");
          }
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
        place TEXT,
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

  /// v5 tables: user-created categories and notification-center entries.
  /// Called from onCreate (fresh installs) and onUpgrade (v4->v5).
  /// CREATE TABLE IF NOT EXISTS keeps it idempotent.
  Future<void> _createV5Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        time INTEGER NOT NULL,
        read INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'info',
        dedupe TEXT
      )
    ''');
  }

  /// v3 -> v4: add `expenses.place` (custom "where" for Others).
  /// The ALTER is guarded so re-running the migration never crashes.
  Future<void> _migrateV3ToV4(Database db) async {
    try {
      await db.execute('ALTER TABLE expenses ADD COLUMN place TEXT');
    } catch (_) {
      // Column already exists (e.g. partial upgrade) — safe to ignore.
    }
  }

  /// v6 tables: debts, subscriptions and expense templates. Called from
  /// onCreate (fresh installs) and onUpgrade (v5->v6). CREATE TABLE IF NOT
  /// EXISTS keeps it idempotent. Additive only — existing tables are never
  /// dropped or altered here.
  Future<void> _createV6Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debts(
        id TEXT PRIMARY KEY,
        person TEXT NOT NULL,
        amount REAL NOT NULL,
        kind TEXT NOT NULL,
        date INTEGER NOT NULL,
        due_date INTEGER,
        note TEXT NOT NULL DEFAULT '',
        settled INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS subscriptions(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        cycle TEXT NOT NULL,
        next_due INTEGER NOT NULL,
        emoji TEXT NOT NULL DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS templates(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        category_id TEXT NOT NULL DEFAULT '',
        payment TEXT NOT NULL DEFAULT 'cash',
        emoji TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wishlist(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        target_price REAL NOT NULL,
        saved REAL NOT NULL DEFAULT 0,
        emoji TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        done INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salary_rules(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        percent REAL NOT NULL,
        target_type TEXT NOT NULL,
        target_id TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS challenges(
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        start INTEGER NOT NULL,
        end INTEGER NOT NULL,
        streak INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievements(
        id TEXT PRIMARY KEY,
        unlocked_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // v0.2 batch 3 (AJ-BC): trackers
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_ledger(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        date INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fuel_logs(
        id TEXT PRIMARY KEY,
        date INTEGER NOT NULL,
        liters REAL NOT NULL DEFAULT 0,
        price_per_liter REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        odometer REAL NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shopping_items(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        qty REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT 'pcs',
        price REAL NOT NULL DEFAULT 0,
        done INTEGER NOT NULL DEFAULT 0,
        created INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gifts(
        id TEXT PRIMARY KEY,
        person TEXT NOT NULL,
        occasion TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        kind TEXT NOT NULL DEFAULT 'given',
        date INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS emergency_fund(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL DEFAULT 0,
        updated INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS emergency_ledger(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        date INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS category_learning(
        word TEXT NOT NULL,
        category_id TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (word, category_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projects(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start INTEGER NOT NULL DEFAULT 0,
        end INTEGER NOT NULL DEFAULT 0,
        budget REAL NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// v7: indexes on frequently-queried columns. Called from onCreate
  /// (fresh installs) and onUpgrade (oldVersion < 7, i.e. every existing
  /// database — additive only, never touches table data).
  /// CREATE INDEX IF NOT EXISTS keeps it idempotent.
  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(categoryId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_project ON expenses(project_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_debts_date ON debts(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_subs_nextdue ON subscriptions(next_due)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notif_time ON notifications(time)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_budgets_month ON budgets(monthKey)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cashledger_date ON cash_ledger(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_fuellogs_date ON fuel_logs(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gifts_date ON gifts(date)');
  }

  /// v8: user notes (Google Keep style).
  Future<void> _createV8Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        color INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        updated INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes(updated)');
  }

  /// v6 column additions on pre-existing tables. Runs on fresh installs
  /// (after creates) and on upgrade from v5. Checks PRAGMA first so it
  /// is safe if partially applied.
  Future<void> _applyV6Alters(Database db) async {
    Future<void> addColumn(
        String table, String column, String ddl) async {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final exists = info.any((c) => c['name'] == column);
      if (!exists) {
        await db.execute('ALTER TABLE $table ADD COLUMN $ddl');
      }
    }

    await addColumn(
        'expenses', 'currency', "currency TEXT NOT NULL DEFAULT 'BDT'");
    await addColumn('expenses', 'bdt_amount', 'bdt_amount REAL');
    await addColumn(
        'expenses', 'mood', "mood TEXT NOT NULL DEFAULT ''");
    await addColumn('recurring_expenses', 'kind',
        "kind TEXT NOT NULL DEFAULT 'expense'");
    await addColumn('bill_reminders', 'photo_path',
        "photo_path TEXT NOT NULL DEFAULT ''");
    await addColumn(
        'expenses', 'project_id', "project_id TEXT NOT NULL DEFAULT ''");
    await addColumn('expenses', 'lat', 'lat REAL');
    await addColumn('expenses', 'lng', 'lng REAL');
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
      'place': expense.place,
      'receiptPath': expense.receiptPath,
      'currency': expense.currency,
      'bdt_amount': expense.bdtAmount,
      'mood': expense.mood,
      'project_id': expense.projectId,
      'lat': expense.lat,
      'lng': expense.lng,
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
        'place': expense.place,
        'receiptPath': expense.receiptPath,
        'currency': expense.currency,
        'bdt_amount': expense.bdtAmount,
        'mood': expense.mood,
        'project_id': expense.projectId,
        'lat': expense.lat,
        'lng': expense.lng,
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
      // Record tombstone so a fresh pull doesn't resurrect this record.
      await _addTombstone('expense', id);
      await SyncService.instance.pushDelete(id);
    }
    return count;
  }

  /// Records a deleted record ID (tombstone) to prevent resurrection on sync.
  Future<void> _addTombstone(String type, String id) async {
    try {
      final key = 'tombstones_$type';
      final raw = await getSetting(key);
      final ids = <String>{};
      if (raw != null && raw.isNotEmpty) {
        ids.addAll(raw.split(',').where((s) => s.isNotEmpty));
      }
      ids.add(id);
      await setSetting(key, ids.join(','));
    } catch (_) {}
  }

  /// Returns tombstoned IDs for [type].
  Future<Set<String>> getTombstones(String type) async {
    try {
      final raw = await getSetting('tombstones_$type');
      if (raw == null || raw.isEmpty) return {};
      return raw.split(',').where((s) => s.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Clears tombstones for [type] after successful sync.
  Future<void> clearTombstones(String type) async {
    try {
      await setSetting('tombstones_$type', '');
    } catch (_) {}
  }

  /// Upserts a remote expense into SQLite without touching the cloud.
  /// The caller (SyncService) holds the [SyncService.applyingRemote] guard.
  /// Preserves device-local columns (receiptPath, project_id, lat, lng)
  /// that are not synced to Firestore.
  Future<void> upsertExpense(Expense expense) async {
    final db = await database;
    // Preserve local-only columns from the existing row.
    if (expense.id != null) {
      final existing = await db.query(
        'expenses',
        columns: ['receiptPath', 'project_id', 'lat', 'lng'],
        where: 'id = ?',
        whereArgs: [expense.id],
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        expense = expense.copyWith(
          receiptPath: row['receiptPath'] as String?,
          projectId: row['project_id'] as String? ?? '',
          lat: (row['lat'] as num?)?.toDouble(),
          lng: (row['lng'] as num?)?.toDouble(),
        );
      }
    }
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
  // Generic CRUD for the v3 tables (id + updatedAt pattern). Local writes
  // push to Firestore via SyncService (no-op when logged out or while
  // applying remote changes). Remote-applied writes go through
  // upsertRemoteRecord/deleteRemoteRecord under the
  // SyncService.applyingRemote guard (no push-back loops).
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

  /// Pushes the current SQLite row for [id] in [table] to the Firestore
  /// [collection]. No-op when logged out or while applying remote changes.
  /// The row is re-read so the push carries the exact persisted state
  /// (including the bumped updatedAt).
  Future<void> _pushRow<T>({
    required String table,
    required String collection,
    required String id,
    required T Function(Map<String, dynamic> row) fromMap,
    required Map<String, dynamic> Function(T item) toFirestore,
  }) async {
    if (SyncService.instance.applyingRemote) return;
    final db = await database;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await SyncService.instance.pushRecord(
      collection,
      id,
      toFirestore(fromMap(rows.first)),
    );
  }

  /// Pushes a cloud delete for [id] in [collection]. No-op when logged out
  /// or while applying remote changes.
  Future<void> _pushDelete(String collection, String id) async {
    if (SyncService.instance.applyingRemote) return;
    await SyncService.instance.pushRecordDelete(collection, id);
  }

  /// Upserts a remotely-fetched record into [table] by id without touching
  /// the cloud. The caller (SyncService) holds the
  /// [SyncService.applyingRemote] guard while calling this.
  Future<void> upsertRemoteRecord(
      String table, Map<String, dynamic> map) async {
    final db = await database;
    await db.insert(
      table,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a row for a remote delete without touching the cloud.
  /// The caller (SyncService) holds the [SyncService.applyingRemote] guard
  /// while calling this.
  Future<void> deleteRemoteRecord(String table, String id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
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
    await _pushRow<Income>(
      table: 'incomes',
      collection: 'incomes',
      id: id,
      fromMap: Income.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

  Future<List<Income>> getAllIncomes() async {
    final db = await database;
    final rows = await db.query('incomes', orderBy: 'date DESC');
    return rows.map(Income.fromMap).toList();
  }

  Future<int> updateIncome(Income income) async {
    final id = income.id;
    if (id == null) return 0;
    final count = await _updateRecord('incomes', id, {
      'amount': income.amount,
      'source': income.source,
      'date': income.date.toIso8601String(),
      'note': income.note,
    });
    await _pushRow<Income>(
      table: 'incomes',
      collection: 'incomes',
      id: id,
      fromMap: Income.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return count;
  }

  Future<int> deleteIncome(String id) async {
    final count = await _deleteRecord('incomes', id);
    await _pushDelete('incomes', id);
    return count;
  }

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

  Future<String> insertBudget(Budget budget) async {
    final id = await _insertRecord('budgets', budget.toMap());
    await _pushRow<Budget>(
      table: 'budgets',
      collection: 'budgets',
      id: id,
      fromMap: Budget.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

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
  /// Pushes the final row to Firestore.
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
    final String id;
    if (existing.isNotEmpty) {
      id = existing.first['id'] as String;
      await db.update(
        'budgets',
        {'limitAmount': budget.limitAmount, 'updatedAt': updatedAt},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      id = await _insertRecord('budgets', budget.toMap());
    }
    await _pushRow<Budget>(
      table: 'budgets',
      collection: 'budgets',
      id: id,
      fromMap: Budget.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

  Future<int> updateBudget(Budget budget) async {
    final id = budget.id;
    if (id == null) return 0;
    final count = await _updateRecord('budgets', id, {
      'categoryId': budget.categoryId,
      'monthKey': budget.monthKey,
      'limitAmount': budget.limitAmount,
    });
    await _pushRow<Budget>(
      table: 'budgets',
      collection: 'budgets',
      id: id,
      fromMap: Budget.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return count;
  }

  Future<int> deleteBudget(String id) async {
    final count = await _deleteRecord('budgets', id);
    await _pushDelete('budgets', id);
    return count;
  }

  /// Wipes all local budgets without touching the cloud (logout).
  Future<void> wipeLocalBudgets() async {
    final db = await database;
    await db.delete('budgets');
  }

  // ------------------------- recurring expenses ----------------------

  Future<String> insertRecurringExpense(RecurringExpense r) async {
    final id = await _insertRecord('recurring_expenses', r.toMap());
    await _pushRow<RecurringExpense>(
      table: 'recurring_expenses',
      collection: 'recurring',
      id: id,
      fromMap: RecurringExpense.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

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

  /// Local update — also used by RecurringService.processDue() to stamp
  /// lastAddedMonth; the push keeps the template in sync cross-device.
  Future<int> updateRecurringExpense(RecurringExpense r) async {
    final id = r.id;
    if (id == null) return 0;
    final count = await _updateRecord('recurring_expenses', id, {
      'amount': r.amount,
      'categoryId': r.categoryId,
      'label': r.label,
      'dayOfMonth': r.dayOfMonth,
      'paymentMethod': r.paymentMethod,
      'note': r.note,
      'active': r.active ? 1 : 0,
      'lastAddedMonth': r.lastAddedMonth,
    });
    await _pushRow<RecurringExpense>(
      table: 'recurring_expenses',
      collection: 'recurring',
      id: id,
      fromMap: RecurringExpense.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return count;
  }

  Future<int> deleteRecurringExpense(String id) async {
    final count = await _deleteRecord('recurring_expenses', id);
    await _pushDelete('recurring', id);
    return count;
  }

  /// Wipes all local recurring templates without touching the cloud
  /// (logout).
  Future<void> wipeLocalRecurringExpenses() async {
    final db = await database;
    await db.delete('recurring_expenses');
  }

  // ----------------------------- savings goals -----------------------

  Future<String> insertSavingsGoal(SavingsGoal goal) async {
    final id = await _insertRecord('savings_goals', goal.toMap());
    await _pushRow<SavingsGoal>(
      table: 'savings_goals',
      collection: 'goals',
      id: id,
      fromMap: SavingsGoal.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

  Future<List<SavingsGoal>> getAllSavingsGoals() async {
    final db = await database;
    final rows =
        await db.query('savings_goals', orderBy: 'targetAmount DESC');
    return rows.map(SavingsGoal.fromMap).toList();
  }

  Future<int> updateSavingsGoal(SavingsGoal goal) async {
    final id = goal.id;
    if (id == null) return 0;
    final count = await _updateRecord('savings_goals', id, {
      'title': goal.title,
      'targetAmount': goal.targetAmount,
      'savedAmount': goal.savedAmount,
      'deadline': goal.deadline?.toIso8601String(),
      'emoji': goal.emoji,
    });
    await _pushRow<SavingsGoal>(
      table: 'savings_goals',
      collection: 'goals',
      id: id,
      fromMap: SavingsGoal.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return count;
  }

  Future<int> deleteSavingsGoal(String id) async {
    final count = await _deleteRecord('savings_goals', id);
    await _pushDelete('goals', id);
    return count;
  }

  /// Wipes all local savings goals without touching the cloud (logout).
  Future<void> wipeLocalSavingsGoals() async {
    final db = await database;
    await db.delete('savings_goals');
  }

  // ----------------------------- custom places -----------------------

  Future<String> insertCustomPlace(CustomPlace place) async {
    final id = await _insertRecord('custom_places', place.toMap());
    await _pushRow<CustomPlace>(
      table: 'custom_places',
      collection: 'custom_places',
      id: id,
      fromMap: CustomPlace.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

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
  /// Returns the row id. The final row is pushed to Firestore.
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
    final String id;
    if (existing.isNotEmpty) {
      final row = existing.first;
      id = row['id'] as String;
      final updates = <String, dynamic>{
        'usageCount': ((row['usageCount'] as num?)?.toInt() ?? 0) + 1,
        'updatedAt': now,
      };
      if (emoji.isNotEmpty && (row['emoji'] as String? ?? '').isEmpty) {
        updates['emoji'] = emoji;
      }
      await db.update('custom_places', updates,
          where: 'id = ?', whereArgs: [id]);
    } else {
      id = await _insertRecord('custom_places', {
        'label': trimmed,
        'emoji': emoji,
        'usageCount': 1,
      });
    }
    await _pushRow<CustomPlace>(
      table: 'custom_places',
      collection: 'custom_places',
      id: id,
      fromMap: CustomPlace.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

  Future<int> deleteCustomPlace(String id) async {
    final count = await _deleteRecord('custom_places', id);
    await _pushDelete('custom_places', id);
    return count;
  }

  /// Wipes all local custom places without touching the cloud (logout).
  Future<void> wipeLocalCustomPlaces() async {
    final db = await database;
    await db.delete('custom_places');
  }

  // --------------------------- custom payments -----------------------

  Future<String> insertCustomPayment(CustomPayment payment) async {
    final id = await _insertRecord('custom_payment_methods', payment.toMap());
    await _pushRow<CustomPayment>(
      table: 'custom_payment_methods',
      collection: 'custom_payments',
      id: id,
      fromMap: CustomPayment.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

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
  /// Returns the row id. The final row is pushed to Firestore.
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
    final String id;
    if (existing.isNotEmpty) {
      final row = existing.first;
      id = row['id'] as String;
      await db.update(
        'custom_payment_methods',
        {
          'usageCount': ((row['usageCount'] as num?)?.toInt() ?? 0) + 1,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      id = await _insertRecord('custom_payment_methods', {
        'label': trimmed,
        'usageCount': 1,
      });
    }
    await _pushRow<CustomPayment>(
      table: 'custom_payment_methods',
      collection: 'custom_payments',
      id: id,
      fromMap: CustomPayment.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

  Future<int> deleteCustomPayment(String id) async {
    final count = await _deleteRecord('custom_payment_methods', id);
    await _pushDelete('custom_payments', id);
    return count;
  }

  /// Wipes all local custom payment methods without touching the cloud
  /// (logout).
  Future<void> wipeLocalCustomPayments() async {
    final db = await database;
    await db.delete('custom_payment_methods');
  }

  // ---------------------------- bill reminders -----------------------

  Future<String> insertBillReminder(BillReminder reminder) async {
    final id = await _insertRecord('bill_reminders', reminder.toMap());
    await _pushRow<BillReminder>(
      table: 'bill_reminders',
      collection: 'reminders',
      id: id,
      fromMap: BillReminder.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return id;
  }

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

  Future<int> updateBillReminder(BillReminder reminder) async {
    final id = reminder.id;
    if (id == null) return 0;
    final count = await _updateRecord('bill_reminders', id, {
      'title': reminder.title,
      'amount': reminder.amount,
      'dayOfMonth': reminder.dayOfMonth,
      'note': reminder.note,
      'active': reminder.active ? 1 : 0,
      'photo_path': reminder.photoPath,
    });
    await _pushRow<BillReminder>(
      table: 'bill_reminders',
      collection: 'reminders',
      id: id,
      fromMap: BillReminder.fromMap,
      toFirestore: (item) => item.toFirestore(),
    );
    return count;
  }

  Future<int> deleteBillReminder(String id) async {
    final count = await _deleteRecord('bill_reminders', id);
    await _pushDelete('reminders', id);
    return count;
  }

  /// Wipes all local bill reminders without touching the cloud (logout).
  Future<void> wipeLocalBillReminders() async {
    final db = await database;
    await db.delete('bill_reminders');
  }

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

  /// Built-in category ids the user chose to hide from pickers.
  /// Stored as a JSON list under the 'hidden_categories' setting key.
  static const String hiddenCategoriesKey = 'hidden_categories';

  Future<List<String>> getHiddenCategories() async {
    final raw = await getSetting(hiddenCategoriesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return [];
  }

  Future<void> setHiddenCategories(List<String> ids) async {
    await setSetting(hiddenCategoriesKey, jsonEncode(ids));
  }

  // --------------------------- custom categories ----------------------
  // User-created expense categories. Local-only: never synced to
  // Firestore.

  Future<List<CustomCategory>> getCustomCategories() async {
    final db = await database;
    final rows = await db.query('custom_categories', orderBy: 'name ASC');
    return rows.map(CustomCategory.fromMap).toList();
  }

  /// Inserts a user-created category. Returns the new id.
  /// NOTE: direct insert (not _insertRecord) — this table has no
  /// `updatedAt` column because custom categories are local-only (no sync).
  Future<String> insertCustomCategory(String name, String emoji) async {
    final db = await database;
    final id = const Uuid().v4();
    await db.insert('custom_categories', {
      'id': id,
      'name': name.trim(),
      'emoji': emoji.trim(),
    });
    return id;
  }

  Future<int> deleteCustomCategory(String id) async {
    return _deleteRecord('custom_categories', id);
  }

  Future<int> updateCustomCategory(
      String id, String name, String emoji) async {
    final db = await database;
    return db.update(
      'custom_categories',
      {'name': name.trim(), 'emoji': emoji.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --------------------------- notes --------------------
  Future<List<Map<String, dynamic>>> getNotes() async {
    final db = await database;
    return db.query('notes', orderBy: 'pinned DESC, updated DESC');
  }

  Future<String> insertNote(Map<String, dynamic> map) async {
    final db = await database;
    final id = map['id'] as String? ?? const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('notes', {
      ...map,
      'id': id,
      'updated': now,
      'updatedAt': now,
    });
    return id;
  }

  Future<int> updateNote(String id, Map<String, dynamic> map) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update('notes', {...map, 'updated': now, 'updatedAt': now},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteNote(String id) async {
    final db = await database;
    return db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------- notification center --------------------

  /// Inserts a notification-center entry. Returns the row id.
  Future<int> insertNotification({
    required String title,
    required String body,
    String type = 'info',
    String? dedupe,
  }) async {
    final db = await database;
    return db.insert('notifications', {
      'title': title,
      'body': body,
      'time': DateTime.now().millisecondsSinceEpoch,
      'read': 0,
      'type': type,
      'dedupe': dedupe,
    });
  }

  /// Newest first.
  Future<List<AppNotification>> getNotifications({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'notifications',
      orderBy: 'time DESC',
      limit: limit,
    );
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<int> unreadNotificationCount() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM notifications WHERE read = 0',
    );
    return ((rows.first['c'] as num?)?.toInt() ?? 0);
  }

  Future<void> markNotificationRead(int id) async {
    final db = await database;
    await db.update(
      'notifications',
      {'read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAllNotificationsRead() async {
    final db = await database;
    await db.update('notifications', {'read': 1});
  }

  Future<void> clearNotifications() async {
    final db = await database;
    await db.delete('notifications');
  }

  /// True when a notification with the same (type, dedupe) key already
  /// exists today — used to avoid spamming repeat alerts (budget warnings,
  /// recurring additions, due-today bill reminders).
  Future<bool> hasNotificationToday(String type, String dedupe) async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await db.query(
      'notifications',
      columns: ['id'],
      where: 'type = ? AND dedupe = ? AND time >= ?',
      whereArgs: [type, dedupe, startOfDay],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // --------------------------------- debts ---------------------------
  // Money lent to / borrowed from people. Local writes follow the
  // _insertRecord/_updateRecord/_deleteRecord UUID + updatedAt pattern;
  // no Firestore push here (sync wiring is owned by the sync package).

  /// Newest debt first; pass [settled] to show only settled or unsettled.
  Future<List<Debt>> getDebts({bool? settled}) async {
    final db = await database;
    final rows = await db.query(
      'debts',
      where: settled == null ? null : 'settled = ?',
      whereArgs: settled == null ? null : [settled ? 1 : 0],
      orderBy: 'date DESC',
    );
    return rows.map(Debt.fromMap).toList();
  }

  /// Inserts a debt record. Returns the new id.
  Future<String> insertDebt(Debt debt) async {
    return _insertRecord('debts', debt.toMap());
  }

  /// Marks a debt as paid off (settled = 1).
  Future<int> settleDebt(String id) async {
    return _updateRecord('debts', id, {'settled': 1});
  }

  Future<int> deleteDebt(String id) async {
    return _deleteRecord('debts', id);
  }

  // ----------------------------- subscriptions -----------------------
  // Recurring subscription reminders (Netflix, gym, ...).

  /// Earliest due date first.
  Future<List<AppSubscription>> getSubscriptions() async {
    final db = await database;
    final rows = await db.query('subscriptions', orderBy: 'next_due ASC');
    return rows.map(AppSubscription.fromMap).toList();
  }

  /// Inserts a subscription. Returns the new id.
  Future<String> insertSubscription(AppSubscription s) async {
    return _insertRecord('subscriptions', s.toMap());
  }

  /// Full row update by id.
  Future<int> updateSubscription(AppSubscription s) async {
    final id = s.id;
    if (id == null) return 0;
    return _updateRecord('subscriptions', id, {
      'name': s.name,
      'amount': s.amount,
      'cycle': s.cycle,
      'next_due': s.nextDue.millisecondsSinceEpoch,
      'emoji': s.emoji,
      'active': s.active ? 1 : 0,
    });
  }

  Future<int> deleteSubscription(String id) async {
    return _deleteRecord('subscriptions', id);
  }

  // --------------------------- expense templates ---------------------
  // Quick-add expense presets.

  /// Alphabetical by name.
  Future<List<ExpenseTemplate>> getTemplates() async {
    final db = await database;
    final rows = await db.query('templates', orderBy: 'name ASC');
    return rows.map(ExpenseTemplate.fromMap).toList();
  }

  /// Inserts a template. Returns the new id.
  Future<String> insertTemplate(ExpenseTemplate t) async {
    return _insertRecord('templates', t.toMap());
  }

  Future<int> deleteTemplate(String id) async {
    return _deleteRecord('templates', id);
  }

  // ------------------------------- wishlist --------------------------
  // Items the user is saving up for (Package M). Follows the v3 table
  // pattern: UUID ids + updatedAt; local-only for now (sync wiring is
  // owned by the sync package).

  /// Open items first, then bought ones; alphabetical within each group.
  Future<List<WishlistItem>> getWishlist() async {
    final db = await database;
    final rows = await db.query('wishlist', orderBy: 'done ASC, name ASC');
    return rows.map(WishlistItem.fromMap).toList();
  }

  /// Inserts a wishlist item. Returns the new id.
  Future<String> insertWishlist(WishlistItem w) async {
    return _insertRecord('wishlist', w.toMap());
  }

  /// Full row update by id.
  Future<int> updateWishlist(WishlistItem w) async {
    final id = w.id;
    if (id == null) return 0;
    return _updateRecord('wishlist', id, {
      'name': w.name,
      'target_price': w.targetPrice,
      'saved': w.saved,
      'emoji': w.emoji,
      'note': w.note,
      'done': w.done ? 1 : 0,
    });
  }

  Future<int> deleteWishlist(String id) async {
    return _deleteRecord('wishlist', id);
  }

  /// Wipes all local wishlist items without touching the cloud (logout).
  Future<void> wipeLocalWishlist() async {
    final db = await database;
    await db.delete('wishlist');
  }

  // ----------------------------- challenges --------------------------
  Future<List<Challenge>> getChallenges() async {
    final db = await database;
    final rows =
        await db.query('challenges', orderBy: 'start DESC');
    return rows.map(Challenge.fromMap).toList();
  }

  Future<Challenge?> getActiveChallenge() async {
    final db = await database;
    final rows = await db.query(
      'challenges',
      where: 'active = 1',
      orderBy: 'start DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Challenge.fromMap(rows.first);
  }

  Future<String> insertChallenge(Challenge c) async {
    return _insertRecord('challenges', c.toMap());
  }

  Future<int> updateChallenge(Challenge c) async {
    return _updateRecord('challenges', c.id ?? '', c.toMap());
  }

  Future<int> deleteChallenge(String id) async {
    return _deleteRecord('challenges', id);
  }

  // ---------------------------- achievements -------------------------
  Future<Set<String>> getUnlockedAchievements() async {
    final db = await database;
    final rows = await db.query('achievements', columns: ['id']);
    return rows.map((r) => r['id'].toString()).toSet();
  }

  // ------------------------ category learning ------------------------
  Future<void> learnCategoryWord(String word, String categoryId) async {
    final db = await database;
    await db.execute(
      'INSERT INTO category_learning(word, category_id, count) VALUES(?, ?, 1) '
      'ON CONFLICT(word, category_id) DO UPDATE SET count = count + 1',
      [word.toLowerCase(), categoryId],
    );
  }

  Future<String?> suggestCategoryForWords(List<String> words) async {
    if (words.isEmpty) return null;
    final db = await database;
    final q = words.map((_) => '?').join(',');
    final rows = await db.rawQuery(
      'SELECT category_id, SUM(count) AS c FROM category_learning '
      'WHERE word IN ($q) GROUP BY category_id ORDER BY c DESC LIMIT 1',
      words.map((w) => w.toLowerCase()).toList(),
    );
    if (rows.isEmpty) return null;
    return rows.first['category_id'] as String?;
  }

  // --------------------------- cash ledger ---------------------------
  Future<List<CashEntry>> getCashLedger() async {
    final db = await database;
    final rows = await db.query('cash_ledger', orderBy: 'date DESC');
    return rows.map(CashEntry.fromMap).toList();
  }

  Future<double> getCashBalance() async {
    final db = await database;
    final rows = await db.query('cash_ledger', columns: ['amount', 'type']);
    double bal = 0;
    for (final r in rows) {
      final a = (r['amount'] as num?)?.toDouble() ?? 0;
      bal += r['type'] == 'in' ? a : -a;
    }
    return bal;
  }

  Future<String> insertCashEntry(CashEntry e) async =>
      _insertRecord('cash_ledger', e.toMap());

  Future<int> deleteCashEntry(String id) async =>
      _deleteRecord('cash_ledger', id);

  // ----------------------------- fuel logs ---------------------------
  Future<List<FuelLog>> getFuelLogs() async {
    final db = await database;
    final rows = await db.query('fuel_logs', orderBy: 'date DESC');
    return rows.map(FuelLog.fromMap).toList();
  }

  Future<String> insertFuelLog(FuelLog f) async =>
      _insertRecord('fuel_logs', f.toMap());

  Future<int> deleteFuelLog(String id) async =>
      _deleteRecord('fuel_logs', id);

  // --------------------------- shopping list -------------------------
  Future<List<ShoppingItem>> getShoppingItems() async {
    final db = await database;
    final rows = await db.query('shopping_items',
        orderBy: 'done ASC, created DESC');
    return rows.map(ShoppingItem.fromMap).toList();
  }

  Future<String> insertShoppingItem(ShoppingItem i) async =>
      _insertRecord('shopping_items', i.toMap());

  Future<int> updateShoppingItem(ShoppingItem i) async =>
      _updateRecord('shopping_items', i.id ?? '', i.toMap());

  Future<int> deleteShoppingItem(String id) async =>
      _deleteRecord('shopping_items', id);

  // ------------------------------- gifts -----------------------------
  Future<List<Gift>> getGifts() async {
    final db = await database;
    final rows = await db.query('gifts', orderBy: 'date DESC');
    return rows.map(Gift.fromMap).toList();
  }

  Future<String> insertGift(Gift g) async =>
      _insertRecord('gifts', g.toMap());

  Future<int> deleteGift(String id) async => _deleteRecord('gifts', id);

  // --------------------------- emergency fund ------------------------
  Future<double> getEmergencyFund() async {
    final db = await database;
    final rows = await db.query('emergency_fund',
        where: "id = 'vault'", limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['amount'] as num?)?.toDouble() ?? 0;
  }

  Future<void> setEmergencyFund(double amount) async {
    final db = await database;
    await db.insert(
      'emergency_fund',
      {
        'id': 'vault',
        'amount': amount,
        'updated': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addEmergencyLedger(
      String id, double amount, String type, String note) async {
    final db = await database;
    await db.insert('emergency_ledger', {
      'id': id,
      'amount': amount,
      'type': type,
      'date': DateTime.now().millisecondsSinceEpoch,
      'note': note,
    });
  }

  Future<List<Map<String, dynamic>>> getEmergencyLedger() async {
    final db = await database;
    final rows = await db.query('emergency_ledger', orderBy: 'date DESC');
    return rows;
  }

  // ------------------------------ projects ---------------------------
  Future<List<Project>> getProjects() async {
    final db = await database;
    final rows = await db.query('projects', orderBy: 'start DESC');
    return rows.map(Project.fromMap).toList();
  }

  Future<String> insertProject(Project p) async =>
      _insertRecord('projects', p.toMap());

  Future<int> deleteProject(String id) async =>
      _deleteRecord('projects', id);

  Future<double> getProjectSpent(String projectId) async {
    final db = await database;
    final r = await db.rawQuery(
        'SELECT SUM(COALESCE(bdt_amount, amount)) AS t FROM expenses '
        "WHERE project_id = ?",
        [projectId]);
    return (r.first['t'] as num?)?.toDouble() ?? 0;
  }

  /// Total spent per project id in ONE query (batch alternative to
  /// calling [getProjectSpent] per project in a loop).
  Future<Map<String, double>> getAllProjectsSpent() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT project_id AS p, SUM(COALESCE(bdt_amount, amount)) AS t '
      'FROM expenses GROUP BY project_id',
    );
    final map = <String, double>{};
    for (final r in rows) {
      final id = r['p'] as String?;
      if (id != null && id.isNotEmpty) {
        map[id] = (r['t'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return map;
  }

  Future<void> unlockAchievement(String id) async {
    final db = await database;
    await db.insert(
      'achievements',
      {
        'id': id,
        'unlocked_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ----------------------------- salary rules ------------------------
  // Salary distribution rules (Package O). Local-only for now (sync
  // wiring is owned by the sync package).

  /// Highest percent first.
  Future<List<SalaryRule>> getSalaryRules() async {
    final db = await database;
    final rows = await db.query('salary_rules', orderBy: 'percent DESC');
    return rows.map(SalaryRule.fromMap).toList();
  }

  /// Inserts a salary rule. Returns the new id.
  Future<String> insertSalaryRule(SalaryRule rule) async {
    return _insertRecord('salary_rules', rule.toMap());
  }

  /// Full row update by id.
  Future<int> updateSalaryRule(SalaryRule rule) async {
    final id = rule.id;
    if (id == null) return 0;
    return _updateRecord('salary_rules', id, {
      'name': rule.name,
      'percent': rule.percent,
      'target_type': rule.targetType,
      'target_id': rule.targetId,
    });
  }

  Future<int> deleteSalaryRule(String id) async {
    return _deleteRecord('salary_rules', id);
  }
}
