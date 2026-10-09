import 'dart:async' show unawaited, Timer;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kharcha/providers/money_provider.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'db/database_helper.dart';
import 'models/bill_reminder.dart';
import 'models/custom_category.dart';
import 'theme/amoled.dart';
import 'utils/formatters.dart';
import 'providers/expense_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/total_balance_provider.dart';
import 'screens/add_expense_screen.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/more_screen.dart';
import 'services/lock_service.dart';
import 'services/achievements.dart';
import 'services/carry_forward_service.dart';
import 'services/challenge_service.dart';
import 'services/currency_service.dart';
import 'services/daily_limit_service.dart';
import 'services/home_widget_service.dart';
import 'services/monthly_report_service.dart';
import 'services/notification_center.dart';
import 'services/notification_service.dart';
import 'services/recurring_detect_service.dart';
import 'services/recurring_service.dart';
import 'services/salary_service.dart';
import 'services/scheduled_export_service.dart';
import 'services/stats_notification.dart';
import 'services/subscription_service.dart';
import 'services/update_check_worker.dart';
import 'services/update_service.dart';
import 'widgets/gooey_nav_bar.dart';
import 'widgets/motion.dart';

/// Brand colors: deep green + gold (matches the 3D expense logo).
const Color kDeepGreen = Color(0xFF0B3D2E);
const Color kDeepGreenDark = Color(0xFF072A1F);
const Color kDeepGreenSurface = Color(0xFF0A2B1E);
const Color kDeepGreenCard = Color(0xFF0E3B2C);
const Color kGold = Color(0xFFD4AF37);
const Color kGoldLight = Color(0xFFF0D878);
const Color kGoldDark = Color(0xFF9C7C1E);
const Color kEmerald = Color(0xFF10B981);
const Color kEmeraldDark = Color(0xFF059669);
const Color kEmeraldLight = Color(0xFFA7F3D0);

/// Custom accent themes (Package AF). 'gold' is the default brand accent.
const Map<String, Color> kAccents = {
  'gold': Color(0xFFD4AF37),
  'emerald': Color(0xFF10B981),
  'blue': Color(0xFF3B82F6),
  'purple': Color(0xFF8B5CF6),
  'orange': Color(0xFFF97316),
};

/// Light tint of each accent (replaces kGoldLight when a custom accent is
/// active).
const Map<String, Color> kAccentLights = {
  'gold': Color(0xFFF0D878),
  'emerald': Color(0xFFA7F3D0),
  'blue': Color(0xFFBFDBFE),
  'purple': Color(0xFFDDD6FE),
  'orange': Color(0xFFFED7AA),
};

/// Dark shade of each accent (replaces kGoldDark when a custom accent is
/// active).
const Map<String, Color> kAccentDarks = {
  'gold': Color(0xFF9C7C1E),
  'emerald': Color(0xFF059669),
  'blue': Color(0xFF1D4ED8),
  'purple': Color(0xFF7C3AED),
  'orange': Color(0xFFC2410C),
};

/// Global navigator key — lets background services (SMS listener, update
/// checker) show dialogs/snackbars without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

/// AC: deletes an SMS auto-added expense (undo from the notification).

/// AE: shows the bill photo + amount when a bill reminder is tapped.
Future<void> _showBillReminder(String reminderId) async {
  try {
    final reminders =
        await DatabaseHelper.instance.getActiveBillReminders();
    BillReminder? found;
    for (final r in reminders) {
      if (r.id == reminderId) {
        found = r;
        break;
      }
    }
    final ctx = appNavigatorKey.currentContext;
    if (found == null || ctx == null || !ctx.mounted) return;
    final r = found;
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(r.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.photoPath.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(r.photoPath),
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            const SizedBox(height: 8),
            Text(formatMoney(r.amount)),
            Text(tr(ctx, 'reminder_due_day')
                .replaceAll('{n}', r.dayOfMonth.toString())),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, 'close')),
          ),
        ],
      ),
    );
  } catch (_) {}
}

