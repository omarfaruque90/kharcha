import 'package:uuid/uuid.dart';

/// A spending project (e.g. a trip). Expenses link via expense.projectId.
class Project {
  final String? id;
  final String name;
  final DateTime start;
  final DateTime end;
  final double budget;

  Project({
    this.id,
    required this.name,
    DateTime? start,
    DateTime? end,
    this.budget = 0,
  })  : start = start ?? DateTime.now(),
        end = end ?? DateTime.now().add(const Duration(days: 7));

  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'budget': budget,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: m['id']?.toString(),
        name: m['name'] as String? ?? '',
        start: DateTime.fromMillisecondsSinceEpoch(
            (m['start'] as num?)?.toInt() ?? 0),
        end: DateTime.fromMillisecondsSinceEpoch(
            (m['end'] as num?)?.toInt() ?? 0),
        budget: (m['budget'] as num?)?.toDouble() ?? 0,
      );
}
