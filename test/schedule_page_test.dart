import 'dart:async';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/widgets/moodle_activity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bnbu_me/models/exam_timetable.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/teacher_review.dart';
import 'package:bnbu_me/pages/campus_directory_page.dart';
import 'package:bnbu_me/pages/schedule_page.dart';
import 'package:bnbu_me/pages/timeline_detail_page.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/services/teacher_review_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';
import 'package:bnbu_me/widgets/schedule_holiday_panel.dart';
import 'package:bnbu_me/widgets/bnbu_loading.dart';
import 'package:bnbu_me/widgets/timeline_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final (size, endHour, scale, glass, highContrast) in [
    (const Size(375, 812), 22, 1.0, true, false),
    (const Size(390, 844), 23, 1.0, true, false),
    (const Size(402, 874), 24, 1.0, true, false),
    (const Size(390, 844), 22, 1.6, true, false),
    (const Size(390, 844), 22, 1.0, false, false),
    (const Size(390, 844), 22, 1.0, true, true),
  ]) {
    testWidgets('dock clearance preserves grid height and reveals late course '
        '$size end=$endHour scale=$scale glass=$glass contrast=$highContrast', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
      final base = _timetable();
      final start = (endHour - 3) * 60;
      final lateCourse = TimetableCourse(
        section: '1',
        category: 'Core',
        code: 'LATE101',
        name: 'Late course',
        teacher: 'Teacher',
        meetings: [
          TimetableMeeting(
            weekday: DateTime.tuesday,
            dayLabel: 'Tue',
            startLabel: '${endHour - 3}:00',
            endLabel: '${endHour - 1}:50',
            startMinutes: start,
            endMinutes: endHour * 60 - 10,
            room: 'TH-208',
          ),
        ],
        rooms: const ['TH-208'],
        units: '3',
        remark: '',
      );
      final session = _ScheduleSessionController(
        timetable: TimetableData(
          profile: base.profile,
          semesters: base.semesters,
          selectedSemesterId: base.selectedSemesterId,
          selectedSemesterName: base.selectedSemesterName,
          courses: [...base.courses, lateCourse],
        ),
        timelineItems: [],
      );
      final ta = TaCourseController(sessionController: session);
      final shell = RootShellController()..selectTab(AppTab.schedule);
      final mail = MailAssistantIntentController();
      final appearance = AppThemeModeController(
        liquidGlassSupportLoader: () async => true,
      );
      await appearance.restore();
      await appearance.setLiquidGlassEnabled(glass);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        ta.dispose();
        session.dispose();
        shell.dispose();
        mail.dispose();
        appearance.dispose();
        tester.view.reset();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: (endHour == 23 ? AppTheme.dark : AppTheme.light).copyWith(
            platform: TargetPlatform.iOS,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              highContrast: highContrast,
              textScaler: TextScaler.linear(scale),
            ),
            child: BnbuLiquidGlassScope(controller: appearance, child: child!),
          ),
          home: RootShellPage(
            controller: session,
            shellController: shell,
            taCourseController: ta,
            mailIntentController: mail,
            pageOverrideBuilder: (tab) => tab == AppTab.schedule
                ? SchedulePage(
                    controller: session,
                    taCourseController: ta,
                    directoryService: _TeacherLinkDirectoryService(),
                    now: DateTime.utc(2026, 7, 27, 1),
                  )
                : const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final extendsBehindDock = glass && !highContrast;
      final root = tester.widget<Scaffold>(
        find.byKey(const ValueKey('root-compact-scaffold')),
      );
      expect(root.extendBody, extendsBehindDock);
      final terminal = find.byKey(const ValueKey('schedule-end-hour'));
      expect(tester.widget<Text>(terminal).data, '$endHour');
      final navigation = find.byKey(const ValueKey('root-bottom-navigation'));
      final dockBounds = tester.getRect(navigation);
      final clearance = find.byKey(
        const ValueKey('schedule-bottom-scroll-clearance'),
        skipOffstage: false,
      );
      final late = find.byKey(
        ValueKey('schedule-course-block-2-$start-LATE101'),
      );
      final lateHeight = tester.getSize(late).height;
      if (extendsBehindDock) {
        expect(clearance, findsOneWidget);
        final inset = MediaQuery.paddingOf(
          tester.element(find.byType(SchedulePage)),
        ).bottom;
        expect(tester.getSize(clearance).height, closeTo(inset + 12, .01));
        if (scale == 1) {
          expect(
            tester.getRect(terminal).bottom,
            closeTo(size.height, .01),
            reason: 'Dock must not reduce the full-height timetable canvas',
          );
          // System safe-area changes alter clearance, not the time geometry.
          tester.view.padding = const FakeViewPadding(top: 62);
          tester.view.viewPadding = const FakeViewPadding(top: 62);
          await tester.pumpAndSettle();
          final changedInset = MediaQuery.paddingOf(
            tester.element(find.byType(SchedulePage)),
          ).bottom;
          expect(
            tester.getSize(clearance).height,
            closeTo(changedInset + 12, .01),
          );
          expect(tester.getSize(late).height, closeTo(lateHeight, .01));
          tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
          tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
          await tester.pumpAndSettle();
        }
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(terminal).bottom, lessThan(dockBounds.top));
        expect(tester.getRect(late).bottom, lessThan(dockBounds.top));
        expect(tester.getSize(late).height, closeTo(lateHeight, .01));
        expect(tester.getRect(navigation), dockBounds);
        await tester.tap(late);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('schedule-course-detail-modal')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        expect(tester.getRect(terminal).bottom, lessThan(dockBounds.top));
        expect(tester.getSize(late).height, closeTo(lateHeight, .01));
        shell.selectTab(AppTab.mail);
        await tester.pumpAndSettle();
        shell.selectTab(AppTab.schedule);
        await tester.pumpAndSettle();
        expect(tester.getRect(terminal).bottom, lessThan(dockBounds.top));
        expect(tester.getSize(late).height, closeTo(lateHeight, .01));
        if (endHour == 22 && scale == 1) {
          await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
          await tester.pumpAndSettle();
          final listLabel = tester
              .element(find.byType(SchedulePage))
              .l10n
              .text('课表竖表视图');
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == listLabel,
            ),
            findsOneWidget,
          );
          expect(clearance, findsOneWidget);
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -8000),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(clearance).top, lessThan(dockBounds.top));
          expect(tester.getRect(navigation), dockBounds);
        }
      } else {
        expect(clearance, findsNothing);
        expect(
          tester.getRect(terminal).bottom,
          lessThanOrEqualTo(dockBounds.top),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, platform, glass) in [
    (const Size(390, 844), TargetPlatform.iOS, false),
    (const Size(402, 874), TargetPlatform.iOS, false),
    (const Size(390, 844), TargetPlatform.android, false),
    (const Size(900, 1000), TargetPlatform.iOS, false),
    (const Size(1440, 900), TargetPlatform.macOS, false),
    (const Size(375, 812), TargetPlatform.iOS, true),
    (const Size(390, 844), TargetPlatform.iOS, true),
  ]) {
    testWidgets(
      'schedule modals preserve root layout at $size on $platform glass=$glass',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
        final session = _ScheduleSessionController(
          timetable: _timetable(),
          timelineItems: [_deadline(due: DateTime(2026, 7, 27, 10))],
        );
        final ta = TaCourseController(sessionController: session);
        final shell = RootShellController()..selectTab(AppTab.schedule);
        final mail = MailAssistantIntentController();
        final appearance = AppThemeModeController(
          liquidGlassSupportLoader: () async => true,
        );
        await appearance.restore();
        await appearance.setLiquidGlassEnabled(glass);
        addTearDown(appearance.dispose);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          ta.dispose();
          session.dispose();
          shell.dispose();
          mail.dispose();
          tester.view.reset();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: (glass ? AppTheme.dark : AppTheme.light).copyWith(
              platform: platform,
            ),
            builder: (context, child) =>
                BnbuLiquidGlassScope(controller: appearance, child: child!),
            home: RootShellPage(
              controller: session,
              shellController: shell,
              taCourseController: ta,
              mailIntentController: mail,
              pageOverrideBuilder: (tab) => tab == AppTab.schedule
                  ? SchedulePage(
                      controller: session,
                      taCourseController: ta,
                      directoryService: _TeacherLinkDirectoryService(),
                      now: DateTime.utc(2026, 7, 27, 1),
                    )
                  : const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Rect hour(int value) => tester.getRect(
          find.descendant(
            of: find
                .byKey(
                  const ValueKey('schedule-week-translation'),
                  skipOffstage: false,
                )
                .first,
            matching: find.byKey(
              ValueKey('schedule-hour-${value * 60}'),
              skipOffstage: false,
            ),
          ),
        );
        final before = [for (var h = 8; h < 22; h++) hour(h)];
        final navigation = find.byKey(
          ValueKey(
            size.width < 700
                ? 'root-bottom-navigation'
                : 'root-side-navigation-panel',
          ),
          skipOffstage: false,
        );
        final navigationBounds = tester.getRect(navigation);
        if (size.width < 700) {
          if (glass) {
            expect(
              hour(21).bottom,
              closeTo(size.height, .001),
              reason:
                  'glass overlays the full-height canvas without shrinking rows',
            );
            final scrollable = tester.state<ScrollableState>(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Scrollable &&
                        widget.axisDirection == AxisDirection.down,
                  )
                  .first,
            );
            expect(
              scrollable.position.maxScrollExtent,
              greaterThanOrEqualTo(size.height - navigationBounds.top),
            );
          } else {
            expect(hour(21).bottom, lessThanOrEqualTo(navigationBounds.top));
          }
        }
        void expectStable() {
          expect(navigation, findsOneWidget);
          expect(tester.getRect(navigation), navigationBounds);
          for (var h = 8; h < 22; h++) {
            expect(
              hour(h),
              before[h - 8],
              reason: 'hour $h must not move behind a popup',
            );
          }
          expect(hour(8).height / hour(9).height, closeTo(.5, .001));
          expect(tester.takeException(), isNull);
        }

        // Inspect transition frames too: settled-only checks miss a visible jump.
        Future<void> checkTransition() async {
          await tester.pump();
          expectStable();
          for (var i = 0; i < 24; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expectStable();
          }
          await tester.pumpAndSettle();
          expectStable();
        }

        final deadline = find
            .byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'DDL：Accessible Deadline' &&
                  widget.properties.button == true,
            )
            .first;
        final deadlineModal = find.byKey(
          const ValueKey('schedule-deadline-detail-modal'),
        );
        for (final dismissal in [
          'close',
          'back',
          'barrier',
          if (size.width < 700) 'drag',
        ]) {
          await tester.tap(deadline);
          await checkTransition();
          expect(deadlineModal, findsOneWidget);
          expect(
            Navigator.of(tester.element(deadlineModal)),
            Navigator.of(
              tester.element(find.byType(RootShellPage)),
              rootNavigator: true,
            ),
            reason: 'the deadline modal must cover the root navigation',
          );
          if (dismissal == 'close') {
            await tester.tap(find.byTooltip('关闭'));
          } else if (dismissal == 'back') {
            await tester.binding.handlePopRoute();
          } else if (dismissal == 'barrier') {
            await tester.tapAt(Offset(size.width / 2, 70));
          } else {
            await tester.drag(find.text('DDL详情'), const Offset(0, 700));
          }
          await checkTransition();
          expect(deadlineModal, findsNothing);
        }
        await tester.tap(deadline);
        await checkTransition();
        await tester.tap(
          find.byKey(const ValueKey('schedule-deadline-open-ispace')),
        );
        await tester.pumpAndSettle();
        expect(deadlineModal, findsNothing);
        expect(find.byType(TimelineDetailPage), findsOneWidget);
        if (size.width < 700) expect(navigation, findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(TimelineDetailPage), findsNothing);
        expectStable();

        for (final dismissal in ['close', 'same-week', 'back', 'other-week']) {
          await tester.tap(find.byKey(const ValueKey('schedule-week-picker')));
          await checkTransition();
          if (size.width < 700) {
            expect(
              tester.getRect(find.byType(BottomSheet)).bottom,
              closeTo(size.height, .001),
              reason: 'the picker must cover the bottom navigation too',
            );
          }
          if (dismissal == 'close') {
            await tester.tap(find.byTooltip('关闭'));
          } else if (dismissal == 'back') {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(
              find.byKey(
                ValueKey(
                  dismissal == 'same-week'
                      ? 'fixed-schedule-week-2026-7-27'
                      : 'fixed-schedule-week-2026-7-13',
                ),
              ),
            );
          }
          // The alternate fixture week has the same meetings/geometry and is
          // non-adjacent, avoiding the intentionally moving week transition.
          await checkTransition();
          expect(find.byTooltip('上个月'), findsNothing);
        }
        expect(find.textContaining('7/13'), findsWidgets);
        for (final dismissal in ['close', 'back']) {
          await tester.tap(
            find
                .byKey(const ValueKey('schedule-course-block-1-540-ACC101'))
                .first,
          );
          await checkTransition();
          expect(
            find.byKey(const ValueKey('schedule-course-detail-modal')),
            findsOneWidget,
          );
          if (dismissal == 'close') {
            await tester.tap(find.byTooltip('关闭'));
          } else {
            await tester.binding.handlePopRoute();
          }
          await checkTransition();
        }
      },
    );
  }

  for (final width in [320.0, 375.0, 390.0, 402.0, 510.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'phone toolbar stays readable at $width and text scale $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          final session = _ScheduleSessionController(
            timetable: _timetable(),
            timelineItems: [],
          );
          final ta = TaCourseController(sessionController: session);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            ta.dispose();
            session.dispose();
            tester.view.reset();
          });
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: SchedulePage(
                directoryService: _TeacherLinkDirectoryService(),
                controller: session,
                taCourseController: ta,
                now: DateTime(2026, 12, 21, 8),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final toolbar = tester.getRect(
            find.byKey(const ValueKey('schedule-toolbar')),
          );
          expect(
            find.byKey(const ValueKey('schedule-phone-two-row-toolbar')),
            findsNothing,
            reason: '长日期、大字和窄屏都不能把功能按钮移到第二行',
          );
          for (final name in ['view', 'locate', 'deadline', 'ta']) {
            final icon = tester.widget<Icon>(
              find.byKey(ValueKey('schedule-$name-base-icon')),
            );
            expect(icon.size, 18, reason: '恢复 d13f746 之前的实际图标尺寸');
            final label = tester.widget<Text>(
              find.byKey(ValueKey('schedule-$name-label')),
            );
            expect(
              label.style!.fontSize,
              name == 'ta' ? closeTo(7.84, .001) : 7,
            );
          }
          final date = find.byKey(const ValueKey('schedule-week-range-label'));
          final text = tester.widget<Text>(date);
          expect(text.style!.fontSize, inInclusiveRange(13, 15.4));
          final calendar = find.descendant(
            of: find.byKey(const ValueKey('schedule-week-picker')),
            matching: find.byIcon(LucideIcons.calendarRange300),
          );
          expect(calendar, findsNothing);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(
            find.ancestor(of: date, matching: find.byType(FittedBox)),
            findsNothing,
            reason: '只允许有下限的日期字号调整，不能整体缩放图标或点击区域',
          );
          for (final name in [
            'view-toggle',
            'locate-action',
            'previous-week',
            'next-week',
            'deadline-toggle',
            'ta-action',
            'week-picker',
          ]) {
            final rect = tester.getRect(find.byKey(ValueKey('schedule-$name')));
            expect(rect.width, greaterThanOrEqualTo(44));
            expect(rect.height, greaterThanOrEqualTo(44));
            expect(rect.center.dy, closeTo(toolbar.center.dy, 0.01));
            await tester.ensureVisible(find.byKey(ValueKey('schedule-$name')));
            await tester.pumpAndSettle();
            final visible = tester.getRect(
              find.byKey(ValueKey('schedule-$name')),
            );
            expect(visible.left, greaterThanOrEqualTo(12));
            if (visible.width <= width - 24) {
              expect(visible.right, lessThanOrEqualTo(width - 12));
            } else {
              // Ahem's wide glyphs at 2x can exceed the entire viewport.
              // Keep the date unabridged and horizontally scrollable.
              expect(name, 'week-picker');
              expect(visible.overlaps(toolbar), isTrue);
            }
          }
          await tester.ensureVisible(date);
          await tester.pumpAndSettle();
          final textRect = tester.getRect(date);
          expect(textRect.top, greaterThanOrEqualTo(toolbar.top));
          expect(textRect.bottom, lessThanOrEqualTo(toolbar.bottom));
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: date, matching: find.byType(RichText)),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          await tester.ensureVisible(
            find.byKey(const ValueKey('schedule-next-week')),
          );
          await tester.tap(find.byKey(const ValueKey('schedule-next-week')));
          await tester.pumpAndSettle();
          expect(find.text('12/28–1/3'), findsOneWidget);
          if (scale == 1) {
            final nextToolbar = tester.getRect(
              find.byKey(const ValueKey('schedule-toolbar')),
            );
            expect(nextToolbar.height, 44);
            expect(toolbar.height, 44);
            expect(
              tester
                  .getRect(
                    find.byKey(const ValueKey('schedule-loading-progress')),
                  )
                  .bottom,
              nextToolbar.bottom,
              reason: '长短日期切换不能改变顶栏高度，蓝条保持原位置',
            );
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('schedule-previous-week')),
          );
          await tester.tap(
            find.byKey(const ValueKey('schedule-previous-week')),
          );
          await tester.pumpAndSettle();
          expect(find.text('12/21–12/27'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Large English toolbar stays pinned above scrolling content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: [],
    );
    final ta = TaCourseController(sessionController: session);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      ta.dispose();
      session.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
        locale: const Locale('en'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: ta,
          now: DateTime(2026, 12, 21, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toolbar = find.byKey(const ValueKey('schedule-toolbar'));
    final date = find.byKey(const ValueKey('schedule-week-range-label'));
    final originalToolbar = tester.getRect(toolbar);
    await tester.ensureVisible(date);
    await tester.pumpAndSettle();
    final originalDate = tester.getRect(date);
    expect(tester.widget<Text>(date).data, '12/21–12/27');
    expect(tester.widget<Text>(date).style?.fontSize, 13);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(of: date, matching: find.byType(RichText)),
          )
          .textScaler
          .scale(13),
      26,
      reason: '日期字体下限仍遵循系统两倍字号，不抵消辅助功能设置',
    );
    final dateColor = tester.widget<Text>(date).style!.color!;
    final background = AppTheme.dark.extension<BnbuThemeExtension>()!.surface;
    expect(
      (dateColor.computeLuminance() + 0.05) /
          (background.computeLuminance() + 0.05),
      greaterThanOrEqualTo(4.5),
      reason: '放大后深色顶栏日期仍须清晰可读',
    );
    expect(originalDate.top, greaterThanOrEqualTo(originalToolbar.top));
    expect(originalDate.bottom, lessThanOrEqualTo(originalToolbar.bottom));
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(of: date, matching: find.byType(RichText)),
          )
          .didExceedMaxLines,
      isFalse,
    );
    final progress = find.byKey(const ValueKey('schedule-loading-progress'));
    expect(tester.getRect(progress).bottom, originalToolbar.bottom);
    final scrollView = find.byType(CustomScrollView);
    final scroll = tester.widget<CustomScrollView>(scrollView).controller!;
    scroll.jumpTo(0);
    await tester.pump();
    await tester.dragFrom(const Offset(150, 650), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0), reason: '正文确实发生了纵向滚动');
    expect(tester.getRect(toolbar), originalToolbar);
    expect(tester.getRect(date), originalDate);
    expect(tester.getRect(progress).bottom, originalToolbar.bottom);
    await tester.ensureVisible(
      find.byKey(const ValueKey('schedule-next-week')),
    );
    await tester.tap(find.byKey(const ValueKey('schedule-next-week')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(date).data, '12/28–1/3');
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 900.0, 1440.0]) {
    for (final campusMinutes in [479, 480, 750]) {
      testWidgets('current time line width=$width minute=$campusMinutes', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        final session = _ScheduleSessionController(
          timetable: _timetable(),
          timelineItems: [],
        );
        final ta = TaCourseController(sessionController: session);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          ta.dispose();
          session.dispose();
          tester.view.reset();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: SchedulePage(
              directoryService: _TeacherLinkDirectoryService(),
              controller: session,
              taCourseController: ta,
              now: DateTime.utc(
                2026,
                7,
                27,
              ).add(Duration(minutes: campusMinutes - 480)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final marker = find.bySemanticsLabel(RegExp(r'^当前时间 '));
        if (campusMinutes < 480) {
          expect(marker, findsNothing);
        } else {
          expect(marker, findsOneWidget);
          final rect = tester.getRect(marker);
          final today = tester.getRect(
            find.byKey(const ValueKey('schedule-grid-today-highlight')),
          );
          expect(rect.height, 2);
          expect(rect.left, closeTo(today.left, 0.01));
          expect(rect.width, closeTo(today.width, 0.01));
          if (campusMinutes == 480) {
            expect(rect.top, closeTo(today.top, 0.01));
          } else {
            expect(rect.top, greaterThan(today.top));
          }
          await tester.tap(find.byKey(const ValueKey('schedule-next-week')));
          await tester.pumpAndSettle();
          expect(marker, findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final lateSchedule in [false, true]) {
    testWidgets(
      'hidden DDL does not extend the axis; late schedule=$lateSchedule',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        final session = _SignedInScheduleSessionController(
          timetable: _timetable(),
          timelineItems: [_deadline(due: DateTime.utc(2026, 7, 27, 15, 59))],
        );
        final ta = TaCourseController(sessionController: session);
        addTearDown(() {
          ta.dispose();
          session.dispose();
          tester.view.reset();
        });
        await ta.reload();
        if (lateSchedule) {
          final result = await ta.addEntry(
            const TaCourseEntry(
              id: 'late-schedule',
              title: 'Late study',
              location: 'Library',
              weekday: DateTime.monday,
              startMinutes: 22 * 60,
              endMinutes: 22 * 60 + 30,
              repeatType: TaCourseRepeatType.weekly,
            ),
            expectedRevision: ta.revision,
          );
          expect(result.isSuccess, isTrue);
        }
        Widget page() => MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: ta,
            now: DateTime.utc(2026, 7, 27, 1),
          ),
        );
        String? endHour() => tester
            .widget<Text>(find.byKey(const ValueKey('schedule-end-hour')))
            .data;
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(endHour(), '24');
        await tester.tap(
          find.byKey(const ValueKey('schedule-deadline-toggle')),
        );
        await tester.pumpAndSettle();
        expect(endHour(), lateSchedule ? '23' : '22');
        // Restoring the saved preference must also restore the shorter axis.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(endHour(), lateSchedule ? '23' : '22');
        await tester.tap(
          find.byKey(const ValueKey('schedule-deadline-toggle')),
        );
        await tester.pumpAndSettle();
        expect(endHour(), '24');
      },
    );
  }

  testWidgets(
    'iPad landscape splits and rotation preserves week without a refresh button',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1194, 834);
      final session = _ScheduleSessionController(
        timetable: _timetable(),
        timelineItems: [],
      );
      final ta = TaCourseController(sessionController: session);
      addTearDown(() {
        ta.dispose();
        session.dispose();
        tester.view.reset();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: ta,
            now: DateTime(2026, 12, 28, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-mac-split')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-view-toggle')), findsNothing);
      expect(find.byKey(const ValueKey('schedule-refresh')), findsNothing);
      for (final action in ['deadline-toggle', 'locate-action', 'ta-action']) {
        expect(find.byKey(ValueKey('schedule-$action')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('schedule-next-week')));
      await tester.pumpAndSettle();
      expect(find.text('1/4 - 1/10'), findsOneWidget);
      tester.view.physicalSize = const Size(834, 1194);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-mac-split')), findsNothing);
      expect(
        find.byKey(const ValueKey('schedule-view-toggle')),
        findsOneWidget,
      );
      expect(find.text('1/4 - 1/10'), findsOneWidget);
      tester.view.physicalSize = const Size(1194, 834);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-mac-split')), findsOneWidget);
      expect(find.text('1/4 - 1/10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mac shows a shared week in two independently scrolling panes', (
    tester,
  ) async {
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: [_deadline()],
    );
    final ta = TaCourseController(sessionController: session);
    addTearDown(() {
      ta.dispose();
      session.dispose();
      tester.view.reset();
    });
    for (final width in [648.0, 900.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: ta,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-view-toggle')), findsNothing);
      final grid = find.bySemanticsLabel('课表横表视图');
      final agenda = find.byKey(const ValueKey('schedule-mac-agenda-scroll'));
      expect(grid, findsOneWidget);
      expect(agenda, findsOneWidget);
      expect(tester.getRect(grid).right, lessThan(tester.getRect(agenda).left));
      final right = tester.widget<SingleChildScrollView>(agenda).controller!;
      final left = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .firstWhere(
            (w) => w.scrollDirection == Axis.vertical && w.controller != right,
          )
          .controller!;
      final leftOffset = left.offset;
      right.jumpTo(150);
      await tester.pump();
      expect(right.offset, 150);
      expect(left.offset, leftOffset);
      await tester.tap(find.byKey(const ValueKey('schedule-next-week')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('schedule-locate-action')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Schedule page exposes accessible hit targets in grid mode', (
    tester,
  ) async {
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: [_deadline()],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
        ),
      ),
    );
    await tester.pump();

    final deadlineToggle = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'DDL显示开关' &&
          widget.properties.button == true,
    );
    expect(deadlineToggle, findsOneWidget);
    expect(tester.getSize(deadlineToggle).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(deadlineToggle).width, greaterThanOrEqualTo(44));

    final courseHitTarget = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == '课程：Accessible Course' &&
          widget.properties.button == true,
    );
    expect(courseHitTarget, findsOneWidget);
    expect(tester.getSize(courseHitTarget).height, greaterThanOrEqualTo(44));

    final courseBlock = find.byKey(
      const ValueKey('schedule-course-block-1-540-ACC101'),
    );
    expect(courseBlock, findsOneWidget);
    expect(tester.getSize(courseBlock).height, greaterThan(20));
    expect(
      tester.getRect(find.byKey(const ValueKey('schedule-end-hour'))).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    final decoration =
        tester.widget<Container>(courseBlock).decoration as BoxDecoration;
    expect(decoration.borderRadius, isNull);
    final weekBoard = find.byKey(const ValueKey('schedule-week-board'));
    expect(weekBoard, findsOneWidget);
    expect(
      find.ancestor(of: weekBoard, matching: find.byType(BnbuSurfaceCard)),
      findsNothing,
    );

    final taIcon = find.byKey(const ValueKey('schedule-ta-icon'));
    expect(tester.getSize(taIcon), const Size.square(26));
    final taBaseIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('schedule-ta-base-icon')),
    );
    expect(taBaseIcon.size, 18);
    expect(find.byKey(const ValueKey('schedule-ta-label')), findsOneWidget);

    final weekPicker = find.byKey(const ValueKey('schedule-week-picker'));
    expect(weekPicker, findsOneWidget);
    expect(tester.getSize(weekPicker).height, greaterThanOrEqualTo(44));
    expect(find.byTooltip(RegExp(r'^选择所在周，.+$')), findsOneWidget);
    expect(find.byTooltip('切换周'), findsNothing);
    expect(find.byTooltip('刷新'), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester.tap(weekPicker);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byTooltip('上个月'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'fixed-schedule-week-',
            ),
      ),
      findsNWidgets(6),
    );
  });

  testWidgets(
    'linked TA shares course color and exposes its type only in details',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final timetable = _timetable();
      final course = timetable.courses.first;
      final session = _SignedInScheduleSessionController(
        timetable: timetable,
        timelineItems: [],
      );
      final entries = TaCourseController(sessionController: session);
      addTearDown(() {
        entries.dispose();
        session.dispose();
      });
      await entries.ensureLoaded();
      final saved = await entries.addEntry(
        TaCourseEntry(
          id: 'linked',
          title: course.name,
          location: '',
          weekday: 2,
          startMinutes: 600,
          endMinutes: 650,
          repeatType: TaCourseRepeatType.weekly,
          kind: FixedScheduleKind.ta,
          courseKey: TaCourseEntry.bindingKey(timetable, course),
          courseCode: course.code,
          semesterId: timetable.selectedSemesterId,
        ),
        expectedRevision: entries.revision,
      );
      expect(saved.isSuccess, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: entries,
            now: DateTime.utc(2026, 7, 27, 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final parent = find.byKey(
        ValueKey('schedule-course-block-1-540-${course.code}'),
      );
      final ta = find.byKey(
        ValueKey('schedule-course-block-2-600-${course.code}'),
      );
      final parentColor =
          (tester.widget<Container>(parent).decoration! as BoxDecoration).color;
      final taColor =
          (tester.widget<Container>(ta).decoration! as BoxDecoration).color;
      expect(taColor, parentColor);
      expect(find.descendant(of: ta, matching: find.text('TA')), findsNothing);
      await tester.tap(ta);
      await tester.pumpAndSettle();
      final detail = find.byKey(const ValueKey('schedule-course-detail-modal'));
      expect(
        find.descendant(of: detail, matching: find.text('TA')),
        findsOneWidget,
      );
      expect(find.text('${course.name} · ${course.code}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weighted idle hours fill viewport as schedules and linked TA change occupancy',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final timetable = _timetable();
      final course = timetable.courses.first;
      final session = _SignedInScheduleSessionController(
        timetable: timetable,
        timelineItems: [],
      );
      final entries = TaCourseController(sessionController: session);
      addTearDown(() {
        entries.dispose();
        session.dispose();
      });
      await entries.ensureLoaded();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: entries,
            now: DateTime.utc(2026, 7, 27, 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double height(int hour) => tester
          .getSize(find.byKey(ValueKey('schedule-hour-${hour * 60}')))
          .height;
      void expectFilledViewport() {
        final first = tester.getRect(
          find.byKey(const ValueKey('schedule-hour-480')),
        );
        final last = tester.getRect(
          find.byKey(const ValueKey('schedule-hour-1260')),
        );
        expect(
          first.top,
          closeTo(
            tester
                .getBottomLeft(
                  find.byKey(const ValueKey('schedule-day-header-2026-07-27')),
                )
                .dy,
            .001,
          ),
        );
        expect(last.bottom, closeTo(844, .001));
      }

      expectFilledViewport();
      final normalHeight = height(9);
      for (var hour = 8; hour < 22; hour++) {
        expect(height(hour) / normalHeight, closeTo(hour == 9 ? 1 : .5, .001));
      }
      expect(
        (await entries.addEntry(
          const TaCourseEntry(
            id: 'noon',
            title: 'Study',
            location: '',
            weekday: 1,
            startMinutes: 720,
            endMinutes: 780,
            repeatType: TaCourseRepeatType.weekly,
          ),
          expectedRevision: entries.revision,
        )).isSuccess,
        isTrue,
      );
      await tester.pumpAndSettle();
      expectFilledViewport();
      expect(height(12), closeTo(height(9), .001));
      expect(height(18), closeTo(height(9) * .5, .001));
      expect(
        (await entries.addEntry(
          TaCourseEntry(
            id: 'evening',
            title: course.name,
            location: '',
            weekday: 3,
            startMinutes: 1080,
            endMinutes: 1130,
            repeatType: TaCourseRepeatType.weekly,
            kind: FixedScheduleKind.ta,
            courseKey: TaCourseEntry.bindingKey(timetable, course),
            courseCode: course.code,
            semesterId: timetable.selectedSemesterId,
          ),
          expectedRevision: entries.revision,
        )).isSuccess,
        isTrue,
      );
      await tester.pumpAndSettle();
      expectFilledViewport();
      expect(height(12), closeTo(height(9), .001));
      expect(height(18), closeTo(height(9), .001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('下一周可以跨过十一月边界', (tester) async {
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime(2026, 10, 26, 8),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('10/26 - 11/1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('schedule-next-week')));
    await tester.pumpAndSettle();

    expect(find.text('11/2 - 11/8'), findsOneWidget);
  });

  testWidgets('切周在松手前跟随手指而不提前更换日期', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final ta = TaCourseController(sessionController: session);
    addTearDown(() {
      ta.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: ta,
          now: DateTime(2026, 9, 7, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final day = find.text('9/7');
    final original = tester.getTopLeft(day);
    final gesture = await tester.startGesture(const Offset(270, 190));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(tester.getTopLeft(day).dx, lessThan(original.dx - 15));
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(find.text('9/7–9/13'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('9/14–9/20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机横表和竖表都可以在课表内左右滑动切周', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime(2026, 10, 26, 8),
        ),
      ),
    );
    await tester.pump();

    Future<void> swipeWeek(Offset offset) async {
      final surface = find.byKey(
        const ValueKey('schedule-mobile-week-swipe-surface'),
      );
      final rect = tester.getRect(surface);
      await tester.dragFrom(rect.topLeft + Offset(rect.width / 2, 120), offset);
      await tester.pumpAndSettle();
    }

    expect(find.text('10/26–11/1'), findsOneWidget);
    await swipeWeek(const Offset(-120, 0));
    expect(find.text('10/26–11/1'), findsOneWidget);
    await swipeWeek(const Offset(-180, 0));
    expect(find.text('11/2–11/8'), findsOneWidget);
    await swipeWeek(const Offset(180, 0));
    expect(find.text('10/26–11/1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '课表竖表视图',
      ),
      findsOneWidget,
    );
    await swipeWeek(const Offset(-180, 0));
    expect(find.text('11/2–11/8'), findsOneWidget);
  });

  testWidgets('iPhone竖表切周后仍可在课程正文上纵向滚动', (tester) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final ta = TaCourseController(sessionController: session);
    addTearDown(() {
      ta.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: ta,
          now: DateTime(2026, 9, 7, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(280, 300), const Offset(-180, 0));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(200));
    final before = scroll.offset;
    final course = find.byKey(
      const ValueKey('schedule-list-2026-09-14-course-ACC101-540'),
    );
    await tester.dragFrom(tester.getCenter(course), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(before + 100));
    expect(find.text('9/14–9/20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(820, 1180),
    const Size(1180, 820),
    const Size(700, 900),
  ]) {
    testWidgets('iPad $size 横竖表支持左右切周且不误触纵向滚动', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _ScheduleSessionController(
        timetable: _timetable(),
        timelineItems: const [],
      );
      final taCourses = TaCourseController(sessionController: session);
      addTearDown(() {
        taCourses.dispose();
        session.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: taCourses,
            now: DateTime(2026, 12, 28, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var modeIndex = 0;
      Future<void> swipe(Offset offset, {bool deliberate = false}) async {
        final board = tester.getRect(
          find.byKey(
            ValueKey(
              modeIndex == 1
                  ? 'schedule-mac-agenda-board'
                  : 'schedule-week-board',
            ),
          ),
        );
        await tester.dragFrom(
          board.topLeft + Offset(board.width / 2, 160),
          deliberate ? Offset(board.width * .45 * offset.dx.sign, 0) : offset,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      for (var mode = 0; mode < 2; mode++) {
        expect(find.text('12/28 - 1/3'), findsOneWidget);
        await swipe(const Offset(-24, 0));
        expect(find.text('12/28 - 1/3'), findsOneWidget);
        await swipe(const Offset(-20, -120));
        expect(find.text('12/28 - 1/3'), findsOneWidget);
        await swipe(const Offset(-1, 0), deliberate: true);
        expect(find.text('1/4 - 1/10'), findsOneWidget);
        await swipe(const Offset(1, 0), deliberate: true);
        expect(find.text('12/28 - 1/3'), findsOneWidget);
        if (mode == 0 && size.width < size.height) {
          await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
          await tester.pumpAndSettle();
        } else if (mode == 0) {
          modeIndex = 1;
        }
      }
    });
  }

  testWidgets('宽屏 macOS 保留原有周次按钮且不增加拖动切周', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime(2026, 12, 28, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-mobile-week-swipe-surface')),
      findsNothing,
    );
    final board = tester.getRect(
      find.byKey(const ValueKey('schedule-week-board')),
    );
    await tester.dragFrom(
      board.topLeft + Offset(board.width / 2, 160),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('12/28 - 1/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('schedule-next-week')));
    await tester.pumpAndSettle();
    expect(find.text('1/4 - 1/10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home course intent focuses its week and opens course detail', (
    tester,
  ) async {
    final timetable = _timetable();
    final session = _ScheduleSessionController(
      timetable: timetable,
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    final shell = RootShellController();
    addTearDown(() {
      shell.dispose();
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          shellController: shell,
          now: DateTime(2026, 7, 20, 8),
        ),
      ),
    );
    await tester.pump();
    shell.openScheduleCourse(
      course: timetable.courses.single,
      meeting: timetable.courses.single.meetings.single,
      startsAt: DateTime.utc(2026, 7, 20, 1),
    );
    await tester.pumpAndSettle();

    expect(find.text('7/20 - 7/26'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-course-detail-modal')),
      findsOneWidget,
    );
    expect(find.text('Accessible Course'), findsWidgets);
    expect(find.text('本次时间'), findsOneWidget);
  });

  testWidgets('course detail uses a centered dialog on wide layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
        ),
      ),
    );
    await tester.pump();

    final courseBlock = find.byKey(
      const ValueKey('schedule-course-block-1-540-ACC101'),
    );
    tester
        .widget<InkWell>(
          find.ancestor(of: courseBlock, matching: find.byType(InkWell)).first,
        )
        .onTap!();
    await tester.pumpAndSettle();

    final modal = find.byKey(const ValueKey('schedule-course-detail-modal'));
    final dialog = find.byKey(const ValueKey('bnbu-adaptive-modal-dialog'));
    expect(modal, findsOneWidget);
    expect(dialog, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    final dialogRect = tester.getRect(dialog);
    expect(dialogRect.width, lessThanOrEqualTo(760));
    expect(dialogRect.center.dx, closeTo(450, 0.1));
    expect(dialogRect.center.dy, closeTo(600, 0.1));
    final detailCard = tester.widget<BnbuSurfaceCard>(
      find.byKey(const ValueKey('schedule-detail-course-ACC101-540')),
    );
    expect(detailCard.borderRadius, BorderRadius.zero);
    expect(
      find.byKey(const ValueKey('schedule-detail-accent-ACC101-540')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(modal, findsNothing);
  });

  testWidgets('course detail remains a bottom sheet on compact layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
        ),
      ),
    );
    await tester.pump();

    final courseBlock = find.byKey(
      const ValueKey('schedule-course-block-1-540-ACC101'),
    );
    tester
        .widget<InkWell>(
          find.ancestor(of: courseBlock, matching: find.byType(InkWell)).first,
        )
        .onTap!();
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      findsNothing,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('schedule-course-detail-modal')))
          .bottom,
      closeTo(844, 0.1),
    );
  });

  testWidgets('phone deadline detail shows its heading and can be closed', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: [_deadline(due: DateTime(2026, 7, 27, 10))],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime(2026, 7, 27, 8),
        ),
      ),
    );
    await tester.pump();
    final deadlineHitTarget = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'DDL：Accessible Deadline' &&
          widget.properties.button == true,
    );
    await tester.ensureVisible(deadlineHitTarget);
    await tester.tap(deadlineHitTarget);
    await tester.pumpAndSettle();

    final modal = find.byKey(const ValueKey('schedule-deadline-detail-modal'));
    expect(find.byType(BottomSheet), findsOneWidget);
    final heading = find.descendant(of: modal, matching: find.text('DDL详情'));
    expect(heading, findsOneWidget);
    expect(
      tester.getRect(heading).bottom,
      lessThan(
        tester
            .getRect(
              find.byKey(const ValueKey('schedule-detail-deadline-card')),
            )
            .top,
      ),
    );
    final close = find.descendant(of: modal, matching: find.byTooltip('关闭'));
    expect(close, findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(modal, findsNothing);
    expect(find.byType(TimelineDetailPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deadline detail uses a centered dialog on wide layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 7, 27, 8);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: [_deadline(due: DateTime(2026, 7, 27, 10))],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: now,
        ),
      ),
    );
    await tester.pump();

    final deadlineHitTarget = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'DDL：Accessible Deadline' &&
          widget.properties.button == true,
    );
    expect(deadlineHitTarget, findsOneWidget);
    await tester.ensureVisible(deadlineHitTarget);
    await tester.tap(deadlineHitTarget);
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('bnbu-adaptive-modal-dialog'));
    expect(
      find.byKey(const ValueKey('schedule-deadline-detail-modal')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
    final dialogRect = tester.getRect(dialog);
    expect(dialogRect.width, lessThanOrEqualTo(640));
    expect(dialogRect.center.dx, closeTo(450, 0.1));
    expect(dialogRect.center.dy, closeTo(600, 0.1));
    final detailCard = tester.widget<BnbuTimelineSummaryCard>(
      find.byKey(const ValueKey('schedule-detail-deadline-card')),
    );
    expect(detailCard.showIspaceLabel, isFalse);
    expect(detailCard.showChevron, isFalse);
    final typeIcon = tester.widget<MoodleActivityIcon>(
      find.byKey(const ValueKey('timeline-summary-type-icon-1')),
    );
    expect(typeIcon.color, detailCard.accentColor);
    expect(typeIcon.size, 17);
    await tester.tap(
      find.byKey(const ValueKey('schedule-deadline-open-ispace')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimelineDetailPage), findsOneWidget);
  });

  for (final scenario in ['single', 'multiple', 'prefetch-failure']) {
    testWidgets(
      'course detail hands off immediately and reuses teacher lookup: $scenario',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        final rawNames = scenario == 'multiple' ? 'Teacher;Second' : 'Teacher';
        final session = _ScheduleSessionController(
          timetable: _timetable(teacher: rawNames),
          timelineItems: [],
        );
        final ta = TaCourseController(sessionController: session);
        final shell = RootShellController()..selectTab(AppTab.schedule);
        final mail = MailAssistantIntentController();
        final directory = _ControlledTeacherDirectory();
        final reviews = _EmptyTeacherReviewService();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          tester.view.reset();
          ta.dispose();
          session.dispose();
          shell.dispose();
          mail.dispose();
          directory.dispose();
          reviews.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: RootShellPage(
              controller: session,
              shellController: shell,
              taCourseController: ta,
              mailIntentController: mail,
              pageOverrideBuilder: (tab) => tab == AppTab.schedule
                  ? SchedulePage(
                      controller: session,
                      taCourseController: ta,
                      directoryService: directory,
                      teacherReviewService: reviews,
                      now: DateTime.utc(2026, 7, 27, 1),
                    )
                  : const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('schedule-course-block-1-540-ACC101')),
        );
        await tester.pumpAndSettle();
        final expectedRequests = scenario == 'multiple' ? 2 : 1;
        expect(directory.responses, hasLength(expectedRequests));
        if (scenario == 'prefetch-failure') {
          directory.responses.first.completeError(StateError('offline'));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await tester.tap(
          find.byKey(ValueKey('schedule-teacher-link-$rawNames')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (scenario == 'multiple') {
          expect(find.text('选择教师'), findsOneWidget);
          await tester.tap(find.text('Teacher'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(
          find.byKey(const ValueKey('schedule-course-detail-modal')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('teacher-profile-loading')),
          findsOneWidget,
        );
        expect(
          directory.responses,
          hasLength(
            expectedRequests + (scenario == 'prefetch-failure' ? 1 : 0),
          ),
        );
        final result = await _TeacherLinkDirectoryService().loadTeachers(
          query: 'Teacher',
        );
        for (final response in directory.responses) {
          if (!response.isCompleted) response.complete(result);
        }
        await tester.pumpAndSettle();
        expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('schedule-course-block-1-540-ACC101')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('root-bottom-navigation')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('course teacher opens the matching official teacher page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'schedule.week_layout.v1.signed-out': 'list',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    final directory = _TeacherLinkDirectoryService();
    final reviews = _EmptyTeacherReviewService();
    addTearDown(() {
      reviews.dispose();
      directory.dispose();
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          controller: session,
          taCourseController: taCourses,
          directoryService: directory,
          teacherReviewService: reviews,
          now: DateTime(2026, 7, 27, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('schedule-teacher-link-Teacher')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
    expect(find.text('同学评价'), findsOneWidget);
    expect(directory.lastQuery, 'Teacher');
  });

  testWidgets(
    'comma inside an official English teacher name stays in one profile link',
    (tester) async {
      const teacherName = 'Prof. Jian-Hua, LIN';
      SharedPreferences.setMockInitialValues({
        'schedule.week_layout.v1.signed-out': 'list',
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _ScheduleSessionController(
        timetable: _timetable(teacher: teacherName),
        timelineItems: const [],
      );
      final taCourses = TaCourseController(sessionController: session);
      final directory = _TeacherLinkDirectoryService(
        teacherName: '林建华',
        teacherNameEn: teacherName,
      );
      final reviews = _EmptyTeacherReviewService();
      addTearDown(() {
        reviews.dispose();
        directory.dispose();
        taCourses.dispose();
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            controller: session,
            taCourseController: taCourses,
            directoryService: directory,
            teacherReviewService: reviews,
            now: DateTime(2026, 7, 27, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('schedule-teacher-link-$teacherName')).first,
      );
      await tester.pumpAndSettle();

      expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
      expect(directory.lastQuery, teacherName);
    },
  );

  testWidgets('one unique teacher candidate opens when names differ slightly', (
    tester,
  ) async {
    const timetableName = 'Katharina Schmidt';
    SharedPreferences.setMockInitialValues({
      'schedule.week_layout.v1.signed-out': 'list',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(teacher: timetableName),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    final directory = _TeacherLinkDirectoryService(
      teacherName: 'Katharina YU GEB. SCHMIDT',
      teacherNameEn: 'Katharina YU GEB. SCHMIDT',
      matchType: OfficialTeacherMatchType.candidate,
    );
    final reviews = _EmptyTeacherReviewService();
    addTearDown(() {
      reviews.dispose();
      directory.dispose();
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          controller: session,
          taCourseController: taCourses,
          directoryService: directory,
          teacherReviewService: reviews,
          now: DateTime(2026, 7, 27, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('schedule-teacher-link-$timetableName')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
    expect(directory.lastQuery, timetableName);
  });

  testWidgets('ambiguous teacher uses the unavailable profile notice', (
    tester,
  ) async {
    const timetableName = 'LIN';
    SharedPreferences.setMockInitialValues({
      'schedule.week_layout.v1.signed-out': 'list',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(teacher: timetableName),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    final directory = _TeacherLinkDirectoryService(
      teacherName: '林建华',
      teacherNameEn: 'Prof. Jian-Hua, LIN',
      matchType: OfficialTeacherMatchType.candidate,
      total: 2,
    );
    final reviews = _EmptyTeacherReviewService();
    addTearDown(() {
      reviews.dispose();
      directory.dispose();
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        home: SchedulePage(
          controller: session,
          taCourseController: taCourses,
          directoryService: directory,
          teacherReviewService: reviews,
          now: DateTime(2026, 7, 27, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('schedule-teacher-link-$timetableName')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(OfficialTeacherDetailPage), findsNothing);
    expect(
      find.text('This instructor may not be listed in the school directory'),
      findsOneWidget,
    );
    expect(find.text('该教师可能未被学校收录'), findsNothing);
    expect(find.textContaining('multiple match'), findsNothing);
    final noticeSemantics = tester
        .getSemantics(find.byKey(const ValueKey('teacher-profile-unavailable')))
        .label;
    expect(
      noticeSemantics,
      contains('This instructor may not be listed in the school directory'),
    );
    expect(noticeSemantics, isNot(contains('该教师可能未被学校收录')));
    expect(noticeSemantics, isNot(contains('multiple match')));
    expect(directory.lastQuery, timetableName);
  });

  testWidgets('missing schedule teacher shows the school collection notice', (
    tester,
  ) async {
    const timetableName = 'Missing Teacher';
    SharedPreferences.setMockInitialValues({
      'schedule.week_layout.v1.signed-out': 'list',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(teacher: timetableName),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    final directory = _TeacherLinkDirectoryService(total: 0);
    final reviews = _EmptyTeacherReviewService();
    addTearDown(() {
      reviews.dispose();
      directory.dispose();
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          controller: session,
          taCourseController: taCourses,
          directoryService: directory,
          teacherReviewService: reviews,
          now: DateTime(2026, 7, 27, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('schedule-teacher-link-$timetableName')).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(OfficialTeacherDetailPage), findsNothing);
    expect(find.text('该教师可能未被学校收录'), findsOneWidget);
    expect(find.textContaining('多个匹配'), findsNothing);
    final noticeSemantics = tester
        .getSemantics(find.byKey(const ValueKey('teacher-profile-unavailable')))
        .label;
    expect(noticeSemantics, contains('该教师可能未被学校收录'));
    expect(noticeSemantics, isNot(contains('多个匹配')));
    expect(directory.lastQuery, timetableName);
  });

  testWidgets('Schedule switches between weekly grid and weekly list cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime(2026, 7, 27, 8),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('schedule-toolbar')), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(
      find.byKey(const ValueKey('schedule-phone-single-row-toolbar')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('schedule-toolbar'))).height,
      44,
    );
    expect(find.text('课表'), findsNothing);
    expect(find.byKey(const ValueKey('schedule-view-toggle')), findsOneWidget);
    expect(find.text('HOR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-course-block-1-540-ACC101')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('schedule-list-day-2026-07-27')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-list-day-2026-08-02')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-list-2026-07-27-course-ACC101-540')),
      findsOneWidget,
    );
    final listCard = tester.widget<BnbuSurfaceCard>(
      find.byKey(const ValueKey('schedule-list-2026-07-27-course-ACC101-540')),
    );
    expect(listCard.borderRadius, BorderRadius.zero);
    expect(find.text('9:00 - 9:50'), findsOneWidget);
    expect(find.text('T1-101'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-deadline-toggle')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('schedule-list-2026-07-27-course-ACC101-540')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-detail-course-ACC101-540')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<BnbuSurfaceCard>(
            find.byKey(const ValueKey('schedule-detail-course-ACC101-540')),
          )
          .borderRadius,
      BorderRadius.zero,
    );
    Navigator.of(
      tester.element(
        find.byKey(const ValueKey('schedule-course-detail-modal')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('schedule-course-block-1-540-ACC101')),
      findsOneWidget,
    );
  });

  testWidgets(
    'today highlight follows the shared color and visibility setting',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _ScheduleSessionController(
        timetable: _timetable(),
        timelineItems: const [],
      );
      final taCourses = TaCourseController(sessionController: session);
      final themeController = AppThemeModeController();
      addTearDown(() {
        themeController.dispose();
        taCourses.dispose();
        session.dispose();
      });
      await themeController.restore();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => BnbuLiquidGlassScope(
            controller: themeController,
            child: child ?? const SizedBox.shrink(),
          ),
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: taCourses,
            now: DateTime(2026, 7, 27, 8),
          ),
        ),
      );
      await tester.pump();

      final gridHighlight = find.byKey(
        const ValueKey('schedule-grid-today-highlight'),
      );
      expect(gridHighlight, findsOneWidget);
      expect(
        (tester.widget<DecoratedBox>(gridHighlight).decoration as BoxDecoration)
            .border,
        isNull,
      );
      expect(
        tester.getRect(gridHighlight).bottom,
        greaterThanOrEqualTo(
          tester
              .getRect(find.byKey(const ValueKey('schedule-end-hour')))
              .bottom,
        ),
      );
      expect(find.text('HOR'), findsOneWidget);
      expect(
        (tester.widget<DecoratedBox>(gridHighlight).decoration as BoxDecoration)
            .color,
        const Color(0xFFE4F2FF).withValues(alpha: 0.9),
      );

      await themeController.setScheduleTodayAccent(ScheduleTodayAccent.violet);
      await tester.pump();
      expect(
        (tester.widget<DecoratedBox>(gridHighlight).decoration as BoxDecoration)
            .color,
        const Color(0xFFF0E8FF).withValues(alpha: 0.9),
      );

      await themeController.setScheduleTodayHighlightEnabled(false);
      await tester.pump();
      expect(gridHighlight, findsNothing);

      await themeController.setScheduleTodayAccent(ScheduleTodayAccent.teal);
      await themeController.setScheduleTodayHighlightEnabled(true);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('VER'), findsOneWidget);

      final todayListSection = find.byKey(
        const ValueKey('schedule-list-day-2026-07-27'),
      );
      final todayContainer = tester.widget<Container>(todayListSection);
      expect(todayContainer.decoration, isNull);
      expect(todayContainer.padding, isNull);
      expect(
        find.byKey(const ValueKey('schedule-list-today-icon')),
        findsNothing,
      );
      final todayTitle = tester.widget<Text>(
        find.byKey(const ValueKey('schedule-list-today-title')),
      );
      expect(todayTitle.style?.color, const Color(0xFF087A6A));
      final todayBadge = find.byKey(
        const ValueKey('schedule-list-today-badge'),
      );
      expect(todayBadge, findsNothing);
    },
  );

  testWidgets(
    'vertical list today uses a blue title and trailing badge without a frame',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'schedule.week_layout.v1.signed-out': 'list',
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _ScheduleSessionController(
        timetable: _timetable(),
        timelineItems: const [],
      );
      final taCourses = TaCourseController(sessionController: session);
      final themeController = AppThemeModeController();
      addTearDown(() {
        themeController.dispose();
        taCourses.dispose();
        session.dispose();
      });
      await themeController.restore();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => BnbuLiquidGlassScope(
            controller: themeController,
            child: child ?? const SizedBox.shrink(),
          ),
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: taCourses,
            now: DateTime(2026, 7, 27, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final todaySection = find.byKey(
        const ValueKey('schedule-list-day-2026-07-27'),
      );
      final todayContainer = tester.widget<Container>(todaySection);
      expect(todayContainer.decoration, isNull);
      expect(todayContainer.padding, isNull);
      expect(
        find.byKey(const ValueKey('schedule-list-today-icon')),
        findsNothing,
      );
      final todayTitle = tester.widget<Text>(
        find.byKey(const ValueKey('schedule-list-today-title')),
      );
      expect(todayTitle.style?.color, const Color(0xFF075EA8));
      final todayBadge = find.byKey(
        const ValueKey('schedule-list-today-badge'),
      );
      expect(todayBadge, findsNothing);
    },
  );

  testWidgets('Weekly list starts with today near the upper third', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'schedule.week_layout.v1.signed-out': 'list',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime(2026, 7, 31, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final today = find.byKey(const ValueKey('schedule-list-day-2026-07-31'));
    final monday = find.byKey(const ValueKey('schedule-list-day-2026-07-27'));
    final sunday = find.byKey(const ValueKey('schedule-list-day-2026-08-02'));
    expect(today, findsOneWidget);
    expect(monday, findsOneWidget);
    expect(sunday, findsOneWidget);
    expect(tester.getTopLeft(today).dy, inInclusiveRange(180, 360));

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        ),
      ),
    );
    expect(scrollable.position.pixels, greaterThan(0));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, 0);
    expect(tester.getTopLeft(monday).dy, greaterThanOrEqualTo(44));
  });

  testWidgets('Wide weekly list includes TA courses and DDL cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final due = DateTime(2026, 7, 29, 15);
    final session = _SignedInScheduleSessionController(
      timetable: _timetable(),
      timelineItems: [_deadline(due: due)],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });
    await taCourses.reload();
    final result = await taCourses.addEntry(
      const TaCourseEntry(
        id: 'weekly-list-ta',
        title: 'Weekly List TA',
        location: 'T2-201',
        weekday: DateTime.wednesday,
        startMinutes: 13 * 60,
        endMinutes: 14 * 60,
        repeatType: TaCourseRepeatType.weekly,
      ),
      expectedRevision: taCourses.revision,
    );
    expect(result.isSuccess, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime(2026, 7, 29, 8),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('schedule-list-day-2026-07-27')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-list-day-2026-08-02')),
      findsOneWidget,
    );
    final taCard = find.byKey(
      const ValueKey(
        'schedule-list-2026-07-29-course-schedule:weekly-list-ta-780',
      ),
    );
    final ddlCard = find.byKey(
      const ValueKey('schedule-list-2026-07-29-deadline-1'),
    );
    expect(taCard, findsOneWidget);
    expect(ddlCard, findsOneWidget);
    expect(
      tester.widget<BnbuSurfaceCard>(taCard).borderRadius,
      BorderRadius.zero,
    );
    expect(
      tester.widget<BnbuSurfaceCard>(ddlCard).borderRadius,
      BorderRadius.zero,
    );
  });

  testWidgets(
    'Schedule today follows Beijing time across a UTC date boundary',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _ScheduleSessionController(
        timetable: _timetable(),
        timelineItems: const [],
      );
      final taCourses = TaCourseController(sessionController: session);
      addTearDown(() {
        taCourses.dispose();
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: taCourses,
            now: DateTime.utc(2026, 7, 26, 17),
          ),
        ),
      );
      await tester.pump();
      final gridView = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '课表横表视图',
      );
      if (gridView.evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
        await tester.pumpAndSettle();
      }

      expect(find.text('周一 7/27'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('schedule-list-2026-07-27-course-ACC101-540'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Schedule shows official holiday names instead of classes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _calendarTimetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    Future<void> expectHoliday(DateTime now, String label) async {
      final campusDay = now.add(const Duration(hours: 8));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            key: ValueKey(now),
            controller: session,
            taCourseController: taCourses,
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (find
              .byKey(const ValueKey('schedule-list-day-2026-09-21'))
              .evaluate()
              .isEmpty &&
          find
              .byKey(const ValueKey('schedule-week-grid-horizontal-scroll'))
              .evaluate()
              .isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsWidgets);
      expect(
        find.byKey(
          ValueKey(
            'schedule-list-${campusDay.year.toString().padLeft(4, '0')}-'
            '${campusDay.month.toString().padLeft(2, '0')}-'
            '${campusDay.day.toString().padLeft(2, '0')}-course-ACC101-540',
          ),
        ),
        findsNothing,
      );
    }

    await expectHoliday(DateTime.utc(2026, 9, 24, 16), '中秋假期');
    await expectHoliday(DateTime.utc(2026, 9, 30, 16), '国庆假期');
    await expectHoliday(DateTime.utc(2026, 10, 25, 16), 'Reading Week 假期');
  });

  for (final size in const [
    Size(390, 844),
    Size(820, 1180),
    Size(900, 900),
    Size(1180, 820),
    Size(1440, 900),
  ]) {
    for (final holiday in [
      (DateTime.utc(2026, 9, 24, 16), '中秋假期'),
      (DateTime.utc(2026, 9, 30, 16), '国庆假期'),
      (DateTime.utc(2026, 10, 25, 16), 'Reading Week\n假期'),
    ]) {
      testWidgets(
        'Holiday label stays in the viewport at $size ${holiday.$2}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final session = _ScheduleSessionController(
            timetable: _calendarTimetable(),
            timelineItems: const [],
          );
          final taCourses = TaCourseController(sessionController: session);
          addTearDown(() {
            taCourses.dispose();
            session.dispose();
          });
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(
                platform: size.width > 1000
                    ? TargetPlatform.macOS
                    : TargetPlatform.iOS,
              ),
              home: SchedulePage(
                directoryService: _TeacherLinkDirectoryService(),
                controller: session,
                taCourseController: taCourses,
                now: holiday.$1,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scroll = tester
              .widget<ScheduleHolidayPanel>(
                find.byType(ScheduleHolidayPanel).first,
              )
              .scrollController;
          scroll.jumpTo(0);
          await tester.pump();
          // Compare the painted header, not its outer Container: the latter
          // includes margin and can hide a visible column-edge misalignment.
          for (final element in find.byType(ScheduleHolidayPanel).evaluate()) {
            final panel = element.renderObject! as RenderScheduleHolidayPanel;
            final panelKey = (element.widget.key! as ValueKey<String>).value;
            final header = find.byKey(
              ValueKey(
                panelKey.replaceFirst(
                  'schedule-holiday-block-',
                  'schedule-day-header-',
                ),
              ),
            );
            final headerSurface = find
                .descendant(of: header, matching: find.byType(DecoratedBox))
                .first;
            final headerRect = tester.getRect(headerSurface);
            final panelLeft = panel.localToGlobal(Offset.zero).dx;
            expect(headerRect.left, closeTo(panelLeft, 0.01));
            expect(
              headerRect.right,
              closeTo(panelLeft + panel.size.width, 0.01),
            );
          }
          final label = find.text(holiday.$2).first;
          final initialY = tester.getCenter(label).dy;
          scroll.jumpTo(scroll.position.maxScrollExtent.clamp(0, 160));
          await tester.pump();
          expect(
            tester.getCenter(label).dy,
            closeTo(initialY - scroll.offset, 0.01),
          );
          expect(tester.getRect(label).top, greaterThan(44));
          expect(tester.getRect(label).bottom, lessThan(size.height));
          for (final panel
              in tester.renderObjectList<RenderScheduleHolidayPanel>(
                find.byType(ScheduleHolidayPanel),
              )) {
            final painted = panel.visiblePanelBounds.shift(
              panel.localToGlobal(Offset.zero),
            );
            final gridTop = panel.localToGlobal(Offset.zero).dy;
            expect(
              painted.top,
              closeTo(gridTop.clamp(44.0, size.height), 0.01),
            );
            expect(
              painted.bottom,
              closeTo(
                (gridTop + panel.size.height).clamp(44.0, size.height),
                0.01,
              ),
            );
            expect(painted.width, closeTo(panel.size.width, 0.000001));
            expect(painted.height, lessThanOrEqualTo(size.height - 44));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Reading Week keeps its official dates and underlying time grid',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = _ScheduleSessionController(
        timetable: _calendarTimetable(),
        timelineItems: const [],
      );
      final taCourses = TaCourseController(sessionController: session);
      addTearDown(() {
        taCourses.dispose();
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: taCourses,
            now: DateTime.utc(2026, 10, 25, 16),
          ),
        ),
      );
      await tester.pump();

      final monday = find.byKey(
        const ValueKey('schedule-holiday-block-2026-10-26'),
      );
      final saturday = find.byKey(
        const ValueKey('schedule-holiday-block-2026-10-31'),
      );
      final sunday = find.byKey(
        const ValueKey('schedule-holiday-block-2026-11-01'),
      );
      expect(monday, findsOneWidget);
      expect(saturday, findsNothing);
      expect(sunday, findsNothing);
      expect(tester.getSize(monday).height, closeTo(900 - 44 - 28, .001));
      final sundayHeader = find.byKey(
        const ValueKey('schedule-day-header-2026-11-01'),
      );
      expect(
        tester.getSize(monday).width,
        closeTo(tester.getSize(sundayHeader).width * 1.5, .01),
      );
      expect(find.text('Reading Week\n假期'), findsOneWidget);
      final panel = tester.renderObject<RenderScheduleHolidayPanel>(monday);
      expect(
        panel.visiblePanelBounds.height,
        lessThanOrEqualTo(panel.size.height),
      );
    },
  );

  testWidgets('local TA courses remain visible during official MIS holidays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _SignedInScheduleSessionController(
      timetable: _calendarTimetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });
    await taCourses.reload();
    final result = await taCourses.addEntry(
      const TaCourseEntry(
        id: 'holiday-ta',
        title: 'Reading Week TA',
        location: 'T2-201',
        weekday: DateTime.wednesday,
        startMinutes: 13 * 60,
        endMinutes: 14 * 60,
        repeatType: TaCourseRepeatType.weekly,
      ),
      expectedRevision: taCourses.revision,
    );
    expect(result.isSuccess, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime.utc(2026, 10, 27, 16),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('schedule-course-block-3-780-schedule:holiday-ta'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-holiday-block-2026-10-26')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('schedule-course-block-3-780-schedule:holiday-ta'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reading Week TA'), findsWidgets);
    expect(
      find.byKey(const ValueKey('schedule-course-detail-modal')),
      findsOneWidget,
    );
  });

  testWidgets('Schedule maps October 10 to Monday make-up classes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _ScheduleSessionController(
      timetable: _calendarTimetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime.utc(2026, 10, 10, 1),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('schedule-course-block-6-540-ACC101')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('周六 10/10'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-list-2026-10-10-course-ACC101-540')),
      findsOneWidget,
    );
  });

  testWidgets('Mobile schedule lets large-text users choose list or grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 8, 2, 4);
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: [_deadline(due: now.add(const Duration(hours: 2)))],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: taCourses,
            now: now,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('schedule-view-toggle')), findsOneWidget);
    expect(find.text('Accessible Course'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '课表横表视图',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('schedule-view-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Accessible Deadline'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '课表竖表视图',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();

    final horizontalGrid = find.byKey(
      const ValueKey('schedule-week-grid-horizontal-scroll'),
    );
    expect(horizontalGrid, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(horizontalGrid).scrollDirection,
      Axis.horizontal,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '课表横表视图',
      ),
      findsOneWidget,
    );
    final horizontalScrollable = find.descendant(
      of: horizontalGrid,
      matching: find.byType(Scrollable),
    );
    final scrollableState = tester.state<ScrollableState>(horizontalScrollable);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0));
    expect(find.text('7/27–8/2'), findsOneWidget);
    await tester.drag(horizontalGrid, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('7/27–8/2'), findsOneWidget);
    expect(scrollableState.position.pixels, greaterThan(0));

    scrollableState.position.jumpTo(180);
    await tester.pump();
    expect(scrollableState.position.pixels, greaterThan(0));

    scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
    await tester.pump();
    await tester.drag(horizontalGrid, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('7/27–8/2'), findsOneWidget);
    await tester.drag(horizontalGrid, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('8/3–8/9'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('schedule.week_layout.v1.signed-out'), 'grid');
  });

  testWidgets(
    'Mobile weekday grid fits Monday through Friday without scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _ScheduleSessionController(
        timetable: _timetable(),
        timelineItems: const [],
      );
      final taCourses = TaCourseController(sessionController: session);
      addTearDown(() {
        taCourses.dispose();
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            controller: session,
            taCourseController: taCourses,
            now: DateTime.utc(2026, 8, 3, 1),
          ),
        ),
      );
      await tester.pump();

      final horizontalGrid = find.byKey(
        const ValueKey('schedule-week-grid-horizontal-scroll'),
      );
      expect(horizontalGrid, findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('Sat'), findsNothing);
      expect(find.text('Sun'), findsNothing);
      expect(
        tester.widget<SingleChildScrollView>(horizontalGrid).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      final horizontalScrollable = find.descendant(
        of: horizontalGrid,
        matching: find.byType(Scrollable),
      );
      final scrollableState = tester.state<ScrollableState>(
        horizontalScrollable,
      );
      expect(scrollableState.position.maxScrollExtent, 0);
    },
  );

  testWidgets('Mobile weekend content keeps all seven days on one screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final base = _timetable();
    final weekendCourse = TimetableCourse(
      section: '2',
      category: 'Core',
      code: 'SUN101',
      name: 'Sunday Course',
      teacher: 'Teacher',
      meetings: [
        TimetableMeeting(
          weekday: DateTime.sunday,
          dayLabel: 'Sun',
          startLabel: '10:00',
          endLabel: '10:50',
          startMinutes: 10 * 60,
          endMinutes: 10 * 60 + 50,
          room: 'T2-201',
        ),
      ],
      rooms: const ['T2-201'],
      units: '3',
      remark: '',
    );
    final session = _ScheduleSessionController(
      timetable: TimetableData(
        profile: base.profile,
        semesters: base.semesters,
        selectedSemesterId: base.selectedSemesterId,
        selectedSemesterName: base.selectedSemesterName,
        courses: [...base.courses, weekendCourse],
      ),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime.utc(2026, 8, 3, 1),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
    final horizontalGrid = find.byKey(
      const ValueKey('schedule-week-grid-horizontal-scroll'),
    );
    expect(
      tester.widget<SingleChildScrollView>(horizontalGrid).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    final scrollableState = tester.state<ScrollableState>(
      find.descendant(of: horizontalGrid, matching: find.byType(Scrollable)),
    );
    expect(scrollableState.position.maxScrollExtent, 0);
  });

  testWidgets('Schedule automatically displays MIS exam times', (tester) async {
    final session = _ScheduleSessionController(
      timetable: _examTimetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime.utc(2026, 12, 15, 1),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('schedule-exam-section')), findsOneWidget);
    expect(find.text('考试安排'), findsOneWidget);
    expect(find.text('12月15日 周二 · 09:00-11:00'), findsOneWidget);
    expect(find.text('Programming'), findsOneWidget);
    expect(find.text('T2-101 · 座位 18'), findsOneWidget);
    expect(find.text('闭卷，请携带学生证'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schedule-view-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('09:00-11:00'), findsOneWidget);
  });

  testWidgets('English schedule uses an abbreviated English month for exams', (
    tester,
  ) async {
    final session = _ScheduleSessionController(
      timetable: _examTimetable(),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime.utc(2026, 12, 15, 1),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dec 15 Tuesday · 09:00-11:00'), findsOneWidget);
    expect(find.textContaining('12月15日'), findsNothing);
  });

  testWidgets('same-course exams on one date use distinct stable widget keys', (
    tester,
  ) async {
    final timetable = _examTimetable();
    final session = _ScheduleSessionController(
      timetable: TimetableData(
        profile: timetable.profile,
        semesters: timetable.semesters,
        selectedSemesterId: timetable.selectedSemesterId,
        selectedSemesterName: timetable.selectedSemesterName,
        courses: timetable.courses,
        examAvailability: ExamTimetableAvailability.available,
        exams: [
          ...timetable.exams,
          ExamTimetableEntry(
            courseCode: 'COMP1001',
            courseName: 'Programming',
            date: DateTime(2026, 12, 15),
            startMinutes: 14 * 60,
            endMinutes: 16 * 60,
            room: 'T3-201',
            seat: '19',
            remark: '',
          ),
        ],
      ),
      timelineItems: const [],
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
          now: DateTime.utc(2026, 12, 15, 1),
        ),
      ),
    );
    await tester.pump();

    for (final exam in session.timetable!.exams) {
      expect(
        find.byKey(ValueKey('schedule-exam-${exam.widgetKey}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('initial timetable error remains pull-to-refreshable', (
    tester,
  ) async {
    final session = _RecoveringScheduleSessionController();
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SchedulePage(
          directoryService: _TeacherLinkDirectoryService(),
          controller: session,
          taCourseController: taCourses,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('课表加载失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-retry-button')), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(SliverFillRemaining), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schedule-retry-button')));
    await tester.pumpAndSettle();

    expect(session.refreshTimetableCount, 2, reason: '首次自动尝试失败后，下拉应发起第二次刷新');
    expect(find.text('课表加载失败'), findsNothing);
    expect(find.text('还没有加载到课表'), findsOneWidget);
  });

  testWidgets('Toolbar restores icons and preserves wide layout', (
    tester,
  ) async {
    final session = _ScheduleSessionController(
      timetable: _timetable(),
      timelineItems: const [],
      isLoading: true,
    );
    final taCourses = TaCourseController(sessionController: session);
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpAt(Size size, {ThemeData? theme}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.light,
          home: SchedulePage(
            directoryService: _TeacherLinkDirectoryService(),
            key: ValueKey(size.width),
            controller: session,
            taCourseController: taCourses,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('schedule-ta-icon'))),
        const Size.square(26),
      );
      expect(find.text('TA'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-locate-icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-locate-label')),
        findsOneWidget,
      );
      final todayLabel = tester.widget<Text>(
        find.byKey(const ValueKey('schedule-locate-label')),
      );
      expect(todayLabel.data, 'NOW');
      expect(
        todayLabel.style?.color,
        Theme.of(
          tester.element(find.byKey(const ValueKey('schedule-locate-label'))),
        ).extension<BnbuThemeExtension>()?.textPrimary,
      );
      expect(todayLabel.style?.fontSize, 7);
      final locateIcon = tester.getRect(
        find.byKey(const ValueKey('schedule-locate-icon')),
      );
      final locateLabel = tester.getRect(
        find.byKey(const ValueKey('schedule-locate-label')),
      );
      expect(locateLabel.center.dx, greaterThan(locateIcon.center.dx));
      expect(locateLabel.center.dy, greaterThan(locateIcon.center.dy));
      final taLabel = tester.widget<Text>(
        find.byKey(const ValueKey('schedule-ta-label')),
      );
      expect(taLabel.style?.color, todayLabel.style?.color);
      expect(
        taLabel.style?.fontSize,
        closeTo(todayLabel.style!.fontSize! * 1.12, 0.001),
      );
      final baseIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('schedule-ta-base-icon')),
      );
      expect(baseIcon.size, 18);
      final progress = tester.widget<BnbuUpdateProgress>(
        find.byKey(const ValueKey('schedule-loading-progress')),
      );
      expect(progress.height, 2);
      expect(progress.active, isTrue);
      if (size.width >= 700) {
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('schedule-toolbar')),
        );
        final centeredControls = tester.getRect(
          find.byKey(const ValueKey('schedule-wide-primary-controls')),
        );
        expect(centeredControls.center.dx, closeTo(toolbar.center.dx, 0.1));
        expect(
          tester
              .getRect(find.byKey(const ValueKey('schedule-view-toggle')))
              .right,
          lessThan(centeredControls.left),
        );
        expect(
          centeredControls.right,
          lessThan(
            tester
                .getRect(find.byKey(const ValueKey('schedule-deadline-toggle')))
                .left,
          ),
        );
      }
    }

    await pumpAt(const Size(390, 844));
    expect(find.text('课表'), findsNothing);
    expect(find.byType(SliverPersistentHeader), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('schedule-toolbar'))).height,
      44,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('schedule-view-toggle'))).left,
      lessThan(
        tester
            .getRect(find.byKey(const ValueKey('schedule-locate-action')))
            .left,
      ),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('schedule-deadline-toggle')))
          .left,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('schedule-ta-action'))).left,
      ),
    );
    final phoneWeekTitleRegion = tester.getRect(
      find.byKey(const ValueKey('schedule-phone-week-title-region')),
    );
    expect(
      phoneWeekTitleRegion.width,
      greaterThanOrEqualTo(
        tester
            .getSize(find.byKey(const ValueKey('schedule-week-range-label')))
            .width,
      ),
      reason: '移除日历图标后仍必须完整容纳日期文字',
    );
    final weekRangeText = tester.widget<Text>(
      find.byKey(const ValueKey('schedule-week-range-label')),
    );
    expect(weekRangeText.style?.fontSize, inInclusiveRange(13, 15.4));
    expect(weekRangeText.maxLines, 1);
    expect(weekRangeText.softWrap, isFalse);
    expect(weekRangeText.overflow, isNot(TextOverflow.ellipsis));
    expect(find.byKey(const ValueKey('schedule-week-range-fit')), findsNothing);
    await pumpAt(const Size(700, 900), theme: AppTheme.dark);
    await pumpAt(const Size(1440, 900));
    expect(find.text('课表'), findsNothing);
    expect(find.byType(SliverPersistentHeader), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('schedule-toolbar'))).height,
      44,
    );
    final toolbar = tester.getRect(
      find.byKey(const ValueKey('schedule-toolbar')),
    );
    final centeredControls = tester.getRect(
      find.byKey(const ValueKey('schedule-wide-primary-controls')),
    );
    expect(centeredControls.center.dx, closeTo(toolbar.center.dx, 0.1));
    expect(
      tester.getRect(find.byKey(const ValueKey('schedule-previous-week'))).left,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('schedule-week-picker'))).left,
      ),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('schedule-week-picker'))).right,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('schedule-next-week'))).right,
      ),
    );
    final selector = tester.getRect(
      find.byKey(const ValueKey('schedule-view-toggle')),
    );
    final deadline = tester.getRect(
      find.byKey(const ValueKey('schedule-deadline-toggle')),
    );
    final taAction = tester.getRect(
      find.byKey(const ValueKey('schedule-ta-action')),
    );
    expect(selector.left, lessThan(deadline.left));
    expect(deadline.right, lessThan(taAction.right));
    final ddlLabel = tester.widget<Text>(
      find.byKey(const ValueKey('schedule-deadline-label')),
    );
    expect(ddlLabel.data, 'DDL');
    expect(
      ddlLabel.style?.color,
      AppTheme.light.extension<BnbuThemeExtension>()?.danger,
    );
  });
}

