import 'dart:convert';

import 'course_summary.dart';

/// Presentation only. Never mutate Moodle course identities or enrolments.
class CourseDisplayPreferences {
  /// Unicode code points, matching the server's Python string length.
  static const maxNameLength = 150;

  static bool isValidName(String name) =>
      name.trim().isNotEmpty &&
      name.runes.length <= maxNameLength &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name);

  CourseDisplayPreferences({
    Map<int, String> names = const {},
    Set<int> hidden = const {},
    List<int> order = const [],
  }) : names = Map.unmodifiable(names),
       hidden = Set.unmodifiable(hidden),
       order = List.unmodifiable(order);

  final Map<int, String> names;
  final Set<int> hidden;
  final List<int> order;

  String label(CourseSummary course, {bool short = false}) =>
      names[course.id] ??
      (short && course.shortName.isNotEmpty
          ? course.shortName
          : course.fullName);

  List<CourseSummary> arrange(
    List<CourseSummary> courses, {
    bool includeHidden = false,
  }) {
    final byId = {for (final course in courses) course.id: course};
    return [
      for (final id in {...order, ...courses.map((course) => course.id)})
        if (byId.containsKey(id) && (includeHidden || !hidden.contains(id)))
          byId[id]!,
    ];
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'names': {for (final entry in names.entries) '${entry.key}': entry.value},
    'hidden': hidden.toList(),
    'order': order,
  };

  factory CourseDisplayPreferences.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['schema'] != 1 ||
        raw['names'] is! Map ||
        raw['hidden'] is! List ||
        raw['order'] is! List) {
      throw const FormatException('Unsupported course preferences');
    }
    List<int> ids(Object? value) {
      final list = value as List;
      if (list.length > 500 || list.any((id) => id is! int || id <= 0)) {
        throw const FormatException('Invalid course identities');
      }
      return list.cast<int>().toSet().toList();
    }

    final names = <int, String>{};
    final rawNames = raw['names'] as Map;
    if (rawNames.length > 500) throw const FormatException('Too many courses');
    for (final entry in rawNames.entries) {
      final id = int.tryParse('${entry.key}');
      final name = entry.value;
      if (id == null || id <= 0 || name is! String || !isValidName(name)) {
        throw const FormatException('Invalid display name');
      }
      names[id] = name;
    }
    final result = CourseDisplayPreferences(
      names: names,
      hidden: ids(raw['hidden']).toSet(),
      order: ids(raw['order']),
    );
    if (utf8.encode(jsonEncode(result.toJson())).length > 64 * 1024) {
      throw const FormatException('Course preferences exceed 64 KiB');
    }
    return result;
  }

  /// Only fields actually edited locally are replayed after a version conflict.
  CourseDisplayPreferences apply(Map<String, dynamic> changes) {
    final nextNames = {...names};
    final nextHidden = {...hidden};
    var nextOrder = order;
    for (final change in changes.entries) {
      if (change.key == 'order') {
        nextOrder = (change.value as List).cast<int>();
      } else if (change.key.startsWith('name:')) {
        final id = int.parse(change.key.substring(5));
        final value = change.value as String?;
        if (value == null) {
          nextNames.remove(id);
        } else {
          nextNames[id] = value;
        }
      } else if (change.key.startsWith('hidden:')) {
        final id = int.parse(change.key.substring(7));
        if (change.value == true) {
          nextHidden.add(id);
        } else {
          nextHidden.remove(id);
        }
      } else {
        throw const FormatException('Unknown preference field');
      }
    }
    return CourseDisplayPreferences.fromJson(
      CourseDisplayPreferences(
        names: nextNames,
        hidden: nextHidden,
        order: nextOrder,
      ).toJson(),
    );
  }

  Map<String, dynamic> changesFrom(CourseDisplayPreferences base) => {
    for (final id in {...base.names.keys, ...names.keys})
      if (names[id] != base.names[id]) 'name:$id': names[id],
    for (final id in {...base.hidden, ...hidden})
      if (hidden.contains(id) != base.hidden.contains(id))
        'hidden:$id': hidden.contains(id),
    if (jsonEncode(order) != jsonEncode(base.order)) 'order': order,
  };
}
