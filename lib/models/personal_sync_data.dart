import 'dart:convert';

import 'account_habit.dart';
import 'course_display_preferences.dart';
import 'ta_course_entry.dart';

typedef PersonalSyncData = Map<String, dynamic>;
bool sameSyncData(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && sameSyncData(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => sameSyncData(a[i], b[i]));
  }
  return a == b;
}

/// Three-way merge: only locally changed fields/entries override remote values.
/// A missing key is a deletion, never an instruction to restore the old value.
PersonalSyncData mergePersonalData(
  PersonalSyncData base,
  PersonalSyncData local,
  PersonalSyncData remote,
) {
  final result = {...remote};
  for (final key in {...base.keys, ...local.keys}) {
    if (sameSyncData(base[key], local[key])) continue;
    if (key.startsWith('habit:') &&
        local[key] is Map &&
        local[key]['source'] == 'legacy' &&
        remote.containsKey(key)) {
      continue;
    }
    if ((key == 'habit:mail.radar.rules' || key == 'mail.radar.rules') &&
        local[key] is Map &&
        remote[key] is Map) {
      result[key] = mergeRadarRules(base[key], local[key], remote[key]);
    } else if (local.containsKey(key)) {
      result[key] = local[key];
    } else {
      result.remove(key);
    }
  }
  return result;
}

Map<String, dynamic> mergeRadarRules(Object? base, Map local, Map remote) {
  Map<String, dynamic> index(Object? record) => {
    if (record is Map && record['value'] is List)
      for (final rule in record['value'] as List)
        (rule as Map)['sender'] as String: rule,
  };
  final merged = mergePersonalData(index(base), index(local), index(remote));
  final keys = merged.keys.toList()..sort();
  return {
    'value': [for (final key in keys) merged[key]],
    'source': 'explicit',
  };
}

/// Crash recovery can encounter a partially applied target; those fields are
/// already reconciled, not new local edits. Genuine edits during I/O survive.
PersonalSyncData recoverPersonalData(
  PersonalSyncData before,
  PersonalSyncData current,
  PersonalSyncData target,
) {
  final result = {...target};
  for (final key in {...before.keys, ...current.keys, ...target.keys}) {
    if (sameSyncData(current[key], before[key]) ||
        sameSyncData(current[key], target[key])) {
      continue;
    }
    if ((key == 'habit:mail.radar.rules' || key == 'mail.radar.rules') &&
        current[key] is Map &&
        target[key] is Map) {
      result[key] = mergeRadarRules(before[key], current[key], target[key]);
    } else if (current.containsKey(key)) {
      result[key] = current[key];
    } else {
      result.remove(key);
    }
  }
  return result;
}

PersonalSyncData encodePersonalData(
  CourseDisplayPreferences courses,
  List<TaCourseEntry> entries,
) => {
  for (final item in courses.names.entries) 'name:${item.key}': item.value,
  for (final id in courses.hidden) 'hidden:$id': true,
  if (courses.order.isNotEmpty) 'order': courses.order,
  for (final entry in entries) 'entry:${entry.id}': encodeSyncEntry(entry),
};

Map<String, dynamic> encodeSyncEntry(TaCourseEntry entry) {
  final value = entry.toJson()..remove('revision');
  value['weekStart'] = entry.weekStart == null
      ? null
      : TaCourseEntry.weekDateKey(entry.weekStart!);
  return value;
}

CourseDisplayPreferences syncCourses(PersonalSyncData data) =>
    CourseDisplayPreferences().apply({
      for (final entry in data.entries)
        if (entry.key.startsWith('name:') ||
            entry.key.startsWith('hidden:') ||
            entry.key == 'order')
          entry.key: entry.value,
    });

List<TaCourseEntry> syncEntries(PersonalSyncData data) => [
  for (final item in data.entries)
    if (item.key.startsWith('entry:'))
      TaCourseEntry.fromJson((item.value as Map).cast<String, dynamic>()),
];

PersonalSyncData validatePersonalData(Object? raw) {
  if (raw is! Map ||
      raw.length > 1541 ||
      utf8.encode(jsonEncode(raw)).length > 512 * 1024) {
    throw const FormatException('Invalid personal settings');
  }
  final data = raw.cast<String, dynamic>();
  final entries = syncEntries(data);
  if (entries.length > 500) throw const FormatException('Too many schedules');
  for (final entry in entries) {
    if (!data.containsKey('entry:${entry.id}')) {
      throw const FormatException('Invalid schedule identity');
    }
  }
  final habits = AccountHabit.validateSnapshot({
    for (final e in data.entries)
      if (e.key.startsWith('habit:')) e.key.substring(6): e.value,
  });
  final normalized = {
    ...encodePersonalData(syncCourses(data), entries),
    for (final e in habits.entries) 'habit:${e.key}': e.value,
  };
  if (!sameSyncData(data, normalized)) {
    throw const FormatException('Unknown personal settings fields');
  }
  return normalized;
}
