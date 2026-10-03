import 'package:uuid/uuid.dart';

/// A recurring subscription the user pays for (Netflix, gym, domain, ...).
///
/// Named [AppSubscription] (not `Subscription`) to avoid clashing with
/// `dart:async`'s `Subscription`. [cycle] is `'monthly'` or `'yearly'`.
/// [nextDue] is the next billing date. [active] false pauses reminders.
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/subscriptions/{id}`).
class AppSubscription {
  final String? id;
  final String name;
  final double amount;
  final String cycle;
  final DateTime nextDue;
  final String emoji;
  final bool active;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  AppSubscription({
    this.id,
    required this.name,
    required this.amount,
    required this.cycle,
    required this.nextDue,
    this.emoji = '',
    this.active = true,
    DateTime? updatedAt,
  })  : assert(cycle == 'monthly' || cycle == 'yearly'),
        updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created subscription.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'cycle': cycle,
      'next_due': nextDue.millisecondsSinceEpoch,
      'emoji': emoji,
      'active': active ? 1 : 0,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory AppSubscription.fromMap(Map<String, dynamic> map) {
    final activeRaw = map['active'];
    return AppSubscription(
      id: map['id']?.toString(),
      name: map['name'] as String? ?? '',
      amount: (map['amount'] as num).toDouble(),
      cycle: map['cycle'] as String? ?? 'monthly',
      nextDue: DateTime.fromMillisecondsSinceEpoch(
        (map['next_due'] as num).toInt(),
      ),
      emoji: map['emoji'] as String? ?? '',
      active: activeRaw is int
          ? activeRaw == 1
          : (activeRaw as bool? ?? true),
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a subscription from a Firestore document ([docId] is the
  /// document id).
  factory AppSubscription.fromFirestore(
      String docId, Map<String, dynamic> data) {
    return AppSubscription(
      id: docId,
      name: data['name'] as String? ?? '',
      amount: (data['amount'] as num).toDouble(),
      cycle: data['cycle'] as String? ?? 'monthly',
      nextDue: DateTime.fromMillisecondsSinceEpoch(
        (data['next_due'] as num?)?.toInt() ?? 0,
      ),
      emoji: data['emoji'] as String? ?? '',
      active: data['active'] as bool? ?? true,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'amount': amount,
      'cycle': cycle,
      'next_due': nextDue.millisecondsSinceEpoch,
      'emoji': emoji,
      'active': active,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  AppSubscription copyWith({
    String? id,
    String? name,
    double? amount,
    String? cycle,
    DateTime? nextDue,
    String? emoji,
    bool? active,
    DateTime? updatedAt,
  }) {
    return AppSubscription(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      cycle: cycle ?? this.cycle,
      nextDue: nextDue ?? this.nextDue,
      emoji: emoji ?? this.emoji,
      active: active ?? this.active,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
