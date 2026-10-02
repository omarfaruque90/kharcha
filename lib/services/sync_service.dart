import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../db/database_helper.dart';
import '../models/expense.dart';

/// Per-user Firestore sync for expenses.
///
/// SQLite stays the local store (offline-first); the cloud copy lives at
/// `users/{uid}/expenses/{expenseId}`. Conflicts resolve last-write-wins on
/// the `updatedAt` field.
///
/// Wiring contract (owned by the auth/main wiring):
/// - call [startSync] after login, [stopAndClear] on logout;
/// - listen to [remoteChanges] and reload the ExpenseProvider so the UI
///   reflects changes made on other devices.
class SyncService {
  SyncService._private();

  static final SyncService instance = SyncService._private();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

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
      _firestore.collection('users').doc(uid).collection('expenses');

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
  /// 3. attaches a live listener for remote changes.
  ///
  /// Cloud failures (offline, rules not configured yet) never break the
  /// local app: they are swallowed and the next sync reconciles.
  Future<void> startSync(String uid) async {
    await _ensurePersistence();
    await _subscription?.cancel();
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

  /// Stops sync, clears the uid, and wipes local expenses (privacy on
  /// logout). Cloud data is untouched.
  Future<void> stopAndClear() async {
    await _subscription?.cancel();
    _subscription = null;
    _uid = null;
    await DatabaseHelper.instance.wipeLocalExpenses();
  }
}
