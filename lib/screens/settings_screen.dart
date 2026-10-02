import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final user = AuthService.instance.currentUser;
    final userLabel = user == null
        ? null
        : (user.displayName?.isNotEmpty == true
            ? user.displayName!
            : (user.email ?? user.phoneNumber ?? ''));

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
            title: Text(tr(context, 'about')),
            subtitle: Text(tr(context, 'app_version')),
          ),
        ],
      ),
    );
  }
}
