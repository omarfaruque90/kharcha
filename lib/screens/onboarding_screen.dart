import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../theme/design_tokens.dart';
import '../widgets/motion.dart';

/// Startup gate: shows [OnboardingScreen] once (after auth, before
/// MainShell), then never again. The flag lives in SharedPreferences as
/// `onboarding_seen == '1'`.
class OnboardingGate extends StatefulWidget {
  final Widget child;

  const OnboardingGate({super.key, required this.child});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  /// null = checking, true = seen (go to app), false = show onboarding.
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _seen = prefs.getString('onboarding_seen') == '1');
    } catch (_) {
      // Fail closed: a prefs failure must never trap the user on this
      // screen — skip onboarding and go straight to the app.
      if (!mounted) return;
      setState(() => _seen = true);
    }
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('onboarding_seen', '1');
    } catch (_) {
      // Best-effort; the app still opens.
    }
    if (mounted) setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) {
      return const Scaffold(
        backgroundColor: kDeepGreenDark,
        body: Center(
          child: CircularProgressIndicator(color: kGold),
        ),
      );
    }
    if (seen) return widget.child;
    return OnboardingScreen(onDone: _finish);
  }
}

class _ObPage {
  final String emoji;
  final IconData icon;
  final String titleKey;
  final String subKey;

  const _ObPage(this.emoji, this.icon, this.titleKey, this.subKey);
}

const List<_ObPage> _pages = [
  _ObPage('🧾', Icons.receipt_long_outlined, 'ob1_title', 'ob1_sub'),
  _ObPage('🎯', Icons.savings_outlined, 'ob2_title', 'ob2_sub'),
  _ObPage('📴', Icons.cloud_off_outlined, 'ob4_title', 'ob4_sub'),
];

/// First-run showcase: swipeable brand cards (gold + deep green, emoji /
/// icon compositions — no image assets). Skippable; "Get started" on the
/// last page. Shown once via [OnboardingGate].
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kDeepGreenDark, kDeepGreen, Color(0xFF052018)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip — always one tap away until the last page.
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: last ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: last,
                    child: TextButton(
                      onPressed: widget.onDone,
                      child: Text(
                        tr(context, 'ob_skip'),
                        style: TextStyle(
                          color: kGoldLight.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _PageCard(page: _pages[i]),
                ),
              ),
              // Dots.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin:
                          const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? kGold
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: KSpacing.l),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KSpacing.l),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: kDeepGreenDark,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(
                      tr(context, last ? 'ob_start' : 'ob_next'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: KSpacing.l),
            ],
          ),
        ),
      ),
    );
  }
}

/// One branded showcase card: gold-ringed deep-green medallion with an
/// emoji + icon composition, headline and teaching subtitle.
class _PageCard extends StatelessWidget {
  final _ObPage page;

  const _PageCard({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StaggeredEntrance(
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kDeepGreenCard, kDeepGreenDark],
                ),
                border: Border.all(
                  color: kGold.withValues(alpha: 0.65),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kGold.withValues(alpha: 0.25),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    page.emoji,
                    style: const TextStyle(fontSize: 84),
                  ),
                  Positioned(
                    bottom: 26,
                    right: 26,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: kGold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: kDeepGreenDark,
                        size: 18,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 30,
                    left: 30,
                    child: Icon(
                      page.icon,
                      color: kGoldLight.withValues(alpha: 0.5),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KSpacing.xl),
          StaggeredEntrance(
            delayMs: 120,
            child: Text(
              tr(context, page.titleKey),
              style: KType.headline(context).copyWith(
                color: Colors.white,
                fontSize: 24,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: KSpacing.s),
          StaggeredEntrance(
            delayMs: 220,
            child: Text(
              tr(context, page.subKey),
              style: KType.body(context).copyWith(
                color: Colors.white70,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
