import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/project.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Travel mode / projects: create named projects (e.g. a trip), optionally
/// with a budget and date range, and see how much was spent per project.
/// Expenses are linked via [Expense.projectId]; the coordinator wires the
/// project picker into the add-expense screen.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<_ProjectRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_ProjectRow>> _load() async {
    final db = DatabaseHelper.instance;
    final projects = await db.getProjects();
    final rows = <_ProjectRow>[];
    for (final p in projects) {
      final spent = await db.getProjectSpent(p.id ?? '');
      rows.add(_ProjectRow(project: p, spent: spent));
    }
    return rows;
  }

  void _refresh() {
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'projects_title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProjectDialog(context, null),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'project_add')),
      ),
      body: FutureBuilder<List<_ProjectRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final rows = snapshot.data ?? const <_ProjectRow>[];
          if (snapshot.hasError && rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(context, 'tpl_failed'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            );
          }
          if (rows.isEmpty) {
            return StaggeredEntrance(
              child: _EmptyState(
                icon: Icons.card_travel_outlined,
                title: tr(context, 'project_empty'),
                subtitle: tr(context, 'project_empty_sub'),
                ctaLabel: tr(context, 'project_add'),
                onAdd: () => _showProjectDialog(context, null),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (context, i) => StaggeredEntrance(
              key: ValueKey('project-${rows[i].project.id}'),
              delayMs: (i * 60).clamp(0, 240).toInt(),
              child: _ProjectCard(
                row: rows[i],
                lang: lang,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectDetailScreen(
                      project: rows[i].project,
                      spent: rows[i].spent,
                    ),
                  ),
                ),
                onDeleted: _refresh,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showProjectDialog(BuildContext context, Project? existing) {
    showDialog(
      context: context,
      builder: (_) => _ProjectDialog(existing: existing),
    ).then((saved) {
      if (saved == true) _refresh();
    });
  }
}

class _ProjectRow {
  final Project project;
  final double spent;
  const _ProjectRow({required this.project, required this.spent});
}

/// One project card: gold travel avatar, name, date range, animated
/// spent-vs-budget progress bar (like the budget screen), delete button.
class _ProjectCard extends StatelessWidget {
  final _ProjectRow row;
  final String lang;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  const _ProjectCard({
    required this.row,
    required this.lang,
    required this.onTap,
    required this.onDeleted,
  });

  String _dateRange(Project p) {
    final fmt = DateFormat('d MMM y', lang == 'bn' ? 'bn' : 'en');
    return '${fmt.format(p.start)} – ${fmt.format(p.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = row.project;
    final spent = row.spent;
    final ratio = p.budget > 0 ? spent / p.budget : 0.0;
    final over = p.budget > 0 && spent >= p.budget;
    Color colorFor(double r) => r >= 1
        ? theme.colorScheme.error
        : r >= 0.8
            ? const Color(0xFFF9A825)
            : theme.colorScheme.primary;

    return PressableScale(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (ctx, t, _) {
              final ar = ratio * t;
              final barColor = colorFor(ar);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: kGold.withValues(alpha: 0.18),
                        child: const Icon(Icons.card_travel, color: kGold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _dateRange(p),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (p.budget > 0)
                        Text(
                          '${(ar * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: barColor,
                          ),
                        ),
                      IconButton(
                        tooltip: tr(context, 'delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (p.budget > 0) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: ar.clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    p.budget > 0
                        ? '${tr(context, 'spent')}: ${formatMoney(spent * t)} / '
                            '${formatMoney(p.budget)}'
                        : '${tr(context, 'spent')}: ${formatMoney(spent * t)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: over ? theme.colorScheme.error : null,
                    ),
                  ),
                  Text(
                    p.budget <= 0
                        ? tr(context, 'project_no_budget')
                        : over
                            ? tr(context, 'budget_exceeded')
                            : '${tr(context, 'remaining')}: '
                                '${formatMoney(p.budget - spent)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: over
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          over ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'project_delete_title')),
        content: Text(tr(ctx, 'project_delete_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              tr(ctx, 'delete'),
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      final id = row.project.id;
      if (id != null) {
        await DatabaseHelper.instance.deleteProject(id);
      }
      onDeleted();
    }
  }
}

/// Add-project dialog: name, start/end date pickers, optional budget.
class _ProjectDialog extends StatefulWidget {
  final Project? existing;
  const _ProjectDialog({this.existing});

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final TextEditingController _name;
  late final TextEditingController _budget;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _budget = TextEditingController(
        text: e != null && e.budget > 0 ? e.budget.toStringAsFixed(0) : '');
    _start = e?.start ?? DateTime.now();
    _end = e?.end ?? DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final fmt = DateFormat('d MMM y', lang == 'bn' ? 'bn' : 'en');
    return AlertDialog(
      title: Text(tr(context, 'project_add')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: tr(context, 'project_name'),
                hintText: tr(context, 'project_name_hint'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _budget,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(context, 'project_budget'),
                hintText: tr(context, 'project_budget_hint'),
                prefixText: '৳ ',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(tr(context, 'project_start')),
              trailing: Text(fmt.format(_start)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _start = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(tr(context, 'project_end')),
              trailing: Text(fmt.format(_end)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _end,
                  firstDate: _start,
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _end = d);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final budget = double.tryParse(_budget.text.trim()) ?? 0;
    final p = Project(
      id: widget.existing?.id ?? Project.newId(),
      name: name,
      start: _start,
      end: _end,
      budget: budget,
    );
    await DatabaseHelper.instance.insertProject(p);
    if (mounted) Navigator.pop(context, true);
  }
}

/// Project detail: summary header + the project's expenses, newest first.
class ProjectDetailScreen extends StatefulWidget {
  final Project project;
  final double spent;

  const ProjectDetailScreen({
    super.key,
    required this.project,
    required this.spent,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  /// Stored in initState: creating the future in build() refetches the
  /// expense list on every rebuild.
  late final Future<List<Expense>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadExpenses();
  }

  Future<List<Expense>> _loadExpenses() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'expenses',
      where: 'project_id = ?',
      whereArgs: [widget.project.id ?? ''],
      orderBy: 'date DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<SettingsProvider>().language;
    final project = widget.project;
    final spent = widget.spent;
    final over = project.budget > 0 && spent >= project.budget;
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: FutureBuilder<List<Expense>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(context, 'tpl_failed'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            );
          }
          final expenses = snapshot.data ?? const <Expense>[];
          // Index 0 = summary header + section title; the rest are the
          // expense rows (or a single empty-state row).
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: expenses.isEmpty ? 2 : expenses.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StaggeredEntrance(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceAround,
                            children: [
                              _Stat(
                                label: tr(context, 'spent'),
                                value: formatMoney(spent),
                                color: over
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                              _Stat(
                                label: tr(context, 'project_budget'),
                                value: project.budget > 0
                                    ? formatMoney(project.budget)
                                    : '—',
                              ),
                              _Stat(
                                label: tr(context, 'remaining'),
                                value: project.budget > 0
                                    ? formatMoney(project.budget - spent)
                                    : '—',
                                color: over
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        tr(context, 'project_expenses'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                );
              }
              if (expenses.isEmpty) {
                return StaggeredEntrance(
                  delayMs: 120,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      tr(context, 'project_no_expenses'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              final expense = expenses[i - 1];
              return StaggeredEntrance(
                key: ValueKey('pexp-${expense.id}'),
                delayMs: ((i - 1) * 40).clamp(0, 200).toInt(),
                child: _ExpenseRow(
                  expense: expense,
                  lang: lang,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final String lang;

  const _ExpenseRow({required this.expense, required this.lang});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM y', lang == 'bn' ? 'bn' : 'en');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(
          CustomCategoryRegistry.displayName(expense.categoryId, lang),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            fmt.format(expense.date),
            if (expense.note.isNotEmpty) expense.note,
          ].join(' • '),
        ),
        trailing: Text(
          formatMoney(expense.amount),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: kGold),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(ctaLabel),
            ),
          ],
        ),
      ),
    );
  }
}
