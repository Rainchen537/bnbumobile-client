import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timetable_data.dart';

abstract interface class TimetableCacheStore {
  Future<TimetableData?> load(String username);

  Future<void> save(String username, TimetableData timetable);
}

class SharedPreferencesTimetableCacheStore implements TimetableCacheStore {
  static const String _keyPrefix = 'timetable.cache.v1';

  @override
  Future<TimetableData?> load(String username) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_keyFor(username));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return TimetableData.fromJson(decoded);
    } on FormatException {
      await preferences.remove(_keyFor(username));
      return null;
    }
  }

  @override
  Future<void> save(String username, TimetableData timetable) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _keyFor(username),
      jsonEncode(timetable.toJson()),
    );
  }

  String _keyFor(String username) {
    final normalized = username.trim().toLowerCase();
    final owner = sha256.convert(utf8.encode(normalized));
    return '$_keyPrefix.$owner';
  }
}
