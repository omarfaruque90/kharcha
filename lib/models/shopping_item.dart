import 'package:uuid/uuid.dart';

class ShoppingItem {
  final String? id;
  final String name;
  final double qty;
  final String unit; // 'pcs', 'kg', 'g', 'L'
  final double price;
  final bool done;
  final DateTime created;

  ShoppingItem({
    this.id,
    required this.name,
    this.qty = 1,
    this.unit = 'pcs',
    this.price = 0,
    this.done = false,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'qty': qty,
        'unit': unit,
        'price': price,
        'done': done ? 1 : 0,
        'created': created.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory ShoppingItem.fromMap(Map<String, dynamic> m) => ShoppingItem(
        id: m['id']?.toString(),
        name: m['name'] as String? ?? '',
        qty: (m['qty'] as num?)?.toDouble() ?? 1,
        unit: m['unit'] as String? ?? 'pcs',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        done: (m['done'] as num?)?.toInt() == 1,
        created: DateTime.fromMillisecondsSinceEpoch(
            (m['created'] as num?)?.toInt() ?? 0),
      );

  ShoppingItem copyWith({String? id, String? name, double? qty,
      String? unit, double? price, bool? done}) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      qty: qty ?? this.qty,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      done: done ?? this.done,
      created: created,
    );
  }
}
