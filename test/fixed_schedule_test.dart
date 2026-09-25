import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/schedule_grid_geometry.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/theme/course_color_palette.dart';
import 'package:bnbu_me/widgets/fixed_schedule_editor.dart';

TimetableData fixture() => TimetableData(
  profile: TimetableProfile(studentId: '', name: '', programme: '', year: ''),
  semesters: [],
  selectedSemesterId: '2026-1',
  selectedSemesterName: '2026',
  courses: [
    TimetableCourse(
      section: '1',
      category: '',
      code: 'COMP1',
      name: 'Computer Organisation',
      teacher: 'Alex',
      meetings: [],
      rooms: [],
      units: '',
      remark: '',
    ),
  ],
);

void main() {
  test(
    'old unbound TA data migrates losslessly to an independent schedule',
    () {
      final entry = TaCourseEntry.fromJson({
        'id': 'old',
        'title': 'Workshop',
        'location': 'T1',
        'weekday': 3,
        'startMinutes': 720,
        'endMinutes': 780,
        'repeatType': 'singleWeek',
        'weekStart': '2026-09-07',
        'revision': 4,
      });
      expect(entry.kind, FixedScheduleKind.schedule);
      expect(entry.revision, 4);
      expect(entry.toJson()['kind'], 'schedule');
      expect(
        TaCourseEntry.fromJson(entry.toJson()).hasSameCourseFields(entry),
        isTrue,
      );
      expect(entry.appliesToWeek(DateTime(2026, 9, 7)), isTrue);
      expect(entry.appliesToWeek(DateTime(2026, 9, 14)), isFalse);
    },
  );
  test('TA requires a binding and shares the exact parent course color', () {
    final timetable = fixture();
    final course = timetable.courses.single;
    final entry = TaCourseEntry(
      id: 'ta',
      title: course.name,
      location: '',
      weekday: 2,
      startMinutes: 540,
      endMinutes: 590,
      repeatType: TaCourseRepeatType.weekly,
      kind: FixedScheduleKind.ta,
      courseKey: TaCourseEntry.bindingKey(timetable, course),
      courseCode: course.code,
      semesterId: timetable.selectedSemesterId,
    );
    entry.validate();
    expect(entry.resolveCourse(timetable), same(course));
    expect(
      entry.copyWith(semesterId: 'other').resolveCourse(timetable),
      isNull,
    );
    expect(
      () => entry.copyWith(courseKey: '').validate(),
      throwsFormatException,
    );
    final colors = CourseColorPalette.build(timetable, [
      entry,
    ], AppTheme.light.extension<BnbuThemeExtension>()!);
    expect(
      colors[CourseColorPalette.taCourseSeed(entry)],
      colors[CourseColorPalette.courseSeed(course)],
    );
    expect(colors.length, 1);
  });
  test('compressed rows stay aligned and do not shift time boundaries', () {
    final grid = ScheduleGridGeometry(
      startMinutes: 480,
      endMinutes: 1320,
      availableHeight: 700,
      occupiedRanges: const [
        (startMinutes: 480, endMinutes: 720),
        (startMinutes: 780, endMinutes: 1080),
        (startMinutes: 1140, endMinutes: 1320),
      ],
    );
    expect(grid.offsetFor(480), 0);
    expect(grid.offsetFor(1320), closeTo(700, .00001));
    expect(grid.rowHeight(4) / grid.rowHeight(3), closeTo(.5, .00001));
    expect(grid.rowHeight(10) / grid.rowHeight(9), closeTo(.5, .00001));
    expect(
      grid.offsetFor(750),
      closeTo((grid.offsetFor(720) + grid.offsetFor(780)) / 2, .00001),
    );
    final occupied = ScheduleGridGeometry(
      startMinutes: 480,
      endMinutes: 1320,
      availableHeight: 700,
      occupiedRanges: const [
        (startMinutes: 480, endMinutes: 1080),
        (startMinutes: 1140, endMinutes: 1320),
      ],
    );
    expect(occupied.rowHeight(4), closeTo(occupied.rowHeight(3), .00001));
  });
  testWidgets('editor survives a negative keyboard transition inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: MediaQuery(
            data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: -80)),
            child: FixedScheduleEditor(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('fixed-schedule-title')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('fixed-schedule-title')),
      'Study',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'week picker returns a whole Monday week across a year boundary',
    (tester) async {
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showFixedScheduleWeekPicker(
                  context,
                  initialWeek: DateTime(2026, 12, 28),
                );
              },
              child: const Text('pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('fixed-schedule-week-2027-1-4')),
      );
      await tester.pumpAndSettle();
      expect(selected, DateTime(2027, 1, 4));
      expect(fixedScheduleWeekLabel(selected!), '1/4 – 1/10');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TA editor refuses an unbound save then returns a real course binding',
    (tester) async {
      TaCourseEntry? result;
      final timetable = fixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<TaCourseEntry>(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: FixedScheduleEditor(timetable: timetable),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixed-schedule-kind-ta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ta-course-editor-save')));
      await tester.pumpAndSettle();
      expect(find.text('请选择所属课程'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.byKey(const ValueKey('fixed-schedule-course')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('fixed-schedule-course-COMP1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ta-course-editor-save')));
      await tester.pumpAndSettle();
      expect(result!.isTa, isTrue);
      expect(result!.title, 'Computer Organisation');
      expect(result!.resolveCourse(timetable), same(timetable.courses.single));
      expect(tester.takeException(), isNull);
    },
  );
}
