import 'package:uuid/uuid.dart';

/// A single income record (salary, freelance, gift, ...).
///
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/incomes/{id}`).
class Income {
  final String? id;
  final double amount;
  final String source;
  final DateTime date;
  final String note;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  Income({
    this.id,
    required this.amount,
    required this.source,
    required this.date,
    this.note = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created income.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'source': source,
      'date': date.toIso8601String(),
      'note': note,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Income.fromMap(Map<String, dynamic> map) {
    return Income(
      id: map['id']?.toString(),
      amount: (map['amount'] as num).toDouble(),
      source: map['source'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String? ?? '',
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds an income from a Firestore document ([docId] is the document id).
  factory Income.fromFirestore(String docId, Map<String, dynamic> data) {
    return Income(
      id: docId,
      amount: (data['amount'] as num).toDouble(),
      source: data['source'] as String? ?? '',
      date: DateTime.parse(data['date'] as String),
      note: data['note'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'source': source,
      'date': date.toIso8601String(),
      'note': note,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Income copyWith({
    String? id,
    double? amount,
    String? source,
    DateTime? date,
    String? note,
    DateTime? updatedAt,
  }) {
    return Income(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      source: source ?? this.source,
      date: date ?? this.date,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
