import 'package:uuid/uuid.dart';

/// A no-spend challenge (e.g. 7 days with zero expenses).
class Challenge {
  final String? id;
  final String type;
  final DateTime start;
  final DateTime end;
  final int streak;
  final bool active;
  final DateTime updatedAt;

  Challenge({
    this.id,
    required this.type,
    required this.start,
    required this.end,
    this.streak = 0,
    this.active = true,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'streak': streak,
      'active': active ? 1 : 0,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Challenge.fromMap(Map<String, dynamic> map) {
    return Challenge(
      id: map['id']?.toString(),
      type: map['type'] as String? ?? 'no_spend',
      start: DateTime.fromMillisecondsSinceEpoch(
          (map['start'] as num?)?.toInt() ?? 0),
      end: DateTime.fromMillisecondsSinceEpoch(
          (map['end'] as num?)?.toInt() ?? 0),
      streak: (map['streak'] as num?)?.toInt() ?? 0,
      active: (map['active'] as num?)?.toInt() == 1,
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  Challenge copyWith({
    String? id,
    String? type,
    DateTime? start,
    DateTime? end,
    int? streak,
    bool? active,
  }) {
    return Challenge(
      id: id ?? this.id,
      type: type ?? this.type,
      start: start ?? this.start,
      end: end ?? this.end,
      streak: streak ?? this.streak,
      active: active ?? this.active,
      updatedAt: DateTime.now(),
    );
  }
}
