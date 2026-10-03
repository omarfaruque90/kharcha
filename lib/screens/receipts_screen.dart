import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Gallery grid of all expenses that have a receipt photo attached.
/// Receipts are device-local; entries whose file no longer exists are
/// filtered out.
class ReceiptsScreen extends StatelessWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final all = context.watch<ExpenseProvider>().expenses;
    // Newest first; drop missing files (device-local paths).
    final receipts = all
        .where((e) =>
            e.receiptPath != null &&
            e.receiptPath!.isNotEmpty &&
            File(e.receiptPath!).existsSync())
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'receipts_title')),
      ),
      body: receipts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'receipts_empty'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'receipts_empty_sub'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemCount: receipts.length,
              itemBuilder: (ctx, i) {
                final e = receipts[i];
                return StaggeredEntrance(
                  delayMs: (i * 40).clamp(0, 320),
                  child: _ReceiptTile(expense: e, lang: lang),
                );
              },
            ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  final Expense expense;
  final String lang;

  const _ReceiptTile({required this.expense, required this.lang});

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(expense.date);
    return PressableScale(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ReceiptViewer(expense: expense),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(expense.receiptPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
            // Bottom gradient + amount/date overlay.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatMoney(expense.amount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen receipt viewer with expense details and delete.
class _ReceiptViewer extends StatelessWidget {
  final Expense expense;

  const _ReceiptViewer({required this.expense});

  Future<void> _confirmDelete(BuildContext context) async {
    final lang = context.read<SettingsProvider>().language;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'receipts_delete_title')),
        content: Text(tr(dctx, 'receipts_delete_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(tr(dctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(tr(dctx, 'delete')),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    // Delete the file, then clear the path on the expense.
    try {
      final f = File(expense.receiptPath!);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (!context.mounted) return;
    await context.read<ExpenseProvider>().update(
          Expense(
            id: expense.id,
            amount: expense.amount,
            categoryId: expense.categoryId,
            date: expense.date,
            note: expense.note,
            paymentMethod: expense.paymentMethod,
            place: expense.place,
          ),
        );
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('receipts_deleted', lang))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(expense.date);
    final catLabel = CustomCategoryRegistry.displayName(
      expense.categoryId,
      lang,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'receipts_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: tr(context, 'delete'),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.file(
                  File(expense.receiptPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: kGold.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatMoney(expense.amount),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: dark ? kGoldLight : kGoldDark),
                ),
                const SizedBox(height: 4),
                Text('$catLabel · $dateLabel',
                    style: Theme.of(context).textTheme.bodyMedium),
                if (expense.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    expense.note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
