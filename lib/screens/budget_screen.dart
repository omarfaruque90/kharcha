import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Monthly per-category spending limits: set/edit budgets, see spent vs
/// limit with progress bars, and get warned at 80% / when exceeded.
class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final lang = context.watch<SettingsProvider>().language;
    final key = monthKeyOf(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'budget_title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBudgetDialog(context, key, null),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'budget_set')),
      ),
      body: FutureBuilder<Map<String, double>>(
        future: money.expenseForMonth(key),
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
          final spent = snapshot.data ?? <String, double>{};
          final budgets = money.budgetsForMonth(key);
          final warnings = budgets.where((b) {
            final s = spent[b.categoryId] ?? 0;
            return b.limitAmount > 0 && s / b.limitAmount >= 0.8;
          }).toList(growable: false);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (warnings.isNotEmpty)
                StaggeredEntrance(
                  child: _WarningBanner(
                    budgets: warnings,
                    spent: spent,
                    lang: lang,
                  ),
                ),
              if (budgets.isEmpty)
                StaggeredEntrance(
                  child: _EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: tr(context, 'no_budgets'),
                    subtitle: tr(context, 'no_budgets_sub'),
                    ctaLabel: tr(context, 'budget_set'),
                    onAdd: () =>
                        _showBudgetDialog(context, key, null),
                  ),
                ),
              for (var i = 0; i < budgets.length; i++)
                StaggeredEntrance(
                  key: ValueKey('budget-${budgets[i].id}'),
                  delayMs: (i * 60).clamp(0, 240).toInt(),
                  child: _BudgetCard(
                    budget: budgets[i],
                    spent: spent[budgets[i].categoryId] ?? 0,
                    lang: lang,
                    onTap: () => _showBudgetDialog(
                        context, key, budgets[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showBudgetDialog(
      BuildContext context, String monthKey, Budget? existing) {
    showDialog(
      context: context,
      builder: (_) => _BudgetDialog(monthKey: monthKey, existing: existing),
    );
  }
}

/// Amber/red banner listing budgets at >=80% (amber) or exceeded (red).
class _WarningBanner extends StatelessWidget {
  final List<Budget> budgets;
  final Map<String, double> spent;
  final String lang;

  const _WarningBanner({
    required this.budgets,
    required this.spent,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final anyExceeded = budgets.any((b) {
      final s = spent[b.categoryId] ?? 0;
      return b.limitAmount > 0 && s > b.limitAmount;
    });
    // Amber "near limit" banner must stay readable in dark mode too:
    // gold-tinted surface + warm amber text instead of hardcoded light colors.
    final bg = anyExceeded
        ? theme.colorScheme.errorContainer
        : kGold.withValues(alpha: isDark ? 0.22 : 0.16);
    final fg = anyExceeded
        ? theme.colorScheme.onErrorContainer
        : isDark
            ? const Color(0xFFFFCC80)
            : const Color(0xFFE65100);
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: fg),
                const SizedBox(width: 8),
                Text(
                  anyExceeded
                      ? tr(context, 'budget_exceeded')
                      : tr(context, 'budget_near_limit'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final b in budgets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${AppStrings.categoryName(b.categoryId, lang)} — '
                  '${formatMoney(spent[b.categoryId] ?? 0)} / '
                  '${formatMoney(b.limitAmount)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final double spent;
  final String lang;
  final VoidCallback onTap;

  const _BudgetCard({
    required this.budget,
    required this.spent,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = categoryById(budget.categoryId);
    final ratio = budget.limitAmount > 0 ? spent / budget.limitAmount : 0.0;
    final barColor = ratio >= 1
        ? theme.colorScheme.error
        : ratio >= 0.8
            ? const Color(0xFFF9A825)
            : theme.colorScheme.primary;
    return PressableScale(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cat.color.withValues(alpha: 0.15),
                    child: Icon(cat.icon, color: cat.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.categoryName(budget.categoryId, lang),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${tr(context, 'spent')}: ${formatMoney(spent)} / '
                          '${formatMoney(budget.limitAmount)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(ratio * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: barColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ratio >= 1
                    ? tr(context, 'budget_exceeded')
                    : '${tr(context, 'remaining')}: '
                        '${formatMoney(budget.limitAmount - spent)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ratio >= 1
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight:
                      ratio >= 1 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(ctaLabel),
          ),
        ],
      ),
    );
  }
}

/// Dialog to add (pick a category + limit) or edit (change limit/delete)
/// a budget for [monthKey].
class _BudgetDialog extends StatefulWidget {
  final String monthKey;
  final Budget? existing;

  const _BudgetDialog({required this.monthKey, this.existing});

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  late String _categoryId;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _categoryId = existing?.categoryId ?? kCategories.first.id;
    if (existing != null) {
      _amountCtrl.text = existing.limitAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final existing = widget.existing;
    return AlertDialog(
      title: Text(
        tr(context, existing == null ? 'budget_set' : 'budget_edit'),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: InputDecoration(
                labelText: tr(context, 'category'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in kCategories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        Icon(c.icon, size: 18, color: c.color),
                        const SizedBox(width: 8),
                        Text(AppStrings.categoryName(c.id, lang)),
                      ],
                    ),
                  ),
              ],
              onChanged: existing == null
                  ? (v) => setState(() => _categoryId = v ?? _categoryId)
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: InputDecoration(
                labelText: tr(context, 'limit'),
                prefixText: '৳ ',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return tr(context, 'err_amount_invalid');
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (existing != null)
          TextButton.icon(
            onPressed: () async {
              final money = context.read<MoneyProvider>();
              await money.removeBudget(existing.id!);
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr(context, 'msg_deleted'))),
                );
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(tr(context, 'delete')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final amount = double.parse(_amountCtrl.text.trim());
            final money = context.read<MoneyProvider>();
            if (existing == null) {
              await money.upsertBudget(Budget(
                categoryId: _categoryId,
                monthKey: widget.monthKey,
                limitAmount: amount,
              ));
            } else {
              await money.updateBudget(
                existing.copyWith(limitAmount: amount),
              );
            }
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(context, 'msg_saved'))),
              );
            }
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}
