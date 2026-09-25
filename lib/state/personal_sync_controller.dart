import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/personal_sync_data.dart';
import '../services/personal_sync_service.dart';

abstract interface class PersonalSyncLocalData {
  Future<PersonalSyncData> read(String owner);
  Future<void> apply(
    String owner,
    PersonalSyncData before,
    PersonalSyncData target,
    bool Function() isCurrent,
  );
}

/// Account sync is always active while signed in. Epochs isolate stale requests;
/// disk/network failures retain pending local changes and retry automatically.
class PersonalSyncController extends ChangeNotifier {
  PersonalSyncController({
    required PersonalSyncLocalData local,
    PersonalSyncStore? store,
  }) : _local = local,
       _store = store ?? RemotePersonalSyncStore();
  final PersonalSyncLocalData _local;
  final PersonalSyncStore _store;
  String? owner;
  bool ready = false;
  bool get enabled => owner != null;
  bool syncing = false;
  DateTime? lastSyncedAt;
  String? error;
  int _epoch = 0;
  int _generation = 0;
  bool _disposed = false;
  PersonalSyncData _base = {};
  Map<String, dynamic>? _journal;
  Future<void> _queue = Future.value();
  bool _current(int generation) => !_disposed && generation == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() async {
    final account = owner;
    if (account == null) return;
    final record = <String, dynamic>{
      'schema': 2,
      'policy': 'always-on.v1',
      'epoch': _epoch,
      'base': {..._base},
      'journal': _journal,
    };
    final operation = _queue.then((_) => _store.saveLocal(account, record));
    _queue = operation.catchError((Object _) {});
    await operation;
  }

  Future<void> bind(String? username) async {
    final next = username?.trim().toLowerCase();
    if (next == owner) return;
    final generation = ++_generation;
    owner = next;
    ready = false;
    syncing = false;
    lastSyncedAt = null;
    error = null;
    _epoch = 0;
    _base = {};
    _journal = null;
    _emit();
    if (next == null) return;
    try {
      await _queue;
      final record = await _store.loadLocal(next);
      if (!_current(generation)) return;
      if (record != null) {
        if (![1, 2].contains(record['schema']) || record['epoch'] is! int) {
          throw const FormatException('Invalid sync preferences');
        }
        _base = validatePersonalData(record['base']);
        _journal = (record['journal'] as Map?)?.cast<String, dynamic>();
        if (_journal != null) {
          validatePersonalData(_journal!['before']);
          validatePersonalData(_journal!['target']);
        }
        _epoch = record['epoch'] as int;
        if (record['schema'] == 1 &&
            (record['enabled'] != true || record['deletionPending'] == true)) {
          // Old off/deletion intents are retired before any network request.
          // Keep the actual local content, not a baseline that could erase it
          // when the old cloud deletion already completed.
          _base = {};
          _journal = null;
        }
      }
      ready = true;
    } catch (_) {
      if (_current(generation)) error = '同步设置读取失败，请重试。';
    }
    if (_current(generation)) {
      _emit();
      unawaited(synchronize());
    }
  }

  Future<void> retryLoading() async {
    if (ready || owner == null) return;
    final account = owner;
    await bind(null);
    await bind(account);
  }

  Future<void> synchronize() async {
    final account = owner;
    if (!ready || syncing || account == null || _disposed) return;
    final generation = _generation;
    bool current() => _current(generation);
    syncing = true;
    _emit();
    try {
      // Persist the automatic policy and retire old deletion intents first.
      // Storage failure must never lead to a destructive/empty upload.
      await _persist();
      if (!current()) return;
      final control = await _store.ensure(account);
      if (!current()) return;
      if (!control.enabled || control.epoch <= 0) {
        throw const FormatException('Invalid automatic sync receipt');
      }
      _epoch = control.epoch;
      final epoch = _epoch;
      await _persist();
      if (!current()) return;
      final journal = _journal;
      if (journal != null) {
        await _local.apply(
          account,
          validatePersonalData(journal['before']),
          validatePersonalData(journal['target']),
          current,
        );
        if (!current()) return;
        _base = validatePersonalData(journal['target']);
        _journal = null;
        await _persist();
      }
      for (var attempt = 0; attempt < 3; attempt++) {
        final remote = await _store.fetch(account, epoch);
        if (!current()) return;
        final before = await _local.read(account);
        if (!current()) return;
        final target = validatePersonalData(
          mergePersonalData(_base, before, remote.value),
        );
        if (!sameSyncData(target, remote.value)) {
          try {
            if (!current()) return;
            await _store.put(
              account,
              epoch,
              PersonalSyncSnapshot(remote.version, target),
            );
          } on PersonalSyncConflict {
            continue;
          }
          if (!current()) return;
        }
        // Durable application journal protects partial writes/crashes. It is
        // local-only; the server epoch rejects a delayed request after account changes.
        _journal = {'before': before, 'target': target};
        await _persist();
        if (!current()) return;
        await _local.apply(account, before, target, current);
        if (!current()) return;
        _base = target;
        _journal = null;
        await _persist();
        error = null;
        lastSyncedAt = DateTime.now();
        return;
      }
      error = '同步暂未完成，稍后自动重试。';
    } catch (_) {
      if (current()) error = '同步暂未完成，稍后自动重试。';
    } finally {
      if (current()) {
        syncing = false;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _store.dispose();
    super.dispose();
  }
}
