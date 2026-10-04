import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Premium dark navbar matching the reference design:
/// floating dark pill with concave center notch, elevated blue orb
/// for the Add action, and a sliding green indicator under the
/// selected tab. Icon + label per tab.
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

  static const _duration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    _pos = Tween<double>(
      begin: widget.index.toDouble(),
      end: widget.index.toDouble(),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.fastOutSlowIn));
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
    // 0: Home, 1: History, 2: Add, 3: Reports, 4: More
    final items = [
      _NavItem(Icons.home_outlined, Icons.home_rounded, 'nav_home'),
      _NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded,
          'nav_history'),
      null, // center orb
      _NavItem(Icons.bar_chart_outlined, Icons.bar_chart_rounded,
          'nav_reports'),
      _NavItem(Icons.settings_outlined, Icons.settings_rounded,
          'nav_settings'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The dark pill bar with center notch.
              Positioned.fill(
                top: 10,
                child: CustomPaint(
                  painter: _NotchBarPainter(),
                ),
              ),
              // Tab items + sliding indicator.
              Positioned.fill(
                top: 10,
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
                                      child: _TabButton(
                                        item: items[i]!,
                                        selected:
                                            widget.index == i,
                                        onTap: () =>
                                            widget.onTap(i),
                                      ),
                                    ),
                              ],
                            ),
                            // Sliding green indicator.
                            if (widget.index != 2)
                              Positioned(
                                left: indicatorX - 12,
                                bottom: 8,
                                child: Container(
                                  width: 24,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    borderRadius:
                                        BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF22C55E)
                                            .withValues(alpha: 0.6),
                                        blurRadius: 6,
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
              // Center elevated blue orb (Add).
              Positioned.fill(
                child: Center(
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

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;
  _NavItem(this.icon, this.activeIcon, this.labelKey);
}

class _TabButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.45);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              selected ? item.activeIcon : item.icon,
              color: color,
              size: 26,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tr(context, item.labelKey),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CenterOrb extends StatefulWidget {
  final VoidCallback onTap;
  const _CenterOrb({required this.onTap});

  @override
  State<_CenterOrb> createState() => _CenterOrbState();
}

class _CenterOrbState extends State<_CenterOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.12,
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
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
        animation: _pressCtrl,
        builder: (ctx, _) {
          final scale = 1.0 - _pressCtrl.value;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF3B82F6),
                    Color(0xFF2563EB),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6)
                        .withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Paints the dark pill bar with a smooth concave notch in the center
/// where the orb sits.
class _NotchBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const r = 28.0; // corner radius
    const notchW = 88.0; // notch width
    const notchDepth = 22.0; // how deep the dip goes
    final cx = w / 2;

    final path = Path();
    // Start top-left after corner.
    path.moveTo(r, 0);
    // Top edge to notch start.
    path.lineTo(cx - notchW / 2 - 12, 0);
    // Smooth concave curve down into the notch.
    path.cubicTo(
      cx - notchW / 2 + 6, 0,
      cx - notchW / 2 + 10, notchDepth,
      cx, notchDepth,
    );
    path.cubicTo(
      cx + notchW / 2 - 10, notchDepth,
      cx + notchW / 2 - 6, 0,
      cx + notchW / 2 + 12, 0,
    );
    // Top edge to top-right corner.
    path.lineTo(w - r, 0);
    path.quadraticBezierTo(w, 0, w, r);
    path.lineTo(w, h - r);
    path.quadraticBezierTo(w, h, w - r, h);
    path.lineTo(r, h);
    path.quadraticBezierTo(0, h, 0, h - r);
    path.lineTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);
    path.close();

    // Bar fill: dark with subtle vertical gradient.
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF2A2A2A),
          Color(0xFF1A1A1A),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, fillPaint);

    // Subtle top highlight border.
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
