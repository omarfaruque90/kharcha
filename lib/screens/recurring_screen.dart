import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/recurring_expense.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/category_dialogs.dart';
import '../widgets/motion.dart';
import '../widgets/payment_selector.dart';

/// Recurring templates: CRUD + active toggle. Due templates are
/// auto-added as real expenses (or incomes, for 'income' kind templates)
/// by RecurringService on app start.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  /// 0 = expense templates, 1 = income templates.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final kind = _tab == 0 ? 'expense' : 'income';
    final items = money.recurring.where((r) => r.kind == kind).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'recurring_title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _RecurringDialog(initialKind: kind),
        ),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'recurring_add')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(tr(context, 'recurring_tab_expense')),
                  selected: _tab == 0,
                  onSelected: (_) => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(tr(context, 'recurring_tab_income')),
                  selected: _tab == 1,
                  onSelected: (_) => setState(() => _tab = 1),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _tab == 0
                              ? Icons.event_repeat_outlined
                              : Icons.trending_up,
                          size: 56,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            context,
                            _tab == 0 ? 'no_recurring' : 'no_recurring_income',
                          ),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            tr(
                              context,
                              _tab == 0
                                  ? 'no_recurring_sub'
                                  : 'no_recurring_income_sub',
                            ),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) =>
                                _RecurringDialog(initialKind: kind),
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
                      final isIncome = r.kind == 'income';
                      final cat = categoryById(r.categoryId);
                      final iconBg = isIncome
                          ? Colors.green.withValues(alpha: 0.15)
                          : cat.color.withValues(alpha: 0.15);
                      final iconFg =
                          isIncome ? Colors.green : cat.color;
                      return StaggeredEntrance(
                        key: ValueKey('recurring-${r.id}'),
                        delayMs: (i * 50).clamp(0, 250).toInt(),
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: iconBg,
                              child: Icon(
                                isIncome ? Icons.trending_up : cat.icon,
                                color: iconFg,
                              ),
                            ),
                            title: Text(
                              r.label.trim().isEmpty
                                  ? (isIncome
                                      ? tr(context, 'income_title')
                                      : CustomCategoryRegistry.displayName(
                                          r.categoryId, lang))
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
                                  onChanged: (v) {
                                    final id = r.id;
                                    if (id != null) {
                                      money.toggleRecurring(id, v);
                                    }
                                  },
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
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, RecurringExpense r) {
    final id = r.id;
    if (id == null) return;
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
              await ctx.read<MoneyProvider>().removeRecurring(id);
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

/// Add / edit dialog: kind (expense/income), label, amount, category,
/// day 1-31, payment method, active flag. Category and payment method are
/// only shown for expense templates.
class _RecurringDialog extends StatefulWidget {
  final RecurringExpense? existing;
  final String? initialKind;

  const _RecurringDialog({this.existing, this.initialKind});

  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  late String _kind;
  late String _categoryId;
  int _catNonce = 0;
  late int _day;
  late String _paymentMethod;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? widget.initialKind ?? 'expense';
    _labelCtrl.text = existing?.label ?? '';
    // Keep decimals: toStringAsFixed(0) would round 1050.5 to "1050"
    // and saving would corrupt the stored amount.
    final existingAmount = existing?.amount;
    _amountCtrl.text = existingAmount == null
        ? ''
        : (existingAmount.truncateToDouble() == existingAmount
            ? existingAmount.toStringAsFixed(0)
            : existingAmount.toString());
    _categoryId = existing?.categoryId ??
        (CustomCategoryRegistry.visibleBuiltinCategories().isNotEmpty
            ? CustomCategoryRegistry.visibleBuiltinCategories().first.id
            : kCategories.first.id);
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
              // Expense / income kind selector.
              Row(
                children: [
                  ChoiceChip(
                    label: Text(tr(context, 'recurring_tab_expense')),
                    selected: _kind == 'expense',
                    onSelected: (_) => setState(() => _kind = 'expense'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(tr(context, 'recurring_tab_income')),
                    selected: _kind == 'income',
                    onSelected: (_) => setState(() => _kind = 'income'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
              if (_kind == 'expense') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('cat-$_categoryId-$_catNonce'),
                  initialValue: _categoryId,
                  decoration: InputDecoration(
                    labelText: tr(context, 'category'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in CustomCategoryRegistry
                        .visibleBuiltinCategories())
                      DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(c.icon, size: 18, color: c.color),
                            const SizedBox(width: 8),
                            Text(CustomCategoryRegistry.displayName(
                                c.id, lang)),
                          ],
                        ),
                      ),
                    for (final cc in CustomCategoryRegistry.all)
                      DropdownMenuItem(
                        value: cc.id,
                        child: Row(
                          children: [
                            Text(cc.emoji,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Flexible(child: Text(cc.name)),
                          ],
                        ),
                      ),
                    DropdownMenuItem(
                      value: '__add_new__',
                      child: Row(
                        children: [
                          const Icon(Icons.add_circle_outline, size: 18),
                          const SizedBox(width: 8),
                          Text(tr(context, 'add_category')),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (v) async {
                    if (v == '__add_new__') {
                      final id = await showAddCategoryDialog(context);
                      if (!mounted) return;
                      setState(() {
                        _catNonce++;
                        if (id != null) _categoryId = id;
                      });
                      return;
                    }
                    setState(() => _categoryId = v ?? _categoryId);
                  },
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
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
              if (_kind == 'expense') ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, 'payment_method'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                PaymentSelector(
                  value: _paymentMethod,
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
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
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final amount = double.parse(_amountCtrl.text.trim());
            final money = context.read<MoneyProvider>();
            final isIncome = _kind == 'income';
            // Persist a custom "Other" payment label for reuse, mirroring
            // the add-expense screen. (Expense kind only.)
            if (!isIncome && _paymentMethod.startsWith('other:')) {
              final label =
                  _paymentMethod.substring('other:'.length).trim();
              if (label.isNotEmpty) {
                await DatabaseHelper.instance
                    .upsertCustomPaymentByLabel(label);
              }
            }
            final existing = widget.existing;
            if (existing == null) {
              await money.addRecurring(RecurringExpense(
                kind: _kind,
                label: _labelCtrl.text.trim(),
                amount: amount,
                categoryId: isIncome ? 'others' : _categoryId,
                dayOfMonth: _day,
                paymentMethod: isIncome ? 'cash' : _paymentMethod,
                active: _active,
              ));
            } else {
              await money.updateRecurring(existing.copyWith(
                kind: _kind,
                label: _labelCtrl.text.trim(),
                amount: amount,
                // Income templates don't expose category/payment in the
                // dialog; keep the stored values so switching kind back
                // and forth doesn't lose them.
                categoryId: isIncome ? existing.categoryId : _categoryId,
                dayOfMonth: _day,
                paymentMethod:
                    isIncome ? existing.paymentMethod : _paymentMethod,
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
