import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/income.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Income list with a gold-accented monthly total header; add via FAB.
class IncomeScreen extends StatelessWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final key = monthKeyOf(DateTime.now());
    final monthIncomes = money.incomesForMonth(key);
    final monthTotal = money.incomeForMonth(key);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'income_title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _IncomeDialog(),
        ),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'income_add')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          StaggeredEntrance(
            child: Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.2,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.trending_up,
                        color: theme.colorScheme.onSecondaryContainer,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tr(context, 'this_month')} — '
                            '${tr(context, 'income_title')}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            formatMoney(monthTotal),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          Text(
                            '${monthIncomes.length} ${tr(context, 'income_entries')}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (monthIncomes.isEmpty && money.incomes.isEmpty)
            StaggeredEntrance(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 56,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'no_income'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          if (monthIncomes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(
                monthLong(DateTime.now(), lang),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (var i = 0; i < monthIncomes.length; i++)
              StaggeredEntrance(
                key: ValueKey('income-${monthIncomes[i].id}'),
                delayMs: (i * 50).clamp(0, 250).toInt(),
                child: _IncomeTile(
                  income: monthIncomes[i],
                  lang: lang,
                  onEdit: () => showDialog(
                    context: context,
                    builder: (_) =>
                        _IncomeDialog(existing: monthIncomes[i]),
                  ),
                  onDelete: () => _confirmDelete(context, monthIncomes[i]),
                ),
              ),
          ],
          if (money.incomes.isNotEmpty && monthIncomes.length < money.incomes.length) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                tr(context, 'income_older'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final income in money.incomes
                .where((e) => monthKeyOf(e.date) != key))
              StaggeredEntrance(
                key: ValueKey('income-old-${income.id}'),
                child: _IncomeTile(
                  income: income,
                  lang: lang,
                  onEdit: () => showDialog(
                    context: context,
                    builder: (_) => _IncomeDialog(existing: income),
                  ),
                  onDelete: () => _confirmDelete(context, income),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Income income) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_income_title')),
        content: Text(tr(ctx, 'delete_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await ctx.read<MoneyProvider>().removeIncome(income.id!);
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(tr(ctx, 'msg_deleted'))),
                );
              }
            },
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
  }
}

class _IncomeTile extends StatelessWidget {
  final Income income;
  final String lang;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _IncomeTile({
    required this.income,
    required this.lang,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              theme.colorScheme.secondary.withValues(alpha: 0.15),
          child: Icon(
            Icons.attach_money,
            color: theme.colorScheme.secondary,
          ),
        ),
        title: Text(
          income.source.trim().isEmpty
              ? tr(context, 'income_title')
              : income.source,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(income.date)}'
          '${income.note.trim().isEmpty ? '' : ' • ${income.note.trim()}'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+${formatMoney(income.amount)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit dialog: amount, source, date and optional note.
class _IncomeDialog extends StatefulWidget {
  final Income? existing;

  const _IncomeDialog({this.existing});

  @override
  State<_IncomeDialog> createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<_IncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _date = existing?.date ?? DateTime.now();
    if (existing != null) {
      _amountCtrl.text = existing.amount.toStringAsFixed(0);
      _sourceCtrl.text = existing.source;
      _noteCtrl.text = existing.note;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _sourceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final lang = context.read<SettingsProvider>().language;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: Locale(lang),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return AlertDialog(
      title: Text(
        tr(context,
            widget.existing == null ? 'income_add' : 'income_edit'),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'amount'),
                  prefixText: '৳ ',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) {
                    return tr(context, 'err_amount_invalid');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sourceCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'income_source'),
                  hintText: tr(context, 'income_source_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(_date),
                ),
                subtitle: Text(tr(context, 'date')),
                onTap: _pickDate,
              ),
              TextFormField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'note'),
                  hintText: tr(context, 'note_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final amount = double.parse(_amountCtrl.text.trim());
            final money = context.read<MoneyProvider>();
            final existing = widget.existing;
            if (existing == null) {
              await money.addIncome(Income(
                amount: amount,
                source: _sourceCtrl.text.trim(),
                date: _date,
                note: _noteCtrl.text.trim(),
              ));
            } else {
              await money.updateIncome(existing.copyWith(
                amount: amount,
                source: _sourceCtrl.text.trim(),
                date: _date,
                note: _noteCtrl.text.trim(),
              ));
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
