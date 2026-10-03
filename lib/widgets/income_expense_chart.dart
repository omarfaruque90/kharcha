import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';

/// Package BK: income-vs-expense comparison chart.
///
/// Last 6 calendar months, income (green) and expense (red) bars
/// side-by-side per month. Handles empty data gracefully.
class IncomeExpenseChart extends StatelessWidget {
  const IncomeExpenseChart({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<SettingsProvider>().language;
    final expenses = context.watch<ExpenseProvider>();
    final money = context.watch<MoneyProvider>();

    final months = expenses.last6Months();
    final incomes = months
        .map((m) => money.incomeForMonth(monthKeyOf(m.month)))
        .toList(growable: false);
    final spent =
        months.map((m) => m.total).toList(growable: false);

    final maxValue = [
      for (var i = 0; i < months.length; i++) incomes[i],
      for (var i = 0; i < months.length; i++) spent[i],
    ].fold(0.0, (a, b) => a > b ? a : b);
    final hasData = maxValue > 0;
    final maxY = hasData ? maxValue * 1.15 : 1.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'income_expense_title'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _Legend(theme: theme),
            const SizedBox(height: 12),
            if (!hasData)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    tr(context, 'no_data'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
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
                            padding: const EdgeInsets.only(right: 8),
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
                          barsSpace: 4,
                          barRods: [
                            BarChartRodData(
                              toY: incomes[i],
                              width: 12,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                              color: const Color(0xFF10B981),
                            ),
                            BarChartRodData(
                              toY: spent[i],
                              width: 12,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                              color: const Color(0xFFEF4444),
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
    );
  }
}

class _Legend extends StatelessWidget {
  final ThemeData theme;

  const _Legend({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _swatch(const Color(0xFF10B981)),
        const SizedBox(width: 6),
        Text(
          tr(context, 'income_title'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(width: 16),
        _swatch(const Color(0xFFEF4444)),
        const SizedBox(width: 6),
        Text(
          tr(context, 'expense_legend'),
          style: theme.textTheme.bodySmall,
        ),
        const Spacer(),
      ],
    );
  }

  Widget _swatch(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
