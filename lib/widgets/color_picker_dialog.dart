import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Simple color picker dialog with a grid of preset colors.
class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const ColorPickerDialog({super.key, required this.initialColor});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _selected;

  static const List<Color> _colors = [
    Color(0xFFD4AF37), // gold
    Color(0xFF10B981), // emerald
    Color(0xFF3B82F6), // blue
    Color(0xFF8B5CF6), // purple
    Color(0xFFF97316), // orange
    Color(0xFFEF4444), // red
    Color(0xFFEC4899), // pink
    Color(0xFF06B6D4), // cyan
    Color(0xFF84CC16), // lime
    Color(0xFFEAB308), // yellow
    Color(0xFF14B8A6), // teal
    Color(0xFF6366F1), // indigo
    Color(0xFFF43F5E), // rose
    Color(0xFFA855F7), // violet
    Color(0xFF0EA5E9), // sky
    Color(0xFF22C55E), // green
    Color(0xFFD946EF), // fuchsia
    Color(0xFFFB7185), // coral
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'pick_color')),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _colors.length,
          itemBuilder: (ctx, i) {
            final c = _colors[i];
            final selected = c.toARGB32() == _selected.toARGB32();
            return GestureDetector(
              onTap: () => setState(() => _selected = c),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c,
                  border: selected
                      ? Border.all(
                          color: Theme.of(ctx).colorScheme.onSurface,
                          width: 3)
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 20)
                    : null,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}
