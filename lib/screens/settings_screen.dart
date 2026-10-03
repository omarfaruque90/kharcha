import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/export_service.dart';
import '../services/lock_service.dart';
import '../services/sync_service.dart';
import '../services/update_service.dart';
import 'lock_screen.dart';

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
    if (!mounted) return;
    setState(() {
      _lockEnabled = lock;
      _bioEnabled = bio && supported;
      _bioSupported = supported;
      _appVersion = version;
    });
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
        _snack(tr(context, ok ? 'backup_done' : 'backup_failed'));
      });

  Future<void> _doRestore() => _runBusy(() async {
        if (!mounted) return;
        final count = await BackupService.restore(context);
        if (count < 0) {
          _snack(tr(context, 'restore_failed'));
          return;
        }
        _snack('${tr(context, 'restore_done')} ($count)');
      });

  Future<void> _doExportPdf() => _runBusy(() async {
        final now = DateTime.now();
        await ExportService.exportMonthlyPdf(
            context, DateTime(now.year, now.month));
        _snack(tr(context, 'export_done'));
      });

  Future<void> _doExportExcel() => _runBusy(() async {
        final now = DateTime.now();
        await ExportService.exportMonthlyExcel(
            context, DateTime(now.year, now.month));
        _snack(tr(context, 'export_done'));
      });

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

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'nav_settings'))),
      body: ListView(
        children: [
          if (user != null) ...[
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  (userLabel?.isNotEmpty == true ? userLabel![0] : '?')
                      .toUpperCase(),
                ),
              ),
              title: Text(userLabel ?? tr(context, 'auth_account')),
              subtitle: Text(tr(context, 'auth_account')),
              trailing: IconButton(
                icon: const Icon(Icons.logout),
                tooltip: tr(context, 'auth_logout'),
                onPressed: () => _confirmLogout(context),
              ),
            ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(tr(context, 'language')),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bn', label: Text('বাংলা')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {lang},
              onSelectionChanged: (s) => settings.setLanguage(s.first),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(tr(context, 'dark_mode')),
            subtitle: Text(tr(context, 'theme')),
            value: settings.isDark,
            onChanged: (v) => settings.setThemeMode(
              v ? ThemeMode.dark : ThemeMode.light,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              tr(context, 'security_section'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
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
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              tr(context, 'data_section'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
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
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              tr(context, 'about'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/app_logo.png',
                width: 44,
                height: 44,
              ),
            ),
            title: const Text('Kharcha'),
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
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.amber),
            title: const Text('Niczzxo 💛'),
            subtitle: Text(tr(context, 'about_developer')),
          ),
        ],
      ),
    );
  }
}
