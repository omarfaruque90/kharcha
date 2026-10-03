import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../services/share_summary_service.dart';
import '../widgets/income_expense_chart.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _selectedMonth;

  /// Package AK: expense comparison — this month vs last month.
  bool _compareMode = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  /// Deletes all expenses of the selected month after double confirm.
  /// For cleaning up test/try entries.
  Future<void> _confirmClearMonth(BuildContext context) async {
    final lang = context.read<SettingsProvider>().language;
    final provider = context.read<ExpenseProvider>();
    final count = provider.expenses
        .where((e) =>
            e.date.year == _selectedMonth.year &&
            e.date.month == _selectedMonth.month)
        .length;
    if (count == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'clear_nothing'))),
        );
      }
      return;
    }
    final monthName = DateFormat.yMMM(lang == 'bn' ? 'bn' : 'en')
        .format(_selectedMonth);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(dctx).colorScheme.error, size: 32),
        title: Text(tr(dctx, 'clear_month_title')),
        content: Text(
          tr(dctx, 'clear_month_msg')
              .replaceAll('{n}', '$count')
              .replaceAll('{m}', monthName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(tr(dctx, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
              foregroundColor: Theme.of(dctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(tr(dctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final removed = await provider.removeForMonth(_selectedMonth);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'clear_done')
              .replaceAll('{n}', '$removed')),
        ),
      );
    }
  }

  /// Deletes one category's expenses of the selected month after confirm.
  Future<void> _confirmClearCategory(
      BuildContext context, String categoryId) async {
    final provider = context.read<ExpenseProvider>();
    final name =
        CustomCategoryRegistry.displayName(categoryId, context.read<SettingsProvider>().language);
    final count = provider.expenses
        .where((e) =>
            e.categoryId == categoryId &&
            e.date.year == _selectedMonth.year &&
            e.date.month == _selectedMonth.month)
        .length;
    if (count == 0 || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'clear_cat_title')),
        content: Text(tr(dctx, 'clear_cat_msg')
            .replaceAll('{n}', '$count')
            .replaceAll('{c}', name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(tr(dctx, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
              foregroundColor: Theme.of(dctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(tr(dctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final removed =
        await provider.removeForCategoryMonth(categoryId, _selectedMonth);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              tr(context, 'clear_done').replaceAll('{n}', '$removed')),
        ),
      );
    }
  }

  /// Package U: build year aggregates and open the shareable review card.
  void _showYearReview() {
    final expenses = context.read<ExpenseProvider>();
    final money = context.read<MoneyProvider>();
    final lang = context.read<SettingsProvider>().language;
    final stats = _computeYearStats(expenses, money);
    final cardKey = GlobalKey();

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: kDeepGreenDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: cardKey,
                child: _YearReviewCard(stats: stats, lang: lang),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGold,
                        foregroundColor: kDeepGreenDark,
                      ),
                      onPressed: () =>
                          _shareYearCard(dialogCtx, cardKey, stats, lang),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(_ytr(lang, 'yr_share')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: Text(
                      _ytr(lang, 'yr_close'),
                      style: const TextStyle(color: kGoldLight),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Package U: capture the card and hand it to the system share sheet.
  Future<void> _shareYearCard(
    BuildContext ctx,
    GlobalKey cardKey,
    _YearStats stats,
    String lang,
  ) async {
    try {
      final boundary = cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('card render object unavailable');
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('toByteData returned null');
      }
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/khorcha_year_${stats.year}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Khorcha ${stats.year}',
        ),
      );
    } catch (_) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(_ytr(lang, 'yr_share_fail'))),
        );
      }
    }
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
      appBar: AppBar(
        title: Text(tr(context, 'nav_reports')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr(context, 'share_title'),
            onPressed: () => ShareSummaryService.shareMonthSummary(
              context,
              _selectedMonth,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: tr(context, 'clear_data'),
            onSelected: (v) {
              if (v == 'clear_month') _confirmClearMonth(context);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'clear_month',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined,
                        color: theme.colorScheme.error, size: 20),
                    const SizedBox(width: 10),
                    Text(tr(context, 'clear_month_data')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Package U: Year in review — always visible gold button.
          StaggeredEntrance(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: kDeepGreenDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _showYearReview,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  _ytr(lang, 'yr_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // BK: income vs expense chart (last 6 months).
          const StaggeredEntrance(
            child: IncomeExpenseChart(),
          ),
          const SizedBox(height: 12),
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
            delayMs: 60,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'export_title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                ExportService.exportMonthlyPdf(
                              context,
                              _selectedMonth,
                            ),
                            icon: const Icon(
                                Icons.picture_as_pdf_outlined),
                            label: Text(tr(context, 'export_pdf')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                ExportService.exportMonthlyExcel(
                              context,
                              _selectedMonth,
                            ),
                            icon:
                                const Icon(Icons.table_chart_outlined),
                            label: Text(tr(context, 'export_excel')),
                          ),
                        ),
                      ],
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
                        // Package AK: compare toggle (this month vs last month).
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                          ),
                          onPressed: () => setState(
                              () => _compareMode = !_compareMode),
                          icon: Icon(
                            Icons.compare_arrows,
                            size: 18,
                            color: _compareMode
                                ? kGold
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          label: Text(
                            _ctr(lang, 'cmp_compare'),
                            style: TextStyle(
                              color: _compareMode
                                  ? kGold
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: _compareMode
                                  ? FontWeight.bold
                                  : FontWeight.normal,
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
                  // Package AK: compare mode replaces the pie + legend
                  // with this-month vs last-month bars per category.
                  if (_compareMode)
                    _buildCompareView(
                      context,
                      provider,
                      lang,
                      theme,
                      catTotals,
                      monthTotal,
                    )
                  else if (sortedCats.isEmpty)
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
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onLongPress: () => _confirmClearCategory(
                                context, sortedCats[li].key),
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
                                  CustomCategoryRegistry.displayName(
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
                      ),
                  ],
                ],
              ),
            ),
          ),
          ),
          // Package AB: mood insights — skip entirely when no moods recorded.
          const SizedBox(height: 12),
          _buildMoodInsightCard(context, provider, lang, theme),
        ],
      ),
    );
  }

  /// Package AB: "Mood insights" card. Computes average spend per mood tag
  /// (in BDT) for the selected month and shows the mood with the highest
  /// average plus a fun line. Returns an empty box when nothing is recorded.
  Widget _buildMoodInsightCard(
    BuildContext context,
    ExpenseProvider provider,
    String lang,
    ThemeData theme,
  ) {
    final moodTotals = <String, double>{};
    final moodCounts = <String, int>{};
    for (final e in provider.expenses) {
      if (e.date.year != _selectedMonth.year ||
          e.date.month != _selectedMonth.month ||
          e.mood.isEmpty) {
        continue;
      }
      final bdt = e.bdtAmount ?? e.amount;
      moodTotals[e.mood] = (moodTotals[e.mood] ?? 0) + bdt;
      moodCounts[e.mood] = (moodCounts[e.mood] ?? 0) + 1;
    }
    if (moodTotals.isEmpty) return const SizedBox.shrink();

    var topMood = '';
    var topAvg = 0.0;
    for (final entry in moodTotals.entries) {
      final avg = entry.value / (moodCounts[entry.key] ?? 1);
      if (avg > topAvg) {
        topAvg = avg;
        topMood = entry.key;
      }
    }

    final line = tr(context, 'mood_insight_high')
        .replaceAll('{mood}', topMood);

    return StaggeredEntrance(
      delayMs: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'mood_insights'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kGold.withValues(alpha: 0.12),
                      border: Border.all(
                        color: kGold.withValues(alpha: 0.6),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      topMood,
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tr(context, 'mood_avg_spend')}: '
                          '${formatMoney(topAvg)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Package AK: expense comparison — selected month vs the previous month.
  // Reuses ExpenseProvider.totalsByCategory for both months.
  // -------------------------------------------------------------------------

  /// Side-by-side horizontal bars per category (gold = this month,
  /// grey = last month) plus a total delta line.
  Widget _buildCompareView(
    BuildContext context,
    ExpenseProvider provider,
    String lang,
    ThemeData theme,
    Map<String, double> catTotals,
    double monthTotal,
  ) {
    final prevMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    final prevTotals = provider.totalsByCategory(prevMonth);
    final prevTotal = prevTotals.values.fold(0.0, (a, b) => a + b);
    final delta = monthTotal - prevTotal;

    final ids = {...catTotals.keys, ...prevTotals.keys}.toList()
      ..sort(
          (a, b) => (catTotals[b] ?? 0).compareTo(catTotals[a] ?? 0));
    var maxV = 0.0;
    for (final id in ids) {
      final m = (catTotals[id] ?? 0) > (prevTotals[id] ?? 0)
          ? (catTotals[id] ?? 0)
          : (prevTotals[id] ?? 0);
      if (m > maxV) maxV = m;
    }

    // Spending more than last month is worse → red; less → green.
    final deltaColor = delta > 0
        ? Colors.red
        : delta < 0
            ? Colors.green
            : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              delta >= 0 ? Icons.trending_up : Icons.trending_down,
              size: 18,
              color: deltaColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${delta >= 0 ? '+' : '−'}${formatMoney(delta.abs())} '
                '${_ctr(lang, 'cmp_vs_last_month')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: deltaColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _cmpLegendDot(kGold),
            const SizedBox(width: 6),
            Text(
              _ctr(lang, 'cmp_this_month'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 16),
            _cmpLegendDot(Colors.grey),
            const SizedBox(width: 6),
            Text(
              _ctr(lang, 'cmp_last_month'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (ids.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(tr(context, 'no_data'))),
          )
        else
          for (var ci = 0; ci < ids.length; ci++)
            StaggeredEntrance(
              key: ValueKey(
                  'cmp-${_selectedMonth.millisecondsSinceEpoch}-${ids[ci]}'),
              delayMs: (ci * 40).clamp(0, 200).toInt(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          categoryById(ids[ci]).icon,
                          size: 16,
                          color: categoryById(ids[ci]).color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            CustomCategoryRegistry.displayName(
                                ids[ci], lang),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          formatMoney(catTotals[ids[ci]] ?? 0),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: kGold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatMoney(prevTotals[ids[ci]] ?? 0),
                          style: TextStyle(
                            color:
                                theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _cmpBar(catTotals[ids[ci]] ?? 0, maxV, kGold),
                    const SizedBox(height: 3),
                    _cmpBar(prevTotals[ids[ci]] ?? 0, maxV, Colors.grey),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _cmpLegendDot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );

  Widget _cmpBar(double value, double max, Color color) {
    final frac = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Package U: Year in review share card.
// NOTE: the keys below are proposed AppStrings keys — add them to
// lib/l10n/app_strings.dart ('en'/'bn' maps); the local map keeps the card
// working until then.
// ---------------------------------------------------------------------------
const Map<String, Map<String, String>> _yrStrings = {
  'en': {
    'yr_title': 'Year in review',
    'yr_brand': 'Khorcha',
    'yr_total_spent': 'Total spent',
    'yr_top_category': 'Top category',
    'yr_biggest_month': 'Biggest month',
    'yr_savings': 'Savings',
    'yr_of_spending': 'of spending',
    'yr_share': 'Share',
    'yr_close': 'Close',
    'yr_no_data': 'No expenses recorded this year yet.',
    'yr_share_fail': 'Could not create the share image.',
    'yr_tagline': 'Khorcha · Daily Expense Tracker',
  },
  'bn': {
    'yr_title': 'বছরের হিসাব',
    'yr_brand': 'খরচা',
    'yr_total_spent': 'মোট খরচ',
    'yr_top_category': 'সবচেয়ে বেশি খরচের খাত',
    'yr_biggest_month': 'সবচেয়ে বেশি খরচের মাস',
    'yr_savings': 'সঞ্চয়',
    'yr_of_spending': 'খরচের',
    'yr_share': 'শেয়ার করুন',
    'yr_close': 'বন্ধ করুন',
    'yr_no_data': 'এ বছর এখনো কোনো খরচ রেকর্ড হয়নি।',
    'yr_share_fail': 'শেয়ার ছবি তৈরি করা যায়নি।',
    'yr_tagline': 'খরচা · দৈনিক খরচ ট্র্যাকার',
  },
};

String _ytr(String lang, String key) =>
    _yrStrings[lang]?[key] ?? _yrStrings['en']![key] ?? key;

/// Year-level aggregates used by the review card.
class _YearStats {
  final int year;
  final double yearTotal;
  final String topCategoryId;
  final double topCategoryAmount;
  final int topCategoryPct;
  final int biggestMonth; // 1-12; 0 when no data
  final double biggestMonthTotal;
  final double savingsTotal;

  const _YearStats({
    required this.year,
    required this.yearTotal,
    required this.topCategoryId,
    required this.topCategoryAmount,
    required this.topCategoryPct,
    required this.biggestMonth,
    required this.biggestMonthTotal,
    required this.savingsTotal,
  });
}

/// Reuses ExpenseProvider.totalsByCategory for each month of the current year
/// and MoneyProvider.goals for the savings total.
_YearStats _computeYearStats(
  ExpenseProvider expenses,
  MoneyProvider money,
) {
  final year = DateTime.now().year;
  final catTotals = <String, double>{};
  final monthTotals = List<double>.filled(12, 0.0);
  var yearTotal = 0.0;

  for (var m = 1; m <= 12; m++) {
    for (final e in expenses.totalsByCategory(DateTime(year, m)).entries) {
      catTotals[e.key] = (catTotals[e.key] ?? 0) + e.value;
      monthTotals[m - 1] += e.value;
      yearTotal += e.value;
    }
  }

  var topId = '';
  var topAmt = 0.0;
  for (final e in catTotals.entries) {
    if (e.value > topAmt) {
      topAmt = e.value;
      topId = e.key;
    }
  }
  final pct = yearTotal > 0 ? (topAmt / yearTotal * 100).round() : 0;

  var bigMonth = 0;
  var bigAmt = 0.0;
  for (var i = 0; i < 12; i++) {
    if (monthTotals[i] > bigAmt) {
      bigAmt = monthTotals[i];
      bigMonth = i + 1;
    }
  }

  final savings =
      money.goals.fold(0.0, (sum, g) => sum + g.savedAmount);

  return _YearStats(
    year: year,
    yearTotal: yearTotal,
    topCategoryId: topId,
    topCategoryAmount: topAmt,
    topCategoryPct: pct,
    biggestMonth: bigMonth,
    biggestMonthTotal: bigAmt,
    savingsTotal: savings,
  );
}

/// Self-contained branded card captured by RepaintBoundary for sharing.
class _YearReviewCard extends StatelessWidget {
  final _YearStats stats;
  final String lang;

  const _YearReviewCard({required this.stats, required this.lang});

  @override
  Widget build(BuildContext context) {
    final hasData = stats.yearTotal > 0;
    final bigMonthLabel = stats.biggestMonth > 0
        ? monthLong(DateTime(stats.year, stats.biggestMonth), lang)
        : '—';
    final topName = stats.topCategoryId.isEmpty
        ? '—'
        : CustomCategoryRegistry.displayName(
            stats.topCategoryId, lang);

    return Container(
      width: 340,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kDeepGreenDark, kDeepGreen, kDeepGreenCard],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGold, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kGold, width: 2),
            ),
            alignment: Alignment.center,
            child: const Text(
              '৳',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: kGoldLight,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _ytr(lang, 'yr_brand'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: kGoldLight,
            ),
          ),
          Text(
            '${_ytr(lang, 'yr_title')} · ${stats.year}',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: kGold.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            _ytr(lang, 'yr_total_spent'),
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(stats.yearTotal),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          if (hasData) ...[
            _statRow(
              icon: Icons.star_outline,
              label: _ytr(lang, 'yr_top_category'),
              value:
                  '$topName · ${stats.topCategoryPct}% ${_ytr(lang, 'yr_of_spending')}',
            ),
            const SizedBox(height: 10),
            _statRow(
              icon: Icons.calendar_month_outlined,
              label: _ytr(lang, 'yr_biggest_month'),
              value:
                  '$bigMonthLabel · ${formatMoney(stats.biggestMonthTotal)}',
            ),
            const SizedBox(height: 10),
            _statRow(
              icon: Icons.savings_outlined,
              label: _ytr(lang, 'yr_savings'),
              value: formatMoney(stats.savingsTotal),
            ),
            const SizedBox(height: 16),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _ytr(lang, 'yr_no_data'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
            ),
          Container(height: 1, color: kGold.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          Text(
            _ytr(lang, 'yr_tagline'),
            style: const TextStyle(
              fontSize: 11,
              color: kGoldLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: kGold, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Package AK: Compare-mode strings.
// NOTE: the keys below are proposed AppStrings keys — add them to
// lib/l10n/app_strings.dart ('en'/'bn' maps); the local map keeps the view
// working until then. (Same pattern as Package U's _yrStrings.)
// ---------------------------------------------------------------------------
const Map<String, Map<String, String>> _cmpStrings = {
  'en': {
    'cmp_compare': 'Compare',
    'cmp_this_month': 'This month',
    'cmp_last_month': 'Last month',
    'cmp_vs_last_month': 'vs last month',
  },
  'bn': {
    'cmp_compare': 'তুলনা',
    'cmp_this_month': 'এই মাস',
    'cmp_last_month': 'গত মাস',
    'cmp_vs_last_month': 'গত মাসের তুলনায়',
  },
};

String _ctr(String lang, String key) =>
    _cmpStrings[lang]?[key] ?? _cmpStrings['en']![key] ?? key;
