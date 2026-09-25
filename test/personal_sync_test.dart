import 'dart:async';
import 'dart:convert';

import 'package:bnbu_me/models/course_display_preferences.dart';
import 'package:bnbu_me/models/personal_sync_data.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/services/personal_sync_service.dart';
import 'package:bnbu_me/state/course_display_preferences_controller.dart';
import 'package:bnbu_me/state/personal_sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'course_display_preferences_test.dart' show MemoryCourseStore;

PersonalSyncData copy(PersonalSyncData data) =>
    (jsonDecode(jsonEncode(data)) as Map).cast<String, dynamic>();

class MemoryPersonalData implements PersonalSyncLocalData {
  final values = <String, PersonalSyncData>{};
  bool failApply = false;
  @override
  Future<PersonalSyncData> read(String owner) async =>
      copy(values[owner] ?? {});
  @override
  Future<void> apply(
    String owner,
    PersonalSyncData before,
    PersonalSyncData target,
    bool Function() isCurrent,
  ) async {
    if (failApply) throw StateError('disk');
    if (isCurrent()) {
      values[owner] = recoverPersonalData(before, values[owner] ?? {}, target);
    }
  }
}

class MemoryPersonalServer {
  final controls = <String, PersonalSyncControl>{};
  final values = <String, PersonalSyncSnapshot>{};
}

class MemoryPersonalStore implements PersonalSyncStore {
  MemoryPersonalStore(this.server);
  final MemoryPersonalServer server;
  final local = <String, Map<String, dynamic>>{};
  bool offline = false;
  bool losePutResponse = false;
  bool failSave = false;
  int networkCalls = 0;
  int puts = 0;
  Completer<void>? putGate;
  Completer<void>? fetchGate;
  Future<void> Function()? beforePut;
  void check() {
    networkCalls++;
    if (offline) throw StateError('offline');
  }

  PersonalSyncControl status(String owner) =>
      server.controls[owner] ?? const PersonalSyncControl(false, 0);
  void lease(String owner, int epoch) {
    if (!status(owner).enabled || status(owner).epoch != epoch) {
      throw PersonalSyncRevoked();
    }
  }

  @override
  Future<Map<String, dynamic>?> loadLocal(String owner) async =>
      local[owner] == null ? null : copy(local[owner]!);
  @override
  Future<void> saveLocal(String owner, Map<String, dynamic> value) async {
    if (failSave) throw StateError('disk');
    local[owner] = copy(value);
  }

  @override
  Future<PersonalSyncControl> ensure(String owner) async {
    check();
    final old = status(owner);
    final result = PersonalSyncControl(
      true,
      old.enabled ? old.epoch : old.epoch + 1,
    );
    server.controls[owner] = result;
    return result;
  }

  @override
  Future<PersonalSyncSnapshot> fetch(String owner, int epoch) async {
    check();
    lease(owner, epoch);
    final result = server.values[owner] ?? const PersonalSyncSnapshot(0, {});
    if (fetchGate != null) await fetchGate!.future;
    return PersonalSyncSnapshot(result.version, copy(result.value));
  }

  @override
  Future<void> put(
    String owner,
    int epoch,
    PersonalSyncSnapshot snapshot,
  ) async {
    check();
    if (putGate != null) await putGate!.future;
    final hook = beforePut;
    beforePut = null;
    if (hook != null) await hook();
    lease(owner, epoch);
    if ((server.values[owner]?.version ?? 0) != snapshot.version) {
      throw PersonalSyncConflict();
    }
    puts++;
    server.values[owner] = PersonalSyncSnapshot(
      snapshot.version + 1,
      copy(snapshot.value),
    );
    if (losePutResponse) {
      losePutResponse = false;
      throw StateError('lost response');
    }
  }

  @override
  void dispose() {}
}

Future<void> settle(PersonalSyncController controller) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
    if (!controller.syncing) return;
  }
  throw StateError('sync did not finish');
}