class _RecoveringScheduleSessionController extends AppSessionController {
  String? _timetableError = 'MIS 暂时无法连接。';
  int refreshTimetableCount = 0;

  @override
  TimetableData? get timetable => null;

  @override
  List<TimelineItem> get timelineItems => const [];

  @override
  bool get isLoadingTimetable => false;

  @override
  String? get timetableError => _timetableError;

  @override
  Future<void> refreshTimetable() async {
    refreshTimetableCount++;
    if (refreshTimetableCount >= 2) {
      _timetableError = null;
    }
    notifyListeners();
  }

  @override
  Future<void> ensureTimetableLoaded() => refreshTimetable();

  @override
  Future<void> refreshTimeline() async {}
}

class _ScheduleSessionController extends AppSessionController {
  _ScheduleSessionController({
    required TimetableData timetable,
    required List<TimelineItem> timelineItems,
    this.isLoading = false,
  }) : _timetable = timetable,
       _timelineItems = timelineItems;

  final TimetableData _timetable;
  final List<TimelineItem> _timelineItems;

  final bool isLoading;

  @override
  TimetableData? get timetable => _timetable;

  @override
  List<TimelineItem> get timelineItems => _timelineItems;

  @override
  bool get isLoadingTimetable => isLoading;

  @override
  String? get timetableError => null;

