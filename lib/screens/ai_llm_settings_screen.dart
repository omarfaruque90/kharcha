import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../widgets/motion.dart';

/// AI Assistant settings — simplified.
/// The AI works automatically with the bundled configuration.
/// No manual setup needed.
class AiLlmSettingsScreen extends StatefulWidget {
  const AiLlmSettingsScreen({super.key});

  @override
  State<AiLlmSettingsScreen> createState() =>
      _AiLlmSettingsScreenState();
}

class _AiLlmSettingsScreenState extends State<AiLlmSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'ai_settings_title'))),
      body: StaggeredEntrance(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFD4AF37),
                            Color(0xFFF0D878)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4AF37)
                                .withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'ai_ready_title'),
                      style:
                          theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'ai_ready_sub'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
