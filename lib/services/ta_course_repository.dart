import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ta_course_entry.dart';
import '../models/personal_sync_data.dart';

abstract interface class TaCoursePreferencesStore {
  Future<String?> getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class SharedPreferencesTaCourseStore implements TaCoursePreferencesStore {
  SharedPreferencesTaCourseStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;

  @override
  Future<String?> getString(String key) async {
    return (await _preferencesLoader()).getString(key);
  }

  @override
  Future<bool> setString(String key, String value) async {
    return (await _preferencesLoader()).setString(key, value);
  }

  @override
  Future<bool> remove(String key) async {
    return (await _preferencesLoader()).remove(key);
  }
}

class TaCourseRepository {
  TaCourseRepository({TaCoursePreferencesStore? store})
    : _store = store ?? SharedPreferencesTaCourseStore();

  static const String _storageKeyPrefix = 'bnbu.ta_courses.v1';
  static const String _legacyV2Prefix = 'schedule.ta_courses.v2';
  static const String _legacyUnscopedKey = 'schedule.ta_courses';
  static const String _legacyUnscopedQuarantineKey =
      'bnbu.ta_courses.legacy_unscoped.v1';

  final TaCoursePreferencesStore _store;
  Future<void> _mutationQueue = Future<void>.value();

  Future<TaCourseState> load(String username) {
    return _withMutation(() async {
      final normalized = normalizeUsername(username);
      final stored = await _loadStored(normalized);
      return TaCourseState(
        ownerHash: ownerHashForUsername(normalized),
        revision: stored.revision,
        entries: _sortedEntries(stored.entries),
      );
    });
  }

  Future<TaCourseState> applySynchronized(
    String username,
    PersonalSyncData before,
    PersonalSyncData target,
    bool Function() isCurrent,
  ) => _withMutation(() async {
    final normalized = normalizeUsername(username);
    final stored = await _loadStored(normalized);
    if (!isCurrent()) throw StateError('Sync lease expired');
    final current = <String, dynamic>{
      for (final entry in stored.entries)
        'entry:${entry.id}': encodeSyncEntry(entry),
    };
    final merged = recoverPersonalData(
      {
        for (final item in before.entries)
          if (item.key.startsWith('entry:')) item.key: item.value,
      },
      current,
      {
        for (final item in target.entries)
          if (item.key.startsWith('entry:')) item.key: item.value,
      },
    );
    if (sameSyncData(current, merged)) {
      return TaCourseState(
        ownerHash: ownerHashForUsername(normalized),
        revision: stored.revision,
        entries: _sortedEntries(stored.entries),
      );
    }
    final revision = stored.revision + 1;
    final old = {for (final entry in stored.entries) entry.id: entry};
    final entries = _sortedEntries(
      syncEntries(merged)
          .map(
            (entry) => old[entry.id]?.hasSameCourseFields(entry) == true
                ? old[entry.id]!
                : entry.copyWith(revision: revision),
          )
          .toList(),
    );
    if (!isCurrent()) throw StateError('Sync lease expired');
    await _saveStored(normalized, revision, entries);
    return TaCourseState(
      ownerHash: ownerHashForUsername(normalized),
      revision: revision,
      entries: entries,
    );
  });

