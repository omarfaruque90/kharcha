import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Multi-currency support (package V).
///
/// BDT is the base currency; every expense records the original [amount] and
/// [currency] plus a precomputed `bdt_amount`, so totals stay consistent even
/// when rates drift. Rates bundled here are fallback values — [refreshRates]
/// tries a no-key live fetch and caches the result, but never throws.
class CurrencyService {
  CurrencyService._();

  /// Fallback conversion rates to BDT (per 1 unit of the currency).
  static const Map<String, double> rates = {
    'BDT': 1.0,
    'USD': 117.0,
    'INR': 1.4,
    'EUR': 126.0,
  };

  static const Map<String, String> symbols = {
    'BDT': '৳',
    'USD': '\$',
    'INR': '₹',
    'EUR': '€',
  };

  /// Supported currency codes for the picker UI, in display order.
  static const List<String> supported = ['BDT', 'USD', 'INR', 'EUR'];

  static const _cacheKey = 'currency_rates';
  static const _cacheAtKey = 'currency_rates_at';

  /// Converts [amount] in [currency] to BDT using the live-cached rate when
  /// available, falling back to the bundled [rates]. Never throws.
  static double toBdt(double amount, String currency) {
    return amount * (_liveRate(currency) ?? rates[currency] ?? 1.0);
  }

  static final Map<String, double> _liveCache = {};

  static double? _liveRate(String currency) {
    final r = _liveCache[currency];
    return (r != null && r > 0) ? r : null;
  }

  /// Loads the last cached rates into memory (call at app startup).
  /// Never throws.
  static Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _liveCache
          ..clear()
          ..addEntries(decoded.entries.map((e) => MapEntry(
                e.key.toString(),
                (e.value as num?)?.toDouble() ?? 0.0,
              )));
      }
    } catch (_) {
      // Keep bundled rates.
    }
  }

  /// Best-effort refresh of BDT rates from a no-key public API
  /// (https://open.er-api.com/v6/latest/BDT). Caches the fetched map in
  /// SharedPreferences. On any failure the bundled rates stay in effect.
  /// Never throws.
  static Future<void> refreshRates() async {
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/BDT'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['result'] != 'success') return;
      final rawRates = decoded['rates'];
      if (rawRates is! Map) return;
      // er-api returns units per 1 BDT; invert to "BDT per 1 unit".
      final next = <String, double>{};
      for (final code in supported) {
        if (code == 'BDT') continue;
        final perBdt = (rawRates[code] as num?)?.toDouble();
        if (perBdt != null && perBdt > 0) {
          next[code] = 1 / perBdt;
        }
      }
      if (next.isEmpty) return;
      _liveCache
        ..clear()
        ..addAll(next);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(next));
      await prefs.setInt(
          _cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Best effort — keep the bundled (or previously cached) rates.
    }
  }
}
