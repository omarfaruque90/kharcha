import 'dart:async';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';

/// App settings (language + theme), persisted in SQLite.
///
/// Theme is a 4-way choice stored under 'themeMode':
/// 'system' | 'light' | 'dark' | 'scheduled' (legacy 'light'/'dark' values
/// map straight onto the matching choice).
/// With 'scheduled', dark theme applies between [darkStart] and [darkEnd]
/// ('HH:mm', 24h). The window handles overnight wrap, e.g. 22:00 -> 06:00.
class SettingsProvider extends ChangeNotifier {
  static const String choiceSystem = 'system';
  static const String choiceLight = 'light';
  static const String choiceDark = 'dark';
  static const String choiceScheduled = 'scheduled';

  /// Accent theme choices, persisted under the 'accent' setting.
  static const String accentGold = 'gold';
  static const String accentEmerald = 'emerald';
  static const String accentBlue = 'blue';
  static const String accentPurple = 'purple';
  static const String accentOrange = 'orange';
  static const String accentCustom = 'custom';

  /// Accent keys in picker order.
  static const List<String> accents = [
    accentGold,
    accentEmerald,
    accentBlue,
    accentPurple,
    accentOrange,
    accentCustom,
  ];

  /// Dot colors for the settings accent picker. Must match `kAccents` in
  /// main.dart; kept here so settings_screen.dart can use them without
  /// importing main.dart (which would create an import cycle).
  static const Map<String, Color> accentColors = {
    accentGold: Color(0xFFD4AF37),
    accentEmerald: Color(0xFF10B981),
    accentBlue: Color(0xFF3B82F6),
    accentPurple: Color(0xFF8B5CF6),
    accentOrange: Color(0xFFF97316),
  };

  static final RegExp _hhmmRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  String _language = 'bn';
  String _themeChoice = choiceLight;
  String _darkStart = '22:00';
  String _darkEnd = '06:00';
  String _accent = accentGold;
  int _customColor = 0xFFD4AF37; // Custom accent color (ARGB int)
  bool _amoled = false;
  double _fontScale = 1.0;
  Timer? _scheduleTimer;

  String get language => _language;
  String get themeChoice => _themeChoice;
  String get darkStart => _darkStart;
  String get darkEnd => _darkEnd;
  String get accent => _accent;
  Color get customColor => Color(_customColor);
  bool get amoled => _amoled;
  double get fontScale => _fontScale;

  /// Resolves the stored choice to a concrete [ThemeMode] for MaterialApp.
  ThemeMode get themeMode {
    switch (_themeChoice) {
      case choiceSystem:
        return ThemeMode.system;
      case choiceDark:
        return ThemeMode.dark;
      case choiceScheduled:
        return _nowInDarkWindow() ? ThemeMode.dark : ThemeMode.light;
      case choiceLight:
      default:
        return ThemeMode.light;
    }
  }

  /// True when the resolved theme is currently dark (scheduled resolves too).
  bool get isDark => themeMode == ThemeMode.dark;

  bool _nowInDarkWindow() {
    final start = _toMinutes(_darkStart);
    final end = _toMinutes(_darkEnd);
    if (start == end) return false; // degenerate window -> always light
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    if (start < end) return current >= start && current < end;
    // Overnight wrap, e.g. 22:00 -> 06:00.
    return current >= start || current < end;
  }

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return 0;
    return (h * 60 + m).clamp(0, 24 * 60 - 1);
  }

  static bool _isValidChoice(String value) =>
      value == choiceSystem ||
      value == choiceLight ||
      value == choiceDark ||
      value == choiceScheduled;

  static bool _isValidAccent(String value) =>
      value == accentGold ||
      value == accentEmerald ||
      value == accentBlue ||
      value == accentPurple ||
      value == accentOrange;

  Future<void> load() async {
    final db = DatabaseHelper.instance;
    _language = await db.getSetting('language') ?? 'bn';
    final choice = await db.getSetting('themeMode') ?? choiceLight;
    _themeChoice = _isValidChoice(choice) ? choice : choiceLight;
    final accent = await db.getSetting('accent');
    _accent = (accent != null && _isValidAccent(accent)) ? accent : accentGold;
    final cc = int.tryParse(await db.getSetting('custom_color') ?? '');
    if (cc != null) _customColor = cc;
    final start = await db.getSetting('dark_start');
    if (start != null && _hhmmRe.hasMatch(start)) _darkStart = start;
    final end = await db.getSetting('dark_end');
    if (end != null && _hhmmRe.hasMatch(end)) _darkEnd = end;
    _amoled = (await db.getSetting('amoled')) == '1';
    final fs = double.tryParse(await db.getSetting('font_scale') ?? '');
    if (fs != null) _fontScale = fs.clamp(0.85, 1.3);
    _armScheduleTimer();
    notifyListeners();
  }

  Future<void> setAccent(String accent) async {
    if (!_isValidAccent(accent) || accent == _accent) return;
    _accent = accent;
    await DatabaseHelper.instance.setSetting('accent', accent);
    notifyListeners();
  }

  Future<void> setCustomColor(Color color) async {
    _customColor = color.value;
    _accent = accentCustom;
    await DatabaseHelper.instance
        .setSetting('custom_color', color.value.toString());
    await DatabaseHelper.instance.setSetting('accent', accentCustom);
    notifyListeners();
  }

  Future<void> setAmoled(bool value) async {
    if (value == _amoled) return;
    _amoled = value;
    await DatabaseHelper.instance.setSetting('amoled', value ? '1' : '0');
    notifyListeners();
  }

  Future<void> setFontScale(double value) async {
    final v = value.clamp(0.85, 1.3);
    if (v == _fontScale) return;
    _fontScale = v;
    await DatabaseHelper.instance
        .setSetting('font_scale', v.toStringAsFixed(2));
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    if (language == _language) return;
    _language = language;
    await DatabaseHelper.instance.setSetting('language', language);
    notifyListeners();
  }

  Future<void> setThemeChoice(String choice) async {
    if (!_isValidChoice(choice) || choice == _themeChoice) return;
    _themeChoice = choice;
    await DatabaseHelper.instance.setSetting('themeMode', choice);
    _armScheduleTimer();
    notifyListeners();
  }

  /// Back-compat shim for the old two-state API.
  @Deprecated('Use setThemeChoice instead')
  Future<void> setThemeMode(ThemeMode mode) async {
    switch (mode) {
      case ThemeMode.dark:
        return setThemeChoice(choiceDark);
      case ThemeMode.system:
        return setThemeChoice(choiceSystem);
      case ThemeMode.light:
        return setThemeChoice(choiceLight);
    }
  }

  Future<void> setDarkStart(String hhmm) async {
    if (!_hhmmRe.hasMatch(hhmm) || hhmm == _darkStart) return;
    _darkStart = hhmm;
    await DatabaseHelper.instance.setSetting('dark_start', hhmm);
    notifyListeners();
  }

  Future<void> setDarkEnd(String hhmm) async {
    if (!_hhmmRe.hasMatch(hhmm) || hhmm == _darkEnd) return;
    _darkEnd = hhmm;
    await DatabaseHelper.instance.setSetting('dark_end', hhmm);
    notifyListeners();
  }

  /// While 'scheduled' is active, re-evaluate once a minute so the theme
  /// flips automatically when the dark window starts/ends.
  void _armScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    if (_themeChoice != choiceScheduled) return;
    var last = themeMode;
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = themeMode;
      if (now != last) {
        last = now;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    super.dispose();
  }
}
