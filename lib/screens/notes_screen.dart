import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/note.dart';
import '../widgets/motion.dart';

/// Google Keep-style notes: colorful cards, pin, search, edit.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await DatabaseHelper.instance.getNotes();
      if (mounted) {
        setState(() {
          _notes = rows.map(Note.fromMap).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Note> get _filtered {
    if (_query.isEmpty) return _notes;
    final q = _query.toLowerCase();
    return _notes
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.content.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _openEditor([Note? note]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
    );
    if (changed == true) _load();
  }

  Future<void> _togglePin(Note note) async {
    await DatabaseHelper.instance.updateNote(note.id, {'pinned': note.pinned ? 0 : 1});
    _load();
  }

  Future<void> _delete(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'delete')),
        content: Text(tr(dctx, 'note_delete_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(tr(dctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(tr(dctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.deleteNote(note.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'notes_title')),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGold,
        foregroundColor: kDeepGreenDark,
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: tr(context, 'notes_search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.note_alt_outlined,
                                size: 56,
                                color: Theme.of(context).disabledColor),
                            const SizedBox(height: 12),
                            Text(tr(context, 'notes_empty'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                        color: Theme.of(context).hintColor)),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: MasonryGridView.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final note = filtered[i];
                            return StaggeredEntrance(
                              delayMs: (i * 40).clamp(0, 240).toInt(),
                              child: _NoteCard(
                                note: note,
                                dark: dark,
                                onTap: () => _openEditor(note),
                                onLongPress: () => _delete(note),
                                onPin: () => _togglePin(note),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPin;

  const _NoteCard({
    required this.note,
    required this.dark,
    required this.onTap,
    required this.onLongPress,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final bg = NoteColors.background(note.color, dark);
    final fg = NoteColors.onBackground(note.color, dark);
    return GestureDetector(
      onLongPress: onLongPress,
      child: PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fg.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (note.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.push_pin,
                        size: 14, color: fg.withValues(alpha: 0.6)),
                  ),
                Expanded(
                  child: note.title.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          note.title,
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
                InkWell(
                  onTap: onPin,
                  child: Icon(
                    note.pinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    size: 16,
                    color: fg.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            if (note.content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note.content,
                style: TextStyle(color: fg.withValues(alpha: 0.85)),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// Full-screen note editor with color picker.
class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late int _color;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.note?.content ?? '');
    _color = widget.note?.color ?? 0;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    final existing = widget.note;
    if (existing == null) {
      await DatabaseHelper.instance.insertNote({
        'title': title,
        'content': content,
        'color': _color,
        'pinned': 0,
      });
    } else {
      await DatabaseHelper.instance.updateNote(existing.id, {
        'title': title,
        'content': content,
        'color': _color,
      });
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = NoteColors.background(_color, dark);
    final fg = NoteColors.onBackground(_color, dark);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: tr(context, 'save'),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    style: TextStyle(
                        color: fg,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: tr(context, 'notes_title_hint'),
                      hintStyle:
                          TextStyle(color: fg.withValues(alpha: 0.4)),
                      border: InputBorder.none,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _contentCtrl,
                      style: TextStyle(color: fg, fontSize: 16),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: tr(context, 'notes_content_hint'),
                        hintStyle:
                            TextStyle(color: fg.withValues(alpha: 0.4)),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < NoteColors.palette.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: NoteColors.palette[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == i
                              ? fg
                              : fg.withValues(alpha: 0.2),
                          width: _color == i ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
