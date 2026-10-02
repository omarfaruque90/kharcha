import 'package:uuid/uuid.dart';

/// A savings goal with a progress bar.
///
/// [deadline] is an ISO-8601 string or null (no deadline).
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/savings_goals/{id}`).
class SavingsGoal {
  final String? id;
  final String title;
  final double targetAmount;
  final double savedAmount;
  final DateTime? deadline;
  final String emoji;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  SavingsGoal({
    this.id,
    required this.title,
    required this.targetAmount,
    this.savedAmount = 0,
    this.deadline,
    this.emoji = '💰',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created goal.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'deadline': deadline?.toIso8601String(),
      'emoji': emoji,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SavingsGoal.fromMap(Map<String, dynamic> map) {
    final deadlineRaw = map['deadline'] as String?;
    return SavingsGoal(
      id: map['id']?.toString(),
      title: map['title'] as String? ?? '',
      targetAmount: (map['targetAmount'] as num).toDouble(),
      savedAmount: (map['savedAmount'] as num?)?.toDouble() ?? 0,
      deadline: deadlineRaw != null ? DateTime.parse(deadlineRaw) : null,
      emoji: map['emoji'] as String? ?? '💰',
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a goal from a Firestore document ([docId] is the document id).
  factory SavingsGoal.fromFirestore(String docId, Map<String, dynamic> data) {
    final deadlineRaw = data['deadline'] as String?;
    return SavingsGoal(
      id: docId,
      title: data['title'] as String? ?? '',
      targetAmount: (data['targetAmount'] as num).toDouble(),
      savedAmount: (data['savedAmount'] as num?)?.toDouble() ?? 0,
      deadline: deadlineRaw != null ? DateTime.parse(deadlineRaw) : null,
      emoji: data['emoji'] as String? ?? '💰',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'deadline': deadline?.toIso8601String(),
      'emoji': emoji,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  SavingsGoal copyWith({
    String? id,
    String? title,
    double? targetAmount,
    double? savedAmount,
    DateTime? deadline,
    bool clearDeadline = false,
    String? emoji,
    DateTime? updatedAt,
  }) {
    return SavingsGoal(
      id: id ?? this.id,
      title: title ?? this.title,
      targetAmount: targetAmount ?? this.targetAmount,
      savedAmount: savedAmount ?? this.savedAmount,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      emoji: emoji ?? this.emoji,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
