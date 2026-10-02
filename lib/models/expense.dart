/// A single expense record.
class Expense {
  final int? id;
  final double amount;
  final String categoryId;
  final DateTime date;
  final String note;
  final String paymentMethod;

  const Expense({
    this.id,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.paymentMethod = 'cash',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'categoryId': categoryId,
      'date': date.toIso8601String(),
      'note': note,
      'paymentMethod': paymentMethod,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      categoryId: map['categoryId'] as String,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String? ?? '',
      paymentMethod: map['paymentMethod'] as String? ?? 'cash',
    );
  }

  Expense copyWith({
    int? id,
    double? amount,
    String? categoryId,
    DateTime? date,
    String? note,
    String? paymentMethod,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}
