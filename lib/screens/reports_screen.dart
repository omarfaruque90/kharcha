import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final months = provider.last6Months();
    final maxBar = months.fold<double>(
      0,
      (m, e) => e.total > m ? e.total : m,
    );
    final maxY = maxBar <= 0 ? 100.0 : maxBar * 1.2;

    final catTotals = provider.totalsByCategory(_selectedMonth);
    final sortedCats = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final monthTotal = catTotals.values.fold(0.0, (a, b) => a + b);

    final now = DateTime.now();
    final monthOptions =
        List.generate(12, (i) => DateTime(now.year, now.month - i));

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'nav_reports'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          StaggeredEntrance(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'last_6_months'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          maxY: maxY,
                          barTouchData: BarTouchData(enabled: false),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                          show: true,
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 52,
                              interval: maxY / 4,
                              getTitlesWidget: (value, meta) => Padding(
                                padding:
                                    const EdgeInsets.only(right: 8),
                                child: Text(
                                  formatCompact(value),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= months.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    monthShort(months[i].month, lang),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < months.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: months[i].total,
                                  width: 22,
                                  borderRadius:
                                      const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                  ),
                                  color: scheme.primary,
                                ),
                              ],
                            ),
                        ],
                      ),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            delayMs: 120,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(context, 'by_category'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DropdownButton<DateTime>(
                          value: _selectedMonth,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final m in monthOptions)
                              DropdownMenuItem(
                                value: m,
                                child: Text(monthLong(m, lang)),
                              ),
                          ],
                          onChanged: (m) {
                            if (m != null) {
                              setState(() => _selectedMonth = m);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slide,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        '${tr(context, 'month_total')}: ${formatMoney(monthTotal)}',
                        key: ValueKey(_selectedMonth),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (sortedCats.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text(tr(context, 'no_data'))),
                    )
                  else ...[
                    TweenAnimationBuilder<double>(
                      key: ValueKey(_selectedMonth),
                      tween: Tween(begin: 0.94, end: 1.0),
                      duration: const Duration(milliseconds: 550),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) => Transform.scale(
                        scale: value,
                        child: child,
                      ),
                      child: SizedBox(
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 36,
                            sections: [
                              for (final e in sortedCats)
                                PieChartSectionData(
                                  value: e.value,
                                  color: categoryById(e.key).color,
                                  title:
                                      '${(e.value / monthTotal * 100).toStringAsFixed(0)}%',
                                  radius: 62,
                                  titleStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeInOutCubic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var li = 0; li < sortedCats.length; li++)
                      StaggeredEntrance(
                        key: ValueKey(
                            '${_selectedMonth.millisecondsSinceEpoch}-${sortedCats[li].key}'),
                        delayMs: (li * 40).clamp(0, 200).toInt(),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: categoryById(sortedCats[li].key).color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                categoryById(sortedCats[li].key).icon,
                                size: 16,
                                color: categoryById(sortedCats[li].key).color,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  AppStrings.categoryName(
                                      sortedCats[li].key, lang),
                                ),
                              ),
                              Text(
                                formatMoney(sortedCats[li].value),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}
