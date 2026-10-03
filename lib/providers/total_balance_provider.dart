import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import '../models/cash_entry.dart';

/// Total balance across all money locations: hand cash + wallets
/// (bKash/Nagad/Rocket/Upay/card/bank) + lent-out debts.
///
/// Both the home hero card and the My Money card watch this, so they
/// always agree.
class TotalBalanceProvider extends ChangeNotifier {
  static const List<String> walletIds = [
    'bkash',
    'nagad',
    'rocket',
    'upay',
    'card',
    'bank',
  ];

  double _cash = 0;
  Map<String, double> _wallets = {for (final id in walletIds) id: 0};
  double _lentOut = 0;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  double get cash => _cash;
  double get lentOut => _lentOut;
  double walletOf(String id) => _wallets[id] ?? 0;

  double get walletsTotal =>
      _wallets.values.fold(0.0, (a, b) => a + b);

  /// Everything the user owns.
  double get total => _cash + walletsTotal + _lentOut;

  Future<void> load() async {
    try {
      final db = DatabaseHelper.instance;
      final results = await Future.wait([
        db.getCashBalance(),
        _readWallets(db),
        db.getDebts(),
      ]);
      _cash = results[0] as double;
      _wallets = results[1] as Map<String, double>;
      final debts = results[2] as List;
      _lentOut = debts
          .where((d) => d.kind == 'lent' && !d.settled)
          .fold<double>(0, (s, d) => s + (d.amount as num).toDouble());
    } catch (_) {
      // Keep previous values; never crash startup.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<Map<String, double>> _readWallets(
      DatabaseHelper db) async {
    final out = {for (final id in walletIds) id: 0.0};
    try {
      final raw = await db.getSetting('wallet_balances');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final id in walletIds) {
          final v = map[id];
          if (v is num) out[id] = v.toDouble();
        }
      } else {
        final old = await db.getSetting('bank_balance');
        final v = double.tryParse(old ?? '');
        if (v != null) out['bank'] = v;
      }
    } catch (_) {}
    return out;
  }

  Future<void> setWallet(String id, double amount) async {
    if (!walletIds.contains(id)) return;
    _wallets[id] = amount;
    notifyListeners();
    try {
      await DatabaseHelper.instance
          .setSetting('wallet_balances', jsonEncode(_wallets));
    } catch (_) {}
  }

  /// Sets hand cash via a ledger adjustment entry.
  Future<void> setCash(double amount) async {
    final diff = amount - _cash;
    if (diff.abs() < 0.005) return;
    try {
      await DatabaseHelper.instance.insertCashEntry(CashEntry(
        id: CashEntry.newId(),
        amount: diff.abs(),
        type: diff > 0 ? 'in' : 'out',
        note: 'adjust',
        date: DateTime.now(),
      ));
      _cash = await DatabaseHelper.instance.getCashBalance();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Maps an expense payment method to a wallet id.
  /// Returns 'cash' for hand cash, a wallet id, or null if unmapped.
  static String? walletForPayment(String pm) {
    if (pm == 'cash') return 'cash';
    if (pm == 'bkash') return 'bkash';
    if (pm.startsWith('mobile_banking:')) {
      switch (pm.split(':').last.toLowerCase()) {
        case 'bkash':
          return 'bkash';
        case 'nagad':
          return 'nagad';
        case 'rocket':
          return 'rocket';
        case 'upay':
          return 'upay';
      }
      return null;
    }
    if (pm == 'card') return 'card';
    if (pm == 'other' || pm.startsWith('other:')) return 'bank';
    return null;
  }

  /// Deducts an expense amount from the matching wallet.
  Future<void> deductForExpense(
      String paymentMethod, double amount) async {
    final w = walletForPayment(paymentMethod);
    if (w == null || amount <= 0) return;
    try {
      if (w == 'cash') {
        await DatabaseHelper.instance.insertCashEntry(CashEntry(
          id: CashEntry.newId(),
          amount: amount,
          type: 'out',
          note: 'expense',
          date: DateTime.now(),
        ));
        _cash = await DatabaseHelper.instance.getCashBalance();
      } else {
        _wallets[w] = (_wallets[w] ?? 0) - amount;
        await DatabaseHelper.instance
            .setSetting('wallet_balances', jsonEncode(_wallets));
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Refunds a deleted expense amount back to the matching wallet.
  Future<void> refundForExpense(
      String paymentMethod, double amount) async {
    final w = walletForPayment(paymentMethod);
    if (w == null || amount <= 0) return;
    try {
      if (w == 'cash') {
        await DatabaseHelper.instance.insertCashEntry(CashEntry(
          id: CashEntry.newId(),
          amount: amount,
          type: 'in',
          note: 'refund',
          date: DateTime.now(),
        ));
        _cash = await DatabaseHelper.instance.getCashBalance();
      } else {
        _wallets[w] = (_wallets[w] ?? 0) + amount;
        await DatabaseHelper.instance
            .setSetting('wallet_balances', jsonEncode(_wallets));
      }
    } catch (_) {}
    notifyListeners();
  }
}
