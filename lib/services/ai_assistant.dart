import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../utils/formatters.dart';
import 'expense_query.dart';
import 'voice_budget_parser.dart';

/// An action the bot can perform on the user's data, parsed from chat.
class AiAction {
  /// 'add_expense' | 'add_income' | 'set_budget' | 'delete_last'
  final String type;
  final double? amount;
  final String? categoryId;
  final String? note;

  const AiAction({
    required this.type,
    this.amount,
    this.categoryId,
    this.note,
  });
}

/// Bot reply + optional action for the UI to execute.
class AiResponse {
  final String reply;
  final AiAction? action;

  const AiResponse(this.reply, [this.action]);
}

/// On-device AI assistant for Khorcha (Package BD).
///
/// Purely rule-based — no network, no API keys. Understands Bangla,
/// Banglish and English questions about spending, and answers them from
/// the local SQLite database (expenses + incomes).
class AiAssistant {
  AiAssistant._();

  /// Answers a natural-language money question in [lang] ('bn'/'en').
  /// Includes a short simulated "thinking" delay so the chat UI can show
  /// a typing indicator. Never throws.
  /// Returns an [AiResponse]; when [AiResponse.action] is set, the chat UI
  /// should execute it via the providers and confirm.
  static Future<AiResponse> answer(String input, String lang) async {
    // Simulated processing so the typing dots show briefly.
    await Future.delayed(const Duration(milliseconds: 400));
    final q = input.toLowerCase().trim();
    if (q.isEmpty) return AiResponse(_t('ai_fallback', lang));
    try {
      // Action intents first — the bot manages data like an assistant.
      final action = _parseAction(input, q, lang);
      if (action != null) return AiResponse('', action);
      if (_isGreeting(q)) return AiResponse(_t('ai_greeting_reply', lang));
      if (_isThanks(q)) return AiResponse(_t('ai_thanks_reply', lang));
      if (_isAdvice(q)) return AiResponse(await _advice(lang));
      if (_isSavings(q)) return AiResponse(await _savings(lang));
      if (_isBreakdown(q)) return AiResponse(await _breakdown(lang));
      if (_isComparison(q)) return AiResponse(await _comparison(lang));
      if (_isTop(q)) return AiResponse(await _topExpenses(lang));
      return AiResponse(await _generic(input, lang));
    } catch (_) {
      return AiResponse(_t('ai_fallback', lang));
    }
  }

  /// 4 quick-suggestion chips shown above the chat input.
  static List<String> suggestions(String lang) {
    return [
      _t('ai_sug_save', lang),
      _t('ai_sug_breakdown', lang),
      _t('ai_sug_compare', lang),
      _t('ai_sug_advice', lang),
    ];
  }

  // ------------------------------------------------------------------
  // Intent detection (Bangla + Banglish + English keywords).
  // Advice is checked first so "how to save" doesn't land in savings.
  // ------------------------------------------------------------------
  static bool _has(String q, List<String> keys) =>
      keys.any((k) => q.contains(k));

  static bool _isAdvice(String q) => _has(q, const [
        'advice', 'tips', 'tip dao', 'পরামর্শ', 'টিপস', 'টিপ',
        'khoroch komabo', 'খরচ কমাবো', 'খরচ কমানোর', 'কমানো',
        'how to save', 'how can i save', 'how do i save', 'কীভাবে সেভ',
        'কিভাবে সেভ', 'কীভাবে বাঁচাবো', 'kivabe save', 'কীভাবে খরচ কমাবো',
      ]);

  static bool _isSavings(String q) => _has(q, const [
        'koto save', 'কত সেভ', 'কতো সেভ', 'how much saved', 'how much save',
        'কত বাঁচ', 'সেভ করেছি', 'সেভ হয়েছে', 'saved this month',
        'savings কত', 'সঞ্চয় কত',
      ]);

  static bool _isBreakdown(String q) => _has(q, const [
        'breakdown', 'ব্রেকডাউন', 'কোন খাতে', 'কোন খাত', 'সব খাতে',
        'kothay khoroch', 'kothay koto', 'কোথায় কত', 'category-wise',
        'category wise', 'ক্যাটাগরি',
      ]);

  static bool _isComparison(String q) => _has(q, const [
        'vs', 'goto mas', 'গত মাস', 'গত মাসে', 'last month', 'তুলনা',
        'ager mas', 'আগের মাস', 'compared',
      ]);

  static bool _isTop(String q) => _has(q, const [
        'boro khoroch', 'বড় খরচ', 'বড়ো খরচ', 'সবচেয়ে বড়', 'biggest',
        'largest', 'top expense', 'top khoroch', 'সবচাইতে বড়',
      ]);

  static bool _isGreeting(String q) => _has(q, const [
        'hello', 'hi', 'hey', 'সালাম', 'আসসালামু', 'আদাব', 'নমস্কার',
        'good morning', 'good evening', 'শুভ',
      ]) && q.length < 30;

  static bool _isThanks(String q) => _has(q, const [
        'thank', 'ধন্যবাদ', 'শুকরিয়া', 'thanks a lot',
      ]);

