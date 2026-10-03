import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/custom_place.dart';

/// "Kothay khoroch?" — custom place input shown when the Others category is
/// selected. The user types where they spent (e.g. "Dhanmondi Lake") and can
/// add an emoji manually (e.g. 🎮). Previously used places are offered as
/// reusable chips. The parent screen owns the controllers and upserts the
/// label via upsertCustomPlaceByLabel on save.
class PlaceInput extends StatefulWidget {
  final TextEditingController labelController;
  final TextEditingController emojiController;

  const PlaceInput({
    super.key,
    required this.labelController,
    required this.emojiController,
  });

  @override
  State<PlaceInput> createState() => _PlaceInputState();
}

class _PlaceInputState extends State<PlaceInput> {
  late final Future<List<CustomPlace>> _recent;

  @override
  void initState() {
    super.initState();
    _recent = DatabaseHelper.instance.getMostUsedPlaces(6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'place_where'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: widget.labelController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: tr(context, 'place_hint'),
                  prefixIcon: const Icon(Icons.place_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.emojiController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: tr(context, 'place_emoji_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<CustomPlace>>(
          future: _recent,
          builder: (context, snapshot) {
            final places = snapshot.data ?? const <CustomPlace>[];
            if (places.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'place_recent'),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final p in places)
                      ActionChip(
                        avatar: p.emoji.isEmpty ? null : Text(p.emoji),
                        label: Text(p.label),
                        onPressed: () {
                          widget.labelController.text = p.label;
                          widget.emojiController.text = p.emoji;
                        },
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
