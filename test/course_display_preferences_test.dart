import 'dart:async';
import 'dart:convert';

import 'package:bnbu_me/models/course_display_preferences.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/services/course_display_preferences_service.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:bnbu_me/state/course_display_preferences_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

CourseSummary fixtureCourse(int id) => CourseSummary(
  id: id,
  fullName: 'Course $id',
  shortName: 'C$id',
  categoryName: '',
  progress: null,
);

class MemoryCourseStore implements CourseDisplayPreferencesStore {
  MemoryCourseStore({Map<String, CourseDisplaySnapshot>? remote})
    : remote = remote ?? {};
  final Map<String, CourseDisplaySnapshot> remote;
  final local = <String, Map<String, dynamic>>{};
  bool offline = false;
  bool failLocal = false;
  bool loseWriteResponse = false;
  Future<void> Function()? beforePut;
  Completer<void>? readGate;
  Completer<void>? localGate;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> loadLocal(String owner) async => local[owner];
  @override
  Future<void> saveLocal(String owner, Map<String, dynamic> record) async {
    await localGate?.future;
    if (failLocal) throw StateError('local fixture failure');
    local[owner] = jsonDecode(jsonEncode(record)) as Map<String, dynamic>;
  }

  @override
  Future<CourseDisplaySnapshot> fetch(String owner) async {
    await readGate?.future;
    if (offline) throw StateError('offline fixture');
    return remote[owner] ??
        CourseDisplaySnapshot(0, CourseDisplayPreferences());
  }

  @override
  Future<void> put(String owner, CourseDisplaySnapshot snapshot) async {
    writes++;
    final callback = beforePut;
    beforePut = null;
    await callback?.call();
    if (offline) throw StateError('offline fixture');
    if ((remote[owner]?.version ?? 0) != snapshot.version) {
      throw CourseDisplayConflict();
    }
    remote[owner] = CourseDisplaySnapshot(snapshot.version + 1, snapshot.value);
    if (loseWriteResponse) {
      loseWriteResponse = false;
      throw StateError('lost response');
    }
  }

  @override
  void dispose() {}
}

Future<void> settleCourseSync(
  CourseDisplayPreferencesController controller,
) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
    if (!controller.syncing) return;
  }
  fail('Course sync did not settle');
}

