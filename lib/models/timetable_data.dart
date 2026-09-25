import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'exam_timetable.dart';

class TimetableData {
  TimetableData({
    required this.profile,
    required this.semesters,
    required this.selectedSemesterId,
    required this.selectedSemesterName,
    required this.courses,
    this.examAvailability = ExamTimetableAvailability.unavailable,
    this.exams = const <ExamTimetableEntry>[],
  });

  final TimetableProfile profile;
  final List<TimetableSemester> semesters;
  final String selectedSemesterId;
  final String selectedSemesterName;
  final List<TimetableCourse> courses;
  final ExamTimetableAvailability examAvailability;
  final List<ExamTimetableEntry> exams;

  int get totalMeetings =>
      courses.fold<int>(0, (total, course) => total + course.meetings.length);

  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile.toJson(),
    'semesters': semesters.map((semester) => semester.toJson()).toList(),
    'selectedSemesterId': selectedSemesterId,
    'selectedSemesterName': selectedSemesterName,
    'courses': courses.map((course) => course.toJson()).toList(),
    'examAvailability': examAvailability.name,
    'exams': exams.map((exam) => exam.toJson()).toList(),
  };

  factory TimetableData.fromJson(Map<String, dynamic> json) {
    return TimetableData(
      profile: TimetableProfile.fromJson(_jsonMap(json['profile'])),
      semesters: _jsonList(json['semesters'])
          .map((item) => TimetableSemester.fromJson(_jsonMap(item)))
          .toList(growable: false),
      selectedSemesterId: _jsonString(json['selectedSemesterId']),
      selectedSemesterName: _jsonString(json['selectedSemesterName']),
      courses: _jsonList(json['courses'])
          .map((item) => TimetableCourse.fromJson(_jsonMap(item)))
          .toList(growable: false),
      examAvailability: ExamTimetableAvailability.values.firstWhere(
        (value) => value.name == _jsonString(json['examAvailability']),
        orElse: () => ExamTimetableAvailability.unavailable,
      ),
      exams: json['exams'] == null
          ? const <ExamTimetableEntry>[]
          : ExamTimetableData.deduplicateEntries(
              _jsonList(
                json['exams'],
              ).map((item) => ExamTimetableEntry.fromJson(_jsonMap(item))),
            ),
    );
  }

  TimetableData withExamTimetable(ExamTimetableData examTimetable) {
    return TimetableData(
      profile: profile,
      semesters: semesters,
      selectedSemesterId: selectedSemesterId,
      selectedSemesterName: selectedSemesterName,
      courses: courses,
      examAvailability: examTimetable.availability,
      exams: ExamTimetableData.deduplicateEntries(examTimetable.entries),
    );
  }

  factory TimetableData.fromHtml(String source) {
    final document = html_parser.parse(source);
    final semesters = document
        .querySelectorAll('#semesterList option')
        .map(
          (option) => TimetableSemester(
            id: option.attributes['value']?.trim() ?? '',
            name: _normalize(option.text),
            isSelected: option.attributes.containsKey('selected'),
          ),
        )
        .where((semester) => semester.id.isNotEmpty && semester.name.isNotEmpty)
        .toList();

    TimetableSemester? selectedSemester;
    for (final semester in semesters) {
      if (semester.isSelected) {
        selectedSemester = semester;
        break;
      }
    }
    selectedSemester ??= semesters.isNotEmpty ? semesters.first : null;

    final courses = <TimetableCourse>[];
    final sectionRows = document.querySelectorAll('table.tablestyle-2 tr');
    for (final row in sectionRows) {
      final indexCell = row.querySelector('th');
      final cells = row.querySelectorAll('td');
      if (indexCell == null || cells.length < 8) {
        continue;
      }

      final timeLines = _extractCellLines(cells[4]);
      final roomLines = _extractCellLines(cells[5]);
      final meetings = <TimetableMeeting>[];
      for (var index = 0; index < timeLines.length; index++) {
        final meeting = TimetableMeeting.tryParse(
          timeLines[index],
          room: index < roomLines.length ? roomLines[index] : '',
        );
        if (meeting != null) {
          meetings.add(meeting);
        }
      }

      courses.add(
        TimetableCourse(
          section: _normalize(indexCell.text),
          category: _normalize(cells[0].text),
          code: _normalize(cells[1].text),
          name: _normalize(cells[2].text),
          teacher: _extractCellLines(cells[3]).join('; '),
          meetings: meetings,
          rooms: roomLines,
          units: _normalize(cells[6].text),
          remark: _normalize(cells[7].text),
        ),
      );
    }

    return TimetableData(
      profile: TimetableProfile(
        studentId: _profileValue(document, '.studentid span'),
        name: _profileValue(document, '.name span'),
        programme: _profileValue(document, '.programme span'),
        year: _profileValue(document, '.year span'),
      ),
      semesters: semesters,
      selectedSemesterId: selectedSemester?.id ?? '',
      selectedSemesterName: selectedSemester?.name ?? '',
      courses: courses,
    );
  }

  static String _profileValue(Document document, String selector) {
    return _normalize(document.querySelector(selector)?.text ?? '');
  }

  static List<String> _extractCellLines(Element cell) {
    final normalizedHtml = cell.innerHtml.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    final text = html_parser.parseFragment(normalizedHtml).text ?? '';
    return text
        .split('\n')
        .map(_normalize)
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String _normalize(String value) {
    return value
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Map<String, dynamic> _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    throw const FormatException('Invalid timetable cache object.');
  }

  static List<dynamic> _jsonList(Object? value) {
    if (value is List) {
      return value;
    }
    throw const FormatException('Invalid timetable cache list.');
  }

  static String _jsonString(Object? value) => value is String ? value : '';

  static int _jsonInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw const FormatException('Invalid timetable cache number.');
  }
}

