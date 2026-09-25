import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/home_overview.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/timetable_data.dart';

void main() {
  group('findNextCourseOccurrence', () {
    test('prefers a class that is currently in progress', () {
      final now = DateTime.utc(2026, 7, 20, 1, 20);
      final timetable = _timetable([
        _course(
          name: 'Programming',
          weekday: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          room: 'T2-201',
        ),
        _course(
          name: 'Writing',
          weekday: DateTime.monday,
          startMinutes: 10 * 60,
          endMinutes: 10 * 60 + 50,
          room: 'T3-105',
        ),
      ]);

      final occurrence = findNextCourseOccurrence(timetable, now: now);

      expect(occurrence?.course.name, 'Programming');
      expect(occurrence?.meeting.room, 'T2-201');
      expect(occurrence?.startsAt, DateTime.utc(2026, 7, 20, 1));
      expect(occurrence?.campusStartsAt, DateTime(2026, 7, 20, 9));
      expect(occurrence?.phase, HomeCoursePhase.inProgress);
    });

    test('wraps a completed weekly meeting to the following week', () {
      final now = DateTime.utc(2026, 7, 20, 4);
      final timetable = _timetable([
        _course(
          name: 'Programming',
          weekday: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          room: 'T2-201',
        ),
      ]);

      final occurrence = findNextCourseOccurrence(timetable, now: now);

      expect(occurrence?.startsAt, DateTime.utc(2026, 7, 27, 1));
      expect(occurrence?.campusStartsAt, DateTime(2026, 7, 27, 9));
      expect(occurrence?.phase, HomeCoursePhase.future);
    });

    test('marks a class within 30 minutes as imminent', () {
      final now = DateTime.utc(2026, 7, 20, 0, 45);
      final timetable = _timetable([
        _course(
          name: 'Programming',
          weekday: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          room: 'T2-201',
        ),
      ]);

      expect(
        findNextCourseOccurrence(timetable, now: now)?.phase,
        HomeCoursePhase.within30Minutes,
      );
    });

    test('uses the Beijing weekday when the device date is still Sunday', () {
      final now = DateTime.utc(2026, 7, 19, 17);
      final timetable = _timetable([
        _course(
          name: 'Programming',
          weekday: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          room: 'T2-201',
        ),
      ]);

      final occurrence = findNextCourseOccurrence(timetable, now: now);

      expect(occurrence?.startsAt, DateTime.utc(2026, 7, 20, 1));
      expect(occurrence?.campusStartsAt, DateTime(2026, 7, 20, 9));
      expect(occurrence?.phase, HomeCoursePhase.laterToday);
    });

    test('uses the Saturday make-up date for a Monday course', () {
      final now = DateTime.utc(2026, 10, 9, 16);
      final timetable = _timetable([
        _course(
          name: 'Programming',
          weekday: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          room: 'T2-201',
        ),
      ], selectedSemesterName: 'Semester 1 of AY2026-27');

      final occurrence = findNextCourseOccurrence(timetable, now: now);

      expect(occurrence?.startsAt, DateTime.utc(2026, 10, 10, 1));
      expect(occurrence?.campusStartsAt, DateTime(2026, 10, 10, 9));
    });

    test('skips the Monday inside Reading Week', () {
      final now = DateTime.utc(2026, 10, 25, 16);
      final timetable = _timetable([
        _course(
          name: 'Programming',
          weekday: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          room: 'T2-201',
        ),
      ], selectedSemesterName: 'Semester 1 of AY2026-27');

      final occurrence = findNextCourseOccurrence(timetable, now: now);

      expect(occurrence?.startsAt, DateTime.utc(2026, 11, 2, 1));
    });
  });

  group('findRelevantDeadline', () {
    test('selects the earliest upcoming deadline before overdue work', () {
      final now = DateTime(2026, 7, 20, 9);
      final deadline = findRelevantDeadline([
        _timelineItem(
          id: 1,
          title: 'Past report',
          dueAt: now.subtract(const Duration(hours: 2)),
          isOverdue: true,
        ),
        _timelineItem(
          id: 2,
          title: 'Later quiz',
          dueAt: now.add(const Duration(days: 2)),
        ),
        _timelineItem(
          id: 3,
          title: 'Next report',
          dueAt: now.add(const Duration(minutes: 45)),
        ),
      ], now: now);

      expect(deadline?.item.title, 'Next report');
      expect(deadline?.phase, HomeDeadlinePhase.within1Hour);
    });

    test('falls back to the most recently overdue deadline', () {
      final now = DateTime(2026, 7, 20, 9);
      final deadline = findRelevantDeadline([
        _timelineItem(
          id: 1,
          title: 'Older',
          dueAt: now.subtract(const Duration(days: 3)),
          isOverdue: true,
        ),
        _timelineItem(
          id: 2,
          title: 'Recent',
          dueAt: now.subtract(const Duration(hours: 2)),
          isOverdue: true,
        ),
      ], now: now);

      expect(deadline?.item.title, 'Recent');
      expect(deadline?.phase, HomeDeadlinePhase.overdue);
    });

    test('uses separate urgency states for one day and three days', () {
      final now = DateTime(2026, 7, 20, 9);

      expect(
        findRelevantDeadline([
          _timelineItem(
            id: 1,
            title: 'Tomorrow',
            dueAt: now.add(const Duration(hours: 12)),
          ),
        ], now: now)?.phase,
        HomeDeadlinePhase.within24Hours,
      );
      expect(
        findRelevantDeadline([
          _timelineItem(
            id: 2,
            title: 'This week',
            dueAt: now.add(const Duration(days: 2)),
          ),
        ], now: now)?.phase,
        HomeDeadlinePhase.within3Days,
      );
    });
  });
}

TimetableData _timetable(
  List<TimetableCourse> courses, {
  String selectedSemesterName = '2026 Summer',
}) {
  return TimetableData(
    profile: TimetableProfile(studentId: '', name: '', programme: '', year: ''),
    semesters: const [],
    selectedSemesterId: '2026-summer',
    selectedSemesterName: selectedSemesterName,
    courses: courses,
  );
}

TimetableCourse _course({
  required String name,
  required int weekday,
  required int startMinutes,
  required int endMinutes,
  required String room,
}) {
  return TimetableCourse(
    section: '',
    category: '',
    code: name,
    name: name,
    teacher: '',
    meetings: [
      TimetableMeeting(
        weekday: weekday,
        dayLabel: 'Mon',
        startLabel: '09:00',
        endLabel: '09:50',
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        room: room,
      ),
    ],
    rooms: [room],
    units: '',
    remark: '',
  );
}

TimelineItem _timelineItem({
  required int id,
  required String title,
  required DateTime dueAt,
  bool isOverdue = false,
}) {
  return TimelineItem(
    id: id,
    title: title,
    activityState: '',
    activityType: 'assign',
    moduleName: 'assign',
    description: '',
    courseName: 'Course',
    courseId: 1,
    instanceId: id,
    url: '/mod/assign/view.php?id=$id',
    sortTime: dueAt,
    formattedTime: '',
    isOverdue: isOverdue,
  );
}
