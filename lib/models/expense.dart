import 'package:uuid/uuid.dart';

/// A single expense record.
///
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/expenses/{id}`).
class Expense {
  final String? id;
  final double amount;
  final String categoryId;
  final DateTime date;
  final String note;
  final String paymentMethod;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  Expense({
    this.id,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.paymentMethod = 'cash',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created expense.
  static String newId() => Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'categoryId': categoryId,
      'date': date.toIso8601String(),
      'note': note,
      'paymentMethod': paymentMethod,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      // Tolerant: v1 rows carried int ids before the UUID migration.
      id: map['id']?.toString(),
      amount: (map['amount'] as num).toDouble(),
      categoryId: map['categoryId'] as String,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String? ?? '',
      paymentMethod: map['paymentMethod'] as String? ?? 'cash',
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds an expense from a Firestore document ([docId] is the document id).
  factory Expense.fromFirestore(String docId, Map<String, dynamic> data) {
    return Expense(
      id: docId,
      amount: (data['amount'] as num).toDouble(),
      categoryId: data['category'] as String? ?? 'others',
      date: DateTime.parse(data['date'] as String),
      note: data['note'] as String? ?? '',
      paymentMethod: data['paymentMethod'] as String? ?? 'cash',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'category': categoryId,
      'date': date.toIso8601String(),
      'note': note,
      'paymentMethod': paymentMethod,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Expense copyWith({
    String? id,
    double? amount,
    String? categoryId,
    DateTime? date,
    String? note,
    String? paymentMethod,
    DateTime? updatedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