/// BM: suggests recurring entries for detected repeating expenses (once/month).
Future<void> _maybeSuggestRecurring() async {
  try {
    if (await RecurringDetectService.wasShownThisMonth()) return;
    final candidates = await RecurringDetectService.detect();
    if (candidates.isEmpty) return;
    await RecurringDetectService.markShown();
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final c = candidates.first;
    final create = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(tr(dctx, 'recurring_detect_title')),
        content: Text(
          tr(dctx, 'recurring_detect_body')
              .replaceAll('{name}', c.note)
              .replaceAll('{money}', formatMoney(c.amount)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(tr(dctx, 'dismiss')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(tr(dctx, 'create')),
          ),
        ],
      ),
    );
    if (create == true) {
      await RecurringDetectService.createFromCandidate(c);
    }
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsProvider();
  // Parallel init: Firebase, locale data and settings load concurrently
  // instead of one after another, so the first frame paints ASAP.
  // (AuthGate still reads Firebase Auth state only after init completes.)
  await Future.wait([
    Firebase.initializeApp(),
    initializeDateFormatting(),
    settings.load(),
    // BS: load the active profile before any DB access.
    DatabaseHelper.instance.loadProfile(),
  ]);
  final expenses = ExpenseProvider();
  final money = MoneyProvider();
  final totalBalance = TotalBalanceProvider();
  expenses.totalBalance = totalBalance;
  money.totalBalance = totalBalance;
  // First frame NOW — the remaining boot work continues in the background
  // so the app opens instantly instead of blocking on services.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: expenses),
        ChangeNotifierProvider.value(value: money),
        ChangeNotifierProvider.value(value: totalBalance),
      ],
      child: const KharchaApp(),
    ),
  );
  unawaited(_finishBootInBackground(expenses, money));
  unawaited(totalBalance.load());
}

/// Completes startup work without blocking the UI. Everything is
/// best-effort; a failing service must never break startup — and no
/// failure may leak out as an unhandled async error to the zone.
Future<void> _finishBootInBackground(
    ExpenseProvider expenses, MoneyProvider money) async {
  try {
    await _finishBootInBackgroundImpl(expenses, money);
  } catch (_) {
    // Safety net: every step below is already individually guarded.
  }
}

/// Background boot implementation. Each service call is individually
/// try/catch-guarded so one bad service can never abort the rest.
Future<void> _finishBootInBackgroundImpl(
    ExpenseProvider expenses, MoneyProvider money) async {
  // Custom-category registry first — display code needs correct labels.
  try {
    CustomCategoryRegistry.setAll(
      await DatabaseHelper.instance.getCustomCategories(),
    );
    CustomCategoryRegistry.onHiddenChanged =
        (hidden) => DatabaseHelper.instance.setHiddenCategories(hidden);
    CustomCategoryRegistry.setHidden(
      await DatabaseHelper.instance.getHiddenCategories(),
    );
  } catch (_) {}
  // Local data in parallel so lists populate immediately.
  try {
    await Future.wait([expenses.load(), money.load()]);
  } catch (_) {}
  // System services — notifications, recurring expenses, SMS.
  try {
    await NotificationService.init();
  } catch (_) {}
  // Tapping the background "update available" notification opens the
  // update dialog directly.
  NotificationService.onTap = (payload) {
    if (payload == 'app_update') {
      UpdateService.promptNow(appNavigatorKey);
    } else if (payload != null && payload.startsWith('bill_')) {
      // AE: show the bill photo + amount on reminder tap.
      _showBillReminder(payload.substring(5));
    }
  };
  // Periodic background update check -> phone notification when a new
  // version is published. Fire-and-forget.
  UpdateCheckWorker.schedule();
  // Wire tray notifications for the in-app notification center.
  NotificationCenter.systemNotify = ({
    required String title,
    required String body,
  }) =>
      NotificationService.showNow(title: title, body: body);
  try {
    await RecurringService.processDue();
    // Recurring may have inserted expenses; refresh the list.
    await expenses.load();
  } catch (_) {}
  try {
    await NotificationService.scheduleBillReminders();
  } catch (_) {}
  // New v0.2 services: subscription due checks + monthly auto-report.
  // Fire-and-forget, best-effort.
  SubscriptionService.checkDue();
  MonthlyReportService.maybeSend();
  // v0.2 batch 2: salary day, challenges, achievements, quick-add.
  SalaryService.checkSalaryDay(expenses, money);
  ChallengeService.checkDaily();
  Achievements.checkAll();
  // v0.2 batch 4: carry-forward, recurring detect, stats notification.
  CarryForwardService.maybeRollover();
  StatsNotification.init();
  // v0.3 batch: best-effort startup extras, each individually guarded so
  // one bad service can never abort the rest (mirrors the neighbors).
  try {
    DailyLimitService.check(expenses);
  } catch (_) {}
  try {
    ScheduledExportService.maybeRun();
  } catch (_) {}
  try {
    CurrencyService.loadCached();
    CurrencyService.refreshRates();
  } catch (_) {}
  _maybeSuggestRecurring();
  // Keep the Android home widget in sync: debounced refresh whenever
  // expenses or income change, plus once after boot.
  HomeWidgetService.refreshFrom(expenses, money);
  Timer? widgetTimer;
  void scheduleWidgetSync() {
    widgetTimer?.cancel();
    widgetTimer = Timer(
      const Duration(seconds: 2),
      () => HomeWidgetService.refreshFrom(expenses, money),
    );
  }

  expenses.addListener(scheduleWidgetSync);
  money.addListener(scheduleWidgetSync);
  // Prime the notification bell badge.
  await NotificationCenter.refreshUnread();
}

