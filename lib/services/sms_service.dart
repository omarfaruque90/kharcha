import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:receive_sms/receive_sms.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Result of parsing a transaction SMS with enough confidence to add it as
/// an expense (auto mode) or suggest it (manual mode).
class SmsParseResult {
  final double amount;
  final String merchant;
  final String paymentMethod;

  /// Guessed category id ('food', 'transport', ..., 'others').
  final String categoryId;

  /// Display brand for notifications: 'bKash', 'Nagad', 'Rocket', 'Bank'.
  final String brand;

  /// Transaction/reference id when the SMS carries one, else null.
  final String? trxId;

  /// SMS timestamp when parseable, otherwise [DateTime.now].
  final DateTime date;

  const SmsParseResult({
    required this.amount,
    required this.merchant,
    required this.paymentMethod,
    this.categoryId = 'others',
    this.brand = 'bKash',
    this.trxId,
    required this.date,
  });
}

/// Parses bKash / Nagad / Rocket / bank debit SMS messages.
///
/// bKash examples:
///   "Payment Tk 250.00 to 017XXXXXXXX successful. TrxID 9HXK2L ..."
///   "Send Money Tk 1,000.00 to 018XXXXXXXX successful. ..."
///   "Cash Out Tk 5,000.00 from Agent 019XXXXXXXX successful. ..."
/// Nagad example:
///   "Cash Out Tk 2,000.00 to 01XXXXXXXXX successful. TxnID NGD123 ..."
/// Rocket (DBBL) example:
///   "Rocket A/C XXXX debited Tk 1,500.00. Ref 7RKT9 ..."
/// Bank example:
///   "Your A/C XXXX1234 has been debited with BDT 2,500.00 ..."
///   "BDT 1,000.00 withdrawn from ATM ... at Gulshan ..."
///
/// Only *outgoing* money (payment / send money / cash out / debited /
/// withdrawn) is matched — incoming money ("received", "credited",
/// "cash in") and OTP messages are ignored.
class SmsParser {
  static final RegExp _amountRe = RegExp(
    r'(?:tk|bdt|৳)\.?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _toRe = RegExp(
    r'\bto\s+([^\n.,;]{2,40})',
    caseSensitive: false,
  );
  static final RegExp _bkashAgentRe =
      RegExp(r'from\s+agent\s+([0-9a-zA-Z\- ]{3,20})', caseSensitive: false);
  static final RegExp _trxRe = RegExp(
    r'(?:trx\s?id|transaction\s?id|txn\s?id|ref(?:erence)?(?:\s?no)?)\s*[:\-]?\s*([A-Za-z0-9\-]{6,24})',
    caseSensitive: false,
  );
  static final RegExp _bankAtRe =
      RegExp(r'\bat\s+([A-Za-z0-9 .&\-]{3,40})', caseSensitive: false);
  static final RegExp _bankInfoRe = RegExp(
    r'(?:info|narration)\s*[:\-]?\s*(.{3,40})',
    caseSensitive: false,
  );

  /// Source tags used for payment-method mapping and notification branding.
  static const String srcBkash = 'bkash';
  static const String srcNagad = 'nagad';
  static const String srcRocket = 'rocket';
  static const String srcBank = 'bank';

  static SmsParseResult? parse(String sender, String body,
      [String timestamp = '']) {
    final lower = body.toLowerCase();
    final senderLower = sender.toLowerCase();
    // Skip incoming money and OTP-ish messages.
    if (lower.contains('received') ||
        lower.contains('credited') ||
        lower.contains('cash in') ||
        lower.contains('otp') ||
        lower.contains('verification code')) {
      return null;
    }
    const debitWords = [
      'payment',
      'send money',
      'cash out',
      'debited',
      'debit ',
      'paid',
      'withdrawn',
      'withdraw ',
      'purchase',
      'spent',
    ];
    final isDebit = debitWords.any(lower.contains);
    if (!isDebit) return null;

    bool has(String s) => senderLower.contains(s) || lower.contains(s);
    String source;
    if (has('bkash') || RegExp(r'trx\s?id').hasMatch(lower)) {
      source = srcBkash;
    } else if (has('nagad')) {
      source = srcNagad;
    } else if (has('rocket') || has('dbbl')) {
      source = srcRocket;
    } else if (lower.contains('debited') ||
        lower.contains('a/c') ||
        lower.contains('account') ||
        has('bdt') ||
        has('card')) {
      source = srcBank;
    } else {
      return null; // Unrecognized source: not confident enough.
    }

    final amountMatch = _amountRe.firstMatch(body);
    if (amountMatch == null) return null;
    final amount =
        double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    final trxMatch = _trxRe.firstMatch(body);
    final trxId = trxMatch?.group(1)?.trim();

    String merchant;
    String method;
    String brand;
    switch (source) {
      case srcBkash:
        brand = 'bKash';
        method = 'mobile_banking:bKash';
        merchant = _merchantFromTo(body) ?? 'bKash';
        break;
      case srcNagad:
        brand = 'Nagad';
        method = 'mobile_banking:Nagad';
        merchant = _merchantFromTo(body) ?? 'Nagad';
        break;
      case srcRocket:
        brand = 'Rocket';
        method = 'mobile_banking:Rocket';
        merchant = _merchantFromTo(body) ?? 'Rocket';
        break;
      default:
        brand = 'Bank';
        method = 'card';
        final at = _bankAtRe.firstMatch(body);
        final info = _bankInfoRe.firstMatch(body);
        merchant = at?.group(1)?.trim() ??
            info?.group(1)?.trim() ??
            (sender.isNotEmpty ? sender : 'Bank');
    }

    final categoryId = guessCategory('$merchant $body');
    return SmsParseResult(
      amount: amount,
      merchant: merchant,
      paymentMethod: method,
      categoryId: categoryId,
      brand: brand,
      trxId: trxId,
      date: _smsDate(timestamp),
    );
  }

