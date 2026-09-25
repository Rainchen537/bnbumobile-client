import 'academic_calendar.dart';
import 'campus_time.dart';
import 'ta_course_entry.dart';
import 'timeline_item.dart';
import 'timetable_data.dart';
import '../theme/app_theme.dart';
import '../theme/course_color_palette.dart';

class BnbuWidgetCourseOccurrence {
  const BnbuWidgetCourseOccurrence({
    required this.title,
    required this.code,
    required this.room,
    required this.teacher,
    required this.startsAt,
    required this.endsAt,
    required this.isTaCourse,
    this.lightAccentHex = '',
    this.darkAccentHex = '',
  });

  final String title;
  final String code;
  final String room;
  final String teacher;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isTaCourse;
  final String lightAccentHex;
  final String darkAccentHex;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'code': code,
    'room': room,
    'teacher': teacher,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'isTaCourse': isTaCourse,
    'lightAccentHex': lightAccentHex,
    'darkAccentHex': darkAccentHex,
  };
}

class BnbuWidgetDeadline {
  const BnbuWidgetDeadline({
    required this.title,
    required this.courseName,
    required this.dueAt,
  });

  final String title;
  final String courseName;
  final DateTime dueAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'courseName': courseName,
    'dueAt': dueAt.toUtc().toIso8601String(),
  };
}

class BnbuWidgetSnapshot {
  const BnbuWidgetSnapshot({
    required this.generatedAt,
    required this.courses,
    required this.deadlines,
    required this.interfaceLanguage,
  });

  final DateTime generatedAt;
  final List<BnbuWidgetCourseOccurrence> courses;
  final List<BnbuWidgetDeadline> deadlines;
  final String interfaceLanguage;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'campusTimeZone': 'Asia/Shanghai',
    'interfaceLanguage': interfaceLanguage,
    'courses': courses.map((course) => course.toJson()).toList(growable: false),
    'deadlines': deadlines
        .map((deadline) => deadline.toJson())
        .toList(growable: false),
  };
}

BnbuWidgetSnapshot buildBnbuWidgetSnapshot({
  required TimetableData? timetable,
  required Iterable<TimelineItem> timelineItems,
  required Iterable<TaCourseEntry> taCourses,
  required DateTime now,
  String interfaceLanguage = 'en',
  int scheduleDays = 28,
  int deadlineLimit = 12,
}) {
  final taCourseList = taCourses.toList(growable: false);
  final courseSeeds = timetable == null
      ? <String>[]
      : (timetable.courses.map(CourseColorPalette.courseSeed).toSet().toList()
          ..sort());
  final taSeeds =
      taCourseList.map(CourseColorPalette.taCourseSeed).toSet().toList()
        ..sort();
  final lightTokens = AppTheme.light.extension<BnbuThemeExtension>()!;
  final darkTokens = AppTheme.dark.extension<BnbuThemeExtension>()!;
  final lightColors = CourseColorPalette.buildForSeeds(
    courseSeeds,
    taSeeds,
    lightTokens,
  );
  final darkColors = CourseColorPalette.buildForSeeds(
    courseSeeds,
    taSeeds,
    darkTokens,
  );
  final campusNow = toBnbuCampusClock(now);
  final currentWeekStart = DateTime(
    campusNow.year,
    campusNow.month,
    campusNow.day - campusNow.weekday + 1,
  );
  final courses = <BnbuWidgetCourseOccurrence>[];

  if (timetable != null) {
    for (var offset = 0; offset < scheduleDays; offset++) {
      final date = DateTime(
        currentWeekStart.year,
        currentWeekStart.month,
        currentWeekStart.day + offset,
      );
      final sourceWeekday = BnbuAcademicCalendar.classDayFor(
        timetable,
        date,
      ).sourceWeekday;
      if (sourceWeekday == null) {
        continue;
      }
      for (final course in timetable.courses) {
        final colorSeed = CourseColorPalette.courseSeed(course);
        for (final meeting in course.meetings) {
          if (meeting.weekday != sourceWeekday) {
            continue;
          }
          courses.add(
            BnbuWidgetCourseOccurrence(
              title: course.name.trim().isEmpty
                  ? course.code.trim()
                  : course.name.trim(),
              code: course.code.trim(),
              room: meeting.room.trim(),
              teacher: course.teacher.trim(),
              startsAt: _campusMinutesToUtc(date, meeting.startMinutes),
              endsAt: _campusMinutesToUtc(date, meeting.endMinutes),
              isTaCourse: false,
              lightAccentHex: CourseColorPalette.widgetHex(
                lightColors[colorSeed] ??
                    CourseColorPalette.fallback(colorSeed, lightTokens),
              ),
              darkAccentHex: CourseColorPalette.widgetHex(
                darkColors[colorSeed] ??
                    CourseColorPalette.fallback(colorSeed, darkTokens),
              ),
            ),
          );
        }
      }
    }
  }

  for (var offset = 0; offset < scheduleDays; offset += 7) {
    final weekStart = DateTime(
      currentWeekStart.year,
      currentWeekStart.month,
      currentWeekStart.day + offset,
    );
    for (final taCourse in taCourseList) {
      if (!taCourse.appliesToWeek(weekStart) ||
          !taCourse.isVisibleIn(timetable)) {
        continue;
      }
      final date = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day + taCourse.weekday - 1,
      );
      final colorSeed = CourseColorPalette.taCourseSeed(taCourse);
      courses.add(
        BnbuWidgetCourseOccurrence(
          title: taCourse.displayTitle,
          code: taCourse.isTa ? taCourse.courseCode : '',
          room: taCourse.displayLocation,
          teacher: '',
          startsAt: _campusMinutesToUtc(date, taCourse.startMinutes),
          endsAt: _campusMinutesToUtc(date, taCourse.endMinutes),
          isTaCourse: taCourse.isTa,
          lightAccentHex: CourseColorPalette.widgetHex(
            lightColors[colorSeed] ??
                CourseColorPalette.fallback(colorSeed, lightTokens),
          ),
          darkAccentHex: CourseColorPalette.widgetHex(
            darkColors[colorSeed] ??
                CourseColorPalette.fallback(colorSeed, darkTokens),
          ),
        ),
      );
    }
  }

  courses.sort((left, right) => left.startsAt.compareTo(right.startsAt));

  final deadlines =
      timelineItems
          .where(
            (item) =>
                item.sortTime != null &&
                !item.isOverdue &&
                !item.sortTime!.isBefore(now),
          )
          .map(
            (item) => BnbuWidgetDeadline(
              title: item.title.trim(),
              courseName: item.courseName.trim(),
              dueAt: item.sortTime!,
            ),
          )
          .toList(growable: false)
        ..sort((left, right) => left.dueAt.compareTo(right.dueAt));

  return BnbuWidgetSnapshot(
    generatedAt: now,
    courses: List.unmodifiable(courses),
    deadlines: List.unmodifiable(deadlines.take(deadlineLimit)),
    interfaceLanguage: interfaceLanguage,
  );
}

DateTime _campusMinutesToUtc(DateTime campusDate, int minutes) {
  final campusClock = DateTime(
    campusDate.year,
    campusDate.month,
    campusDate.day,
    minutes ~/ 60,
    minutes % 60,
  );
  return bnbuCampusClockToUtc(campusClock);
}
