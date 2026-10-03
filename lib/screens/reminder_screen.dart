import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/bill_reminder.dart';
import '../providers/money_provider.dart';
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
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _ReminderDialog(),
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(tr(context, 'reminder_add')),
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
                            onChanged: (v) {
                              final id = r.id;
                              if (id != null) {
                                money.toggleReminder(id, v);
                              }
                            },
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
    final id = r.id;
    if (id == null) return;
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
              await ctx.read<MoneyProvider>().removeReminder(id);
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
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleCtrl.text = existing?.title ?? '';
    // Keep decimals: toStringAsFixed(0) would round 1050.5 to "1050"
    // and saving would corrupt the stored amount.
    final existingAmount = existing?.amount;
    _amountCtrl.text = existingAmount == null
        ? ''
        : (existingAmount.truncateToDouble() == existingAmount
            ? existingAmount.toStringAsFixed(0)
            : existingAmount.toString());
    _noteCtrl.text = existing?.note ?? '';
    _day = existing?.dayOfMonth ?? 1;
    _active = existing?.active ?? true;
    final existingPhoto = existing?.photoPath;
    _photoPath =
        existingPhoto != null && existingPhoto.isNotEmpty ? existingPhoto : null;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Picks a bill photo from camera or gallery, mirroring the receipt flow
  /// in add_expense_screen.dart.
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file != null && mounted) {
        setState(() => _photoPath = file.path);
      }
    } catch (_) {
      // Permission denied or picker unavailable — leave the form as-is.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              const SizedBox(height: 12),
              // Package AE: optional bill photo (camera/gallery). Shown as a
              // thumbnail when set; the path is saved with the reminder and
              // included in the notification payload lookup.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_photoPath != null)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_photoPath!),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 64,
                              height: 64,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _photoPath = null),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: theme.colorScheme.outlineVariant),
                      ),
                      child: const Icon(Icons.image_outlined),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined,
                              size: 18),
                          label: Text(tr(context, 'receipt_camera')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 18),
                          label: Text(tr(context, 'receipt_gallery')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                tr(context, 'reminder_attach_photo'),
                style: theme.textTheme.bodySmall,
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
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final money = context.read<MoneyProvider>();
            final existing = widget.existing;
            if (existing == null) {
              await money.addReminder(BillReminder(
                title: _titleCtrl.text.trim(),
                amount: double.parse(_amountCtrl.text.trim()),
                dayOfMonth: _day,
                note: _noteCtrl.text.trim(),
                active: _active,
                photoPath: _photoPath ?? '',
              ));
            } else {
              await money.updateReminder(existing.copyWith(
                title: _titleCtrl.text.trim(),
                amount: double.parse(_amountCtrl.text.trim()),
                dayOfMonth: _day,
                note: _noteCtrl.text.trim(),
                active: _active,
                photoPath: _photoPath ?? '',
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
