import 'package:uuid/uuid.dart';

/// A salary distribution rule (Package O): when the monthly salary lands
/// on salary day, [percent] of it is routed to a target.
///
/// [targetType] is 'savings' ([targetId] = savings goal id), 'wishlist'
/// ([targetId] = wishlist item id) or 'budget' ([targetId] unused — the
/// share simply stays in the monthly budget).
///
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore. Salary rules are local-only for now (no sync wiring).
class SalaryRule {
  final String? id;
  final String name;

  /// Share of the salary, 0-100.
  final double percent;

  final String targetType;
  final String targetId;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  SalaryRule({
    this.id,
    required this.name,
    required this.percent,
    required this.targetType,
    this.targetId = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created rule.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'percent': percent,
      'target_type': targetType,
      'target_id': targetId,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SalaryRule.fromMap(Map<String, dynamic> map) {
    return SalaryRule(
      id: map['id']?.toString(),
      name: map['name'] as String? ?? '',
      percent: (map['percent'] as num).toDouble(),
      targetType: map['target_type'] as String? ?? 'budget',
      targetId: map['target_id']?.toString() ?? '',
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  SalaryRule copyWith({
    String? id,
    String? name,
    double? percent,
    String? targetType,
    String? targetId,
    DateTime? updatedAt,
  }) {
    return SalaryRule(
      id: id ?? this.id,
      name: name ?? this.name,
      percent: percent ?? this.percent,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
