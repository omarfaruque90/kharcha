import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/llm_service.dart';
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
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final reply = await LlmService.chat(
        history: const [
          {'role': 'user', 'content': 'Say "OK" if you can read this.'}
        ],
        systemPrompt: 'You are a helpful assistant.',
      );
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = reply.text.isNotEmpty
            ? '${tr(context, 'ai_test_ok')}: ${reply.text}'
            : tr(context, 'ai_test_ok');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = tr(context, 'ai_test_fail');
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

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
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      _testOk
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _testOk
                          ? Colors.green
                          : theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style:
                            theme.textTheme.bodySmall?.copyWith(
                          color: _testOk
                              ? Colors.green
                              : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_outlined),
              label: Text(tr(context, 'ai_test_button')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
