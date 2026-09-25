import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/home_overview.dart';
import 'package:bnbu_me/pages/home_page.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/timeline_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/home_navigation_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'navigation keeps the existing order with the reference shell across widths',
    (tester) async {
      final session = HomeNavigationFixture();
      final shell = RootShellController();
      final mail = MailAssistantIntentController();
      final ta = TaCourseController(sessionController: session);
      addTearDown(() {
        ta.dispose();
        mail.dispose();
        shell.dispose();
        session.dispose();
        tester.view.reset();
      });
      tester.view.devicePixelRatio = 1;
      final initialized = <AppTab, int>{};
      final semantics = tester.ensureSemantics();

      const labels = ['首页', '邮箱', 'iSpace', '课表', '我的'];
      const tabs = [
        AppTab.home,
        AppTab.mail,
        AppTab.ispace,
        AppTab.schedule,
        AppTab.user,
      ];
      for (final width in [390.0, 699.0, 700.0, 900.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: RootShellPage(
              controller: session,
              shellController: shell,
              taCourseController: ta,
              mailIntentController: mail,
              pageOverrideBuilder: (tab) => _NavigationProbe(
                tab: tab,
                onInit: () => initialized.update(
                  tab,
                  (count) => count + 1,
                  ifAbsent: () => 1,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final wide = width >= 700;
        final prefix = wide ? 'root-side-navigation' : 'root-bottom-navigation';
        expect(
          find.byKey(
            ValueKey(
              wide ? 'root-bottom-navigation' : 'root-side-navigation-panel',
            ),
          ),
          findsNothing,
        );
        if (wide) {
          final brand = tester.widget<Image>(
            find.byKey(const ValueKey('root-side-navigation-brand-logo')),
          );
          expect(
            (brand.image as AssetImage).assetName,
            'assets/branding/sidebar_logo.png',
          );
          expect(brand.semanticLabel, 'BNBU.ME');
          expect(brand.width, 40);
          expect(brand.height, 40);

          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('root-side-navigation-panel')),
                )
                .width,
            72,
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('root-side-navigation-panel')),
                )
                .height,
            900,
          );
          expect(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('root-side-navigation-brand-logo')),
                )
                .dy,
            24,
          );
          shell.setNavigationExpanded(!shell.navigationExpanded);
          await tester.pump();
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('root-side-navigation-panel')),
                )
                .width,
            72,
          );
        }
        var previous = -1.0;
        for (var i = 0; i < tabs.length; i++) {
          final finder = find.byKey(
            ValueKey('$prefix-destination-${labels[i]}'),
          );
          final rect = tester.getRect(finder);
          expect(wide ? rect.top : rect.left, greaterThan(previous));
          previous = wide ? rect.top : rect.left;
          expect(rect.height, greaterThanOrEqualTo(44));
          if (wide) expect(rect.width, 56);
          await tester.tap(finder);
          await tester.pump();
          expect(shell.selectedTab, tabs[i]);
          expect(
            tester
                .getSemantics(find.bySemanticsLabel(labels[i]))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(find.text('page-${tabs[i].name}'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      await tester.pump();
      final safeRail = tester.getRect(
        find.byKey(const ValueKey('root-side-navigation-panel')),
      );
      expect(safeRail.top, 24);
      expect(safeRail.height, 876);
      expect(initialized.keys, unorderedEquals(tabs));
      expect(initialized.values, everyElement(1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(shell.selectedTab, AppTab.mail);
      expect(shell.selectedIndex, AppTab.mail.index);
      semantics.dispose();
    },
  );

  testWidgets(
    'service entries keep three compact columns and four wide columns',
    (tester) async {
      final session = HomeNavigationFixture();
      addTearDown(() {
        session.dispose();
        tester.view.reset();
      });

      Future<List<Rect>> pumpAt(double width, {double textScale = 1}) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: HomePage(
                controller: session,
                clock: () => HomeNavigationFixture.now,
                onGoToIspace: () {},
                onGoToSchedule: () {},
                onGoToUser: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        return [
          for (final label in const ['政教信息', '统一门户', 'iSpace', 'ME生活'])
            tester.getRect(find.byKey(ValueKey('home-quick-action-$label'))),
        ];
      }

      final compact = await pumpAt(390);
      expect(compact[0].top, compact[1].top);
      expect(compact[1].top, compact[2].top);
      expect(compact[3].top, greaterThan(compact[0].bottom));

      final compactLargeText = await pumpAt(390, textScale: 2);
      expect(compactLargeText[0].top, compactLargeText[1].top);
      expect(compactLargeText[1].top, compactLargeText[2].top);
      expect(compactLargeText[3].top, greaterThan(compactLargeText[0].bottom));

      final wide = await pumpAt(900);
      expect(wide.map((rect) => rect.top).toSet(), hasLength(1));

      final wider = await pumpAt(1200);
      expect(wider.map((rect) => rect.top).toSet(), hasLength(1));
      expect(wider.first.width, greaterThan(wide.first.width));
    },
  );

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets(
      'service redesign preserves the original home overview at $width',
      (tester) async {
        final session = HomeNavigationFixture();
        HomeCourseOccurrence? opened;
        addTearDown(() {
          session.dispose();
          tester.view.reset();
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1200);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: HomePage(
              controller: session,
              clock: () => HomeNavigationFixture.now,
              onGoToIspace: () {},
              onGoToSchedule: () {},
              onGoToUser: () {},
              onOpenCourse: (course) => opened = course,
            ),
          ),
        );
        await tester.pump();
        final nextFinder = find.byKey(const ValueKey('home-next-course-card'));
        final next = tester.getRect(nextFinder);
        final due = tester.getRect(
          find.byKey(const ValueKey('home-recent-task-card')),
        );
        final services = tester.getRect(
          find.byKey(const ValueKey('home-quick-access-panel')),
        );
        expect(due.left, next.left);
        expect(due.top - next.bottom, closeTo(12, .1));
        expect(services.top - due.bottom, closeTo(24, .1));
        if (width < 700) {
          expect(
            find.byKey(const ValueKey('home-expanded-date-panel')),
            findsNothing,
          );
          expect(next.left, 16);
        } else {
          final date = tester.getRect(
            find.byKey(const ValueKey('home-expanded-date-panel')),
          );
          expect(date.width, 184);
          expect(date.height, 276);
          expect(date.top, next.top);
          expect(date.bottom, due.bottom);
          expect(next.height, due.height);
        }
        expect(find.byType(BnbuTimelineSummaryCard), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home-course-accent')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('timeline-summary-ispace-label-1')),
          findsOneWidget,
        );
        expect(find.text('Assignment 01: Understanding users'), findsOneWidget);
        expect(find.text('Problem Set 02'), findsNothing);
        expect(find.text('Academic Writing'), findsNothing);
        await tester.tap(nextFinder);
        await tester.pump();
        expect(opened?.course.code, 'COMP 3023');
        expect(opened?.startsAt, DateTime.utc(2026, 9, 7, 2));
        expect(opened?.meeting.room, 'T29 / 203');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _NavigationProbe extends StatefulWidget {
  const _NavigationProbe({required this.tab, required this.onInit});
  final AppTab tab;
  final VoidCallback onInit;
  @override
  State<_NavigationProbe> createState() => _NavigationProbeState();
}

class _NavigationProbeState extends State<_NavigationProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('page-${widget.tab.name}'));
}
