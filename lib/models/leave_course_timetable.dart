import 'timetable_data.dart';

/// Presentation only. Never infer a school selection ID from timetable data.
abstract final class LeaveCourseTimetableData {
  static const identityFields = ['code', 'teacher', 'type', 'time'];

  static String _displayValue(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool sameCourse(Map<String, String> a, Map<String, String> b) =>
      identityFields.every((field) {
        final value = _displayValue(a[field]);
        final other = _displayValue(b[field]);
        if (value.isEmpty || other.isEmpty) return false;
        if (field == 'time') {
          final left = meetings(value), right = meetings(other);
          if (left.isNotEmpty && right.isNotEmpty) {
            String key(List<TimetableMeeting> rows) {
              final parts =
                  rows
                      .map(
                        (m) => '${m.weekday}:${m.startMinutes}:${m.endMinutes}',
                      )
                      .toList()
                    ..sort();
              return parts.join('|');
            }

            return key(left) == key(right);
          }
        }
        return value == other;
      });

  static List<TimetableMeeting> meetings(String source) {
    if (source.length > 4000) return const [];
    final pattern = RegExp(
      r'(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun|星期[一二三四五六日天]|[周週][一二三四五六日天])\s*(\d{1,2}):([0-5]\d)\s*[-–—－]\s*(\d{1,2}):([0-5]\d)',
      caseSensitive: false,
    );
    final result = <TimetableMeeting>[];
    var offset = 0;
    final separators = RegExp(r'^[\s,;，；/]*$');
    for (final match in pattern.allMatches(source)) {
      if (!separators.hasMatch(source.substring(offset, match.start))) {
        return const [];
      }
      final day = match[1]!.toLowerCase();
      final english = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      var weekday = english.indexWhere(day.startsWith) + 1;
      if (weekday == 0) {
        weekday =
            '一二三四五六日'.indexOf(day.endsWith('天') ? '日' : day[day.length - 1]) +
            1;
      }
      final start = int.parse(match[2]!) * 60 + int.parse(match[3]!);
      final end = int.parse(match[4]!) * 60 + int.parse(match[5]!);
      if (weekday == 0 || start >= 1440 || end > 1440 || start >= end) {
        return const [];
      }
      if (!result.any(
        (m) =>
            m.weekday == weekday &&
            m.startMinutes == start &&
            m.endMinutes == end,
      )) {
        result.add(
          TimetableMeeting(
            weekday: weekday,
            dayLabel: english[weekday - 1],
            startLabel: minuteLabel(start),
            endLabel: minuteLabel(end),
            startMinutes: start,
            endMinutes: end,
            room: '',
          ),
        );
      }
      offset = match.end;
    }
    return separators.hasMatch(source.substring(offset)) ? result : const [];
  }

  static String minuteLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  /// Only the current Portal label determines presentation color.
  static String colorSeed(Map<String, String> row) =>
      _displayValue(row['code']);
}
