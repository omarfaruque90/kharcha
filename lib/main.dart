import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kharcha/providers/money_provider.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'providers/expense_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/add_expense_screen.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'services/lock_service.dart';
import 'services/notification_service.dart';
import 'services/recurring_service.dart';
import 'services/sms_service.dart';
import 'services/update_service.dart';

/// Brand colors: charcoal black + emerald (sleek dark).
const Color kCharcoal = Color(0xFF121212);
const Color kCharcoalSurface = Color(0xFF1E1E1E);
const Color kCharcoalCard = Color(0xFF2D2D2D);
const Color kEmerald = Color(0xFF10B981);
const Color kEmeraldDark = Color(0xFF059669);
const Color kEmeraldLight = Color(0xFFA7F3D0);

/// Global navigator key — lets background services (SMS listener, update
/// checker) show dialogs/snackbars without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase config comes from android/app/google-services.json.
  // Awaited: AuthGate reads Firebase Auth state before the first frame.
  await Firebase.initializeApp();
  // Awaited: home screen formats dates immediately; needs locale data.
  await initializeDateFormatting();
  // Awaited: fast local read; determines locale/theme before first frame.
  final settings = SettingsProvider();
  await settings.load();
  final expenses = ExpenseProvider();
  final money = MoneyProvider();
  // First frame NOW — the remaining boot work continues in the background
  // so the app opens instantly instead of blocking on services.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: expenses),
        ChangeNotifierProvider.value(value: money),
      ],
      child: const KharchaApp(),
    ),
  );
  unawaited(_finishBootInBackground(expenses, money));
}

/// Completes startup work without blocking the UI. Everything is
/// best-effort; a failing service must never break startup.
Future<void> _finishBootInBackground(
    ExpenseProvider expenses, MoneyProvider money) async {
  // Local data first so lists populate immediately.
  try {
    await expenses.load();
  } catch (_) {}
  try {
    await money.load();
  } catch (_) {}
  // System services — notifications, recurring expenses, SMS.
  try {
    await NotificationService.init();
  } catch (_) {}
  try {
    await RecurringService.processDue();
    // Recurring may have inserted expenses; refresh the list.
    await expenses.load();
  } catch (_) {}
  try {
    await NotificationService.scheduleBillReminders();
  } catch (_) {}
  SmsService.instance.attachNavigator(appNavigatorKey);
}

ColorScheme _brandScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: kEmerald,
    brightness: brightness,
  );
  if (brightness == Brightness.dark) {
    // Sleek dark hero: true charcoal surfaces instead of seed-derived ones.
    return base.copyWith(
      surface: kCharcoal,
      surfaceContainerLowest: kCharcoal,
      surfaceContainerLow: kCharcoalSurface,
      surfaceContainer: kCharcoalSurface,
      surfaceContainerHigh: kCharcoalCard,
      surfaceContainerHighest: kCharcoalCard,
    );
  }
  return base;
}

class KharchaApp extends StatelessWidget {
  const KharchaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'Kharcha',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      locale: Locale(settings.language),
      // Bundled localizations: without these, Locale('bn') has no
      // Material strings and the date picker renders a blank screen.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('bn'),
        Locale('en'),
      ],
      theme: ThemeData(
        colorScheme: _brandScheme(Brightness.light),
        useMaterial3: true,
        // --- Kharcha brand polish (shared by every screen) ---
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: kEmerald.withValues(alpha: 0.25),
          thickness: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: _brandScheme(Brightness.dark),
        useMaterial3: true,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: kEmerald.withValues(alpha: 0.25),
          thickness: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: settings.themeMode,
      home: const SplashScreen(),
    );
  }
}

/// Branded splash / welcome header shown at startup.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Logo bounces in first...
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
      ),
    );
    // ...then the tagline fades and slides up.
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.8, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    _controller.forward();
    // Brief brand flash only — navigate as soon as the animation completes.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const LockGate(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCharcoal,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/app_logo.png',
                    width: 140,
                    height: 140,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Kharcha',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: kEmerald,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _taglineOpacity,
                child: SlideTransition(
                  position: _taglineSlide,
                  child: Text(
                    tr(context, 'tagline'),
                    style:
                        const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Startup gate: shows the PIN/biometric lock screen when app lock is
/// enabled, otherwise goes straight to the Firebase auth flow.
///
/// Also kicks off the SMS listener and the in-app update check once the
/// navigator is ready (both need a BuildContext for their dialogs).
class LockGate extends StatefulWidget {
  const LockGate({super.key});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  /// null = checking, false = locked, true = unlocked / no lock.
  bool? _unlocked;
  bool _startupTasksDone = false;

  @override
  void initState() {
    super.initState();
    _checkLock();
  }

  Future<void> _checkLock() async {
    final enabled = await LockService.instance.isLockEnabled();
    if (!mounted) return;
    setState(() => _unlocked = !enabled);
    _runStartupTasks();
  }

  void _runStartupTasks() {
    if (_startupTasksDone) return;
    _startupTasksDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fire-and-forget: rationale/update dialogs handle their own errors.
      SmsService.instance.maybeStart();
      UpdateService.maybePromptOnStartup(appNavigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _unlocked;
    if (unlocked == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!unlocked) {
      return LockScreen(
        onUnlock: () {
          setState(() => _unlocked = true);
          _runStartupTasks();
        },
      );
    }
    return const AuthGate(home: MainShell());
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _goHome() => setState(() => _index = 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: IndexedStack(
          key: ValueKey<int>(_index),
          index: _index,
          children: [
            const HomeScreen(),
            AddExpenseScreen(onSaved: _goHome),
            const ReportsScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: tr(context, 'nav_home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline),
            selectedIcon: const Icon(Icons.add_circle),
            label: tr(context, 'nav_add'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: tr(context, 'nav_reports'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: tr(context, 'nav_settings'),
          ),
        ],
      ),
    );
  }
}
