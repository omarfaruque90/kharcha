import 'package:intl/intl.dart';

/// Formats an amount in BDT, e.g. ৳1,250.
String formatMoney(double amount) {
  final f = NumberFormat('#,##0.##', 'en_US');
  return '৳${f.format(amount)}';
}

/// Compact, chart-axis-friendly format, e.g. ৳2.5k.
String formatCompact(double value) {
  if (value >= 1000) {
    final k = value / 1000;
    final text =
        k.truncateToDouble() == k ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return '৳${text}k';
  }
  return '৳${value.toStringAsFixed(0)}';
}

/// Short month label in the given language code ('bn' or 'en').
String monthShort(DateTime month, String lang) {
  return DateFormat.MMM(lang == 'bn' ? 'bn' : 'en').format(month);
}

/// Long month label in the given language code ('bn' or 'en').
String monthLong(DateTime month, String lang) {
  return DateFormat.yMMMM(lang == 'bn' ? 'bn' : 'en').format(month);
}
