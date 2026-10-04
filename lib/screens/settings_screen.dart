import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../theme/design_tokens.dart';
import '../db/database_helper.dart';
import '../widgets/motion.dart';
import '../widgets/smart_search.dart';
import '../widgets/color_picker_dialog.dart';
import '../providers/settings_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/carry_forward_service.dart';
import '../services/drive_backup_service.dart';
import '../services/export_service.dart';
import '../services/home_widget_service.dart';
import '../services/lock_service.dart';
import '../services/profile_service.dart';
import '../services/scheduled_export_service.dart';
import '../services/sync_service.dart';
import '../services/stats_notification.dart';
import '../services/update_service.dart';
import '../utils/formatters.dart';
import 'lock_screen.dart';
import 'ai_llm_settings_screen.dart';
import 'categories_screen.dart';
import 'profile_screen.dart';
import 'settings_section_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _lockEnabled = false;
  bool _bioEnabled = false;
  bool _bioSupported = false;
  String _appVersion = '';
  bool _busy = false;
  bool _driveAuto = false;
  DateTime? _driveLast;
  String _widgetStyle = 'detailed';
  double _dailyLimit = 0;
  List<String> _profiles = const ['personal'];
  String _activeProfile = 'personal';
  bool _statsNotif = false;
  bool _carryForward = false;
  bool _autoPdf = false;
  final GlobalKey<_SettingsAvatarState> _avatarKey =
      GlobalKey<_SettingsAvatarState>();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final lock = await LockService.instance.isLockEnabled();
    final bio = await LockService.instance.isBiometricEnabled();
    final supported = await LockService.instance.canUseBiometrics();
    String version = '';
    try {
      final pkg = await PackageInfo.fromPlatform();
      version = pkg.version;
    } catch (_) {}
    final driveAuto = await DriveBackupService.isAutoEnabled();
    final driveLast = await DriveBackupService.lastBackup();
    final dailyLimit =
        double.tryParse(await DatabaseHelper.instance.getSetting('daily_limit') ?? '') ?? 0;
    final profiles = await DatabaseHelper.getProfiles();
    final statsNotif = await StatsNotification.isEnabled();
    final carryForward =
        (await DatabaseHelper.instance.getSetting('carry_forward')) == '1';
    // Reads the same SharedPreferences-backed toggle the background
    // worker checks (ScheduledExportService.maybeRun); the SQLite
    // 'auto_pdf' setting was never read by the worker.
    final autoPdf = await ScheduledExportService.isEnabled();
    if (!mounted) return;
    setState(() {
      _lockEnabled = lock;
      _bioEnabled = bio && supported;
      _bioSupported = supported;
      _appVersion = version;
      _driveAuto = driveAuto;
      _driveLast = driveLast;
      _dailyLimit = dailyLimit;
      _profiles = profiles;
      _activeProfile = DatabaseHelper.instance.activeProfile;
      _statsNotif = statsNotif;
      _carryForward = carryForward;
      _autoPdf = autoPdf;
    });
  }

  Future<void> _editDailyLimit(BuildContext context) async {
    final ctrl = TextEditingController(
        text: _dailyLimit > 0 ? _dailyLimit.toStringAsFixed(0) : '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'daily_limit_title')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: tr(dctx, 'daily_limit_hint'),
            prefixText: '৳ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(tr(dctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(tr(dctx, 'save')),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      final v = double.tryParse(ctrl.text.trim()) ?? 0;
      await DatabaseHelper.instance
          .setSetting('daily_limit', v > 0 ? v.toStringAsFixed(0) : '0');
      setState(() => _dailyLimit = v > 0 ? v : 0);
    }
    ctrl.dispose();
  }

  Future<void> _showProfileSwitcher(BuildContext context) async {
    final profiles = await DatabaseHelper.getProfiles();
    if (!context.mounted) return;
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'profile_switch')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in profiles)
                ListTile(
                  dense: true,
                  leading: Icon(
                    p == DatabaseHelper.instance.activeProfile
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: Theme.of(dctx).colorScheme.primary,
                  ),
                  title: Text(p == 'personal'
                      ? tr(dctx, 'profile_personal')
                      : p),
                  subtitle: p == 'personal'
                      ? Text(tr(dctx, 'profile_personal_sub'))
                      : null,
                  trailing: p == 'personal'
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            await DatabaseHelper.deleteProfile(p);
                            if (dctx.mounted) Navigator.pop(dctx);
                            _refresh();
                          },
                        ),
                  onTap: () async {
                    await DatabaseHelper.instance.setProfile(p);
                    // Reload providers so the UI reflects the new profile.
                    if (dctx.mounted) {
                      Navigator.pop(dctx);
                      final expenses = context.read<ExpenseProvider>();
                      final money = context.read<MoneyProvider>();
                      await expenses.load();
                      await money.load();
                      _refresh();
                    }
                  },
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: tr(dctx, 'profile_new_hint'),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      final n = nameCtrl.text.trim();
                      if (n.isEmpty) return;
                      await DatabaseHelper.addProfile(n);
                      await DatabaseHelper.instance.setProfile(n);
                      if (dctx.mounted) {
                        Navigator.pop(dctx);
                        final expenses = context.read<ExpenseProvider>();
                        final money = context.read<MoneyProvider>();
                        await expenses.load();
                        await money.load();
                        _refresh();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(tr(dctx, 'close')),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
  }

  /// Native display name for every supported language code.
  static const Map<String, String> _languageNames = {
    'bn': 'বাংলা',
    'en': 'English',
    'hi': 'हिन्दी',
    'ur': 'اردو',
    'ar': 'العربية',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'pt': 'Português',
    'ru': 'Русский',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
    'tr': 'Türkçe',
    'id': 'Bahasa Indonesia',
    'ms': 'Bahasa Melayu',
    'vi': 'Tiếng Việt',
    'th': 'ไทย',
    'it': 'Italiano',
    'fa': 'فارسی',
    'nl': 'Nederlands',
  };

  /// Languages shown in the "Popular" section of the language picker.
  static const List<String> _popularLangs = ['bn', 'en', 'hi', 'ur', 'ar'];

  /// Languages shown in the "World" section of the language picker.
  static const List<String> _worldLangs = [
    'es',
    'fr',
    'de',
    'pt',
    'ru',
    'zh',
    'ja',
    'ko',
    'tr',
    'id',
    'ms',
    'vi',
    'th',
    'it',
    'fa',
    'nl',
  ];

  void _showLanguagePicker(BuildContext context, SettingsProvider settings) {
    final scheme = Theme.of(context).colorScheme;
    Widget sectionHeader(String key) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            tr(context, key),
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        );
    Widget langTile(String code) {
      final selected = settings.language == code;
      return ListTile(
        dense: true,
        title: Text(_languageNames[code] ?? code),
        trailing: selected
            ? Icon(Icons.check, color: scheme.primary)
            : null,
        onTap: () {
          settings.setLanguage(code);
          Navigator.of(context).pop();
        },
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'language')),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              sectionHeader('lang_popular'),
              for (final c in _popularLangs) langTile(c),
              sectionHeader('lang_world'),
              for (final c in _worldLangs) langTile(c),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'close')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'auth_logout_title')),
        content: Text(tr(ctx, 'auth_logout_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'auth_logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Clear local data first (privacy), then sign out. AuthGate takes over.
    try {
      await SyncService.instance.stopAndClear();
    } catch (_) {}
    try {
      await AuthService.instance.signOut();
    } catch (_) {}
  }

  Future<void> _onLockToggle(bool value) async {
    if (value) {
      final set = await SetPinFlow.show(context);
      if (set && mounted) setState(() => _lockEnabled = true);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'lock_disable_title')),
        content: Text(tr(ctx, 'lock_disable_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LockService.instance.clearPin();
      if (mounted) {
        setState(() {
          _lockEnabled = false;
          _bioEnabled = false;
        });
      }
    }
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _doBackup() => _runBusy(() async {
        final ok = await BackupService.backup(context);
        if (!mounted) return;
        _snack(tr(context, ok ? 'backup_done' : 'backup_failed'));
      });

  Future<void> _doRestore() => _runBusy(() async {
        if (!mounted) return;
        final count = await BackupService.restore(context);
        if (!mounted) return;
        if (count < 0) {
          _snack(tr(context, 'restore_failed'));
          return;
        }
        _snack('${tr(context, 'restore_done')} ($count)');
      });

  Future<void> _toggleDriveAuto(bool value) async {
    if (value) {
      // Enabling requests the drive.appdata scope (incremental consent).
      await _runBusy(() async {
        try {
          final ok = await DriveBackupService.backupNow(interactive: true);
          if (!mounted) return;
          if (ok) {
            await DriveBackupService.setAutoEnabled(true);
            _driveAuto = true;
            _driveLast = await DriveBackupService.lastBackup();
            if (!mounted) return;
            setState(() {});
            _snack(tr(context, 'drive_done'));
          } else {
            _snack(tr(context, 'drive_failed'));
          }
        } on DriveAuthException {
          if (!mounted) return;
          _snack(tr(context, 'drive_auth_failed'));
        }
      });
    } else {
      await DriveBackupService.setAutoEnabled(false);
      if (mounted) setState(() => _driveAuto = false);
    }
  }

  Future<void> _driveBackupNow() => _runBusy(() async {
        _snack(tr(context, 'drive_backing_up'));
        try {
          final ok = await DriveBackupService.backupNow(interactive: true);
          if (!mounted) return;
          _driveLast = await DriveBackupService.lastBackup();
          if (!mounted) return;
          setState(() {});
          _snack(tr(context, ok ? 'drive_done' : 'drive_failed'));
        } on DriveAuthException {
          if (!mounted) return;
          await DriveBackupService.setAutoEnabled(false);
          if (!mounted) return;
          setState(() => _driveAuto = false);
          _snack(tr(context, 'drive_auth_failed'));
        }
      });

  Future<void> _driveRestore() => _runBusy(() async {
        try {
          final count = await DriveBackupService.restoreLatest();
          if (!mounted) return;
          if (count < 0) {
            _snack(tr(context, 'drive_no_backup'));
            return;
          }
          _driveLast = await DriveBackupService.lastBackup();
          if (!mounted) return;
          setState(() {});
          _snack(tr(context, 'drive_restored').replaceAll('{n}', '$count'));
        } on DriveAuthException {
          if (!mounted) return;
          await DriveBackupService.setAutoEnabled(false);
          if (!mounted) return;
          setState(() => _driveAuto = false);
          _snack(tr(context, 'drive_auth_failed'));
        }
      });

  Future<void> _doExportPdf() => _runBusy(() async {
        final now = DateTime.now();
        await ExportService.exportMonthlyPdf(
            context, DateTime(now.year, now.month));
        if (!mounted) return;
        _snack(tr(context, 'export_done'));
      });

  Future<void> _doExportExcel() => _runBusy(() async {
        final now = DateTime.now();
        await ExportService.exportMonthlyExcel(
            context, DateTime(now.year, now.month));
        if (!mounted) return;
        _snack(tr(context, 'export_done'));
      });

  Future<void> _pickDarkTime(BuildContext context,
      {required bool isStart}) async {
    final settings =
        Provider.of<SettingsProvider>(context, listen: false);
    final current = isStart ? settings.darkStart : settings.darkEnd;
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? (isStart ? 22 : 6),
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (isStart) {
      await settings.setDarkStart(hhmm);
    } else {
      await settings.setDarkEnd(hhmm);
    }
  }

  Future<void> _checkForUpdates() async {
    if (_busy) return;
    setState(() => _busy = true);
    var dialogShown = false;
    try {
      // Show a small progress indicator while the network call runs.
      if (mounted) {
        dialogShown = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      if (info == null) {
        _snack(tr(context, 'update_latest'));
      } else {
        await UpdateService.showUpdateDialog(context, info);
      }
    } finally {
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Named section header — every settings group gets one.
  IconData _sectionIcon(String key) {
    switch (key) {
      case 'account_section':
        return Icons.person_outline;
      case 'general_section':
        return Icons.tune;
      case 'appearance_section':
        return Icons.palette_outlined;
      case 'money_section':
        return Icons.account_balance_wallet_outlined;
      case 'profile_section':
        return Icons.group_outlined;
      case 'security_section':
        return Icons.lock_outline;
      case 'ai_settings_section':
        return Icons.smart_toy_outlined;
      case 'data_section':
        return Icons.backup_outlined;
      case 'about':
        return Icons.info_outline;
      default:
        return Icons.settings_outlined;
    }
  }

  /// Expandable section: tap the header to collapse/expand.
  /// Items hide inside when collapsed.
  /// Section tile: tap to navigate to the section's detail screen.
  /// iOS-style row: 40px icon container, semibold 16px title, gray chevron.
  Widget _expandableSection(
      BuildContext context, String key, List<Widget> children) {
    final dark = Theme.of(context).brightness == Brightness.dark;
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
        child: Icon(
          _sectionIcon(key),
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        tr(context, key),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: dark ? const Color(0xFF48484A) : const Color(0xFFC7C7CC),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                SettingsSectionScreen(sectionKey: key, tiles: children),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final user = AuthService.instance.currentUser;
    final userLabel = user == null
        ? null
        : (user.displayName?.isNotEmpty == true
            ? user.displayName!
            : (user.email ??
                user.phoneNumber ??
                (user.isAnonymous
                    ? tr(context, 'auth_guest_label')
                    : '')));

    // Section rows — each navigates to its detail screen.
    // Account keeps profile + name only (logout sits in its own group).
    final Widget? accountRow = user == null
        ? null
        : _expandableSection(context, 'account_section', [
              ListTile(
                leading: _SettingsAvatar(
                  key: _avatarKey,
                  initial: (userLabel?.isNotEmpty == true ? userLabel![0] : '?')
                      .toUpperCase(),
                ),
                title: Text(userLabel ?? tr(context, 'auth_account')),
                subtitle: Text(tr(context, 'profile_title')),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                  // Refresh the avatar in case the photo was changed.
                  _avatarKey.currentState?.refresh();
                  if (mounted) setState(() {});
                },
              ),
            ]);
    // ── General ──
    final generalRow = _expandableSection(context, 'general_section', [
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(tr(context, 'language')),
              subtitle: Text(_languageNames[lang] ?? lang),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguagePicker(context, settings),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(tr(context, 'customize_categories')),
              subtitle: Text(tr(context, 'customize_categories_sub')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CategoriesScreen()),
              ),
            ),
          ]);
          // ── Appearance ──
          final appearanceRow =
              _expandableSection(context, 'appearance_section', [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(tr(context, 'appearance')),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 12),
                  ),
                ),
                segments: [
                  ButtonSegment(
                      value: 'system',
                      label: Text(tr(context, 'theme_system'),
                          softWrap: false, maxLines: 1)),
                  ButtonSegment(
                      value: 'light',
                      label: Text(tr(context, 'theme_light'),
                          softWrap: false, maxLines: 1)),
                  ButtonSegment(
                      value: 'dark',
                      label: Text(tr(context, 'theme_dark'),
                          softWrap: false, maxLines: 1)),
                  ButtonSegment(
                      value: 'scheduled',
                      label: Text(tr(context, 'theme_scheduled'),
                          softWrap: false, maxLines: 1)),
                ],
                selected: {settings.themeChoice},
                onSelectionChanged: (s) =>
                    settings.setThemeChoice(s.first),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.color_lens_outlined),
            title: Text(tr(context, 'accent_title')),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  for (final key in SettingsProvider.accents)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: PressableScale(
                        onTap: () async {
                          if (key == SettingsProvider.accentCustom) {
                            final picked =
                                await showDialog<Color>(
                              context: context,
                              builder: (ctx) => ColorPickerDialog(
                                initialColor: settings.customColor,
                              ),
                            );
                            if (picked != null && context.mounted) {
                              await settings.setCustomColor(picked);
                            }
                          } else {
                            settings.setAccent(key);
                          }
                        },
                        child: Builder(
                          builder: (dotCtx) {
                            final isCustom =
                                key == SettingsProvider.accentCustom;
                            final swatch = isCustom
                                ? settings.customColor
                                : (SettingsProvider.accentColors[key] ??
                                    Colors.grey);
                            final onSwatch =
                                ThemeData.estimateBrightnessForColor(
                                            swatch) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF072A1F);
                            final selected = key == settings.accent;
                            return Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: swatch,
                                border: selected
                                    ? Border.all(
                                        color: Theme.of(dotCtx)
                                            .colorScheme
                                            .onSurface,
                                        width: 3,
                                      )
                                    : Border.all(
                                        color: Theme.of(dotCtx)
                                            .colorScheme
                                            .outlineVariant,
                                        width: 1,
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.25),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: selected
                                  ? Icon(Icons.check,
                                      color: onSwatch, size: 22)
                                  : null,
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (settings.themeChoice == 'scheduled') ...[
            ListTile(
              dense: true,
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(tr(context, 'dark_start')),
              trailing: Text(
                settings.darkStart,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              onTap: () => _pickDarkTime(context, isStart: true),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.wb_sunny_outlined),
              title: Text(tr(context, 'dark_end')),
              trailing: Text(
                settings.darkEnd,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              onTap: () => _pickDarkTime(context, isStart: false),
            ),
          ],
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(tr(context, 'amoled_title')),
            subtitle: Text(tr(context, 'amoled_sub')),
            value: settings.amoled,
            onChanged: (v) => settings.setAmoled(v),
          ),
          ListTile(
            leading: const Icon(Icons.format_size_outlined),
            title: Text(tr(context, 'font_size_title')),
            subtitle: Slider(
              value: settings.fontScale,
              min: 0.85,
              max: 1.3,
              divisions: 9,
              label: '${(settings.fontScale * 100).round()}%',
              onChanged: (v) => settings.setFontScale(v),
            ),
            trailing: Text(
              '${(settings.fontScale * 100).round()}%',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: Text(tr(context, 'widget_style_title')),
            trailing: DropdownButton<String>(
              value: _widgetStyle,
              items: [
                for (final s in HomeWidgetService.widgetStyles)
                  DropdownMenuItem(
                    value: s,
                    child: Text(tr(context, 'widget_style_$s')),
                  ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _widgetStyle = v);
                await HomeWidgetService.setStyle(v);
              },
            ),
          ),
          ]);
          // ── Money ──
          final moneyRow = _expandableSection(context, 'money_section', [
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: Text(tr(context, 'daily_limit_title')),
            subtitle: Text(_dailyLimit > 0
                ? formatMoney(_dailyLimit)
                : tr(context, 'daily_limit_off')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editDailyLimit(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(tr(context, 'stats_notif_title')),
            subtitle: Text(tr(context, 'stats_notif_sub')),
            value: _statsNotif,
            onChanged: (v) async {
              await StatsNotification.setEnabled(v);
              if (mounted) setState(() => _statsNotif = v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.redo_outlined),
            title: Text(tr(context, 'carry_forward_title')),
            subtitle: Text(tr(context, 'carry_forward_sub')),
            value: _carryForward,
            onChanged: (v) async {
              await DatabaseHelper.instance
                  .setSetting('carry_forward', v ? '1' : '0');
              if (mounted) setState(() => _carryForward = v);
              if (v) {
                // Run the rollover immediately so the current month picks
                // up any leftover right away (BP: carry-forward).
                try {
                  await CarryForwardService.maybeRollover();
                } catch (_) {}
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(tr(context, 'auto_pdf_title')),
            subtitle: Text(tr(context, 'auto_pdf_sub')),
            value: _autoPdf,
            onChanged: (v) async {
              await ScheduledExportService.setEnabled(v);
              if (mounted) setState(() => _autoPdf = v);
            },
          ),
          ]);
          // ── Profiles ──
          final profilesRow = _expandableSection(context, 'profile_section', [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(tr(context, 'profile_current')),
            subtitle: Text(_profiles.isEmpty
                ? 'personal'
                : _profiles.contains(_activeProfile)
                    ? _activeProfile
                    : 'personal'),
            trailing: const Icon(Icons.swap_horiz),
            onTap: () => _showProfileSwitcher(context),
          ),
          ]);
          // ── Security ──
          final securityRow = _expandableSection(context, 'security_section', [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(tr(context, 'lock_title')),
            subtitle: Text(tr(context, 'lock_sub')),
            value: _lockEnabled,
            onChanged: _onLockToggle,
          ),
          if (_lockEnabled)
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(tr(context, 'lock_change_pin')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => SetPinFlow.show(context),
            ),
          if (_lockEnabled && _bioSupported)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: Text(tr(context, 'lock_bio')),
              value: _bioEnabled,
              onChanged: (v) async {
                await LockService.instance.setBiometricEnabled(v);
                if (mounted) setState(() => _bioEnabled = v);
              },
            ),
          ]);
          // ── AI Assistant ──
          final aiRow = _expandableSection(context, 'ai_settings_section', [
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(tr(context, 'ai_settings_title')),
            subtitle: Text(tr(context, 'ai_settings_sub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiLlmSettingsScreen()),
            ),
          ),
          ]);
          // ── Data ──
          final dataRow = _expandableSection(context, 'data_section', [
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(tr(context, 'backup_now')),
            onTap: _busy ? null : _doBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: Text(tr(context, 'restore_title')),
            onTap: _busy ? null : _doRestore,
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off_outlined),
            title: Text(tr(context, 'clear_search_hist')),
            subtitle: Text(tr(context, 'clear_search_hist_sub')),
            onTap: _busy
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: Text(tr(dctx, 'clear_search_hist')),
                        content:
                            Text(tr(dctx, 'clear_search_hist_msg')),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dctx).pop(false),
                            child: Text(tr(dctx, 'cancel')),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dctx).pop(true),
                            child: Text(tr(dctx, 'delete')),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await SmartSearch.clearHistory();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                tr(context, 'clear_search_hist_done')),
                          ),
                        );
                      }
                    }
                  },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_upload_outlined),
            title: Text(tr(context, 'drive_auto')),
            subtitle: Text(_driveLast == null
                ? tr(context, 'drive_never')
                : tr(context, 'drive_last').replaceAll(
                    '{date}',
                    DateFormat.yMMMd(
                            context.watch<SettingsProvider>().language == 'bn'
                                ? 'bn'
                                : 'en')
                        .format(_driveLast!))),
            value: _driveAuto,
            onChanged: _busy ? null : (v) => _toggleDriveAuto(v),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: Text(tr(context, 'drive_backup')),
            subtitle: Text(tr(context, 'drive_backup_sub')),
            onTap: _busy ? null : _driveBackupNow,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(tr(context, 'drive_restore')),
            subtitle: Text(tr(context, 'drive_restore_sub')),
            onTap: _busy ? null : _driveRestore,
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(tr(context, 'export_pdf')),
            subtitle: Text(tr(context, 'export_pdf_sub')),
            onTap: _busy ? null : _doExportPdf,
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(tr(context, 'export_excel')),
            subtitle: Text(tr(context, 'export_excel_sub')),
            onTap: _busy ? null : _doExportExcel,
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text(tr(context, 'check_updates')),
            onTap: _busy ? null : _checkForUpdates,
          ),
          ]);
          // ── About ──
          final aboutRow = _expandableSection(context, 'about', [
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/app_logo.png',
                width: 44,
                height: 44,
              ),
            ),
            title: const Text('Khorcha'),
            subtitle: Text(tr(context, 'tagline')),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(tr(context, 'about_version')),
            trailing: Text(
              _appVersion.isEmpty ? '…' : 'v$_appVersion',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          ]);

    // iOS-style grouped sections, each with a staggered entrance.
    var groupIndex = 0;
    Widget grouped(List<Widget> rows) {
      return StaggeredEntrance(
        delayMs: ((groupIndex++) * 35).clamp(0, 280),
        child: KIOS.groupedSection(context, children: rows),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'nav_settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Group 1: Account (no header)
          if (accountRow != null) grouped([accountRow]),
          // Group 2: General, Appearance, Money, Profiles
          grouped(
              [generalRow, appearanceRow, moneyRow, profilesRow]),
          // Group 3: Security, AI Assistant, Data
          grouped([securityRow, aiRow, dataRow]),
          // Group 4: About
          grouped([aboutRow]),
          // Group 5: Logout — destructive red, centered
          if (user != null)
            grouped([
              ListTile(
                title: Center(
                  child: Text(
                    tr(context, 'auth_logout'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                onTap: () => _confirmLogout(context),
              ),
            ]),
        ],
      ),
    );
  }
}

/// Avatar circle for the settings profile row. Loads the Firestore thumbnail
/// (cached in [ProfileService]) and falls back to the user's initial.
class _SettingsAvatar extends StatefulWidget {
  final String initial;
  const _SettingsAvatar({super.key, required this.initial});

  @override
  State<_SettingsAvatar> createState() => _SettingsAvatarState();
}

class _SettingsAvatarState extends State<_SettingsAvatar> {
  String? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final thumb = await ProfileService.instance.getAvatarThumb();
    if (mounted) setState(() => _thumb = thumb);
  }

  /// Re-fetch after returning from [ProfileScreen].
  void refresh() => _load();

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (_thumb != null && _thumb!.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(_thumb!));
      } catch (_) {
        image = null;
      }
    }
    return CircleAvatar(
      backgroundImage: image,
      child: image == null ? Text(widget.initial) : null,
    );
  }
}