  Future<TaCourseState> addEntry(
    String username,
    TaCourseEntry entry, {
    required int expectedRevision,
  }) {
    return _withMutation(() async {
      final normalized = normalizeUsername(username);
      final stored = await _loadStored(normalized);
      if (stored.revision != expectedRevision) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.collectionRevisionMismatch,
          expectedRevision: expectedRevision,
          actualRevision: stored.revision,
        );
      }
      if (stored.entries.any((item) => item.id == entry.id)) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.duplicateEntry,
          entryId: entry.id,
        );
      }
      final nextRevision = stored.revision + 1;
      final nextEntries = _sortedEntries([
        ...stored.entries,
        entry.copyWith(revision: nextRevision),
      ]);
      await _saveStored(normalized, nextRevision, nextEntries);
      return TaCourseState(
        ownerHash: ownerHashForUsername(normalized),
        revision: nextRevision,
        entries: nextEntries,
      );
    });
  }

  Future<TaCourseState> updateEntry(
    String username,
    TaCourseEntry entry, {
    required int expectedRevision,
  }) {
    return _withMutation(() async {
      final normalized = normalizeUsername(username);
      final stored = await _loadStored(normalized);
      final index = stored.entries.indexWhere((item) => item.id == entry.id);
      if (index < 0) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.missingEntry,
          entryId: entry.id,
          expectedRevision: expectedRevision,
        );
      }
      final current = stored.entries[index];
      if (current.revision != expectedRevision) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.entryRevisionMismatch,
          entryId: entry.id,
          expectedRevision: expectedRevision,
          actualRevision: current.revision,
        );
      }
      if (current.hasSameCourseFields(entry)) {
        return TaCourseState(
          ownerHash: ownerHashForUsername(normalized),
          revision: stored.revision,
          entries: _sortedEntries(stored.entries),
        );
      }
      final nextRevision = stored.revision + 1;
      final nextEntries = List<TaCourseEntry>.from(stored.entries);
      nextEntries[index] = entry.copyWith(revision: nextRevision);
      final sorted = _sortedEntries(nextEntries);
      await _saveStored(normalized, nextRevision, sorted);
      return TaCourseState(
        ownerHash: ownerHashForUsername(normalized),
        revision: nextRevision,
        entries: sorted,
      );
    });
  }

  Future<TaCourseState> deleteEntry(
    String username,
    String entryId, {
    required int expectedRevision,
  }) {
    return _withMutation(() async {
      final normalized = normalizeUsername(username);
      final stored = await _loadStored(normalized);
      final index = stored.entries.indexWhere((item) => item.id == entryId);
      if (index < 0) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.missingEntry,
          entryId: entryId,
          expectedRevision: expectedRevision,
        );
      }
      final current = stored.entries[index];
      if (current.revision != expectedRevision) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.entryRevisionMismatch,
          entryId: entryId,
          expectedRevision: expectedRevision,
          actualRevision: current.revision,
        );
      }
      final nextRevision = stored.revision + 1;
      final nextEntries = _sortedEntries(
        stored.entries.where((item) => item.id != entryId),
      );
      await _saveStored(normalized, nextRevision, nextEntries);
      return TaCourseState(
        ownerHash: ownerHashForUsername(normalized),
        revision: nextRevision,
        entries: nextEntries,
      );
    });
  }

  TaCourseImportDiff previewImport(
    TaCourseState current,
    List<TaCourseEntry> importedEntries,
  ) {
    final currentById = <String, TaCourseEntry>{
      for (final entry in current.entries) entry.id: entry,
    };
    final importedById = <String, TaCourseEntry>{};
    final additions = <TaCourseEntry>[];
    final updates = <TaCourseImportUpdate>[];
    final conflicts = <TaCourseImportConflict>[];

    for (final imported in importedEntries) {
      final duplicate = importedById[imported.id];
      if (duplicate != null) {
        conflicts.add(
          TaCourseImportConflict(
            entryId: imported.id,
            imported: imported,
            current: duplicate,
            reason: TaCourseImportConflictReason.duplicateImportedId,
          ),
        );
        continue;
      }
      importedById[imported.id] = imported;
      final currentEntry = currentById[imported.id];
      if (currentEntry == null) {
        additions.add(imported);
        continue;
      }
      if (currentEntry.hasSameCourseFields(imported)) {
        continue;
      }
      if (currentEntry.revision != imported.revision) {
        conflicts.add(
          TaCourseImportConflict(
            entryId: imported.id,
            imported: imported,
            current: currentEntry,
            reason: TaCourseImportConflictReason.revisionMismatch,
          ),
        );
        continue;
      }
      updates.add(
        TaCourseImportUpdate(
          current: currentEntry,
          imported: imported,
          expectedRevision: currentEntry.revision,
        ),
      );
    }

    final deletions = current.entries
        .where((entry) => !importedById.containsKey(entry.id))
        .map(
          (entry) => TaCourseImportDelete(
            current: entry,
            expectedRevision: entry.revision,
          ),
        )
        .toList(growable: false);

    return TaCourseImportDiff(
      ownerHash: current.ownerHash,
      baseRevision: current.revision,
      additions: _sortedEntries(additions),
      updates: updates,
      conflicts: conflicts,
      deletions: deletions,
    );
  }

  Future<TaCourseState> applyImportDiff(
    String username,
    TaCourseImportDiff diff,
  ) {
    return _withMutation(() async {
      if (diff.conflicts.isNotEmpty) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.importHasConflicts,
          entryId: diff.conflicts.first.entryId,
        );
      }
      final normalized = normalizeUsername(username);
      final stored = await _loadStored(normalized);
      final ownerHash = ownerHashForUsername(normalized);
      if (diff.ownerHash != ownerHash || stored.revision != diff.baseRevision) {
        throw TaCourseConflictException(
          type: TaCourseConflictType.collectionRevisionMismatch,
          expectedRevision: diff.baseRevision,
          actualRevision: stored.revision,
        );
      }

      final nextById = <String, TaCourseEntry>{
        for (final entry in stored.entries) entry.id: entry,
      };
      for (final addition in diff.additions) {
        if (nextById.containsKey(addition.id)) {
          throw TaCourseConflictException(
            type: TaCourseConflictType.duplicateEntry,
            entryId: addition.id,
          );
        }
      }
      for (final update in diff.updates) {
        final current = nextById[update.imported.id];
        if (current == null) {
          throw TaCourseConflictException(
            type: TaCourseConflictType.missingEntry,
            entryId: update.imported.id,
            expectedRevision: update.expectedRevision,
          );
        }
        if (current.revision != update.expectedRevision) {
          throw TaCourseConflictException(
            type: TaCourseConflictType.entryRevisionMismatch,
            entryId: update.imported.id,
            expectedRevision: update.expectedRevision,
            actualRevision: current.revision,
          );
        }
      }
      for (final deletion in diff.deletions) {
        final current = nextById[deletion.current.id];
        if (current == null) {
          throw TaCourseConflictException(
            type: TaCourseConflictType.missingEntry,
            entryId: deletion.current.id,
            expectedRevision: deletion.expectedRevision,
          );
        }
        if (current.revision != deletion.expectedRevision) {
          throw TaCourseConflictException(
            type: TaCourseConflictType.entryRevisionMismatch,
            entryId: deletion.current.id,
            expectedRevision: deletion.expectedRevision,
            actualRevision: current.revision,
          );
        }
      }

      if (!diff.hasChanges) {
        return TaCourseState(
          ownerHash: ownerHash,
          revision: stored.revision,
          entries: _sortedEntries(stored.entries),
        );
      }

      final nextRevision = stored.revision + 1;
      for (final deletion in diff.deletions) {
        nextById.remove(deletion.current.id);
      }
      for (final update in diff.updates) {
        nextById[update.imported.id] = update.imported.copyWith(
          revision: nextRevision,
        );
      }
      for (final addition in diff.additions) {
        nextById[addition.id] = addition.copyWith(revision: nextRevision);
      }
      final nextEntries = _sortedEntries(nextById.values);
      await _saveStored(normalized, nextRevision, nextEntries);
      return TaCourseState(
        ownerHash: ownerHash,
        revision: nextRevision,
        entries: nextEntries,
      );
    });
  }

  static String normalizeUsername(String username) =>
      username.trim().toLowerCase();

  static String ownerHashForUsername(String username) {
    return sha256.convert(utf8.encode(normalizeUsername(username))).toString();
  }

  static String storageKeyForUsername(String username) {
    return '$_storageKeyPrefix.${ownerHashForUsername(username)}';
  }

  static String legacyV2KeyForUsername(String username) {
    final normalized = normalizeUsername(username);
    return '$_legacyV2Prefix.${base64Url.encode(utf8.encode(normalized))}';
  }

  Future<_StoredTaCourses> _loadStored(String normalizedUsername) async {
    await _quarantineUnscopedLegacyIfNeeded();
    final key = storageKeyForUsername(normalizedUsername);
    final raw = await _store.getString(key);
    if (raw != null && raw.isNotEmpty) {
      await _removeLegacyV2IfNeeded(normalizedUsername);
      return _decodeStoredPayload(raw);
    }

    final legacyV2Key = legacyV2KeyForUsername(normalizedUsername);
    final legacyRaw = await _store.getString(legacyV2Key);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return const _StoredTaCourses(revision: 0, entries: []);
    }
    final migrated = _decodeStoredPayload(legacyRaw);
    await _saveStored(normalizedUsername, migrated.revision, migrated.entries);
    await _removeRequired(legacyV2Key);
    return migrated;
  }

  Future<void> _saveStored(
    String normalizedUsername,
    int revision,
    List<TaCourseEntry> entries,
  ) async {
    final payload = jsonEncode(<String, dynamic>{
      'version': entries.any((entry) => entry.activeWeekStarts != null) ? 3 : 2,
      'revision': revision,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    });
    final saved = await _store.setString(
      storageKeyForUsername(normalizedUsername),
      payload,
    );
    if (!saved) {
      throw const TaCourseStorageException('无法保存 TA 课配置。');
    }
  }

  _StoredTaCourses _decodeStoredPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final rawEntries = decoded is Map<String, dynamic>
          ? decoded['entries']
          : decoded;
      if (rawEntries is! List) {
        return const _StoredTaCourses(revision: 0, entries: []);
      }
      final entries = <TaCourseEntry>[];
      final seenIds = <String>{};
      for (final item in rawEntries.whereType<Map>()) {
        try {
          final entry = TaCourseEntry.fromJson(item.cast<String, dynamic>());
          if (seenIds.add(entry.id)) {
            entries.add(entry);
          }
        } on FormatException {
          // Keep the rest of a locally stored TA course list readable.
        }
      }
      final payloadRevision = decoded is Map<String, dynamic>
          ? (decoded['revision'] as num?)?.toInt() ?? 0
          : 0;
      final maxEntryRevision = entries.fold<int>(
        0,
        (current, entry) => max(current, entry.revision),
      );
      return _StoredTaCourses(
        revision: max(payloadRevision, maxEntryRevision),
        entries: _sortedEntries(entries),
      );
    } catch (_) {
      return const _StoredTaCourses(revision: 0, entries: []);
    }
  }

  Future<void> _quarantineUnscopedLegacyIfNeeded() async {
    final raw = await _store.getString(_legacyUnscopedKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final quarantined = await _store.getString(_legacyUnscopedQuarantineKey);
    if (quarantined == null || quarantined.isEmpty) {
      final saved = await _store.setString(_legacyUnscopedQuarantineKey, raw);
      if (!saved) {
        throw const TaCourseStorageException('无法保存旧版 TA 课配置迁移备份。');
      }
    }
    await _removeRequired(_legacyUnscopedKey);
  }

  Future<void> _removeLegacyV2IfNeeded(String normalizedUsername) async {
    final legacyV2Key = legacyV2KeyForUsername(normalizedUsername);
    final raw = await _store.getString(legacyV2Key);
    if (raw != null) {
      await _removeRequired(legacyV2Key);
    }
  }

  Future<void> _removeRequired(String key) async {
    final removed = await _store.remove(key);
    if (!removed) {
      throw const TaCourseStorageException('无法清理旧版 TA 课配置。');
    }
  }

  Future<T> _withMutation<T>(Future<T> Function() operation) async {
    final previous = _mutationQueue;
    final completer = Completer<void>();
    _mutationQueue = completer.future;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
    }
  }

  static List<TaCourseEntry> _sortedEntries(Iterable<TaCourseEntry> entries) {
    final sorted = List<TaCourseEntry>.from(entries);
    sorted.sort((left, right) {
      final leftRank = left.repeatType == TaCourseRepeatType.weekly ? 0 : 1;
      final rightRank = right.repeatType == TaCourseRepeatType.weekly ? 0 : 1;
      final repeatCompare = leftRank.compareTo(rightRank);
      if (repeatCompare != 0) {
        return repeatCompare;
      }
      final weekCompare = (left.weekStart?.millisecondsSinceEpoch ?? 0)
          .compareTo(right.weekStart?.millisecondsSinceEpoch ?? 0);
      if (weekCompare != 0) {
        return weekCompare;
      }
      final weekdayCompare = left.weekday.compareTo(right.weekday);
      if (weekdayCompare != 0) {
        return weekdayCompare;
      }
      final timeCompare = left.startMinutes.compareTo(right.startMinutes);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return left.id.compareTo(right.id);
    });
    return List<TaCourseEntry>.unmodifiable(sorted);
  }
}

