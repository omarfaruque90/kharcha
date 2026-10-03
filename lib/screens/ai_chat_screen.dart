import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/total_balance_provider.dart';
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
import '../services/llm_service.dart';
import '../services/llm_tools.dart';
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

  /// Real-LLM mode (user-provided API key). Falls back to the on-device
  /// rule-based assistant when no key is configured.
  bool _llmMode = false;
  LlmConfig? _llmConfig;
  final List<LlmMessage> _llmHistory = [];
  late final List<LlmToolDef> _llmTools = buildLlmTools();

  String get _lang =>
      Provider.of<SettingsProvider>(context, listen: false).language;

  @override
  void initState() {
    super.initState();
    _messages.add(_Msg.ai(AppStrings.get('ai_greeting', _lang)));
    _initLlm();
  }

  /// Checks for a configured LLM key; enables LLM mode when present.
  Future<void> _initLlm() async {
    final cfg = await LlmConfig.load();
    if (!mounted) return;
    setState(() {
      _llmConfig = cfg;
      _llmMode = cfg.isConfigured;
    });
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
    if (_llmMode) {
      await _sendLlm(input, null);
      return;
    }
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

  /// Sends a message in real-LLM mode: multi-round tool calling
  /// (max 3 rounds), then shows the final text.
  Future<void> _sendLlm(String text, String? imagePath) async {
    final input = text.trim();
    if ((input.isEmpty && imagePath == null) || _typing) return;
    final lang = _lang;
    // Capture providers before async gaps.
    final expenses = context.read<ExpenseProvider>();
    final money = context.read<MoneyProvider>();
    final wallets = context.read<TotalBalanceProvider>();
    final cfg = _llmConfig ?? await LlmConfig.load();
    final toolCtx = LlmToolContext(
      expenses: expenses,
      money: money,
      wallets: wallets,
      lang: lang,
    );
    final schemas = [for (final t in _llmTools) t.schema];
    final byName = {for (final t in _llmTools) t.name: t};

    setState(() {
      _messages.add(_Msg.user(input, imagePath: imagePath));
      _typing = true;
    });
    _ctrl.clear();
    _scrollToEnd();

    _llmHistory.add(LlmMessage.user(
      input,
      imagePaths: imagePath == null ? const [] : [imagePath],
    ));
    // Keep history bounded.
    while (_llmHistory.length > 20) {
      _llmHistory.removeAt(0);
    }

    final todayIso =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    final systemPrompt = buildAssistantSystemPrompt(
      lang: lang,
      todayIso: todayIso,
      categoryList: categoryListForPrompt(lang),
    );

    String? finalText;
    try {
      for (var round = 0; round < 3; round++) {
        final reply = await LlmService.chat(
          config: cfg,
          history: List.of(_llmHistory),
          systemPrompt: systemPrompt,
          toolSchemas: schemas,
        );
        if (reply.text != null && reply.text!.isNotEmpty) {
          _llmHistory.add(LlmMessage.assistant(reply.text!,
              toolCalls: reply.toolCalls));
        } else if (reply.toolCalls.isNotEmpty) {
          _llmHistory.add(LlmMessage.assistant('', toolCalls: reply.toolCalls));
        } else {
          finalText = reply.text;
          break;
        }
        if (reply.toolCalls.isEmpty) {
          finalText = reply.text;
          break;
        }
        // Execute tool calls and feed results back.
        for (final call in reply.toolCalls) {
          final def = byName[call.name];
          String result;
          if (def == null) {
            result = 'Error: unknown tool ${call.name}.';
          } else {
            try {
              result = await def.execute(call.args, toolCtx);
            } catch (e) {
              result = 'Error executing ${call.name}: $e';
            }
          }
          _llmHistory.add(LlmMessage.toolResult(
            toolCallId: call.id ?? 'call_${call.name}_$round',
            toolName: call.name,
            result: result,
          ));
        }
        // If the last round produced text alongside tools, use it.
        if (reply.text != null && reply.text!.isNotEmpty) {
          finalText = reply.text;
        }
      }
    } catch (_) {
      finalText = null;
    }

    if (!mounted) return;
    var displayText = finalText?.trim().isNotEmpty == true
        ? finalText!.trim()
        : AppStrings.get('ai_action_failed', lang);
    // True offline fallback: if the LLM is unreachable, answer with the
    // on-device rule-based assistant instead of showing an error.
    if (displayText.startsWith('🌐')) {
      try {
        final res = await AiAssistant.answer(input, lang);
        if (!mounted) return;
        var reply = res.reply;
        if (res.action != null) {
          reply = await _runAction(res.action!, lang);
        }
        displayText = reply;
      } catch (_) {
        // Keep the network error text.
      }
    }
    if (!mounted) return;
    setState(() {
      _typing = false;
      _messages.add(_Msg.ai(displayText));
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
    final totalBalance = context.read<TotalBalanceProvider>();
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
          try {
            await totalBalance.deductForExpense('cash', action.amount!);
          } catch (_) {}
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

    // LLM mode: send the image to the real AI with the current text.
    if (_llmMode) {
      await _sendLlm(_ctrl.text, file.path);
      return;
    }

    // Rule-based mode: on-device OCR bill scan (unchanged).
    // Show the bill in chat, then "think" while scanning.
    setState(() {
      _messages.add(_Msg.user('', imagePath: file!.path));
      _typing = true;
    });
    _scrollToEnd();

    final addedTpl = tr(context, 'ai_bill_added');
    final noAmountTpl = tr(context, 'ai_bill_no_amount');
    final failedTpl = tr(context, 'ai_bill_failed');
    final expenses = context.read<ExpenseProvider>();
    final totalBalance = context.read<TotalBalanceProvider>();
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
        await expenses.add(Expense(
          amount: amount,
          categoryId: categoryId,
          date: DateTime.now(),
          note: merchant.isEmpty ? 'Bill scan' : 'Bill: $merchant',
          paymentMethod: 'cash',
          currency: 'BDT',
          bdtAmount: amount,
          receiptPath: file.path,
        ));
        try {
          await totalBalance.deductForExpense('cash', amount);
        } catch (_) {}
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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kGold.withValues(alpha: 0.9),
                    kGold.withValues(alpha: 0.5),
                  ],
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Color(0xFF072A1F),
              ),
            ),
            const SizedBox(width: 10),
            const Text('AI Assistant'),
          ],
        ),
        centerTitle: true,
      ),
      body: StaggeredEntrance(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty && !_typing
                  ? _buildEmptyState(context, theme, isDark)
                  : ListView.builder(
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
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: m.isUser
                            ? kGold
                            : isDark
                                ? theme.colorScheme.surfaceContainerHigh
                                : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(m.isUser ? 20 : 6),
                          bottomRight: Radius.circular(m.isUser ? 6 : 20),
                        ),
                        boxShadow: m.isUser
                            ? [
                                BoxShadow(
                                  color:
                                      kGold.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
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
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  kGold.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _ctrl,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          decoration: InputDecoration(
                            hintText: tr(context, 'ai_hint'),
                            filled: true,
                            fillColor: isDark
                                ? theme.colorScheme.surfaceContainerHigh
                                : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: kGold.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: kGold.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: const BorderSide(
                                color: kGold,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            // Mic lives INSIDE the chat field.
                            suffixIcon: IconButton(
                              icon: Icon(
                                _listening ? Icons.stop : Icons.mic_outlined,
                                color: _listening
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              tooltip: tr(context, 'voice_input_tip'),
                              onPressed: _toggleMic,
                            ),
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

  /// Premium empty state: glowing orb + minimal text.
  Widget _buildEmptyState(
      BuildContext context, ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kGold.withValues(alpha: 0.35),
                    kGold.withValues(alpha: 0.08),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kGold.withValues(alpha: 0.25),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 36,
                color: kGold,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr(context, 'ai_welcome_title'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'ai_welcome_sub'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
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
