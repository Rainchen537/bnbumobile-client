import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/account_habit.dart';
import 'package:bnbu_me/models/personal_sync_data.dart';
import 'package:bnbu_me/services/sync/account_sync_storage.dart';
import 'package:bnbu_me/state/account_habits.dart';
import 'package:bnbu_me/state/personal_sync_controller.dart';
import 'personal_sync_test.dart'
    show MemoryPersonalServer, MemoryPersonalStore, settle;

class _Local implements PersonalSyncLocalData {
  _Local(this.habits);
  final AccountHabits habits;
  @override
  Future<PersonalSyncData> read(String owner) async {
    await habits.ensureSaved();
    return {for (final e in habits.snapshot.entries) 'habit:${e.key}': e.value};
  }

  @override
  Future<void> apply(
    String owner,
    PersonalSyncData before,
    PersonalSyncData target,
    bool Function() current,
  ) async {
    if (!current()) return;
    await habits.apply(
      {for (final e in before.entries) e.key.substring(6): e.value},
      {for (final e in target.entries) e.key.substring(6): e.value},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SecretKey key;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('bnbu-sync-test-');
    key = await AesGcm.with256bits().newSecretKey();
  });
  tearDown(() async => directory.delete(recursive: true));
  AccountSyncStorage storage(String device) => AccountSyncStorage(
    directory: () async => Directory('${directory.path}/$device'),
    key: () async => key,
  );

  test(
    'account habits survive restart, remain encrypted and isolate accounts',
    () async {
      final a = AccountHabits(storage: storage('a'));
      await a.bind('one');
      await a.set(
        'study.organization_prompt',
        'private synthetic study instruction',
      );
      await a.bind('two');
      expect(a.read<String?>('study.organization_prompt', null), isNull);
      final restarted = AccountHabits(storage: storage('a'));
      await restarted.bind('one');
      expect(
        restarted.read('study.organization_prompt', ''),
        'private synthetic study instruction',
      );
      for (final file
          in directory.listSync(recursive: true).whereType<File>()) {
        expect(
          utf8.decode(file.readAsBytesSync(), allowMalformed: true),
          isNot(contains('private synthetic')),
        );
      }
      a.dispose();
      restarted.dispose();
    },
  );
  test(
    'two devices converge independent habits; new defaults never overwrite choices',
    () async {
      final server = MemoryPersonalServer();
      final a = AccountHabits(storage: storage('a'));
      final b = AccountHabits(storage: storage('b'));
      await a.bind('one');
      await b.bind('one');
      final ca = PersonalSyncController(
        local: _Local(a),
        store: MemoryPersonalStore(server),
      );
      final cb = PersonalSyncController(
        local: _Local(b),
        store: MemoryPersonalStore(server),
      );
      await ca.bind('one');
      await settle(ca);
      await cb.bind('one');
      await settle(cb);
      await a.set('ispace.dashboard.date_filter', 'next30Days');
      await ca.synchronize();
      await cb.synchronize();
      expect(b.read('ispace.dashboard.date_filter', 'all'), 'next30Days');
      await a.set('ispace.dashboard.sort_mode', 'byCourses');
      await b.set('schedule.show_deadlines', false);
      await ca.synchronize();
      await cb.synchronize();
      await ca.synchronize();
      expect(a.read('schedule.show_deadlines', true), false);
      expect(b.read('ispace.dashboard.sort_mode', 'byDates'), 'byCourses');
      ca.dispose();
      cb.dispose();
      a.dispose();
      b.dispose();
    },
  );
  test(
    'legacy preferences migrate but cannot replace explicit remote values',
    () async {
      SharedPreferences.setMockInitialValues({
        'ispace.dashboard.sort_mode': 'byDates',
        'app.appearance.language_mode': 'english',
      });
      final a = AccountHabits(storage: storage('a'));
      await a.bind('one');
      expect(a.snapshot['app.appearance.language_mode'], {
        'value': 'english',
        'source': 'legacy',
      });
      final local = {
        'habit:ispace.dashboard.sort_mode':
            a.snapshot['ispace.dashboard.sort_mode'],
      };
      final remote = {
        'habit:ispace.dashboard.sort_mode': {
          'value': 'byCourses',
          'source': 'explicit',
        },
      };
      expect(mergePersonalData({}, local, remote), remote);
      await a.bind('two');
      expect(a.snapshot, isEmpty);
      a.dispose();
    },
  );
  test('a delayed write cannot move to another account', () async {
    final habits = AccountHabits(storage: storage('a'));
    await habits.bind('one');
    final lease = habits.lease;
    await habits.bind('two');
    await expectLater(
      habits.set('mail.unread_only', true, lease: lease),
      throwsStateError,
    );
    expect(habits.snapshot, isEmpty);
    habits.dispose();
  });
  test(
    'an explicit selection during account loading is saved after restore',
    () async {
      final store = _GatedStorage();
      final habits = AccountHabits(storage: store);
      final loading = habits.bind('one');
      final change = habits.set('mail.unread_only', true);
      store.gate.complete();
      await loading;
      await change;
      expect(habits.read('mail.unread_only', false), true);
      expect(store.saved!['values']['mail.unread_only']['source'], 'explicit');
      habits.dispose();
    },
  );
  test(
    'schema rejects unknown settings, credential fields and invalid policy',
    () {
      expect(
        () => AccountHabit.validate('password', 'secret'),
        throwsFormatException,
      );
      expect(
        () => AccountHabit.validate('course_reminders.lead_minutes', 0),
        throwsFormatException,
      );
      expect(
        () => validatePersonalData({
          'habit:mail.sort_order': {'value': 'invalid', 'source': 'explicit'},
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'corrupt local sync records cannot become an empty cloud overwrite',
    () async {
      final store = storage('a');
      await store.write('one', 'habits', {'values': {}});
      final file = directory.listSync(recursive: true).whereType<File>().single;
      await file.writeAsBytes([1, 2, 3], flush: true);
      final a = AccountHabits(storage: storage('a'));
      await a.bind('one');
      expect(a.ready, false);
      expect(a.error, isNotNull);
      await expectLater(a.ensureSaved(), throwsStateError);
      a.dispose();
    },
  );
}

class _GatedStorage extends AccountSyncStorage {
  final gate = Completer<void>();
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>?> read(String owner, String domain) async {
    await gate.future;
    return {'values': <String, dynamic>{}};
  }

  @override
  Future<void> write(
    String owner,
    String domain,
    Map<String, dynamic> value,
  ) async {
    saved = value;
  }
}
