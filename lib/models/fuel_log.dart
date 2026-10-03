import 'package:uuid/uuid.dart';

class FuelLog {
  final String? id;
  final DateTime date;
  final double liters;
  final double pricePerLiter;
  final double total;
  final double odometer;
  final String note;

  FuelLog({
    this.id,
    DateTime? date,
    this.liters = 0,
    this.pricePerLiter = 0,
    this.total = 0,
    this.odometer = 0,
    this.note = '',
  }) : date = date ?? DateTime.now();

  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'liters': liters,
        'price_per_liter': pricePerLiter,
        'total': total,
        'odometer': odometer,
        'note': note,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory FuelLog.fromMap(Map<String, dynamic> m) => FuelLog(
        id: m['id']?.toString(),
        date: DateTime.fromMillisecondsSinceEpoch(
            (m['date'] as num?)?.toInt() ?? 0),
        liters: (m['liters'] as num?)?.toDouble() ?? 0,
        pricePerLiter:
            (m['price_per_liter'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        odometer: (m['odometer'] as num?)?.toDouble() ?? 0,
        note: m['note'] as String? ?? '',
      );
}