  /// "Payment Tk 120.00 to Shabbir Hossain successful" → "Shabbir Hossain".
  /// Falls back to the raw recipient (phone number) when no name is present.
  static String? _merchantFromTo(String body) {
    final to = _toRe.firstMatch(body);
    if (to != null) {
      var name = to.group(1)!.trim();
      // Strip trailing status words the broad pattern may have captured.
      name = name
          .replaceFirst(RegExp(r'\s+successful\.?$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s+completed\.?$', caseSensitive: false), '')
          .trim();
      if (name.length >= 2) return name;
    }
    final agent = _bkashAgentRe.firstMatch(body);
    if (agent != null) return 'Agent ${agent.group(1)!.trim()}';
    return null;
  }

  /// Guesses a category id from merchant/name keywords. Defaults to 'others'.
  static String guessCategory(String text) {
    final l = ' ${text.toLowerCase()} ';
    bool any(List<String> kws) => kws.any(l.contains);
    if (any(const [
      'restaurant', 'food', 'kacchi', 'pizza', 'burger', 'cafe', 'coffee',
      'tea stall', 'cha ', 'hotel', 'biryani', 'bakery', 'sweet', 'misti',
      'chotpoti', 'fuchka', 'kabab', 'khabar', 'dining', 'canteen', 'kitchen',
    ])) {
      return 'food';
    }
    if (any(const [
      'uber', 'pathao', 'bus', 'cng', 'rickshaw', 'taxi', 'train', 'launch',
      'flight', 'biman', 'fuel', 'petrol', 'octane', 'parking', 'toll',
      'metro', 'ferry',
    ])) {
      return 'transport';
    }
    if (any(const [
      'grameenphone', 'grameen phone', 'robi', 'banglalink', 'teletalk',
      'airtel', 'recharge', 'topup', 'top-up', 'top up', 'broadband',
      'internet bill', 'desco', 'dpdc', 'wasa', 'titas', 'electricity',
      'bill payment',
    ])) {
      return 'bills';
    }
    if (any(const [
      'pharmacy', 'hospital', 'doctor', 'clinic', 'medicine', 'diagnostic',
      'dentist', 'pharma',
    ])) {
      return 'health';
    }
    if (any(const [
      'cinema', 'movie', 'netflix', 'spotify', 'game', 'gaming', 'concert',
      'amusement', 'resort', 'tour', 'travel', 'theme park',
    ])) {
      return 'entertainment';
    }
    if (any(const [
      'school', 'college', 'university', 'course', 'book', 'tuition', 'exam',
      'coaching', 'admission',
    ])) {
      return 'education';
    }
    if (any(const [
      'bazar', 'market', 'shop', 'store', 'mall', 'daraz', 'chaldal',
      'grocery', 'super shop', 'supershop', 'tailor', 'salon', 'boutique',
      'electronics',
    ])) {
      return 'shopping';
    }
    return 'others';
  }

  /// Parses the receive_sms timestamp (epoch millis string or ISO date).
  /// Falls back to now when unparseable.
  static DateTime _smsDate(String timestamp) {
    final millis = int.tryParse(timestamp.trim());
    if (millis != null) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      } catch (_) {}
    }
    final dt = DateTime.tryParse(timestamp.trim());
    if (dt != null) return dt;
    return DateTime.now();
  }
}

