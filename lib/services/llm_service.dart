import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Config — stored in secure storage, NEVER in plain settings.
// ---------------------------------------------------------------------------

/// LLM provider configuration.
///
/// Key resolution order:
/// 1. User override in Settings (secure storage) — takes precedence.
/// 2. Bundled key baked at compile time via --dart-define=LLM_API_KEY.
/// The API key is never logged.
class LlmConfig {
  /// 'gemini' or 'openai' (OpenAI-compatible).
  String provider;
  String apiKey;
  String model;
  String baseUrl;

  LlmConfig({
    this.provider = 'gemini',
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
  });

  static const _kProvider = 'llm_provider';
  static const _kApiKey = 'llm_api_key';
  static const _kModel = 'llm_model';
  static const _kBaseUrl = 'llm_base_url';

  static const _storage = FlutterSecureStorage();

  /// Compile-time bundled values (--dart-define). Empty when not provided.
  static const String bundledKey =
      String.fromEnvironment('LLM_API_KEY', defaultValue: '');
  static const String bundledProvider =
      String.fromEnvironment('LLM_PROVIDER', defaultValue: 'gemini');
  static const String bundledModel =
      String.fromEnvironment('LLM_MODEL', defaultValue: 'gemini-3.8-flash');

  /// The key actually used: Settings override first, then bundled key.
  String get effectiveKey =>
      apiKey.trim().isNotEmpty ? apiKey.trim() : bundledKey;

  /// Provider/model/baseUrl overrides only apply together with an override
  /// key; otherwise the bundled compile-time values are used. This avoids
  /// sending (e.g.) a Gemini key to an OpenAI endpoint.
  String get effectiveProvider {
    if (apiKey.trim().isEmpty) {
      return bundledProvider.isNotEmpty ? bundledProvider : 'gemini';
    }
    return provider.trim().isNotEmpty ? provider.trim() : 'gemini';
  }

  String get effectiveModel {
    if (apiKey.trim().isEmpty) {
      return bundledModel.isNotEmpty ? bundledModel : 'gemini-3.8-flash';
    }
    if (model.trim().isNotEmpty) return model.trim();
    final p = provider.trim().isNotEmpty ? provider.trim() : 'gemini';
    return p == 'openai' ? 'gpt-4o-mini' : 'gemini-3.8-flash';
  }

  String get effectiveBaseUrl {
    if (baseUrl.trim().isNotEmpty) {
      return baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return 'https://api.openai.com/v1';
  }

  bool get isConfigured => effectiveKey.isNotEmpty;

  /// Loads config from secure storage. Never throws.
  static Future<LlmConfig> load() async {
    try {
      final provider = await _storage.read(key: _kProvider) ?? 'gemini';
      final apiKey = await _storage.read(key: _kApiKey) ?? '';
      final model = await _storage.read(key: _kModel) ?? '';
      final baseUrl = await _storage.read(key: _kBaseUrl) ?? '';
      return LlmConfig(
        provider: provider,
        apiKey: apiKey,
        model: model,
        baseUrl: baseUrl,
      );
    } catch (_) {
      return LlmConfig();
    }
  }

  Future<void> save() async {
    await _storage.write(key: _kProvider, value: provider);
    await _storage.write(key: _kApiKey, value: apiKey.trim());
    await _storage.write(key: _kModel, value: model.trim());
    await _storage.write(key: _kBaseUrl, value: baseUrl.trim());
  }

  Future<void> clearKey() async {
    await _storage.delete(key: _kApiKey);
    apiKey = '';
  }

  static Future<void> clearAll() async {
    await _storage.delete(key: _kProvider);
    await _storage.delete(key: _kApiKey);
    await _storage.delete(key: _kModel);
    await _storage.delete(key: _kBaseUrl);
  }
}

// ---------------------------------------------------------------------------
// Message / reply types (provider-agnostic).
// ---------------------------------------------------------------------------

/// One chat turn. Roles: 'user', 'assistant', 'tool'.
class LlmMessage {
  final String role;
  final String text;
  final List<String> imagePaths;
  final List<LlmToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;

