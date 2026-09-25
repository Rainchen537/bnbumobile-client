import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'timetable_data.dart';

enum FixedScheduleKind { schedule, ta }

enum TaCourseRepeatType { weekly, singleWeek }

class TaCourseEntry {
  const TaCourseEntry({
    required this.id,
    required this.title,
    required this.location,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    required this.repeatType,
    this.weekStart,
    this.activeWeekStarts,
    this.revision = 0,
    this.kind = FixedScheduleKind.schedule,
    this.courseKey = '',
    this.courseCode = '',
    this.semesterId = '',
  });

  final String id;
  final String title;
  final String location;
  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final TaCourseRepeatType repeatType;
  final DateTime? weekStart;

  /// Null preserves legacy unlimited recurrence; empty means paused.
  /// Calendar dates (Mondays), never device-time instants.
  final List<DateTime>? activeWeekStarts;
  final int revision;
  final FixedScheduleKind kind;
  final String courseKey;
  final String courseCode;
  final String semesterId;
  bool get isTa => kind == FixedScheduleKind.ta;
  String get kindLabel => isTa ? 'TA' : '日程';

  static String bindingKey(TimetableData timetable, TimetableCourse course) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode([
                timetable.selectedSemesterId,
                course.code,
                course.section,
                course.name,
              ]),
            ),
          )
          .toString();

  TimetableCourse? resolveCourse(TimetableData? timetable) {
    if (!isTa ||
        timetable == null ||
        semesterId != timetable.selectedSemesterId) {
      return null;
    }
    final matches = timetable.courses.where(
      (course) => bindingKey(timetable, course) == courseKey,
    );
    return matches.length == 1 ? matches.single : null;
  }

  bool isVisibleIn(TimetableData? timetable) =>
      !isTa || resolveCourse(timetable) != null;

  void validate() {
    final weeks = activeWeekStarts;
    if (weeks != null &&
        (weeks.length > 520 ||
            weeks.any(
              (week) =>
                  week.weekday != DateTime.monday ||
                  week.year < 1 ||
                  week.year > 9999 ||
                  week.hour != 0 ||
                  week.minute != 0 ||
                  week.second != 0 ||
                  week.millisecond != 0 ||
                  week.microsecond != 0,
            ))) {
      throw const FormatException('日程适用周无效');
    }
    if (weekday < 1 ||
        weekday > 7 ||
        startMinutes < 0 ||
        endMinutes > 1440 ||
        endMinutes <= startMinutes) {
      throw const FormatException('日程时间无效');
    }
    if (isTa &&
        (courseKey.isEmpty || courseCode.isEmpty || semesterId.isEmpty)) {
      throw const FormatException('TA 必须关联课程');
    }
    if (!isTa &&
        (courseKey.isNotEmpty ||
            courseCode.isNotEmpty ||
            semesterId.isNotEmpty)) {
      throw const FormatException('普通日程不能携带课程关联');
    }
  }

  String get displayTitle =>
      title.trim().isEmpty ? (isTa ? 'TA' : '日程') : title.trim();

  String get displayLocation => location.trim();

  String get timeRangeLabel =>
      '${formatMinutes(startMinutes)}-${formatMinutes(endMinutes)}';

  bool appliesToWeek(DateTime targetWeekStart) {
    if (repeatType == TaCourseRepeatType.weekly) {
      return activeWeekStarts == null ||
          activeWeekStarts!.any(
            (week) => _sameDate(week, normalizeWeekStart(targetWeekStart)),
          );
    }
    if (weekStart == null) {
      return false;
    }
    final normalizedTarget = normalizeWeekStart(targetWeekStart);
    final normalizedSelf = normalizeWeekStart(weekStart!);
    return normalizedTarget.year == normalizedSelf.year &&
        normalizedTarget.month == normalizedSelf.month &&
        normalizedTarget.day == normalizedSelf.day;
  }

  bool hasSameCourseFields(TaCourseEntry other) {
    return kind == other.kind &&
        courseKey == other.courseKey &&
        courseCode == other.courseCode &&
        semesterId == other.semesterId &&
        title == other.title &&
        location == other.location &&
        weekday == other.weekday &&
        startMinutes == other.startMinutes &&
        endMinutes == other.endMinutes &&
        repeatType == other.repeatType &&
        _sameDate(weekStart, other.weekStart) &&
        _sameWeeks(activeWeekStarts, other.activeWeekStarts);
  }

  TaCourseEntry copyWith({
    String? id,
    String? title,
    String? location,
    int? weekday,
    int? startMinutes,
    int? endMinutes,
    TaCourseRepeatType? repeatType,
    DateTime? weekStart,
    bool clearWeekStart = false,
    List<DateTime>? activeWeekStarts,
    bool clearActiveWeekStarts = false,
    int? revision,
    FixedScheduleKind? kind,
    String? courseKey,
    String? courseCode,
    String? semesterId,
  }) {
    return TaCourseEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      location: location ?? this.location,
      weekday: weekday ?? this.weekday,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      repeatType: repeatType ?? this.repeatType,
      weekStart: clearWeekStart ? null : weekStart ?? this.weekStart,
      activeWeekStarts: clearActiveWeekStarts
          ? null
          : activeWeekStarts ?? this.activeWeekStarts,
      revision: revision ?? this.revision,
      kind: kind ?? this.kind,
      courseKey: courseKey ?? this.courseKey,
      courseCode: courseCode ?? this.courseCode,
      semesterId: semesterId ?? this.semesterId,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      if (activeWeekStarts != null)
        'activeWeekStarts': _weekKeys(activeWeekStarts!),
      'title': title,
      'location': location,
      'weekday': weekday,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'repeatType': repeatType.name,
      'weekStart': weekStart?.toIso8601String(),
      'revision': revision,
      'kind': kind.name,
      'courseKey': courseKey,
      'courseCode': courseCode,
      'semesterId': semesterId,
    };
  }

  factory TaCourseEntry.fromJson(Map<String, dynamic> json) {
    final repeatTypeName = json['repeatType']?.toString() ?? 'weekly';
    final repeatType = repeatTypeName == TaCourseRepeatType.singleWeek.name
        ? TaCourseRepeatType.singleWeek
        : TaCourseRepeatType.weekly;
    final weekday = (json['weekday'] as num?)?.toInt() ?? 1;
    final startMinutes = (json['startMinutes'] as num?)?.toInt() ?? 8 * 60;
    final endMinutes = (json['endMinutes'] as num?)?.toInt() ?? 8 * 60 + 50;
    if (weekday < 1 || weekday > 7) {
      throw const FormatException('TA课 weekday 超出范围');
    }
    if (endMinutes <= startMinutes) {
      throw const FormatException('TA课结束时间必须晚于开始时间');
    }
    final parsedWeekStart = json['weekStart']?.toString();
    final rawRevision = (json['revision'] as num?)?.toInt() ?? 0;
    final entry = TaCourseEntry(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : stableIdFromJson(json),
      title: json['title']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      weekday: weekday,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      repeatType: repeatType,
      activeWeekStarts: _parseWeeks(json['activeWeekStarts']),
      weekStart: parsedWeekStart == null || parsedWeekStart.isEmpty
          ? null
          : normalizeWeekStart(DateTime.parse(parsedWeekStart)),
      revision: rawRevision < 0 ? 0 : rawRevision,
      kind: json['kind'] == 'ta'
          ? FixedScheduleKind.ta
          : FixedScheduleKind.schedule,
      courseKey: json['courseKey']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      semesterId: json['semesterId']?.toString() ?? '',
    );
    if (json['kind'] != null && !['ta', 'schedule'].contains(json['kind'])) {
      throw const FormatException('未知日程类型');
    }
    entry.validate();
    return entry;
  }

  static DateTime normalizeWeekStart(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return DateTime(date.year, date.month, date.day - normalized.weekday + 1);
  }

  static String weekDateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static List<String> _weekKeys(List<DateTime> weeks) =>
      weeks.map(weekDateKey).toSet().toList()..sort();

  static bool _sameWeeks(List<DateTime>? left, List<DateTime>? right) {
    if (left == null || right == null) return left == right;
    return jsonEncode(_weekKeys(left)) == jsonEncode(_weekKeys(right));
  }

  static List<DateTime>? _parseWeeks(Object? raw) {
    if (raw == null) return null;
    if (raw is! List || raw.length > 520) {
      throw const FormatException('日程适用周无效');
    }
    final dates = <DateTime>{};
    for (final value in raw) {
      if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        throw const FormatException('日程适用周无效');
      }
      final date = DateTime.tryParse(value);
      if (date == null ||
          weekDateKey(date) != value ||
          date.weekday != DateTime.monday) {
        throw const FormatException('日程适用周无效');
      }
      dates.add(date);
    }
    return List.unmodifiable(dates.toList()..sort());
  }

  static String formatMinutes(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hour = safeMinutes ~/ 60;
    final minute = safeMinutes % 60;
    return '$hour:${minute.toString().padLeft(2, '0')}';
  }

  static String createId({Random? random}) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return _uuidFromBytes(bytes);
  }

  static String stableIdFromJson(Map<String, dynamic> json) {
    final canonical = jsonEncode(<String, dynamic>{
      'title': json['title']?.toString() ?? '',
      'location': json['location']?.toString() ?? '',
      'weekday': (json['weekday'] as num?)?.toInt() ?? 1,
      'startMinutes': (json['startMinutes'] as num?)?.toInt() ?? 8 * 60,
      'endMinutes': (json['endMinutes'] as num?)?.toInt() ?? 8 * 60 + 50,
      'repeatType': json['repeatType']?.toString() ?? 'weekly',
      'weekStart': json['weekStart']?.toString() ?? '',
      if (json['activeWeekStarts'] != null)
        'activeWeekStarts': _weekKeys(_parseWeeks(json['activeWeekStarts'])!),
    });
    final bytes = sha256
        .convert(utf8.encode(canonical))
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return _uuidFromBytes(bytes);
  }

  static bool _sameDate(DateTime? left, DateTime? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static String _uuidFromBytes(List<int> bytes) {
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
