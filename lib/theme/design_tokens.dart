import 'package:flutter/material.dart';

/// Khorcha design tokens — the single source of truth for spacing, radii
/// and type across the app. Everything new should reach for these before
/// inventing a one-off value.
///
/// GOLD USAGE RULES (brand: deep green + gold + gold ৳ logo):
/// - Gold (kGold) is the brand accent. Use it for:
///   * Primary CTAs (gold filled buttons — wired in the app theme),
///   * Selected states (chips, nav indicator, toggles),
///   * Key money numbers (hero balance, headline amounts).
/// - kGoldLight is for gold text sitting on deep-green surfaces.
/// - NEVER use gold for: body text, long paragraphs, error/success
///   semantics (use colorScheme.error / emerald instead), or large
///   light-mode backgrounds (fails contrast and looks cheap).
/// Elevate the brand, don't replace it: deep green stays the canvas,
/// gold stays the jewelry.

/// Spacing scale. Prefer these steps over arbitrary EdgeInsets.
class KSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double s = 12;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

/// Corner radii. Cards and sheets share the 20dp premium radius.
class KRadius {
  static const double card = 20;
  static const double sheet = 20;
  static const double button = 14;
  static const double chip = 12;
  static const double tile = 14;
}

/// Type scale, derived from Theme.of so it stays dark/light aware.
/// Sizes: display 32/800, headline 20/700, title 16/700, body 14, label 12.
class KType {
  static TextStyle _s(
    BuildContext context,
    TextStyle? base,
    double size,
    FontWeight weight, [
    double letterSpacing = 0,
  ]) =>
      (base ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
      );

  /// Hero numbers and splash-style headlines.
  static TextStyle display(BuildContext context) => _s(
        context,
        Theme.of(context).textTheme.headlineLarge,
        32,
        FontWeight.w800,
        0.3,
      );

  /// Screen/section titles.
  static TextStyle headline(BuildContext context) => _s(
        context,
        Theme.of(context).textTheme.titleLarge,
        20,
        FontWeight.w700,
        0.3,
      );

  /// Card titles, list headers.
  static TextStyle title(BuildContext context) => _s(
        context,
        Theme.of(context).textTheme.titleMedium,
        16,
        FontWeight.w700,
        0.2,
      );

  /// Default reading text.
  static TextStyle body(BuildContext context) => _s(
        context,
        Theme.of(context).textTheme.bodyMedium,
        14,
        FontWeight.w400,
      );

  /// Captions, overlines, chip labels.
  static TextStyle label(BuildContext context) => _s(
        context,
        Theme.of(context).textTheme.labelSmall,
        12,
        FontWeight.w600,
        0.8,
      );
}

/// Section headers: icon in a tinted rounded container + bold title,
/// optional trailing widget (e.g. "see all").
class KSection {
  static Widget header(
    BuildContext context, {
    required String title,
    IconData? icon,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: KSpacing.s),
        ],
        Expanded(
          child: Text(title, style: KType.title(context)),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}