ColorScheme _brandScheme(Brightness brightness, String accent,
    [Color? customColor]) {
  final base = ColorScheme.fromSeed(
    seedColor: kDeepGreen,
    brightness: brightness,
  );
  final accentColor = accent == 'custom' && customColor != null
      ? customColor
      : (kAccents[accent] ?? kGold);
  final accentDark = kAccentDarks[accent] ?? kGoldDark;
  // Text/icon color on top of the accent: dark green on light accents
  // (gold), white on saturated ones. Matches the original gold behavior.
  final onAccent =
      ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
          ? Colors.white
          : kDeepGreenDark;
  if (brightness == Brightness.dark) {
    // iOS dark: pure black background, #1C1C1E cards, accent primary.
    // Brand gold stays the accent — the jewelry, not the canvas.
    return base.copyWith(
      primary: accentColor,
      onPrimary: onAccent,
      secondary: kEmerald,
      surface: const Color(0xFF1C1C1E),
      surfaceContainerLowest: const Color(0xFF0A0A0C),
      surfaceContainerLow: const Color(0xFF1C1C1E),
      surfaceContainer: const Color(0xFF1C1C1E),
      surfaceContainerHigh: const Color(0xFF2C2C2E),
      surfaceContainerHighest: const Color(0xFF3A3A3C),
    );
  }
  // iOS light: #F2F2F7 grouped background, white cards, deep green
  // headers + gold accent highlights.
  return base.copyWith(
    primary: kDeepGreen,
    onPrimary: Colors.white,
    secondary: accentDark,
    surface: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF7F7F9),
    surfaceContainer: const Color(0xFFF2F2F7),
    surfaceContainerHigh: const Color(0xFFE9E9EE),
    surfaceContainerHighest: const Color(0xFFE4E4E9),
  );
}

