import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/project.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/category_learner.dart';
import '../services/currency_service.dart';
import '../services/notification_center.dart';
import '../services/ocr_categorize.dart';
import '../services/ocr_service.dart';
import '../widgets/calculator_pad.dart';
import '../widgets/branded_date_picker.dart';
import '../widgets/motion.dart';
import '../widgets/payment_selector.dart';

/// Add a new expense, or edit [expense] when provided.
/// Used both as the "Add" bottom-nav tab and as a pushed edit page.
class AddExpenseScreen extends StatefulWidget {
  final Expense? expense;
  final VoidCallback? onSaved;

  const AddExpenseScreen({super.key, this.expense, this.onSaved});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _categoryId = 'food';
  DateTime _date = DateTime.now();
  String _payment = 'cash';
  String? _receiptPath;
  bool _showCalculator = false;
  bool _showSuccess = false;
  bool _scanning = false;
  // Package V/AB: currency picker and mood tag.
  String _currency = 'BDT';
  String _mood = '';
  // Package Y: set when receipt OCR autofilled amount/date.
  bool _ocrAutofilled = false;
  List<CustomCategory> _customCats = [];
  // Package AP: project assignment ('' = no project).
  String _projectId = '';
  List<Project> _projects = [];
  // Package AZ: attached GPS location.
  double? _lat, _lng;
  bool _locating = false;
  // Package BA: OCR auto-categorize.
  bool _categoryManuallyPicked = false;
  bool _ocrAutoCategory = false;
  // Package BG: smart category suggestion from the note text.
  Timer? _suggestDebounce;
  String? _suggestedCategoryId;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e != null) {
      final whole = e.amount.truncateToDouble() == e.amount;
      _amountCtrl.text =
          whole ? e.amount.toStringAsFixed(0) : e.amount.toString();
      _noteCtrl.text = e.note;
      _categoryId = e.categoryId;
      _date = e.date;
      _payment = e.paymentMethod;
      _receiptPath = e.receiptPath;
      _currency = e.currency;
      _mood = e.mood;
      // Package AP/AZ: restore project and location on edit.
      _projectId = e.projectId;
      _lat = e.lat;
      _lng = e.lng;
      // Legacy/synced data may hold a code the picker doesn't offer —
      // DropdownButton throws if value isn't in items.
      if (!CurrencyService.supported.contains(_currency)) {
        _currency = 'BDT';
      }
    }
    _loadCustomCategories();
    // Package AP: load projects for the project dropdown.
    DatabaseHelper.instance.getProjects().then((ps) {
      if (mounted) {
        setState(() {
          _projects = ps;
          // Editing an expense whose project was deleted: coerce to ''
          // so the dropdown value always matches an item (a value with
          // no matching item throws in debug and misbehaves in release).
          if (_projectId.isNotEmpty &&
              !_projects.any((p) => p.id == _projectId)) {
            _projectId = '';
          }
        });
      }
    });
  }

  Future<void> _loadCustomCategories() async {
    try {
      final cats = await DatabaseHelper.instance.getCustomCategories();
      CustomCategoryRegistry.setAll(cats);
      if (mounted) setState(() => _customCats = cats);
    } catch (_) {}
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(String lang) async {
    final picked = await showBrandedDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      // Only pass a locale the bundled flutter_localizations supports;
      // null falls back to the app locale (bn/en are both bundled).
      locale: lang == 'en' ? const Locale('en') : null,
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save(String lang) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.parse(_amountCtrl.text.trim());
    final provider = context.read<ExpenseProvider>();
    final money = context.read<MoneyProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final db = DatabaseHelper.instance;

    // Remember custom payment labels for reuse suggestions.
    if (_payment.startsWith('other:')) {
      final customLabel = _payment.substring('other:'.length).trim();
      if (customLabel.isNotEmpty) {
        await db.upsertCustomPaymentByLabel(customLabel);
      }
    }

    if (_isEdit) {
      // Built explicitly (not copyWith): place/receiptPath must be
      // clearable, and copyWith cannot distinguish "set to null".
      final updated = Expense(
        id: widget.expense?.id,
        amount: amount,
        categoryId: _categoryId,
        date: _date,
        note: _noteCtrl.text.trim(),
        paymentMethod: _payment,
        place: null,
        receiptPath: _receiptPath,
        currency: _currency,
        bdtAmount: CurrencyService.toBdt(amount, _currency),
        mood: _mood,
        projectId: _projectId,
        lat: _lat,
        lng: _lng,
      );
      await provider.update(updated);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.get('msg_updated', lang))),
      );
      navigator.pop();
    } else {
      await provider.add(
        Expense(
          amount: amount,
          categoryId: _categoryId,
          date: _date,
          note: _noteCtrl.text.trim(),
          paymentMethod: _payment,
          place: null,
          receiptPath: _receiptPath,
          currency: _currency,
          bdtAmount: CurrencyService.toBdt(amount, _currency),
          mood: _mood,
          projectId: _projectId,
          lat: _lat,
          lng: _lng,
        ),
      );
      if (!mounted) return;
      // Fire-and-forget: budget near-limit / exceeded alerts.
      unawaited(_checkBudgetAlerts(
        money: money,
        categoryId: _categoryId,
        date: _date,
        lang: lang,
      ));
      // Animated success check, then reset and go home.
      setState(() => _showSuccess = true);
      await Future.delayed(const Duration(milliseconds: 950));
      if (!mounted) return;
      setState(() => _showSuccess = false);
      _amountCtrl.clear();
      _noteCtrl.clear();
      setState(() {
        _categoryId = 'food';
        _date = DateTime.now();
        _payment = 'cash';
        _receiptPath = null;
        _showCalculator = false;
        _currency = 'BDT';
        _mood = '';
        _ocrAutofilled = false;
        // Package AP/AZ/BA/BG: reset project, location, OCR and
        // suggestion state with the rest of the form.
        _projectId = '';
        _lat = null;
        _lng = null;
        _categoryManuallyPicked = false;
        _ocrAutoCategory = false;
        _suggestDebounce?.cancel();
        _suggestedCategoryId = null;
      });
      widget.onSaved?.call();
    }
  }

  /// Pushes budget near-limit / exceeded notifications after an expense is
  /// saved. Deduped per budget per day so it never spams.
  Future<void> _checkBudgetAlerts({
    required MoneyProvider money,
    required String categoryId,
    required DateTime date,
    required String lang,
  }) async {
    try {
      if (!money.isLoaded) await money.load();
      final key = monthKeyOf(date);
      final spentByCat = await money.expenseForMonth(key);
      final catName = CustomCategoryRegistry.displayName(categoryId, lang);

      final catBudget = money.budgetFor(categoryId, key);
      if (catBudget != null && catBudget.limitAmount > 0) {
        final spent = spentByCat[categoryId] ?? 0;
        final limit = catBudget.limitAmount;
        if (spent >= limit) {
          await NotificationCenter.push(
            title: AppStrings.get('budget_exceeded', lang),
            body: AppStrings.get('notif_budget_over_body', lang)
                .replaceAll('{category}', catName)
                .replaceAll('{over}', _fmtNum(spent - limit)),
            type: 'budget',
            dedupeKey: 'cat:$categoryId:$key:over',
          );
        } else if (spent >= limit * 0.8) {
          await NotificationCenter.push(
            title: AppStrings.get('budget_near_limit', lang),
            body: AppStrings.get('notif_budget_near_body', lang)
                .replaceAll('{category}', catName)
                .replaceAll('{spent}', _fmtNum(spent))
                .replaceAll('{limit}', _fmtNum(limit)),
            type: 'budget',
            dedupeKey: 'cat:$categoryId:$key:near',
          );
        }
      }

      final monthBudget = money.monthlyBudgetFor(key);
      if (monthBudget != null && monthBudget.limitAmount > 0) {
        final total = spentByCat.values.fold(0.0, (a, b) => a + b);
        final limit = monthBudget.limitAmount;
        final name = AppStrings.get('monthly_budget', lang);
        if (total >= limit) {
          await NotificationCenter.push(
            title: AppStrings.get('budget_exceeded', lang),
            body: AppStrings.get('notif_budget_over_body', lang)
                .replaceAll('{category}', name)
                .replaceAll('{over}', _fmtNum(total - limit)),
            type: 'budget',
            dedupeKey: 'month:$key:over',
          );
        } else if (total >= limit * 0.8) {
          await NotificationCenter.push(
            title: AppStrings.get('budget_near_limit', lang),
            body: AppStrings.get('notif_budget_near_body', lang)
                .replaceAll('{category}', name)
                .replaceAll('{spent}', _fmtNum(total))
                .replaceAll('{limit}', _fmtNum(limit)),
            type: 'budget',
            dedupeKey: 'month:$key:near',
          );
        }
      }
    } catch (_) {
      // Alerts are best-effort; never break the save flow.
    }
  }

  String _fmtNum(double value) {
    final whole = value.truncateToDouble() == value;
    return whole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file != null && mounted) {
        setState(() => _receiptPath = file.path);
        // Package Y: OCR autofill the amount/date from the receipt.
        unawaited(_ocrAutofill(file));
      }
    } catch (_) {
      // Permission denied or picker unavailable — leave the form as-is.
    }
  }

  /// Package Y: runs the existing OCR service on an attached receipt and
  /// autofills the amount and date. Manual edits always win: the amount is
  /// only filled when the field is still empty.
  Future<void> _ocrAutofill(XFile file) async {
    try {
      final result = await OcrService.scanBillAmount(file);
      if (!mounted || result == null) return;
      var touched = false;
      final amount = result['amount'] as double?;
      if (amount != null && _amountCtrl.text.trim().isEmpty) {
        final whole = amount.truncateToDouble() == amount;
        _amountCtrl.text =
            whole ? amount.toStringAsFixed(0) : amount.toString();
        touched = true;
      }
      final raw = result['rawText'] as String? ?? '';
      final date = _extractDateFromText(raw);
      if (date != null) {
        _date = date;
        touched = true;
      }
      // Package BA: auto-categorize from the OCR merchant text unless the
      // user has already picked a category by hand.
      final autoCat = categorizeShop(raw);
      if (autoCat != null && !_categoryManuallyPicked) {
        _categoryId = autoCat;
        _ocrAutoCategory = true;
        touched = true;
      }
      if (touched && mounted) {
        // _categoryId/_ocrAutoCategory were assigned above; one rebuild
        // reflects amount/date/category together.
        setState(() => _ocrAutofilled = true);
      }
    } catch (_) {
      // OCR is best-effort; never break the receipt flow.
    }
  }

  /// Package AZ: attach the current GPS location to this expense.
  Future<void> _attachLocation() async {
    final lang = context.read<SettingsProvider>().language;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('location permission denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang == 'bn'
              ? 'লোকেশন যোগ হয়েছে'
              : 'Location attached'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'expense_location_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Extracts a plausible receipt date from OCR text.
  /// Matches DD/MM/YYYY, DD-MM-YYYY, YYYY/MM/DD and YYYY-MM-DD.
  DateTime? _extractDateFromText(String text) {
    final dmy = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})\b');
    final ymd = RegExp(r'\b(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b');
    // Try both; take the first valid, non-future date found.
    for (final re in [ymd, dmy]) {
      for (final m in re.allMatches(text)) {
        int y, mo, d;
        try {
          if (identical(re, ymd)) {
            y = int.parse(m.group(1)!);
            mo = int.parse(m.group(2)!);
            d = int.parse(m.group(3)!);
          } else {
            d = int.parse(m.group(1)!);
            mo = int.parse(m.group(2)!);
            y = int.parse(m.group(3)!);
          }
        } catch (_) {
          continue;
        }
        if (y < 2000 || y > 2100 || mo < 1 || mo > 12 || d < 1 || d > 31) {
          continue;
        }
        final date = DateTime(y, mo, d);
        if (date.year != y || date.month != mo || date.day != d) continue;
        if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) {
          continue;
        }
        return date;
      }
    }
    return null;
  }

  /// v5: bill OCR — snap a bill, extract the total, fill the amount field.
  Future<void> _scanBill() async {
    if (_scanning) return;
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2000,
        imageQuality: 90,
      );
    } catch (_) {
      // Camera permission denied or picker unavailable.
      return;
    }
    // Bind to a final so the null-promotion survives the setState closure.
    final picked = file;
    if (picked == null || !mounted) return;
    setState(() => _scanning = true);
    // Keep the photo as the receipt attachment too.
    setState(() => _receiptPath = picked.path);
    try {
      final result = await OcrService.scanBillAmount(file);
      if (!mounted) return;
      final amount = result?['amount'] as double?;
      if (amount != null) {
        final whole = amount.truncateToDouble() == amount;
        _amountCtrl.text =
            whole ? amount.toStringAsFixed(0) : amount.toString();
        // Package Y: also try to pick up the bill date.
        final raw = result?['rawText'] as String?;
        final billDate = raw != null ? _extractDateFromText(raw) : null;
        if (billDate != null) _date = billDate;
        setState(() => _ocrAutofilled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, 'bill_scanned')
                  .replaceAll('{amount}', _amountCtrl.text),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'bill_scan_failed'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'bill_scan_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(_date);

    String? validateAmount(String? v) {
      final text = (v ?? '').trim();
      if (text.isEmpty) return AppStrings.get('err_amount_empty', lang);
      final parsed = double.tryParse(text);
      if (parsed == null || parsed <= 0) {
        return AppStrings.get('err_amount_invalid', lang);
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, _isEdit ? 'edit_expense' : 'add_expense')),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StaggeredEntrance(
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    decoration: InputDecoration(
                      labelText: tr(context, 'amount'),
                      hintText: tr(context, 'amount_hint'),
                      prefixText:
                          '${CurrencyService.symbols[_currency] ?? '৳'} ',
                      prefixStyle:
                          theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 18),
                    ),
                    validator: validateAmount,
                  ),
                ),
                const SizedBox(width: 8),
                // Package V: currency of the entered amount.
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: kGold.withValues(alpha: 0.55),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color:
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _currency,
                      borderRadius: BorderRadius.circular(12),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      items: [
                        for (final code in CurrencyService.supported)
                          DropdownMenuItem(
                            value: code,
                            child: Text(
                              '${CurrencyService.symbols[code]} $code',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _IconSquare(
                  icon: Icons.calculate_outlined,
                  active: _showCalculator,
                  onTap: () =>
                      setState(() => _showCalculator = !_showCalculator),
                ),
                const SizedBox(width: 8),
                _IconSquare(
                  icon: Icons.calendar_month_outlined,
                  active: false,
                  onTap: () => _pickDate(lang),
                ),
              ],
              ),
            ),
            if (_showCalculator) ...[
              const SizedBox(height: 12),
              CalculatorPad(
                onResult: (value) {
                  final whole = value.truncateToDouble() == value;
                  _amountCtrl.text = whole
                      ? value.toStringAsFixed(0)
                      : _trimDecimals(value);
                },
              ),
            ],
            const SizedBox(height: 16),
            StaggeredEntrance(
              delayMs: 60,
              child: _sectionLabel(context, tr(context, 'category')),
            ),
            const SizedBox(height: 10),
            StaggeredEntrance(
              delayMs: 90,
              child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              // Built-ins + user-created categories + the "add" tile.
              itemCount: kCategories.length + _customCats.length + 1,
              itemBuilder: (ctx, i) {
                if (i < kCategories.length) {
                  final c = kCategories[i];
                  return _categoryTile(
                    label: AppStrings.categoryName(c.id, lang),
                    color: c.color,
                    selected: _categoryId == c.id,
                    iconChild: Icon(c.icon, color: c.color, size: 26),
                    onTap: () => setState(() {
                      _categoryId = c.id;
                      _categoryManuallyPicked = true;
                      _ocrAutoCategory = false;
                    }),
                  );
                }
                final ci = i - kCategories.length;
                if (ci < _customCats.length) {
                  final cc = _customCats[ci];
                  return _categoryTile(
                    label: cc.name,
                    color: kCustomCategoryColor,
                    selected: _categoryId == cc.id,
                    iconChild: cc.emoji.isNotEmpty
                        ? Text(cc.emoji,
                            style: const TextStyle(fontSize: 26))
                        : const Icon(Icons.label_rounded,
                            color: kCustomCategoryColor, size: 26),
                    onTap: () => setState(() {
                      _categoryId = cc.id;
                      _categoryManuallyPicked = true;
                      _ocrAutoCategory = false;
                    }),
                    onLongPress: () =>
                        _confirmDeleteCategory(cc, lang),
                  );
                }
                return _addCategoryTile();
              },
              ),
            ),
            // Package BA: shown when receipt OCR auto-detected the category.
            if (_ocrAutoCategory)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr(context, 'ocr_auto_category'),
                  style: const TextStyle(
                    color: kGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              delayMs: 120,
              child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.calendar_today),
              title: Text(tr(context, 'date')),
              subtitle: Text(dateLabel),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () => _pickDate(lang),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              delayMs: 180,
              child: TextFormField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: tr(context, 'note'),
                hintText: tr(context, 'note_hint'),
                border: const OutlineInputBorder(),
              ),
              // Package BG: debounce the note and suggest a category from
              // past learning. (Learning itself happens centrally in
              // ExpenseProvider.add — never call learn() here.)
              onChanged: (value) {
                _suggestDebounce?.cancel();
                if (value.trim().isEmpty) {
                  setState(() => _suggestedCategoryId = null);
                  return;
                }
                _suggestDebounce =
                    Timer(const Duration(milliseconds: 600), () async {
                  final id = await CategoryLearner.suggest(value);
                  if (mounted) setState(() => _suggestedCategoryId = id);
                });
              },
              ),
            ),
            // Package BG: one-tap smart suggestion chip.
            if (_suggestedCategoryId != null &&
                _suggestedCategoryId != _categoryId)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Text('✨'),
                    label: Text(
                      '${CustomCategoryRegistry.displayName(_suggestedCategoryId!, lang)}?',
                    ),
                    onPressed: () => setState(() {
                      _categoryId = _suggestedCategoryId!;
                      _categoryManuallyPicked = true;
                      _ocrAutoCategory = false;
                      _suggestedCategoryId = null;
                    }),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              delayMs: 240,
              child: _sectionLabel(context, tr(context, 'payment_method')),
            ),
            const SizedBox(height: 10),
            StaggeredEntrance(
              delayMs: 270,
              child: PaymentSelector(
              value: _payment,
              onChanged: (value) => setState(() => _payment = value),
              ),
            ),
            const SizedBox(height: 16),
            // Package AP: optional project assignment.
            StaggeredEntrance(
              delayMs: 285,
              child: DropdownButtonFormField<String>(
                key: ValueKey(_projectId),
                initialValue: _projectId,
                decoration: InputDecoration(
                  labelText: tr(context, 'project_label'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(tr(context, 'project_none')),
                  ),
                  for (final p in _projects)
                    if (p.id != null)
                      DropdownMenuItem(
                        value: p.id!,
                        child: Text(p.name),
                      ),
                ],
                onChanged: (v) => setState(() => _projectId = v ?? ''),
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              delayMs: 300,
              child: _sectionLabel(context, tr(context, 'receipt_photo')),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_receiptPath != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_receiptPath!),
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                          // The file can vanish (user deleted it outside the
                          // app, OS cleanup) — show a placeholder, not a
                          // red screen.
                          errorBuilder: (_, __, ___) => Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      theme.colorScheme.outlineVariant),
                            ),
                            child: const Icon(
                                Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _receiptPath = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant),
                    ),
                    child: const Icon(Icons.receipt_long_outlined),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickReceipt(ImageSource.camera),
                        icon: const Icon(
                            Icons.photo_camera_outlined,
                            size: 18),
                        label: Text(tr(context, 'receipt_camera')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickReceipt(ImageSource.gallery),
                        icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 18),
                        label: Text(tr(context, 'receipt_gallery')),
                      ),
                      FilledButton.icon(
                        onPressed: _scanning ? null : _scanBill,
                        icon: _scanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.document_scanner_outlined,
                                size: 18),
                        label: Text(tr(context,
                            _scanning ? 'bill_scanning' : 'scan_bill')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Package Y: shown when receipt OCR autofilled amount/date.
            if (_ocrAutofilled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '✨ ${tr(context, 'ocr_autofill')}',
                  style: const TextStyle(
                    color: kGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // Package AZ: attach the current GPS location to the expense.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _locating ? null : _attachLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_lat == null
                        ? Icons.location_on_outlined
                        : Icons.location_on),
                label: Text(_locating
                    ? tr(context, 'expense_locating')
                    : _lat == null
                        ? tr(context, 'expense_add_location')
                        : tr(context, 'expense_location_set')),
              ),
            ),
            // Package AB: mood tags, single-select.
            StaggeredEntrance(
              delayMs: 315,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(context, tr(context, 'mood_label')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final emoji in const ['😊', '😐', '😟', '😡', '🥳'])
                        Padding(
                          padding:
                              const EdgeInsets.only(right: 8),
                          child: _MoodButton(
                            emoji: emoji,
                            selected: _mood == emoji,
                            onTap: () => setState(() =>
                                _mood = _mood == emoji ? '' : emoji),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            StaggeredEntrance(
              delayMs: 330,
              child: PressableScale(
              pressedScale: 0.97,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kGoldLight, kGold, kGoldDark],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: kGold.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: () => _save(lang),
                  icon: const Icon(Icons.check),
                  label: Text(tr(context, 'save')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    // Dark text on the gold gradient stays readable in
                    // both light and dark mode.
                    foregroundColor: kDeepGreenDark,
                    iconColor: kDeepGreenDark,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              ),
            ),
          ],
        ),
      ),
      // Animated success check overlay.
      Positioned.fill(
        child: AnimatedOpacity(
          opacity: _showSuccess ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_showSuccess,
            child: Container(
              color: Colors.black54,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_showSuccess),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  /// 10.50 → "10.5", 10.05 stays "10.05".
  String _trimDecimals(double value) {
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// One category tile in the grid (built-in or user-created).
  Widget _categoryTile({
    required String label,
    required Color color,
    required bool selected,
    required Widget iconChild,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
        transform: Matrix4.diagonal3Values(
          selected ? 1.06 : 1.0,
          selected ? 1.06 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? color.withValues(alpha: 0.18)
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? color : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  selected ? color.withValues(alpha: 0.35) : Colors.transparent,
              blurRadius: selected ? 10 : 0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconChild,
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: const TextStyle(fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dashed "+ Add new category" tile at the end of the grid.
  Widget _addCategoryTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showAddCategoryDialog(),
      child: CustomPaint(
        painter: _DashedRectPainter(kGold.withValues(alpha: 0.7)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: kGold.withValues(alpha: 0.06),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_outline,
                  color: kGold, size: 26),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  tr(context, 'add_new_category'),
                  style: const TextStyle(fontSize: 11, color: kGold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog to create a custom category: name + manually typed emoji.
  Future<void> _showAddCategoryDialog() async {
    final lang = context.read<SettingsProvider>().language;
    final nameCtrl = TextEditingController();
    final emojiCtrl = TextEditingController();
    var confirmed = false;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'new_category_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr(ctx, 'category_name'),
                hintText: tr(ctx, 'category_name_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emojiCtrl,
              decoration: InputDecoration(
                labelText: tr(ctx, 'goal_emoji'),
                hintText: '🎮',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text(AppStrings.get('err_name_empty', lang))),
                );
                return;
              }
              confirmed = true;
              Navigator.pop(ctx);
            },
            child: Text(tr(ctx, 'save')),
          ),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final emoji = emojiCtrl.text.trim();
    nameCtrl.dispose();
    emojiCtrl.dispose();
    if (!confirmed || name.isEmpty || !mounted) return;
    try {
      final id =
          await DatabaseHelper.instance.insertCustomCategory(name, emoji);
      final cats = await DatabaseHelper.instance.getCustomCategories();
      CustomCategoryRegistry.setAll(cats);
      if (mounted) {
        setState(() {
          _customCats = cats;
          _categoryId = id;
          _categoryManuallyPicked = true;
          _ocrAutoCategory = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('err_name_empty', lang))),
        );
      }
    }
  }

  /// Long-press a custom category tile → confirm → delete it.
  Future<void> _confirmDeleteCategory(CustomCategory cat, String lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'delete_category_title')),
        content: Text(AppStrings.get('delete_category_msg', lang)),
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
    await DatabaseHelper.instance.deleteCustomCategory(cat.id);
    final cats = await DatabaseHelper.instance.getCustomCategories();
    CustomCategoryRegistry.setAll(cats);
    if (mounted) {
      setState(() {
        _customCats = cats;
        if (_categoryId == cat.id) _categoryId = 'food';
      });
    }
  }

  /// Premium section header: small caps gold, letterspaced.
  Widget _sectionLabel(BuildContext context, String text) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: dark ? kGoldLight : kGoldDark,
      ),
    );
  }
}

/// Dashed rounded-rectangle painter for the "+ Add new category" tile.
class _DashedRectPainter extends CustomPainter {
  final Color color;

  _DashedRectPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(16),
        ),
      );
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Package AB: one emoji mood toggle. Gold ring when selected.
class _MoodButton extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _MoodButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? kGold.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? kGold : kGold.withValues(alpha: 0.35),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: kGold.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

/// Small square icon button used next to the amount field (calculator
/// toggle, voice input). Highlights emerald/gold when [active].
class _IconSquare extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _IconSquare({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: active
              ? kGold
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? kGold : kGold.withValues(alpha: 0.55),
          ),
          boxShadow: [
            if (active)
              BoxShadow(
                color: kGold.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Icon(
          icon,
          color: active ? kDeepGreenDark : (isDark ? kGoldLight : kGoldDark),
        ),
      ),
    );
  }
}
