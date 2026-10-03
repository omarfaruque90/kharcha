import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import 'liquid_add_button.dart';

/// Gooey sliding-notch bottom nav, like the reference video:
/// a floating deep-green pill whose concave dip glides from tab to tab,
/// carrying a bubble with the selected icon.
class GooeyNavBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;

  const GooeyNavBar({super.key, required this.index, required this.onTap});

  @override
  State<GooeyNavBar> createState() => _GooeyNavBarState();
}

class _GooeyNavBarState extends State<GooeyNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _pos; // fractional tab position 0..4

  static const _duration = Duration(milliseconds: 480);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    _pos = Tween<double>(
      begin: widget.index.toDouble(),
      end: widget.index.toDouble(),
    ).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic));
  }

  @override
  void didUpdateWidget(GooeyNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _pos = Tween<double>(begin: _pos.value, end: widget.index.toDouble())
          .animate(
              CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic));
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.brightness == Brightness.dark
        ? const Color(0xFF14352A)
        : kDeepGreen;
    final iconColor = Colors.white.withValues(alpha: 0.75);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: LayoutBuilder(
          builder: (ctx, c) {
            final barW = c.maxWidth;
            const barH = 68.0;
            const sidePad = 18.0;
            const bubbleR = 27.0;
            final tabW = (barW - sidePad * 2) / 5;
            double xFor(int i) => sidePad + tabW * (i + 0.5);

            return AnimatedBuilder(
              animation: _pos,
              builder: (ctx, _) {
                // Interpolate the dip x between neighboring tab centers.
                final p = _pos.value.clamp(0.0, 4.0);
                final i0 = p.floor().clamp(0, 3);
                final frac = p - i0;
                final dipX =
                    xFor(i0) * (1 - frac) + xFor(i0 + 1) * frac;

                return SizedBox(
                  height: barH + 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Bar with the sliding dip.
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: CustomPaint(
                          size: Size(barW, barH),
                          painter: _BarPainter(
                              dipX: dipX, color: barColor),
                        ),
                      ),
                      // Bubble carrying the selected icon, riding the dip.
                      Positioned(
                        left: dipX - bubbleR,
                        bottom: barH - 34,
                        child: _bubble(
                            context, widget.index, bubbleR, theme),
                      ),
                      // Tap targets + unselected icons/labels.
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: barH,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: sidePad),
                          child: Row(
                            children: [
                              _tab(context, 0, Icons.home_outlined,
                                  'nav_home', iconColor, theme),
                              _tab(context, 1, Icons.history_outlined,
                                  'nav_history', iconColor, theme),
                              _tab(context, 2, Icons.add, 'nav_add',
                                  iconColor, theme),
                              _tab(context, 3,
                                  Icons.bar_chart_outlined,
                                  'nav_reports', iconColor, theme),
                              _tab(context, 4, Icons.more_horiz,
                                  'more', iconColor, theme),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i, IconData icon,
      String labelKey, Color iconColor, ThemeData theme) {
    final isSel = widget.index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onTap(i),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The selected slot stays empty — the bubble covers it.
            Icon(
              icon,
              size: 24,
              color: isSel ? Colors.transparent : iconColor,
            ),
            const SizedBox(height: 3),
            Text(
              tr(context, labelKey),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSel
                    ? kGold
                    : iconColor.withValues(alpha: 0.8),
                fontWeight:
                    isSel ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(
      BuildContext context, int index, double r, ThemeData theme) {
    // Center tab: the liquid-marble add button.
    if (index == 2) {
      return LiquidAddButton(
        size: r * 2,
        onTap: () => widget.onTap(2),
        active: true,
      );
    }
    final icons = {
      0: Icons.home,
      1: Icons.history,
      3: Icons.bar_chart,
      4: Icons.more_horiz,
    };
    return Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF1E4A3A)
            : kDeepGreenDark,
        border: Border.all(
          color: kGold.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icons[index], size: 26, color: kGold),
    );
  }
}

/// Paints the floating pill with a smooth concave dip at [dipX].
class _BarPainter extends CustomPainter {
  final double dipX;
  final Color color;

  _BarPainter({required this.dipX, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 22.0; // corner radius
    const dipR = 30.0; // dip half-width at the base
    const dipD = 24.0; // dip depth
    const s = dipR + 14; // smooth zone half-width

    final path = Path();
    path.moveTo(r, 0);
    path.lineTo(dipX - s, 0);
    // Glide down into the valley...
    path.cubicTo(
      dipX - s * 0.55, 0,
      dipX - dipR * 0.75, dipD,
      dipX, dipD,
    );
    // ...and back up.
    path.cubicTo(
      dipX + dipR * 0.75, dipD,
      dipX + s * 0.55, 0,
      dipX + s, 0,
    );
    path.lineTo(size.width - r, 0);
    path.quadraticBezierTo(size.width, 0, size.width, r);
    path.lineTo(size.width, size.height - r);
    path.quadraticBezierTo(
        size.width, size.height, size.width - r, size.height);
    path.lineTo(r, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - r);
    path.lineTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);
    path.close();

    canvas.drawShadow(
        path, Colors.black.withValues(alpha: 0.35), 12, 0);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.dipX != dipX || old.color != color;
}
