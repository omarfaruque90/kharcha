import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// On-device spending insights card for the home screen.
///
/// Computes five simple signals from [ExpenseProvider] in a single pass
/// over the expense list and shows up to three of them (priority order:
/// category spike, rising spending, top category, biggest expense, daily
/// average). Returns [SizedBox.shrink] when there is nothing to show.
class SpendingInsights extends StatelessWidget {
  const SpendingInsights({super.key});

  @override
  Widget build(BuildContext context) {
    final expenses = context.watch<ExpenseProvider>().expenses;
    final lang = context.watch<SettingsProvider>().language;

    final insights = _compute(context, expenses, lang);
    if (insights.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return StaggeredEntrance(
      delayMs: 150,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: kGold, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'insights_title'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final insight in insights)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(insight.icon, size: 17, color: kGoldDark),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          insight.text,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One computed insight row.
  List<_Insight> _compute(
    BuildContext context,
    List<Expense> expenses,
    String lang,
  ) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(now.year, now.month - 1);

    // Single pass: totals, per-category totals and biggest expense
    // for this month and last month.
    double thisTotal = 0;
    double lastTotal = 0;
    final thisByCat = <String, double>{};
    final lastByCat = <String, double>{};
    Expense? biggest;

    for (final e in expenses) {
      if (e.date.year == thisMonth.year && e.date.month == thisMonth.month) {
        thisTotal += e.amount;
        thisByCat[e.categoryId] = (thisByCat[e.categoryId] ?? 0) + e.amount;
        if (biggest == null || e.amount > biggest.amount) biggest = e;
      } else if (e.date.year == lastMonth.year &&
          e.date.month == lastMonth.month) {
        lastTotal += e.amount;
        lastByCat[e.categoryId] = (lastByCat[e.categoryId] ?? 0) + e.amount;
      }
    }

    if (thisTotal == 0) return const [];

    String catName(String id) => CustomCategoryRegistry.displayName(id, lang);
    String sub(String key, Map<String, String> vars) {
      var s = tr(context, key);
      vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
      return s;
    }

    final insights = <_Insight>[];

    // Rule 2: categories with >25% increase vs last month (last month > 0).
    final spikes = <_Insight>[];
    thisByCat.forEach((id, amount) {
      final prev = lastByCat[id] ?? 0;
      if (prev > 0) {
        final pct = ((amount - prev) / prev * 100).round();
        if (pct > 25) {
          spikes.add(_Insight(
            Icons.warning_amber_rounded,
            sub('insights_rise', {
              'cat': catName(id),
              'pct': pct.toString(),
            }),
          ));
        }
      }
    });

    // Rule 4: spending rising vs last month.
    _Insight? rising;
    if (thisTotal > lastTotal && lastTotal > 0) {
      rising = _Insight(
        Icons.trending_up,
        tr(context, 'insights_rising'),
      );
    }

    // Rule 1: top category this month with share of total.
    _Insight? topCat;
    if (thisByCat.isNotEmpty) {
      final top = thisByCat.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      final share = (top.value / thisTotal * 100).round();
      topCat = _Insight(
        Icons.emoji_events_outlined,
        sub('insights_top', {
          'cat': catName(top.key),
          'money': formatMoney(top.value),
          'pct': share.toString(),
        }),
      );
    }

    // Rule 5: biggest single expense this month.
    _Insight? biggestRow;
    if (biggest != null) {
      biggestRow = _Insight(
        Icons.receipt_long_outlined,
        sub('insights_biggest', {
          'money': formatMoney(biggest.amount),
          'cat': catName(biggest.categoryId),
        }),
      );
    }

    // Rule 3: daily average this month.
    final dailyAvg = _Insight(
      Icons.calendar_today_outlined,
      sub('insights_daily_avg', {
        'money': formatMoney(thisTotal / now.day),
      }),
    );

    // Priority: 2, 4, 1, 5, 3 — max 3 shown.
    insights
      ..addAll(spikes)
      ..addIf(rising)
      ..addIf(topCat)
      ..addIf(biggestRow)
      ..add(dailyAvg);

    return insights.take(3).toList();
  }
}

/// A single insight row: icon + one-line text.
class _Insight {
  final IconData icon;
  final String text;

  const _Insight(this.icon, this.text);
}

extension on List<_Insight> {
  void addIf(_Insight? insight) {
    if (insight != null) add(insight);
  }
}
