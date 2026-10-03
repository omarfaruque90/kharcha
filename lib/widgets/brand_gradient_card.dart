import 'package:flutter/material.dart';

import '../main.dart';

/// Header card with a subtle emerald-tinted gradient — used for the balance
/// card on home and the income total header. Readable in both themes.
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kDeepGreen.withValues(alpha: dark ? 0.55 : 0.30),
            kDeepGreen.withValues(alpha: dark ? 0.35 : 0.18),
            kGold.withValues(alpha: dark ? 0.30 : 0.22),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
