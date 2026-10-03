import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../widgets/motion.dart';
import '../models/app_notification.dart';
import '../providers/settings_provider.dart';
import '../services/notification_center.dart';
import 'package:provider/provider.dart';

/// In-app notification center: budget alerts, recurring-expense notices,
/// bill reminders and other app events. Newest first; tap marks read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await NotificationCenter.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _open(AppNotification n) async {
    if (n.id != null && !n.read) {
      await NotificationCenter.markRead(n.id!);
      await _reload();
    }
  }

  Future<void> _clearAll(String lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'clear_all')),
        content: Text(AppStrings.get('delete_confirm_msg', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await NotificationCenter.clearAll();
    await _reload();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'budget':
        return Icons.warning_amber_rounded;
      case 'recurring':
        return Icons.event_repeat_outlined;
      case 'bill_reminder':
        return Icons.notifications_active_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'notifications')),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: tr(context, 'clear_all'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _clearAll(lang),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none_outlined,
                        size: 56,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(context, 'no_notifications'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final n = _items[i];
                      final timeLabel = DateFormat.yMMMd(
                        lang == 'bn' ? 'bn' : 'en',
                      ).add_Hm().format(n.time);
                      return StaggeredEntrance(
                        delayMs: (i * 40).clamp(0, 320),
                        child: Card(
                          child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconFor(n.type),
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.read
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (n.body.isNotEmpty)
                                Text(n.body),
                              const SizedBox(height: 4),
                              Text(
                                timeLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          trailing: n.read
                              ? null
                              : Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                          onTap: () => _open(n),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
