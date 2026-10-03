import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/category.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_center.dart';
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
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  String _partialWords = '';

  String _categoryId = 'food';
  DateTime _date = DateTime.now();
  String _payment = 'cash';
  String? _receiptPath;
  bool _showCalculator = false;
  bool _listening = false;
  bool _showSuccess = false;
  bool _scanning = false;
  List<CustomCategory> _customCats = [];

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
    }
    _loadCustomCategories();
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
    _speech.stop();
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
    if (!_formKey.currentState!.validate()) return;
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
        id: widget.expense!.id,
        amount: amount,
        categoryId: _categoryId,
        date: _date,
        note: _noteCtrl.text.trim(),
        paymentMethod: _payment,
        place: null,
        receiptPath: _receiptPath,
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
      }
    } catch (_) {
      // Permission denied or picker unavailable — leave the form as-is.
    }
  }

  /// v5: bill OCR — snap a bill, extract the total, fill the amount field.
  Future<void> _scanBill() async {
    if (_scanning) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    setState(() => _scanning = true);
    // Keep the photo as the receipt attachment too.
    setState(() => _receiptPath = file.path);
    try {
      final result = await OcrService.scanBillAmount(file);
      if (!mounted) return;
      final amount = result?['amount'] as double?;
      if (amount != null) {
        final whole = amount.truncateToDouble() == amount;
        _amountCtrl.text =
            whole ? amount.toStringAsFixed(0) : amount.toString();
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

  Future<void> _toggleVoice(String lang) async {
    if (_listening) {
      await _speech.stop();
      if (mounted && _listening) {
        setState(() {
          _listening = false;
          _partialWords = '';
        });
      }
      return;
    }
    // Initialize the speech engine only once and reuse it — initializing
    // on every tap was the main source of the mic "lag".
    if (!_speechReady) {
      try {
        _speechReady = await _speech.initialize(
          onStatus: (status) {
            if ((status == 'done' || status == 'notListening') &&
                mounted &&
                _listening) {
              setState(() {
                _listening = false;
                _partialWords = '';
              });
            }
          },
          onError: (_) {
            if (mounted && _listening) {
              setState(() {
                _listening = false;
                _partialWords = '';
              });
            }
          },
        );
      } catch (_) {
        _speechReady = false;
      }
    }
    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('voice_unavailable', lang))),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _listening = true;
      _partialWords = '';
    });
    try {
      // listen() resolves once recognition starts; results arrive via
      // onResult and the session end via the onStatus handler above.
      // partialResults + short pauseFor keep the UI feeling instant.
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          if (result.finalResult) {
            _applyVoiceText(result.recognizedWords, lang);
            if (_listening) {
              setState(() {
                _listening = false;
                _partialWords = '';
              });
            }
          } else if (_listening) {
            setState(() => _partialWords = result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
        ),
      );
    } catch (_) {
      if (mounted && _listening) {
        setState(() {
          _listening = false;
          _partialWords = '';
        });
      }
    }
  }

  /// First spoken number → amount field (Bangla ০১২৩৪৫৬৭৮৯ and English
  /// digits both supported); the remaining words → note field.
  void _applyVoiceText(String text, String lang) {
    if (text.trim().isEmpty) {
      _voiceSnack(lang, 'voice_no_number');
      return;
    }
    const bnDigits = '০১২৩৪৫৬৭৮৯';
    final normalized = text.split('').map((ch) {
      final idx = bnDigits.indexOf(ch);
      return idx >= 0 ? String.fromCharCode(48 + idx) : ch;
    }).join();
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(normalized);
    if (match == null) {
      _voiceSnack(lang, 'voice_no_number');
      return;
    }
    _amountCtrl.text = match.group(0)!;
    // Indices line up 1:1 (each Bangla digit maps to one ASCII digit), so
    // the surrounding words are taken from the original text to keep
    // their script.
    final rest = '${text.substring(0, match.start)} ${text.substring(match.end)}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (rest.isNotEmpty) {
      final current = _noteCtrl.text.trim();
      _noteCtrl.text = current.isEmpty ? rest : '$current $rest';
    }
  }

  void _voiceSnack(String lang, String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.get(key, lang))),
    );
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
            Row(
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
                      prefixText: '৳ ',
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
                _IconSquare(
                  icon: Icons.calculate_outlined,
                  active: _showCalculator,
                  onTap: () =>
                      setState(() => _showCalculator = !_showCalculator),
                ),
                const SizedBox(width: 8),
                _IconSquare(
                  icon: _listening ? Icons.mic : Icons.mic_none_outlined,
                  active: _listening,
                  onTap: () => _toggleVoice(lang),
                ),
              ],
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
            if (_listening) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _partialWords.isNotEmpty
                            ? _partialWords
                            : tr(context, 'voice_listening'),
                        style:
                            const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _sectionLabel(context, tr(context, 'category')),
            const SizedBox(height: 10),
            GridView.builder(
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
                    onTap: () => setState(() => _categoryId = c.id),
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
                    onTap: () => setState(() => _categoryId = cc.id),
                    onLongPress: () =>
                        _confirmDeleteCategory(cc, lang),
                  );
                }
                return _addCategoryTile();
              },
            ),
            const SizedBox(height: 16),
            ListTile(
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: tr(context, 'note'),
                hintText: tr(context, 'note_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel(context, tr(context, 'payment_method')),
            const SizedBox(height: 10),
            PaymentSelector(
              value: _payment,
              onChanged: (value) => setState(() => _payment = value),
            ),
            const SizedBox(height: 16),
            _sectionLabel(context, tr(context, 'receipt_photo')),
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
            const SizedBox(height: 24),
            PressableScale(
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
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