  @override
  Future<void> refreshTimetable() async {}

  @override
  Future<void> refreshTimeline() async {}
}

class _SignedInScheduleSessionController extends _ScheduleSessionController {
  _SignedInScheduleSessionController({
    required super.timetable,
    required super.timelineItems,
  });

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student';
}

class _ControlledTeacherDirectory extends _TeacherLinkDirectoryService {
  final responses = <Completer<OfficialTeacherPage>>[];
  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) {
    final response = Completer<OfficialTeacherPage>();
    responses.add(response);
    return response.future;
  }
}

class _TeacherLinkDirectoryService implements CampusDirectoryService {
  _TeacherLinkDirectoryService({
    this.teacherName = 'Teacher',
    this.teacherNameEn = 'Teacher',
    this.matchType = OfficialTeacherMatchType.exact,
    this.total = 1,
  });

  final String teacherName;
  final String teacherNameEn;
  final OfficialTeacherMatchType matchType;
  final int total;
  String? lastQuery;

  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async =>
      const [];

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    lastQuery = query;
    return OfficialTeacherPage(
      items: total == 0
          ? const []
          : [
              OfficialTeacherProfile(
                name: teacherName,
                nameEn: teacherNameEn,
                email: 'teacher@bnbu.edu.cn',
                title: '讲师',
                titleEn: 'Lecturer',
                position: '',
                office: '',
                telephone: '',
                academicCn: '',
                academicEn: '',
                educationCn: '',
                educationEn: '',
                unitNames: const ['理工科技学院'],
                photoUrl: '',
                profileUrl: 'https://staff.bnbu.edu.cn/teacher/en',
                sourceUpdatedAt: null,
                matchType: matchType,
              ),
            ],
      total: total,
      offset: 0,
      limit: limit,
      units: const ['理工科技学院'],
    );
  }

  @override
  void dispose() {}
}

