import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/expense.dart';
import '../models/wishlist_item.dart';
import '../providers/expense_provider.dart';
import '../services/notification_center.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Wishlist (Package M): items the user is saving up for. Each card shows
/// an animated saving-progress bar; "Add money" bumps the saved amount
/// and fires a celebration notification when the target is reached;
/// "Mark as bought" optionally records the purchase as an expense.
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<WishlistItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final items = await DatabaseHelper.instance.getWishlist();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      // List stays empty on failure.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddEdit({WishlistItem? existing}) async {
    await showDialog(
      context: context,
      builder: (_) => _WishlistDialog(existing: existing),
    );
    await _reload();
  }

  Future<void> _addMoney(WishlistItem w) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _AddMoneyDialog(item: w),
    );
    if (amount == null || amount <= 0) return;
    final wasReached = w.targetReached;
    final updated = w.copyWith(
      saved: w.saved + amount,
      updatedAt: DateTime.now(),
    );
    await DatabaseHelper.instance.updateWishlist(updated);
    // Celebrate the moment the target is first reached.
    if (!wasReached && updated.targetReached && !updated.done) {
      final title = tr(context, 'notif_wish_title');
      final body = tr(context, 'notif_wish_body')
          .replaceAll('{name}', updated.name);
      await NotificationService.showNow(title: title, body: body);
      await NotificationCenter.push(
        title: title,
        body: body,
        type: 'wishlist',
        dedupeKey: 'wish-${updated.id ?? updated.name}',
      );
    }
    await _reload();
  }

  Future<void> _markBought(WishlistItem w) async {
    final addExpense = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'wish_bought_title')),
        content: Text(tr(ctx, 'wish_bought_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'wish_bought_no')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'wish_bought_yes')),
          ),
        ],
      ),
    );
    if (addExpense == null) return; // dismissed
    if (addExpense && mounted) {
      await context.read<ExpenseProvider>().add(
            Expense(
              amount: w.targetPrice,
              categoryId: 'shopping',
              date: DateTime.now(),
              note: 'Wishlist: ${w.name}',
              paymentMethod: 'cash',
            ),
          );
    }
    await DatabaseHelper.instance.updateWishlist(
      w.copyWith(done: true, updatedAt: DateTime.now()),
    );
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'wish_bought_done'))),
      );
    }
  }

  void _confirmDelete(WishlistItem w) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'wish_delete_title')),
        content: Text(tr(ctx, 'wish_delete_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteWishlist(w.id!);
              await _reload();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'wish_title')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddEdit(),
        backgroundColor: kGold,
        foregroundColor: kDeepGreenDark,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _EmptyView(onAdd: () => _openAddEdit())
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final w = _items[i];
                      return StaggeredEntrance(
                        key: ValueKey('wish-${w.id}'),
                        delayMs: (i * 50).clamp(0, 250).toInt(),
                        child: _WishlistCard(
                          item: w,
                          onTap: () => _openAddEdit(existing: w),
                          onLongPress: () => _confirmDelete(w),
                          onAddMoney: () => _addMoney(w),
                          onMarkBought: () => _markBought(w),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.card_giftcard_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(tr(context, 'no_wish'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              tr(context, 'no_wish_sub'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(tr(context, 'wish_add')),
          ),
        ],
      ),
    );
  }
}

class _WishlistCard extends StatelessWidget {
  final WishlistItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAddMoney;
  final VoidCallback onMarkBought;

  const _WishlistCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    required this.onAddMoney,
    required this.onMarkBought,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reached = item.targetReached;

    final leading = item.emoji.trim().isNotEmpty
        ? Text(item.emoji.trim(), style: const TextStyle(fontSize: 26))
        : Icon(Icons.card_giftcard, color: kGoldDark);

    final barColors = reached
        ? [const Color(0xFF10B981), const Color(0xFF059669)]
        : [kGoldLight, kGold];
    final percentColor = reached
        ? (isDark ? const Color(0xFF10B981) : kDeepGreen)
        : (isDark ? kGold : kGoldDark);

    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: kGold.withValues(alpha: 0.15),
                    child: leading,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: item.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (item.done)
                              Chip(
                                label: Text(
                                  tr(context, 'wish_bought_chip'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isDark
                                        ? const Color(0xFF10B981)
                                        : kDeepGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                backgroundColor: const Color(0xFF10B981)
                                    .withValues(alpha: 0.15),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatMoney(item.saved)} / '
                          '${formatMoney(item.targetPrice)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (item.note.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.note.trim(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: item.progress),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        value >= 1 ? barColors.first : barColors.last,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: item.progress * 100),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return Text(
                      '${value.toStringAsFixed(0)}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: percentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!item.done) ...[
                    PressableScale(
                      child: OutlinedButton.icon(
                        onPressed: onAddMoney,
                        icon: const Icon(Icons.savings_outlined, size: 18),
                        label: Text(tr(context, 'wish_add_money')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PressableScale(
                      child: FilledButton.tonalIcon(
                        onPressed: onMarkBought,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(tr(context, 'wish_mark_bought')),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add-money dialog: a single amount field that bumps the saved total.
class _AddMoneyDialog extends StatefulWidget {
  final WishlistItem item;

  const _AddMoneyDialog({required this.item});

  @override
  State<_AddMoneyDialog> createState() => _AddMoneyDialogState();
}

class _AddMoneyDialogState extends State<_AddMoneyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'wish_add_money')),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.name,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              autofocus: true,
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context)
                .pop(double.parse(_amountCtrl.text.trim()));
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}

/// Add / edit dialog: name, target price, emoji, note.
class _WishlistDialog extends StatefulWidget {
  final WishlistItem? existing;

  const _WishlistDialog({this.existing});

  @override
  State<_WishlistDialog> createState() => _WishlistDialogState();
}

class _WishlistDialogState extends State<_WishlistDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl.text = existing?.name ?? '';
    _priceCtrl.text =
        existing != null ? existing.targetPrice.toStringAsFixed(0) : '';
    _emojiCtrl.text = existing?.emoji ?? '';
    _noteCtrl.text = existing?.note ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _emojiCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context,
          widget.existing == null ? 'wish_add' : 'wish_edit')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'wish_name'),
                  hintText: tr(context, 'wish_name_hint'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? tr(context, 'err_title_empty')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'wish_target_price'),
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emojiCtrl,
                      decoration: InputDecoration(
                        labelText: tr(context, 'wish_emoji'),
                        hintText: '🎮',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'wish_note'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
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
            final db = DatabaseHelper.instance;
            final existing = widget.existing;
            if (existing == null) {
              await db.insertWishlist(WishlistItem(
                id: WishlistItem.newId(),
                name: _nameCtrl.text.trim(),
                targetPrice: double.parse(_priceCtrl.text.trim()),
                emoji: _emojiCtrl.text.trim(),
                note: _noteCtrl.text.trim(),
              ));
            } else {
              await db.updateWishlist(existing.copyWith(
                name: _nameCtrl.text.trim(),
                targetPrice: double.parse(_priceCtrl.text.trim()),
                emoji: _emojiCtrl.text.trim(),
                note: _noteCtrl.text.trim(),
                updatedAt: DateTime.now(),
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
