import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../models/recurring_expense.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Recurring expense templates: CRUD + active toggle. Due templates are
/// auto-added as real expenses by RecurringService on app start.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final items = money.recurring;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'recurring_title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _RecurringDialog(),
        ),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'recurring_add')),
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_repeat_outlined,
                    size: 56,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, 'no_recurring'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      tr(context, 'no_recurring_sub'),
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _RecurringDialog(),
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(tr(context, 'recurring_add')),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final r = items[i];
                final cat = categoryById(r.categoryId);
                return StaggeredEntrance(
                  key: ValueKey('recurring-${r.id}'),
                  delayMs: (i * 50).clamp(0, 250).toInt(),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cat.color.withValues(alpha: 0.15),
                        child: Icon(cat.icon, color: cat.color),
                      ),
                      title: Text(
                        r.label.trim().isEmpty
                            ? AppStrings.categoryName(r.categoryId, lang)
                            : r.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${tr(context, 'recurring_day')}: ${r.dayOfMonth} • '
                        '${formatMoney(r.amount)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: r.active,
                            onChanged: (v) => money.toggleRecurring(
                                r.id!, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  _RecurringDialog(existing: r),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, r),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, RecurringExpense r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_recurring_title')),
        content: Text(tr(ctx, 'delete_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await ctx.read<MoneyProvider>().removeRecurring(r.id!);
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

/// Add / edit dialog: label, amount, category, day 1-31, payment method,
/// active flag.
class _RecurringDialog extends StatefulWidget {
  final RecurringExpense? existing;

  const _RecurringDialog({this.existing});

  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  late String _categoryId;
  late int _day;
  late String _paymentMethod;
  late bool _active;

  static const List<String> _paymentMethods = [
    'cash',
    'bkash',
    'card',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelCtrl.text = existing?.label ?? '';
    _amountCtrl.text = existing != null
        ? existing.amount.toStringAsFixed(0)
        : '';
    _categoryId = existing?.categoryId ?? kCategories.first.id;
    _day = existing?.dayOfMonth ?? 1;
    _paymentMethod = existing?.paymentMethod ?? 'cash';
    _active = existing?.active ?? true;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return AlertDialog(
      title: Text(
        tr(context,
            widget.existing == null ? 'recurring_add' : 'recurring_edit'),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'recurring_label'),
                  hintText: tr(context, 'recurring_label_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
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
                onChanged: (v) =>
                    setState(() => _categoryId = v ?? _categoryId),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _day,
                      decoration: InputDecoration(
                        labelText: tr(context, 'recurring_day'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (var d = 1; d <= 31; d++)
                          DropdownMenuItem(
                            value: d,
                            child: Text('$d'),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _day = v ?? _day),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: InputDecoration(
                        labelText: tr(context, 'payment_method'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final m in _paymentMethods)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                                AppStrings.paymentName(m, lang)),
                          ),
                      ],
                      onChanged: (v) => setState(
                        () => _paymentMethod = v ?? _paymentMethod,
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.zero,
                title: Text(tr(context, 'active')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
              await money.addRecurring(RecurringExpense(
                label: _labelCtrl.text.trim(),
                amount: amount,
                categoryId: _categoryId,
                dayOfMonth: _day,
                paymentMethod: _paymentMethod,
                active: _active,
              ));
            } else {
              await money.updateRecurring(existing.copyWith(
                label: _labelCtrl.text.trim(),
                amount: amount,
                categoryId: _categoryId,
                dayOfMonth: _day,
                paymentMethod: _paymentMethod,
                active: _active,
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
