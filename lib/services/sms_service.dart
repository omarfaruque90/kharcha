import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:readsms/readsms.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';

/// Result of parsing a transaction SMS with enough confidence to suggest
/// adding it as an expense.
class SmsParseResult {
  final double amount;
  final String merchant;
  final String paymentMethod;

  const SmsParseResult({
    required this.amount,
    required this.merchant,
    required this.paymentMethod,
  });
}

/// Parses bKash / bank debit SMS messages.
///
/// bKash examples:
///   "Payment Tk 250.00 to 017XXXXXXXX successful. TrxID 9HXK2L ..."
///   "Send Money Tk 1,000.00 to 018XXXXXXXX successful. ..."
///   "Cash Out Tk 5,000.00 from Agent 019XXXXXXXX successful. ..."
/// Bank example:
///   "Your A/C XXXX1234 has been debited with BDT 2,500.00 ..."
///
/// Only *outgoing* money (payment / send money / cash out / debited) is
/// matched — incoming money ("received", "credited") is ignored.
class SmsParser {
  static final RegExp _amountRe =
      RegExp(r'(?:tk|bdt)\.?\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
  static final RegExp _bkashToRe = RegExp(r'to\s+(01\d{9})');
  static final RegExp _bkashAgentRe =
      RegExp(r'from\s+agent\s+([0-9a-zA-Z\- ]{3,20})', caseSensitive: false);
  static final RegExp _bankInfoRe =
      RegExp(r'(?:info|narration|at)\s*[:\-]?\s*(.{3,40})', caseSensitive: false);

  static SmsParseResult? parse(String sender, String body) {
    final lower = body.toLowerCase();
    // Skip incoming money and OTP-ish messages.
    if (lower.contains('received') ||
        lower.contains('credited') ||
        lower.contains('cash in')) {
      return null;
    }
    const debitWords = [
      'payment',
      'send money',
      'cash out',
      'debited',
      'debit ',
      'paid',
      'withdraw',
    ];
    final isDebit = debitWords.any(lower.contains);
    if (!isDebit) return null;

    final isBkash = sender.toLowerCase().contains('bkash') ||
        lower.contains('bkash') ||
        lower.contains('trxid');
    // Confidence: bKash marker present, or an explicit "debited".
    if (!isBkash &&
        !lower.contains('debited') &&
        !lower.contains('cash out')) {
      return null;
    }

    final amountMatch = _amountRe.firstMatch(body);
    if (amountMatch == null) return null;
    final amount =
        double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    String merchant;
    String method;
    if (isBkash) {
      method = 'bkash';
      final to = _bkashToRe.firstMatch(body);
      final agent = _bkashAgentRe.firstMatch(body);
      if (to != null) {
        merchant = 'bKash → ${to.group(1)}';
      } else if (agent != null) {
        merchant = 'bKash Agent ${agent.group(1)!.trim()}';
      } else {
        merchant = 'bKash';
      }
    } else {
      method = 'other';
      final info = _bankInfoRe.firstMatch(body);
      merchant = info != null ? info.group(1)!.trim() : sender;
    }
    return SmsParseResult(
      amount: amount,
      merchant: merchant,
      paymentMethod: method,
    );
  }
}

/// Listens for incoming transaction SMS and offers to add confident matches
/// as expenses. Everything is opt-in: a Bangla rationale dialog precedes the
/// runtime permission request, and a denied permission leaves the feature
/// silently off.
class SmsService {
  SmsService._();
  static final SmsService instance = SmsService._();

  final Readsms _reader = Readsms();
  GlobalKey<NavigatorState>? _navKey;
  StreamSubscription<SMS>? _sub;
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
      _reader.read();
      _sub = _reader.smsStream.listen(_onSms, onError: (_) {});
    } catch (_) {
      _started = false;
    }
  }

  Future<void> _onSms(SMS sms) async {
    try {
      final fingerprint =
          '${sms.sender}|${sms.body}|${sms.timeReceived.millisecondsSinceEpoch}';
      if (!_seen.add(fingerprint)) return; // de-dupe double delivery
      if (_seen.length > 200) _seen.clear();

      final parsed = SmsParser.parse(sms.sender, sms.body);
      if (parsed == null) return;
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
      // Refresh the home list when the provider is reachable.
      final ctx2 = _navKey?.currentContext;
      if (ctx2 != null) {
        try {
          await Provider.of<ExpenseProvider>(ctx2, listen: false).load();
        } catch (_) {}
        try {
          final messenger = ScaffoldMessenger.maybeOf(ctx2);
          messenger?.showSnackBar(
            SnackBar(content: Text(tr(ctx2, 'sms_added'))),
          );
        } catch (_) {}
      }
    } catch (_) {
      // A bad SMS must never crash the app.
    }
  }

  void dispose() {
    _sub?.cancel();
    _reader.dispose();
    _started = false;
  }
}
