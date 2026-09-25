import 'dart:io';
import 'dart:ui' as ui;

import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/pages/schedule_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _preview = bool.fromEnvironment('SCHEDULE_LAYOUT_PREVIEWS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (!_preview) return;
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (!font.existsSync()) return;
    final bytes = ByteData.sublistView(await font.readAsBytes());
    final chineseFont = File('/System/Library/Fonts/STHeiti Light.ttc');
    final chinese = chineseFont.existsSync()
        ? ByteData.sublistView(await chineseFont.readAsBytes())
        : null;
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      final loader = FontLoader(family)..addFont(Future.value(bytes));
      await loader.load();
    }
    if (chinese != null) {
      await (FontLoader(
        'SchedulePreviewCJK',
      )..addFont(Future.value(chinese))).load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
          rootBundle.load(
            'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
          ),
        ))
        .load();
  });

  Future<(TaCourseController, AppThemeModeController)> pump(
    WidgetTester tester, {
    required Size size,
    required TargetPlatform platform,
    List<TimetableMeeting> meetings = const [],
    List<TimelineItem> deadlines = const [],
    List<TaCourseEntry> entries = const [],
    DateTime? now,
    double scale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final session = _Session(meetings, deadlines);
    final ta = TaCourseController(sessionController: session);
    final appearance = AppThemeModeController(
      liquidGlassSupportLoader: () async => true,
    );
    await appearance.restore();
    await ta.ensureLoaded();
    for (final entry in entries) {
      expect(
        (await ta.addEntry(entry, expectedRevision: ta.revision)).isSuccess,
        isTrue,
      );
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
      ta.dispose();
      session.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: platform,
          textTheme: _preview
              ? (dark ? AppTheme.dark : AppTheme.light).textTheme.apply(
                  fontFamilyFallback: const ['SchedulePreviewCJK'],
                )
              : null,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: BnbuLiquidGlassScope(controller: appearance, child: child!),
        ),
        home: RepaintBoundary(
          key: const ValueKey('schedule-layout-preview'),
          child: SchedulePage(
            controller: session,
            taCourseController: ta,
            now: now ?? DateTime.utc(2026, 12, 21, 8, 30),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (ta, appearance);
  }

  Rect rect(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));
  double row(WidgetTester tester, int hour) =>
      rect(tester, 'schedule-hour-${hour * 60}').height;

  for (final (size, platform) in [
    (const Size(390, 844), TargetPlatform.iOS),
    (const Size(390, 844), TargetPlatform.android),
    (const Size(820, 1180), TargetPlatform.iOS),
    (const Size(1180, 820), TargetPlatform.iOS),
    (const Size(1440, 900), TargetPlatform.macOS),
    (const Size(900, 900), TargetPlatform.windows),
  ]) {
    for (final endHour in [22, 23, 24]) {
      testWidgets(
        '$platform $size terminal $endHour shares the last occupied row',
        (tester) async {
          await pump(
            tester,
            size: size,
            platform: platform,
            meetings: [
              _meeting(1, 570, 690), // 9:30–11:30: all three rows are occupied
              _meeting(3, (endHour - 1) * 60, endHour * 60),
            ],
          );
          final normal = row(tester, 9);
          for (var hour = 8; hour < endHour; hour++) {
            expect(
              row(tester, hour),
              closeTo(
                normal * ({9, 10, 11, endHour - 1}.contains(hour) ? 1 : .5),
                .001,
              ),
            );
            final line = rect(tester, 'schedule-grid-line-${hour * 60}');
            expect(
              line.top,
              closeTo(rect(tester, 'schedule-hour-${hour * 60}').top, .001),
            );
          }
          final axis = rect(tester, 'schedule-grid-time-axis');
          final last = rect(tester, 'schedule-hour-${(endHour - 1) * 60}');
          expect(last.bottom, closeTo(axis.bottom, .001));
          expect(
            rect(tester, 'schedule-grid-line-${endHour * 60}').bottom,
            closeTo(axis.bottom, .001),
          );
          final terminal = find.byKey(const ValueKey('schedule-end-hour'));
          expect(tester.widget<Text>(terminal).data, '$endHour');
          expect(tester.getRect(terminal).bottom, closeTo(axis.bottom, .001));
          expect(tester.getRect(terminal).top, greaterThan(last.top));
          expect(
            tester.getRect(terminal).bottom,
            lessThanOrEqualTo(size.height + .001),
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: terminal, matching: find.byType(RichText)),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          final course = rect(tester, 'schedule-course-block-1-570-CHECK');
          expect(
            course.top,
            closeTo(rect(tester, 'schedule-hour-540').top + normal / 2, .001),
          );
          expect(
            course.bottom,
            closeTo(rect(tester, 'schedule-hour-660').top + normal / 2, .001),
          );
          expect(
            rect(
              tester,
              'schedule-course-block-3-${(endHour - 1) * 60}-CHECK',
            ).bottom,
            closeTo(axis.bottom, .001),
          );
          final nowLine = find.bySemanticsLabel('当前时间 16:30');
          expect(nowLine, findsOneWidget);
          expect(
            tester.getRect(nowLine).center.dy,
            closeTo(
              rect(tester, 'schedule-hour-960').top + row(tester, 16) / 2,
              .001,
            ),
          );
          expect(tester.takeException(), isNull);
          if (_preview && endHour == 24 && platform != TargetPlatform.windows) {
            await _savePreview(
              tester,
              '${platform.name}-${size.width.toInt()}-24',
            );
          }
        },
      );
    }
  }

  testWidgets(
    'DDL alone keeps equal rows filling the available height including the final minute',
    (tester) async {
      await pump(
        tester,
        size: const Size(390, 844),
        platform: TargetPlatform.iOS,
        deadlines: [_deadline(23, 59)],
      );
      final normal = (844 - 44 - 26) / 16;
      for (var hour = 8; hour < 24; hour++) {
        expect(row(tester, hour), closeTo(normal, .001));
      }
      final axis = rect(tester, 'schedule-grid-time-axis');
      expect(axis.height, closeTo(844 - 44 - 26, .001));
      final ddl = find.byKey(const ValueKey('schedule-deadline-77'));
      expect(ddl, findsOneWidget);
      expect(tester.getRect(ddl).bottom, lessThanOrEqualTo(axis.bottom));
      final hit = rect(tester, 'schedule-deadline-hit-77');
      expect(hit.height, greaterThanOrEqualTo(44));
      expect(hit.bottom, lessThanOrEqualTo(axis.bottom));
      expect(hit.top, greaterThanOrEqualTo(axis.top));
      await tester.tap(ddl);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('schedule-deadline-detail-modal')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DDL and hit area follow interpolation inside an idle hour', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(390, 844),
      platform: TargetPlatform.iOS,
      meetings: [_meeting(1, 570, 690)],
      deadlines: [_deadline(12, 30)],
    );
    final normal = (844 - 44 - 26) / (3 + 11 * .5);
    expect(row(tester, 12), closeTo(normal * .5, .001));
    final marker = rect(tester, 'schedule-deadline-77');
    expect(
      marker.top,
      closeTo(
        rect(tester, 'schedule-hour-720').top + row(tester, 12) / 2,
        .001,
      ),
    );
    final hit = rect(tester, 'schedule-deadline-hit-77');
    expect(hit.center, marker.center);
    await tester.tapAt(hit.topCenter + const Offset(0, 2));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-deadline-detail-modal')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty week and changing fixed schedules preserve full height and relative weights',
    (tester) async {
      final (ta, _) = await pump(
        tester,
        size: const Size(390, 844),
        platform: TargetPlatform.iOS,
      );
      var normal = (844 - 44 - 26) / 14;
      for (var hour = 8; hour < 22; hour++) {
        expect(row(tester, hour), closeTo(normal, .001));
      }
      for (final (id, day, start, end, kind) in [
        ('study', 7, 750, 810, FixedScheduleKind.schedule),
        ('ta', 2, 1135, 1140, FixedScheduleKind.ta),
      ]) {
        final timetable = _Session.timetableFor([]);
        final course = timetable.courses.first;
        expect(
          (await ta.addEntry(
            TaCourseEntry(
              id: id,
              title: id,
              location: '',
              weekday: day,
              startMinutes: start,
              endMinutes: end,
              repeatType: TaCourseRepeatType.weekly,
              kind: kind,
              courseKey: kind == FixedScheduleKind.ta
                  ? TaCourseEntry.bindingKey(timetable, course)
                  : '',
              courseCode: kind == FixedScheduleKind.ta ? course.code : '',
              semesterId: kind == FixedScheduleKind.ta
                  ? timetable.selectedSemesterId
                  : '',
            ),
            expectedRevision: ta.revision,
          )).isSuccess,
          isTrue,
        );
        await tester.pumpAndSettle();
      }
      normal = (844 - 44 - 26) / (3 + 11 * .5);
      for (var hour = 8; hour < 22; hour++) {
        expect(
          row(tester, hour),
          closeTo(normal * ({12, 13, 18}.contains(hour) ? 1 : .5), .001),
        );
      }
      final study = rect(tester, 'schedule-course-block-7-750-schedule:study');
      expect(
        study.top,
        closeTo(rect(tester, 'schedule-hour-720').top + normal / 2, .001),
      );
      expect(study.height, closeTo(normal, .001));
      await tester.tap(
        find.byKey(
          const ValueKey('schedule-course-block-7-750-schedule:study'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('schedule-course-detail-modal')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      Navigator.of(
        tester.element(
          find.byKey(const ValueKey('schedule-course-detail-modal')),
        ),
      ).pop();
      await tester.pumpAndSettle();
      for (final id in ['study', 'ta']) {
        expect(
          (await ta.deleteEntry(
            id,
            expectedRevision: ta.entries
                .singleWhere((entry) => entry.id == id)
                .revision,
          )).isSuccess,
          isTrue,
        );
      }
      await tester.pumpAndSettle();
      normal = (844 - 44 - 26) / 14;
      for (var hour = 8; hour < 22; hour++) {
        expect(row(tester, hour), closeTo(normal, .001));
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final endHour in [22, 23, 24]) {
    testWidgets(
      'short final course retains exact paint and full hit area at $endHour',
      (tester) async {
        await pump(
          tester,
          size: const Size(390, 844),
          platform: TargetPlatform.iOS,
          meetings: [
            _meeting(1, 480, 485),
            _meeting(1, endHour * 60 - 5, endHour * 60),
          ],
          scale: endHour == 23 ? 2 : 1,
        );
        final axis = rect(tester, 'schedule-grid-time-axis');
        final first = rect(tester, 'schedule-course-block-1-480-CHECK');
        expect(
          first.top,
          closeTo(axis.top, .001),
          reason: 'minimum hit target must not move the painted start',
        );
        final key = ValueKey(
          'schedule-course-block-1-${endHour * 60 - 5}-CHECK',
        );
        final block = find.byKey(key);
        final hit = find
            .ancestor(of: block, matching: find.byType(InkWell))
            .first;
        expect(tester.getRect(block).bottom, closeTo(axis.bottom, .001));
        expect(tester.getRect(hit).bottom, closeTo(axis.bottom, .001));
        expect(tester.getRect(hit).height, greaterThanOrEqualTo(44));
        await tester.ensureVisible(hit);
        await tester.pumpAndSettle();
        final end = find.byKey(const ValueKey('schedule-end-hour'));
        await tester.ensureVisible(end);
        await tester.pumpAndSettle();
        expect(tester.getRect(end).bottom, lessThanOrEqualTo(844.001));
        await tester.tapAt(tester.getRect(hit).topCenter + const Offset(0, 5));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('schedule-course-detail-modal')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    for (final (size, platform) in [
      (const Size(390, 844), TargetPlatform.iOS),
      (const Size(820, 1180), TargetPlatform.iOS),
      (const Size(1180, 820), TargetPlatform.iOS),
      (const Size(1440, 900), TargetPlatform.macOS),
    ]) {
      testWidgets(
        'solid toolbar stays centered with asymmetric controls $size $platform dark=$dark',
        (tester) async {
          final (_, appearance) = await pump(
            tester,
            size: size,
            platform: platform,
            dark: dark,
          );
          final toolbar = find.byKey(const ValueKey('schedule-toolbar'));
          final original = tester.getRect(toolbar);
          for (final enabled in [true, false, true]) {
            await appearance.setLiquidGlassEnabled(enabled);
            await tester.pumpAndSettle();
            expect(appearance.liquidGlassEnabled, enabled);
            final surface =
                tester.widget<DecoratedBox>(toolbar).decoration
                    as BoxDecoration;
            expect(
              surface.color,
              (dark ? AppTheme.dark : AppTheme.light)
                  .extension<BnbuThemeExtension>()!
                  .surface,
            );
            expect(surface.color!.a, 1);
            final dateStyle = tester
                .widget<Text>(
                  find.byKey(const ValueKey('schedule-week-range-label')),
                )
                .style!;
            final colors = (dark ? AppTheme.dark : AppTheme.light)
                .extension<BnbuThemeExtension>()!;
            expect(dateStyle.color, dark ? colors.brandBlue : colors.info);
            expect(
              find.ancestor(
                of: toolbar,
                matching: find.byType(BnbuLiquidGlassSurface),
              ),
              findsNothing,
            );
            expect(tester.getRect(toolbar), original);
            for (var week = 0; week < 2; week++) {
              expect(
                find.descendant(
                  of: toolbar,
                  matching: find.byIcon(LucideIcons.calendarRange300),
                ),
                findsNothing,
              );
              final date = rect(tester, 'schedule-week-range-label');
              expect(
                rect(tester, 'schedule-week-range-label').center.dx,
                closeTo(original.center.dx, .01),
              );
              expect(date.center.dy, closeTo(original.center.dy, .01));
              await tester.ensureVisible(
                find.byKey(const ValueKey('schedule-next-week')),
              );
              await tester.tap(
                find.byKey(const ValueKey('schedule-next-week')),
              );
              await tester.pumpAndSettle();
            }
          }
          if (_preview) {
            await _savePreview(
              tester,
              '${platform.name}-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'large text starts centered and recenters after resize $width',
      (tester) async {
        await pump(
          tester,
          size: Size(width, 844),
          platform: TargetPlatform.iOS,
          scale: 2,
          now: DateTime.utc(2026, 12, 28, 8),
        );
        for (final size in [
          Size(width, 844),
          const Size(820, 1180),
          Size(width, 844),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          final toolbar = rect(tester, 'schedule-toolbar');
          final label = rect(tester, 'schedule-week-range-label');
          expect(label.center.dx, closeTo(toolbar.center.dx, .01));
          expect(label.center.dy, closeTo(toolbar.center.dy, .01));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

Future<void> _savePreview(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('schedule-layout-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/schedule-layout-previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

TimetableMeeting _meeting(int day, int start, int end) => TimetableMeeting(
  weekday: day,
  dayLabel: 'Day',
  startLabel: TaCourseEntry.formatMinutes(start),
  endLabel: TaCourseEntry.formatMinutes(end),
  startMinutes: start,
  endMinutes: end,
  room: 'Room',
);

TimelineItem _deadline(int hour, int minute) => TimelineItem(
  id: 77,
  title: 'Deadline',
  activityState: '',
  moduleName: 'assign',
  courseId: 1,
  instanceId: 1,
  isOverdue: false,
  activityType: 'assign',
  courseName: 'Course',
  sortTime: DateTime(2026, 12, 21, hour, minute),
  formattedTime: '',
  url: '',
  description: '',
);

class _Session extends AppSessionController {
  _Session(this.meetings, this.deadlines);
  final List<TimetableMeeting> meetings;
  final List<TimelineItem> deadlines;
  @override
  bool get isLoggedIn => true;
  @override
  String get username => 'layout-fixture';
  @override
  TimetableData get timetable => timetableFor(meetings);
  static TimetableData timetableFor(List<TimetableMeeting> meetings) =>
      TimetableData(
        profile: TimetableProfile(
          studentId: '',
          name: '',
          programme: '',
          year: '',
        ),
        semesters: const [],
        selectedSemesterId: 'fixture',
        selectedSemesterName: 'fixture',
        courses: [
          TimetableCourse(
            section: '1',
            category: '',
            code: 'CHECK',
            name: 'Example course',
            teacher: '',
            meetings: meetings,
            rooms: const [],
            units: '',
            remark: '',
          ),
        ],
      );
  @override
  List<TimelineItem> get timelineItems => deadlines;
  @override
  bool get isLoadingTimetable => false;
  @override
  String? get timetableError => null;
  @override
  Future<void> refreshTimetable() async {}
  @override
  Future<void> refreshTimeline() async {}
}
