import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course_display_preferences.dart';
import 'usage_sync_service.dart';

class CourseDisplaySnapshot {
  const CourseDisplaySnapshot(this.version, this.value);
  final int version;
  final CourseDisplayPreferences value;
}

class CourseDisplayConflict implements Exception {}

abstract interface class CourseDisplayPreferencesStore {
  Future<Map<String, dynamic>?> loadLocal(String owner);
  Future<void> saveLocal(String owner, Map<String, dynamic> record);
  Future<CourseDisplaySnapshot> fetch(String owner);
  Future<void> put(String owner, CourseDisplaySnapshot snapshot);
  void dispose();
}

class RemoteCourseDisplayPreferencesStore
    implements CourseDisplayPreferencesStore {
  RemoteCourseDisplayPreferencesStore({
    http.Client? client,
    UsageSyncStore? devices,
    String? baseUrl,
  });

  static const namespace = 'ispace.course-display.v1';
  late final _local = SharedPreferencesAsync();
  String _key(String owner) =>
      'ispace.course-display.${sha256.convert(utf8.encode(owner))}';

  @override
  Future<Map<String, dynamic>?> loadLocal(String owner) async {
    final raw = await _local.getString(_key(owner));
    return raw == null
        ? null
        : (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  @override
  Future<void> saveLocal(String owner, Map<String, dynamic> record) =>
      _local.setString(_key(owner), jsonEncode(record));

  @override
  Future<CourseDisplaySnapshot> fetch(String owner) =>
      Future.error(StateError('Use PersonalSyncCoordinator'));
  @override
  Future<void> put(String owner, CourseDisplaySnapshot snapshot) =>
      Future.error(StateError('Use PersonalSyncCoordinator'));

  @override
  void dispose() {}
}
