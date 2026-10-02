import 'package:uuid/uuid.dart';

/// A per-category spending limit for one calendar month.
///
/// [monthKey] is `yyyy-MM`, e.g. `"2026-10"`. One budget per
/// (categoryId, monthKey) pair.
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/budgets/{id}`).
class Budget {
  final String? id;
  final String categoryId;
  final String monthKey;
  final double limitAmount;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  Budget({
    this.id,
    required this.categoryId,
    required this.monthKey,
    required this.limitAmount,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created budget.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'categoryId': categoryId,
      'monthKey': monthKey,
      'limitAmount': limitAmount,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id']?.toString(),
      categoryId: map['categoryId'] as String,
      monthKey: map['monthKey'] as String,
      limitAmount: (map['limitAmount'] as num).toDouble(),
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a budget from a Firestore document ([docId] is the document id).
  factory Budget.fromFirestore(String docId, Map<String, dynamic> data) {
    return Budget(
      id: docId,
      categoryId: data['categoryId'] as String,
      monthKey: data['monthKey'] as String,
      limitAmount: (data['limitAmount'] as num).toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'categoryId': categoryId,
      'monthKey': monthKey,
      'limitAmount': limitAmount,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Budget copyWith({
    String? id,
    String? categoryId,
    String? monthKey,
    double? limitAmount,
    DateTime? updatedAt,
  }) {
    return Budget(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      monthKey: monthKey ?? this.monthKey,
      limitAmount: limitAmount ?? this.limitAmount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
