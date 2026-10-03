import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';

/// Full local backup / restore as a JSON file.
///
/// Backup dumps every table (expenses, incomes, budgets, recurring
/// templates, savings goals, custom places/payments, bill reminders,
/// settings) and shares the file. Restore validates the file, then
/// merge-upserts each row by id with last-write-wins on `updatedAt`,
/// so restoring over existing data never loses newer edits.
class BackupService {
  static const List<String> _tables = [
    'expenses',
    'incomes',
    'budgets',
    'recurring_expenses',
    'savings_goals',
    'custom_places',
    'custom_payment_methods',
    'bill_reminders',
    'settings',
  ];

  /// Dumps all tables to a JSON file and opens the share sheet.
  /// Returns true when a file was shared.
  static Future<bool> backup(BuildContext context) async {
    final doneText = tr(context, 'backup_done');
    try {
      final db = await DatabaseHelper.instance.database;
      final tables = <String, dynamic>{};
      for (final t in _tables) {
        tables[t] = await db.query(t);
      }
      final payload = {
        'app': 'kharcha',
        'format': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'tables': tables,
      };
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final file =
          File(p.join(dir.path, 'kharcha-backup-$stamp.json'));
      await file.writeAsString(jsonEncode(payload));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: doneText,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Picks a backup JSON file and merges it in. Returns the number of
  /// rows written, or -1 when the file is invalid / cancelled.
  static Future<int> restore(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return -1;
      final file = File(result.files.single.path!);
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return -1;
      if (data['app'] != 'kharcha') return -1;
      final tables = data['tables'];
      if (tables is! Map) return -1;

      final db = await DatabaseHelper.instance.database;
      var written = 0;
      await db.transaction((txn) async {
        for (final entry in tables.entries) {
          final table = entry.key.toString();
          if (!_tables.contains(table)) continue;
          final rows = entry.value;
          if (rows is! List) continue;
          for (final row in rows) {
            if (row is! Map) continue;
            final map = Map<String, dynamic>.from(row);
            if (table == 'settings') {
              final key = map['key']?.toString();
              if (key == null || key.isEmpty) continue;
              await txn.insert(
                'settings',
                {'key': key, 'value': map['value']?.toString() ?? ''},
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              written++;
            } else {
              final id = map['id']?.toString();
              if (id == null || id.isEmpty) continue;
              final incomingTs = (map['updatedAt'] as num?)?.toInt() ?? 0;
              final existing = await txn.query(
                table,
                columns: ['updatedAt'],
                where: 'id = ?',
                whereArgs: [id],
                limit: 1,
              );
              final existingTs = existing.isEmpty
                  ? -1
                  : ((existing.first['updatedAt'] as num?)?.toInt() ?? 0);
              if (incomingTs >= existingTs) {
                await txn.insert(
                  table,
                  map,
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                written++;
              }
            }
          }
        }
      });

      // Refresh in-memory providers so the UI reflects restored data.
      if (context.mounted) {
        final expenses = Provider.of<ExpenseProvider>(context, listen: false);
        final money = Provider.of<MoneyProvider>(context, listen: false);
        try {
          await expenses.load();
        } catch (_) {}
        if (!context.mounted) return written;
        try {
          await money.load();
        } catch (_) {}
      }
      return written;
    } catch (_) {
      return -1;
    }
  }
}
