import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/motion.dart';

/// Detail screen for a single Settings section.
/// Tapping a section in Settings navigates here with a tile builder.
/// Tiles are built fresh with this screen's context so switches,
/// language changes, and provider updates render correctly.
class SettingsSectionScreen extends StatelessWidget {
  final String sectionKey;
  final List<Widget> Function(BuildContext) tileBuilder;

  const SettingsSectionScreen({
    super.key,
    required this.sectionKey,
    required this.tileBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Watch settings so tiles rebuild on language/theme changes.
    context.watch<SettingsProvider>();
    final tiles = tileBuilder(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, sectionKey)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          KIOS.groupedSection(
            context,
            children: [
              for (var i = 0; i < tiles.length; i++)
                StaggeredEntrance(
                  delayMs: (i * 35).clamp(0, 280),
                  child: tiles[i],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
