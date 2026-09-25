import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/course_display_preferences.dart';
import '../services/course_display_preferences_service.dart';

class CourseDisplayPreferencesController extends ChangeNotifier {
  CourseDisplayPreferencesController({
    CourseDisplayPreferencesStore? store,
    bool Function()? syncAllowed,
  }) : _store = store ?? RemoteCourseDisplayPreferencesStore(),
       _syncAllowed = syncAllowed ?? _disabled;
  static bool _disabled() => false;
  final bool Function() _syncAllowed;
  final CourseDisplayPreferencesStore _store;
  CourseDisplayPreferences value = CourseDisplayPreferences();
  String? owner;
  bool ready = false;
  bool syncing = false;
  bool syncUnavailable = false;
  bool localSaveFailed = false;
  bool _accepted = false;
  bool _disposed = false;
  int _generation = 0;
  Map<String, dynamic> _pending = {};
  Future<void> _localQueue = Future.value();
  bool get hasPending => _pending.isNotEmpty;
  int get bindingGeneration => _generation;

  bool _current(int generation) => !_disposed && generation == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> bind(String? username) async {
    final next = username?.trim().toLowerCase();
    if (owner == next) return;
    final generation = ++_generation;
    owner = next;
    value = CourseDisplayPreferences();
    _pending = {};
    ready = false;
    _accepted = false;
    syncing = false;
    syncUnavailable = false;
    localSaveFailed = false;
    _emit();
    if (next == null) return;
    try {
      final record = await _store.loadLocal(next);
      if (!_current(generation)) return;
      if (record != null) {
        final saved = CourseDisplayPreferences.fromJson(record['value']);
        final pending = (record['pending'] as Map).cast<String, dynamic>();
        value = saved.apply(pending);
        _pending = pending;
        _accepted = record['accepted'] == true;
      }
    } catch (_) {
      if (_current(generation)) localSaveFailed = true;
    }
    if (!_current(generation)) return;
    ready = true;
    _emit();
    unawaited(synchronize());
  }

  Future<void> saveDraft(
    CourseDisplayPreferences draft,
    CourseDisplayPreferences baseline,
  ) async {
    if (!ready || owner == null || _disposed) return;
    final changes = draft.changesFrom(baseline);
    if (changes.isEmpty) return;
    value = value.apply(changes);
    _pending = {..._pending, ...changes};
    _accepted = _syncAllowed(); // Local Save alone never grants sync consent.
    _emit();
    await _persist();
    unawaited(synchronize());
  }

  /// Persist only this name, never a management window's order/hidden draft.
  /// A captured generation also rejects logout/login back to the same account.
  Future<void> saveName(
    int courseId,
    String? name, {
    required int expectedGeneration,
  }) async {
    if (!_current(expectedGeneration) || !ready || owner == null) {
      throw StateError('Preferences binding expired');
    }
    final baseline = value;
    final draft = baseline.apply({'name:$courseId': name});
    if (draft.changesFrom(baseline).isEmpty) {
      // A previous failed write may already be reflected in memory.
      if (localSaveFailed) {
        await _persist();
        if (_current(expectedGeneration)) {
          _emit();
          unawaited(synchronize());
        }
      }
      return;
    }
    await saveDraft(draft, baseline);
  }

  Future<void> _persist() async {
    final account = owner;
    final generation = _generation;
    if (account == null) return;
    final record = {
      'value': value.toJson(),
      'pending': {..._pending},
      'accepted': _accepted,
    };
    final operation = _localQueue.then(
      (_) => _store.saveLocal(account, record),
    );
    _localQueue = operation.catchError((Object _) {});
    try {
      await operation;
      if (_current(generation)) localSaveFailed = false;
    } catch (_) {
      if (_current(generation)) {
        localSaveFailed = true;
        _emit();
      }
      rethrow;
    }
  }

  Future<void> synchronize() async {
    final account = owner;
    if (!_syncAllowed() || !ready || syncing || account == null || _disposed) {
      return;
    }
    final generation = _generation;
    syncing = true;
    _emit();
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final remote = await _store.fetch(account);
        if (!_current(generation)) return;
        final patch = {..._pending};
        final merged = remote.value.apply(patch);
        if (patch.isNotEmpty && _accepted) {
          // Durable intent precedes a network write. A lost response is safe to replay.
          await _persist();
          if (!_current(generation)) return;
          try {
            await _store.put(
              account,
              CourseDisplaySnapshot(remote.version, merged),
            );
          } on CourseDisplayConflict {
            continue;
          }
          if (!_current(generation)) return;
          for (final entry in patch.entries) {
            if (_pending.containsKey(entry.key) &&
                jsonEncode(_pending[entry.key]) == jsonEncode(entry.value)) {
              _pending.remove(entry.key);
            }
          }
        }
        value = merged.apply(_pending);
        await _persist();
        if (!_current(generation)) return;
        syncUnavailable = false;
        if (_pending.isEmpty) return;
      }
      syncUnavailable = true;
    } catch (_) {
      if (_current(generation)) syncUnavailable = true;
    } finally {
      if (_current(generation)) {
        syncing = false;
        _emit();
      }
    }
  }

  Future<void> applySynchronized(CourseDisplayPreferences value) async {
    if (!ready || owner == null || _disposed) {
      throw StateError('Preferences not ready');
    }
    this.value = value;
    _pending = {};
    await _persist();
    _emit();
  }

  Future<void> ensureSaved() async {
    await _localQueue;
    if (localSaveFailed) throw StateError('Preferences not saved');
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _store.dispose();
    super.dispose();
  }
}
