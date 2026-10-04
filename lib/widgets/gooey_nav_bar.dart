import 'package:flutter/material.dart';

/// Bottom navigation bar matching the reference design exactly:
/// dark pill bar, 5 tabs, large blue center orb breaking the top,
/// white abstract logo, thin outline icons, green glowing indicator
/// at the bottom edge under the active tab.
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
      duration: const Duration(milliseconds: 350),
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
    // Khorcha tabs mapped to reference icon styles:
    // 0: Home (line chart), 1: History (wallet), 2: Add (blue orb),
    // 3: Reports (storefront), 4: More (briefcase).
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: SizedBox(
          height: 96,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Dark pill bar.
              Positioned.fill(
                top: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
              // Tab items + sliding green indicator.
              Positioned.fill(
                top: 28,
                child: AnimatedBuilder(
                  animation: _pos,
                  builder: (ctx, _) {
                    return LayoutBuilder(
                      builder: (ctx, cons) {
                        final w = cons.maxWidth;
                        // 5 slots; slot centers at (i + 0.5) / 5 * w.
                        final slotW = w / 5;
                        final indX =
                            (_pos.value + 0.5) * slotW;
                        return Stack(
                          children: [
                            // Green glowing indicator at bottom edge.
                            Positioned(
                              left: indX - 14,
                              bottom: 0,
                              child: Container(
                                width: 28,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E676)
                                          .withValues(alpha: 0.8),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 5 tab buttons.
                            Row(
                              children: List.generate(5, (i) {
                                if (i == 2) {
                                  return const Expanded(
                                      child: SizedBox());
                                }
                                final active =
                                    widget.index == i;
                                return Expanded(
                                  child: _TabButton(
                                    active: active,
                                    index: i,
                                    onTap: () =>
                                        widget.onTap(i),
                                  ),
                                );
                              }),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              // Blue center orb breaking the top.
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

/// Single tab button with thin outline icon + small label.
class _TabButton extends StatelessWidget {
  final bool active;
  final int index;
  final VoidCallback onTap;

  const _TabButton({
    required this.active,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Reference icon styles: 0 = line chart, 1 = wallet,
    // 3 = storefront, 4 = briefcase.
    IconData icon;
    String label;
    switch (index) {
      case 0:
        icon = Icons.show_chart_rounded;
        label = 'Home';
        break;
      case 1:
        icon = Icons.account_balance_wallet_outlined;
        label = 'History';
        break;
      case 3:
        icon = Icons.storefront_outlined;
        label = 'Reports';
        break;
      default:
        icon = Icons.business_center_outlined;
        label = 'More';
    }
    final color = active ? Colors.white : const Color(0xFF8E8E93);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large blue orb with white abstract overlapping-circles logo.
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
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2E5BFF),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E5BFF).withValues(alpha: 0.4),
                blurRadius: 16,
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
      c + const Offset(-7, 8),
      13,
      paint,
    );
    // Medium circle top-right (slightly transparent overlap).
    canvas.drawCircle(
      c + const Offset(9, -7),
      10,
      paint..color = Colors.white.withValues(alpha: 0.85),
    );
    // Small dot top-left.
    canvas.drawCircle(
      c + const Offset(-13, -11),
      4,
      paint..color = Colors.white,
    );
    // Small dot bottom-right.
    canvas.drawCircle(
      c + const Offset(14, 10),
      3.5,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
