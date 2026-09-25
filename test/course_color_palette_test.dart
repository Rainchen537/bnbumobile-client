import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/theme/course_color_palette.dart';

void main() {
  test(
    'home-only and full schedule palettes keep MIS course colors identical',
    () {
      final timetable = TimetableData(
        profile: TimetableProfile(
          studentId: '',
          name: '',
          programme: '',
          year: '',
        ),
        semesters: const [],
        selectedSemesterId: '',
        selectedSemesterName: '',
        courses: [
          TimetableCourse(
            section: '1',
            category: '',
            code: 'ACC101',
            name: 'Accessible Course',
            teacher: '',
            meetings: const [],
            rooms: const [],
            units: '',
            remark: '',
          ),
        ],
      );
      const taCourse = TaCourseEntry(
        id: 'ta-1',
        title: 'TA Course',
        location: 'T2-101',
        weekday: DateTime.monday,
        startMinutes: 600,
        endMinutes: 650,
        repeatType: TaCourseRepeatType.weekly,
      );
      final tokens = AppTheme.light.extension<BnbuThemeExtension>()!;

      final homePalette = CourseColorPalette.build(timetable, const [], tokens);
      final schedulePalette = CourseColorPalette.build(timetable, const [
        taCourse,
      ], tokens);

      expect(schedulePalette['ACC101'], homePalette['ACC101']);
      expect(
        CourseColorPalette.widgetHex(schedulePalette['ACC101']!),
        CourseColorPalette.widgetHex(homePalette['ACC101']!),
      );
    },
  );
}
