import 'academic_calendar.dart';
import 'campus_time.dart';
import 'timeline_item.dart';
import 'timetable_data.dart';

enum HomeCoursePhase { inProgress, within30Minutes, laterToday, future }

enum HomeDeadlinePhase {
  overdue,
  within1Hour,
  within24Hours,
  within3Days,
  future,
}

class HomeCourseOccurrence {
  const HomeCourseOccurrence({
    required this.course,
    required this.meeting,
    required this.startsAt,
    required this.endsAt,
    required this.phase,
  });

  final TimetableCourse course;
  final TimetableMeeting meeting;
  final DateTime startsAt;
  final DateTime endsAt;
  final HomeCoursePhase phase;

  DateTime get campusStartsAt => toBnbuCampusClock(startsAt);

  DateTime get campusEndsAt => toBnbuCampusClock(endsAt);
}

class HomeDeadline {
  const HomeDeadline({
    required this.item,
    required this.dueAt,
    required this.phase,
  });

  final TimelineItem item;
  final DateTime dueAt;
  final HomeDeadlinePhase phase;
}

HomeCourseOccurrence? findNextCourseOccurrence(
  TimetableData? timetable, {
  required DateTime now,
}) {
  if (timetable == null) {
    return null;
  }

  final instantNow = now.toUtc();
  final campusNow = toBnbuCampusClock(instantNow);
  final today = DateTime(campusNow.year, campusNow.month, campusNow.day);
  final occurrences = <HomeCourseOccurrence>[];

  for (final course in timetable.courses) {
    for (final meeting in course.meetings) {
      var meetingDate = BnbuAcademicCalendar.nextMeetingDate(
        timetable: timetable,
        meeting: meeting,
        fromCampusDate: today,
      );
      if (meetingDate == null) continue;
      var startsAt = bnbuCampusClockToUtc(
        meetingDate.add(Duration(minutes: meeting.startMinutes)),
      );
      var endsAt = bnbuCampusClockToUtc(
        meetingDate.add(Duration(minutes: meeting.endMinutes)),
      );
      if (!endsAt.isAfter(instantNow)) {
        meetingDate = BnbuAcademicCalendar.nextMeetingDate(
          timetable: timetable,
          meeting: meeting,
          fromCampusDate: DateTime(
            meetingDate.year,
            meetingDate.month,
            meetingDate.day + 1,
          ),
        );
        if (meetingDate == null) continue;
        startsAt = bnbuCampusClockToUtc(
          meetingDate.add(Duration(minutes: meeting.startMinutes)),
        );
        endsAt = bnbuCampusClockToUtc(
          meetingDate.add(Duration(minutes: meeting.endMinutes)),
        );
      }
      if (!endsAt.isAfter(startsAt)) {
        continue;
      }

      occurrences.add(
        HomeCourseOccurrence(
          course: course,
          meeting: meeting,
          startsAt: startsAt,
          endsAt: endsAt,
          phase: _coursePhase(
            now: instantNow,
            startsAt: startsAt,
            endsAt: endsAt,
          ),
        ),
      );
    }
  }

  if (occurrences.isEmpty) {
    return null;
  }
  occurrences.sort((left, right) {
    final leftInProgress = left.phase == HomeCoursePhase.inProgress;
    final rightInProgress = right.phase == HomeCoursePhase.inProgress;
    if (leftInProgress != rightInProgress) {
      return leftInProgress ? -1 : 1;
    }
    return left.startsAt.compareTo(right.startsAt);
  });
  return occurrences.first;
}

HomeDeadline? findRelevantDeadline(
  Iterable<TimelineItem> items, {
  required DateTime now,
}) {
  final localNow = now.toLocal();
  final upcoming = <({TimelineItem item, DateTime dueAt})>[];
  final overdue = <({TimelineItem item, DateTime dueAt})>[];

  for (final item in items) {
    final dueAt = item.sortTime?.toLocal();
    if (dueAt == null) {
      continue;
    }
    if (item.isOverdue || dueAt.isBefore(localNow)) {
      overdue.add((item: item, dueAt: dueAt));
    } else {
      upcoming.add((item: item, dueAt: dueAt));
    }
  }

  if (upcoming.isNotEmpty) {
    upcoming.sort((left, right) => left.dueAt.compareTo(right.dueAt));
    final selected = upcoming.first;
    return HomeDeadline(
      item: selected.item,
      dueAt: selected.dueAt,
      phase: _deadlinePhase(now: localNow, dueAt: selected.dueAt),
    );
  }
  if (overdue.isEmpty) {
    return null;
  }

  overdue.sort((left, right) => right.dueAt.compareTo(left.dueAt));
  final selected = overdue.first;
  return HomeDeadline(
    item: selected.item,
    dueAt: selected.dueAt,
    phase: HomeDeadlinePhase.overdue,
  );
}

HomeCoursePhase _coursePhase({
  required DateTime now,
  required DateTime startsAt,
  required DateTime endsAt,
}) {
  if (!now.isBefore(startsAt) && now.isBefore(endsAt)) {
    return HomeCoursePhase.inProgress;
  }
  final untilStart = startsAt.difference(now);
  if (untilStart <= const Duration(minutes: 30)) {
    return HomeCoursePhase.within30Minutes;
  }
  if (_isSameDate(toBnbuCampusClock(now), toBnbuCampusClock(startsAt))) {
    return HomeCoursePhase.laterToday;
  }
  return HomeCoursePhase.future;
}

HomeDeadlinePhase _deadlinePhase({
  required DateTime now,
  required DateTime dueAt,
}) {
  if (dueAt.isBefore(now)) {
    return HomeDeadlinePhase.overdue;
  }
  final remaining = dueAt.difference(now);
  if (remaining <= const Duration(hours: 1)) {
    return HomeDeadlinePhase.within1Hour;
  }
  if (remaining <= const Duration(hours: 24)) {
    return HomeDeadlinePhase.within24Hours;
  }
  if (remaining <= const Duration(days: 3)) {
    return HomeDeadlinePhase.within3Days;
  }
  return HomeDeadlinePhase.future;
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
