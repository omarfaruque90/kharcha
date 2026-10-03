import 'package:uuid/uuid.dart';

/// A monthly bill reminder (rent, net bill, subscription, ...).
///
/// [dayOfMonth] is 1-31. [active] false pauses notifications.
/// IDs are UUID strings so the same record can live in SQLite and in
/// Firestore (`users/{uid}/bill_reminders/{id}`).
class BillReminder {
  final String? id;
  final String title;
  final double amount;
  final int dayOfMonth;
  final String note;
  final bool active;

  /// Path to an attached bill photo (camera/gallery). Empty = none.
  /// Stored verbatim in the `photo_path` SQLite column and synced in the
  /// `photoPath` Firestore field so the notification payload lookup can find
  /// the same reminder on any device.
  final String photoPath;

  /// Last modification time (millis precision). Used for last-write-wins
  /// merging between the local DB and Firestore.
  final DateTime updatedAt;

  BillReminder({
    this.id,
    required this.title,
    required this.amount,
    required this.dayOfMonth,
    this.note = '',
    this.active = true,
    this.photoPath = '',
    DateTime? updatedAt,
  })  : assert(dayOfMonth >= 1 && dayOfMonth <= 31),
        updatedAt = updatedAt ?? DateTime.now();

  /// Generates a new UUID v4 id for a locally created reminder.
  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'dayOfMonth': dayOfMonth,
      'note': note,
      'active': active ? 1 : 0,
      'photo_path': photoPath,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory BillReminder.fromMap(Map<String, dynamic> map) {
    final activeRaw = map['active'];
    return BillReminder(
      id: map['id']?.toString(),
      title: map['title'] as String? ?? '',
      amount: (map['amount'] as num).toDouble(),
      dayOfMonth: (map['dayOfMonth'] as num).toInt(),
      note: map['note'] as String? ?? '',
      active: activeRaw is int
          ? activeRaw == 1
          : (activeRaw as bool? ?? true),
      photoPath: map['photo_path'] as String? ?? '',
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  /// Builds a reminder from a Firestore document ([docId] is the document id).
  factory BillReminder.fromFirestore(String docId, Map<String, dynamic> data) {
    return BillReminder(
      id: docId,
      title: data['title'] as String? ?? '',
      amount: (data['amount'] as num).toDouble(),
      dayOfMonth: (data['dayOfMonth'] as num?)?.toInt() ?? 1,
      note: data['note'] as String? ?? '',
      active: data['active'] as bool? ?? true,
      photoPath: data['photoPath'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Document fields for Firestore (the id is the document id itself).
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'amount': amount,
      'dayOfMonth': dayOfMonth,
      'note': note,
      'active': active,
      'photoPath': photoPath,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  BillReminder copyWith({
    String? id,
    String? title,
    double? amount,
    int? dayOfMonth,
    String? note,
    bool? active,
    String? photoPath,
    DateTime? updatedAt,
  }) {
    return BillReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      note: note ?? this.note,
      active: active ?? this.active,
      photoPath: photoPath ?? this.photoPath,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
