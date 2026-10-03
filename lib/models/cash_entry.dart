import 'package:uuid/uuid.dart';

/// Physical cash movement. type: 'in' (added cash) / 'out' (spent cash).
class CashEntry {
  final String? id;
  final double amount;
  final String type;
  final DateTime date;
  final String note;

  CashEntry({
    this.id,
    required this.amount,
    required this.type,
    DateTime? date,
    this.note = '',
  }) : date = date ?? DateTime.now();

  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'type': type,
        'date': date.millisecondsSinceEpoch,
        'note': note,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory CashEntry.fromMap(Map<String, dynamic> m) => CashEntry(
        id: m['id']?.toString(),
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        type: m['type'] as String? ?? 'out',
        date: DateTime.fromMillisecondsSinceEpoch(
            (m['date'] as num?)?.toInt() ?? 0),
        note: m['note'] as String? ?? '',
      );
}