  // ------------------------------------------------------------------
  // Action intents — the bot manages data, not just answers.
  // Questions (how/what/কত/?) never trigger actions.
  // ------------------------------------------------------------------
  static bool _looksLikeQuestion(String q) =>
      q.contains('?') ||
      q.startsWith('how') ||
      q.startsWith('what') ||
      q.startsWith('কত') ||
      q.startsWith('কোথায়') ||
      q.startsWith('কোন');

  static bool _isDeleteLast(String q) =>
      _has(q, const [
        'delete', 'ডিলিট', 'মুছে', 'মুছো', 'remove', 'বাদ দাও', 'বাদ দে',
      ]) &&
      _has(q, const [
        'last', 'শেষ', 'previous', 'আগের',
      ]);

  static bool _isSetBudget(String q) => _has(q, const ['budget', 'বাজেট']);

  static bool _isAddIncome(String q) => _has(q, const [
        'income', 'আয়', 'aay', 'বেতন', 'salary',
      ]);

  static bool _isAddExpense(String q) => _has(q, const [
        'add', 'যোগ', 'khoroch', 'খরচ', 'expense', 'ব্যয়',
        'spent', 'খরচ করলাম', 'khoroch korlam',
      ]);

  /// Parses an action command. Returns null when the input is a question
  /// or has no actionable amount.
  static AiAction? _parseAction(String input, String q, String lang) {
    if (_looksLikeQuestion(q)) return null;

    // Delete last expense — no amount needed.
    if (_isDeleteLast(q)) {
      return const AiAction(type: 'delete_last');
    }

    final parsed = VoiceBudgetParser.parse(input, lang);
    final amount = parsed.amount;
    if (amount == null || amount <= 0) return null;

    if (_isSetBudget(q)) {
      return AiAction(
        type: 'set_budget',
        amount: amount,
        categoryId: parsed.categoryId ?? 'others',
      );
    }
    if (_isAddIncome(q)) {
      // "salary 50000" — note keeps the raw input for reference.
      return AiAction(
        type: 'add_income',
        amount: amount,
        note: input.trim(),
      );
    }
    if (_isAddExpense(q)) {
      return AiAction(
        type: 'add_expense',
        amount: amount,
        categoryId: parsed.categoryId ?? 'others',
        note: '',
      );
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Data helpers.
  // ------------------------------------------------------------------
  static String _t(String key, String lang) => AppStrings.get(key, lang);

  static String _money(double v) => formatMoney(v);

  /// Currency-correct amount: BDT-converted value when available.
  static double _bdt(Expense e) => e.bdtAmount ?? e.amount;

  static List<Expense> _thisMonth(List<Expense> all) {
    final now = DateTime.now();
    return all
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .toList();
  }

  static List<Expense> _lastMonth(List<Expense> all) {
    final first = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final prev = DateTime(first.year, first.month - 1, 1);
    return all
        .where((e) => e.date.year == prev.year && e.date.month == prev.month)
        .toList();
  }

  static double _incomeThisMonth(List<Income> all) {
    final now = DateTime.now();
    return all
        .where((i) => i.date.year == now.year && i.date.month == now.month)
        .fold<double>(0, (s, i) => s + i.amount);
  }

  /// Category totals, highest first.
  static List<MapEntry<String, double>> _categoryTotals(
      List<Expense> expenses) {
    final sums = <String, double>{};
    for (final e in expenses) {
      sums[e.categoryId] = (sums[e.categoryId] ?? 0) + _bdt(e);
    }
    final entries = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  // ------------------------------------------------------------------
  // Intent: savings — income minus expense for the current month.
  // ------------------------------------------------------------------
  static Future<String> _savings(String lang) async {
    final db = DatabaseHelper.instance;
    final expenses = _thisMonth(await db.getAllExpenses());
    final income = _incomeThisMonth(await db.getAllIncomes());
    final spent = expenses.fold<double>(0, (s, e) => s + _bdt(e));
    final saved = income - spent;
    final base = _t('ai_save_answer', lang)
        .replaceAll('{income}', _money(income))
        .replaceAll('{spent}', _money(spent))
        .replaceAll('{saved}', _money(saved.abs()));
    if (saved >= 0) return '$base ${_t('ai_save_good', lang)}';
    return '$base ${_t('ai_save_bad', lang)}';
  }

  // ------------------------------------------------------------------
  // Intent: category breakdown — top 3 categories with shares.
  // ------------------------------------------------------------------
  static Future<String> _breakdown(String lang) async {
    final expenses =
        _thisMonth(await DatabaseHelper.instance.getAllExpenses());
    if (expenses.isEmpty) return _t('ai_no_data', lang);
    final totals = _categoryTotals(expenses);
    final grand = totals.fold<double>(0, (s, e) => s + e.value);
    final lines = totals.take(3).map((e) {
      final pct = grand > 0 ? (e.value / grand * 100).round() : 0;
      return _t('ai_breakdown_line', lang)
          .replaceAll('{cat}', CustomCategoryRegistry.displayName(e.key, lang))
          .replaceAll('{amount}', _money(e.value))
          .replaceAll('{pct}', '$pct');
    }).join('\n');
    final total = _t('ai_breakdown_total', lang)
        .replaceAll('{amount}', _money(grand));
    return '$lines\n$total';
  }

  // ------------------------------------------------------------------
  // Intent: comparison — this month vs last month.
  // ------------------------------------------------------------------
  static Future<String> _comparison(String lang) async {
    final all = await DatabaseHelper.instance.getAllExpenses();
    final thisM = _thisMonth(all).fold<double>(0, (s, e) => s + _bdt(e));
    final lastM = _lastMonth(all).fold<double>(0, (s, e) => s + _bdt(e));
    final delta = thisM - lastM;
    if (delta.abs() < 1) {
      return _t('ai_compare_same', lang)
          .replaceAll('{this}', _money(thisM))
          .replaceAll('{last}', _money(lastM));
    }
    final pct = lastM > 0 ? (delta.abs() / lastM * 100).round() : 0;
    final key = delta > 0 ? 'ai_compare_up' : 'ai_compare_down';
    return _t(key, lang)
        .replaceAll('{this}', _money(thisM))
        .replaceAll('{last}', _money(lastM))
        .replaceAll('{delta}', _money(delta.abs()))
        .replaceAll('{pct}', '$pct');
  }

  // ------------------------------------------------------------------
  // Intent: top individual expenses this month.
  // ------------------------------------------------------------------
  static Future<String> _topExpenses(String lang) async {
    final expenses =
        _thisMonth(await DatabaseHelper.instance.getAllExpenses());
    if (expenses.isEmpty) return _t('ai_no_data', lang);
    expenses.sort((a, b) => _bdt(b).compareTo(_bdt(a)));
    final lines = expenses.take(3).map((e) {
      final cat = CustomCategoryRegistry.displayName(e.categoryId, lang);
      final note = e.note.isNotEmpty ? ' — ${e.note}' : '';
      return _t('ai_top_line', lang)
          .replaceAll('{amount}', _money(_bdt(e)))
          .replaceAll('{cat}', cat)
          .replaceAll('{note}', note);
    }).join('\n');
    return '${_t('ai_top_header', lang)}\n$lines';
  }

  // ------------------------------------------------------------------
  // Intent: advice — actionable, based on the top category.
  // ------------------------------------------------------------------
  static Future<String> _advice(String lang) async {
    final expenses =
        _thisMonth(await DatabaseHelper.instance.getAllExpenses());
    if (expenses.isEmpty) return _t('ai_advice_empty', lang);
    final totals = _categoryTotals(expenses);
    final top = totals.first;
    final grand = totals.fold<double>(0, (s, e) => s + e.value);
    final pct = grand > 0 ? (top.value / grand * 100).round() : 0;
    final save = top.value * 0.10;
    final tip = _t('ai_advice_top', lang)
        .replaceAll('{cat}', CustomCategoryRegistry.displayName(top.key, lang))
        .replaceAll('{pct}', '$pct')
        .replaceAll('{amount}', _money(top.value))
        .replaceAll('{save}', _money(save));
    return '$tip\n${_t('ai_advice_generic', lang)}';
  }

  // ------------------------------------------------------------------
  // Fallback: reuse ExpenseQueryParser for balance / period / category
  // totals from the parsed query.
  // ------------------------------------------------------------------
  static Future<String> _generic(String input, String lang) async {
    final q = ExpenseQueryParser.parse(input, lang);
    final all = await DatabaseHelper.instance.getAllExpenses();
    if (q.asksBalance) {
      final incomes = await DatabaseHelper.instance.getAllIncomes();
      final bal = _incomeThisMonth(incomes) -
          _thisMonth(all).fold<double>(0, (s, e) => s + _bdt(e));
      return _t('ai_balance', lang).replaceAll('{amount}', _money(bal));
    }
    double total = 0;
    for (final e in all) {
      final inRange = !e.date.isBefore(q.from) && !e.date.isAfter(q.to);
      final inCat = q.categoryId == null || e.categoryId == q.categoryId;
      if (inRange && inCat) total += _bdt(e);
    }
    final period = _periodLabel(q, lang);
    if (q.categoryId != null) {
      final cat = CustomCategoryRegistry.displayName(q.categoryId!, lang);
      return _t('ai_spent_cat', lang)
          .replaceAll('{amount}', _money(total))
          .replaceAll('{cat}', cat)
          .replaceAll('{period}', period);
    }
    return _t('ai_spent_total', lang)
        .replaceAll('{amount}', _money(total))
        .replaceAll('{period}', period);
  }

  /// Short human label for the parsed date range.
  static String _periodLabel(ParsedQuery q, String lang) {
    final now = DateTime.now();
    final thisMonth =
        q.from.year == now.year && q.from.month == now.month && q.from.day == 1;
    if (thisMonth) return _t('ai_period_month', lang);
    final sameDay = q.from.year == q.to.year &&
        q.from.month == q.to.month &&
        q.from.day == q.to.day;
    if (sameDay) {
      return '${q.from.day}/${q.from.month}';
    }
    return '${q.from.day}/${q.from.month}–${q.to.day}/${q.to.month}';
  }
}
