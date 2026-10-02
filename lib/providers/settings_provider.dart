import 'package:flutter/material.dart';

import '../db/database_helper.dart';

/// App settings (language + theme), persisted in SQLite.
class SettingsProvider extends ChangeNotifier {
  String _language = 'bn';
  ThemeMode _themeMode = ThemeMode.light;

  String get language => _language;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    final db = DatabaseHelper.instance;
    _language = await db.getSetting('language') ?? 'bn';
    final theme = await db.getSetting('themeMode') ?? 'light';
    _themeMode = theme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    if (language == _language) return;
    _language = language;
    await DatabaseHelper.instance.setSetting('language', language);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await DatabaseHelper.instance
        .setSetting('themeMode', mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
}
