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
import '../models/custom_category.dart';
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
          pw.Text('Khorcha — $monthLabel', style: titleStyle),
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
                  CustomCategoryRegistry.displayName(e.categoryId, lang),
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
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Khorcha — $monthLabel',
      ),
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
          .value = TextCellValue(CustomCategoryRegistry.displayName(e.categoryId, lang));
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
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Khorcha — $monthLabel',
      ),
    );
  }

  /// Monthly expense export as CSV (UTF-8 with BOM so Excel opens
  /// Bangla text correctly). No extra package needed.
  static Future<void> exportMonthlyCsv(
      BuildContext context, DateTime month) async {
    final lang =
        Provider.of<SettingsProvider>(context, listen: false).language;
    final rows = await _monthExpenses(month);
    final total = rows.fold<double>(0, (s, e) => s + e.amount);
    final monthLabel = monthLong(month, lang);

    String esc(String v) {
      // Quote fields containing comma, quote, or newline.
      if (v.contains(',') || v.contains('"') || v.contains('\n')) {
        return '"${v.replaceAll('"', '""')}"';
      }
      return v;
    }

    final buf = StringBuffer();
    // BOM for Excel Bangla support.
    buf.write('\uFEFF');
    buf.writeln([
      esc(AppStrings.get('date', lang)),
      esc(AppStrings.get('category', lang)),
      esc(AppStrings.get('amount', lang)),
      esc(AppStrings.get('payment_method', lang)),
      esc(AppStrings.get('note', lang)),
    ].join(','));
    for (final e in rows) {
      buf.writeln([
        _dateStr(e.date),
        esc(CustomCategoryRegistry.displayName(e.categoryId, lang)),
        e.amount.toString(),
        esc(AppStrings.paymentName(e.paymentMethod, lang)),
        esc(e.note),
      ].join(','));
    }
    buf.writeln([
      '',
      esc(AppStrings.get('month_total', lang)),
      total.toString(),
      '',
      '',
    ].join(','));

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${_fileBase(month)}.csv'));
    await file.writeAsString(buf.toString());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Khorcha — $monthLabel',
      ),
    );
  }

  /// Branded monthly statement PDF: deep-green header, income/expense/
  /// balance summary boxes, category breakdown bars and the full expense
  /// table. The plain [exportMonthlyPdf] stays as the lightweight fallback.
  static Future<void> exportFancyStatement(
      BuildContext context, DateTime month) async {
    final lang =
        Provider.of<SettingsProvider>(context, listen: false).language;
    final rows = await _monthExpenses(month);
    final incomes = (await DatabaseHelper.instance.getAllIncomes())
        .where((i) => i.date.year == month.year && i.date.month == month.month)
        .toList();

    final font = await _bengaliFont();
    // ৳ and Bengali glyphs need the bundled font; without it fall back to a
    // latin-safe format so amounts never render as tofu boxes.
    String money(double v) =>
        font != null ? formatMoney(v) : 'BDT ${v.toStringAsFixed(0)}';

    final totalExpense = rows.fold<double>(0, (s, e) => s + e.amount);
    final totalIncome = incomes.fold<double>(0, (s, i) => s + i.amount);
    final balance = totalIncome - totalExpense;
    final monthLabel = monthLong(month, lang);

    const deepGreen = PdfColor.fromInt(0xFF0B3D2E);
    const gold = PdfColor.fromInt(0xFFD4AF37);
    const goldDark = PdfColor.fromInt(0xFF9C7C1E);

    final titleStyle = pw.TextStyle(
      font: font,
      fontSize: 24,
      fontWeight: pw.FontWeight.bold,
      color: gold,
    );
    final monthStyle =
        pw.TextStyle(font: font, fontSize: 13, color: PdfColors.white);
    final sectionStyle = pw.TextStyle(
      font: font,
      fontSize: 13,
      fontWeight: pw.FontWeight.bold,
      color: deepGreen,
    );
    final baseStyle = pw.TextStyle(font: font, fontSize: 9);
    final headerStyle = pw.TextStyle(
      font: font,
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );

    pw.Widget summaryBox(
        String label, String value, PdfColor bg, PdfColor fg) {
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 8),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: bg,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(
                    font: font, fontSize: 9, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  font: font,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final byCat = <String, double>{};
    for (final e in rows) {
      byCat[e.categoryId] = (byCat[e.categoryId] ?? 0) + e.amount;
    }
    final catEntries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    pw.Widget catRow(String name, double amount) {
      final pct =
          totalExpense > 0 ? (amount / totalExpense).clamp(0.0, 1.0) : 0.0;
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Text(name,
                  style: pw.TextStyle(font: font, fontSize: 9)),
            ),
            pw.SizedBox(
              width: 70,
              child: pw.Text(
                money(amount),
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  font: font,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.SizedBox(
              width: 34,
              child: pw.Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: pw.TextStyle(
                    font: font, fontSize: 8, color: PdfColors.grey600),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.SizedBox(
              width: 100,
              child: pw.Row(
                children: [
                  pw.Container(
                    width: (100 * pct).clamp(0.0, 100.0),
                    height: 8,
                    color: deepGreen,
                  ),
                  pw.Expanded(
                    child:
                        pw.Container(height: 8, color: PdfColors.grey300),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Generated by Khorcha    ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: pw.BoxDecoration(
              color: deepGreen,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Khorcha', style: titleStyle),
                pw.SizedBox(height: 4),
                pw.Text(monthLabel, style: monthStyle),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              summaryBox(
                AppStrings.get('income_title', lang),
                money(totalIncome),
                PdfColors.green100,
                PdfColors.green800,
              ),
              summaryBox(
                AppStrings.get('month_total', lang),
                money(totalExpense),
                PdfColors.red100,
                PdfColors.red800,
              ),
              summaryBox(
                AppStrings.get('balance_title', lang),
                money(balance),
                PdfColors.amber100,
                goldDark,
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          if (catEntries.isNotEmpty) ...[
            pw.Text(
                '${AppStrings.get('category', lang)} — ${money(totalExpense)}',
                style: sectionStyle),
            pw.SizedBox(height: 6),
            for (final c in catEntries)
              catRow(
                  CustomCategoryRegistry.displayName(c.key, lang), c.value),
            pw.SizedBox(height: 14),
          ],
          pw.TableHelper.fromTextArray(
            headers: [
              AppStrings.get('date', lang),
              AppStrings.get('category', lang),
              AppStrings.get('note', lang),
              AppStrings.get('amount', lang),
            ],
            data: [
              for (final e in rows)
                [
                  _dateStr(e.date),
                  CustomCategoryRegistry.displayName(e.categoryId, lang),
                  e.note,
                  money(e.amount),
                ],
            ],
            headerStyle: headerStyle,
            headerDecoration: const pw.BoxDecoration(color: deepGreen),
            cellStyle: baseStyle,
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file =
        File(p.join(dir.path, '${_fileBase(month)}-statement.pdf'));
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Khorcha — $monthLabel',
      ),
    );
  }
}