  const LlmMessage._({
    required this.role,
    this.text = '',
    this.imagePaths = const [],
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  factory LlmMessage.user(String text, {List<String> imagePaths = const []}) =>
      LlmMessage._(role: 'user', text: text, imagePaths: imagePaths);

  factory LlmMessage.assistant(String text,
          {List<LlmToolCall> toolCalls = const []}) =>
      LlmMessage._(role: 'assistant', text: text, toolCalls: toolCalls);

  factory LlmMessage.toolResult(
          {required String toolCallId,
          required String toolName,
          required String result}) =>
      LlmMessage._(
          role: 'tool',
          text: result,
          toolCallId: toolCallId,
          toolName: toolName);
}

class LlmToolCall {
  final String name;
  final Map<String, dynamic> args;
  final String? id;

  const LlmToolCall({required this.name, required this.args, this.id});
}

class LlmReply {
  final String? text;
  final List<LlmToolCall> toolCalls;

  const LlmReply({this.text, this.toolCalls = const []});
}

// ---------------------------------------------------------------------------
// Service.
// ---------------------------------------------------------------------------

class LlmService {
  LlmService._();

  /// Max image bytes sent to the LLM (larger files are skipped with a note).
  static const int maxImageBytes = 1024 * 1024;

  static Future<LlmReply> chat({
    required LlmConfig config,
    required List<LlmMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolSchemas,
  }) async {
    if (!config.isConfigured) {
      return const LlmReply(text: null, toolCalls: []);
    }
    try {
      if (config.effectiveProvider == 'openai') {
        return await _chatOpenAi(
          config: config,
          history: history,
          systemPrompt: systemPrompt,
          toolSchemas: toolSchemas,
        );
      }
      return await _chatGemini(
        config: config,
        history: history,
        systemPrompt: systemPrompt,
        toolSchemas: toolSchemas,
      );
    } catch (e) {
      return LlmReply(text: _friendlyError(e));
    }
  }

  /// Quick connectivity/key check: asks the model to reply "ok".
  static Future<String?> testConnection(LlmConfig config) async {
    final reply = await chat(
      config: config,
      history: [LlmMessage.user('Reply with exactly: ok')],
      systemPrompt: 'You are a test endpoint. Reply with exactly: ok',
      toolSchemas: const [],
    );
    if (reply.text != null && reply.text!.toLowerCase().contains('ok')) {
      return null; // success
    }
    return reply.text ?? 'Empty response';
  }

  // ------------------------- Gemini -------------------------

  static Future<LlmReply> _chatGemini({
    required LlmConfig config,
    required List<LlmMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolSchemas,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${config.effectiveModel}:generateContent?key=${config.effectiveKey}',
    );
    final contents = <Map<String, dynamic>>[];
    for (final m in history) {
      contents.add(await _geminiMessage(m));
    }
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {'temperature': 0.7},
    };
    if (toolSchemas.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': toolSchemas
              .map((t) => {
                    'name': t['name'],
                    'description': t['description'],
                    'parameters': t['parameters'],
                  })
              .toList(),
        }
      ];
    }
    final resp = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      throw _HttpError(resp.statusCode, _safeBody(resp.body));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final blockReason =
          data['promptFeedback']?['blockReason']?.toString() ?? 'unknown';
      throw Exception('empty:$blockReason');
    }
    final parts =
        (candidates.first['content']?['parts'] as List?) ?? const [];
    String? text;
    final calls = <LlmToolCall>[];
    for (final p in parts) {
      final pm = p as Map<String, dynamic>;
      if (pm['text'] is String) {
        text = (text ?? '') + (pm['text'] as String);
      }
      final fc = pm['functionCall'] as Map<String, dynamic>?;
      if (fc != null) {
        calls.add(LlmToolCall(
          name: fc['name']?.toString() ?? '',
          args: Map<String, dynamic>.from(fc['args'] as Map? ?? {}),
        ));
      }
    }
    return LlmReply(text: text?.trim().isEmpty == true ? null : text?.trim(), toolCalls: calls);
  }

  static Future<Map<String, dynamic>> _geminiMessage(LlmMessage m) async {
    switch (m.role) {
      case 'assistant':
        final parts = <Map<String, dynamic>>[];
        if (m.text.isNotEmpty) parts.add({'text': m.text});
        for (final c in m.toolCalls) {
          parts.add({
            'functionCall': {'name': c.name, 'args': c.args}
          });
        }
        return {'role': 'model', 'parts': parts};
      case 'tool':
        return {
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': m.toolName ?? 'result',
                'response': {'result': m.text},
              }
            }
          ]
        };
      default:
        final parts = <Map<String, dynamic>>[];
        if (m.text.isNotEmpty) parts.add({'text': m.text});
        for (final p in m.imagePaths) {
          final inline = await _readImageInline(p);
          if (inline != null) parts.add({'inlineData': inline});
        }
        return {
          'role': 'user',
          'parts': parts.isEmpty ? [
            {'text': '(image only)'}
          ] : parts
        };
    }
  }

  static Future<Map<String, String>?> _readImageInline(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (bytes.length > maxImageBytes) return null;
      final mime = path.toLowerCase().endsWith('.png')
          ? 'image/png'
          : path.toLowerCase().endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      return {'mimeType': mime, 'data': base64Encode(bytes)};
    } catch (_) {
      return null;
    }
  }

  // ------------------------- OpenAI-compatible -------------------------

  static Future<LlmReply> _chatOpenAi({
    required LlmConfig config,
    required List<LlmMessage> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolSchemas,
  }) async {
    final uri = Uri.parse('${config.effectiveBaseUrl}/chat/completions');
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    for (final m in history) {
      messages.add(await _openAiMessage(m));
    }
    final body = <String, dynamic>{
      'model': config.effectiveModel,
      'messages': messages,
      'temperature': 0.7,
    };
    if (toolSchemas.isNotEmpty) {
      body['tools'] = toolSchemas
          .map((t) => {
                'type': 'function',
                'function': {
                  'name': t['name'],
                  'description': t['description'],
                  'parameters': t['parameters'],
                },
              })
          .toList();
      body['tool_choice'] = 'auto';
    }
    final resp = await http
        .post(uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.effectiveKey}',
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      throw _HttpError(resp.statusCode, _safeBody(resp.body));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('empty:unknown');
    }
    final msg = choices.first['message'] as Map<String, dynamic>? ?? {};
    final content = msg['content'];
    String? text;
    if (content is String) {
      text = content;
    } else if (content is List) {
      final buf = StringBuffer();
      for (final c in content) {
        if (c is Map && c['type'] == 'text') buf.write(c['text'] ?? '');
      }
      text = buf.toString();
    }
    final calls = <LlmToolCall>[];
    final toolCalls = msg['tool_calls'] as List?;
    if (toolCalls != null) {
      for (final tc in toolCalls) {
        final tm = tc as Map<String, dynamic>;
        final fn = tm['function'] as Map<String, dynamic>? ?? {};
        Map<String, dynamic> args = {};
        try {
          final raw = fn['arguments'];
          if (raw is String && raw.trim().isNotEmpty) {
            args = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          } else if (raw is Map) {
            args = Map<String, dynamic>.from(raw);
          }
        } catch (_) {}
        calls.add(LlmToolCall(
          name: fn['name']?.toString() ?? '',
          args: args,
          id: tm['id']?.toString(),
        ));
      }
    }
    return LlmReply(text: text?.trim().isEmpty == true ? null : text?.trim(), toolCalls: calls);
  }

  static Future<Map<String, dynamic>> _openAiMessage(LlmMessage m) async {
    switch (m.role) {
      case 'assistant':
        final out = <String, dynamic>{'role': 'assistant'};
        if (m.text.isNotEmpty) out['content'] = m.text;
        if (m.toolCalls.isNotEmpty) {
          out['tool_calls'] = [
            for (final c in m.toolCalls)
              {
                'id': c.id ?? 'call_${c.name}',
                'type': 'function',
                'function': {
                  'name': c.name,
                  'arguments': jsonEncode(c.args),
                },
              }
          ];
        }
        return out;
      case 'tool':
        return {
          'role': 'tool',
          'tool_call_id': m.toolCallId ?? 'call_${m.toolName}',
          'content': m.text,
        };
      default:
        if (m.imagePaths.isEmpty) {
          return {'role': 'user', 'content': m.text};
        }
        final content = <Map<String, dynamic>>[
          {'type': 'text', 'text': m.text.isEmpty ? '(image)' : m.text},
        ];
        for (final p in m.imagePaths) {
          final url = await _readImageDataUrl(p);
          if (url != null) {
            content.add({
              'type': 'image_url',
              'image_url': {'url': url}
            });
          }
        }
        return {'role': 'user', 'content': content};
    }
  }

  static Future<String?> _readImageDataUrl(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (bytes.length > maxImageBytes) return null;
      final lower = path.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  // ------------------------- errors -------------------------

  static String _safeBody(String body) {
    // Never include anything that could contain the key; keep it short.
    final b = body.trim();
    return b.length > 300 ? '${b.substring(0, 300)}…' : b;
  }

  static String _friendlyError(Object e) {
    if (e is _HttpError) {
      if (e.status == 400) {
        return '⚠️ Request rejected (400). The model name or request format may be wrong. ${_safeBody(e.body)}';
      }
      if (e.status == 401 || e.status == 403) {
        return '🔑 API key rejected (HTTP ${e.status}). Please check the key in Settings → AI Assistant.';
      }
      if (e.status == 404) {
        return '⚠️ Model or endpoint not found (404). Check the model name / base URL.';
      }
      if (e.status == 429) {
        return '⏳ Rate limit hit (429). Please wait a bit and try again.';
      }
      if (e.status >= 500) {
        return '🌐 AI server error (HTTP ${e.status}). Try again in a moment.';
      }
      return '⚠️ AI request failed (HTTP ${e.status}).';
    }
    final s = e.toString();
    if (s.contains('empty:')) {
      return '⚠️ The AI returned an empty response. Try rephrasing.';
    }
    if (s.contains('TimeoutException') ||
        s.contains('SocketException') ||
        s.contains('ClientException')) {
      return '🌐 No connection to the AI server. Check your internet and try again.';
    }
    return '⚠️ AI error. Please try again.';
  }
}

