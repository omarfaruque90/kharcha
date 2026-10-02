import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/bill_reminder.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Bill reminders: CRUD + active toggle. A sibling agent schedules the
/// actual notifications from [DatabaseHelper.getActiveBillReminders].
class ReminderScreen extends StatelessWidget {
  const ReminderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyProvider>();
    final theme = Theme.of(context);
    final items = money.reminders;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'reminder_title')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _ReminderDialog(),
        ),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'reminder_add')),
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none_outlined,
                    size: 56,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, 'no_reminders'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      tr(context, 'no_reminders_sub'),
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final r = items[i];
                return StaggeredEntrance(
                  key: ValueKey('reminder-${r.id}'),
                  delayMs: (i * 50).clamp(0, 250).toInt(),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary
                            .withValues(alpha: 0.15),
                        child: Text(
                          '${r.dayOfMonth}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      title: Text(
                        r.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${formatMoney(r.amount)}'
                        '${r.note.trim().isEmpty ? '' : ' • ${r.note.trim()}'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: r.active,
                            onChanged: (v) =>
                                money.toggleReminder(r.id!, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  _ReminderDialog(existing: r),
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

  void _confirmDelete(BuildContext context, BillReminder r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_reminder_title')),
        content: Text(tr(ctx, 'delete_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await ctx.read<MoneyProvider>().removeReminder(r.id!);
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

/// Add / edit dialog: title, amount, day 1-31, note, active flag.
class _ReminderDialog extends StatefulWidget {
  final BillReminder? existing;

  const _ReminderDialog({this.existing});

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late int _day;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleCtrl.text = existing?.title ?? '';
    _amountCtrl.text =
        existing != null ? existing.amount.toStringAsFixed(0) : '';
    _noteCtrl.text = existing?.note ?? '';
    _day = existing?.dayOfMonth ?? 1;
    _active = existing?.active ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        tr(context,
            widget.existing == null ? 'reminder_add' : 'reminder_edit'),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'reminder_title_label'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? tr(context, 'err_title_empty')
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _amountCtrl,
                      decoration: InputDecoration(
                        labelText: tr(context, 'amount'),
                        prefixText: '৳ ',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) {
                          return tr(context, 'err_amount_invalid');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
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
                      onChanged: (v) => setState(() => _day = v ?? _day),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'note'),
                  hintText: tr(context, 'note_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
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
            if (!_formKey.currentState!.validate()) return;
            final money = context.read<MoneyProvider>();
            final existing = widget.existing;
            if (existing == null) {
              await money.addReminder(BillReminder(
                title: _titleCtrl.text.trim(),
                amount: double.parse(_amountCtrl.text.trim()),
                dayOfMonth: _day,
                note: _noteCtrl.text.trim(),
                active: _active,
              ));
            } else {
              await money.updateReminder(existing.copyWith(
                title: _titleCtrl.text.trim(),
                amount: double.parse(_amountCtrl.text.trim()),
                dayOfMonth: _day,
                note: _noteCtrl.text.trim(),
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
