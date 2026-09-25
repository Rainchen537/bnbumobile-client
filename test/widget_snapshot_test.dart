import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/widget_snapshot.dart';

void main() {
  test('creates Beijing-time occurrences and applies calendar exceptions', () {
    final snapshot = buildBnbuWidgetSnapshot(
      timetable: _timetable(),
      timelineItems: const [],
      taCourses: const [],
      now: DateTime.utc(2026, 10, 9, 16),
    );

    expect(snapshot.courses.first.startsAt, DateTime.utc(2026, 10, 10, 1));
    expect(snapshot.courses.first.title, 'Programming');
    expect(
      snapshot.courses.any(
        (course) =>
            course.startsAt.isAfter(DateTime.utc(2026, 10, 24, 16)) &&
            course.startsAt.isBefore(DateTime.utc(2026, 10, 31, 16)),
      ),
      isFalse,
    );
  });

  test('includes TA courses without applying MIS holiday rules', () {
    final snapshot = buildBnbuWidgetSnapshot(
      timetable: _timetable(),
      timelineItems: const [],
      taCourses: [
        TaCourseEntry(
          id: 'ta-1',
          title: 'Consultation',
          location: 'T2-101',
          weekday: DateTime.monday,
          startMinutes: 10 * 60,
          endMinutes: 11 * 60,
          repeatType: TaCourseRepeatType.weekly,
        ),
      ],
      now: DateTime.utc(2026, 10, 25, 16),
    );

    final taCourse = snapshot.courses.firstWhere(
      (course) => course.title == 'Consultation',
    );
    expect(taCourse.startsAt, DateTime.utc(2026, 10, 26, 2));
    expect(taCourse.isTaCourse, isFalse);
    expect(taCourse.code, '');
  });

  test(
    'keeps only future non-overdue deadlines and removes private fields',
    () {
      final now = DateTime.utc(2026, 8, 11, 2);
      final snapshot = buildBnbuWidgetSnapshot(
        timetable: null,
        timelineItems: [
          _deadline(1, 'Past', now.subtract(const Duration(hours: 1)), true),
          _deadline(2, 'Later', now.add(const Duration(days: 2)), false),
          _deadline(3, 'Next', now.add(const Duration(hours: 2)), false),
        ],
        taCourses: const [],
        now: now,
      );

      expect(snapshot.deadlines.map((item) => item.title), ['Next', 'Later']);
      final json = snapshot.toJson().toString();
      expect(json, isNot(contains('studentId')));
      expect(json, isNot(contains('description')));
      expect(json, isNot(contains('url')));
    },
  );

  test('includes the course teacher required by large widgets', () {
    final snapshot = buildBnbuWidgetSnapshot(
      timetable: _timetable(),
      timelineItems: const [],
      taCourses: const [],
      now: DateTime.utc(2026, 9, 6, 16),
    );

    expect(snapshot.courses.first.teacher, 'private');
    expect(snapshot.toJson().toString(), contains('teacher'));
  });

  test('exports stable light and dark course accents for Apple widgets', () {
    final snapshot = buildBnbuWidgetSnapshot(
      timetable: _timetable(),
      timelineItems: const [],
      taCourses: const [],
      now: DateTime.utc(2026, 9, 6, 16),
    );

    final accents = snapshot.courses
        .where((course) => course.code == 'COMP1001')
        .map((course) => (course.lightAccentHex, course.darkAccentHex))
        .toSet();
    expect(accents, hasLength(1));
    expect(accents.single.$1, matches(RegExp(r'^#[0-9A-F]{6}$')));
    expect(accents.single.$2, matches(RegExp(r'^#[0-9A-F]{6}$')));
  });

  test('includes the effective interface language for the paired Watch', () {
    final snapshot = buildBnbuWidgetSnapshot(
      timetable: null,
      timelineItems: const [],
      taCourses: const [],
      now: DateTime.utc(2026, 8, 29),
      interfaceLanguage: 'zh-Hant',
    );

    expect(snapshot.interfaceLanguage, 'zh-Hant');
    expect(snapshot.toJson()['interfaceLanguage'], 'zh-Hant');
  });
}

TimetableData _timetable() {
  return TimetableData(
    profile: TimetableProfile(
      studentId: 'private',
      name: 'private',
      programme: 'private',
      year: 'private',
    ),
    semesters: const [],
    selectedSemesterId: '2026-27-1',
    selectedSemesterName: 'Semester 1 of AY2026-27',
    courses: [
      TimetableCourse(
        section: '',
        category: '',
        code: 'COMP1001',
        name: 'Programming',
        teacher: 'private',
        meetings: [
          TimetableMeeting(
            weekday: DateTime.monday,
            dayLabel: 'Mon',
            startLabel: '09:00',
            endLabel: '09:50',
            startMinutes: 9 * 60,
            endMinutes: 9 * 60 + 50,
            room: 'T2-201',
          ),
        ],
        rooms: const ['T2-201'],
        units: '',
        remark: '',
      ),
    ],
  );
}

TimelineItem _deadline(int id, String title, DateTime dueAt, bool isOverdue) {
  return TimelineItem(
    id: id,
    title: title,
    activityState: '',
    activityType: 'assign',
    moduleName: 'assign',
    description: 'private',
    courseName: 'Course',
    courseId: 1,
    instanceId: id,
    url: 'https://example.invalid/private',
    sortTime: dueAt,
    formattedTime: '',
    isOverdue: isOverdue,
  );
}
