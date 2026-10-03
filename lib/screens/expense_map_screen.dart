import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Expense map (Package AZ): shows expenses that carry a lat/lng on an
/// OpenStreetMap tile layer. Marker size scales with the amount; tapping a
/// marker opens a bottom sheet with amount / category / date. The coordinator
/// wires the "add location" button into the add-expense screen.
class ExpenseMapScreen extends StatefulWidget {
  const ExpenseMapScreen({super.key});

  @override
  State<ExpenseMapScreen> createState() => _ExpenseMapScreenState();
}

class _Pin {
  final Expense expense;
  final LatLng point;
  const _Pin(this.expense, this.point);
}

class _ExpenseMapScreenState extends State<ExpenseMapScreen> {
  late final Future<List<_Pin>> _future = _loadPins();

  Future<List<_Pin>> _loadPins() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT * FROM expenses WHERE lat IS NOT NULL AND lng IS NOT NULL '
      'ORDER BY date DESC',
    );
    final pins = <_Pin>[];
    for (final r in rows) {
      final lat = (r['lat'] as num?)?.toDouble();
      final lng = (r['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      try {
        pins.add(_Pin(Expense.fromMap(r), LatLng(lat, lng)));
      } catch (_) {
        // Skip malformed rows rather than breaking the map.
      }
    }
    return pins;
  }

  /// Marker diameter scales with the amount: 24 + amount/500, clamped 24..64.
  double _markerSize(double amount) =>
      (24 + amount / 500).clamp(24.0, 64.0);

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'expense_map_title')),
      ),
      body: FutureBuilder<List<_Pin>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final pins = snapshot.data ?? const <_Pin>[];
          if (pins.isEmpty) return _emptyState(context);
          final center = pins.first.point;
          return FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kharcha.app',
              ),
              MarkerLayer(
                markers: [
                  for (final pin in pins)
                    Marker(
                      point: pin.point,
                      width: _markerSize(
                          pin.expense.bdtAmount ?? pin.expense.amount),
                      height: _markerSize(
                          pin.expense.bdtAmount ?? pin.expense.amount),
                      child: GestureDetector(
                        onTap: () => _showExpenseSheet(
                            context, pin.expense, lang),
                        child: const _PinDot(),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return StaggeredEntrance(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 64, color: kGold),
              const SizedBox(height: 16),
              Text(
                tr(context, 'expense_map_empty'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'expense_map_empty_sub'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExpenseSheet(
      BuildContext context, Expense expense, String lang) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM y, h:mm a', lang == 'bn' ? 'bn' : 'en');
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on, color: kGold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    formatMoney(expense.bdtAmount ?? expense.amount),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SheetRow(
              icon: Icons.category_outlined,
              text: CustomCategoryRegistry.displayName(
                  expense.categoryId, lang),
            ),
            const SizedBox(height: 8),
            _SheetRow(
              icon: Icons.calendar_today_outlined,
              text: fmt.format(expense.date),
            ),
            if (expense.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SheetRow(
                icon: Icons.note_outlined,
                text: expense.note,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gold circle pin with a ৳ glyph. Sized by its parent [Marker].
class _PinDot extends StatelessWidget {
  const _PinDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kGold,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: FittedBox(
          child: Text(
            '৳',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SheetRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}
