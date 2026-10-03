import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/fuel_log.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Fuel log (Package AM): records fill-ups, computes average mileage
/// (km/L) from odometer deltas between consecutive fill-ups, and shows
/// this month's total fuel cost.
///
/// Dialog fields: date, liters, price/L (total auto = liters × price/L),
/// odometer, note. Cards list fill-ups newest-first with delete.
class FuelScreen extends StatefulWidget {
  const FuelScreen({super.key});

  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen> {
  List<FuelLog> _logs = [];
  bool _loading = true;

  /// Stats memoized at load time: the mileage/month-cost scan is O(n log n)
  /// and must not rerun on every build (e.g. each dialog close / setState).
  double? _avgMileage;
  double _monthCost = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final logs = await DatabaseHelper.instance.getFuelLogs();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _recomputeStats();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Recomputes [_avgMileage] and [_monthCost] from [_logs].
  void _recomputeStats() {
    final sorted = [..._logs]..sort((a, b) => a.date.compareTo(b.date));
    double dist = 0, liters = 0;
    for (var i = 1; i < sorted.length; i++) {
      final delta = sorted[i].odometer - sorted[i - 1].odometer;
      if (delta > 0 && sorted[i].liters > 0) {
        dist += delta;
        liters += sorted[i].liters;
      }
    }
    _avgMileage = liters > 0 ? dist / liters : null;
    final now = DateTime.now();
    _monthCost = _logs
        .where((l) => l.date.year == now.year && l.date.month == now.month)
        .fold(0.0, (s, l) => s + l.total);
  }

  Future<void> _confirmDelete(FuelLog log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'fuel_delete_title')),
        content: Text(tr(ctx, 'fuel_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok == true && log.id != null) {
      await DatabaseHelper.instance.deleteFuelLog(log.id!);
      await _reload();
    }
  }

  Future<void> _showAddDialog() async {
    final dateCtrl = _DateField(initial: DateTime.now());
    final litersCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final totalCtrl = TextEditingController();
    final odoCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    void recompute() {
      final l = double.tryParse(litersCtrl.text.trim());
      final p = double.tryParse(priceCtrl.text.trim());
      if (l != null && p != null) {
        totalCtrl.text = (l * p).toStringAsFixed(2);
      }
    }

    litersCtrl.addListener(recompute);
    priceCtrl.addListener(recompute);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr(ctx, 'fuel_new_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: dateCtrl.date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => dateCtrl.date = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    _fmtDate(context, dateCtrl.date),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: litersCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'fuel_liters'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'fuel_price_liter'),
                    prefixText: '৳ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: totalCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'fuel_total'),
                    prefixText: '৳ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: odoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'fuel_odometer'),
                    suffixText: 'km',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'note'),
                    hintText: tr(ctx, 'note_hint'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr(ctx, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr(ctx, 'save')),
            ),
          ],
        ),
      ),
    );

    litersCtrl.removeListener(recompute);
    priceCtrl.removeListener(recompute);
    void disposeCtrls() {
      litersCtrl.dispose();
      priceCtrl.dispose();
      totalCtrl.dispose();
      odoCtrl.dispose();
      noteCtrl.dispose();
    }

    if (result != true) {
      disposeCtrls();
      return;
    }
    final liters = double.tryParse(litersCtrl.text.trim());
    final price = double.tryParse(priceCtrl.text.trim());
    final odo = double.tryParse(odoCtrl.text.trim()) ?? 0;
    if (liters == null || liters <= 0 || price == null || price <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'fuel_invalid'))),
      );
      disposeCtrls();
      return;
    }
    await DatabaseHelper.instance.insertFuelLog(
      FuelLog(
        id: FuelLog.newId(),
        date: dateCtrl.date,
        liters: liters,
        pricePerLiter: price,
        total: liters * price,
        odometer: odo,
        note: noteCtrl.text.trim(),
      ),
    );
    await _reload();
    disposeCtrls();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final sorted = [..._logs]..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'fuel_title'))),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: tr(context, 'fuel_new_title'),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              // Index 0 = stats header; the rest are the fill-up cards
              // (or a single empty-state row when there are no logs).
              itemCount: sorted.isEmpty ? 2 : sorted.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StaggeredEntrance(
                      child: _StatsCard(
                        dark: dark,
                        avgMileage: _avgMileage,
                        monthCost: _monthCost,
                      ),
                    ),
                  );
                }
                if (sorted.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      tr(context, 'fuel_empty'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  );
                }
                final log = sorted[i - 1];
                return StaggeredEntrance(
                  delayMs: (80 + (i - 1) * 40).clamp(0, 480).toInt(),
                  child: _FuelCard(
                    log: log,
                    dark: dark,
                    onDelete: () => _confirmDelete(log),
                  ),
                );
              },
            ),
    );
  }
}

/// Locale-aware short date (yMMMd), same convention as debts/home screens.
String _fmtDate(BuildContext context, DateTime d) {
  final lang = context.read<SettingsProvider>().language;
  return DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(d);
}

class _DateField {
  DateTime date;
  _DateField({required this.date});
}

/// Stats card: average mileage (km/L) + this month's fuel cost.
class _StatsCard extends StatelessWidget {
  final bool dark;
  final double? avgMileage;
  final double monthCost;

  const _StatsCard({
    required this.dark,
    required this.avgMileage,
    required this.monthCost,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = dark ? kGoldLight : kGoldDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? kDeepGreenCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              theme: theme,
              accent: accent,
              label: tr(context, 'fuel_avg_mileage'),
              value: avgMileage == null
                  ? '—'
                  : '${avgMileage!.toStringAsFixed(1)} ${tr(context, 'fuel_km_l')}',
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          Expanded(
            child: _Stat(
              theme: theme,
              accent: accent,
              label: tr(context, 'fuel_month_cost'),
              value: formatMoney(monthCost),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final ThemeData theme;
  final Color accent;
  final String label;
  final String value;

  const _Stat({
    required this.theme,
    required this.accent,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: accent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// One fill-up card: date, liters, total, odometer; delete button.
class _FuelCard extends StatelessWidget {
  final FuelLog log;
  final bool dark;
  final VoidCallback onDelete;

  const _FuelCard({
    required this.log,
    required this.dark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? kDeepGreenCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_gas_station_outlined,
                color: kGold, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtDate(context, log.date),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${log.liters.toStringAsFixed(2)} L · ${formatMoney(log.total)}'
                  '${log.odometer > 0 ? ' · ${log.odometer.toStringAsFixed(0)} km' : ''}'
                  '${log.note.isNotEmpty ? ' · ${log.note}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: theme.colorScheme.error,
            tooltip: tr(context, 'delete'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
