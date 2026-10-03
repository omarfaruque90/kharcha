import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import '../services/ai_assistant.dart';
import '../widgets/motion.dart';

/// One chat message.
class _Msg {
  final String text;
  final bool isUser;

  const _Msg.user(this.text) : isUser = true;
  const _Msg.ai(this.text) : isUser = false;
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
    final reply = await AiAssistant.answer(input, lang);
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
                      child: Text(
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