/// Listens for incoming transaction SMS and either auto-adds confident
/// matches as expenses (setting 'auto_sms' == '1') or offers the old manual
/// confirm dialog ('auto_sms' == '0').
///
/// Everything is opt-in: a Bangla rationale dialog precedes the runtime
/// permission request, and a denied permission leaves the feature silently
/// off. Auto-add is ON by default once SMS permission is granted.
class SmsService {
  SmsService._();
  static final SmsService instance = SmsService._();

  /// Settings key for the auto-add toggle. '1' = auto-add, '0' = manual
  /// confirm dialog. Absent = default ON when SMS permission is granted.
  static const String autoSmsKey = 'auto_sms';

  /// Settings key holding the JSON list of seen transaction ids (cap 200).
  static const String seenTrxKey = 'sms_seen_trx';

  /// Undo payload prefix. The full payload is '<prefix><expenseId>',
  /// e.g. 'sms_undo_3f9a1c2e-...'. See the WIRING NOTE below.
  static const String undoPayloadPrefix = 'sms_undo_';

  /// Builds the undo payload for an auto-added expense.
  static String undoPayloadFor(String expenseId) =>
      '$undoPayloadPrefix$expenseId';

  final ReceiveSms _receiver = ReceiveSms();
  GlobalKey<NavigatorState>? _navKey;
  StreamSubscription<SmsMessage>? _sub;
  bool _started = false;
  final Set<String> _seen = <String>{};

  void attachNavigator(GlobalKey<NavigatorState> key) {
    _navKey = key;
  }

