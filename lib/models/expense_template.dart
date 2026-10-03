import 'package:uuid/uuid.dart';

/// A quick-add expense template: a named preset (amount + category +
/// payment method + emoji) the user can tap to fill the add-expense form.
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/templates/{id}`).
class ExpenseTemplate {
  final String? id;
  final String name;
  final double amount;
  final String categoryId;
  final String payment;
  final String emoji;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  ExpenseTemplate({
    this.id,
    required this.name,
    required this.amount,
    this.categoryId = '',
    this.payment = 'cash',
    this.emoji = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created template.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'category_id': categoryId,
      'payment': payment,
      'emoji': emoji,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ExpenseTemplate.fromMap(Map<String, dynamic> map) {
    return ExpenseTemplate(
      id: map['id']?.toString(),
      name: map['name'] as String? ?? '',
      amount: (map['amount'] as num).toDouble(),
      categoryId: map['category_id'] as String? ?? '',
      payment: map['payment'] as String? ?? 'cash',
      emoji: map['emoji'] as String? ?? '',
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a template from a Firestore document ([docId] is the
  /// document id).
  factory ExpenseTemplate.fromFirestore(
      String docId, Map<String, dynamic> data) {
    return ExpenseTemplate(
      id: docId,
      name: data['name'] as String? ?? '',
      amount: (data['amount'] as num).toDouble(),
      categoryId: data['category_id'] as String? ?? '',
      payment: data['payment'] as String? ?? 'cash',
      emoji: data['emoji'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'amount': amount,
      'category_id': categoryId,
      'payment': payment,
      'emoji': emoji,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  ExpenseTemplate copyWith({
    String? id,
    String? name,
    double? amount,
    String? categoryId,
    String? payment,
    String? emoji,
    DateTime? updatedAt,
  }) {
    return ExpenseTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      payment: payment ?? this.payment,
      emoji: emoji ?? this.emoji,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
