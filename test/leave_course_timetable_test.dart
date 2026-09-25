import 'dart:async';

import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/models/leave_course_timetable.dart';
import 'package:bnbu_me/services/leave_application_bridge.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/theme/course_color_palette.dart';
import 'package:bnbu_me/widgets/leave_course_picker.dart';
import 'package:bnbu_me/widgets/leave_course_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> row(String key, String time) => {
  'key': key,
  'code': 'DEMO$key',
  'teacher': 'Example teacher $key',
  'type': 'Lecture',
  'units': '3',
  'time': time,
};

LeaveCoursePickerSnapshot snapshot(
  List<Map<String, String>> rows,
  String token,
) => LeaveCoursePickerSnapshot.fromJson({
  'token': token,
  'rowIndex': '4',
  'page': '1/1',
  'candidates': rows,
});

void main() {
  testWidgets(
    'empty hours compress to fit while dense courses retain scrolling',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 620);
      addTearDown(tester.view.reset);
      for (final dense in [false, true]) {
        final rows = dense
            ? [
                for (var h = 8; h < 22; h++)
                  row(
                    '$h',
                    'Mon ${h.toString().padLeft(2, '0')}:00-${(h + 1).toString().padLeft(2, '0')}:00',
                  ),
              ]
            : [
                row('a', 'Mon 08:00-09:00'),
                row('b', 'Tue 10:00-11:00'),
                row('c', 'Wed 14:00-15:00'),
                row('d', 'Thu 18:00-19:00'),
                row('e', 'Fri 21:00-22:00'),
              ];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: LeaveCourseTimetable(
                key: ValueKey(dense),
                candidates: rows,
                selectedCourses: const [],
                onSelected: (_) {},
              ),
            ),
          ),
        );
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('leave-week-vertical')),
            matching: find.byType(Scrollable),
          ),
        );
        if (dense) {
          expect(scroll.position.maxScrollExtent, greaterThan(0));
        } else {
          expect(scroll.position.maxScrollExtent, closeTo(0, .01));
          expect(
            tester
                .getRect(find.byKey(const ValueKey('leave-course-e-5-1260')))
                .bottom,
            lessThanOrEqualTo(620),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final width in [320.0, 390.0, 900.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('course code wraps at letters/digits $width $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.reset);
        final course = {...row('wrap', 'Mon 09:00-09:30'), 'code': 'COMP1003'};
        final choices = <Map<String, String>>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: LeaveCourseTimetable(
                  candidates: [course],
                  selectedCourses: const [],
                  onSelected: choices.add,
                ),
              ),
            ),
          ),
        );
        final block = find.byKey(const ValueKey('leave-course-wrap-1-540'));
        if (width == 900) {
          expect(find.text('COMP1003'), findsOneWidget);
        } else {
          expect(find.text('COMP'), findsOneWidget);
          expect(find.text('1003'), findsOneWidget);
          for (final part in ['COMP', '1003']) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(part),
                matching: find.byType(RichText),
              ),
            );
            expect(paragraph.didExceedMaxLines, isFalse);
          }
          expect(
            tester.getRect(find.text('1003')).top,
            greaterThanOrEqualTo(tester.getRect(find.text('COMP')).bottom),
          );
          expect(
            tester.getRect(find.text('1003')).bottom,
            lessThan(tester.getRect(block).bottom),
          );
        }
        await tester.tap(block);
        expect(identical(choices.single, course), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'course identity ignores display whitespace but never changes class values',
    () {
      final a = row('1001', 'Mon 09:00-09:50; Wed 10:00-10:50');
      expect(
        LeaveCourseTimetableData.sameCourse(a, {
          ...a,
          'teacher': 'Example\n teacher 1001',
          'time': 'Mon 09:00-09:50;\n Wed 10:00-10:50',
        }),
        isTrue,
      );
      expect(
        LeaveCourseTimetableData.sameCourse(a, {
          ...a,
          'time': 'Wednesday 10:00–10:50, Monday 9:00-9:50',
        }),
        isTrue,
      );
      expect(
        LeaveCourseTimetableData.sameCourse(a, {
          ...a,
          'time': 'Tue 09:00-09:50; Wed 10:00-10:50',
        }),
        isFalse,
      );
      expect(
        LeaveCourseTimetableData.sameCourse(a, {
          ...a,
          'time': 'Mon 09:00-09:50',
        }),
        isFalse,
      );
      for (final field in LeaveCourseTimetableData.identityFields) {
        expect(
          LeaveCourseTimetableData.sameCourse(a, {
            ...a,
            field: '${a[field]} other',
          }),
          isFalse,
        );
        expect(
          LeaveCourseTimetableData.sameCourse(a, {...a, field: ''}),
          isFalse,
        );
      }
    },
  );
  testWidgets(
    'compact aligned hours preserve tap targets and complete tooltips',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final course = {
        ...row('1001', 'Mon 09:00-09:50'),
        'code': 'Introduction to Computer Science',
      };
      final late = row('1002', 'Fri 23:00-24:00');
      final choices = <Map<String, String>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveCourseTimetable(
              candidates: [course, late],
              selectedCourses: const [],
              onSelected: choices.add,
            ),
          ),
        ),
      );
      final block = find.byKey(const ValueKey('leave-course-1001-1-540'));
      // Another day has a wrapped code, so all columns share its taller axis.
      expect(tester.getSize(block).height, inInclusiveRange(44, 70));
      expect(find.text('Example teacher 1001 · Lecture'), findsNothing);
      await tester.longPress(block);
      await tester.pumpAndSettle();
      expect(choices, isEmpty);
      expect(
        find.text(
          'Introduction to Computer Science\nExample teacher 1001\nLecture\nMon 09:00-09:50',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('周五'));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('leave-week-vertical')),
          matching: find.byType(Scrollable),
        ),
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('24')).bottom, lessThanOrEqualTo(844));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single-page picker has no footer; next snapshot closes old overlap choices',
    (tester) async {
      final a = row('1001', 'Mon 09:00-09:50');
      final b = row('1002', 'Mon 09:10-10:00');
      final choices = <Map<String, String>>[];
      Future<void> pump(List<Map<String, String>> courses) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveCourseTimetable(
              candidates: courses,
              selectedCourses: const [],
              onSelected: choices.add,
            ),
          ),
        ),
      );
      await pump([a, b]);
      await tester.tap(find.byKey(const ValueKey('leave-overlap-1-540')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('leave-overlap-options')),
        findsOneWidget,
      );
      await pump([row('next', 'Tue 09:00-09:50')]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leave-overlap-options')), findsNothing);
      expect(choices, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveCoursePicker(
              initial: snapshot([a], 'only-page'),
              onPage: (_, _) async =>
                  throw StateError('single-page must not page'),
            ),
          ),
        ),
      );
      expect(find.byTooltip('下一页'), findsNothing);
      expect(find.byTooltip('上一页'), findsNothing);
      expect(find.text('1/1'), findsNothing);
      expect(find.byTooltip('取消'), findsOneWidget);
    },
  );

  test(
    'school times support bilingual multi-meeting schedules without guessing',
    () {
      for (final source in [
        'Mon 09:00-09:50; Thu 10:00-10:50',
        'Monday 09:00–09:50,Thursday10:00–10:50',
        '周一9:00-9:50，星期四10:00-10:50',
        '週一09:00—09:50\n週四10:00—10:50',
      ]) {
        final meetings = LeaveCourseTimetableData.meetings(source);
        expect(meetings.map((m) => m.weekday), [1, 4]);
        expect(meetings.map((m) => m.startMinutes), [540, 600]);
        expect(meetings.map((m) => m.endMinutes), [590, 650]);
      }
      for (final invalid in [
        '',
        'TBA',
        'Mon 25:00-26:00',
        'Mon 09:60-10:00',
        'Mon 10:00-09:00',
        'Mon 09:00-10:00 unknown',
        'Fri 23:00-24:01',
        'MondayTuesday 09:00-10:00',
        'Mon 09:00-10:00; Thu pending',
      ]) {
        expect(
          LeaveCourseTimetableData.meetings(invalid),
          isEmpty,
          reason: invalid,
        );
      }
      expect(
        LeaveCourseTimetableData.meetings('Sun 23:00-24:00').single.endMinutes,
        1440,
      );
      expect(
        LeaveCourseTimetableData.meetings('Mon 09:00-10:00,Mon 09:00-10:00'),
        hasLength(1),
      );
    },
  );

  test('color seed uses only the Portal label and survives page changes', () {
    final a = {...row('a', 'Mon 09:00-09:50'), 'code': 'COMP1003'};
    final b = {
      ...a,
      'key': 'fresh-school-handle',
      'teacher': 'Another teacher',
    };
    expect(LeaveCourseTimetableData.colorSeed(a), 'COMP1003');
    expect(LeaveCourseTimetableData.colorSeed(b), 'COMP1003');
    expect(
      LeaveCourseTimetableData.colorSeed({'code': 'Course 1 (1001)'}),
      'Course 1 (1001)',
    );
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final tokens = theme.extension<BnbuThemeExtension>()!;
      expect(
        CourseColorPalette.fallback(
          LeaveCourseTimetableData.colorSeed(a),
          tokens,
        ),
        CourseColorPalette.fallback(
          LeaveCourseTimetableData.colorSeed(b),
          tokens,
        ),
      );
    }
  });

  testWidgets(
    'Portal times alone compress empty hours and preserve cross-hour classes',
    (tester) async {
      final courses = [
        {...row('a', 'Mon 09:30-10:30'), 'code': 'Alpha'},
        {...row('b', 'Fri 12:00-13:00'), 'code': 'Beta'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveCourseTimetable(
              candidates: courses,
              selectedCourses: const [],
              onSelected: (_) {},
            ),
          ),
        ),
      );
      double y(String hour) => tester.getTopLeft(find.text(hour)).dy;
      final normal = y('10') - y('9');
      expect(y('11') - y('10'), closeTo(normal, .01));
      expect(y('12') - y('11'), closeTo(normal * .5, .01));
      expect(y('13') - y('12'), closeTo(normal, .01));
      final card = tester.getRect(
        find.byKey(const ValueKey('leave-course-a-1-570')),
      );
      expect(card.top, closeTo(y('9') + normal / 2, .01));
      expect(card.height, closeTo(normal, .01));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'five weekday columns preserve meetings, overlaps, unknown times and selected identity',
    (tester) async {
      final selected = row('1001', 'Mon 09:00-10:50; Wed 09:00-10:50');
      final overlap = row('1002', 'Mon 09:00-09:50');
      final other = row('1003', 'TBA');
      final weekend = row('1004', 'Sat 10:00-11:50');
      final choices = <Map<String, String>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveCourseTimetable(
              candidates: [selected, overlap, other, weekend],
              selectedCourses: [selected],
              onSelected: choices.add,
            ),
          ),
        ),
      );
      expect(find.text('周一'), findsOneWidget);
      expect(find.text('周五'), findsOneWidget);
      expect(find.text('周六'), findsNothing);
      expect(find.text('周日'), findsNothing);
      expect(find.text('DEMO1001'), findsOneWidget);
      expect(find.text('已选'), findsOneWidget);
      await tester.tap(find.text('DEMO1001').first);
      expect(choices, isEmpty);
      final first = tester.getRect(
        find.byKey(const ValueKey('leave-weekday-1')),
      );
      for (var day = 2; day <= 5; day++) {
        expect(
          tester.getSize(find.byKey(ValueKey('leave-weekday-$day'))).width,
          first.width,
        );
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('leave-weekday-5'))).right,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
      expect(find.byKey(const ValueKey('leave-course-1003')), findsOneWidget);
      expect(find.byKey(const ValueKey('leave-course-1004')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('leave-overlap-1-540')));
      await tester.pumpAndSettle();
      expect(choices, isEmpty);
      expect(
        find.byKey(const ValueKey('leave-overlap-options')),
        findsOneWidget,
      );
      await tester.tap(find.text('DEMO1001'));
      expect(choices, isEmpty);
      await tester.tap(find.text('DEMO1002'));
      expect(identical(choices.single, overlap), isTrue);
      await tester.tap(find.text('返回课表'));
      await tester.pumpAndSettle();
      expect(find.text('周五'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in [
    'confirmed',
    'unconfirmed',
    'next-browser-failed',
    'dispose',
  ]) {
    testWidgets('continuous selection waits for school readback ($outcome)', (
      tester,
    ) async {
      final course = row('1001', 'Mon 09:00-09:50; Wed 09:00-09:50');
      final second = row('1002', 'Tue 09:00-09:50');
      final initial = snapshot([course], 'old-token');
      final fresh = snapshot([
        {...course, 'key': 'new-key'},
        second,
      ], 'new-token');
      final pending = Completer<LeaveBridgeResult>();
      var choices = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveCoursePicker(
              initial: initial,
              onPage: (_, _) async => throw StateError('unexpected paging'),
              onSelect: (choice) {
                choices++;
                if (choices == 2) {
                  expect(identical(choice.snapshot, fresh), isTrue);
                  expect(choice.candidate['key'], '1002');
                  return Future.value(
                    LeaveBridgeResult(
                      'course_ready',
                      LeaveApplicationForm(
                        fields: const {},
                        courses: [course, second],
                      ),
                      snapshot(fresh.candidates, 'third-token'),
                    ),
                  );
                }
                expect(identical(choice.snapshot, initial), isTrue);
                expect(
                  identical(choice.candidate, course),
                  isFalse,
                ); // immutable decoded copy
                expect(choice.candidate['key'], '1001');
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('DEMO1001').first);
      await tester.pump();
      expect(find.text('已选'), findsNothing);
      expect(find.text('DEMO1001'), findsNWidgets(2));
      expect(
        tester.widget<AbsorbPointer>(find.byType(AbsorbPointer).last).absorbing,
        isTrue,
      );
      if (outcome == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      pending.complete(
        outcome == 'unconfirmed'
            ? const LeaveBridgeResult('selection_unconfirmed')
            : LeaveBridgeResult(
                'course_ready',
                LeaveApplicationForm(fields: const {}, courses: [course]),
                outcome == 'next-browser-failed' ? null : fresh,
              ),
      );
      await tester.pumpAndSettle();
      if (outcome == 'confirmed') {
        expect(find.text('已选'), findsNWidgets(2));
        expect(find.byType(LeaveCoursePicker), findsOneWidget);
        await tester.tap(find.text('DEMO1001').first);
        await tester.pumpAndSettle();
        expect(choices, 1);
        await tester.tap(find.text('DEMO1002'));
        await tester.pumpAndSettle();
        expect(choices, 2);
        expect(find.text('已选'), findsNWidgets(3));
      } else if (outcome == 'unconfirmed') {
        expect(find.text('已选'), findsNothing);
        expect(find.text('返回表单'), findsOneWidget);
        expect(find.text('重新读取课程'), findsNothing);
        expect(choices, 1);
      } else if (outcome == 'next-browser-failed') {
        expect(find.text('课程已加入，请重新读取。'), findsOneWidget);
        expect(find.text('返回表单'), findsOneWidget);
        expect(find.text('重新读取课程'), findsNothing);
        expect(choices, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