void main() {
  test('fresh login automatically syncs without a settings action', () async {
    final store = MemoryPersonalStore(MemoryPersonalServer());
    final data = MemoryPersonalData()..values['a'] = {'name:1': 'Local'};
    final sync = PersonalSyncController(local: data, store: store);
    await sync.bind(' A ');
    await settle(sync);
    expect(sync.enabled, isTrue);
    expect(store.server.values['a']!.value, {'name:1': 'Local'});
    expect(store.local['a']!['policy'], 'always-on.v1');
    await sync.bind(null);
    final calls = store.networkCalls;
    await sync.synchronize();
    expect(store.networkCalls, calls);
    expect(store.server.values['a']!.value, {'name:1': 'Local'});
    sync.dispose();
  });

  for (final pending in [false, true]) {
    test(
      'legacy off/pending=$pending retires deletion before networking and restart',
      () async {
        final server = MemoryPersonalServer();
        final store = MemoryPersonalStore(server)..offline = true;
        store.local['a'] = {
          'schema': 1,
          'epoch': 4,
          'enabled': false,
          'deletionPending': pending,
          'deletionNeedsConfirmation': pending,
          'base': {'name:1': 'Local'},
          'journal': {
            'before': {'name:1': 'Local'},
            'target': <String, dynamic>{},
          },
        };
        server.controls['a'] = const PersonalSyncControl(false, 5);
        final data = MemoryPersonalData()..values['a'] = {'name:1': 'Local'};
        var sync = PersonalSyncController(local: data, store: store);
        await sync.bind('a');
        await settle(sync);
        expect(sync.enabled, isTrue);
        expect(sync.error, isNotNull);
        expect(store.local['a']!['schema'], 2);
        expect(store.local['a']!.containsKey('deletionPending'), isFalse);
        expect(store.local['a']!['journal'], isNull);
        expect(store.local['a']!['base'], isEmpty);
        sync.dispose();
        store.offline = false;
        sync = PersonalSyncController(local: data, store: store);
        await sync.bind('a');
        await settle(sync);
        expect(data.values['a'], {'name:1': 'Local'});
        expect(server.values['a']!.value, data.values['a']);
        expect(sync.error, isNull);
        sync.dispose();
      },
    );
  }

  test(
    'normal scope1 upgrade keeps baseline so remote deletion does not resurrect',
    () async {
      final store = MemoryPersonalStore(MemoryPersonalServer());
      store.local['a'] = {
        'schema': 1,
        'epoch': 1,
        'enabled': true,
        'base': {'name:1': 'Deleted elsewhere'},
        'journal': null,
      };
      store.server.controls['a'] = const PersonalSyncControl(true, 2);
      store.server.values['a'] = const PersonalSyncSnapshot(3, {});
      final data = MemoryPersonalData()
        ..values['a'] = {'name:1': 'Deleted elsewhere'};
      final sync = PersonalSyncController(local: data, store: store);
      await sync.bind('a');
      await settle(sync);
      expect(data.values['a'], isEmpty);
      expect(store.puts, 0);
      sync.dispose();
    },
  );

  test(
    'legacy course transport remains retired during automatic sync',
    () async {
      final legacy = MemoryCourseStore();
      legacy.local['a'] = {
        'value': CourseDisplayPreferences(names: {2: 'Old'}).toJson(),
        'pending': {'name:2': 'Old'},
        'accepted': true,
      };
      final courses = CourseDisplayPreferencesController(store: legacy);
      await courses.bind('a');
      await courses.saveDraft(
        courses.value.apply({'name:1': 'New'}),
        courses.value,
      );
      await courses.synchronize();
      expect(legacy.writes, 0);
      expect(courses.value.names, {1: 'New', 2: 'Old'});
      courses.dispose();
    },
  );

  test(
    'two signed-in devices automatically merge course and schedule changes',
    () async {
      final server = MemoryPersonalServer();
      final a = MemoryPersonalData()..values['u'] = {'name:1': 'Math'};
      final b = MemoryPersonalData();
      final ca = PersonalSyncController(
        local: a,
        store: MemoryPersonalStore(server),
      );
      final cb = PersonalSyncController(
        local: b,
        store: MemoryPersonalStore(server),
      );
      await ca.bind('u');
      await settle(ca);
      await cb.bind('u');
      await settle(cb);
      expect(b.values['u'], {'name:1': 'Math'});
      final entry = TaCourseEntry(
        repeatType: TaCourseRepeatType.weekly,
        id: 'ta-a',
        title: 'TA',
        location: 'T1',
        weekday: 1,
        startMinutes: 540,
        endMinutes: 590,
        activeWeekStarts: [DateTime(2026, 10, 26)],
        kind: FixedScheduleKind.ta,
        courseKey: 'key',
        courseCode: 'COMP',
        semesterId: 'semester',
      );
      a.values['u']!['entry:ta-a'] = encodeSyncEntry(entry);
      b.values['u']!['hidden:2'] = true;
      await ca.synchronize();
      await cb.synchronize();
      await ca.synchronize();
      expect(a.values['u'], b.values['u']);
      expect(syncEntries(a.values['u']!).single.activeWeekStarts, [
        DateTime(2026, 10, 26),
      ]);
      ca.dispose();
      cb.dispose();
    },
  );

  test(
    'remote delete propagates, local offline unrelated edit does not resurrect',
    () async {
      final store = MemoryPersonalStore(MemoryPersonalServer());
      final local = MemoryPersonalData()
        ..values['u'] = {'name:1': 'A', 'name:2': 'B'};
      final c = PersonalSyncController(local: local, store: store);
      await c.bind('u');
      await settle(c);
      store.server.values['u'] = const PersonalSyncSnapshot(2, {'name:2': 'B'});
      local.values['u']!['name:3'] = 'C';
      await c.synchronize();
      expect(local.values['u'], {'name:2': 'B', 'name:3': 'C'});
      local.values['u']!.remove('name:2');
      await c.synchronize();
      expect(store.server.values['u']!.value, {'name:3': 'C'});
      c.dispose();
    },
  );

  test(
    'version conflict and lost receipt preserve independent fields',
    () async {
      final store = MemoryPersonalStore(MemoryPersonalServer());
      final local = MemoryPersonalData();
      final c = PersonalSyncController(local: local, store: store);
      await c.bind('u');
      await settle(c);
      local.values['u'] = {'name:1': 'A'};
      store.beforePut = () async {
        store.server.values['u'] = const PersonalSyncSnapshot(1, {
          'hidden:2': true,
        });
        local.values['u']!['name:3'] = 'During request';
      };
      store.losePutResponse = true;
      await c.synchronize();
      expect(c.error, isNotNull);
      await c.synchronize();
      expect(store.server.values['u']!.value, {
        'name:1': 'A',
        'hidden:2': true,
        'name:3': 'During request',
      });
      c.dispose();
    },
  );

  test(
    'durable journal recovers local apply failure without reversing remote deletion',
    () async {
      final store = MemoryPersonalStore(MemoryPersonalServer());
      final local = MemoryPersonalData()..values['u'] = {'name:1': 'A'};
      var c = PersonalSyncController(local: local, store: store);
      await c.bind('u');
      await settle(c);
      store.server.values['u'] = const PersonalSyncSnapshot(2, {
        'hidden:2': true,
      });
      local.failApply = true;
      await c.synchronize();
      c.dispose();
      expect(store.local['u']!['journal'], isNotNull);
      local.failApply = false;
      c = PersonalSyncController(local: local, store: store);
      await c.bind('u');
      await settle(c);
      expect(local.values['u'], {'hidden:2': true});
      expect(store.local['u']!['journal'], isNull);
      c.dispose();
    },
  );

  test(
    'late fetch after account change cannot apply previous account data',
    () async {
      final store = MemoryPersonalStore(MemoryPersonalServer());
      final local = MemoryPersonalData()..values['u'] = {'name:1': 'A'};
      final c = PersonalSyncController(local: local, store: store);
      await c.bind('u');
      await settle(c);
      store.fetchGate = Completer<void>();
      final flight = c.synchronize();
      await Future<void>.delayed(Duration.zero);
      await c.bind('other');
      store.fetchGate!.complete();
      await flight;
      expect(c.owner, 'other');
      await settle(c);
      expect(c.enabled, isTrue);
      expect(local.values['other'], isEmpty);
      c.dispose();
    },
  );

  test(
    'failed durable storage prevents uploads but sync remains automatically enabled',
    () async {
      final store = MemoryPersonalStore(MemoryPersonalServer())
        ..failSave = true;
      final local = MemoryPersonalData()..values['u'] = {'name:1': 'A'};
      final c = PersonalSyncController(local: local, store: store);
      await c.bind('u');
      await settle(c);
      expect(c.enabled, isTrue);
      expect(store.networkCalls, 0);
      expect(store.puts, 0);
      expect(c.error, isNotNull);
      c.dispose();
    },
  );

  test(
    'strict local wire rejects unknown fields and partial-apply recovery keeps edits',
    () {
      expect(
        () => validatePersonalData({'password': 'not-real'}),
        throwsFormatException,
      );
      expect(
        recoverPersonalData(
          {'name:1': 'A', 'name:2': 'B'},
          {'hidden:3': true, 'name:2': 'edited'},
          {'hidden:3': true, 'name:2': 'B'},
        ),
        {'hidden:3': true, 'name:2': 'edited'},
      );
    },
  );
}
