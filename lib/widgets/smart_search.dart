import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/add_expense_screen.dart';
import '../services/currency_service.dart';
import '../services/expense_query.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// Smart natural-language search for expenses.
///
/// Type e.g. "food this week" / "এই মাসে খাবার" (Bangla supported), hit the
/// search button, and a gold-tinted result card shows the total, the item
/// count and the parsed date range, followed by the matching expense rows.
/// Balance questions ("balance this month" / "ব্যালেন্স") show an
/// income-minus-expense card instead of expense rows.
///
/// Fallback: when the query has no date keywords and no category
/// (e.g. "500", "lunch", "ধানমন্ডি"), it searches ALL expenses by note,
/// category name, place and amount, with the matched text highlighted
/// gold-bold in the note line.
///
/// Recent searches (prefs key 'recent_searches', max 8, most-recent-first)
/// appear as chips while the field is empty and no search has run.
class SmartSearch extends StatefulWidget {
  const SmartSearch({super.key});

  /// Clears all saved search history (used from Settings).
  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recent_searches');
    } catch (_) {}
  }

  @override
  State<SmartSearch> createState() => _SmartSearchState();
}

class _SmartSearchState extends State<SmartSearch> {
  static const _recentKey = 'recent_searches';
  static const _maxRecent = 8;

  final _controller = TextEditingController();
  ParsedQuery? _query;

  /// Raw text of the last executed search (drives fallback + highlight).
  String _searchText = '';

  /// True when the current results come from the text/amount fallback.
  bool _fallback = false;

