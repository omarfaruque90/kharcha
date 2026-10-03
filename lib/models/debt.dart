import 'package:uuid/uuid.dart';

/// A debt record: money the user lent to someone or borrowed from someone.
///
/// [kind] is `'lent'` (someone owes the user) or `'borrowed'` (the user owes
/// someone). [settled] marks the debt as paid off. IDs are UUID strings so
/// the same record can live in SQLite and in Firestore
/// (`users/{uid}/debts/{id}`).
class Debt {
  final String? id;
  final String person;
  final double amount;
  final String kind;
  final DateTime date;
  final DateTime? dueDate;
  final String note;
  final bool settled;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  Debt({
    this.id,
    required this.person,
    required this.amount,
    required this.kind,
    required this.date,
    this.dueDate,
    this.note = '',
    this.settled = false,
    DateTime? updatedAt,
  })  : assert(kind == 'lent' || kind == 'borrowed'),
        updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created debt.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'person': person,
      'amount': amount,
      'kind': kind,
      'date': date.millisecondsSinceEpoch,
      'due_date': dueDate?.millisecondsSinceEpoch,
      'note': note,
      'settled': settled ? 1 : 0,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Debt.fromMap(Map<String, dynamic> map) {
    final settledRaw = map['settled'];
    final dueRaw = map['due_date'];
    return Debt(
      id: map['id']?.toString(),
      person: map['person'] as String? ?? '',
      amount: (map['amount'] as num).toDouble(),
      kind: map['kind'] as String? ?? 'lent',
      date: DateTime.fromMillisecondsSinceEpoch(
        (map['date'] as num).toInt(),
      ),
      dueDate: dueRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(dueRaw.toInt())
          : null,
      note: map['note'] as String? ?? '',
      settled: settledRaw is int
          ? settledRaw == 1
          : (settledRaw as bool? ?? false),
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a debt from a Firestore document ([docId] is the document id).
  factory Debt.fromFirestore(String docId, Map<String, dynamic> data) {
    return Debt(
      id: docId,
      person: data['person'] as String? ?? '',
      amount: (data['amount'] as num).toDouble(),
      kind: data['kind'] as String? ?? 'lent',
      date: DateTime.fromMillisecondsSinceEpoch(
        (data['date'] as num?)?.toInt() ?? 0,
      ),
      dueDate: data['due_date'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (data['due_date'] as num).toInt())
          : null,
      note: data['note'] as String? ?? '',
      settled: data['settled'] as bool? ?? false,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'person': person,
      'amount': amount,
      'kind': kind,
      'date': date.millisecondsSinceEpoch,
      'due_date': dueDate?.millisecondsSinceEpoch,
      'note': note,
      'settled': settled,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Debt copyWith({
    String? id,
    String? person,
    double? amount,
    String? kind,
    DateTime? date,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? note,
    bool? settled,
    DateTime? updatedAt,
  }) {
    return Debt(
      id: id ?? this.id,
      person: person ?? this.person,
      amount: amount ?? this.amount,
      kind: kind ?? this.kind,
      date: date ?? this.date,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      note: note ?? this.note,
      settled: settled ?? this.settled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
