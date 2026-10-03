import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../db/database_helper.dart';
import '../models/bill_reminder.dart';
import '../models/budget.dart';
import '../models/custom_payment.dart';
import '../models/custom_place.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/recurring_expense.dart';
import '../models/savings_goal.dart';

/// Per-user Firestore sync for expenses and the v4 money/custom tables.
///
/// SQLite stays the local store (offline-first); the cloud copy lives at
/// `users/{uid}/expenses/{expenseId}` plus one collection per secondary
/// type: `incomes`, `budgets`, `recurring`, `goals`, `reminders`,
/// `custom_places`, `custom_payments`. Doc ids are the UUID row ids.
/// Conflicts resolve last-write-wins on the `updatedAt` field.
///
/// Wiring contract (owned by the auth/main wiring):
/// - call [startSync] after login, [stopAndClear] on logout;
/// - listen to [remoteChanges] and reload providers so the UI reflects
///   changes made on other devices.
class SyncService {
  SyncService._private();

  static final SyncService instance = SyncService._private();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  /// Live listeners for the secondary collections (one per collection).
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _collectionSubscriptions = [];

  /// True while remote changes are being applied to SQLite.
  /// DatabaseHelper checks this so remote-applied writes are NOT
  /// pushed back to Firestore (no sync loops).
  bool _applyingRemote = false;
  bool get applyingRemote => _applyingRemote;

  /// Broadcast stream emitting after remote changes were applied locally.
  final StreamController<void> _remoteChanges =
      StreamController<void>.broadcast();

  /// Subscribe to refresh the UI when another device changes data.
  Stream<void> get remoteChanges => _remoteChanges.stream;

  bool _persistenceSet = false;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _userCollection(uid, 'expenses');

  CollectionReference<Map<String, dynamic>> _userCollection(
    String uid,
    String name,
  ) =>
      _firestore.collection('users').doc(uid).collection(name);

