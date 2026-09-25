import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/academic_calendar.dart';
import 'package:bnbu_me/models/fixed_schedule_weeks.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/widget_snapshot.dart';
import 'package:bnbu_me/models/fixed_schedule_transfer.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'dart:convert';

TimetableData calendarTimetable({String? name}) => TimetableData(
  profile: TimetableProfile(studentId: '', name: '', programme: '', year: ''),
  semesters: [],
  selectedSemesterId: 'fixture',
  selectedSemesterName: name ?? bnbuAy202627Semester1Title,
  courses: [],
);

TaCourseEntry weeklyEntry({List<DateTime>? weeks}) => TaCourseEntry(
  id: 'weekly',
  title: 'Study',
  location: '',
  weekday: 1,
  startMinutes: 540,
  endMinutes: 600,
  repeatType: TaCourseRepeatType.weekly,
  activeWeekStarts: weeks,
);

void main() {
  test(
    'display week numbers retain holidays and mark first/last teaching weeks',
    () {
      final semester = BnbuAcademicCalendar.semesterFor(calendarTimetable())!;
      final first = FixedScheduleWeekContext(DateTime(2026, 9, 1), semester);
      expect(first.weekNumber, 1);
      expect(first.startsTeaching, isTrue);
      expect(first.endsTeaching, isFalse);
      final last = FixedScheduleWeekContext(DateTime(2026, 12, 11), semester);
      expect(last.weekNumber, 15);
      expect(last.endsTeaching, isTrue);
      expect(
        FixedScheduleWeekContext(DateTime(2026, 10, 26), semester).weekNumber,
        9,
      );
      final outside = FixedScheduleWeekContext(DateTime(2027, 1, 4), semester);
      expect(outside.outsideTeachingTerm, isTrue);
      expect(outside.weekNumber, isNull);
      expect(outside.startsTeaching, isFalse);
    },
  );
  test('holiday annotations are clipped to the actual days in each week', () {
    final semester = BnbuAcademicCalendar.semesterFor(calendarTimetable())!;
    final autumn = FixedScheduleWeekContext(DateTime(2026, 9, 21), semester);
    expect(autumn.observances.single.startsOn, DateTime(2026, 9, 25));
    expect(autumn.observances.single.endsOn, DateTime(2026, 9, 27));
    final national = FixedScheduleWeekContext(DateTime(2026, 9, 28), semester);
    expect(national.observances.single.startsOn, DateTime(2026, 10, 1));
    expect(national.observances.single.endsOn, DateTime(2026, 10, 4));
    final tail = FixedScheduleWeekContext(DateTime(2026, 10, 5), semester);
    expect(tail.observances.single.startsOn, DateTime(2026, 10, 5));
    expect(tail.observances.single.endsOn, DateTime(2026, 10, 7));
    expect(
      FixedScheduleWeekContext(DateTime(2026, 10, 12), semester).observances,
      isEmpty,
    );
  });
  test(
    'Reading Week Sunday boundary is not described as a full holiday week',
    () {
      final semester = BnbuAcademicCalendar.semesterFor(calendarTimetable())!;
      final head = FixedScheduleWeekContext(DateTime(2026, 10, 19), semester);
      final tail = FixedScheduleWeekContext(DateTime(2026, 10, 26), semester);
      expect(head.observances.single.startsOn, DateTime(2026, 10, 25));
      expect(head.observances.single.endsOn, DateTime(2026, 10, 25));
      expect(tail.observances.single.startsOn, DateTime(2026, 10, 26));
      expect(tail.observances.single.endsOn, DateTime(2026, 10, 31));
    },
  );
  test(
    'unavailable calendar never fabricates context or borrows the built-in term',
    () {
      final details = FixedScheduleWeekContext(DateTime(2026, 9, 1), null);
      expect(details.weekNumber, isNull);
      expect(details.startsTeaching, isFalse);
      expect(details.endsTeaching, isFalse);
      expect(details.outsideTeachingTerm, isFalse);
      expect(details.observances, isEmpty);
    },
  );
  test(
    'display follows supplied calendar dates across years, including one-week term',
    () {
      final semester = BnbuCalendarSemester(
        id: 'winter-fixture',
        academicYearStart: 2030,
        semester: 4,
        semesterTitle: 'Winter',
        semesterIds: const ['winter-fixture'],
        semesterStartsOn: DateTime(2030, 12, 31),
        lastClassDay: DateTime(2031, 1, 3),
        events: [
          BnbuCalendarEvent(
            kind: BnbuCalendarEventKind.holiday,
            name: 'Test holiday',
            startsOn: DateTime(2030, 12, 31),
            endsOn: DateTime(2031, 1, 2),
          ),
          BnbuCalendarEvent(
            kind: BnbuCalendarEventKind.administrative,
            name: 'Not a holiday',
            startsOn: DateTime(2031, 1, 1),
            endsOn: DateTime(2031, 1, 1),
          ),
        ],
        documents: const {},
      );
      final details = FixedScheduleWeekContext(DateTime(2031, 1, 1), semester);
      expect(details.startsTeaching && details.endsTeaching, isTrue);
      expect(details.weekNumber, 1);
      expect(details.observances.single.startsOn, DateTime(2030, 12, 31));
      expect(details.observances.single.endsOn, DateTime(2031, 1, 2));
      expect(details.observances.single.event.name, 'Test holiday');
    },
  );
  test(
    'defaults follow the actual weekday and skip holidays and Reading Week',
    () {
      final timetable = calendarTimetable();
      final monday = FixedScheduleWeeks.teachingWeeks(timetable, 1)!;
      expect(monday, contains(DateTime(2026, 9, 21)));
      expect(monday, isNot(contains(DateTime(2026, 8, 31))));
      expect(monday, isNot(contains(DateTime(2026, 10, 5))));
      expect(monday, contains(DateTime(2026, 10, 19)));
      expect(monday, isNot(contains(DateTime(2026, 10, 26))));
      expect(monday, isNot(contains(DateTime(2026, 12, 14))));
      final friday = FixedScheduleWeeks.teachingWeeks(timetable, 5)!;
      expect(friday, isNot(contains(DateTime(2026, 9, 21))));
      final sunday = FixedScheduleWeeks.teachingWeeks(timetable, 7)!;
      expect(sunday, isNot(contains(DateTime(2026, 10, 19))));
    },
  );
  test('unknown semesters do not borrow another semester teaching weeks', () {
    expect(
      FixedScheduleWeeks.teachingWeeks(calendarTimetable(name: 'unknown'), 1),
      isNull,
    );
    expect(FixedScheduleWeeks.teachingWeeks(null, 1), isNull);
  });
  test('explicit holiday and out-of-term weeks override teaching defaults', () {
    final entry = weeklyEntry(
      weeks: [DateTime(2026, 10, 26), DateTime(2027, 1, 4)],
    );
    expect(entry.appliesToWeek(DateTime(2026, 10, 27)), isTrue);
    expect(entry.appliesToWeek(DateTime(2027, 1, 10)), isTrue);
    expect(entry.appliesToWeek(DateTime(2026, 11, 2)), isFalse);
    expect(weeklyEntry(weeks: []).appliesToWeek(DateTime(2026, 9, 7)), isFalse);
    expect(weeklyEntry().appliesToWeek(DateTime(2030, 1, 7)), isTrue);
  });
  test(
    'round-trip, copy and equality retain exact weeks independent of ordering',
    () {
      final entry = weeklyEntry(
        weeks: [DateTime(2027, 1, 4), DateTime(2026, 10, 26)],
      );
      expect(entry.toJson()['activeWeekStarts'], ['2026-10-26', '2027-01-04']);
      final restored = TaCourseEntry.fromJson(entry.toJson());
      expect(restored.hasSameCourseFields(entry), isTrue);
      expect(
        restored.copyWith(title: 'Changed').activeWeekStarts,
        entry.activeWeekStarts!.reversed,
      );
      expect(
        entry.hasSameCourseFields(entry.copyWith(activeWeekStarts: [])),
        isFalse,
      );
      expect(entry.hasSameCourseFields(weeklyEntry()), isFalse);
      expect(
        weeklyEntry(weeks: []).hasSameCourseFields(weeklyEntry()),
        isFalse,
      );
    },
  );
  test(
    'invalid explicit selections fail closed instead of reverting to all weeks',
    () {
      for (final value in [
        'all',
        ['2026-02-30'],
        ['2026-10-27'],
        [null],
        ['2026-10-26T00:00:00Z'],
      ]) {
        expect(
          () => TaCourseEntry.fromJson({
            ...weeklyEntry().toJson(),
            'activeWeekStarts': value,
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Widget/Watch/live activity occurrence source excludes unselected weeks',
    () {
      final entry = weeklyEntry(weeks: [DateTime(2026, 11, 2)]);
      final snapshot = buildBnbuWidgetSnapshot(
        timetable: calendarTimetable(),
        timelineItems: [],
        taCourses: [entry],
        now: DateTime.utc(2026, 10, 26),
      );
      expect(snapshot.courses.map((c) => c.startsAt), [
        DateTime.utc(2026, 11, 2, 1),
      ]);
      final overridden = buildBnbuWidgetSnapshot(
        timetable: calendarTimetable(),
        timelineItems: [],
        taCourses: [
          entry.copyWith(activeWeekStarts: [DateTime(2026, 10, 26)]),
        ],
        now: DateTime.utc(2026, 10, 26),
      );
      expect(overridden.courses.map((c) => c.startsAt), [
        DateTime.utc(2026, 10, 26, 1),
      ]);
    },
  );
  test(
    'reminder plans cancel excluded weeks and include explicit holiday/out-of-term weeks',
    () {
      final service = DeadlineReminderService();
      final entry = weeklyEntry(
        weeks: [DateTime(2026, 10, 26), DateTime(2026, 11, 2)],
      );
      List<Map<String, Object?>> plan(TaCourseEntry value, DateTime now) =>
          service.buildCourseNotificationPlanForTesting(
            calendarTimetable(),
            now: now,
            fixedSchedules: [value],
          );
      final now = DateTime.utc(2026, 10, 26);
      final before = plan(entry, now);
      expect(before, hasLength(2));
      expect(
        plan(entry.copyWith(activeWeekStarts: [DateTime(2026, 11, 2)]), now),
        hasLength(1),
      );
      expect(plan(entry.copyWith(activeWeekStarts: []), now), isEmpty);
      expect(plan(entry, now), before);
      expect(
        plan(
          weeklyEntry(weeks: [DateTime(2027, 1, 4)]),
          DateTime.utc(2027, 1, 3),
        ),
        hasLength(1),
      );
    },
  );
  test('v3 transfer preserves selections and old importers fail closed', () {
    final entry = weeklyEntry(weeks: [DateTime(2027, 1, 4)]);
    final encoded = FixedScheduleTransfer.encode([entry]);
    expect((jsonDecode(encoded) as Map)['entries'], isNull);
    expect(
      FixedScheduleTransfer.decode(encoded).single.hasSameCourseFields(entry),
      isTrue,
    );
    for (final version in [1, 2]) {
      final legacy = jsonEncode({
        'version': version,
        'entries': [weeklyEntry().toJson()],
      });
      expect(
        FixedScheduleTransfer.decode(legacy).single.activeWeekStarts,
        isNull,
      );
    }
    expect(
      () => FixedScheduleTransfer.decode('{"version":4,"entries":[]}'),
      throwsFormatException,
    );
    expect(
      () => FixedScheduleTransfer.decode('{"version":3,"entries":[]}'),
      throwsFormatException,
    );
  });
}
