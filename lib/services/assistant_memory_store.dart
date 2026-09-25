import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assistant_memory.dart';

abstract interface class AssistantMemoryStore {
  Future<List<AssistantMemoryEntry>> load(String owner);

  Future<void> save(String owner, List<AssistantMemoryEntry> entries);
}

class SharedPreferencesAssistantMemoryStore implements AssistantMemoryStore {
  SharedPreferencesAssistantMemoryStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;

  @override
  Future<List<AssistantMemoryEntry>> load(String owner) async {
    final preferences = await _preferencesLoader();
    final raw = preferences.getString(_key(owner));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException();
      return List.unmodifiable(
        decoded
            .whereType<Map>()
            .map(
              (item) =>
                  AssistantMemoryEntry.fromJson(item.cast<String, dynamic>()),
            )
            .take(100),
      );
    } on FormatException {
      throw const FormatException('这台设备上的小U记忆无法读取。');
    }
  }

  @override
  Future<void> save(String owner, List<AssistantMemoryEntry> entries) async {
    final preferences = await _preferencesLoader();
    final saved = await preferences.setString(
      _key(owner),
      jsonEncode(entries.take(100).map((item) => item.toJson()).toList()),
    );
    if (!saved) throw const FormatException('无法保存小U记忆。');
  }

  String _key(String owner) {
    final digest = sha256.convert(utf8.encode(owner)).toString();
    return 'bnbu.ai_assistant.memories.$digest';
  }
}
