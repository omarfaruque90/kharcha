import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../widgets/motion.dart';

/// Detail screen for a single Settings section.
/// Tapping a section in Settings navigates here with pre-built tiles.
class SettingsSectionScreen extends StatelessWidget {
  final String sectionKey;
  final List<Widget> tiles;

  const SettingsSectionScreen({
    super.key,
    required this.sectionKey,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, sectionKey)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          for (var i = 0; i < tiles.length; i++)
            StaggeredEntrance(
              delayMs: (i * 35).clamp(0, 280),
              child: tiles[i],
            ),
        ],
      ),
    );
  }
}
