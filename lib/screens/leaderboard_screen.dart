import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../services/leaderboard_service.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Friend leaderboard (Package BH): create/join boards with a 6-char code,
/// publish this month's savings score, and see the monthly ranking.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  Future<List<Map<String, dynamic>>>? _boardsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _boardsFuture = LeaderboardService.myBoards();
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'lb_create_board')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            hintText: tr(ctx, 'lb_board_name_hint'),
            labelText: tr(ctx, 'lb_board_name'),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
            child: Text(tr(ctx, 'lb_create_board')),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    _snack(tr(context, 'lb_creating'));
    final code = await LeaderboardService.createBoard(name);
    if (!mounted) return;
    if (code.isEmpty) {
      _snack(tr(context, 'lb_create_fail'), error: true);
      return;
    }
    _refresh();
    await _showCodeDialog(code);
  }

  /// Shows the new board's code big, with a copy button.
  Future<void> _showCodeDialog(String code) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'lb_your_code')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGold, width: 1.5),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: kGold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(tr(ctx, 'lb_copied'))),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(tr(ctx, 'lb_copy')),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _showJoinDialog() async {
    final codeCtrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'lb_join_board')),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: tr(ctx, 'lb_code_hint'),
            labelText: tr(ctx, 'lb_code'),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(codeCtrl.text),
            child: Text(tr(ctx, 'lb_join_board')),
          ),
        ],
      ),
    );
    codeCtrl.dispose();
    if (code == null || code.trim().isEmpty) return;
    if (!mounted) return;

    _snack(tr(context, 'lb_joining'));
    final ok = await LeaderboardService.joinBoard(code);
    if (!mounted) return;
    if (ok) {
      _snack(tr(context, 'lb_joined'));
      _refresh();
    } else {
      _snack(tr(context, 'lb_join_fail'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'lb_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: tr(context, 'lb_refresh'),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: PressableScale(
                    onTap: _showCreateDialog,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          children: [
                            const Icon(Icons.group_add_outlined, size: 28),
                            const SizedBox(height: 6),
                            Text(
                              tr(context, 'lb_create_board'),
                              style:
                                  Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressableScale(
                    onTap: _showJoinDialog,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          children: [
                            const Icon(Icons.login_outlined, size: 28),
                            const SizedBox(height: 6),
                            Text(
                              tr(context, 'lb_join_board'),
                              style:
                                  Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _boardsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                final boards = snap.data ?? [];
                if (boards.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.emoji_events_outlined,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr(context, 'lb_no_boards'),
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(context, 'lb_no_boards_sub'),
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: boards.length,
                  itemBuilder: (context, i) {
                    final b = boards[i];
                    final members =
                        (b['members'] as List?)?.length ?? 0;
                    return StaggeredEntrance(
                      delayMs: i * 60,
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: kGold.withValues(alpha: 0.2),
                            child: const Icon(
                              Icons.emoji_events_outlined,
                              color: kGold,
                            ),
                          ),
                          title: Text(
                            '${b['name'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${tr(context, 'lb_code')}: ${b['code']} • '
                            '$members ${tr(context, 'lb_members')}',
                          ),
                          trailing:
                              const Icon(Icons.chevron_right_outlined),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _BoardDetailScreen(
                                code: '${b['code']}',
                                name: '${b['name'] ?? ''}',
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One board's monthly ranking.
class _BoardDetailScreen extends StatefulWidget {
  final String code;
  final String name;

  const _BoardDetailScreen({required this.code, required this.name});

  @override
  State<_BoardDetailScreen> createState() => _BoardDetailScreenState();
}

class _BoardDetailScreenState extends State<_BoardDetailScreen> {
  late DateTime _viewMonth;
  late String _monthKey;
  Future<Map<String, dynamic>>? _detailFuture;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewMonth = DateTime(now.year, now.month);
    _refresh();
  }

  /// Loads scores for [_monthKey] plus the members' avatars in parallel.
  Future<Map<String, dynamic>> _loadDetail() async {
    final scores = await LeaderboardService.boardScores(
      widget.code,
      _monthKey,
    );
    final avatars = await LeaderboardService.boardAvatars(widget.code);
    return {'scores': scores, 'avatars': avatars};
  }

  void _refresh() {
    _monthKey = monthKeyOf(_viewMonth);
    setState(() {
      _detailFuture = _loadDetail();
    });
  }

  void _shiftMonth(int delta) {
    _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta);
    _refresh();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _viewMonth.year == now.year && _viewMonth.month == now.month;
  }

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    try {
      final money = context.read<MoneyProvider>();
      final expenses = context.read<ExpenseProvider>();
      final spent = expenses.totalThisMonth();
      final income = money.incomeForMonth(_monthKey);
      await LeaderboardService.publishScore(
        widget.code,
        income - spent,
        spent,
      );
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'lb_score_published'))),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'lb_copied'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          TextButton.icon(
            onPressed: _copyCode,
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(
              widget.code,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: kGold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  monthLong(
                    _viewMonth,
                    context.watch<SettingsProvider>().language,
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _detailFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                final data = snap.data;
                final scores =
                    (data?['scores'] as List?)?.cast<Map<String, dynamic>>() ??
                        const [];
                final avatars =
                    (data?['avatars'] as Map?)?.cast<String, String>() ??
                        const <String, String>{};
                if (scores.isEmpty) {
                  return Center(
                    child: Text(tr(context, 'lb_no_scores')),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: scores.length,
                  itemBuilder: (context, i) {
                    final s = scores[i];
                    final rank = i + 1;
                    final isFirst = rank == 1;
                    final name = '${s['name'] ?? ''}';
                    final saved = (s['saved'] as num?)?.toDouble() ?? 0;
                    final spent = (s['spent'] as num?)?.toDouble() ?? 0;
                    return StaggeredEntrance(
                      delayMs: i * 50,
                      child: Card(
                        color: isFirst
                            ? kGold.withValues(alpha: 0.12)
                            : null,
                        shape: isFirst
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: kGold,
                                  width: 1.5,
                                ),
                              )
                            : null,
                        child: ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RankBadge(rank: rank),
                              const SizedBox(width: 8),
                              _MemberAvatar(
                                name: name,
                                avatarBase64: avatars['${s['uid']}'],
                              ),
                            ],
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight: isFirst
                                  ? FontWeight.w900
                                  : FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${tr(context, 'lb_spent')}: ${formatMoney(spent)}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(saved),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: isFirst
                                      ? kGoldDark
                                      : theme.colorScheme.primary,
                                ),
                              ),
                              Text(
                                tr(context, 'lb_saved'),
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_isCurrentMonth)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.publish_outlined),
                  label: Text(tr(context, 'lb_publish_score')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rank circle — gold crown look for #1, plain number otherwise.
class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    return CircleAvatar(
      radius: 22,
      backgroundColor:
          isFirst ? kGold : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: isFirst
          ? const Icon(Icons.emoji_events, color: Colors.white)
          : Text(
              '$rank',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
    );
  }
}

/// Avatar for a board member: base64 photo when present, initial otherwise.
class _MemberAvatar extends StatelessWidget {
  final String name;
  final String? avatarBase64;

  const _MemberAvatar({required this.name, this.avatarBase64});

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    final raw = avatarBase64;
    if (raw != null && raw.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(raw));
      } catch (_) {
        image = null;
      }
    }
    if (image != null) return CircleAvatar(backgroundImage: image);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(child: Text(initial));
  }
}
