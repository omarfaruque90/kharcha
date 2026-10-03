/// One entry in the in-app notification center, persisted in the
/// SQLite `notifications` table so it survives restarts.
class AppNotification {
  final int? id;
  final String title;
  final String body;
  final DateTime time;
  final bool read;
  final String type;
  final String? dedupe;

  const AppNotification({
    this.id,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
    this.type = 'info',
    this.dedupe,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      time: DateTime.fromMillisecondsSinceEpoch(
        (map['time'] as num?)?.toInt() ?? 0,
      ),
      read: (map['read'] as num?)?.toInt() == 1,
      type: map['type'] as String? ?? 'info',
      dedupe: map['dedupe'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'body': body,
        'time': time.millisecondsSinceEpoch,
        'read': read ? 1 : 0,
        'type': type,
        'dedupe': dedupe,
      };
}
