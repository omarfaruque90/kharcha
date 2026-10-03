import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/budget.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ai_assistant.dart';
import '../services/ocr_service.dart';
import '../services/voice_budget_parser.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// One chat message. [imagePath] is set for user-sent bill photos.
class _Msg {
  final String text;
  final bool isUser;
  final String? imagePath;

  const _Msg.user(this.text, {this.imagePath}) : isUser = true;
  const _Msg.ai(this.text)
      : isUser = false,
        imagePath = null;
}

/// On-device AI assistant chat (Package BD).
/// Ask in Bangla/Banglish/English about spending, savings or budget —
/// answers are computed locally from the user's own data.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _typing = false;

  /// Voice input inside the chat field.
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  String get _lang =>
      Provider.of<SettingsProvider>(context, listen: false).language;

  @override
  void initState() {
    super.initState();
    _messages.add(_Msg.ai(AppStrings.get('ai_greeting', _lang)));
  }

  @override
  void dispose() {
    _speech.stop();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Toggles voice input: recognized words go straight into the chat field.
  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    bool available = false;
    try {
      available = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'notListening' || s == 'done') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    } catch (_) {
      available = false;
    }
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'voice_error'))),
        );
      }
      return;
    }
    if (!mounted) return;
    final lang = _lang;
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: lang == 'bn' ? 'bn_BD' : 'en_US',
        listenFor: const Duration(seconds: 30),
        partialResults: true,
      ),
      onResult: (r) {
        final words = r.recognizedWords.trim();
        if (words.isEmpty || !mounted) return;
        setState(() {
          _ctrl.text = words;
          _ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _ctrl.text.length),
          );
        });
      },
    );
  }

  Future<void> _send(String text) async {
    final input = text.trim();
    if (input.isEmpty || _typing) return;
    final lang = _lang;
    setState(() {
      _messages.add(_Msg.user(input));
      _typing = true;
    });
    _ctrl.clear();
    _scrollToEnd();
    // The service simulates a short "thinking" delay internally.
    final res = await AiAssistant.answer(input, lang);
    if (!mounted) return;
    String reply = res.reply;
    // Execute bot actions (add expense/income, set budget, delete last)
    // through the providers so the whole app updates.
    if (res.action != null) {
      reply = await _runAction(res.action!, lang);
    }
    if (!mounted) return;
    setState(() {
      _typing = false;
      _messages.add(_Msg.ai(reply));
    });
    _scrollToEnd();
  }

  /// Runs a bot action and returns the confirmation message.
  /// Localized templates are captured before any await so the context
  /// is never used across an async gap.
  Future<String> _runAction(AiAction action, String lang) async {
    final addedExpenseTpl = tr(context, 'ai_added_expense');
    final addedIncomeTpl = tr(context, 'ai_added_income');
    final budgetSetTpl = tr(context, 'ai_budget_set');
    final deletedTpl = tr(context, 'ai_deleted');
    final nothingTpl = tr(context, 'ai_nothing_to_delete');
    final failedTpl = tr(context, 'ai_action_failed');
    try {
      final expenses = context.read<ExpenseProvider>();
      final money = context.read<MoneyProvider>();
      switch (action.type) {
        case 'add_expense':
          await expenses.add(Expense(
            amount: action.amount!,
            categoryId: action.categoryId ?? 'others',
            date: DateTime.now(),
            note: action.note ?? '',
            paymentMethod: 'cash',
            currency: 'BDT',
            bdtAmount: action.amount!,
          ));
          return addedExpenseTpl
              .replaceAll('{amount}', formatMoney(action.amount!))
              .replaceAll('{cat}', CustomCategoryRegistry.displayName(
                  action.categoryId ?? 'others', lang));
        case 'add_income':
          await money.addIncome(Income(
            amount: action.amount!,
            source: 'other',
            date: DateTime.now(),
            note: action.note ?? '',
          ));
          return addedIncomeTpl
              .replaceAll('{amount}', formatMoney(action.amount!));
        case 'set_budget':
          await money.upsertBudget(Budget(
            categoryId: action.categoryId ?? 'others',
            monthKey: monthKeyOf(DateTime.now()),
            limitAmount: action.amount!,
          ));
          return budgetSetTpl
              .replaceAll('{cat}', CustomCategoryRegistry.displayName(
                  action.categoryId ?? 'others', lang))
              .replaceAll('{amount}', formatMoney(action.amount!));
        case 'delete_last':
          final all = expenses.expenses;
          if (all.isEmpty) return nothingTpl;
          final last = all.first;
          await expenses.remove(last.id!);
          return deletedTpl
              .replaceAll('{amount}', formatMoney(last.bdtAmount ?? last.amount));
      }
    } catch (_) {}
    return failedTpl;
  }

  /// Bill scan: camera/gallery → OCR → auto-add expense.
  /// The bot talks through it like an assistant would.
  Future<void> _pickBill() async {
    final lang = _lang;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr(sheetCtx, 'bill_camera')),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr(sheetCtx, 'bill_gallery')),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (_) {}
    if (file == null || !mounted) return;

    // Show the bill in chat, then "think" while scanning.
    setState(() {
      _messages.add(_Msg.user('', imagePath: file!.path));
      _typing = true;
    });
    _scrollToEnd();

    final addedTpl = tr(context, 'ai_bill_added');
    final noAmountTpl = tr(context, 'ai_bill_no_amount');
    final failedTpl = tr(context, 'ai_bill_failed');
    String reply;
    try {
      final result = await OcrService.scanBillAmount(file);
      final amount = result?['amount'] as double?;
      final rawText = (result?['rawText'] as String?) ?? '';
      if (amount != null && amount > 0) {
        // Guess category from the bill text.
        final parsed =
            VoiceBudgetParser.parse(rawText, lang);
        final categoryId = parsed.categoryId ?? 'others';
        // Merchant: first non-empty line, trimmed to something readable.
        final merchant = rawText
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.length >= 3, orElse: () => '');
        await context.read<ExpenseProvider>().add(Expense(
          amount: amount,
          categoryId: categoryId,
          date: DateTime.now(),
          note: merchant.isEmpty ? 'Bill scan' : 'Bill: $merchant',
          paymentMethod: 'cash',
          currency: 'BDT',
          bdtAmount: amount,
          receiptPath: file.path,
        ));
        reply = addedTpl
            .replaceAll('{amount}', formatMoney(amount))
            .replaceAll('{cat}', CustomCategoryRegistry.displayName(
                categoryId, lang));
      } else {
        reply = noAmountTpl;
      }
    } catch (_) {
      reply = failedTpl;
    }
    if (!mounted) return;
    setState(() {
      _typing = false;
      _messages.add(_Msg.ai(reply));
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || !mounted) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = context.watch<SettingsProvider>().language;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant ✨'),
        centerTitle: true,
      ),
      body: StaggeredEntrance(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: _messages.length + (_typing ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _messages.length) return const _TypingDots();
                  final m = _messages[i];
                  return Align(
                    alignment:
                        m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: m.isUser
                            ? kGold
                            : isDark
                                ? theme.colorScheme.surfaceContainerHighest
                                : const Color(0xFFE9F2EC),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(m.isUser ? 18 : 4),
                          bottomRight: Radius.circular(m.isUser ? 4 : 18),
                        ),
                      ),
                      child: m.imagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(m.imagePath!),
                                width: 200,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Text(
                              m.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: m.isUser
                                    ? const Color(0xFF072A1F)
                                    : theme.colorScheme.onSurface,
                                height: 1.4,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
            // Suggestion chips above the input.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  for (final s in AiAssistant.suggestions(lang)) ...[
                    ActionChip(
                      label: Text(s),
                      avatar: const Icon(Icons.auto_awesome, size: 16),
                      onPressed: () => _send(s),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            // Input row.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    // Bill scan: camera / gallery.
                    IconButton(
                      icon: Icon(
                        Icons.photo_camera_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: tr(context, 'bill_scan'),
                      onPressed: _pickBill,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: InputDecoration(
                          hintText: tr(context, 'ai_hint'),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          // Mic lives INSIDE the chat field.
                          suffixIcon: IconButton(
                            icon: Icon(
                              _listening ? Icons.stop : Icons.mic_outlined,
                              color: _listening
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            tooltip: tr(context, 'voice_title'),
                            onPressed: _toggleMic,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: kGold,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.send,
                            color: Color(0xFF072A1F)),
                        onPressed: () => _send(_ctrl.text),
                        tooltip: tr(context, 'ai_send'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three bouncing dots shown while the assistant "types".
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value * 3 + i) % 3 / 3;
                final opacity = 0.25 + 0.75 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity,
                    child: const CircleAvatar(radius: 4, backgroundColor: kGold),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
