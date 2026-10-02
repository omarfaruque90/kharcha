import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'nav_settings'))),
      body: ListView(
        children: [
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
              borderRadius: const BorderRadius.circular(10),
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
