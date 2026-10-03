import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/expense.dart';
import '../models/shopping_item.dart';
import '../providers/expense_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Shopping list (Package AN): checklist of items to buy.
///
/// Checkbox toggles done via `updateShoppingItem`. The "bought" action
/// logs the item as an expense (category 'groceries', note
/// 'Shopping: <name>'), marks it done, and shows a toast — same
/// [ExpenseProvider.add] pattern as template one-tap adds.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  List<ShoppingItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final items = await DatabaseHelper.instance.getShoppingItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _pendingTotal => _items
      .where((i) => !i.done)
      .fold(0.0, (s, i) => s + i.price * i.qty);

  Future<void> _toggleDone(ShoppingItem item) async {
    try {
      await DatabaseHelper.instance
          .updateShoppingItem(item.copyWith(done: !item.done));
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'tpl_failed'))),
        );
      }
    }
  }

  /// Logs the item as an expense (same pattern as QuickTemplates
  /// one-tap add), marks it done, and toasts.
  Future<void> _markBought(ShoppingItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ExpenseProvider>();
    try {
      await provider.add(
        Expense(
          amount: item.price * item.qty,
          categoryId: 'shopping',
          date: DateTime.now(),
          note: 'Shopping: ${item.name}',
          paymentMethod: 'cash',
        ),
      );
      await DatabaseHelper.instance
          .updateShoppingItem(item.copyWith(done: true));
      await _reload();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr(context, 'shop_bought_toast'))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr(context, 'tpl_failed'))),
      );
    }
  }

  Future<void> _confirmDelete(ShoppingItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'shop_delete_title')),
        content: Text(tr(ctx, 'shop_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok == true && item.id != null) {
      await DatabaseHelper.instance.deleteShoppingItem(item.id!);
      await _reload();
    }
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'shop_new_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: tr(ctx, 'shop_name'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(ctx, 'shop_qty'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(ctx, 'amount'),
                prefixText: '৳ ',
              ),
            ),
          ],
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
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'shop_invalid'))),
      );
      return;
    }
    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1;
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
    await DatabaseHelper.instance.insertShoppingItem(
      ShoppingItem(
        id: ShoppingItem.newId(),
        name: name,
        qty: qty <= 0 ? 1 : qty,
        price: price < 0 ? 0 : price,
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'shop_title'))),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: tr(context, 'shop_new_title'),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_pendingTotal > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: StaggeredEntrance(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${tr(context, 'shop_pending_total')}: '
                          '${formatMoney(_pendingTotal)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dark ? kGoldLight : kGoldDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Text(
                            tr(context, 'shop_empty'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) {
                            final item = _items[i];
                            return StaggeredEntrance(
                              delayMs: (i * 40).clamp(0, 480).toInt(),
                              child: _ShoppingCard(
                                item: item,
                                dark: dark,
                                onToggle: () => _toggleDone(item),
                                onBought: () => _markBought(item),
                                onDelete: () => _confirmDelete(item),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// One shopping item row: checkbox, name × qty, price, bought action,
/// delete.
class _ShoppingCard extends StatelessWidget {
  final ShoppingItem item;
  final bool dark;
  final VoidCallback onToggle;
  final VoidCallback onBought;
  final VoidCallback onDelete;

  const _ShoppingCard({
    required this.item,
    required this.dark,
    required this.onToggle,
    required this.onBought,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? kDeepGreenCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: item.done,
            activeColor: kGold,
            onChanged: (_) => onToggle(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration:
                        item.done ? TextDecoration.lineThrough : null,
                    color: item.done ? faded : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tr(context, 'shop_qty')}: ${_fmtQty(item.qty)} · '
                  '${formatMoney(item.price * item.qty)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (!item.done)
            TextButton.icon(
              onPressed: onBought,
              icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              label: Text(tr(context, 'shop_bought')),
              style: TextButton.styleFrom(
                foregroundColor: dark ? kGoldLight : kGoldDark,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: theme.colorScheme.error,
            tooltip: tr(context, 'delete'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
