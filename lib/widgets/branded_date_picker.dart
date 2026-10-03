import 'package:flutter/material.dart';

import '../main.dart';

/// Date picker wrapped in the Kharcha brand: deep green header with
/// gold accents in both themes so the text stays readable.
Future<DateTime?> showBrandedDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  Locale? locale,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    locale: locale,
    builder: (dialogContext, child) {
      final base = Theme.of(dialogContext);
      final dark = base.brightness == Brightness.dark;
      return Theme(
        data: base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: dark ? kGold : kDeepGreen,
            onPrimary: dark ? kDeepGreenDark : Colors.white,
            secondary: kGoldDark,
            onSurface: dark ? Colors.white : kDeepGreenDark,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: dark ? kGold : kDeepGreen,
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}
