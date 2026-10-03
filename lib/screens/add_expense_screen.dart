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
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/calculator_pad.dart';
import '../widgets/motion.dart';
import '../widgets/payment_selector.dart';
import '../widgets/place_input.dart';

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
  final TextEditingController _placeCtrl = TextEditingController();
  final TextEditingController _placeEmojiCtrl = TextEditingController();
  final SpeechToText _speech = SpeechToText();

  String _categoryId = 'food';
  DateTime _date = DateTime.now();
  String _payment = 'cash';
  String? _receiptPath;
  bool _showCalculator = false;
  bool _listening = false;
  bool _showSuccess = false;

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
      _placeCtrl.text = e.place ?? '';
      _receiptPath = e.receiptPath;
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _placeCtrl.dispose();
    _placeEmojiCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(String lang) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      // FIX (white/blank screen): this app bundles no flutter_localizations
      // (MaterialApp declares no localizationsDelegates/supportedLocales),
      // so only the default English delegates exist. Passing Locale('bn')
      // left the dialog with no MaterialLocalizations and it rendered blank
      // white (release builds swallow the lookup error). Only pass a locale
      // the bundled delegates actually support.
      locale: lang == 'en' ? const Locale('en') : null,
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: kEmerald,
              onPrimary: Colors.white,
              secondary: kGold,
              onSurface: kEmerald,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: kEmerald),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save(String lang) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.trim());
    final provider = context.read<ExpenseProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final db = DatabaseHelper.instance;

    // Remember custom place / payment labels for reuse suggestions.
    String? place;
    if (_categoryId == 'others') {
      final label = _placeCtrl.text.trim();
      if (label.isNotEmpty) {
        final emoji = _placeEmojiCtrl.text.trim();
        place = emoji.isEmpty ? label : '$label $emoji';
        await db.upsertCustomPlaceByLabel(label, emoji: emoji);
      }
    }
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
        place: place,
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
          place: place,
          receiptPath: _receiptPath,
        ),
      );
      if (!mounted) return;
      // Animated success check, then reset and go home.
      setState(() => _showSuccess = true);
      await Future.delayed(const Duration(milliseconds: 950));
      if (!mounted) return;
      setState(() => _showSuccess = false);
      _amountCtrl.clear();
      _noteCtrl.clear();
      _placeCtrl.clear();
      _placeEmojiCtrl.clear();
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

  Future<void> _toggleVoice(String lang) async {
    if (_listening) {
      await _speech.stop();
      if (mounted && _listening) setState(() => _listening = false);
      return;
    }
    var available = false;
    try {
      available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') &&
              mounted &&
              _listening) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted && _listening) setState(() => _listening = false);
        },
      );
    } catch (_) {
      available = false;
    }
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('voice_unavailable', lang))),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _listening = true);
    try {
      // listen() resolves once recognition starts; results arrive via
      // onResult and the session end via the onStatus handler above.
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && mounted) {
            _applyVoiceText(result.recognizedWords, lang);
            if (_listening) setState(() => _listening = false);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
      );
    } catch (_) {
      if (mounted && _listening) setState(() => _listening = false);
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
    final rest = (text.substring(0, match.start) +
            ' ' +
            text.substring(match.end))
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
                    decoration: InputDecoration(
                      labelText: tr(context, 'amount'),
                      hintText: tr(context, 'amount_hint'),
                      prefixText: '৳ ',
                      border: const OutlineInputBorder(),
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
                  borderRadius: const BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(context, 'voice_listening'),
                        style:
                            const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              tr(context, 'category'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
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
              itemCount: kCategories.length,
              itemBuilder: (ctx, i) {
                final c = kCategories[i];
                final selected = _categoryId == c.id;
                return InkWell(
                  borderRadius: const BorderRadius.circular(12),
                  onTap: () => setState(() => _categoryId = c.id),
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
                      borderRadius: const BorderRadius.circular(12),
                      color: selected
                          ? c.color.withValues(alpha: 0.18)
                          : theme.colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: selected
                            ? c.color
                            : theme.colorScheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: selected
                              ? c.color.withValues(alpha: 0.35)
                              : Colors.transparent,
                          blurRadius: selected ? 8 : 0,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(c.icon, color: c.color, size: 26),
                        const SizedBox(height: 6),
                        Text(
                          AppStrings.categoryName(c.id, lang),
                          style: const TextStyle(fontSize: 11),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_categoryId == 'others') ...[
              const SizedBox(height: 16),
              PlaceInput(
                labelController: _placeCtrl,
                emojiController: _placeEmojiCtrl,
              ),
            ],
            const SizedBox(height: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.calendar_today),
              title: Text(tr(context, 'date')),
              subtitle: Text(dateLabel),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () => _pickDate(lang),
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.circular(12),
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
            Text(
              tr(context, 'payment_method'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            PaymentSelector(
              value: _payment,
              onChanged: (value) => setState(() => _payment = value),
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'receipt_photo'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_receiptPath != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.circular(12),
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
                      borderRadius: const BorderRadius.circular(12),
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
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            PressableScale(
              pressedScale: 0.97,
              child: FilledButton.icon(
                onPressed: () => _save(lang),
                icon: const Icon(Icons.check),
                label: Text(tr(context, 'save')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
}

/// Small square icon button used next to the amount field (calculator
/// toggle, voice input). Highlights emerald/gold when [active].
class _IconSquare extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _IconSquare({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: active
              ? kEmerald
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.circular(14),
          border: Border.all(
            color: active ? kEmerald : kGold.withValues(alpha: 0.55),
          ),
        ),
        child: Icon(
          icon,
          color: active ? Colors.white : kEmerald,
        ),
      ),
    );
  }
}
