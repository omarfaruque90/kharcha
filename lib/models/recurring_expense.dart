import 'package:uuid/uuid.dart';

/// An expense template that auto-adds a real expense once per month.
///
/// [dayOfMonth] is 1-31. [lastAddedMonth] is the `yyyy-MM` key of the month
/// the expense was last generated for (null = never).
/// [kind] is 'expense' (default) or 'income'. Income templates auto-add an
/// [Income] record instead of an [Expense] when they come due.
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/recurring_expenses/{id}`).
class RecurringExpense {
  final String? id;
  final double amount;
  final String categoryId;
  final String label;
  final int dayOfMonth;
  final String paymentMethod;
  final String note;
  final bool active;
  final String? lastAddedMonth;

  /// 'expense' or 'income'.
  final String kind;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  RecurringExpense({
    this.id,
    required this.amount,
    required this.categoryId,
    required this.label,
    required this.dayOfMonth,
    this.paymentMethod = 'cash',
    this.note = '',
    this.active = true,
    this.lastAddedMonth,
    this.kind = 'expense',
    DateTime? updatedAt,
  })  : assert(dayOfMonth >= 1 && dayOfMonth <= 31),
        updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created template.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'categoryId': categoryId,
      'label': label,
      'dayOfMonth': dayOfMonth,
      'paymentMethod': paymentMethod,
      'note': note,
      'active': active ? 1 : 0,
      'lastAddedMonth': lastAddedMonth,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'kind': kind,
    };
  }

  factory RecurringExpense.fromMap(Map<String, dynamic> map) {
    final activeRaw = map['active'];
    return RecurringExpense(
      id: map['id']?.toString(),
      amount: (map['amount'] as num).toDouble(),
      categoryId: map['categoryId'] as String,
      label: map['label'] as String? ?? '',
      dayOfMonth: (map['dayOfMonth'] as num).toInt(),
      paymentMethod: map['paymentMethod'] as String? ?? 'cash',
      note: map['note'] as String? ?? '',
      active: activeRaw is int
          ? activeRaw == 1
          : (activeRaw as bool? ?? true),
      lastAddedMonth: map['lastAddedMonth'] as String?,
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
      kind: map['kind'] as String? ?? 'expense',
    );
  }

  /// Builds a template from a Firestore document ([docId] is the document id).
  factory RecurringExpense.fromFirestore(
      String docId, Map<String, dynamic> data) {
    return RecurringExpense(
      id: docId,
      amount: (data['amount'] as num).toDouble(),
      categoryId: data['categoryId'] as String? ?? 'others',
      label: data['label'] as String? ?? '',
      dayOfMonth: (data['dayOfMonth'] as num?)?.toInt() ?? 1,
      paymentMethod: data['paymentMethod'] as String? ?? 'cash',
      note: data['note'] as String? ?? '',
      active: data['active'] as bool? ?? true,
      lastAddedMonth: data['lastAddedMonth'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
      kind: data['kind'] as String? ?? 'expense',
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'categoryId': categoryId,
      'label': label,
      'dayOfMonth': dayOfMonth,
      'paymentMethod': paymentMethod,
      'note': note,
      'active': active,
      'lastAddedMonth': lastAddedMonth,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'kind': kind,
    };
  }

  RecurringExpense copyWith({
    String? id,
    double? amount,
    String? categoryId,
    String? label,
    int? dayOfMonth,
    String? paymentMethod,
    String? note,
    bool? active,
    String? lastAddedMonth,
    bool clearLastAddedMonth = false,
    String? kind,
    DateTime? updatedAt,
  }) {
    return RecurringExpense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      label: label ?? this.label,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      note: note ?? this.note,
      active: active ?? this.active,
      lastAddedMonth:
          clearLastAddedMonth ? null : (lastAddedMonth ?? this.lastAddedMonth),
      kind: kind ?? this.kind,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
