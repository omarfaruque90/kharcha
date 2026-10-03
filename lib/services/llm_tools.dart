import '../l10n/app_strings.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/total_balance_provider.dart';
import '../utils/formatters.dart';

// ---------------------------------------------------------------------------
// Context + tool definition.
// ---------------------------------------------------------------------------

/// Everything a tool needs to do its job.
class LlmToolContext {
  final ExpenseProvider expenses;
  final MoneyProvider money;
  final TotalBalanceProvider wallets;
  final String lang;

  const LlmToolContext({
    required this.expenses,
    required this.money,
    required this.wallets,
    required this.lang,
  });
}

class LlmToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<String> Function(
      Map<String, dynamic> args, LlmToolContext ctx) execute;

  const LlmToolDef({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  /// JSON-schema map for the LLM provider (used by both Gemini and OpenAI).
  Map<String, dynamic> get schema => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

Map<String, dynamic> _obj(
  Map<String, Map<String, dynamic>> props,
  List<String> required,
) =>
    {
      'type': 'object',
      'properties': props,
      'required': required,
    };

Map<String, dynamic> _num(String desc) =>
    {'type': 'number', 'description': desc};

Map<String, dynamic> _str(String desc, {List<String>? enumValues}) => {
      'type': 'string',
      'description': desc,
      if (enumValues != null) 'enum': enumValues,
    };

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

DateTime _parseDate(dynamic v) {
  if (v is String) {
    final d = DateTime.tryParse(v.trim());
    if (d != null) return d;
  }
  return DateTime.now();
}

String _monthKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Resolves a category name/id from the LLM to a real category id.
/// Matches ids, English/Bangla names, and common keywords.
String resolveCategoryId(String? raw, String lang) {
  final q = (raw ?? '').trim().toLowerCase();
  if (q.isEmpty) return 'others';
  // Direct id hit (built-in or custom).
  for (final c in kCategories) {
    if (c.id == q) return c.id;
  }
  for (final c in CustomCategoryRegistry.all) {
    if (c.id.toLowerCase() == q) return c.id;
  }
  // Localized name hit (en + bn).
  for (final c in kCategories) {
    for (final l in ['en', 'bn']) {
      if (AppStrings.categoryName(c.id, l).toLowerCase() == q) return c.id;
    }
  }
  for (final c in CustomCategoryRegistry.all) {
    if (c.name.toLowerCase() == q) return c.id;
  }
  // Keyword fallback (Bangla + English).
  const keywords = {
    'food': [
      'khabar',
      'khawa',
      'khaoa',
      'lunch',
      'dinner',
      'breakfast',
      'nasta',
      'restaurant',
      'food',
      'kheyechi',
      'khelam'
    ],
    'transport': [
      'vara',
      'bhara',
      'rickshaw',
      'bus',
      'cng',
      'uber',
      'pathao',
      'transport',
      'jatayat',
      'gari'
    ],
    'shopping': [
      'bazar',
      'shopping',
      'kinlam',
      'kinchi',
      'dress',
      'jama',
      'kapor',
      'market'
    ],
    'bills': [
      'bill',
      'current',
      'biddut',
      'electricity',
      'gas',
      'pani',
      'water',
      'wifi',
      'net',
      'recharge',
      'mobile'
    ],
    'health': [
      'oshudh',
      'osudh',
      'medicine',
      'doctor',
      'daktar',
      'health',
      'hospital',
      'chikitsa'
    ],
    'entertainment': [
      'movie',
      'cinema',
      'ghurte',
      'ghurtegelam',
      'entertainment',
      'fun',
      'game',
      'khela'
    ],
    'education': [
      'boi',
      'book',
      'school',
      'college',
      'tuition',
      'teacher',
      'education',
      'porashona',
      'exam',
      'fees'
    ],
    'pet_food': ['pet', 'biral', 'kukur', 'cat', 'dog'],
  };
  for (final entry in keywords.entries) {
    for (final kw in entry.value) {
      if (q.contains(kw)) return entry.key;
    }
  }
  return 'others';
}

String resolvePaymentMethod(String? raw) {
  final q = (raw ?? '').trim().toLowerCase();
  switch (q) {
    case 'cash':
      return 'cash';
    case 'bkash':
      return 'mobile_banking:bKash';
    case 'nagad':
      return 'mobile_banking:Nagad';
    case 'rocket':
      return 'mobile_banking:Rocket';
    case 'upay':
      return 'mobile_banking:Upay';
    case 'card':
      return 'card';
    case 'bank':
      return 'other';
    default:
      return 'cash';
  }
}

/// Short category list for the system prompt.
String categoryListForPrompt(String lang) {
  final parts = <String>[];
  for (final c in kCategories) {
    parts.add('${c.id} (${AppStrings.categoryName(c.id, lang)})');
  }
  for (final c in CustomCategoryRegistry.all) {
    parts.add('${c.id} (${c.name})');
  }
  return parts.join(', ');
}

// ---------------------------------------------------------------------------
// Tool definitions.
// ---------------------------------------------------------------------------

List<LlmToolDef> buildLlmTools() => [
      LlmToolDef(
        name: 'add_expense',
        description:
            'Record a new expense. Use when the user says they spent money.',
        parameters: _obj({
          'amount': _num('Amount spent in BDT (required)'),
          'category': _str(
              'Category id or name, e.g. food, transport, shopping. Optional.'),
          'note': _str('Short note, e.g. what was bought. Optional.'),
          'payment_method': _str(
              'How they paid. Optional.',
              enumValues: const [
                'cash',
                'bkash',
                'nagad',
                'rocket',
                'upay',
                'card',
                'bank'
              ]),
          'date': _str(
              'Date as YYYY-MM-DD. Optional, defaults to today.'),
        }, const [
          'amount'
        ]),
        execute: (args, ctx) async {
          final amount = _asDouble(args['amount']);
          if (amount <= 0) return 'Error: amount must be positive.';
          final categoryId =
              resolveCategoryId(args['category']?.toString(), ctx.lang);
          final note = args['note']?.toString() ?? '';
          final pm = resolvePaymentMethod(args['payment_method']?.toString());
          final date = _parseDate(args['date']);
          final expense = Expense(
            amount: amount,
            categoryId: categoryId,
            date: date,
            note: note,
            paymentMethod: pm,
            currency: 'BDT',
            bdtAmount: amount,
          );
          await ctx.expenses.add(expense);
          try {
            await ctx.wallets.deductForExpense(pm, amount);
          } catch (_) {}
          final catName =
              CustomCategoryRegistry.displayName(categoryId, ctx.lang);
          return 'OK: added expense ${formatMoney(amount)} in $catName'
              '${note.isNotEmpty ? ' ($note)' : ''}.';
        },
      ),
      LlmToolDef(
        name: 'add_income',
        description:
            'Record money the user received (salary, gift, payment).',
        parameters: _obj({
          'amount': _num('Amount received in BDT (required)'),
          'source': _str('Where it came from, e.g. salary. Optional.'),
          'note': _str('Short note. Optional.'),
          'date': _str('Date as YYYY-MM-DD. Optional, defaults to today.'),
        }, const [
          'amount'
        ]),
        execute: (args, ctx) async {
          final amount = _asDouble(args['amount']);
          if (amount <= 0) return 'Error: amount must be positive.';
          final source = args['source']?.toString() ?? 'other';
          final note = args['note']?.toString() ?? '';
          final date = _parseDate(args['date']);
          await ctx.money.addIncome(Income(
            amount: amount,
            source: source,
            date: date,
            note: note,
          ));
          return 'OK: added income ${formatMoney(amount)}'
              '${note.isNotEmpty ? ' ($note)' : ''}.';
        },
      ),
      LlmToolDef(
        name: 'set_budget',
        description: 'Set a monthly spending limit for one category.',
        parameters: _obj({
          'category': _str('Category id or name (required)'),
          'limit': _num('Monthly limit in BDT (required)'),
          'month': _str(
              'Month as YYYY-MM. Optional, defaults to current month.'),
        }, const [
          'category',
          'limit'
        ]),
        execute: (args, ctx) async {
          final categoryId =
              resolveCategoryId(args['category']?.toString(), ctx.lang);
          final limit = _asDouble(args['limit']);
          if (limit <= 0) return 'Error: limit must be positive.';
          final month = (args['month']?.toString().trim().isNotEmpty == true)
              ? args['month'].toString().trim()
              : _monthKeyOf(DateTime.now());
          await ctx.money.upsertBudget(Budget(
            categoryId: categoryId,
            monthKey: month,
            limitAmount: limit,
          ));
          final catName =
              CustomCategoryRegistry.displayName(categoryId, ctx.lang);
          return 'OK: budget for $catName set to ${formatMoney(limit)} for $month.';
        },
      ),
      LlmToolDef(
        name: 'set_monthly_budget',
        description: 'Set the total monthly spending limit.',
        parameters: _obj({
          'limit': _num('Total monthly limit in BDT (required)'),
          'month': _str(
              'Month as YYYY-MM. Optional, defaults to current month.'),
        }, const [
          'limit'
        ]),
        execute: (args, ctx) async {
          final limit = _asDouble(args['limit']);
          if (limit <= 0) return 'Error: limit must be positive.';
          final month = (args['month']?.toString().trim().isNotEmpty == true)
              ? args['month'].toString().trim()
              : _monthKeyOf(DateTime.now());
          await ctx.money.setMonthlyBudget(month, limit);
          return 'OK: total monthly budget set to ${formatMoney(limit)} for $month.';
        },
      ),
      LlmToolDef(
        name: 'delete_last_expense',
        description:
            'Delete the most recently added expense. Only use when the user explicitly asks to delete/remove it.',
        parameters: _obj({}, const []),
        execute: (args, ctx) async {
          final all = ctx.expenses.expenses;
          if (all.isEmpty) return 'Error: no expenses to delete.';
          final last = all.first;
          await ctx.expenses.remove(last.id!);
          return 'OK: deleted the last expense '
              '(${formatMoney(last.bdtAmount ?? last.amount)}).';
        },
      ),
      LlmToolDef(
        name: 'get_spending_summary',
        description:
            'Get spending totals for a period, with per-category breakdown. Use to answer "how much did I spend" questions.',
        parameters: _obj({
          'period': _str(
              'today, week, month, or a month as YYYY-MM (required).',
              enumValues: const ['today', 'week', 'month']),
        }, const [
          'period'
        ]),
        execute: (args, ctx) async {
          final period = args['period']?.toString() ?? 'month';
          final now = DateTime.now();
          double total = 0;
          Map<String, double> byCat = {};
          String label = period;
          if (period == 'today') {
            total = ctx.expenses.totalOn(now);
            byCat = ctx.expenses.totalsByCategoryRange(
                DateTime(now.year, now.month, now.day),
                DateTime(now.year, now.month, now.day, 23, 59, 59));
          } else if (period == 'week') {
            total = ctx.expenses.totalThisWeek();
          } else if (period == 'month') {
            total = ctx.expenses.totalThisMonth();
            byCat = ctx.expenses.totalsByCategory(now);
          } else {
            final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(period);
            if (m == null) {
              return 'Error: period must be today, week, month, or YYYY-MM.';
            }
            final y = int.parse(m.group(1)!);
            final mo = int.parse(m.group(2)!);
            final monthDate = DateTime(y, mo);
            byCat = ctx.expenses.totalsByCategory(monthDate);
            total = byCat.values.fold(0.0, (a, b) => a + b);
          }
          final buf = StringBuffer('Spending for $label: total '
              '${formatMoney(total)}.');
          if (byCat.isNotEmpty) {
            buf.write(' By category: ');
            final parts = byCat.entries
                .map((e) =>
                    '${CustomCategoryRegistry.displayName(e.key, ctx.lang)} ${formatMoney(e.value)}')
                .join(', ');
            buf.write(parts);
            buf.write('.');
          }
          return buf.toString();
        },
      ),
      LlmToolDef(
        name: 'get_wallet_balances',
        description:
            'Get all wallet balances (cash, mobile banking, card, bank, lent out) and the grand total.',
        parameters: _obj({}, const []),
        execute: (args, ctx) async {
          final w = ctx.wallets;
          return 'Wallets — hand cash ${formatMoney(w.cash)}, '
              'bKash ${formatMoney(w.walletOf('bkash'))}, '
              'Nagad ${formatMoney(w.walletOf('nagad'))}, '
              'Rocket ${formatMoney(w.walletOf('rocket'))}, '
              'Upay ${formatMoney(w.walletOf('upay'))}, '
              'card ${formatMoney(w.walletOf('card'))}, '
              'bank ${formatMoney(w.walletOf('bank'))}, '
              'lent out ${formatMoney(w.lentOut)}. '
              'Grand total ${formatMoney(w.total)}.';
        },
      ),
      LlmToolDef(
        name: 'set_wallet_balance',
        description: 'Set a wallet balance directly.',
        parameters: _obj({
          'wallet': _str('Which wallet (required).',
              enumValues: const [
                'cash',
                'bkash',
                'nagad',
                'rocket',
                'upay',
                'card',
                'bank'
              ]),
          'amount': _num('New balance in BDT (required)'),
        }, const [
          'wallet',
          'amount'
        ]),
        execute: (args, ctx) async {
          final wallet = args['wallet']?.toString() ?? '';
          final amount = _asDouble(args['amount']);
          if (amount < 0) return 'Error: amount cannot be negative.';
          if (wallet == 'cash') {
            await ctx.wallets.setCash(amount);
          } else {
            await ctx.wallets.setWallet(wallet, amount);
          }
          return 'OK: $wallet balance set to ${formatMoney(amount)}.';
        },
      ),
    ];

// ---------------------------------------------------------------------------
// Category name → id for prompt building is in categoryListForPrompt above.
// ---------------------------------------------------------------------------
