import 'package:flutter/material.dart';

/// A Google Keep-style user note. Device-local (no sync).
class Note {
  final String id;
  final String title;
  final String content;
  final int color; // index into NoteColors.palette
  final bool pinned;
  final DateTime updated;

  const Note({
    required this.id,
    this.title = '',
    this.content = '',
    this.color = 0,
    this.pinned = false,
    required this.updated,
  });

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        color: (m['color'] as int?) ?? 0,
        pinned: ((m['pinned'] as int?) ?? 0) == 1,
        updated: DateTime.fromMillisecondsSinceEpoch(
            (m['updated'] as int?) ?? 0),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'color': color,
        'pinned': pinned ? 1 : 0,
        'updated': updated.millisecondsSinceEpoch,
      };
}

/// Keep-like pastel palette (works in light + dark mode).
class NoteColors {
  static const List<Color> palette = [
    Color(0xFFFFFFFF), // white
    Color(0xFFF28B82), // red
    Color(0xFFFBBF24), // amber
    Color(0xFFFBBC04), // yellow
    Color(0xFFCCFF90), // green
    Color(0xFFA7FFEB), // teal
    Color(0xFFCBF0F8), // light blue
    Color(0xFFAECBFA), // blue
    Color(0xFFD7AEFB), // purple
    Color(0xFFFDCFE8), // pink
  ];

  /// Dark-mode-safe background: darkens pastels for dark theme.
  static Color background(int index, bool dark) {
    final c = palette[index.clamp(0, palette.length - 1)];
    if (!dark) return c;
    // Mix with dark surface so text stays readable.
    return Color.lerp(const Color(0xFF1E1E1E), c, 0.22) ?? c;
  }

  static Color onBackground(int index, bool dark) =>
      dark ? Colors.white : const Color(0xFF202124);
}
