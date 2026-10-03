import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/custom_category.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../services/expense_query.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// One Q&A turn shown as chat cards.
class _ChatEntry {
  final int id;
  final String query;
  final String answer;

  _ChatEntry({required this.id, required this.query, required this.answer});
}

/// Voice-driven expense report: tap the mic, ask in Bangla/English
/// ("আজকে কত খরচ হয়েছে", "my balance"), hear and see the answer.
class VoiceReportScreen extends StatefulWidget {
  const VoiceReportScreen({super.key});

  @override
  State<VoiceReportScreen> createState() => _VoiceReportScreenState();
}

class _VoiceReportScreenState extends State<VoiceReportScreen> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final List<_ChatEntry> _history = [];
  final ScrollController _scroll = ScrollController();

  bool _listening = false;
  int _seq = 0;

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _scroll.dispose();
    super.dispose();
  }

  String get _lang =>
      Provider.of<SettingsProvider>(context, listen: false).language;

  void _toast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, key))),
    );
  }

  // ------------------------------------------------------------------
  // Mic handling.
  // ------------------------------------------------------------------
  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    bool available = false;
    try {
      available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'notListening' || status == 'done') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listening = false);
          if (error.permanent || error.errorMsg.contains('permission')) {
            _toast('voice_error');
          }
        },
      );
    } catch (_) {
      available = false;
    }
    if (!available) {
      _toast('voice_error');
      return;
    }
    final lang = _lang;
    setState(() => _listening = true);
    try {
      await _speech.listen(
        localeId: lang == 'bn' ? 'bn_BD' : 'en_US',
        listenFor: const Duration(seconds: 10),
        onResult: _onSpeechResult,
      );
    } catch (_) {
      // listen() failed (e.g. engine busy) — don't leave the UI stuck
      // in the listening state.
      if (!mounted) return;
      setState(() => _listening = false);
      _toast('voice_error');
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    // Only act on the final result.
    try {
      final words = result.recognizedWords.trim();
      if (result.finalResult && words.isNotEmpty) {
        _speech.stop();
        _handleQuery(words);
      }
    } catch (_) {
      // Never crash on an unexpected result shape.
    }
  }

  // ------------------------------------------------------------------
  // Query → answer.
  // ------------------------------------------------------------------
  void _handleQuery(String words) {
    final lang = _lang;
    final q = ExpenseQueryParser.parse(words, lang);
    final expenses = Provider.of<ExpenseProvider>(context, listen: false);
    final money = Provider.of<MoneyProvider>(context, listen: false);

    String answer;
    if (q.asksBalance) {
      final now = DateTime.now();
      final bal = money.incomeForMonth(monthKeyOf(now)) -
          expenses.totalThisMonth();
      answer = AppStrings.get('voice_balance_answer', lang).replaceAll(
        '{amount}',
        _displayMoney(bal, lang),
      );
    } else {
      double total = 0;
      for (final e in expenses.expenses) {
        final inRange = !e.date.isBefore(q.from) && !e.date.isAfter(q.to);
        final inCat = q.categoryId == null || e.categoryId == q.categoryId;
        if (inRange && inCat) total += e.amount;
      }
      final period = _periodLabel(q, lang);
      final amount = _displayMoney(total, lang);
      if (q.categoryId != null) {
        final cat = CustomCategoryRegistry.displayName(q.categoryId!, lang);
        answer = AppStrings.get('voice_spent_cat_answer', lang)
            .replaceAll('{cat}', cat)
            .replaceAll('{amount}', amount)
            .replaceAll('{period}', period);
      } else {
        answer = AppStrings.get('voice_spent_answer', lang)
            .replaceAll('{amount}', amount)
            .replaceAll('{period}', period);
      }
    }

    setState(() {
      _listening = false;
      _history.add(_ChatEntry(id: _seq++, query: words, answer: answer));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    _speak(answer, lang);
  }

  /// ৳-formatted amount; Bengali digits when the UI language is Bangla.
  String _displayMoney(double amount, String lang) {
    final text = formatMoney(amount);
    return lang == 'bn' ? _bnDigits(text) : text;
  }

  static String _bnDigits(String s) {
    const bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    return s.replaceAllMapped(
      RegExp('[0-9]'),
      (m) {
        final d = m.group(0);
        return d == null ? '' : bn[int.parse(d)];
      },
    );
  }

  /// Human-readable period label for the parsed range.
  String _periodLabel(ParsedQuery q, String lang) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String key;
    if (_sameDay(q.from, today)) {
      key = 'voice_period_today';
    } else if (_sameDay(q.from, yesterday)) {
      key = 'voice_period_yesterday';
    } else if (q.from.day == 1 &&
        q.from.month == now.month &&
        q.from.year == now.year) {
      key = 'voice_period_this_month';
    } else if (q.from.day == 1 &&
        q.from.month == _prevMonth(now).month &&
        q.from.year == _prevMonth(now).year) {
      key = 'voice_period_last_month';
    } else if (_sameDay(q.from, _monday(today))) {
      key = 'voice_period_this_week';
    } else if (_sameDay(q.from, _monday(today).subtract(const Duration(days: 7)))) {
      key = 'voice_period_last_week';
    } else {
      return AppStrings.get('voice_period_named_month', lang).replaceAll(
        '{month}',
        monthLong(DateTime(q.from.year, q.from.month), lang),
      );
    }
    return AppStrings.get(key, lang);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _prevMonth(DateTime d) => DateTime(d.year, d.month - 1, 1);

  DateTime _monday(DateTime today) =>
      today.subtract(Duration(days: today.weekday - 1));

  Future<void> _speak(String text, String lang) async {
    try {
      await _tts.stop();
      await _tts.setLanguage(lang == 'bn' ? 'bn-BD' : 'en-US');
      await _tts.setSpeechRate(lang == 'bn' ? 0.9 : 1.0);
      await _tts.speak(text);
    } catch (_) {
      // TTS unavailable — the answer card still shows.
    }
  }

  // ------------------------------------------------------------------
  // UI.
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? kDeepGreenCard : Colors.white;
    final textColor = dark ? Colors.white : kDeepGreenDark;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'voice_title'))),
      body: Column(
        children: [
          Expanded(
            child: _history.isEmpty
                ? _EmptyHint(card: card, textColor: textColor)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _history.length,
                    itemBuilder: (context, i) {
                      final entry = _history[i];
                      return Column(
                        children: [
                          // User query — right-aligned gold bubble.
                          Align(
                            alignment: Alignment.centerRight,
                            child: StaggeredEntrance(
                              key: ValueKey('q${entry.id}'),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    left: 48, bottom: 8, top: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: kGold,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(18),
                                    topRight: Radius.circular(18),
                                    bottomLeft: Radius.circular(18),
                                    bottomRight: Radius.circular(4),
                                  ),
                                ),
                                child: Text(
                                  entry.query,
                                  style: const TextStyle(
                                    color: kDeepGreenDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Answer — left-aligned card.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: StaggeredEntrance(
                              key: ValueKey('a${entry.id}'),
                              delayMs: 120,
                              child: Container(
                                margin: const EdgeInsets.only(
                                    right: 48, bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: card,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(18),
                                    bottomLeft: Radius.circular(18),
                                    bottomRight: Radius.circular(18),
                                  ),
                                  border: dark
                                      ? null
                                      : Border.all(
                                          color:
                                              kGold.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.volume_up,
                                        color: kGold, size: 20),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        entry.answer,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          // Listening hint.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _listening
                ? Padding(
                    key: const ValueKey('hint'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      tr(context, 'voice_listening'),
                      style: const TextStyle(color: kGold, fontSize: 13),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('nohint')),
          ),
          // Big gold mic button.
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: PressableScale(
              onTap: _toggleMic,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? Colors.redAccent : kGold,
                  boxShadow: [
                    BoxShadow(
                      color: (_listening ? Colors.redAccent : kGold)
                          .withValues(alpha: 0.4),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  _listening ? Icons.mic_off : Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final Color card;
  final Color textColor;

  const _EmptyHint({required this.card, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StaggeredEntrance(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.record_voice_over, color: kGold, size: 40),
              const SizedBox(height: 12),
              Text(
                tr(context, 'voice_tap_to_ask'),
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'voice_examples'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
