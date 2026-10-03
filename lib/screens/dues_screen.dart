import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';
import 'debts_screen.dart';
import 'reminder_screen.dart';
import 'subscriptions_screen.dart';

/// Unified "upcoming dues" master list (Package BJ): unsettled debts with a
/// due date, active bill reminders (next occurrence) and active subscriptions
/// (next billing date), all merged into one list sorted by due date.
class DuesScreen extends StatefulWidget {
  const DuesScreen({super.key});

  @override
  State<DuesScreen> createState() => _DuesScreenState();
}

/// One row of the dues master list.
class _DueItem {
  final String title;
  final double amount;
  final DateTime date;
  final String kind; // 'debt' | 'bill' | 'sub'

  const _DueItem({
    required this.title,
    required this.amount,
    required this.date,
    required this.kind,
  });
}

class _DuesScreenState extends State<DuesScreen> {
  List<_DueItem> _items = [];
  bool _loading = true;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Next occurrence of a monthly bill reminder given its [dayOfMonth].
  /// Clamps to the last day of the month (e.g. day 31 in February).
  static DateTime _nextBillDate(int dayOfMonth) {
    final now = DateTime.now();
    DateTime candidate(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, dayOfMonth.clamp(1, lastDay));
    }

    final today = _day(now);
    var next = candidate(now.year, now.month);
    if (next.isBefore(today)) {
      final rolled = DateTime(now.year, now.month + 1, 1);
      next = candidate(rolled.year, rolled.month);
    }
    return next;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final db = DatabaseHelper.instance;
      final debts = await db.getDebts(settled: false);
      final reminders = await db.getActiveBillReminders();
      final subs = await db.getSubscriptions();

      final items = <_DueItem>[];
      for (final d in debts) {
        if (d.dueDate == null) continue;
        items.add(_DueItem(
          title: d.person,
          amount: d.amount,
          date: _day(d.dueDate!),
          kind: 'debt',
        ));
      }
      for (final r in reminders) {
        items.add(_DueItem(
          title: r.title,
          amount: r.amount,
          date: _nextBillDate(r.dayOfMonth),
          kind: 'bill',
        ));
      }
      for (final s in subs) {
        if (!s.active) continue;
        items.add(_DueItem(
          title: s.name,
          amount: s.amount,
          date: _day(s.nextDue),
          kind: 'sub',
        ));
      }
      items.sort((a, b) => a.date.compareTo(b.date));
      if (mounted) setState(() => _items = items);
    } catch (_) {
      // List stays empty on failure.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Sum of everything due on or before the end of the current month
  /// (includes overdue items).
  double _totalDueThisMonth() {
    final now = DateTime.now();
    final firstNextMonth = DateTime(now.year, now.month + 1, 1);
    var total = 0.0;
    for (final item in _items) {
      if (!item.date.isBefore(firstNextMonth)) break;
      total += item.amount;
    }
    return total;
  }

  String _kindIcon(String kind) {
    switch (kind) {
      case 'debt':
        return '🤝';
      case 'bill':
        return '🧾';
      default:
        return '🔁';
    }
  }

  Widget _open(String kind) {
    switch (kind) {
      case 'debt':
        return const DebtsScreen();
      case 'bill':
        return const ReminderScreen();
      default:
        return const SubscriptionsScreen();
    }
  }

  Widget _badge(BuildContext context, _DueItem item) {
    final theme = Theme.of(context);
    final diff = item.date.difference(_day(DateTime.now())).inDays;
    late final String label;
    late final Color color;
    if (diff < 0) {
      label = tr(context, 'dues_overdue').replaceAll('{n}', '${-diff}');
      color = theme.colorScheme.error;
    } else if (diff == 0) {
      label = tr(context, 'dues_today');
      color = theme.colorScheme.error;
    } else if (diff <= 3) {
      label = tr(context, 'dues_days_left').replaceAll('{n}', '$diff');
      color = Colors.orange;
    } else {
      label = tr(context, 'dues_days_left').replaceAll('{n}', '$diff');
      color = theme.disabledColor;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'dues_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header: total due this month.
                  StaggeredEntrance(
                    child: Card(
                      color: kDeepGreen,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 18),
                        child: Row(
                          children: [
                            const Icon(Icons.event_note_outlined,
                                color: kGold, size: 30),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr(context, 'dues_total_month'),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color: Colors.white70,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatMoney(_totalDueThisMonth()),
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                      color: kGold,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Column(
                        children: [
                          const Text('🎉', style: TextStyle(fontSize: 52)),
                          const SizedBox(height: 12),
                          Text(
                            tr(context, 'dues_empty'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(context, 'dues_empty_sub'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.disabledColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return StaggeredEntrance(
                          key: ValueKey(
                              'due-$i-${item.kind}-${item.title}'),
                          delayMs: (i * 60).clamp(0, 600).toInt(),
                          child: Card(
                            child: ListTile(
                              leading: Text(
                                _kindIcon(item.kind),
                                style: const TextStyle(fontSize: 26),
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${tr(context, 'dues_kind_${item.kind}')} • '
                                '${DateFormat('d MMM y').format(item.date)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatMoney(item.amount),
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _badge(context, item),
                                ],
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => _open(item.kind)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
