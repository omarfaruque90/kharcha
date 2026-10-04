import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import 'liquid_add_button.dart';

/// Gooey sliding-notch bottom nav, like the reference video:
/// a floating deep-green pill whose concave dip glides from tab to tab,
/// carrying a bubble with the selected icon. Colors follow the theme's
/// accent choice.
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

  static const _duration = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    _pos = Tween<double>(
      begin: widget.index.toDouble(),
      end: widget.index.toDouble(),
    ).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.fastOutSlowIn));
  }

  @override
  void didUpdateWidget(GooeyNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _pos = Tween<double>(begin: _pos.value, end: widget.index.toDouble())
          .animate(
              CurvedAnimation(parent: _ctrl, curve: Curves.fastOutSlowIn));
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
    final accentName = context.watch<SettingsProvider>().accent;
    final accent = kAccents[accentName] ?? kGold;
    final dark = theme.brightness == Brightness.dark;

    // Bar: solid deep green like the video's solid purple.
    final barColor = dark ? const Color(0xFF0E2F25) : kDeepGreen;
    final iconColor = Colors.white.withValues(alpha: 0.72);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: LayoutBuilder(
          builder: (ctx, c) {
            final barW = c.maxWidth;
            const barH = 72.0;
            const sidePad = 16.0;
            // Reference image 1: selected tab sits in a bubble cradled
            // deep in the sliding dip. Reference image 2: the + orb is
            // always big, raised high above the bar with a strong glow.
            const bubbleR = 34.0; // 68px tab bubbles
            const addR = 44.0; // 88px + orb — always big
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

                return RepaintBoundary(
                  child: SizedBox(
                  height: barH + 56,
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
                            dipX: dipX,
                            color: barColor,
                            accent: accent,
                          ),
                        ),
                      ),
                      // Bubble carrying the selected icon, cradled deep
                      // in the dip like the reference: half in, half out.
                      // The + orb stays big and raised like image 2.
                      Positioned(
                        left: dipX -
                            (widget.index == 2 ? addR : bubbleR),
                        bottom: widget.index == 2
                            ? barH - addR + 14
                            : barH - bubbleR + 10,
                        child: _bubble(context, widget.index,
                            bubbleR, addR, accent, dark),
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
                                  'nav_home', iconColor, accent, theme),
                              _tab(context, 1, Icons.history_outlined,
                                  'nav_history', iconColor, accent, theme),
                              _tab(context, 2, Icons.add, 'nav_add',
                                  iconColor, accent, theme),
                              _tab(context, 3,
                                  Icons.bar_chart_outlined,
                                  'nav_reports', iconColor, accent, theme),
                              _tab(context, 4, Icons.more_horiz,
                                  'more', iconColor, accent, theme),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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
      String labelKey, Color iconColor, Color accent, ThemeData theme) {
    final isSel = widget.index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onTap(i),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The selected slot stays empty — the bubble covers it.
            // Smooth fade so the icon doesn't pop.
            AnimatedOpacity(
              opacity: isSel ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: theme.textTheme.labelSmall!.copyWith(
                color: isSel ? accent : iconColor.withValues(alpha: 0.85),
                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
              ),
              child: Text(tr(context, labelKey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, int index, double r,
      double addR, Color accent, bool dark) {
    // Center tab: the liquid-marble add button — always big (88px),
    // raised high with a strong glow like reference image 2.
    if (index == 2) {
      return LiquidAddButton(
        size: addR * 2,
        onTap: () => widget.onTap(2),
        active: true,
      );
    }
    const icons = {
      0: Icons.home,
      1: Icons.history,
      3: Icons.bar_chart,
      4: Icons.more_horiz,
    };
    // Pop-in scale when the bubble arrives at a new tab.
    return TweenAnimationBuilder<double>(
      key: ValueKey('bubble-$index'),
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
      builder: (ctx, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: r * 2,
        height: r * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [const Color(0xFF1B4A3B), const Color(0xFF0E2F25)]
                : [kDeepGreen, kDeepGreenDark],
          ),
          border: Border.all(
            color: accent.withValues(alpha: 0.65),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icons[index], size: 28, color: accent),
      ),
    );
  }
}

/// Paints the floating pill with a smooth concave dip at [dipX],
/// plus a soft accent glow along the dip's rim.
class _BarPainter extends CustomPainter {
  final double dipX;
  final Color color;
  final Color accent;

  _BarPainter(
      {required this.dipX, required this.color, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 26.0; // corner radius — pill like the reference
    const dipR = 52.0; // dip half-width: wide smooth U like image 1
    const dipD = 34.0; // dip depth
    const s = dipR + 22; // smooth zone half-width

    final path = Path();
    path.moveTo(r, 0);
    path.lineTo(dipX - s, 0);
    // Glide down into the valley...
    path.cubicTo(
      dipX - s * 0.55, 0,
      dipX - dipR * 0.72, dipD,
      dipX, dipD,
    );
    // ...and back up.
    path.cubicTo(
      dipX + dipR * 0.72, dipD,
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
        path, Colors.black.withValues(alpha: 0.4), 14, false);
    canvas.drawPath(path, Paint()..color = color);

    // Accent glow tracing the dip's rim.
    final glow = Path()
      ..moveTo(dipX - s, 0)
      ..cubicTo(
        dipX - s * 0.55, 0,
        dipX - dipR * 0.72, dipD,
        dipX, dipD,
      )
      ..cubicTo(
        dipX + dipR * 0.72, dipD,
        dipX + s * 0.55, 0,
        dipX + s, 0,
      );
    canvas.drawPath(
      glow,
      Paint()
        ..color = accent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.dipX != dipX || old.color != color || old.accent != accent;
}
