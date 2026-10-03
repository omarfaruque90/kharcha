import 'package:flutter/material.dart';

import '../main.dart';

/// Premium hero card: rich deep-green gradient with a gold border glow and
/// a subtle top sheen — the glossy fintech look matching the 3D logo.
/// Used for the balance card on home and the income total header.
/// White/gold content reads well in both themes.
class BrandGradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const BrandGradientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [kDeepGreenCard, kDeepGreen, kDeepGreenDark]
              : const [kDeepGreen, kDeepGreenDark, Color(0xFF052018)],
        ),
        border: Border.all(
          color: kGold.withValues(alpha: dark ? 0.4 : 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: dark ? 0.14 : 0.22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Glossy top sheen, like the 3D logo.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 110,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.08 : 0.14),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
