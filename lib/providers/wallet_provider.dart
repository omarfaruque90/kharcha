import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';

/// Where the user's money lives. Balances are stored as a JSON map in
/// settings ('wallet_balances'). Lent-out money is NOT stored here — it is
/// computed live from unsettled 'lent' debts.
class WalletProvider extends ChangeNotifier {
  static const String handCash = 'hand_cash';
  static const String mobileBanking = 'mobile_banking';
  static const String card = 'card';
  static const String otherBank = 'other_bank';

  static const List<String> keys = [
    handCash,
    mobileBanking,
    card,
    otherBank,
  ];

  final Map<String, double> _balances = {
    handCash: 0,
    mobileBanking: 0,
    card: 0,
    otherBank: 0,
  };

  double lentOut = 0;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  double balanceOf(String key) => _balances[key] ?? 0;

  /// Sum of the 4 wallets (excludes lent-out).
  double get walletsTotal =>
      _balances.values.fold(0.0, (a, b) => a + b);

  /// Everything the user owns: wallets + money lent out.
  double get grandTotal => walletsTotal + lentOut;

  Future<void> load() async {
    try {
      final raw = await DatabaseHelper.instance.getSetting('wallet_balances');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final k in keys) {
          final v = map[k];
          if (v is num) _balances[k] = v.toDouble();
        }
      }
    } catch (_) {
      // Corrupt JSON: keep zeros, never crash startup.
    }
    await refreshLentOut();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setBalance(String key, double amount) async {
    if (!keys.contains(key)) return;
    _balances[key] = amount;
    try {
      await DatabaseHelper.instance
          .setSetting('wallet_balances', jsonEncode(_balances));
    } catch (_) {}
    notifyListeners();
  }

  /// Recomputes lent-out from unsettled 'lent' debts.
  Future<void> refreshLentOut() async {
    try {
      final debts = await DatabaseHelper.instance.getDebts();
      lentOut = debts
          .where((d) => d.kind == 'lent' && !d.settled)
          .fold(0.0, (sum, d) => sum + d.amount);
    } catch (_) {
      // keep previous value
    }
    notifyListeners();
  }
}
