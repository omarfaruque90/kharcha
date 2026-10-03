import 'package:uuid/uuid.dart';

/// Gift given or received. kind: 'given' / 'received'.
class Gift {
  final String? id;
  final String person;
  final String occasion;
  final double amount;
  final String kind;
  final DateTime date;
  final String note;

  Gift({
    this.id,
    required this.person,
    this.occasion = '',
    this.amount = 0,
    this.kind = 'given',
    DateTime? date,
    this.note = '',
  }) : date = date ?? DateTime.now();

  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'person': person,
        'occasion': occasion,
        'amount': amount,
        'kind': kind,
        'date': date.millisecondsSinceEpoch,
        'note': note,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory Gift.fromMap(Map<String, dynamic> m) => Gift(
        id: m['id']?.toString(),
        person: m['person'] as String? ?? '',
        occasion: m['occasion'] as String? ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        kind: m['kind'] as String? ?? 'given',
        date: DateTime.fromMillisecondsSinceEpoch(
            (m['date'] as num?)?.toInt() ?? 0),
        note: m['note'] as String? ?? '',
      );
}