class TimetableProfile {
  TimetableProfile({
    required this.studentId,
    required this.name,
    required this.programme,
    required this.year,
  });

  final String studentId;
  final String name;
  final String programme;
  final String year;

  Map<String, Object?> toJson() => <String, Object?>{
    'studentId': studentId,
    'name': name,
    'programme': programme,
    'year': year,
  };

  factory TimetableProfile.fromJson(Map<String, dynamic> json) {
    return TimetableProfile(
      studentId: TimetableData._jsonString(json['studentId']),
      name: TimetableData._jsonString(json['name']),
      programme: TimetableData._jsonString(json['programme']),
      year: TimetableData._jsonString(json['year']),
    );
  }
}

class TimetableSemester {
  TimetableSemester({
    required this.id,
    required this.name,
    required this.isSelected,
  });

  final String id;
  final String name;
  final bool isSelected;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'isSelected': isSelected,
  };

  factory TimetableSemester.fromJson(Map<String, dynamic> json) {
    return TimetableSemester(
      id: TimetableData._jsonString(json['id']),
      name: TimetableData._jsonString(json['name']),
      isSelected: json['isSelected'] == true,
    );
  }
}

class TimetableCourse {
  TimetableCourse({
    required this.section,
    required this.category,
    required this.code,
    required this.name,
    required this.teacher,
    required this.meetings,
    required this.rooms,
    required this.units,
    required this.remark,
  });

  final String section;
  final String category;
  final String code;
  final String name;
  final String teacher;
  final List<TimetableMeeting> meetings;
  final List<String> rooms;
  final String units;
  final String remark;

  Map<String, Object?> toJson() => <String, Object?>{
    'section': section,
    'category': category,
    'code': code,
    'name': name,
    'teacher': teacher,
    'meetings': meetings.map((meeting) => meeting.toJson()).toList(),
    'rooms': rooms,
    'units': units,
    'remark': remark,
  };

  factory TimetableCourse.fromJson(Map<String, dynamic> json) {
    return TimetableCourse(
      section: TimetableData._jsonString(json['section']),
      category: TimetableData._jsonString(json['category']),
      code: TimetableData._jsonString(json['code']),
      name: TimetableData._jsonString(json['name']),
      teacher: TimetableData._jsonString(json['teacher']),
      meetings: TimetableData._jsonList(json['meetings'])
          .map(
            (item) => TimetableMeeting.fromJson(TimetableData._jsonMap(item)),
          )
          .toList(growable: false),
      rooms: TimetableData._jsonList(
        json['rooms'],
      ).map(TimetableData._jsonString).toList(growable: false),
      units: TimetableData._jsonString(json['units']),
      remark: TimetableData._jsonString(json['remark']),
    );
  }
}

class TimetableMeeting {
  TimetableMeeting({
    required this.weekday,
    required this.dayLabel,
    required this.startLabel,
    required this.endLabel,
    required this.startMinutes,
    required this.endMinutes,
    required this.room,
  });

  final int weekday;
  final String dayLabel;
  final String startLabel;
  final String endLabel;
  final int startMinutes;
  final int endMinutes;
  final String room;

  String get timeLabel => '$dayLabel $startLabel-$endLabel';

  Map<String, Object?> toJson() => <String, Object?>{
    'weekday': weekday,
    'dayLabel': dayLabel,
    'startLabel': startLabel,
    'endLabel': endLabel,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'room': room,
  };

  factory TimetableMeeting.fromJson(Map<String, dynamic> json) {
    return TimetableMeeting(
      weekday: TimetableData._jsonInt(json['weekday']),
      dayLabel: TimetableData._jsonString(json['dayLabel']),
      startLabel: TimetableData._jsonString(json['startLabel']),
      endLabel: TimetableData._jsonString(json['endLabel']),
      startMinutes: TimetableData._jsonInt(json['startMinutes']),
      endMinutes: TimetableData._jsonInt(json['endMinutes']),
      room: TimetableData._jsonString(json['room']),
    );
  }

  static TimetableMeeting? tryParse(String source, {required String room}) {
    final match = RegExp(
      r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$',
    ).firstMatch(source);
    if (match == null) {
      return null;
    }
    final dayLabel = match.group(1)!;
    final startLabel = match.group(2)!;
    final endLabel = match.group(3)!;
    return TimetableMeeting(
      weekday: _weekdayFromLabel(dayLabel),
      dayLabel: dayLabel,
      startLabel: startLabel,
      endLabel: endLabel,
      startMinutes: _parseMinutes(startLabel),
      endMinutes: _parseMinutes(endLabel),
      room: room,
    );
  }

  static int _weekdayFromLabel(String value) {
    const mapping = <String, int>{
      'Mon': 1,
      'Tue': 2,
      'Wed': 3,
      'Thu': 4,
      'Fri': 5,
      'Sat': 6,
      'Sun': 7,
    };
    return mapping[value] ?? 1;
  }

  static int _parseMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return 0;
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
  }
}
