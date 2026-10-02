import 'package:uuid/uuid.dart';

/// A user-typed custom payment method (e.g. a bank name under "Other")
/// saved for reuse. [usageCount] ranks suggestions by how often each label
/// was used.
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/custom_payment_methods/{id}`).
class CustomPayment {
  final String? id;
  final String label;
  final int usageCount;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  CustomPayment({
    this.id,
    required this.label,
    this.usageCount = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created custom payment.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'usageCount': usageCount,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CustomPayment.fromMap(Map<String, dynamic> map) {
    return CustomPayment(
      id: map['id']?.toString(),
      label: map['label'] as String? ?? '',
      usageCount: (map['usageCount'] as num?)?.toInt() ?? 0,
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a custom payment from a Firestore document ([docId] is the id).
  factory CustomPayment.fromFirestore(
      String docId, Map<String, dynamic> data) {
    return CustomPayment(
      id: docId,
      label: data['label'] as String? ?? '',
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
      'usageCount': usageCount,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  CustomPayment copyWith({
    String? id,
    String? label,
    int? usageCount,
    DateTime? updatedAt,
  }) {
    return CustomPayment(
      id: id ?? this.id,
      label: label ?? this.label,
      usageCount: usageCount ?? this.usageCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
