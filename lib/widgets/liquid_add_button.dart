import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated "liquid marble" add button, like the reference video:
/// a pearl-white circle with slowly swirling pastel blobs inside,
/// a soft outer glow, and a dark + on top.
class LiquidAddButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool active;
  final double size;

  const LiquidAddButton({
    super.key,
    required this.onTap,
    this.active = false,
    this.size = 88,
  });

  @override
  State<LiquidAddButton> createState() => _LiquidAddButtonState();
}

class _LiquidAddButtonState extends State<LiquidAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // One slow swirl every ~7 seconds, looping forever.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              // Strong halo like reference image 2.
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.7),
                blurRadius: 28,
                spreadRadius: 6,
              ),
              BoxShadow(
                color: const Color(0xFFB6C8FF)
                    .withValues(alpha: widget.active ? 0.95 : 0.7),
                blurRadius: widget.active ? 40 : 30,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: const Color(0xFFFFAECB)
                    .withValues(alpha: 0.45),
                blurRadius: 52,
                spreadRadius: 8,
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 3,
            ),
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _LiquidPainter(_ctrl.value),
                ),
                // Glass sheen on top.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.35, -0.45),
                      radius: 0.9,
                      colors: [
                        Color(0x99FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.add,
                    size: 32,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  /// 0..1 loop progress.
  final double t;

  _LiquidPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Pearl base.
    canvas.drawCircle(
      c,
      r,
      Paint()..color = const Color(0xFFF4F1FF),
    );

    // Pastel blobs orbiting the center — the "liquid marble" swirl.
    const blobs = [
      (Color(0xFFFFAECB), 0.00, 0.42), // pink
      (Color(0xFF9EC5FF), 0.27, 0.50), // blue
      (Color(0xFFC9A8FF), 0.53, 0.44), // purple
      (Color(0xFF9DF0C8), 0.78, 0.38), // mint
      (Color(0xFFFFD6A8), 0.40, 0.34), // peach
    ];
    for (final (color, phase, orbit) in blobs) {
      final a = (t + phase) * 2 * math.pi;
      final off = Offset(
        math.cos(a) * r * orbit,
        math.sin(a) * r * orbit,
      );
      final blobR = r * 0.72;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.9),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: c + off, radius: blobR),
        );
      canvas.drawCircle(c + off, blobR, paint);
    }

    // Slow counter-rotating inner swirl for depth.
    final a2 = (1 - t) * 2 * math.pi;
    final inner = Offset(
      math.cos(a2) * r * 0.2,
      math.sin(a2) * r * 0.2,
    );
    canvas.drawCircle(
      c + inner,
      r * 0.45,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x66FFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(
          Rect.fromCircle(center: c + inner, radius: r * 0.45),
        ),
    );
  }

  @override
  bool shouldRepaint(_LiquidPainter old) => old.t != t;
}
