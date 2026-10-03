import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../widgets/motion.dart';
import '../widgets/quick_templates.dart';

/// Money-tools destination for quick expense templates.
/// One-tap expenses live here; the widget handles create/delete.
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'tpl_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StaggeredEntrance(
            child: Text(
              tr(context, 'tpl_empty'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          const StaggeredEntrance(
            delayMs: 80,
            child: QuickTemplates(),
          ),
        ],
      ),
    );
  }
}
