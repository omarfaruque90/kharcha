import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../theme/design_tokens.dart';
import '../utils/formatters.dart';

/// Premium fintech hero balance card: layered deep-green gradient with a
/// cheap decorative pattern (two translucent circles + a big ৳ watermark,
/// painted once — [CustomPainter.shouldRepaint] is false), an animated
/// count-up on the balance, and a quick-stats chip row (today / this week /
/// month savings) underneath.
///
/// Performance notes:
/// - The pattern painter never repaints (static decoration).
/// - The count-up only rebuilds its own Text via AnimatedBuilder.
/// - When the balance changes, the count animates from the old value to
///   the new one instead of restarting from zero.
class HeroBalanceCard extends StatelessWidget {
  final double balance;
  final double todaySpent;
  final double weekSpent;

  const HeroBalanceCard({
    super.key,
    required this.balance,
    required this.todaySpent,
    required this.weekSpent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KRadius.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kDeepGreenCard, kDeepGreen, kDeepGreenDark],
        ),
        border: Border.all(
          color: kGold.withValues(alpha: 0.45),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KRadius.card),
        child: CustomPaint(
          painter: const _HeroPatternPainter(),
          child: Padding(
            padding: const EdgeInsets.all(KSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: kGold.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: kGold,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: KSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, 'balance_title'),
                            style: KType.label(context).copyWith(
                              color:
                                  kGoldLight.withValues(alpha: 0.9),
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: KSpacing.xxs),
                          _AnimatedMoney(
                            value: balance,
                            style: KType.display(context).copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KSpacing.m),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        icon: Icons.today,
                        label: tr(context, 'today'),
                        value: todaySpent,
                      ),
                    ),
                    const SizedBox(width: KSpacing.xs),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.date_range,
                        label: tr(context, 'this_week'),
                        value: weekSpent,
                      ),
                    ),
                    const SizedBox(width: KSpacing.xs),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.savings_outlined,
                        label: tr(context, 'stat_savings'),
                        value: balance,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small frosted stat chip inside the hero: icon + label + amount.
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final bool highlight;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KSpacing.s,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: highlight
            ? kGold.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KRadius.chip),
        border: Border.all(
          color: highlight
              ? kGold.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: highlight ? kGold : kGoldLight,
              ),
              const SizedBox(width: KSpacing.xxs),
              Expanded(
                child: Text(
                  label,
                  style: KType.label(context).copyWith(
                    fontSize: 10.5,
                    letterSpacing: 0.4,
                    color: kGoldLight.withValues(alpha: 0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.xxs),
          Text(
            formatMoney(value),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Count-up money text: animates 0 → value on first mount, then tweens
/// from the previous value to the new one on updates.
class _AnimatedMoney extends StatefulWidget {
  final double value;
  final TextStyle? style;

  const _AnimatedMoney({required this.value, this.style});

  @override
  State<_AnimatedMoney> createState() => _AnimatedMoneyState();
}

class _AnimatedMoneyState extends State<_AnimatedMoney>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Tween<double> _tween;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _tween = Tween<double>(begin: 0, end: widget.value);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedMoney oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _tween = Tween<double>(
        begin: _tween.evaluate(_controller),
        end: widget.value,
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Text(
        formatMoney(_tween.evaluate(_controller)),
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Static decorative pattern behind the hero content: two translucent
/// circles and a large ৳ watermark. Painted once per layout
/// ([shouldRepaint] is false) so it costs nothing per frame.
class _HeroPatternPainter extends CustomPainter {
  const _HeroPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.92, -size.height * 0.35),
      size.width * 0.5,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 1.45),
      size.width * 0.55,
      Paint()..color = kGold.withValues(alpha: 0.07),
    );
    final glyph = TextPainter(
      text: TextSpan(
        text: '৳',
        style: TextStyle(
          fontSize: 150,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(
      canvas,
      Offset(
        size.width - glyph.width - 4,
        size.height - glyph.height - 8,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
