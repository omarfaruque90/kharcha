import 'package:uuid/uuid.dart';

/// A user-typed custom expense place (e.g. "Dhanmondi Lake 🎮") saved for
/// reuse. [usageCount] ranks suggestions by how often each label was used.
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/custom_places/{id}`).
class CustomPlace {
  final String? id;
  final String label;
  final String emoji;
  final int usageCount;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  CustomPlace({
    this.id,
    required this.label,
    this.emoji = '',
    this.usageCount = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created custom place.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'emoji': emoji,
      'usageCount': usageCount,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CustomPlace.fromMap(Map<String, dynamic> map) {
    return CustomPlace(
      id: map['id']?.toString(),
      label: map['label'] as String? ?? '',
      emoji: map['emoji'] as String? ?? '',
      usageCount: (map['usageCount'] as num?)?.toInt() ?? 0,
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a custom place from a Firestore document ([docId] is the id).
  factory CustomPlace.fromFirestore(String docId, Map<String, dynamic> data) {
    return CustomPlace(
      id: docId,
      label: data['label'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '',
      usageCount: (data['usageCount'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'label': label,
      'emoji': emoji,
      'usageCount': usageCount,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  CustomPlace copyWith({
    String? id,
    String? label,
    String? emoji,
    int? usageCount,
    DateTime? updatedAt,
  }) {
    return CustomPlace(
      id: id ?? this.id,
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
      usageCount: usageCount ?? this.usageCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