  /// Offline persistence is default on Android; set it explicitly once,
  /// before any Firestore operation runs.
  Future<void> _ensurePersistence() async {
    if (_persistenceSet) return;
    _persistenceSet = true;
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  /// Starts syncing for [uid]:
  /// 1. pulls remote docs, merging into SQLite last-write-wins;
  /// 2. pushes the merged local state up (covers offline-created rows);
  /// 3. attaches live listeners for remote changes.
  ///
  /// This covers expenses and every secondary collection (incomes,
  /// budgets, recurring, goals, reminders, custom_places, custom_payments).
  ///
  /// Cloud failures (offline, rules not configured yet) never break the
  /// local app: they are swallowed and the next sync reconciles.
  Future<void> startSync(String uid) async {
    await _ensurePersistence();
    await _subscription?.cancel();
    for (final s in _collectionSubscriptions) {
      await s.cancel();
    }
    _collectionSubscriptions.clear();
    _uid = uid;
    try {
      await _pullAndPush(uid);
    } catch (_) {
      // Cloud unreachable — local data keeps working; retry next login.
    }
    _subscription = _collection(uid).snapshots().listen(
          _onRemoteSnapshot,
          onError: (_) {},
        );
    await _startSecondarySyncs(uid);
  }

  /// Pulls + pushes every secondary collection, then attaches a live
  /// listener per collection. Each collection syncs independently: one
  /// failing collection never blocks the others.
  Future<void> _startSecondarySyncs(String uid) async {
    final db = DatabaseHelper.instance;
    await _syncCollection<Income>(
      uid: uid,
      name: 'incomes',
      getAll: db.getAllIncomes,
      upsert: db.upsertIncome,
      deleteLocal: (id) => db.deleteRemoteRecord('incomes', id),
      fromFirestore: Income.fromFirestore,
      toFirestore: (income) => income.toFirestore(),
      idOf: (income) => income.id,
      updatedAtOf: (income) => income.updatedAt,
    );
    await _syncCollection<Budget>(
      uid: uid,
      name: 'budgets',
      getAll: db.getAllBudgets,
      upsert: (budget) => db.upsertRemoteRecord('budgets', budget.toMap()),
      deleteLocal: (id) => db.deleteRemoteRecord('budgets', id),
      fromFirestore: Budget.fromFirestore,
      toFirestore: (budget) => budget.toFirestore(),
      idOf: (budget) => budget.id,
      updatedAtOf: (budget) => budget.updatedAt,
    );
    await _syncCollection<RecurringExpense>(
      uid: uid,
      name: 'recurring',
      getAll: db.getAllRecurringExpenses,
      upsert: (template) =>
          db.upsertRemoteRecord('recurring_expenses', template.toMap()),
      deleteLocal: (id) => db.deleteRemoteRecord('recurring_expenses', id),
      fromFirestore: RecurringExpense.fromFirestore,
      toFirestore: (template) => template.toFirestore(),
      idOf: (template) => template.id,
      updatedAtOf: (template) => template.updatedAt,
    );
    await _syncCollection<SavingsGoal>(
      uid: uid,
      name: 'goals',
      getAll: db.getAllSavingsGoals,
      upsert: (goal) => db.upsertRemoteRecord('savings_goals', goal.toMap()),
      deleteLocal: (id) => db.deleteRemoteRecord('savings_goals', id),
      fromFirestore: SavingsGoal.fromFirestore,
      toFirestore: (goal) => goal.toFirestore(),
      idOf: (goal) => goal.id,
      updatedAtOf: (goal) => goal.updatedAt,
    );
    await _syncCollection<BillReminder>(
      uid: uid,
      name: 'reminders',
      getAll: db.getAllBillReminders,
      upsert: (reminder) =>
          db.upsertRemoteRecord('bill_reminders', reminder.toMap()),
      deleteLocal: (id) => db.deleteRemoteRecord('bill_reminders', id),
      fromFirestore: BillReminder.fromFirestore,
      toFirestore: (reminder) => reminder.toFirestore(),
      idOf: (reminder) => reminder.id,
      updatedAtOf: (reminder) => reminder.updatedAt,
    );
    await _syncCollection<CustomPlace>(
      uid: uid,
      name: 'custom_places',
      getAll: db.getAllCustomPlaces,
      upsert: (place) =>
          db.upsertRemoteRecord('custom_places', place.toMap()),
      deleteLocal: (id) => db.deleteRemoteRecord('custom_places', id),
      fromFirestore: CustomPlace.fromFirestore,
      toFirestore: (place) => place.toFirestore(),
      idOf: (place) => place.id,
      updatedAtOf: (place) => place.updatedAt,
    );
    await _syncCollection<CustomPayment>(
      uid: uid,
      name: 'custom_payments',
      getAll: db.getAllCustomPayments,
      upsert: (payment) =>
          db.upsertRemoteRecord('custom_payment_methods', payment.toMap()),
      deleteLocal: (id) =>
          db.deleteRemoteRecord('custom_payment_methods', id),
      fromFirestore: CustomPayment.fromFirestore,
      toFirestore: (payment) => payment.toFirestore(),
      idOf: (payment) => payment.id,
      updatedAtOf: (payment) => payment.updatedAt,
    );
  }

  /// Syncs one secondary collection: pull (last-write-wins merge into
  /// SQLite), push the merged local state, then attach a live listener.
  /// Cloud failures are swallowed — local data keeps working.
  Future<void> _syncCollection<T>({
    required String uid,
    required String name,
    required Future<List<T>> Function() getAll,
    required Future<void> Function(T item) upsert,
    required Future<void> Function(String id) deleteLocal,
    required T Function(String docId, Map<String, dynamic> data) fromFirestore,
    required Map<String, dynamic> Function(T item) toFirestore,
    required String? Function(T item) idOf,
    required DateTime Function(T item) updatedAtOf,
  }) async {
    final col = _userCollection(uid, name);
    try {
      // 1. Pull: merge remote docs into SQLite (last-write-wins on updatedAt).
      final localById = <String, T>{};
      for (final item in await getAll()) {
        final id = idOf(item);
        if (id != null) localById[id] = item;
      }
      final snapshot = await col.get();
      _applyingRemote = true;
      try {
        for (final doc in snapshot.docs) {
          final remote = fromFirestore(doc.id, doc.data());
          final id = idOf(remote);
          if (id == null) continue;
          final existing = localById[id];
          if (existing == null ||
              updatedAtOf(remote).isAfter(updatedAtOf(existing))) {
            await upsert(remote);
            localById[id] = remote;
          }
        }
      } finally {
        _applyingRemote = false;
      }

      // 2. Push: upload merged local state (idempotent; covers rows
      // created while logged out or while the cloud was unreachable).
      for (final item in localById.values) {
        final id = idOf(item);
        if (id != null) await pushRecord(name, id, toFirestore(item));
      }
    } catch (_) {
      // Cloud unreachable — local data keeps working; retry next login.
    }
    _collectionSubscriptions.add(
      col.snapshots().listen(
        (snap) => _onRemoteCollectionSnapshot<T>(
          snap,
          fromFirestore: fromFirestore,
          upsert: upsert,
          deleteLocal: deleteLocal,
        ),
        onError: (_) {},
      ),
    );
  }

  Future<void> _pullAndPush(String uid) async {
    final db = DatabaseHelper.instance;
    final col = _collection(uid);

    // 1. Pull: merge remote docs into SQLite (last-write-wins on updatedAt).
    final localById = <String, Expense>{};
    for (final e in await db.getAllExpenses()) {
      final id = e.id;
      if (id != null) localById[id] = e;
    }
    final snapshot = await col.get();
    _applyingRemote = true;
    try {
      for (final doc in snapshot.docs) {
        final remote = Expense.fromFirestore(doc.id, doc.data());
        final existing = localById[remote.id];
        if (existing == null ||
            remote.updatedAt.isAfter(existing.updatedAt)) {
          await db.upsertExpense(remote);
          localById[remote.id!] = remote;
        }
      }
    } finally {
      _applyingRemote = false;
    }

    // 2. Push: upload merged local state (idempotent; covers rows
    // created while logged out or while the cloud was unreachable).
    for (final e in localById.values) {
      await pushExpense(e);
    }
  }

  Future<void> _onRemoteSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final db = DatabaseHelper.instance;
    var changed = false;
    _applyingRemote = true;
    try {
      for (final change in snap.docChanges) {
        switch (change.type) {
          case DocumentChangeType.added:
          case DocumentChangeType.modified:
            final data = change.doc.data();
            if (data != null) {
              await db.upsertExpense(
                Expense.fromFirestore(change.doc.id, data),
              );
              changed = true;
            }
            break;
          case DocumentChangeType.removed:
            await db.deleteExpenseLocal(change.doc.id);
            changed = true;
            break;
        }
      }
    } finally {
      _applyingRemote = false;
    }
    if (changed && !_remoteChanges.isClosed) {
      _remoteChanges.add(null);
    }
  }

