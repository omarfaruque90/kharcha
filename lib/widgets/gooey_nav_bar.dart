import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Premium dark navbar — exact replica of the reference:
/// floating dark pill with concave center notch, oversized royal-blue
/// orb with abstract white logo, glowing neon-green sliding indicator,
/// and fluid icon morph animations on tap. Transparent background.
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

  static const _duration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    _pos = Tween<double>(
      begin: widget.index.toDouble(),
      end: widget.index.toDouble(),
    ).animate(CurvedAnimation(
        parent: _ctrl,
        curve: Curves.elasticOut,
        reverseCurve: Curves.fastOutSlowIn));
  }

  @override
  void didUpdateWidget(GooeyNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _pos = Tween<double>(begin: _pos.value, end: widget.index.toDouble())
          .animate(CurvedAnimation(
              parent: _ctrl,
              curve: const _SnappyCurve(),
              reverseCurve: Curves.fastOutSlowIn));
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
    // 0: Home, 1: History, 2: Add, 3: Reports, 4: More
    final items = [
      _NavItem(Icons.home_outlined, Icons.home_rounded, 'nav_home'),
      _NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded,
          'nav_history'),
      null, // center orb
      _NavItem(Icons.bar_chart_outlined, Icons.bar_chart_rounded,
          'nav_reports'),
      _NavItem(Icons.grid_view_outlined, Icons.grid_view_rounded,
          'nav_more'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 84,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Dark pill bar (reference design) — clean, no border,
              // no highlight, just the dark fill with center notch.
              Positioned.fill(
                top: 18,
                child: CustomPaint(
                  painter: _PillBarPainter(),
                ),
              ),
              // Tab items + sliding indicator.
              Positioned.fill(
                top: 18,
                child: AnimatedBuilder(
                  animation: _pos,
                  builder: (ctx, _) {
                    return LayoutBuilder(
                      builder: (ctx, constraints) {
                        final w = constraints.maxWidth;
                        final slotW = w / 5;
                        final indicatorX =
                            slotW * _pos.value + slotW / 2;
                        return Stack(
                          children: [
                            Row(
                              children: [
                                for (int i = 0; i < 5; i++)
                                  if (i == 2)
                                    SizedBox(width: slotW)
                                  else
                                    SizedBox(
                                      width: slotW,
                                      child: _MorphTabButton(
                                        item: items[i]!,
                                        selected:
                                            widget.index == i,
                                        onTap: () =>
                                            widget.onTap(i),
                                      ),
                                    ),
                              ],
                            ),
                            // Glowing neon-green sliding indicator.
                            if (widget.index != 2)
                              Positioned(
                                left: indicatorX - 14,
                                bottom: 6,
                                child: Container(
                                  width: 28,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00FF88),
                                    borderRadius:
                                        BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF00FF88)
                                            .withValues(alpha: 0.8),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              // Center oversized royal-blue orb with abstract logo.
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _CenterOrb(
                    onTap: () => widget.onTap(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Snappy easing curve for the indicator slide.
class _SnappyCurve extends Curve {
  const _SnappyCurve();
  @override
  double transformInternal(double t) {
    // Fast start, slight overshoot, settle.
    const s = 1.2;
    return 1 + (s + 1) * math.pow(t - 1, 3) + s * math.pow(t - 1, 2);
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;
  _NavItem(this.icon, this.activeIcon, this.labelKey);
}

/// Tab button with fluid morph animation on tap:
/// scale bounce + slight rotation + icon morph.
class _MorphTabButton extends StatefulWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _MorphTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_MorphTabButton> createState() => _MorphTabButtonState();
}

class _MorphTabButtonState extends State<_MorphTabButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morphCtrl;

  @override
  void initState() {
    super.initState();
    _morphCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
  }

  @override
  void dispose() {
    _morphCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _morphCtrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _morphCtrl,
            builder: (ctx, _) {
              final t = _morphCtrl.value;
              // Dramatic morph matching video: strong tilt + bounce + wobble.
              final scale =
                  1.0 + 0.45 * math.sin(t * math.pi) * (1 - t * 0.3);
              final rotation =
                  0.6 * math.sin(t * math.pi * 1.5) * (1 - t);
              final wobble =
                  0.12 * math.sin(t * math.pi * 4) * (1 - t);
              final squashX =
                  1.0 + 0.2 * math.sin(t * math.pi * 2) * (1 - t);
              final squashY =
                  1.0 - 0.18 * math.sin(t * math.pi * 2) * (1 - t);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..rotateZ(rotation + wobble)
                  ..scaleByDouble(
                      scale * squashX, scale * squashY, 1.0, 1.0),
                child: Icon(
                  widget.selected
                      ? widget.item.activeIcon
                      : widget.item.icon,
                  color: color,
                  size: 26,
                ),
              );
            },
          ),
          const SizedBox(height: 3),
          Text(
            tr(context, widget.item.labelKey),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: widget.selected
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// Oversized royal-blue orb with abstract white logo
/// (larger circle + smaller orbiting dot).
class _CenterOrb extends StatefulWidget {
  final VoidCallback onTap;
  const _CenterOrb({required this.onTap});

  @override
  State<_CenterOrb> createState() => _CenterOrbState();
}

class _CenterOrbState extends State<_CenterOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final AnimationController _orbitCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.1,
    );
    // Continuous slow orbit for the small dot.
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    _orbitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) => _pressCtrl.reverse(),
      onTapCancel: () => _pressCtrl.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pressCtrl, _orbitCtrl]),
        builder: (ctx, _) {
          final scale = 1.0 - _pressCtrl.value;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2B5CE6), // royal blue
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2B5CE6)
                        .withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: CustomPaint(
                painter: _AbstractLogoPainter(
                  orbitAngle:
                      _orbitCtrl.value * 2 * math.pi,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Abstract white logo: larger circle + smaller orbiting dot.
class _AbstractLogoPainter extends CustomPainter {
  final double orbitAngle;
  _AbstractLogoPainter({required this.orbitAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final white = Paint()..color = Colors.white;
    final whiteDim =
        Paint()..color = Colors.white.withValues(alpha: 0.7);

    // Larger circle (slightly off-center).
    canvas.drawCircle(
      center + const Offset(-3, 2),
      11,
      white,
    );
    // Smaller orbiting dot.
    const orbitR = 17.0;
    final dotPos = Offset(
      center.dx + orbitR * math.cos(orbitAngle),
      center.dy + orbitR * math.sin(orbitAngle),
    );
    canvas.drawCircle(dotPos, 5.5, whiteDim);
    // Tiny accent dot.
    canvas.drawCircle(
      Offset(
        center.dx + 8 * math.cos(-orbitAngle * 1.5),
        center.dy + 8 * math.sin(-orbitAngle * 1.5),
      ),
      2.5,
      white,
    );
  }

  @override
  bool shouldRepaint(
          covariant _AbstractLogoPainter oldDelegate) =>
      oldDelegate.orbitAngle != orbitAngle;
}

/// Clean dark pill bar with center notch — no border, no highlight.
class _PillBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const r = 30.0;
    const notchW = 96.0;
    const notchDepth = 26.0;
    final cx = w / 2;

    final path = Path();
    path.moveTo(r, 0);
    path.lineTo(cx - notchW / 2 - 14, 0);
    path.cubicTo(
      cx - notchW / 2 + 8, 0,
      cx - notchW / 2 + 12, notchDepth,
      cx, notchDepth,
    );
    path.cubicTo(
      cx + notchW / 2 - 12, notchDepth,
      cx + notchW / 2 - 8, 0,
      cx + notchW / 2 + 14, 0,
    );
    path.lineTo(w - r, 0);
    path.quadraticBezierTo(w, 0, w, r);
    path.lineTo(w, h - r);
    path.quadraticBezierTo(w, h, w - r, h);
    path.lineTo(r, h);
    path.quadraticBezierTo(0, h, 0, h - r);
    path.lineTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);
    path.close();

    // Solid dark fill only — no border, no highlight.
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF1E1E1E),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
