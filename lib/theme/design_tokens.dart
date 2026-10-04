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

/// iOS Human Interface Guidelines inspired palette.
/// Grouped-background style: gray system background, white cards,
/// borderless filled inputs. Brand gold stays the accent.
class KIOS {
  // Light mode
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightCard = Colors.white;
  static const Color lightInputFill = Color(0xFFE9E9EE);
  static const Color lightSeparator = Color(0x1F3C3C43); // ~12% separator
  static const Color lightSecondaryText = Color(0xFF8E8E93);

  // Dark mode
  static const Color darkBackground = Colors.black;
  static const Color darkCard = Color(0xFF1C1C1E);
  static const Color darkInputFill = Color(0xFF2C2C2E);
  static const Color darkSeparator = Color(0x1FE5E5EA);
  static const Color darkSecondaryText = Color(0xFF98989F);

  static const double cardRadius = 16;
  static const double inputRadius = 12;
  static const double buttonRadius = 12;

  /// Secondary (de-emphasized) text color, iOS system gray.
  static Color secondaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSecondaryText
          : lightSecondaryText;

  /// Hairline separator color for grouped rows.
  static Color separator(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSeparator
          : lightSeparator;

  /// iOS section title: 20px semibold, tight tracking, label color.
  static TextStyle sectionTitle(BuildContext context) => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// iOS grouped row label: 15px semibold, label color.
  static TextStyle rowLabel(BuildContext context) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// iOS-style card decoration: no elevation, clean fill.
  /// Use on top of the grouped background for the classic iOS look.
  static BoxDecoration card(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: dark ? darkCard : lightCard,
      borderRadius: BorderRadius.circular(cardRadius),
    );
  }

  /// iOS-style grouped section: white card containing divided rows.
  static Widget groupedSection(
    BuildContext context, {
    String? header,
    required List<Widget> children,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final List<Widget> rows = [];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(
          height: 1,
          indent: 52,
          color: dark ? darkSeparator : lightSeparator,
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
            child: Text(
              header.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: dark ? darkSecondaryText : lightSecondaryText,
                letterSpacing: 0.2,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: card(context),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ],
    );
  }
}
