import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../services/achievements.dart';
import '../widgets/motion.dart';

/// Grid of all badges; unlocked ones shine gold, locked ones stay grey.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  Future<Set<String>> _loadUnlocked() {
    return DatabaseHelper.instance
        .getUnlockedAchievements()
        .catchError((_) => <String>{});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'ach_title')),
        centerTitle: true,
      ),
      body: FutureBuilder<Set<String>>(
        future: _loadUnlocked(),
        builder: (context, snapshot) {
          final unlocked = snapshot.data ?? const <String>{};
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemCount: Achievements.all.length,
            itemBuilder: (context, i) {
              final def = Achievements.all[i];
              final isUnlocked = unlocked.contains(def.id);
              return StaggeredEntrance(
                delayMs: i * 60,
                child: isUnlocked
                    ? _UnlockedTile(def: def)
                    : _LockedTile(def: def, isDark: isDark),
              );
            },
          );
        },
      ),
    );
  }
}

class _UnlockedTile extends StatelessWidget {
  final AchievementDef def;

  const _UnlockedTile({required this.def});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kGoldLight, kGold, kGoldDark],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kGold.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(def.icon, size: 44, color: kDeepGreenDark),
            const SizedBox(height: 10),
            Text(
              tr(context, def.titleKey),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kDeepGreenDark,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr(context, def.descKey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: kDeepGreenDark.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedTile extends StatelessWidget {
  final AchievementDef def;
  final bool isDark;

  const _LockedTile({required this.def, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? scheme.surfaceContainerHigh : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  def.icon,
                  size: 44,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.lock,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr(context, def.titleKey),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr(context, def.descKey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
