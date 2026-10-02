import 'package:flutter/material.dart';

/// Fades + slides its child in once when first built. Replays only if the
/// widget's [key] changes (Flutter reuses state for matching keys).
class StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final double slideFraction;

  const StaggeredEntrance({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.slideFraction = 0.12,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(
      begin: Offset(0, widget.slideFraction),
      end: Offset.zero,
    ).animate(curved);
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Subtle press-scale effect. Wraps any child; the child keeps its own
/// tap handling (pass [onTap] only when the child has none).
class PressableScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final VoidCallback? onTap;

  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
    this.onTap,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