void main() {
  test('display names accept 150 Unicode code points and reject 151', () {
    for (final letter in ['a', '课', '😀']) {
      final preferences = CourseDisplayPreferences(names: {1: letter * 150});
      expect(
        CourseDisplayPreferences.fromJson(preferences.toJson()).names,
        preferences.names,
      );
      expect(
        () => CourseDisplayPreferences.fromJson(
          CourseDisplayPreferences(names: {1: letter * 151}).toJson(),
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'presentation does not alter school courses, hide keeps data and new courses append',
    () {
      final courses = [fixtureCourse(1), fixtureCourse(2), fixtureCourse(3)];
      final preferences = CourseDisplayPreferences(
        names: {2: '我的名称'},
        hidden: {1},
        order: [2, 1],
      );
      expect(preferences.arrange(courses).map((c) => c.id), [2, 3]);
      expect(
        preferences.arrange(courses, includeHidden: true).map((c) => c.id),
        [2, 1, 3],
      );
      expect(preferences.label(courses[1]), '我的名称');
      expect(courses[1].fullName, 'Course 2');
      expect(
        preferences
            .apply({'name:2': null, 'hidden:1': false})
            .label(courses[1]),
        'Course 2',
      );
      expect(courses.length, 3);
    },
  );
  test('invalid, oversized and future schema snapshots fail closed', () {
    final valid = CourseDisplayPreferences().toJson();
    expect(
      () => CourseDisplayPreferences.fromJson({...valid, 'schema': 2}),
      throwsFormatException,
    );
    expect(
      () => CourseDisplayPreferences.fromJson({
        ...valid,
        'names': {'1': 'a' * 151},
      }),
      throwsFormatException,
    );
    expect(
      () => CourseDisplayPreferences.fromJson({
        ...valid,
        'hidden': [-1],
      }),
      throwsFormatException,
    );
    expect(
      () => CourseDisplayPreferences.fromJson({
        ...valid,
        'names': {'1': 'a\nb'},
      }),
      throwsFormatException,
    );
    expect(
      () => CourseDisplayPreferences.fromJson(
        CourseDisplayPreferences(
          names: {for (var i = 1; i <= 500; i++) i: '字' * 100},
        ).toJson(),
      ),
      throwsFormatException,
    );
  });
  test(
    'offline edits survive restart and merge with independent device changes',
    () async {
      final remote = <String, CourseDisplaySnapshot>{};
      final firstStore = MemoryCourseStore(remote: remote)..offline = true;
      final secondStore = MemoryCourseStore(remote: remote);
      final first = CourseDisplayPreferencesController(
        store: firstStore,
        syncAllowed: () => true,
      );
      await first.bind(' Student ');
      await settleCourseSync(first);
      await first.saveDraft(
        first.value.apply({
          'name:1': 'Math',
          'order': [2, 1],
        }),
        first.value,
      );
      await settleCourseSync(first);
      expect(first.hasPending, isTrue);
      expect(firstStore.writes, 0);
      first.dispose();
      final second = CourseDisplayPreferencesController(
        store: secondStore,
        syncAllowed: () => true,
      );
      await second.bind('student');
      await settleCourseSync(second);
      await second.saveDraft(
        second.value.apply({'hidden:2': true}),
        second.value,
      );
      await settleCourseSync(second);
      final restarted = CourseDisplayPreferencesController(
        syncAllowed: () => true,
        store: firstStore..offline = false,
      );
      await restarted.bind('student');
      await settleCourseSync(restarted);
      expect(remote['student']!.value.names, {1: 'Math'});
      expect(remote['student']!.value.hidden, {2});
      expect(remote['student']!.value.order, [2, 1]);
      expect(restarted.hasPending, isFalse);
      await second.synchronize();
      expect(second.value.names, {1: 'Math'});
      expect(second.value.hidden, {2});
      restarted.dispose();
      second.dispose();
    },
  );
  test(
    '409 re-reads remote; changes made during upload are retained',
    () async {
      final store = MemoryCourseStore();
      final controller = CourseDisplayPreferencesController(
        store: store,
        syncAllowed: () => true,
      );
      await controller.bind('a');
      await settleCourseSync(controller);
      store.beforePut = () async {
        store.remote['a'] = CourseDisplaySnapshot(
          1,
          CourseDisplayPreferences(hidden: {3}),
        );
        await controller.saveDraft(
          controller.value.apply({'name:2': 'B'}),
          controller.value,
        );
      };
      await controller.saveDraft(
        controller.value.apply({'name:1': 'A'}),
        controller.value,
      );
      await settleCourseSync(controller);
      expect(store.remote['a']!.value.names, {1: 'A', 2: 'B'});
      expect(store.remote['a']!.value.hidden, {3});
      expect(controller.hasPending, isFalse);
      controller.dispose();
    },
  );
  test(
    'lost upload response is replayed without losing another device field',
    () async {
      final store = MemoryCourseStore()..loseWriteResponse = true;
      final controller = CourseDisplayPreferencesController(
        store: store,
        syncAllowed: () => true,
      );
      await controller.bind('a');
      await settleCourseSync(controller);
      await controller.saveDraft(
        controller.value.apply({'name:1': 'A'}),
        controller.value,
      );
      await settleCourseSync(controller);
      expect(controller.hasPending, isTrue);
      store.remote['a'] = CourseDisplaySnapshot(
        2,
        store.remote['a']!.value.apply({'hidden:2': true}),
      );
      await controller.synchronize();
      expect(controller.hasPending, isFalse);
      expect(controller.value.names, {1: 'A'});
      expect(controller.value.hidden, {2});
      controller.dispose();
    },
  );
  test(
    'switching accounts rejects late reads and does not carry local edits',
    () async {
      final store = MemoryCourseStore()..readGate = Completer<void>();
      store.remote['a'] = CourseDisplaySnapshot(
        1,
        CourseDisplayPreferences(names: {1: 'A private alias'}),
      );
      final controller = CourseDisplayPreferencesController(
        store: store,
        syncAllowed: () => true,
      );
      await controller.bind('a');
      await controller.bind('b');
      store.readGate!.complete();
      await settleCourseSync(controller);
      expect(controller.owner, 'b');
      expect(controller.value.names, isEmpty);
      expect(store.writes, 0);
      await controller.bind(null);
      expect(controller.value.names, isEmpty);
      controller.dispose();
    },
  );
  test(
    'no dirty edits never writes; local failure keeps pending and retryable',
    () async {
      final store = MemoryCourseStore();
      final controller = CourseDisplayPreferencesController(
        store: store,
        syncAllowed: () => true,
      );
      await controller.bind('a');
      await settleCourseSync(controller);
      await controller.saveDraft(controller.value, controller.value);
      expect(store.writes, 0);
      store.failLocal = true;
      await expectLater(
        controller.saveDraft(
          controller.value.apply({'hidden:1': true}),
          controller.value,
        ),
        throwsStateError,
      );
      expect(controller.hasPending, isTrue);
      expect(controller.localSaveFailed, isTrue);
      expect(store.writes, 0);
      store.failLocal = false;
      await controller.synchronize();
      expect(controller.hasPending, isFalse);
      expect(controller.localSaveFailed, isFalse);
      controller.dispose();
    },
  );
  test(
    'retired course transport cannot bypass the unified consent protocol',
    () async {
      final seen = <http.Request>[];
      final store = RemoteCourseDisplayPreferencesStore(
        devices: _DeviceStore(),
        baseUrl: 'https://fixture.invalid',
        client: MockClient((r) async {
          seen.add(r);
          return http.Response('{}', 200);
        }),
      );
      await expectLater(store.fetch('a'), throwsStateError);
      await expectLater(
        store.put('a', CourseDisplaySnapshot(0, CourseDisplayPreferences())),
        throwsStateError,
      );
      expect(seen, isEmpty);
      store.dispose();
    },
  );
}

class _DeviceStore implements UsageSyncStore {
  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async =>
      const UsageSyncDeviceRecord(
        installationId: 'synthetic',
        deviceToken: 'dev_fixture',
      );
  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async =>
      throw StateError('Must not enrol');
}