class _EmptyTeacherReviewService implements TeacherReviewService {
  @override
  Future<TeacherReviewMineState> loadMine(
    String username,
    String teacherKey,
  ) async => const TeacherReviewMineState(
    review: null,
    suspendedUntil: null,
    canReview: true,
  );

  @override
  Future<TeacherReviewPageData> loadReviews(
    String teacherKey, {
    bool courseLinkedOnly = false,
    int offset = 0,
    int limit = 50,
  }) async => const TeacherReviewPageData(
    summary: TeacherReviewSummary(
      count: 0,
      courseLinkedCount: 0,
      overallAverage: null,
      teachingEngagementAverage: null,
      gradingGenerosityAverage: null,
      attendanceFrequencyAverage: null,
      feedbackQualityAverage: null,
      courseWorkloadAverage: null,
    ),
    total: 0,
    offset: 0,
    limit: 50,
    items: [],
  );

  @override
  Future<TeacherReviewMineState> saveReview(
    String username,
    String teacherKey,
    TeacherReviewDraft draft,
  ) async => throw UnimplementedError();

  @override
  void dispose() {}
}

TimetableData _timetable({String teacher = 'Teacher'}) {
  return TimetableData(
    profile: TimetableProfile(
      studentId: 'student',
      name: 'Student',
      programme: 'Programme',
      year: '1',
    ),
    semesters: const [],
    selectedSemesterId: '2026',
    selectedSemesterName: '2026',
    courses: [
      TimetableCourse(
        section: '1',
        category: 'Core',
        code: 'ACC101',
        name: 'Accessible Course',
        teacher: teacher,
        meetings: [
          TimetableMeeting(
            weekday: DateTime.monday,
            dayLabel: 'Mon',
            startLabel: '9:00',
            endLabel: '9:50',
            startMinutes: 9 * 60,
            endMinutes: 9 * 60 + 50,
            room: 'T1-101',
          ),
        ],
        rooms: const ['T1-101'],
        units: '3',
        remark: '',
      ),
    ],
  );
}

