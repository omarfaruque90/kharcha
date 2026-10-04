import 'package:flutter/material.dart';

import 'package:kharcha/widgets/motion.dart';

/// Package AX: pure-black AMOLED theme.
///
/// Mirrors the dark branch of `_buildTheme`/`_brandScheme` in main.dart,
/// but every surface is pure black (#000000) instead of deep green —
/// the pixels stay off on AMOLED screens. Accent coloring works exactly
/// like the dark theme: the [accent] color (Package AF accent variants)
/// drives primary/filled-button/focused-input/selected-chip colors.
ThemeData buildAmoledTheme(Color accent) {
  const deepGreenDark = Color(0xFF072A1F); // kDeepGreenDark in main.dart
  // Text/icon color on top of the accent: dark green on light accents
  // (gold), white on saturated ones. Matches the original gold behavior.
  final onAccent =
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : deepGreenDark;
  final scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: onAccent,
    secondary: const Color(0xFF10B981), // kEmerald
    surface: Colors.black,
    onSurface: Colors.white,
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: Colors.black,
    surfaceContainer: Colors.black,
    surfaceContainerHigh: Colors.black,
    surfaceContainerHighest: Colors.black,
    surfaceDim: Colors.black,
    surfaceBright: const Color(0xFF1A1A1A),
    outlineVariant: Colors.white.withValues(alpha: 0.12),
  );
  const accentText = Color(0xFFF0D878); // default accent light tint (gold)
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // Pure black surfaces everywhere.
    scaffoldBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    cardColor: Colors.black,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FastPageTransitionsBuilder(),
        TargetPlatform.iOS: FastPageTransitionsBuilder(),
      },
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF1C1C1E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Color(0xFF000000),
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: Colors.white,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      side: BorderSide(color: accent.withValues(alpha: 0.45)),
      selectedColor: accent,
      checkmarkColor: onAccent,
      // Unselected chip text: explicit white on the black background.
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      // Selected chip text sits on the accent background.
      secondaryLabelStyle: TextStyle(
        color: onAccent,
        fontWeight: FontWeight.bold,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        disabledBackgroundColor: accent.withValues(alpha: 0.35),
        disabledForegroundColor: onAccent.withValues(alpha: 0.6),
        textStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: accent.withValues(alpha: 0.65)),
        foregroundColor: accentText,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2C2C2E),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      floatingLabelStyle: const TextStyle(
        color: accentText,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: const TextStyle(color: Color(0xFF98989F)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.black,
      indicatorColor: accent.withValues(alpha: 0.28),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: accent.withValues(alpha: 0.25),
      thickness: 1,
    ),
  );
}
