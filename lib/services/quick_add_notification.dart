import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../db/database_helper.dart';
import '../models/expense.dart';
import '../models/expense_template.dart';

/// Package W — persistent quick-add notification.
///
/// Shows an ONGOING notification (id 9002, channel 'khorcha_quickadd')
/// whose action buttons map to the user's first 3 expense templates.
/// Tapping a button inserts the expense straight into the local DB (and
/// syncs via [DatabaseHelper.insertExpense]) without opening the app,
/// then fires a brief confirmation notification.
///
/// This service owns its own [FlutterLocalNotificationsPlugin] instance
/// (separate from [NotificationService]'s) so action taps are handled
/// here even when the app is in the background. NOTE: on Android the
/// native plugin channel keeps only the most-recently-registered
/// notification-response callback, so the coordinator must call
/// [show]/[_ensureInit] AFTER NotificationService.init() at startup and
/// route non-quick-add taps via [onBodyTap] (see wiring notes).
class QuickAddNotification {
  QuickAddNotification._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const int _notifId = 9002;
  static const int _confirmId = 9003;
  static const String _channelId = 'khorcha_quickadd';
  static const String _actionPrefix = 'quickadd_';

  /// Set by the coordinator: receives payloads from taps that are NOT
  /// quick-add actions (e.g. body tap with payload 'open_app'), so the
  /// app's normal notification-tap routing keeps working. Default no-op.
  static void Function(String? payload)? onBodyTap;

  /// Show (or refresh) the ongoing quick-add notification. Best-effort:
  /// never throws.
  static Future<void> show() async {
    try {
      await _ensureInit();
      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final bn = lang == 'bn';
      final templates = await DatabaseHelper.instance.getTemplates();
      final top = templates.take(3).toList();

      final actions = top
          .map((t) => AndroidNotificationAction(
                '$_actionPrefix${t.id ?? ''}',
                '${t.emoji} ${t.name}'.trim(),
              ))
          .toList();

      final title = bn ? 'খরচ দ্রুত যোগ করুন' : 'Khorcha quick add';
      final String body;
      if (top.isEmpty) {
        body = bn
            ? 'টেমপ্লেট যোগ করে এক ট্যাপে খরচ যোগ করুন'
            : 'Add templates to quick-add expenses with one tap';
      } else {
        body = top.map((t) => '${_label(t)} — ৳${_amt(t.amount)}').join('\n');
      }

      await _plugin.show(
        id: _notifId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Quick add',
            importance: Importance.high,
            ongoing: true,
            showWhen: false,
            actions: actions,
          ),
        ),
        // No templates → body tap just opens the app (coordinator routes
        // the 'open_app' payload).
        payload: 'open_app',
      );
    } catch (_) {
      // Quick-add must never crash the caller.
    }
  }

  /// Remove the ongoing quick-add notification (and any leftover
  /// confirmation). Best-effort.
  static Future<void> hide() async {
    try {
      await _plugin.cancel(id: _notifId);
      await _plugin.cancel(id: _confirmId);
    } catch (_) {}
  }

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _handleResponse,
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      const channel = AndroidNotificationChannel(
        _channelId,
        'Quick add',
        description: 'One-tap expense entry from templates',
        importance: Importance.high,
      );
      await android?.createNotificationChannel(channel);
    } catch (_) {
      // Init is best-effort; show() will simply no-op on failure.
    }
  }

  /// Public entry point for the app-wide tap chain. StatsNotification's
  /// native callback is registered LAST at startup (so it wins natively)
  /// and forwards every response here: quick-add action buttons are
  /// handled, everything else falls through to [onBodyTap].
  static Future<void> routeResponse(NotificationResponse response) =>
      _handleResponse(response);

  static Future<void> _handleResponse(NotificationResponse response) async {
    try {
      final actionId = response.actionId;
      if (actionId != null && actionId.startsWith(_actionPrefix)) {
        final templateId = actionId.substring(_actionPrefix.length);
        await _quickAdd(templateId);
        return;
      }
      // Not a quick-add action: let the coordinator route it (e.g. the
      // 'open_app' body tap).
      onBodyTap?.call(response.payload);
    } catch (_) {
      // Never crash on a background tap.
    }
  }

  /// Loads the template with [templateId] and inserts an expense from it.
  static Future<void> _quickAdd(String templateId) async {
    try {
      if (templateId.isEmpty) return;
      final templates = await DatabaseHelper.instance.getTemplates();
      ExpenseTemplate? found;
      for (final t in templates) {
        if ((t.id ?? '') == templateId) {
          found = t;
          break;
        }
      }
      final t = found;
      if (t == null) return; // Template was deleted after show().

      // NOTE: as of implementation time the Expense constructor does NOT
      // accept currency/bdtAmount/mood (another package may add them in
      // parallel). If those fields land in the model, extend this
      // constructor call with currency: 'BDT', bdtAmount: t.amount.
      final expense = Expense(
        amount: t.amount,
        categoryId: t.categoryId.isNotEmpty ? t.categoryId : 'others',
        date: DateTime.now(),
        note: t.name,
        paymentMethod: t.payment.isNotEmpty ? t.payment : 'cash',
      );
      await DatabaseHelper.instance.insertExpense(expense);
      await _showConfirmation(t);
    } catch (_) {
      // Best-effort insert; never throw from a background tap.
    }
  }

  /// Brief, dismissible confirmation that the quick-add landed.
  static Future<void> _showConfirmation(ExpenseTemplate t) async {
    try {
      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final bn = lang == 'bn';
      await _plugin.show(
        id: _confirmId,
        title: bn ? 'যোগ হয়েছে ✓' : 'Added ✓',
        body: '${_label(t)} — ৳${_amt(t.amount)}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Quick add',
            importance: Importance.high,
            autoCancel: true,
          ),
        ),
      );
    } catch (_) {}
  }

  static String _label(ExpenseTemplate t) {
    final name = t.name.isNotEmpty ? t.name : '—';
    return t.emoji.isNotEmpty ? '${t.emoji} $name' : name;
  }

  static String _amt(double amount) {
    final whole = amount % 1 == 0;
    return amount.toStringAsFixed(whole ? 0 : 2);
  }
}