TimetableData _calendarTimetable() {
  final timetable = _timetable();
  return TimetableData(
    profile: timetable.profile,
    semesters: timetable.semesters,
    selectedSemesterId: '2026-27-S1',
    selectedSemesterName: 'Semester 1 of AY2026-27',
    courses: timetable.courses,
  );
}

TimetableData _examTimetable() {
  final timetable = _timetable();
  return TimetableData(
    profile: timetable.profile,
    semesters: timetable.semesters,
    selectedSemesterId: timetable.selectedSemesterId,
    selectedSemesterName: timetable.selectedSemesterName,
    courses: timetable.courses,
    examAvailability: ExamTimetableAvailability.available,
    exams: [
      ExamTimetableEntry(
        courseCode: 'COMP1001',
        courseName: 'Programming',
        date: DateTime(2026, 12, 15),
        startMinutes: 9 * 60,
        endMinutes: 11 * 60,
        room: 'T2-101',
        seat: '18',
        remark: '闭卷，请携带学生证',
      ),
    ],
  );
}

TimelineItem _deadline({DateTime? due}) {
  final effectiveDue = due ?? DateTime.now().add(const Duration(hours: 2));
  return TimelineItem(
    id: 1,
    title: 'Accessible Deadline',
    activityState: '待提交',
    activityType: 'assign',
    moduleName: 'assign',
    description: '',
    courseName: 'Accessible Course',
    courseId: 1,
    instanceId: 1,
    url: '',
    sortTime: effectiveDue,
    formattedTime: '',
    isOverdue: false,
  );
}
