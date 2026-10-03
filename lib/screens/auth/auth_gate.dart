import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart';
import '../../providers/expense_provider.dart';
import '../../providers/money_provider.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import 'login_screen.dart';

/// Routes between the login flow and the main app based on Firebase auth
/// state. After login it kicks off [SyncService.startSync] once, keeps the
/// UI fresh via [SyncService.remoteChanges], then shows [home].
class AuthGate extends StatelessWidget {
  final Widget home;

  const AuthGate({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoading();
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return _SyncedHome(
          key: ValueKey(user.uid),
          uid: user.uid,
          home: home,
        );
      },
    );
  }
}

/// Starts per-user cloud sync, then shows the main app.
class _SyncedHome extends StatefulWidget {
  final String uid;
  final Widget home;

  const _SyncedHome({super.key, required this.uid, required this.home});

  @override
  State<_SyncedHome> createState() => _SyncedHomeState();
}

class _SyncedHomeState extends State<_SyncedHome> {
  bool _ready = false;
  StreamSubscription<void>? _remoteSub;

  @override
  void initState() {
    super.initState();
    // Refresh the expense list when another device changes the cloud data.
    _remoteSub = SyncService.instance.remoteChanges.listen((_) {
      if (mounted) {
        context.read<ExpenseProvider>().load();
        context.read<MoneyProvider>().load();
      }
    });
    _boot();
  }

  Future<void> _boot() async {
    try {
      await SyncService.instance.startSync(widget.uid);
    } catch (_) {
      // Offline / rules not set yet — the app still works locally.
    }
    // Reload the providers so merged cloud data shows up immediately.
    if (mounted) {
      await context.read<ExpenseProvider>().load();
      await context.read<MoneyProvider>().load();
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const _AuthLoading();
    return widget.home;
  }
}

/// Branded loading screen (auth resolving / first sync).
class _AuthLoading extends StatelessWidget {
  const _AuthLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kEmerald,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/app_logo.png',
                  width: 110,
                  height: 110,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: kGold,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) => Text(
                  tr(context, 'auth_syncing'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
