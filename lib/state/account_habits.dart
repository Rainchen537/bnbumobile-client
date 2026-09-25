import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account_habit.dart';
import '../models/personal_sync_data.dart';
import '../services/sync/account_sync_storage.dart';

class HabitLease {
  const HabitLease(this.owner, this.generation);
  final String? owner;
  final int generation;
}

/// One account repository; UI habits never own network clients or timers.
class AccountHabits extends ChangeNotifier {
  AccountHabits({AccountSyncStorage? storage})
    : _storage = storage ?? AccountSyncStorage.shared;
  static final shared = AccountHabits();
  final AccountSyncStorage _storage;
  String? owner;
  bool managed = false;
  bool ready = false;
  int _generation = 0;
  Map<String, dynamic> _values = {};
  Future<void> _queue = Future.value();
  String? error;
  Completer<void>? _loading;
  HabitLease get lease => HabitLease(owner, _generation);
  bool _currentLease(HabitLease lease) =>
      lease.owner != null &&
      lease.owner == owner &&
      lease.generation == _generation;
  Future<void> Function(String, Object?)? _writeDelegate;

  /// Child windows delegate to the main account repository; they never own a second disk writer.
  void attachWindowSnapshot(
    String account,
    Map<String, dynamic> values,
    Future<void> Function(String, Object?) writer,
  ) {
    _generation++;
    managed = true;
    owner = AccountSyncStorage.account(account);
    _values = AccountHabit.validateSnapshot(values);
    ready = true;
    error = null;
    _writeDelegate = writer;
    notifyListeners();
  }

  void detachWindowSnapshot() {
    _generation++;
    managed = true;
    owner = null;
    ready = false;
    _values = {};
    _writeDelegate = null;
    notifyListeners();
  }

  bool isFor(String? value) =>
      ready && value != null && owner == AccountSyncStorage.account(value);
  T read<T>(String key, T fallback) {
    final record = _values[key];
    final value = ready && record is Map ? record['value'] : null;
    return value != null && value is T ? value : fallback;
  }

  Map<String, dynamic> get snapshot =>
      jsonDecode(jsonEncode(_values)) as Map<String, dynamic>;
  Future<void> bind(String? value) async {
    _writeDelegate = null;
    managed = true;
    final next = value == null ? null : AccountSyncStorage.account(value);
    if (owner == next && ready) return;
    if (_loading != null && !_loading!.isCompleted) _loading!.complete();
    final loaded = Completer<void>();
    _loading = loaded;
    final generation = ++_generation;
    owner = next;
    ready = false;
    error = null;
    _values = {};
    notifyListeners();
    if (next == null) {
      loaded.complete();
      return;
    }
    try {
      await _queue;
      var stored = await _storage.read(next, 'habits');
      stored ??= await _migrate(next);
      final values = AccountHabit.validateSnapshot(stored['values']);
      if (generation != _generation) return;
      _values = values;
      ready = true;
    } catch (_) {
      if (generation == _generation) error = '习惯设置读取失败，请重试。';
    } finally {
      if (!loaded.isCompleted) loaded.complete();
    }
    if (generation == _generation) notifyListeners();
  }

  Future<Map<String, dynamic>> _migrate(String account) async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, dynamic>{};
    void add(String key, Object? value) {
      if (value == null) return;
      try {
        AccountHabit.validate(key, value);
        values[key] = {'value': value, 'source': 'legacy'};
      } catch (_) {}
    }

    // Global legacy values have no historical owner; one account may adopt them.
    final hash = sha256.convert(utf8.encode(account)).toString();
    const claim = 'account.habits.legacy-owner.v1';
    if (prefs.getString(claim) == null && !await prefs.setString(claim, hash)) {
      throw StateError('Migration claim failed');
    }
    if (prefs.getString(claim) == hash) {
      for (final key in [...AccountHabit.choices.keys, ...AccountHabit.flags]) {
        // Preserve legacy language locally, but remote choices always win over migrated values.
        add(key, prefs.get(key));
      }
      add(
        'course_reminders.lead_minutes',
        prefs.getInt('course_reminders.lead_minutes')?.clamp(5, 120),
      );
      add(
        'study.organization_prompt',
        prefs.getString('bnbu.study.organization_prompt.v1'),
      );
    }
    if (prefs.getString(claim) == hash &&
        prefs.containsKey('deadline_reminders.mode_v2')) {
      add('deadline_reminders.policy', {
        'mode': prefs.getString('deadline_reminders.mode_v2'),
        'count': prefs.getInt('deadline_reminders.count_v2') ?? 3,
        'leads':
            (prefs.getStringList('deadline_reminders.fixed_lead_minutes_v2') ??
                    ['1440', '480', '120'])
                .map(int.tryParse)
                .whereType<int>()
                .toList(),
        'quietStart':
            prefs.getInt('deadline_reminders.quiet_start_minutes_v2') ?? 0,
        'quietEnd':
            prefs.getInt('deadline_reminders.quiet_end_minutes_v2') ?? 360,
      });
    }
    add(
      'schedule.show_deadlines',
      prefs.getBool('schedule.show_deadlines.v2.$hash') ??
          prefs.getBool(
            'schedule.show_deadlines.v2.${base64Url.encode(utf8.encode(account))}',
          ),
    );
    add(
      'schedule.week_layout',
      prefs.getString('schedule.week_layout.v1.$hash'),
    );
    add(
      'mail.compose.signature',
      prefs.getString(
            'mail.compose.signature.v1.${base64Url.encode(utf8.encode('$account@mail.bnbu.edu.cn'))}',
          ) ??
          prefs.getString(
            'mail.compose.signature.v1.${base64Url.encode(utf8.encode(account))}',
          ),
    );
    final rules = prefs.getString('mail_radar_rules_$hash');
    if (rules != null) {
      try {
        add('mail.radar.rules', jsonDecode(rules));
      } catch (_) {}
    }
    final record = {'values': values};
    await _storage.write(account, 'habits', record);
    return record;
  }

  Future<void> set(String key, Object? value, {HabitLease? lease}) async {
    if (!managed) {
      return; // Standalone previews retain their injected legacy stores.
    }
    final operationLease = lease ?? this.lease;
    if (!ready && _currentLease(operationLease)) await _loading?.future;
    if (!ready || !_currentLease(operationLease)) {
      throw StateError('Account habits operation expired');
    }
    AccountHabit.validate(key, value);
    if (_writeDelegate != null) {
      await _writeDelegate!(key, value);
      return;
    }
    final next = snapshot..[key] = {'value': value, 'source': 'explicit'};
    await _save(next);
  }

  Future<void> _save(Map<String, dynamic> values) async {
    final account = owner!;
    final generation = _generation;
    _values = values;
    final record = {'values': snapshot};
    final operation = _queue.then(
      (_) => _storage.write(account, 'habits', record),
    );
    _queue = operation.catchError((Object _) {});
    try {
      await operation;
      if (generation == _generation) error = null;
    } catch (_) {
      if (generation == _generation) error = '习惯设置尚未保存，请重试。';
      rethrow;
    } finally {
      if (generation == _generation) notifyListeners();
    }
  }

  Future<void> ensureSaved() async {
    await _queue;
    if (!ready) throw StateError('Habits not ready');
    if (error != null) await _save(snapshot);
  }

  Future<void> apply(
    Map<String, dynamic> before,
    Map<String, dynamic> target,
  ) async {
    final next = AccountHabit.validateSnapshot(
      recoverPersonalData(before, snapshot, target),
    );
    if (!sameSyncData(next, _values)) await _save(next);
  }
}
