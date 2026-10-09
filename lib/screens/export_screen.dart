import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../theme/design_tokens.dart';
import '../utils/formatters.dart';

/// Export hub: pick a month and export as PDF, Excel, CSV,
/// or the branded monthly statement.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;
  String? _busyKind;

  Future<void> _pickMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => _MonthPickerDialog(initial: _month),
    );
    if (picked != null && mounted) {
      setState(() => _month = picked);
    }
  }

  Future<void> _export(String kind) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyKind = kind;
    });
    try {
      switch (kind) {
        case 'pdf':
          await ExportService.exportMonthlyPdf(context, _month);
          break;
        case 'excel':
          await ExportService.exportMonthlyExcel(context, _month);
          break;
        case 'csv':
          await ExportService.exportMonthlyCsv(context, _month);
          break;
        case 'statement':
          await ExportService.exportFancyStatement(context, _month);
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'export_done'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'export_failed'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyKind = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final monthLabel = monthLong(_month, lang);

    Widget tile({
      required IconData icon,
      required String titleKey,
      required String subKey,
      required String kind,
    }) {
      final loading = _busy && _busyKind == kind;
      return ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon,
                  color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(tr(context, titleKey)),
        subtitle: Text(tr(context, subKey)),
        trailing: const Icon(Icons.chevron_right),
        onTap: loading ? null : () => _export(kind),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'export_title'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          KIOS.groupedSection(
            context,
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.calendar_month_outlined,
                      color: Theme.of(context).colorScheme.primary),
                ),
                title: Text(tr(context, 'export_pick_month')),
                subtitle: Text(monthLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _pickMonth,
              ),
            ],
          ),
          const SizedBox(height: 16),
          KIOS.groupedSection(
            context,
            children: [
              tile(
                icon: Icons.picture_as_pdf_outlined,
                titleKey: 'export_pdf',
                subKey: 'export_pdf_sub',
                kind: 'pdf',
              ),
              tile(
                icon: Icons.table_chart_outlined,
                titleKey: 'export_excel',
                subKey: 'export_excel_sub',
                kind: 'excel',
              ),
              tile(
                icon: Icons.text_snippet_outlined,
                titleKey: 'export_csv',
                subKey: 'export_csv_sub',
                kind: 'csv',
              ),
              tile(
                icon: Icons.receipt_long_outlined,
                titleKey: 'export_statement',
                subKey: 'export_statement_sub',
                kind: 'statement',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Simple month picker: year stepper + 12-month grid.
class _MonthPickerDialog extends StatefulWidget {
  final DateTime initial;

  const _MonthPickerDialog({required this.initial});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final now = DateTime.now();

    return AlertDialog(
      title: Text(tr(context, 'export_pick_month')),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _year--),
                ),
                Text('$_year',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _year >= now.year
                      ? null
                      : () => setState(() => _year++),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (ctx, i) {
                final m = i + 1;
                final isFuture =
                    _year > now.year || (_year == now.year && m > now.month);
                final selected = _year == widget.initial.year &&
                    m == widget.initial.month;
                return OutlinedButton(
                  onPressed: isFuture
                      ? null
                      : () => Navigator.of(ctx)
                          .pop(DateTime(_year, m)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15)
                        : null,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    monthShort(DateTime(_year, m), lang),
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
      ],
    );
  }
}
