import 'package:uuid/uuid.dart';

/// A wishlist item (Package M): something the user wants to save up for
/// and eventually buy.
///
/// [targetPrice] is the price of the item; [saved] is how much money has
/// been set aside so far. [done] marks the item as bought (the card stays
/// visible so the user keeps a record). IDs are UUID strings so the same
/// record can live in SQLite and in Firestore
/// (`users/{uid}/wishlist/{id}`).
class WishlistItem {
  final String? id;
  final String name;
  final double targetPrice;
  final double saved;
  final String emoji;
  final String note;
  final bool done;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  WishlistItem({
    this.id,
    required this.name,
    required this.targetPrice,
    this.saved = 0,
    this.emoji = '',
    this.note = '',
    this.done = false,
    DateTime? updatedAt,
  })  : assert(targetPrice >= 0),
        updatedAt = updatedAt ?? DateTime.now();

  /// Progress of the saving goal, 0.0-1.0 (clamped).
  double get progress {
    if (targetPrice <= 0) return 0;
    return (saved / targetPrice).clamp(0.0, 1.0);
  }

  /// True once the target has been reached, regardless of [done].
  bool get targetReached => saved >= targetPrice;

  /// Generates a new UUID v4 id for a locally created wishlist item.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'target_price': targetPrice,
      'saved': saved,
      'emoji': emoji,
      'note': note,
      'done': done ? 1 : 0,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory WishlistItem.fromMap(Map<String, dynamic> map) {
    final doneRaw = map['done'];
    return WishlistItem(
      id: map['id']?.toString(),
      name: map['name'] as String? ?? '',
      targetPrice: (map['target_price'] as num).toDouble(),
      saved: (map['saved'] as num?)?.toDouble() ?? 0,
      emoji: map['emoji'] as String? ?? '',
      note: map['note'] as String? ?? '',
      done: doneRaw is int
          ? doneRaw == 1
          : (doneRaw as bool? ?? false),
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a wishlist item from a Firestore document ([docId] is the
  /// document id).
  factory WishlistItem.fromFirestore(String docId, Map<String, dynamic> data) {
    return WishlistItem(
      id: docId,
      name: data['name'] as String? ?? '',
      targetPrice: (data['target_price'] as num?)?.toDouble() ?? 0,
      saved: (data['saved'] as num?)?.toDouble() ?? 0,
      emoji: data['emoji'] as String? ?? '',
      note: data['note'] as String? ?? '',
      done: data['done'] as bool? ?? false,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'target_price': targetPrice,
      'saved': saved,
      'emoji': emoji,
      'note': note,
      'done': done,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  WishlistItem copyWith({
    String? id,
    String? name,
    double? targetPrice,
    double? saved,
    String? emoji,
    String? note,
    bool? done,
    DateTime? updatedAt,
  }) {
    return WishlistItem(
      id: id ?? this.id,
      name: name ?? this.name,
      targetPrice: targetPrice ?? this.targetPrice,
      saved: saved ?? this.saved,
      emoji: emoji ?? this.emoji,
      note: note ?? this.note,
      done: done ?? this.done,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