/// Shared premium fintech theme: accent primary buttons, accent focused
/// inputs, accent selected chips, deep-green app bars with accent titles.
ThemeData _buildTheme(Brightness brightness, String accent,
    [Color? customColor]) {
  final scheme = _brandScheme(brightness, accent, customColor);
  final dark = brightness == Brightness.dark;
  final accentColor = accent == 'custom' && customColor != null
      ? customColor
      : (kAccents[accent] ?? kGold);
  final accentLight = accent == 'custom' && customColor != null
      ? Color.lerp(customColor, Colors.white, 0.6)!
      : (kAccentLights[accent] ?? kGoldLight);
  final accentDark = accent == 'custom' && customColor != null
      ? Color.lerp(customColor, Colors.black, 0.3)!
      : (kAccentDarks[accent] ?? kGoldDark);
  final onAccent =
      ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
          ? Colors.white
          : kDeepGreenDark;
  final accentText = dark ? accentLight : accentDark;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // iOS grouped background.
    scaffoldBackgroundColor:
        dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
    // iOS cards: white / #1C1C1E, 16px radius, soft shadow in light.
    cardTheme: CardThemeData(
      elevation: dark ? 0 : 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      color: dark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: EdgeInsets.zero,
    ),
    // iOS navigation bar: clean, semibold title in label color.
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: dark
          ? const Color(0xFF000000).withValues(alpha: 0.85)
          : const Color(0xFFF2F2F7).withValues(alpha: 0.85),
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FastPageTransitionsBuilder(),
        TargetPlatform.iOS: FastPageTransitionsBuilder(),
      },
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      side: BorderSide(
          color: accentColor.withValues(alpha: dark ? 0.45 : 0.6)),
      selectedColor: accentColor,
      checkmarkColor: onAccent,
      // Unselected chip text: explicit color, otherwise it can resolve
      // to white on the light background in light mode.
      labelStyle: TextStyle(
        fontWeight: FontWeight.w500,
        color: dark ? Colors.white : kDeepGreenDark,
      ),
      // Selected chip text sits on the accent background.
      secondaryLabelStyle: TextStyle(
        color: onAccent,
        fontWeight: FontWeight.bold,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: onAccent,
        disabledBackgroundColor: accentColor.withValues(alpha: 0.35),
        disabledForegroundColor: onAccent.withValues(alpha: 0.6),
        textStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: accentColor.withValues(alpha: 0.65)),
        foregroundColor: accentText,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      // iOS style: borderless, filled light-gray inputs.
      filled: true,
      fillColor: dark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFFE9E9EE),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: accentColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      floatingLabelStyle: TextStyle(
        color: accentText,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: dark
            ? const Color(0xFF98989F)
            : const Color(0xFF8E8E93),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor:
          dark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor:
          dark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: dark
          ? const Color(0x1FE5E5EA)
          : const Color(0x143C3C43),
      thickness: 0.5,
      space: 0,
    ),
    // iOS-style switches.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return dark ? const Color(0xFF48484A) : Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accentColor;
        return dark
            ? const Color(0xFF39393D)
            : const Color(0xFFE4E4E9);
      }),
      trackOutlineColor:
          const WidgetStatePropertyAll(Colors.transparent),
    ),
    // iOS-like text hierarchy: tighter tracking, semibold titles.
    textTheme: ThemeData.light().textTheme.copyWith(
          displayLarge: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5),
          headlineSmall: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3),
          titleLarge: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2),
          titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1),
          bodyLarge:
              const TextStyle(fontSize: 17, letterSpacing: -0.1),
          bodyMedium:
              const TextStyle(fontSize: 15, letterSpacing: -0.1),
          labelLarge: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1),
        ),
  );
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
        Locale('hi'),
        Locale('ur'),
        Locale('ar'),
        Locale('fa'),
        Locale('es'),
        Locale('fr'),
        Locale('de'),
        Locale('pt'),
        Locale('ru'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
        Locale('tr'),
        Locale('id'),
        Locale('ms'),
        Locale('vi'),
        Locale('th'),
        Locale('it'),
        Locale('nl'),
      ],
      // Hand-rolled strings carry no text direction, so force RTL for
      // Arabic/Urdu/Persian (the material delegates already do this for dialogs etc.).
      builder: (context, child) {
        final lang = settings.language;
        final scaled = MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(settings.fontScale),
        );
        final rtl = Directionality(
          textDirection: (lang == 'ar' || lang == 'ur' || lang == 'fa')
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        );
        return MediaQuery(data: scaled, child: rtl);
      },
      theme: _buildTheme(
          Brightness.light, settings.accent, settings.customColor),
      darkTheme: settings.amoled
          ? buildAmoledTheme(settings.accent == 'custom'
              ? settings.customColor
              : (kAccents[settings.accent] ?? kGold))
          : _buildTheme(
              Brightness.dark, settings.accent, settings.customColor),
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
      duration: const Duration(milliseconds: 500),
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
    Future.delayed(const Duration(milliseconds: 600), () {
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
      backgroundColor: kDeepGreenDark,
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
                'Khorcha',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: kGold,
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
      UpdateService.maybePromptOnStartup(appNavigatorKey);
      // App opened by tapping a notification while terminated.
      NotificationService.launchPayload().then((payload) {
        if (payload == 'app_update') {
          UpdateService.promptNow(appNavigatorKey);
        } else if (payload != null && payload.startsWith('bill_')) {
          _showBillReminder(payload.substring(5));
        }
      });
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
    // First-run showcase goes after auth/lock, before the main shell —
    // shown exactly once via OnboardingGate.
    return const AuthGate(home: OnboardingGate(child: MainShell()));
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// Direction of the last tab switch: +1 (moved right) or -1 (moved left).
  /// Drives the slide direction of the tab-switch animation.
  int _slideDir = 1;

  void _goHome() => _goTo(0);
  void _goAdd() => _goTo(2);

  void _goTo(int i) {
    if (i == _index) return;
    setState(() {
      _slideDir = i > _index ? 1 : -1;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Back from any tab goes to Home first (never exits the app directly).
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _goHome();
      },
      child: Scaffold(
      // No bottomNavigationBar — navbar floats directly over content
      // via Stack, so there is no extra background area behind it.
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            reverseDuration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            transitionBuilder:
                (Widget child, Animation<double> animation) {
          // Direction-aware: new tab glides in from the tapped side,
          // buttery fade + gentle scale for depth.
          final slide = Tween<Offset>(
            begin: Offset(0.10 * _slideDir, 0),
            end: Offset.zero,
          ).animate(animation);
          final scale = Tween<double>(begin: 0.98, end: 1.0)
              .animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
        child: IndexedStack(
          key: ValueKey<int>(_index),
          index: _index,
          children: [
            const HomeScreen(),
            HistoryScreen(onAddPressed: _goAdd),
            AddExpenseScreen(onSaved: _goHome),
            const ReportsScreen(),
            const MoreScreen(),
          ],
        ),
          ),
          // Floating navbar — no separate background area.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GooeyNavBar(
              index: _index,
              onTap: _goTo,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Custom 5-tab bottom bar: Home, History, big gold center Add,
/// Reports, More. The center button is raised with a gold glow.
