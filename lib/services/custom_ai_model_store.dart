import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A user-defined AI model configuration.
class CustomAiModel {
  final String id;
  final String name;
  final String provider; // 'gemini', 'openai', 'nvidia'
  final String baseUrl;
  final String model;
  final String apiKey;

  CustomAiModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'provider': provider,
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
      };

  factory CustomAiModel.fromMap(Map<String, dynamic> m) => CustomAiModel(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        provider: m['provider'] as String? ?? 'openai',
        baseUrl: m['baseUrl'] as String? ?? '',
        model: m['model'] as String? ?? '',
        apiKey: m['apiKey'] as String? ?? '',
      );
}

/// Manages user-added custom AI models (stored in secure storage).
class CustomAiModelStore {
  CustomAiModelStore._();
  static final CustomAiModelStore instance = CustomAiModelStore._();

  static const _kModels = 'custom_ai_models';
  static const _kActiveId = 'custom_ai_active_id';
  static const _storage = FlutterSecureStorage();

  Future<List<CustomAiModel>> loadAll() async {
    try {
      final raw = await _storage.read(key: _kModels);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              CustomAiModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<CustomAiModel> models) async {
    final raw = jsonEncode(models.map((m) => m.toMap()).toList());
    await _storage.write(key: _kModels, value: raw);
  }

  Future<void> add(CustomAiModel model) async {
    final all = await loadAll();
    all.add(model);
    await saveAll(all);
  }

  Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((m) => m.id == id);
    await saveAll(all);
    final active = await getActiveId();
    if (active == id) {
      await _storage.delete(key: _kActiveId);
    }
  }

  Future<String?> getActiveId() => _storage.read(key: _kActiveId);

  Future<void> setActiveId(String? id) async {
    if (id == null) {
      await _storage.delete(key: _kActiveId);
    } else {
      await _storage.write(key: _kActiveId, value: id);
    }
  }

  Future<CustomAiModel?> getActive() async {
    final id = await getActiveId();
    if (id == null) return null;
    final all = await loadAll();
    try {
      return all.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
