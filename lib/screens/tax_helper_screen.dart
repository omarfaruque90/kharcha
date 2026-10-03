import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Package AS: tax helper.
///
/// Yearly per-category totals table with a per-category "business/taxable"
/// flag (stored in the 'tax_categories' settings JSON key), plus a
/// Bangladesh-context summary card. Record-keeping aid only — not tax
/// advice.
///
/// Export: ExportService only offers monthly PDF/Excel/fancy-statement
/// exports, no generic table export, so the breakdown is shown on screen.
class TaxHelperScreen extends StatefulWidget {
  const TaxHelperScreen({super.key});

  @override
  State<TaxHelperScreen> createState() => _TaxHelperScreenState();
}

class _TaxHelperScreenState extends State<TaxHelperScreen> {
  static const _settingsKey = 'tax_categories';

  late int _year;
  Set<String> _taxable = {};
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _year = DateTime.now().year;
    _loadTaxable();
  }

  Future<void> _loadTaxable() async {
    final raw = await DatabaseHelper.instance.getSetting(_settingsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).map((e) => e.toString());
      if (mounted) setState(() => _taxable = list.toSet());
    } catch (_) {
      // Corrupt JSON — start empty.
    }
  }

  Future<void> _toggleTaxable(String categoryId, bool value) async {
    final next = Set<String>.of(_taxable);
    if (value) {
      next.add(categoryId);
    } else {
      next.remove(categoryId);
    }
    setState(() => _taxable = next);
    await DatabaseHelper.instance
        .setSetting(_settingsKey, jsonEncode(next.toList()));
  }

  /// Year totals per category id, reusing ExpenseProvider.totalsByCategory.
  Map<String, double> _yearTotals(ExpenseProvider expenses) {
    final map = <String, double>{};
    for (var m = 1; m <= 12; m++) {
      for (final e
          in expenses.totalsByCategory(DateTime(_year, m)).entries) {
        map[e.key] = (map[e.key] ?? 0) + e.value;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final expenses = context.watch<ExpenseProvider>();

    final totals = _yearTotals(expenses);
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final yearTotal = totals.values.fold(0.0, (a, b) => a + b);
    final businessTotal = sorted
        .where((e) => _taxable.contains(e.key))
        .fold(0.0, (a, e) => a + e.value);

    final currentYear = DateTime.now().year;
    final yearOptions =
        List.generate(5, (i) => currentYear - 2 + i);

    return Scaffold(
      appBar: AppBar(title: Text(_txr(lang, 'tx_title'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          StaggeredEntrance(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_txr(lang, 'tx_year_total')}: '
                        '${formatMoney(yearTotal)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DropdownButton<int>(
                      value: _year,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final y in yearOptions)
                          DropdownMenuItem(
                            value: y,
                            child: Text('$y'),
                          ),
                      ],
                      onChanged: (y) {
                        if (y != null) setState(() => _year = y);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Summary card (Bangladesh context).
          StaggeredEntrance(
            delayMs: 60,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kDeepGreenDark, kDeepGreen, kDeepGreenCard],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: kGold.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.business_center_outlined,
                          color: kGold),
                      const SizedBox(width: 8),
                      Text(
                        _txr(lang, 'tx_business_total'),
                        style: const TextStyle(
                          color: kGoldLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatMoney(businessTotal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _txr(lang, 'tx_disclaimer'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            delayMs: 120,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_txr(lang, 'tx_category')}: $_year',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _txr(lang, 'tx_table_hint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (sorted.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: Text(_txr(lang, 'tx_no_data'))),
                      )
                    else
                      for (var i = 0; i < sorted.length; i++)
                        _taxRow(
                          theme,
                          lang,
                          sorted[i].key,
                          sorted[i].value,
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _taxRow(
    ThemeData theme,
    String lang,
    String categoryId,
    double total,
  ) {
    final cat = categoryById(categoryId);
    final isTaxable = _taxable.contains(categoryId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(cat.icon, size: 18, color: cat.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              CustomCategoryRegistry.displayName(categoryId, lang),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            formatMoney(total),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: _txr(lang, 'tx_taxable'),
            child: Switch(
              value: isTaxable,
              activeThumbColor: kGold,
              onChanged: (v) => _toggleTaxable(categoryId, v),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Package AS: proposed AppStrings keys — add them to
// lib/l10n/app_strings.dart ('en'/'bn' maps); the local map keeps the screen
// working until then. (Same pattern as Package U's _yrStrings.)
// ---------------------------------------------------------------------------
const Map<String, Map<String, String>> _txStrings = {
  'en': {
    'tx_title': 'Tax Helper',
    'tx_year_total': 'Year total',
    'tx_business_total': 'Business expenses',
    'tx_disclaimer':
        'Rough estimate for record-keeping — consult a tax professional. Not legal advice.',
    'tx_category': 'By category',
    'tx_table_hint':
        'Toggle the switch on categories that count as business expenses.',
    'tx_taxable': 'Business / taxable',
    'tx_no_data': 'No expenses recorded this year.',
  },
  'bn': {
    'tx_title': 'ট্যাক্স সহায়ক',
    'tx_year_total': 'বছরের মোট',
    'tx_business_total': 'ব্যবসায়িক খরচ',
    'tx_disclaimer':
        'হিসাব রাখার জন্য আনুমানিক — কর বিশেষজ্ঞের পরামর্শ নিন। আইনি পরামর্শ নয়।',
    'tx_category': 'খাত অনুযায়ী',
    'tx_table_hint':
        'যেসব খাত ব্যবসায়িক খরচ হিসেবে গণ্য, সেগুলোতে সুইচ চালু করুন।',
    'tx_taxable': 'ব্যবসায়িক / করযোগ্য',
    'tx_no_data': 'এ বছর কোনো খরচ রেকর্ড হয়নি।',
  },
};

String _txr(String lang, String key) =>
    _txStrings[lang]?[key] ?? _txStrings['en']![key] ?? key;
