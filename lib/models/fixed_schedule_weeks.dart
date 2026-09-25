import 'academic_calendar.dart';
import 'ta_course_entry.dart';
import 'timetable_data.dart';

/// Teaching dates are a creation-time suggestion, not a recurring holiday veto.
/// Saved choices remain stable when the calendar changes or the user adds weeks.
abstract final class FixedScheduleWeeks {
  static List<DateTime> semesterWeeks(TimetableData? timetable) {
    final semester = timetable == null
        ? null
        : BnbuAcademicCalendar.semesterFor(timetable);
    if (semester == null) return const [];
    final first = TaCourseEntry.normalizeWeekStart(semester.semesterStartsOn);
    final last = TaCourseEntry.normalizeWeekStart(semester.lastClassDay);
    return [
      for (
        var week = first;
        !week.isAfter(last);
        week = DateTime(week.year, week.month, week.day + 7)
      )
        week,
    ];
  }

  /// Null means unavailable, distinct from a known calendar with no eligible dates.
  static List<DateTime>? teachingWeeks(TimetableData? timetable, int weekday) {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(weekday, 'weekday');
    }
    if (timetable == null ||
        BnbuAcademicCalendar.semesterFor(timetable) == null) {
      return null;
    }
    return semesterWeeks(timetable)
        .where((week) {
          final date = DateTime(week.year, week.month, week.day + weekday - 1);
          return BnbuAcademicCalendar.classDayFor(timetable, date).hasClasses;
        })
        .toList(growable: false);
  }
}

/// Display-only context from the selected semester. Calendar week numbers do
/// not skip holidays and never determine a saved schedule's eligibility.
class FixedScheduleWeekContext {
  FixedScheduleWeekContext(DateTime date, BnbuCalendarSemester? semester) {
    if (semester == null) return;
    final week = TaCourseEntry.normalizeWeekStart(date);
    final end = DateTime(week.year, week.month, week.day + 6);
    final first = TaCourseEntry.normalizeWeekStart(semester.semesterStartsOn);
    final last = TaCourseEntry.normalizeWeekStart(semester.lastClassDay);
    startsTeaching = week == first;
    endsTeaching = week == last;
    outsideTeachingTerm = week.isBefore(first) || week.isAfter(last);
    if (!outsideTeachingTerm) {
      weekNumber =
          DateTime.utc(week.year, week.month, week.day)
                  .difference(DateTime.utc(first.year, first.month, first.day))
                  .inDays ~/
              7 +
          1;
    }
    for (final event in semester.events) {
      if (event.kind != BnbuCalendarEventKind.holiday &&
          event.kind != BnbuCalendarEventKind.readingWeek) {
        continue;
      }
      final start = DateTime(
        event.startsOn.year,
        event.startsOn.month,
        event.startsOn.day,
      );
      final finish = DateTime(
        event.endsOn.year,
        event.endsOn.month,
        event.endsOn.day,
      );
      if (start.isAfter(end) || finish.isBefore(week)) continue;
      observances.add((
        event: event,
        startsOn: start.isBefore(week) ? week : start,
        endsOn: finish.isAfter(end) ? end : finish,
      ));
    }
    observances.sort((a, b) => a.startsOn.compareTo(b.startsOn));
  }

  int? weekNumber;
  bool startsTeaching = false;
  bool endsTeaching = false;
  bool outsideTeachingTerm = false;
  final List<({BnbuCalendarEvent event, DateTime startsOn, DateTime endsOn})>
  observances = [];
}
