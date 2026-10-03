import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Package AO: "Medical" tracker view.
///
/// Lists health-related expenses that carry a note or a receipt photo —
/// doctor visits, medicines, diagnostics — newest first. Tap an entry for
/// the detail view (receipt photo + note).
///
/// Health-related = [Expense.categoryId] is 'health' (the real built-in
/// health category id) OR the category's display name contains a
/// health/doctor/medicine keyword (en + bn), so user-created categories
/// like "Doctor visit" or "ওষুধ" are picked up too.
class MedicalScreen extends StatefulWidget {
  const MedicalScreen({super.key});

  @override
  State<MedicalScreen> createState() => _MedicalScreenState();

  /// True when [e] is health-related AND has a note or a receipt path.
  static bool isMedicalRecord(Expense e) {
    final enName =
        CustomCategoryRegistry.displayName(e.categoryId, 'en').toLowerCase();
    final bnName = CustomCategoryRegistry.displayName(e.categoryId, 'bn');
    final healthRelated = e.categoryId == 'health' ||
        enName.contains('health') ||
        enName.contains('doctor') ||
        enName.contains('medicine') ||
        bnName.contains('স্বাস্থ্য') ||
        bnName.contains('ডাক্তার') ||
        bnName.contains('ওষুধ');
    if (!healthRelated) return false;
    return e.note.trim().isNotEmpty ||
        (e.receiptPath != null && e.receiptPath!.isNotEmpty);
  }
}

class _MedicalScreenState extends State<MedicalScreen> {
  /// Memoized records: the health filter scans every expense, so recompute
  /// only when the provider hands over a new list instance.
  List<Expense>? _lastExpenses;
  List<Expense> _records = const [];

  List<Expense> _recordsFor(List<Expense> expenses) {
    if (!identical(expenses, _lastExpenses)) {
      _lastExpenses = expenses;
      _records =
          expenses.where(MedicalScreen.isMedicalRecord).toList();
    }
    return _records;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final records =
        _recordsFor(context.watch<ExpenseProvider>().expenses);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'medical_title')),
      ),
      body: records.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.medical_services_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'medical_empty'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'medical_empty_sub'),
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
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: records.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final e = records[i];
                return StaggeredEntrance(
                  delayMs: (i * 40).clamp(0, 320),
                  child: _MedicalTile(expense: e, lang: lang),
                );
              },
            ),
    );
  }
}

class _MedicalTile extends StatelessWidget {
  final Expense expense;
  final String lang;

  const _MedicalTile({required this.expense, required this.lang});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(expense.date);
    final hasPhoto = expense.receiptPath != null &&
        expense.receiptPath!.isNotEmpty &&
        File(expense.receiptPath!).existsSync();
    final cat = categoryById(expense.categoryId);
    final catLabel = CustomCategoryRegistry.displayName(
      expense.categoryId,
      lang,
    );

    return ListTile(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MedicalDetail(expense: expense),
        ),
      ),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: hasPhoto
            ? Image.file(
                File(expense.receiptPath!),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackIcon(cat),
              )
            : _fallbackIcon(cat),
      ),
      title: Text(
        expense.note.trim().isNotEmpty ? expense.note.trim() : catLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$catLabel · $dateLabel',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatMoney(expense.amount),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: dark ? kGoldLight : kGoldDark,
        ),
      ),
    );
  }

  Widget _fallbackIcon(ExpenseCategory cat) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: cat.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        cat.icon,
        color: cat.color,
        size: 26,
      ),
    );
  }
}

/// Detail view: receipt photo (if attached) + amount, date, note, category.
class _MedicalDetail extends StatelessWidget {
  final Expense expense;

  const _MedicalDetail({required this.expense});

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
    final hasPhoto = expense.receiptPath != null &&
        expense.receiptPath!.isNotEmpty &&
        File(expense.receiptPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'medical_title')),
      ),
      body: ListView(
        children: [
          if (hasPhoto)
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.file(
                File(expense.receiptPath!),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  size: 64,
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
                        color: dark ? kGoldLight : kGoldDark,
                      ),
                ),
                const SizedBox(height: 4),
                Text('$catLabel · $dateLabel',
                    style: Theme.of(context).textTheme.bodyMedium),
                if (expense.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    expense.note.trim(),
                    style: Theme.of(context).textTheme.bodyLarge,
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