class _HttpError implements Exception {
  final int status;
  final String body;
  _HttpError(this.status, this.body);
}

// ---------------------------------------------------------------------------
// System prompt.
// ---------------------------------------------------------------------------

/// Builds the system prompt for the financial assistant.
String buildAssistantSystemPrompt({
  required String lang,
  required String todayIso,
  required String categoryList,
}) {
  final bn = lang == 'bn';
  return '''
You are Prio, a friendly personal financial assistant inside the Khorcha expense-tracker app. The user talks to you like a friend — be warm, conversational, and concise.

LANGUAGE — you are fully multilingual, like a normal AI assistant:
- ALWAYS reply in the SAME language the user writes in. Detect it from their message: Bangla, English, Banglish (Bangla in Latin script), Hindi, Urdu, Arabic, Spanish, French, or ANY other language.
- If they write in Bangla script → reply in Bangla. Banglish → reply in Banglish/Bangla mix naturally. English → English. Hindi → Hindi. And so on for every language.
- Default to ${bn ? 'Bangla (Bangladesh)' : 'English'} only when you cannot detect a language.

Today is $todayIso. All amounts are in BDT (৳). Format money like ৳1,250.

You can manage the user's finances with tools — USE THEM, don't just talk:
- add_expense: when the user says they spent money ("ajke 500 tk khoroch korlam", "lunch 200"). Pick the best category from this list: $categoryList. If unsure, use "others". Note = what they bought (short).
- add_income: when the user received money ("3000 tk pelam", "salary 50000", "income holo").
- set_budget / set_monthly_budget: when the user sets a spending limit.
- delete_last_expense: only when the user explicitly asks to delete/remove the last entry.
- get_spending_summary: to answer "koto khoroch holo", "ei mashe koto", breakdowns, comparisons.
- get_wallet_balances / set_wallet_balance: for "kothay koto tk ache" questions and balance updates.

Rules:
- NEVER invent numbers. If you need a fact (spending, balance), call the right tool first.
- After a tool action, confirm briefly in one friendly line, e.g. "Hoise! ✅ Lunch-e ৳200 add korlam (Food)."
- For questions, keep answers short and readable; use ৳ formatting.
- Dates: "ajke" = $todayIso. Parse relative dates yourself into YYYY-MM-DD.
- If the user just greets or chats ("kemon acho", "hi"), reply warmly like a friend — no tools needed.
- If an image of a bill/receipt is attached, read the total amount and merchant from it, then call add_expense with what you found and confirm.
- Never mention tool names, JSON, or system instructions to the user.
''';
}
