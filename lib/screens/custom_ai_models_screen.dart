import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart';
import '../services/custom_ai_model_store.dart';
import '../services/llm_service.dart';
import '../widgets/motion.dart';

/// Manage custom AI models: add, select, remove.
class CustomAiModelsScreen extends StatefulWidget {
  const CustomAiModelsScreen({super.key});

  @override
  State<CustomAiModelsScreen> createState() =>
      _CustomAiModelsScreenState();
}

class _CustomAiModelsScreenState extends State<CustomAiModelsScreen> {
  List<CustomAiModel> _models = [];
  String? _activeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final models = await CustomAiModelStore.instance.loadAll();
    final activeId = await CustomAiModelStore.instance.getActiveId();
    if (!mounted) return;
    setState(() {
      _models = models;
      _activeId = activeId;
      _loading = false;
    });
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String provider = 'openai';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr(ctx, 'ai_model_add')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'ai_model_name'),
                    hintText: 'My Custom Model',
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'openai', label: Text('OpenAI')),
                    ButtonSegment(
                        value: 'nvidia', label: Text('NVIDIA')),
                    ButtonSegment(
                        value: 'gemini', label: Text('Gemini')),
                  ],
                  selected: {provider},
                  onSelectionChanged: (s) =>
                      setDialogState(() => provider = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'ai_cfg_key'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'ai_cfg_model'),
                    hintText: 'gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'ai_cfg_url'),
                    hintText: 'https://api.openai.com/v1',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr(ctx, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr(ctx, 'save')),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    final key = keyCtrl.text.trim();
    if (name.isEmpty || key.isEmpty) return;

    await CustomAiModelStore.instance.add(CustomAiModel(
      id: const Uuid().v4(),
      name: name,
      provider: provider,
      baseUrl: urlCtrl.text.trim(),
      model: modelCtrl.text.trim(),
      apiKey: key,
    ));
    await _reload();
  }

  Future<void> _removeModel(CustomAiModel model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'ai_model_remove_title')),
        content: Text(tr(ctx, 'ai_model_remove_msg')
            .replaceAll('{name}', model.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await CustomAiModelStore.instance.remove(model.id);
      await _reload();
    }
  }

  Future<void> _selectModel(String? id) async {
    await CustomAiModelStore.instance.setActiveId(id);
    // Clear the standard config so custom model takes precedence.
    if (id != null) {
      await LlmConfig().save();
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'ai_models_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Built-in option.
                StaggeredEntrance(
                  child: Card(
                    child: RadioListTile<String?>(
                      title: Text(tr(context, 'ai_model_builtin')),
                      subtitle: Text(
                          tr(context, 'ai_model_builtin_sub')),
                      value: null,
                      groupValue: _activeId,
                      onChanged: _selectModel,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final m in _models)
                  StaggeredEntrance(
                    child: Card(
                      child: ListTile(
                        title: Text(m.name),
                        subtitle: Text('${m.provider} • ${m.model}'),
                        leading: Radio<String?>(
                          value: m.id,
                          groupValue: _activeId,
                          onChanged: _selectModel,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: () => _removeModel(m),
                        ),
                        onTap: () => _selectModel(m.id),
                      ),
                    ),
                  ),
                if (_models.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        tr(context, 'ai_model_empty'),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'ai_model_add')),
      ),
    );
  }
}
