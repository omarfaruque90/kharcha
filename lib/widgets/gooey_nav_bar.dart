import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Bottom navigation bar matching the reference design exactly:
/// 5 floating tabs on a FULLY TRANSPARENT background (no pill, no bar,
/// no backing container) — large blue center orb, thin outline icons,
/// labels under each icon, green glowing indicator under the active tab.
class GooeyNavBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;

  const GooeyNavBar({
    super.key,
    required this.index,
    required this.onTap,
  });

  @override
  State<GooeyNavBar> createState() => _GooeyNavBarState();
}

class _GooeyNavBarState extends State<GooeyNavBar>
    with TickerProviderStateMixin {
  late AnimationController _posCtrl;
  late Animation<double> _pos;
  double _currentPos = 0;

  @override
  void initState() {
    super.initState();
    _currentPos = widget.index.toDouble();
    _posCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pos = Tween<double>(begin: _currentPos, end: _currentPos).animate(
      CurvedAnimation(parent: _posCtrl, curve: Curves.easeOutQuint),
    );
  }

  @override
  void didUpdateWidget(GooeyNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _pos = Tween<double>(
        begin: _currentPos,
        end: widget.index.toDouble(),
      ).animate(
        CurvedAnimation(parent: _posCtrl, curve: Curves.easeOutQuint),
      );
      _posCtrl.forward(from: 0);
      _currentPos = widget.index.toDouble();
    }
  }

  @override
  void dispose() {
    _posCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fully transparent — the icons, orb and indicator float directly
    // over the app content. No pill, no bar, no backing container.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SizedBox(
          height: 108,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Tab items + sliding green indicator (transparent layer).
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pos,
                  builder: (ctx, _) {
                    return LayoutBuilder(
                      builder: (ctx, cons) {
                        final w = cons.maxWidth;
                        // 5 slots; slot centers at (i + 0.5) / 5 * w.
                        final slotW = w / 5;
                        final indX = (_pos.value + 0.5) * slotW;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 4 side tab buttons (center slot is the orb).
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: List.generate(5, (i) {
                                if (i == 2) {
                                  return const Expanded(
                                      child: SizedBox());
                                }
                                final active = widget.index == i;
                                return Expanded(
                                  child: _TabButton(
                                    active: active,
                                    index: i,
                                    onTap: () => widget.onTap(i),
                                  ),
                                );
                              }),
                            ),
                            // Green glowing indicator under active label.
                            Positioned(
                              left: indX - 16,
                              bottom: 2,
                              child: Container(
                                width: 32,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius:
                                      BorderRadius.circular(3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E676)
                                          .withValues(alpha: 0.9),
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
              // Large blue center orb floating above the row.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
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

/// Single tab button: thin outline icon + small label below.
/// Plays a bounce/morph micro-animation when tapped.
class _TabButton extends StatefulWidget {
  final bool active;
  final int index;
  final VoidCallback onTap;

  const _TabButton({
    required this.active,
    required this.index,
    required this.onTap,
  });

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _tilt;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    // Bounce: overshoot then settle.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 0.92)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 35,
      ),
    ]).animate(_ctrl);
    // Tilt: rotate slightly then wobble back.
    _tilt = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.25)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.25, end: -0.12)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.12, end: 0.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 35,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    // Reference icon styles (thin outlines):
    // 0 = home, 1 = wallet, 3 = chart/store, 4 = briefcase.
    IconData icon;
    String labelKey;
    switch (widget.index) {
      case 0:
        icon = Icons.home_outlined;
        labelKey = 'nav_home';
        break;
      case 1:
        icon = Icons.account_balance_wallet_outlined;
        labelKey = 'nav_history';
        break;
      case 3:
        icon = Icons.show_chart_rounded;
        labelKey = 'nav_reports';
        break;
      default:
        icon = Icons.business_center_outlined;
        labelKey = 'nav_more';
    }
    final color =
        widget.active ? Colors.white : const Color(0xFF8E8E93);
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 76,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (ctx, _) {
                return Transform.rotate(
                  angle: _tilt.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Icon(icon, color: color, size: 28),
                  ),
                );
              },
            ),
            const SizedBox(height: 5),
            Text(
              tr(context, labelKey),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: widget.active
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
            // Space reserved for the green indicator below.
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// Large blue orb with white abstract overlapping-circles logo.
/// Tapping opens the Add (center) tab.
class _CenterOrb extends StatefulWidget {
  final VoidCallback onTap;

  const _CenterOrb({required this.onTap});

  @override
  State<_CenterOrb> createState() => _CenterOrbState();
}

class _CenterOrbState extends State<_CenterOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
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
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF3D6BFF),
                Color(0xFF1E40D8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E5BFF).withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: CustomPaint(
            painter: _AbstractLogoPainter(),
          ),
        ),
      ),
    );
  }
}

/// White abstract logo: overlapping circles like the reference.
class _AbstractLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = Colors.white;

    // Large circle bottom-left.
    canvas.drawCircle(
      c + const Offset(-8, 9),
      15,
      paint,
    );
    // Medium circle top-right (slightly transparent overlap).
    canvas.drawCircle(
      c + const Offset(10, -8),
      11,
      paint..color = Colors.white.withValues(alpha: 0.85),
    );
    // Small dot top-left.
    canvas.drawCircle(
      c + const Offset(-15, -13),
      4.5,
      paint..color = Colors.white,
    );
    // Small dot bottom-right.
    canvas.drawCircle(
      c + const Offset(16, 12),
      4,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