  bool _searched = false;
  List<String> _recent = [];
  bool _fieldEmpty = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadRecent();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final empty = _controller.text.isEmpty;
    if (empty != _fieldEmpty) {
      setState(() => _fieldEmpty = empty);
    }
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      if (mounted) {
        setState(() => _recent = list.take(_maxRecent).toList());
      }
    } catch (_) {
      // Corrupt prefs must never break search.
    }
  }

  Future<void> _saveRecent(String text) async {
    final updated =
        [text, ..._recent.where((s) => s != text)].take(_maxRecent).toList();
    if (mounted) setState(() => _recent = updated);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentKey, jsonEncode(updated));
    } catch (_) {
      // Best effort only.
    }
  }

  /// Removes one history entry (long-press on a chip).
  Future<void> _removeRecent(String text) async {
    final updated = _recent.where((s) => s != text).toList();
    if (mounted) setState(() => _recent = updated);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentKey, jsonEncode(updated));
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              tr(context, 'search_hist_removed').replaceAll('{q}', text)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _runSearch([String? preset]) {
    if (preset != null) {
      _controller.text = preset;
      _controller.selection =
          TextSelection.collapsed(offset: preset.length);
    }
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final lang = context.read<SettingsProvider>().language;
    final parsed = ExpenseQueryParser.parse(text, lang);
    // Fallback when the parser found nothing meaningful: no date keywords
    // and no category — search note/category/amount across all expenses.
    final fallback = !parsed.asksBalance &&
        parsed.categoryId == null &&
        !_hasDateKeyword(text);
    _saveRecent(text);
    setState(() {
      _query = parsed;
      _searchText = text;
      _fallback = fallback;
      _searched = true;
    });
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _query = null;
      _searchText = '';
      _fallback = false;
      _searched = false;
    });
  }

  /// Mirrors [ExpenseQueryParser]'s date keywords (which are private) so the
  /// fallback decision matches what the parser itself would detect.
  static const _dateKeywords = [
    'today',
    'আজ',
    'yesterday',
    'গতকাল',
    'this week',
    'এই সপ্তাহ',
    'last week',
    'গত সপ্তাহ',
    'this month',
    'এই মাস',
    'চলতি মাস',
    'last month',
    'গত মাস',
  ];

  static const _monthNames = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
    'jan',
    'feb',
    'mar',
    'apr',
    'jun',
    'jul',
    'aug',
    'sep',
    'sept',
    'oct',
    'nov',
    'dec',
    'জানুয়ারি',
    'জানুয়ারী',
    'ফেব্রুয়ারি',
    'ফেব্রুয়ারী',
    'মার্চ',
    'এপ্রিল',
    'মে',
    'জুন',
    'জুলাই',
    'আগস্ট',
    'সেপ্টেম্বর',
    'অক্টোবর',
    'নভেম্বর',
    'ডিসেম্বর',
  ];

  static bool _hasDateKeyword(String input) {
    final q = input.toLowerCase().trim();
    for (final k in _dateKeywords) {
      if (q.contains(k)) return true;
    }
    for (final m in _monthNames) {
      if (m.codeUnits.first < 128) {
        // English: word-boundary match, same as the parser.
        if (RegExp('\\b${RegExp.escape(m)}\\b').hasMatch(q)) return true;
      } else {
        if (q.contains(m)) return true;
      }
    }
    return false;
  }

  /// Matches [query]: date inside [from, to] with the end bound inclusive
  /// of the whole day, plus an optional category filter. Newest first.
  /// In fallback mode, matches note/category/place/amount across ALL
  /// expenses instead.
  List<Expense> _matches(ParsedQuery query, List<Expense> all) {
    if (_fallback) return _textMatches(_searchText, all);
    final dayStart =
        DateTime(query.from.year, query.from.month, query.from.day);
    final dayEnd = DateTime(
      query.to.year,
      query.to.month,
      query.to.day,
      23,
      59,
      59,
      999,
    );
    final result = all.where((e) {
      final inRange = !e.date.isBefore(dayStart) && !e.date.isAfter(dayEnd);
      final inCategory =
          query.categoryId == null || e.categoryId == query.categoryId;
      return inRange && inCategory;
    }).toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// Text/amount fallback: matches [raw] against note, category name
  /// (built-in en+bn + custom names), place label and amount/bdtAmount.
  /// Newest first.
  List<Expense> _textMatches(String raw, List<Expense> all) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return [];
    final numQ = double.tryParse(_latinDigits(q.replaceAll(',', '')));
    final result = all.where((e) {
      if (e.note.toLowerCase().contains(q)) return true;
      if (e.place != null && e.place!.toLowerCase().contains(q)) return true;
      final enName =
          AppStrings.categoryName(e.categoryId, 'en').toLowerCase();
      final bnName =
          AppStrings.categoryName(e.categoryId, 'bn').toLowerCase();
      final custom = CustomCategoryRegistry.byId(e.categoryId);
      if (enName.contains(q) || bnName.contains(q)) return true;
      if (custom != null && custom.name.toLowerCase().contains(q)) {
        return true;
      }
      if (numQ != null) {
        if (e.amount == numQ) return true;
        if ((e.bdtAmount ?? e.amount) == numQ) return true;
      }
      return false;
    }).toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  /// Converts Bangla digits to ASCII so "৫০০" parses as 500.
  static String _latinDigits(String s) {
    const bn = '০১২৩৪৫৬৭৮৯';
    var out = s;
    for (var i = 0; i < bn.length; i++) {
      out = out.replaceAll(bn[i], '$i');
    }
    return out;
  }

  String _rangeLabel(DateTime from, DateTime to, String lang) {
    final loc = lang == 'bn' ? 'bn' : 'en';
    final fromDay = DateFormat('d', loc).format(from);
    final toEnd = DateFormat('d MMM', loc).format(to);
    return '$fromDay–$toEnd';
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: tr(context, 'search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _runSearch,
              icon: const Icon(Icons.arrow_forward),
              tooltip: tr(context, 'search_hint'),
            ),
            if (_searched)
              IconButton(
                onPressed: _clear,
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
        if (!_searched && _fieldEmpty && _recent.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tr(context, 'recent_searches'),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in _recent)
                GestureDetector(
                  onLongPress: () => _removeRecent(s),
                  child: ActionChip(
                    avatar: const Icon(Icons.history, size: 16),
                    label: Text(s),
                    onPressed: () => _runSearch(s),
                  ),
                ),
            ],
          ),
        ],
        if (_searched && _query != null) ...[
          const SizedBox(height: 12),
          StaggeredEntrance(
            key: ValueKey(_controller.text.trim()),
            child: _query!.asksBalance
                ? _buildBalanceCard(context, lang, theme)
                : _buildResultsCard(context, lang, theme),
          ),
        ],
      ],
    );
  }

  Widget _buildResultsCard(
    BuildContext context,
    String lang,
    ThemeData theme,
  ) {
    final query = _query!;
    final matches =
        _matches(query, context.read<ExpenseProvider>().expenses);
    final total = matches.fold(0.0, (sum, e) => sum + e.amount);
    // Highlight the raw text in fallback mode; otherwise the matched
    // category's display name when the note mentions it.
    final highlightTerm = _fallback
        ? _searchText
        : (query.categoryId == null
            ? ''
            : CustomCategoryRegistry.displayName(query.categoryId!, lang));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: kGold.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fallback
                      ? '“$_searchText”'
                      : _rangeLabel(query.from, query.to, lang),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: kGoldDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoney(total),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${matches.length} ${tr(context, 'qsearch_expenses')}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              tr(context, 'qsearch_no_result'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: matches.length,
            itemBuilder: (ctx, i) => StaggeredEntrance(
              delayMs: 40 * i,
              child: _SearchExpenseTile(
                expense: matches[i],
                highlight: highlightTerm,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBalanceCard(
    BuildContext context,
    String lang,
    ThemeData theme,
  ) {
    final now = DateTime.now();
    final income =
        context.read<MoneyProvider>().incomeForMonth(monthKeyOf(now));
    final spent = context.read<ExpenseProvider>().totalThisMonth();
    final balance = income - spent;

    return Card(
      color: kGold.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'qsearch_balance_title'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: kGoldDark,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatMoney(balance),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: balance >= 0 ? Colors.green.shade700 : theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              monthLong(now, lang),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
/// Splits [text] into spans, wrapping every case-insensitive occurrence of
/// [needle] in gold bold. Returns a single plain span when [needle] is empty
/// or not found.
List<TextSpan> highlightSpans(String text, String needle, TextStyle base) {
  final q = needle.trim().toLowerCase();
  if (q.isEmpty || !text.toLowerCase().contains(q)) {
    return [TextSpan(text: text, style: base)];
  }
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final idx = lower.indexOf(q, start);
    if (idx < 0) {
      spans.add(TextSpan(text: text.substring(start), style: base));
      break;
    }
    if (idx > start) {
      spans.add(TextSpan(text: text.substring(start, idx), style: base));
    }
    spans.add(TextSpan(
      text: text.substring(idx, idx + q.length),
      style: base.copyWith(color: kGold, fontWeight: FontWeight.bold),
    ));
    start = idx + q.length;
  }
  return spans;
}

/// Search-result row mirroring [ExpenseTile] (tap to edit, swipe left to
/// delete) with the matched query highlighted gold-bold in the note line.
/// Kept local to this file so highlight state never leaks into the shared
/// tile used by the home list.
class _SearchExpenseTile extends StatelessWidget {
  final Expense expense;
  final String highlight;

  const _SearchExpenseTile({required this.expense, required this.highlight});

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_title')),
        content: Text(tr(ctx, 'delete_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final cat = categoryById(expense.categoryId);
    final custom = CustomCategoryRegistry.byId(expense.categoryId);
    final theme = Theme.of(context);
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(expense.date);
    final meta =
        '${AppStrings.paymentName(expense.paymentMethod, lang)} • $dateLabel';
    final subStyle = theme.listTileTheme.subtitleTextStyle ??
        theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant) ??
        const TextStyle();

    return Dismissible(
      key: ValueKey('search-expense-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        final id = expense.id;
        if (id == null) return;
        context.read<ExpenseProvider>().remove(id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('msg_deleted', lang))),
        );
      },
      child: PressableScale(
        pressedScale: 0.98,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: cat.color.withValues(alpha: 0.15),
            child: custom != null && custom.emoji.isNotEmpty
                ? Text(custom.emoji, style: const TextStyle(fontSize: 20))
                : Icon(cat.icon, color: cat.color, size: 20),
          ),
          title: Text(
              CustomCategoryRegistry.displayName(expense.categoryId, lang)),
          subtitle: RichText(
            text: TextSpan(
              style: subStyle,
              children: [
                TextSpan(text: meta),
                if (expense.note.isNotEmpty) ...[
                  const TextSpan(text: '\n'),
                  ...highlightSpans(expense.note, highlight, subStyle),
                ],
              ],
            ),
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(expense.bdtAmount ?? expense.amount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (expense.currency != 'BDT')
                Text(
                  '(${CurrencyService.symbols[expense.currency] ?? expense.currency}${_trimAmt(expense.amount)})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddExpenseScreen(expense: expense),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Compact display of a non-BDT original amount: 10 → "10", 10.5 → "10.5".
String _trimAmt(double value) {
  final whole = value.truncateToDouble() == value;
  return whole ? value.toStringAsFixed(0) : value.toString();
}
