import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../models/custom_category.dart';
import '../utils/formatters.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Scheduled monthly PDF export (Package BR).
///
/// Once per calendar month, when the user has enabled the "Monthly auto-PDF"
/// toggle (setting `auto_pdf` = '1'/'0', default '0'), generates the branded
/// monthly statement PDF for LAST month and saves it to the app documents
/// directory, then fires a phone notification + an in-app notification-center
/// entry ("📄 Monthly report ready").
///
/// Why the generator lives here instead of calling
/// [ExportService.exportFancyStatement]: that method takes a [BuildContext]
/// (it reads the language from [SettingsProvider]) and ends with a
/// SharePlus share sheet — neither is usable from the background WorkManager
/// task. This file therefore contains a context-free variant that builds
/// the same branded statement layout using the stored language setting.
/// If a real "no-context, no-share, return-bytes" variant is ever added to
/// ExportService, [maybeRun] should switch to it and the private builder
/// below can be deleted.
///
/// Drive: [DriveBackupService] has no generic "upload arbitrary file"
/// helper — it only uploads the backup JSON via backupNow() — so the PDF
/// is NOT pushed to Drive here (the regular auto-backup JSON keeps running
/// separately in the same worker).
class ScheduledExportService {
  ScheduledExportService._();

  static const _settingKey = 'auto_pdf';
  static const _prefsKey = 'last_export_month';

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Entry point. Silent no-op when disabled or already done this month.
  /// All errors are swallowed — must never crash startup or the worker.
  static Future<void> maybeRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getString(_settingKey) ?? '0') != '1') return;

      final now = DateTime.now();
      final curKey = _monthKey(now);
      if (prefs.getString(_prefsKey) == curKey) return;

      // Last month. DateTime rolls month 0 back to last December.
      final firstOfThisMonth = DateTime(now.year, now.month, 1);
      final lastMonth =
          DateTime(firstOfThisMonth.year, firstOfThisMonth.month - 1, 1);

      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final bytes = await _buildStatementBytes(lastMonth, lang);

      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(
          dir.path, 'khorcha-${_monthKey(lastMonth)}-statement.pdf'));
      await file.writeAsBytes(bytes);

      final monthLabel = monthLong(lastMonth, lang);
      final title = AppStrings.get('export_ready_title', lang);
      final body = AppStrings.get('export_ready_body', lang)
          .replaceAll('{month}', monthLabel);

      // Phone notification + in-app notification center entry.
      // Tapping the tray notification opens the app (payload-less); sharing
      // the PDF from the notification is out of scope for this package —
      // the user opens the app and shares from the export screen.
      try {
        await NotificationService.showNow(title: title, body: body);
      } catch (_) {}
      try {
        await NotificationCenter.push(
          title: title,
          body: body,
          type: 'report',
          dedupeKey: 'auto_pdf_$curKey',
        );
      } catch (_) {}

      await prefs.setString(_prefsKey, curKey);
    } catch (_) {}
  }

  /// Whether the monthly auto-PDF toggle is on.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_settingKey) ?? '0') == '1';
    } catch (_) {
      return false;
    }
  }

  /// Used by the settings toggle.
  static Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingKey, value ? '1' : '0');
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Context-free statement builder. Mirrors ExportService.exportFancyStatement
  // (deep-green/gold branding, summary boxes, category breakdown, full
  // expense table) but takes the language directly and returns bytes instead
  // of opening a share sheet.
  // ------------------------------------------------------------------

  static Future<pw.Font?> _bengaliFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansBengali.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      // Background isolate: no asset bundle — fall back to latin-safe text.
      return null;
    }
  }

  static String _dateStr(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static Future<List<int>> _buildStatementBytes(
      DateTime month, String lang) async {
    final db = DatabaseHelper.instance;
    final expenses = (await db.getAllExpenses())
        .where((e) => e.date.year == month.year && e.date.month == month.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final incomes = (await db.getAllIncomes())
        .where((i) => i.date.year == month.year && i.date.month == month.month)
        .toList();

    final font = await _bengaliFont();
    // ৳ and Bengali glyphs need the bundled font; without it fall back to a
    // latin-safe format so amounts never render as tofu boxes.
    String money(double v) =>
        font != null ? formatMoney(v) : 'BDT ${v.toStringAsFixed(0)}';

    final totalExpense = expenses.fold<double>(0, (s, e) => s + e.amount);
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

    pw.Widget summaryBox(String label, String value, PdfColor bg, PdfColor fg) {
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
              pw.Text(label,
                  style: pw.TextStyle(
                      font: font, fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(value,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: fg,
                  )),
            ],
          ),
        ),
      );
    }

    final byCat = <String, double>{};
    for (final e in expenses) {
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
              child:
                  pw.Text(name, style: pw.TextStyle(font: font, fontSize: 9)),
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
                    child: pw.Container(height: 8, color: PdfColors.grey300),
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
              catRow(CustomCategoryRegistry.displayName(c.key, lang), c.value),
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
              for (final e in expenses)
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

    return doc.save();
  }
}
