import 'package:flutter/material.dart';

import '../main.dart';

/// Date picker wrapped in the Kharcha brand: emerald header in both
/// themes so the text stays readable.
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
            primary: dark ? kEmerald : kEmeraldDark,
            onPrimary: Colors.white,
            secondary: kEmeraldDark,
            onSurface: dark ? Colors.white : kCharcoal,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: dark ? kEmerald : kEmeraldDark,
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}
