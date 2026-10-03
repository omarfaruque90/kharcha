import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/money_provider.dart' show monthKeyOf;
import '../providers/settings_provider.dart';
import '../services/public_templates_service.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Package BI — browse community budget templates from the public
/// `public_templates` Firestore collection.
///
/// Cards show name, author, likes and budget count. Users can like a
/// template and apply it to the current month (replacing existing
/// budgets after a confirm dialog).
class PublicTemplatesScreen extends StatefulWidget {
  const PublicTemplatesScreen({super.key});

  @override
  State<PublicTemplatesScreen> createState() => _PublicTemplatesScreenState();
}

class _PublicTemplatesScreenState extends State<PublicTemplatesScreen> {
  List<Map<String, dynamic>> _templates = const [];
  bool _loading = true;

  /// Template ids liked this session (guards against double taps).
  final Set<String> _likedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final templates = await PublicTemplatesService.instance.browse();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  Future<void> _like(Map<String, dynamic> template) async {
    final id = template['id'] as String;
    if (_likedIds.contains(id)) return;
    setState(() {
      _likedIds.add(id);
      template['likes'] = (template['likes'] as int) + 1;
    });
    await PublicTemplatesService.instance.like(id);
  }

  Future<void> _confirmApply(Map<String, dynamic> template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'pt_apply_confirm_title')),
        content: Text(tr(ctx, 'pt_apply_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'pt_apply')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await PublicTemplatesService.instance.applyTemplate(
      template,
      monthKeyOf(DateTime.now()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'pt_applied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'pt_title')),
        actions: [
          IconButton(
            tooltip: tr(context, 'pt_refresh'),
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _templates.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      StaggeredEntrance(
                        child: Column(
                          children: [
                            Icon(
                              Icons.public_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              tr(context, 'pt_empty'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _templates.length,
                    itemBuilder: (ctx, i) {
                      final template = _templates[i];
                      return StaggeredEntrance(
                        key: ValueKey(template['id']),
                        delayMs: (i % 8) * 60,
                        child: _TemplateCard(
                          template: template,
                          lang: lang,
                          liked: _likedIds.contains(template['id']),
                          onLike: () => _like(template),
                          onApply: () => _confirmApply(template),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final String lang;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onApply;

  const _TemplateCard({
    required this.template,
    required this.lang,
    required this.liked,
    required this.onLike,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (template['name'] as String?)?.trim() ?? '';
    final author = (template['authorName'] as String?)?.trim() ?? '';
    final likes = template['likes'] as int? ?? 0;
    final budgets = (template['budgets'] as List?) ?? const [];
    final total = budgets.fold<double>(
      0,
      (sum, item) =>
          sum + ((item is Map ? item['amount'] : null) as num?)?.toDouble() ??
          0,
    );

    return PressableScale(
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? tr(context, 'pt_untitled') : name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${tr(context, 'pt_by')} $author · ${budgets.length} ${tr(context, 'pt_budget_count')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatMoney(total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: budgets.take(6).map<Widget>((item) {
                  final cat = item is Map
                      ? (item['category'] ?? '').toString()
                      : '';
                  return Chip(
                    label: Text(
                      AppStrings.categoryName(cat, lang),
                      style: theme.textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: liked ? null : onLike,
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: liked
                          ? Colors.red
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    label: Text('$likes'),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: onApply,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(tr(context, 'pt_apply')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
