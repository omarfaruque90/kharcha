import 'package:cloud_firestore/cloud_firestore.dart';

import '../db/database_helper.dart';
import '../models/budget.dart';

/// Package BI — community budget templates shared via the public
/// `public_templates` Firestore collection.
///
/// Unlike the per-user synced collections (see [SyncService]), this is a
/// single public collection:
/// - read: anyone (the app works logged out for templates);
/// - write (publish/like): any authenticated user.
///   See the Firestore rules note in the v0.3 implementation report.
///
/// All failures are swallowed: templates are a bonus feature and must
/// never break the local app.
class PublicTemplatesService {
  PublicTemplatesService._private();

  static final PublicTemplatesService instance =
      PublicTemplatesService._private();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('public_templates');

  /// Most-liked templates first, capped at 50.
  ///
  /// Returns a list of maps with keys:
  /// `id`, `name`, `budgets` (list of `{category, amount}`),
  /// `likes` (int), `authorName`.
  Future<List<Map<String, dynamic>>> browse() async {
    try {
      final snap = await _collection
          .orderBy('likes', descending: true)
          .limit(50)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        final rawBudgets = data['budgets'];
        final budgets = <Map<String, dynamic>>[];
        if (rawBudgets is List) {
          for (final item in rawBudgets) {
            if (item is Map<String, dynamic>) budgets.add(item);
          }
        }
        return {
          'id': doc.id,
          'name': (data['name'] ?? '').toString(),
          'budgets': budgets,
          'likes': (data['likes'] as num?)?.toInt() ?? 0,
          'authorName': (data['authorName'] ?? '').toString(),
        };
      }).toList(growable: false);
      // If Firestore is empty, show built-in starter templates.
      if (result.isEmpty) return _builtInTemplates();
      return result;
    } catch (_) {
      // Offline / rules not deployed yet: show built-in templates.
      return _builtInTemplates();
    }
  }

  /// Built-in starter templates shown when Firestore has none.
  List<Map<String, dynamic>> _builtInTemplates() {
    return [
      {
        'id': 'builtin_student',
        'name': 'Student Budget',
        'budgets': [
          {'category': 'food', 'amount': 3000},
          {'category': 'transport', 'amount': 1500},
          {'category': 'education', 'amount': 2000},
          {'category': 'entertainment', 'amount': 1000},
        ],
        'likes': 128,
        'authorName': 'Khorcha Team',
        'builtIn': true,
      },
      {
        'id': 'builtin_family',
        'name': 'Family Budget',
        'budgets': [
          {'category': 'food', 'amount': 15000},
          {'category': 'housing', 'amount': 12000},
          {'category': 'transport', 'amount': 4000},
          {'category': 'health', 'amount': 3000},
          {'category': 'education', 'amount': 5000},
        ],
        'likes': 96,
        'authorName': 'Khorcha Team',
        'builtIn': true,
      },
      {
        'id': 'builtin_saver',
        'name': 'Saver Budget',
        'budgets': [
          {'category': 'food', 'amount': 8000},
          {'category': 'transport', 'amount': 2500},
          {'category': 'savings', 'amount': 10000},
          {'category': 'entertainment', 'amount': 1500},
        ],
        'likes': 84,
        'authorName': 'Khorcha Team',
        'builtIn': true,
      },
    ];
  }

  /// Increments the like counter on one template (anonymous-friendly
  /// since the service itself doesn't track who liked what; the UI
  /// de-dupes per session).
  Future<void> like(String id) async {
    try {
      await _collection.doc(id).update({
        'likes': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  /// Publishes the user's budget list as a public template.
  Future<void> publish(
    String name,
    List<Budget> budgets,
    String authorName,
  ) async {
    try {
      await _collection.add({
        'name': name.trim(),
        'budgets': budgets
            .map((b) => {
                  'category': b.categoryId,
                  'amount': b.limitAmount,
                })
            .toList(growable: false),
        'likes': 0,
        'authorName': authorName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Replaces the local budgets of [monthKey] with the template's
  /// budgets. Each inserted row syncs to the user's private Firestore
  /// `users/{uid}/budgets` via DatabaseHelper (when logged in).
  Future<void> applyTemplate(
    Map<String, dynamic> template,
    String monthKey,
  ) async {
    try {
      final db = DatabaseHelper.instance;
      for (final existing in await db.getBudgetsForMonth(monthKey)) {
        final id = existing.id;
        if (id != null) await db.deleteBudget(id);
      }
      final rawBudgets = template['budgets'];
      if (rawBudgets is! List) return;
      for (final item in rawBudgets) {
        if (item is! Map<String, dynamic>) continue;
        final category = (item['category'] ?? '').toString();
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
        if (category.isEmpty || amount <= 0) continue;
        await db.insertBudget(Budget(
          categoryId: category,
          monthKey: monthKey,
          limitAmount: amount,
        ));
      }
    } catch (_) {}
  }
}
