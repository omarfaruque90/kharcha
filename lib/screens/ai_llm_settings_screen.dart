import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/llm_service.dart';
import '../widgets/motion.dart';

/// Settings for the LLM-powered AI assistant (Package: real AI).
/// The user brings their own API key (Gemini or OpenAI-compatible).
/// The key is stored in secure storage, never in plain settings.
class AiLlmSettingsScreen extends StatefulWidget {
  const AiLlmSettingsScreen({super.key});

  @override
  State<AiLlmSettingsScreen> createState() => _AiLlmSettingsScreenState();
}

class _AiLlmSettingsScreenState extends State<AiLlmSettingsScreen> {
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  String _provider = 'gemini';
  bool _obscure = true;
  bool _loading = true;
  bool _testing = false;
  String? _testResult; // null = not tested, otherwise message
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await LlmConfig.load();
    if (!mounted) return;
    setState(() {
      _provider = cfg.effectiveProvider == 'openai' ? 'openai' : 'gemini';
      _keyCtrl.text = cfg.apiKey;
      _modelCtrl.text = cfg.model;
      _baseUrlCtrl.text = cfg.baseUrl;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final cfg = LlmConfig(
      // Empty provider/model/baseUrl = use bundled compile-time values.
      provider: _provider,
      apiKey: _keyCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
    );
    await cfg.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'ai_cfg_saved'))),
    );
    setState(() {
      _testResult = null;
    });
  }

  /// Builds the config the Test button actually uses: the typed values,
  /// with bundled compile-time values filling anything empty.
  LlmConfig _effectiveForTest() => LlmConfig(
        provider: _provider,
        apiKey: _keyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        baseUrl: _baseUrlCtrl.text.trim(),
      );

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final cfg = _effectiveForTest();
    if (!cfg.isConfigured) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testOk = false;
          _testResult = tr(context, 'ai_cfg_no_key');
        });
      }
      return;
    }
    final err = await LlmService.testConnection(cfg);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = err == null;
      _testResult =
          err == null ? tr(context, 'ai_cfg_test_ok') : '${tr(context, 'ai_cfg_test_fail')}: $err';
    });
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text(_testResult!)));
    }
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'ai_cfg_clear_title')),
        content: Text(tr(dctx, 'ai_cfg_clear_msg')),
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
    if (confirm != true || !mounted) return;
    await LlmConfig.clearAll();
    _keyCtrl.clear();
    _modelCtrl.clear();
    _baseUrlCtrl.clear();
    setState(() {
      _provider = 'gemini';
      _testResult = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'ai_cfg_cleared'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBundled = LlmConfig.bundledKey.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'ai_settings_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : StaggeredEntrance(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 20,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr(context, 'ai_cfg_info'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, 'ai_cfg_provider'),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'gemini',
                        label: Text(tr(context, 'ai_cfg_gemini')),
                        icon: const Icon(Icons.auto_awesome_outlined),
                      ),
                      ButtonSegment(
                        value: 'openai',
                        label: Text(tr(context, 'ai_cfg_openai')),
                        icon: const Icon(Icons.api_outlined),
                      ),
                    ],
                    selected: {_provider},
                    onSelectionChanged: (s) =>
                        setState(() => _provider = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: tr(context, 'ai_cfg_key'),
                      hintText: tr(context, 'ai_cfg_key_hint'),
                      helperText: hasBundled
                          ? tr(context, 'ai_cfg_builtin_present')
                          : tr(context, 'ai_cfg_builtin_missing'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelCtrl,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: tr(context, 'ai_cfg_model'),
                      hintText: _provider == 'openai'
                          ? 'gpt-4o-mini'
                          : 'gemini-2.0-flash',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.model_training_outlined),
                    ),
                  ),
                  if (_provider == 'openai') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baseUrlCtrl,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: tr(context, 'ai_cfg_base_url'),
                        hintText: 'https://api.openai.com/v1',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.link_outlined),
                      ),
                    ),
                  ],
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _testOk
                                    ? Colors.green
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _testing ? null : _test,
                          icon: _testing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering_outlined),
                          label: Text(tr(context, 'ai_cfg_test')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(tr(context, 'save')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr(context, 'ai_cfg_clear')),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