class TaCourseState {
  const TaCourseState({
    required this.ownerHash,
    required this.revision,
    required this.entries,
  });

  final String ownerHash;
  final int revision;
  final List<TaCourseEntry> entries;
}

class TaCourseImportDiff {
  const TaCourseImportDiff({
    required this.ownerHash,
    required this.baseRevision,
    required this.additions,
    required this.updates,
    required this.conflicts,
    required this.deletions,
  });

  final String ownerHash;
  final int baseRevision;
  final List<TaCourseEntry> additions;
  final List<TaCourseImportUpdate> updates;
  final List<TaCourseImportConflict> conflicts;
  final List<TaCourseImportDelete> deletions;

  bool get hasChanges =>
      additions.isNotEmpty || updates.isNotEmpty || deletions.isNotEmpty;
}

class TaCourseImportUpdate {
  const TaCourseImportUpdate({
    required this.current,
    required this.imported,
    required this.expectedRevision,
  });

  final TaCourseEntry current;
  final TaCourseEntry imported;
  final int expectedRevision;
}

class TaCourseImportDelete {
  const TaCourseImportDelete({
    required this.current,
    required this.expectedRevision,
  });

  final TaCourseEntry current;
  final int expectedRevision;
}

class TaCourseImportConflict {
  const TaCourseImportConflict({
    required this.entryId,
    required this.imported,
    required this.current,
    required this.reason,
  });

  final String entryId;
  final TaCourseEntry imported;
  final TaCourseEntry current;
  final TaCourseImportConflictReason reason;
}

enum TaCourseImportConflictReason { revisionMismatch, duplicateImportedId }

enum TaCourseConflictType {
  collectionRevisionMismatch,
  entryRevisionMismatch,
  missingEntry,
  duplicateEntry,
  importHasConflicts,
}

class TaCourseConflictException implements Exception {
  const TaCourseConflictException({
    required this.type,
    this.entryId,
    this.expectedRevision,
    this.actualRevision,
  });

  final TaCourseConflictType type;
  final String? entryId;
  final int? expectedRevision;
  final int? actualRevision;

  @override
  String toString() {
    return 'TaCourseConflictException($type, entryId: $entryId, '
        'expectedRevision: $expectedRevision, actualRevision: $actualRevision)';
  }
}

class TaCourseStorageException implements Exception {
  const TaCourseStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _StoredTaCourses {
  const _StoredTaCourses({required this.revision, required this.entries});

  final int revision;
  final List<TaCourseEntry> entries;
}