  /// Shows the rationale dialog, requests the SMS permission, and starts
  /// listening. No-op when the permission was already granted and the
  /// listener is running, or when there is no navigator context yet.
  Future<void> maybeStart() async {
    if (_started) return;
    final ctx = _navKey?.currentContext;
    if (ctx == null) return;
    try {
      if (await Permission.sms.isGranted) {
        _startListening();
        return;
      }
      if (!ctx.mounted) return;
      final allow = await showDialog<bool>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          title: Text(tr(dctx, 'sms_rationale_title')),
          content: Text(tr(dctx, 'sms_rationale_msg')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: Text(tr(dctx, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child: Text(tr(dctx, 'sms_allow')),
            ),
          ],
        ),
      );
      if (allow != true) return;
      final status = await Permission.sms.request();
      if (status.isGranted) _startListening();
      // Denied / permanently denied: feature stays off silently.
    } catch (_) {
      // Never crash startup over SMS.
    }
  }

  void _startListening() {
    if (_started) return;
    _started = true;
    try {
      _sub = _receiver.incomingSmsStream.listen(_onSms, onError: (_) {});
    } catch (_) {
      _started = false;
    }
  }

  /// Reads the auto-add toggle. Default ON when SMS permission is granted
  /// (and persists that default); explicit '1'/'0' in settings wins.
  Future<bool> _isAutoEnabled() async {
    try {
      final v = await DatabaseHelper.instance.getSetting(autoSmsKey);
      if (v != null) return v == '1';
      if (await Permission.sms.isGranted) {
        await DatabaseHelper.instance.setSetting(autoSmsKey, '1');
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Dedupe against the persisted seen-transaction list (cap 200).
  /// Returns true when this transaction was already handled (skip it).
  /// Always records the key so a crash mid-flow can't double-add.
  Future<bool> _alreadySeen(String key) async {
    try {
      final db = DatabaseHelper.instance;
      final raw = await db.getSetting(seenTrxKey);
      List<String> list = [];
      if (raw != null && raw.isNotEmpty) {
        try {
          list = List<String>.from(jsonDecode(raw) as List);
        } catch (_) {}
      }
      if (list.contains(key)) return true;
      list.insert(0, key);
      if (list.length > 200) list = list.sublist(0, 200);
      await db.setSetting(seenTrxKey, jsonEncode(list));
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onSms(SmsMessage sms) async {
    try {
      final sender = sms.address;
      final body = sms.body;
      final fingerprint = '$sender|$body|${sms.timestamp}';
      if (!_seen.add(fingerprint)) return; // de-dupe double delivery
      if (_seen.length > 200) _seen.clear();

      final parsed = SmsParser.parse(sender, body, sms.timestamp);
      if (parsed == null) return;

      if (await _isAutoEnabled()) {
        await _autoAdd(parsed, sender: sender, body: body);
        return;
      }
      await _manualConfirm(parsed);
    } catch (_) {
      // A bad SMS must never crash the app.
    }
  }

  /// Full-auto path: dedupe, insert the expense, notify with undo payload.
  Future<void> _autoAdd(SmsParseResult parsed,
      {required String sender, required String body}) async {
    // Dedupe key: real trxID when present, else a hash of sender+amount+date.
    final key = (parsed.trxId != null && parsed.trxId!.isNotEmpty)
        ? 'trx:${parsed.trxId}'
        : 'h:${'$sender|${parsed.amount}|${parsed.date.millisecondsSinceEpoch}'.hashCode}';
    if (await _alreadySeen(key)) return;

    final snippet = body.length > 60 ? body.substring(0, 60) : body;
    final expenseId = await DatabaseHelper.instance.insertExpense(
      Expense(
        amount: parsed.amount,
        categoryId: parsed.categoryId,
        date: parsed.date,
        note: 'SMS: $snippet',
        paymentMethod: parsed.paymentMethod,
        currency: 'BDT',
        bdtAmount: parsed.amount,
      ),
    );

    await _refreshProvider();

    // Undo payload for the coordinator: 'sms_undo_<expenseId>' (see
    // SmsService.undoPayloadPrefix and the WIRING NOTE on this class).
    // NotificationService.showNow / NotificationCenter.push currently take
    // no payload parameter, so the payload plumbing must be added by the
    // coordinator; the undo target is the expense row id returned above.
    final lang = await DatabaseHelper.instance.getSetting('language') ?? 'bn';
    final amountStr = lang == 'bn'
        ? _banglaDigits(parsed.amount.toStringAsFixed(0))
        : parsed.amount.toStringAsFixed(0);
    // Intended tr keys (add to AppStrings; inline fallback until wired):
    //   'sms_auto_title' → en 'Expense auto-added' / bn 'খরচ স্বয়ংক্রিয়ভাবে যোগ হয়েছে'
    //   'sms_auto_body'  → en '{brand} ৳{amount} auto-added'
    //                      / bn '{brand} ৳{amount} স্বয়ংক্রিয়ভাবে যোগ হয়েছে'
    final title = lang == 'bn' ? 'খরচ স্বয়ংক্রিয়ভাবে যোগ হয়েছে' : 'Expense auto-added';
    final notifBody = lang == 'bn'
        ? '${parsed.brand} ৳$amountStr স্বয়ংক্রিয়ভাবে যোগ হয়েছে'
        : '${parsed.brand} ৳$amountStr auto-added';
    await NotificationService.showNow(title: title, body: notifBody);
    await NotificationCenter.push(
      title: title,
      body: notifBody,
      type: 'sms_auto',
      dedupeKey: 'sms:$expenseId',
    );
  }

  /// Manual path (auto_sms == '0'): the old confirm-dialog behavior.
  Future<void> _manualConfirm(SmsParseResult parsed) async {
    final ctx = _navKey?.currentContext;
    if (ctx == null) return;

    final message = tr(ctx, 'sms_confirm_msg')
        .replaceAll('{amount}', parsed.amount.toStringAsFixed(0))
        .replaceAll('{merchant}', parsed.merchant);
    final add = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'sms_confirm_title')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(tr(dctx, 'sms_ignore')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(tr(dctx, 'sms_add')),
          ),
        ],
      ),
    );
    if (add != true) return;

    await DatabaseHelper.instance.insertExpense(
      Expense(
        amount: parsed.amount,
        categoryId: 'others',
        date: DateTime.now(),
        note: parsed.merchant,
        paymentMethod: parsed.paymentMethod,
      ),
    );
    await _refreshProvider();
    // Confirm via snackbar.
    final ctx2 = _navKey?.currentContext;
    if (ctx2 != null && ctx2.mounted) {
      try {
        final messenger = ScaffoldMessenger.maybeOf(ctx2);
        messenger?.showSnackBar(
          SnackBar(content: Text(tr(ctx2, 'sms_added'))),
        );
      } catch (_) {}
    }
  }

  /// Refreshes the home list when the provider is reachable.
  Future<void> _refreshProvider() async {
    final ctx = _navKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    try {
      final expenses = Provider.of<ExpenseProvider>(ctx, listen: false);
      await expenses.load();
    } catch (_) {}
  }

  /// Deletes an auto-added expense (undo target). Called by the
  /// coordinator from the notification-tap handler when the payload starts
  /// with [undoPayloadPrefix]. Returns true when a row was removed.
  static Future<bool> undoAutoAdd(String expenseId) async {
    try {
      final count = await DatabaseHelper.instance.deleteExpense(expenseId);
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  /// Converts ASCII digits to Bengali digits for bn notification text.
  static String _banglaDigits(String s) {
    const bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      buf.write(c >= 0x30 && c <= 0x39 ? bn[c - 0x30] : s[i]);
    }
    return buf.toString();
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