  /// Applies one secondary-collection snapshot to SQLite under the
  /// [_applyingRemote] guard, then notifies [remoteChanges] listeners.
  Future<void> _onRemoteCollectionSnapshot<T>(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required T Function(String docId, Map<String, dynamic> data) fromFirestore,
    required Future<void> Function(T item) upsert,
    required Future<void> Function(String id) deleteLocal,
  }) async {
    var changed = false;
    _applyingRemote = true;
    try {
      for (final change in snap.docChanges) {
        switch (change.type) {
          case DocumentChangeType.added:
          case DocumentChangeType.modified:
            final data = change.doc.data();
            if (data != null) {
              await upsert(fromFirestore(change.doc.id, data));
              changed = true;
            }
            break;
          case DocumentChangeType.removed:
            await deleteLocal(change.doc.id);
            changed = true;
            break;
        }
      }
    } finally {
      _applyingRemote = false;
    }
    if (changed && !_remoteChanges.isClosed) {
      _remoteChanges.add(null);
    }
  }

  /// Pushes one expense to the cloud. No-op when logged out.
  Future<void> pushExpense(Expense expense) async {
    final uid = _uid;
    final id = expense.id;
    if (uid == null || id == null) return;
    try {
      await _collection(uid).doc(id).set(expense.toFirestore());
    } catch (_) {
      // Offline/transient: the write stays queued in the Firestore cache
      // and the next startSync reconciles. Never break local UX.
    }
  }

  /// Deletes one cloud document. No-op when logged out.
  Future<void> pushDelete(String id) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _collection(uid).doc(id).delete();
    } catch (_) {}
  }

  /// Pushes one record to the secondary [collection] (doc id [id]).
  /// No-op when logged out. Used by DatabaseHelper after local writes.
  Future<void> pushRecord(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _userCollection(uid, collection).doc(id).set(data);
    } catch (_) {
      // Offline/transient: queued in the Firestore cache; the next
      // startSync reconciles. Never break local UX.
    }
  }

  /// Deletes one document from the secondary [collection].
  /// No-op when logged out.
  Future<void> pushRecordDelete(String collection, String id) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _userCollection(uid, collection).doc(id).delete();
    } catch (_) {}
  }

  /// Stops sync, clears the uid, and wipes all local synced tables
  /// (privacy on logout). Cloud data is untouched.
  Future<void> stopAndClear() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final s in _collectionSubscriptions) {
      await s.cancel();
    }
    _collectionSubscriptions.clear();
    _uid = null;
    final db = DatabaseHelper.instance;
    await db.wipeLocalExpenses();
    await db.wipeLocalIncomes();
    await db.wipeLocalBudgets();
    await db.wipeLocalRecurringExpenses();
    await db.wipeLocalSavingsGoals();
    await db.wipeLocalCustomPlaces();
    await db.wipeLocalCustomPayments();
    await db.wipeLocalBillReminders();
  }
}
