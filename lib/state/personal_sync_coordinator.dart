import '../services/me_identity_service.dart';
import 'dart:async';

import '../models/personal_sync_data.dart';
import '../services/sync/sync_scheduler.dart';
import 'account_habits.dart';
import 'app_session_controller.dart';
import 'course_display_preferences_controller.dart';
import 'personal_sync_controller.dart';
import 'ta_course_controller.dart';

class PersonalSyncCoordinator implements PersonalSyncLocalData {
  PersonalSyncCoordinator({required this.session, required this.schedules}) {
    controller = PersonalSyncController(local: this);
    session.addListener(_accountChanged);
    MeIdentityService.shared.addListener(_meChanged);
    schedules.addListener(_dataChanged);
    courses.addListener(_dataChanged);
    habits.addListener(_dataChanged);
    _accountChanged();
    _cancelPoll = SyncScheduler.shared.register(
      key: this,
      interval: const Duration(seconds: 45),
      run: controller.synchronize,
    );
  }
  final AppSessionController session;
  final TaCourseController schedules;
  final courses = CourseDisplayPreferencesController();
  final habits = AccountHabits.shared;
  late final PersonalSyncController controller;
  void Function()? _cancelPoll;
  Timer? _debounce;
  bool _foreground = true;
  bool _disposed = false;
  String? _owner;

  void _meChanged() {
    final owner = _owner;
    unawaited(
      controller.bind(
        owner != null && MeIdentityService.shared.syncEnabled(owner)
            ? owner
            : null,
      ),
    );
  }

  void _accountChanged() {
    final owner = session.isLoggedIn
        ? session.username?.trim().toLowerCase()
        : null;
    if (owner == _owner) return;
    _owner = owner;
    // Revoke the old account synchronously, before loading new local data.
    unawaited(controller.bind(null));
    unawaited(_bind(owner));
  }

  Future<void> _bind(String? owner) async {
    await habits.bind(owner);
    if (_disposed || owner != _owner) return;
    await courses.bind(owner);
    if (_disposed || owner != _owner) return;
    if (owner != null) {
      await schedules.ensureLoaded();
      if (_disposed || owner != _owner) return;
    }
    if (owner != null) await MeIdentityService.shared.restore(owner);
    if (_disposed || owner != _owner) return;
    await controller.bind(
      owner != null && MeIdentityService.shared.syncEnabled(owner)
          ? owner
          : null,
    );
  }

  void _tick() {
    if (!_disposed && _foreground) unawaited(controller.synchronize());
  }

  void _dataChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), _tick);
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) _tick();
  }

  @override
  Future<PersonalSyncData> read(String owner) async {
    final result = await schedules.ensureLoaded();
    await courses.ensureSaved();
    await habits.ensureSaved();
    if (_disposed ||
        owner != _owner ||
        courses.owner != owner ||
        !courses.ready ||
        courses.localSaveFailed ||
        !result.isSuccess) {
      throw StateError('Local settings not ready');
    }
    return {
      ...encodePersonalData(courses.value, schedules.entries),
      for (final e in habits.snapshot.entries) 'habit:${e.key}': e.value,
    };
  }

  @override
  Future<void> apply(
    String owner,
    PersonalSyncData before,
    PersonalSyncData target,
    bool Function() isCurrent,
  ) async {
    bool current() => !_disposed && owner == _owner && isCurrent();
    if (!current()) return;
    // Repository performs its merge inside the same local mutation queue as
    // manual edits and small-U confirmed actions, preserving in-flight edits.
    await schedules.applySynchronized(owner, before, target, current);
    if (!current()) return;
    final local = encodePersonalData(courses.value, const []);
    final onlyCourses = <String, dynamic>{
      for (final item in before.entries)
        if (!item.key.startsWith('entry:') && !item.key.startsWith('habit:'))
          item.key: item.value,
    };
    final merged = recoverPersonalData(onlyCourses, local, {
      for (final item in target.entries)
        if (!item.key.startsWith('entry:') && !item.key.startsWith('habit:'))
          item.key: item.value,
    });
    if (!sameSyncData(local, merged)) {
      await courses.applySynchronized(syncCourses(merged));
    }
    if (!current()) return;
    await habits.apply(
      {
        for (final e in before.entries)
          if (e.key.startsWith('habit:')) e.key.substring(6): e.value,
      },
      {
        for (final e in target.entries)
          if (e.key.startsWith('habit:')) e.key.substring(6): e.value,
      },
    );
  }

  void dispose() {
    _disposed = true;
    _cancelPoll?.call();
    _debounce?.cancel();
    session.removeListener(_accountChanged);
    MeIdentityService.shared.removeListener(_meChanged);
    schedules.removeListener(_dataChanged);
    courses.removeListener(_dataChanged);
    habits.removeListener(_dataChanged);
    unawaited(habits.bind(null));
    controller.dispose();
    courses.dispose();
  }
}
