import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/academic_calendar.dart';
import 'package:bnbu_me/models/timetable_data.dart';

void main() {
  group('BnbuAcademicCalendar', () {
    final timetable = _timetable();

    test('recognizes the selected Semester 1 of AY2026-27', () {
      expect(BnbuAcademicCalendar.appliesTo(timetable), isTrue);
      expect(
        BnbuAcademicCalendar.appliesTo(
          _timetable(name: '2026 Semester 1', id: '2026'),
        ),
        isTrue,
      );
      expect(
        BnbuAcademicCalendar.appliesTo(
          _timetable(name: 'Semester 1', id: 'AY2026-27'),
        ),
        isTrue,
      );
    });

    test('does not confuse another 2026 semester with Semester 1', () {
      for (final value in <({String id, String name})>[
        (id: '2026', name: '2026 Semester 2'),
        (id: '2026', name: 'Summer 2026'),
        (id: '2025-26-S1', name: 'Semester 1 of AY2025-26'),
        (id: '2026', name: 'Semester 1 of AY2025-2026'),
        (id: '2026-27-S10', name: 'Semester 10 of AY2026-27'),
      ]) {
        expect(
          BnbuAcademicCalendar.appliesTo(
            _timetable(id: value.id, name: value.name),
          ),
          isFalse,
          reason: '${value.id} / ${value.name}',
        );
      }
    });

    test('marks official holidays and Reading Week as no-class dates', () {
      expect(
        BnbuAcademicCalendar.classDayFor(
          timetable,
          DateTime(2026, 9, 25),
        ).notice,
        '中秋假期',
      );
      expect(
        BnbuAcademicCalendar.classDayFor(
          timetable,
          DateTime(2026, 10, 3),
        ).notice,
        '国庆假期',
      );
      expect(
        BnbuAcademicCalendar.classDayFor(
          timetable,
          DateTime(2026, 10, 28),
        ).notice,
        'Reading Week 假期',
      );
      expect(
        BnbuAcademicCalendar.classDayFor(
          timetable,
          DateTime(2026, 10, 28),
        ).hasClasses,
        isFalse,
      );
      for (final boundary in <DateTime>[
        DateTime(2026, 10, 25),
        DateTime(2026, 10, 31),
      ]) {
        final day = BnbuAcademicCalendar.classDayFor(timetable, boundary);
        expect(day.notice, 'Reading Week 假期');
        expect(day.hasClasses, isFalse);
      }
      expect(
        BnbuAcademicCalendar.classDayFor(
          timetable,
          DateTime(2026, 10, 24),
        ).sourceWeekday,
        DateTime.saturday,
      );
      expect(
        BnbuAcademicCalendar.classDayFor(
          timetable,
          DateTime(2026, 11, 1),
        ).sourceWeekday,
        DateTime.sunday,
      );
    });

    test('maps official make-up dates to the source weekday', () {
      final fridayMakeUp = BnbuAcademicCalendar.classDayFor(
        timetable,
        DateTime(2026, 9, 20),
      );
      final mondayMakeUp = BnbuAcademicCalendar.classDayFor(
        timetable,
        DateTime(2026, 10, 10),
      );

      expect(fridayMakeUp.sourceWeekday, DateTime.friday);
      expect(fridayMakeUp.notice, '补周五课程');
      expect(mondayMakeUp.sourceWeekday, DateTime.monday);
      expect(mondayMakeUp.notice, '补周一课程');
    });

    test('exports the bounded official calendar events for Small U', () {
      final context = BnbuAcademicCalendar.contextFor(timetable);

      expect(context.appliesToSelectedSemester, isTrue);
      expect(context.timezone, 'Asia/Shanghai');
      expect(context.events, hasLength(21));
      expect(
        context.events.map((event) => event.name),
        everyElement(hasLength(lessThanOrEqualTo(80))),
      );
      expect(
        context.events.map((event) => event.name),
        containsAll(<String>[
          'Summer Term Ends (AY2025/26) / 2025/26 夏季学期结束',
          'New Student Orientation & English Enhancement Programme / 新生迎新及英语强化课程',
          'Revision for Final Examinations / 期末考试复习期',
          'Semester I Final Examinations / 第一学期期末考试',
          'Military Training for Year 1 Students / 一年级学生军训',
          'Faculty Board Meetings / 学院委员会会议',
          'Senate Meeting / 校务委员会会议',
          'Release of Grade Reports / Semester I Ends / 成绩报告发布及第一学期结束',
        ]),
      );
      expect(
        context.events.where(
          (event) => event.kind == BnbuCalendarEventKind.makeUpClass,
        ),
        hasLength(2),
      );
      expect(
        context.events
            .singleWhere((event) => event.name == 'Reading Week / 阅读周')
            .startsOn,
        DateTime(2026, 10, 25),
      );
      expect(
        context.events
            .singleWhere(
              (event) => event.name == 'National Day holidays / 国庆节假期',
            )
            .endsOn,
        DateTime(2026, 10, 7),
      );
    });

    test('skips holidays when locating the next regular meeting', () {
      final fridayMeeting = _meeting(DateTime.friday);

      expect(
        BnbuAcademicCalendar.nextMeetingDate(
          timetable: timetable,
          meeting: fridayMeeting,
          fromCampusDate: DateTime(2026, 9, 24),
        ),
        DateTime(2026, 10, 9),
      );
    });

    test('stops recurring MIS classes after the last class day', () {
      expect(
        BnbuAcademicCalendar.nextMeetingDate(
          timetable: timetable,
          meeting: _meeting(DateTime.monday),
          fromCampusDate: DateTime(2026, 12, 12),
        ),
        isNull,
      );
    });

    test('does not apply AY2026-27 rules to another semester', () {
      final historical = _timetable(name: 'Semester 2 of AY2025-26');

      expect(
        BnbuAcademicCalendar.classDayFor(
          historical,
          DateTime(2026, 10, 3),
        ).sourceWeekday,
        DateTime.saturday,
      );
    });
  });
}

TimetableData _timetable({
  String name = 'Semester 1 of AY2026-27',
  String id = '2026-27-S1',
}) {
  return TimetableData(
    profile: TimetableProfile(studentId: '', name: '', programme: '', year: ''),
    semesters: const [],
    selectedSemesterId: name == 'Semester 2 of AY2025-26' ? '2025-26-S2' : id,
    selectedSemesterName: name,
    courses: const [],
  );
}

TimetableMeeting _meeting(int weekday) {
  return TimetableMeeting(
    weekday: weekday,
    dayLabel: 'Day',
    startLabel: '09:00',
    endLabel: '09:50',
    startMinutes: 9 * 60,
    endMinutes: 9 * 60 + 50,
    room: 'T1-101',
  );
}
