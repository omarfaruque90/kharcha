import 'package:flutter/material.dart';

import '../main.dart';

/// Date picker wrapped in the Kharcha brand: emerald header in light mode,
/// gold header in dark mode so the text stays readable in both themes.
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
            primary: dark ? kGold : kEmerald,
            onPrimary: dark ? kEmerald : Colors.white,
            secondary: kGold,
            onSurface: dark ? Colors.white : kEmerald,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: dark ? kGold : kEmerald,
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}
