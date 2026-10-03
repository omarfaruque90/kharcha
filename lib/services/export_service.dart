import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/expense.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';

/// Monthly expense export: PDF (printable table) and Excel (.xlsx),
/// shared via the platform share sheet.
class ExportService {
  /// Bundled Bengali font — stock PDF fonts (Helvetica) have no Bengali
  /// glyphs, so Bangla category names would render as boxes without it.
  static Future<pw.Font?> _bengaliFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansBengali.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Expense>> _monthExpenses(DateTime month) async {
    final all = await DatabaseHelper.instance.getAllExpenses();
    final rows = all
        .where((e) =>
            e.date.year == month.year && e.date.month == month.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  static String _fileBase(DateTime month) {
    final m = month.month.toString().padLeft(2, '0');
    return 'kharcha-${month.year}-$m';
  }

  static String _dateStr(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static Future<void> exportMonthlyPdf(
      BuildContext context, DateTime month) async {
    final lang =
        Provider.of<SettingsProvider>(context, listen: false).language;
    final rows = await _monthExpenses(month);
    final font = await _bengaliFont();
    final baseStyle = pw.TextStyle(font: font, fontSize: 9);
    final headerStyle = pw.TextStyle(
      font: font,
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
    );
    final titleStyle = pw.TextStyle(
      font: font,
      fontSize: 18,
      fontWeight: pw.FontWeight.bold,
    );
    final total = rows.fold<double>(0, (s, e) => s + e.amount);
    final monthLabel = monthLong(month, lang);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text('Kharcha — $monthLabel', style: titleStyle),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              AppStrings.get('date', lang),
              AppStrings.get('category', lang),
              AppStrings.get('amount', lang),
              AppStrings.get('payment_method', lang),
              AppStrings.get('note', lang),
            ],
            data: [
              for (final e in rows)
                [
                  _dateStr(e.date),
                  AppStrings.categoryName(e.categoryId, lang),
                  e.amount.toStringAsFixed(0),
                  AppStrings.paymentName(e.paymentMethod, lang),
                  e.note,
                ],
            ],
            headerStyle: headerStyle,
            cellStyle: baseStyle,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '${AppStrings.get('month_total', lang)}: ${formatMoney(total)}',
            style: headerStyle,
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${_fileBase(month)}.pdf'));
    await file.writeAsBytes(await doc.save());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Kharcha — $monthLabel',
    );
  }

  static Future<void> exportMonthlyExcel(
      BuildContext context, DateTime month) async {
    final lang =
        Provider.of<SettingsProvider>(context, listen: false).language;
    final rows = await _monthExpenses(month);
    final total = rows.fold<double>(0, (s, e) => s + e.amount);
    final monthLabel = monthLong(month, lang);

    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    final headers = [
      AppStrings.get('date', lang),
      AppStrings.get('category', lang),
      AppStrings.get('amount', lang),
      AppStrings.get('payment_method', lang),
      AppStrings.get('note', lang),
    ];
    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }
    var r = 1;
    for (final e in rows) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(_dateStr(e.date));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = TextCellValue(AppStrings.categoryName(e.categoryId, lang));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = DoubleCellValue(e.amount);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = TextCellValue(AppStrings.paymentName(e.paymentMethod, lang));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = TextCellValue(e.note);
      r++;
    }
    // Totals row.
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
        .value = TextCellValue(AppStrings.get('month_total', lang));
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
        .value = DoubleCellValue(total);

    final bytes = excel.save();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${_fileBase(month)}.xlsx'));
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Kharcha — $monthLabel',
    );
  }
}
