import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/services/ta_course_repository.dart';
import 'package:bnbu_me/models/personal_sync_data.dart';

void main() {
  test(
    'sync shares mutation queue and keeps local edits and monotonic revisions',
    () async {
      final repository = TaCourseRepository(store: _MemoryTaCourseStore());
      final created = await repository.addEntry(
        'fixture',
        _entry(id: 'a'),
        expectedRevision: 0,
      );
      final before = {'entry:a': encodeSyncEntry(created.entries.single)};
      final edited = await repository.updateEntry(
        'fixture',
        created.entries.single.copyWith(title: 'Local edit'),
        expectedRevision: 1,
      );
      final target = {
        'entry:a': before['entry:a'],
        'entry:b': encodeSyncEntry(
          _entry(id: 'b').copyWith(activeWeekStarts: [DateTime(2026, 10, 26)]),
        ),
      };
      final merged = await repository.applySynchronized(
        'fixture',
        before,
        target,
        () => true,
      );
      expect(merged.revision, edited.revision + 1);
      expect(merged.entries.firstWhere((e) => e.id == 'a').title, 'Local edit');
      expect(
        merged.entries.firstWhere((e) => e.id == 'a').revision,
        edited.entries.single.revision,
      );
      expect(merged.entries.firstWhere((e) => e.id == 'b').activeWeekStarts, [
        DateTime(2026, 10, 26),
      ]);
      final now = {
        for (final e in merged.entries) 'entry:${e.id}': encodeSyncEntry(e),
      };
      final repeated = await repository.applySynchronized(
        'fixture',
        now,
        now,
        () => true,
      );
      expect(repeated.revision, merged.revision);
      await expectLater(
        repository.applySynchronized('fixture', now, {}, () => false),
        throwsStateError,
      );
      expect((await repository.load('fixture')).entries, hasLength(2));
      expect((await repository.load('other')).entries, isEmpty);
    },
  );
  test(
    'week-only edits advance revision, persist and detect stale imports',
    () async {
      final repository = TaCourseRepository(store: _MemoryTaCourseStore());
      final original = _entry(
        id: 'weekly',
      ).copyWith(activeWeekStarts: [DateTime(2026, 10, 26)]);
      final created = await repository.addEntry(
        'student01',
        original,
        expectedRevision: 0,
      );
      final diff = repository.previewImport(created, [
        created.entries.single.copyWith(
          activeWeekStarts: [DateTime(2027, 1, 4)],
        ),
      ]);
      expect(diff.updates, hasLength(1));
      final updated = await repository.updateEntry(
        'student01',
        original.copyWith(activeWeekStarts: []),
        expectedRevision: 1,
      );
      expect(updated.revision, 2);
      final loaded = await repository.load('student01');
      expect(loaded.entries.single.activeWeekStarts, isEmpty);
      expect(
        loaded.entries.single.appliesToWeek(DateTime(2026, 10, 26)),
        isFalse,
      );
      await expectLater(
        repository.applyImportDiff('student01', diff),
        throwsA(isA<TaCourseConflictException>()),
      );
      expect((await repository.load('student02')).entries, isEmpty);
    },
  );
  test('uses hashed owner keys and isolates accounts', () async {
    final store = _MemoryTaCourseStore();
    final repository = TaCourseRepository(store: store);

    await repository.addEntry(
      'Student01',
      _entry(id: 'shared', title: 'A'),
      expectedRevision: 0,
    );
    await repository.addEntry(
      'student02',
      _entry(id: 'shared', title: 'B'),
      expectedRevision: 0,
    );

    final first = await repository.load('student01');
    final second = await repository.load('student02');

    expect(first.entries.single.title, 'A');
    expect(second.entries.single.title, 'B');
    expect(store.keys.any((key) => key.contains('student01')), isFalse);
    expect(store.keys.any((key) => key.contains('Student01')), isFalse);
    expect(store.keys.any((key) => key.contains('student02')), isFalse);
    expect(
      store.keys,
      contains(TaCourseRepository.storageKeyForUsername('student01')),
    );
  });

  test('serializes mutations', () async {
    final store = _MemoryTaCourseStore(delay: const Duration(milliseconds: 1));
    final repository = TaCourseRepository(store: store);

    await Future.wait([
      repository.addEntry('student01', _entry(id: 'a'), expectedRevision: 0),
      repository.addEntry('student01', _entry(id: 'b'), expectedRevision: 1),
      repository.updateEntry(
        'student01',
        _entry(id: 'a', title: 'updated').copyWith(revision: 1),
        expectedRevision: 1,
      ),
    ]);

    final state = await repository.load('student01');

    expect(store.maxActiveWrites, 1);
    expect(state.revision, 3);
    expect(state.entries, hasLength(2));
    expect(
      state.entries.firstWhere((entry) => entry.id == 'a').title,
      'updated',
    );
  });

  test('keeps stable IDs and monotonic revisions', () async {
    final repository = TaCourseRepository(store: _MemoryTaCourseStore());
    final created = await repository.addEntry(
      'student01',
      _entry(id: 'stable-id'),
      expectedRevision: 0,
    );
    final updated = await repository.updateEntry(
      'student01',
      created.entries.single.copyWith(title: 'updated'),
      expectedRevision: created.entries.single.revision,
    );
    final deleted = await repository.deleteEntry(
      'student01',
      'stable-id',
      expectedRevision: updated.entries.single.revision,
    );

    expect(created.entries.single.id, 'stable-id');
    expect(created.revision, 1);
    expect(created.entries.single.revision, 1);
    expect(updated.revision, 2);
    expect(updated.entries.single.id, 'stable-id');
    expect(updated.entries.single.revision, 2);
    expect(deleted.revision, 3);
    expect(deleted.entries, isEmpty);
  });

  test('stableIdFromJson is deterministic for legacy entries without IDs', () {
    final legacy = <String, dynamic>{
      'title': 'Workshop',
      'location': 'B201',
      'weekday': 2,
      'startMinutes': 600,
      'endMinutes': 650,
      'repeatType': 'weekly',
    };

    final first = TaCourseEntry.fromJson(legacy);
    final second = TaCourseEntry.fromJson(legacy);

    expect(first.id, second.id);
    expect(first.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('surfaces storage failures', () async {
    final repository = TaCourseRepository(
      store: _MemoryTaCourseStore(failSetString: true),
    );

    await expectLater(
      repository.addEntry('student01', _entry(), expectedRevision: 0),
      throwsA(isA<TaCourseStorageException>()),
    );
  });

  test('returns typed conflicts for stale revisions', () async {
    final repository = TaCourseRepository(store: _MemoryTaCourseStore());
    final state = await repository.addEntry(
      'student01',
      _entry(id: 'a'),
      expectedRevision: 0,
    );

    await expectLater(
      repository.updateEntry(
        'student01',
        state.entries.single.copyWith(title: 'late'),
        expectedRevision: 0,
      ),
      throwsA(
        isA<TaCourseConflictException>()
            .having(
              (error) => error.type,
              'type',
              TaCourseConflictType.entryRevisionMismatch,
            )
            .having((error) => error.actualRevision, 'actualRevision', 1),
      ),
    );
  });

  test('computes import diff and applies with revision checks', () async {
    final repository = TaCourseRepository(store: _MemoryTaCourseStore());
    final first = await repository.addEntry(
      'student01',
      _entry(id: 'keep', title: 'old'),
      expectedRevision: 0,
    );
    final second = await repository.addEntry(
      'student01',
      _entry(id: 'delete', title: 'delete'),
      expectedRevision: first.revision,
    );
    final current = await repository.load('student01');

    final diff = repository.previewImport(current, [
      current.entries
          .firstWhere((entry) => entry.id == 'keep')
          .copyWith(title: 'new'),
      _entry(id: 'add', title: 'add'),
    ]);

    expect(diff.additions.map((entry) => entry.id), ['add']);
    expect(diff.updates.map((update) => update.imported.id), ['keep']);
    expect(diff.deletions.map((deletion) => deletion.current.id), ['delete']);
    expect(diff.conflicts, isEmpty);

    final applied = await repository.applyImportDiff('student01', diff);

    expect(applied.revision, second.revision + 1);
    expect(
      applied.entries.map((entry) => entry.id),
      containsAll(['keep', 'add']),
    );
    expect(applied.entries.map((entry) => entry.id), isNot(contains('delete')));
    expect(
      applied.entries.firstWhere((entry) => entry.id == 'keep').title,
      'new',
    );
  });

  test('import apply fails if state changes after preview', () async {
    final repository = TaCourseRepository(store: _MemoryTaCourseStore());
    await repository.addEntry(
      'student01',
      _entry(id: 'a'),
      expectedRevision: 0,
    );
    final current = await repository.load('student01');
    final diff = repository.previewImport(current, [
      current.entries.single.copyWith(title: 'imported'),
    ]);
    await repository.updateEntry(
      'student01',
      current.entries.single.copyWith(title: 'meanwhile'),
      expectedRevision: current.entries.single.revision,
    );

    await expectLater(
      repository.applyImportDiff('student01', diff),
      throwsA(
        isA<TaCourseConflictException>().having(
          (error) => error.type,
          'type',
          TaCourseConflictType.collectionRevisionMismatch,
        ),
      ),
    );
  });

  test('import diff reports revision conflicts without overwriting', () async {
    final repository = TaCourseRepository(store: _MemoryTaCourseStore());
    final state = await repository.addEntry(
      'student01',
      _entry(id: 'a'),
      expectedRevision: 0,
    );

    final diff = repository.previewImport(state, [
      state.entries.single.copyWith(title: 'new', revision: 0),
    ]);

    expect(diff.conflicts, hasLength(1));
    expect(
      diff.conflicts.single.reason,
      TaCourseImportConflictReason.revisionMismatch,
    );
    await expectLater(
      repository.applyImportDiff('student01', diff),
      throwsA(
        isA<TaCourseConflictException>().having(
          (error) => error.type,
          'type',
          TaCourseConflictType.importHasConflicts,
        ),
      ),
    );
    expect((await repository.load('student01')).entries.single.title, 'Course');
  });

  test(
    'migrates only scoped legacy keys and quarantines unscoped legacy data',
    () async {
      final store = _MemoryTaCourseStore();
      final repository = TaCourseRepository(store: store);
      final legacyKey = TaCourseRepository.legacyV2KeyForUsername('student01');
      await store.setString(
        legacyKey,
        jsonEncode([_entry(id: 'legacy', title: 'legacy').toJson()]),
      );
      await store.setString(
        'schedule.ta_courses',
        jsonEncode([_entry(id: 'unsafe', title: 'unsafe').toJson()]),
      );

      final migrated = await repository.load('student01');
      final other = await repository.load('student02');

      expect(migrated.entries.single.id, 'legacy');
      expect(other.entries, isEmpty);
      expect(store.keys, isNot(contains(legacyKey)));
      expect(store.keys, isNot(contains('schedule.ta_courses')));
      expect(store.keys, contains('bnbu.ta_courses.legacy_unscoped.v1'));
    },
  );
}

TaCourseEntry _entry({
  String id = 'course',
  String title = 'Course',
  int revision = 0,
}) {
  return TaCourseEntry(
    id: id,
    title: title,
    location: 'B201',
    weekday: DateTime.monday,
    startMinutes: 9 * 60,
    endMinutes: 9 * 60 + 50,
    repeatType: TaCourseRepeatType.weekly,
    revision: revision,
  );
}

class _MemoryTaCourseStore implements TaCoursePreferencesStore {
  _MemoryTaCourseStore({
    this.failSetString = false,
    this.delay = Duration.zero,
  });

  final bool failSetString;
  final Duration delay;
  final Map<String, String> _values = {};
  int activeWrites = 0;
  int maxActiveWrites = 0;

  Iterable<String> get keys => _values.keys;

  @override
  Future<String?> getString(String key) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return _values[key];
  }

  @override
  Future<bool> setString(String key, String value) async {
    activeWrites += 1;
    maxActiveWrites = activeWrites > maxActiveWrites
        ? activeWrites
        : maxActiveWrites;
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (failSetString) {
        return false;
      }
      _values[key] = value;
      return true;
    } finally {
      activeWrites -= 1;
    }
  }

  @override
  Future<bool> remove(String key) async {
    activeWrites += 1;
    maxActiveWrites = activeWrites > maxActiveWrites
        ? activeWrites
        : maxActiveWrites;
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      _values.remove(key);
      return true;
    } finally {
      activeWrites -= 1;
    }
  }
}
