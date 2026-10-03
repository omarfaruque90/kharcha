import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/challenge.dart';
import '../services/challenge_service.dart';
import '../widgets/motion.dart';

/// No-spend challenge screen (Package Z).
///
/// - No active challenge → gold "Start 7-day challenge" button (+ last
///   result history line when a past challenge finished on this device).
/// - Active challenge → animated progress ring (streak/7), 7 day cells
///   (done = gold check, today = highlighted ring, future = grey), and
///   the streak text.
///
/// Codes against the coordinator-provided `Challenge` model
/// (models/challenge.dart) and DatabaseHelper challenge CRUD. The
/// `Challenge` constructor is assumed to take named parameters
/// (type/start/end/streak/active).
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

const Color _kGold = Color(0xFFD4AF37);
const Color _kDeepGreen = Color(0xFF0B3D2E);

enum _DayStatus { done, spent, todayPending, future }

class _ChallengeScreenState extends State<ChallengeScreen> {
  bool _loading = true;
  Challenge? _active;
  Set<String> _spentDays = {};
  ({bool won, int streak})? _history;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    Challenge? active;
    try {
      active = await DatabaseHelper.instance.getActiveChallenge();
    } catch (_) {
      active = null;
    }
    Set<String> spent = {};
    if (active != null && active.active) {
      try {
        spent = await ChallengeService.spentDayKeys(active.start, active.end);
      } catch (_) {
        spent = {};
      }
    }
    ({bool won, int streak})? history;
    try {
      history = await ChallengeService.lastResult();
    } catch (_) {
      history = null;
    }
    if (!mounted) return;
    setState(() {
      _active = (active != null && active.active) ? active : null;
      _spentDays = spent;
      _history = history;
      _loading = false;
    });
  }

  Future<void> _startChallenge() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final challenge = Challenge(
        type: 'no_spend',
        start: start,
        end: start.add(const Duration(days: 6)),
        streak: 0,
        active: true,
      );
      await DatabaseHelper.instance.insertChallenge(challenge);
      await ChallengeService.checkDaily();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'challenge_start_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'challenge_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _active == null
              ? _buildStartView(context)
              : _buildActiveView(context, _active!),
    );
  }

  Widget _buildStartView(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const StaggeredEntrance(
              child: Text('🏆', style: TextStyle(fontSize: 72)),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              delayMs: 80,
              child: Text(
                tr(context, 'challenge_title'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            StaggeredEntrance(
              delayMs: 140,
              child: Text(
                tr(context, 'challenge_start_sub'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),
            StaggeredEntrance(
              delayMs: 200,
              child: PressableScale(
                onTap: _startChallenge,
                child: ElevatedButton.icon(
                  onPressed: _starting ? null : _startChallenge,
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(tr(context, 'challenge_start')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGold,
                    foregroundColor: _kDeepGreen,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            if (_history != null) ...[
              const SizedBox(height: 24),
              StaggeredEntrance(
                delayMs: 260,
                child: Text(
                  _history!.won
                      ? tr(context, 'challenge_last_result_win')
                      : tr(context, 'challenge_last_result_end')
                          .replaceAll('{n}', '${_history!.streak}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveView(BuildContext context, Challenge challenge) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final streak = challenge.streak.clamp(0, 7);
    final today = DateTime.now();
    final startDay =
        DateTime(challenge.start.year, challenge.start.month, challenge.start.day);
    final todayKey = _key(today);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Progress ring.
          StaggeredEntrance(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: streak / 7),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: value,
                        strokeWidth: 14,
                        backgroundColor: dark
                            ? Colors.white12
                            : Colors.black12,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_kGold),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$streak/7',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _kGold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr(context, 'challenge_day_streak')
                                .replaceAll('{n}', '$streak'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          StaggeredEntrance(
            delayMs: 100,
            child: Text(
              tr(context, 'challenge_days_left')
                  .replaceAll('{n}', '${7 - streak}'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 7 day cells.
          Row(
            children: List.generate(7, (i) {
              final day = startDay.add(Duration(days: i));
              final key = _key(day);
              final isToday = key == todayKey;
              final isFuture = day.isAfter(
                  DateTime(today.year, today.month, today.day));
              final spent = _spentDays.contains(key);
              final _DayStatus status;
              if (isFuture) {
                status = _DayStatus.future;
              } else if (isToday) {
                status = spent ? _DayStatus.spent : _DayStatus.todayPending;
              } else {
                status = spent ? _DayStatus.spent : _DayStatus.done;
              }
              return Expanded(
                child: StaggeredEntrance(
                  delayMs: 140 + i * 60,
                  child: _DayCell(
                    day: day,
                    status: status,
                    isToday: isToday,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          StaggeredEntrance(
            delayMs: 560,
            child: Text(
              tr(context, 'challenge_streak_note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final _DayStatus status;
  final bool isToday;

  const _DayCell({
    required this.day,
    required this.status,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    Color bg;
    Color fg;
    Widget icon;
    switch (status) {
      case _DayStatus.done:
        bg = _kGold;
        fg = _kDeepGreen;
        icon = const Icon(Icons.check, size: 22);
        break;
      case _DayStatus.spent:
        bg = dark ? Colors.white10 : Colors.black12;
        fg = dark ? Colors.red.shade300 : Colors.red.shade700;
        icon = Icon(Icons.close, size: 20, color: fg);
        break;
      case _DayStatus.todayPending:
        bg = dark ? Colors.white10 : Colors.black12;
        fg = theme.colorScheme.onSurface;
        icon = Icon(Icons.today, size: 20, color: fg);
        break;
      case _DayStatus.future:
        bg = dark ? Colors.white10 : Colors.black12;
        fg = theme.colorScheme.onSurfaceVariant;
        icon = Icon(Icons.circle_outlined, size: 16, color: fg);
        break;
    }

    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: isToday
                ? Border.all(color: _kGold, width: 3)
                : null,
          ),
          child: IconTheme(
            data: IconThemeData(color: fg),
            child: icon,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${day.day}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isToday ? FontWeight.bold : null,
            color: isToday
                ? _kGold
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
