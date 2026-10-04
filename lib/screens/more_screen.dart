import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/design_tokens.dart';
import '../widgets/motion.dart';
import '../widgets/tool_sections.dart';

/// "More" tab: all Track / Plan / Tools / Insights tool sections moved off
/// home.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = toolSections();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'more')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // Tool sections.
          for (var s = 0; s < sections.length; s++) ...[
            StaggeredEntrance(
              delayMs: (s * 60).clamp(0, 240),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                child: KSection.header(
                  context,
                  icon: sections[s].icon,
                  title: tr(context, sections[s].titleKey),
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: sections[s].tools.length,
              itemBuilder: (ctx, i) {
                final tool = sections[s].tools[i];
                return StaggeredEntrance(
                  key: ValueKey('${sections[s].titleKey}-$i'),
                  delayMs: (i * 35).clamp(0, 300).toInt(),
                  child: ToolTile(
                    icon: tool.icon,
                    label: tr(context, tool.labelKey),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => tool.build()),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
