import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';

import '../tool/home_navigation_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (platform, glass) in [
    (TargetPlatform.iOS, false),
    (TargetPlatform.android, false),
    (TargetPlatform.iOS, true),
  ]) {
    testWidgets(
      'iSpace menus retain root navigation and geometry $platform glass=$glass',
      (tester) async {
        await _mount(tester, platform, glass: glass);
        final bar = find.byKey(const ValueKey('root-bottom-navigation'));
        if (glass) {
          expect(
            find.byKey(const ValueKey('root-ios-liquid-glass-navigation')),
            findsOneWidget,
          );
        }
        final card = find.byKey(const ValueKey('ispace-timeline-card-1'));
        final bounds = tester.getRect(card);
        final barBounds = tester.getRect(bar);
        for (final name in ['filter', 'sort']) {
          final control = find.byKey(ValueKey('ispace-timeline-$name-control'));
          await tester.tap(control);
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(bar, findsOneWidget);
            expect(tester.getRect(bar), barBounds);
            expect(tester.getRect(card), bounds);
          }
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(bar, findsOneWidget);
          await tester.tap(control);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate((widget) => widget is PopupMenuItem).first,
          );
          await tester.pumpAndSettle();
          expect(bar, findsOneWidget);
          expect(tester.getRect(bar), barBounds);
        }
        await tester.tap(
          find.byKey(const ValueKey('ispace-timeline-filter-control')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate((widget) => widget is PopupMenuItem).at(1),
        );
        await tester.pumpAndSettle();
        expect(bar, findsOneWidget);
        expect(tester.getRect(bar), barBounds);
        await tester.tap(
          find.byKey(const ValueKey('ispace-timeline-sort-control')),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(380, 650));
        await tester.pumpAndSettle();
        expect(bar, findsOneWidget);
      },
    );
  }

  testWidgets(
    'only dashboard edge opens drawer; section and detail swipe back',
    (tester) async {
      await _mount(tester, TargetPlatform.iOS);
      await _swipe(tester);
      expect(_scaffold(tester).isDrawerOpen, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('ispace-navigation-course-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic course'), findsOneWidget);
      final cancel = await tester.startGesture(const Offset(1, 300));
      await cancel.moveBy(const Offset(35, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await cancel.up();
      await tester.pumpAndSettle();
      expect(find.text('Synthetic course'), findsOneWidget);
      expect(_scaffold(tester).isDrawerOpen, isFalse);
      final context = tester.element(find.text('Synthetic course'));
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Synthetic detail')),
            body: const Center(child: Text('Detail body')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _swipe(tester);
      expect(_scaffold(tester).isDrawerOpen, isFalse);
      expect(find.text('Synthetic detail'), findsNothing);
      expect(find.text('Synthetic course'), findsOneWidget);
      await _swipe(tester);
      expect(_scaffold(tester).isDrawerOpen, isFalse);
      expect(
        find.byKey(const ValueKey('ispace-timeline-filter-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('root-bottom-navigation')),
        findsOneWidget,
      );
      await _swipe(tester);
      expect(_scaffold(tester).isDrawerOpen, isTrue);
      _scaffold(tester).closeDrawer();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'section survives resizing and visible back returns to dashboard',
    (tester) async {
      await _mount(tester, TargetPlatform.iOS);
      await tester.tap(
        find.byKey(const ValueKey('ispace-top-bar-navigation-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ispace-navigation-course-1')),
      );
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic course'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic course'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ispace-section-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ispace-timeline-filter-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('root-bottom-navigation')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Android drawer closes before section back and inactive tab does not pop',
    (tester) async {
      final shell = await _mount(tester, TargetPlatform.android);
      await tester.tap(
        find.byKey(const ValueKey('ispace-top-bar-navigation-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ispace-navigation-course-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ispace-top-bar-navigation-button')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_scaffold(tester).isDrawerOpen, isFalse);
      expect(find.text('Synthetic course'), findsOneWidget);
      shell.selectTab(AppTab.user);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      shell.selectTab(AppTab.ispace);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic course'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ispace-timeline-filter-control')),
        findsOneWidget,
      );
    },
  );
}

ScaffoldState _scaffold(WidgetTester tester) => tester.state<ScaffoldState>(
  find
      .descendant(
        of: find.byType(IspacePage),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scaffold && widget.drawer != null,
        ),
      )
      .first,
);

Future<void> _swipe(WidgetTester tester) async {
  await tester.flingFrom(const Offset(1, 300), const Offset(330, 0), 1000);
  await tester.pumpAndSettle();
}

Future<RootShellController> _mount(
  WidgetTester tester,
  TargetPlatform platform, {
  bool glass = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final session = _Session();
  final shell = RootShellController()..selectTab(AppTab.ispace);
  final mail = MailAssistantIntentController();
  final ta = TaCourseController(sessionController: session);
  final appearance = AppThemeModeController(
    liquidGlassSupportLoader: () async => true,
  );
  await appearance.restore();
  await appearance.setLiquidGlassEnabled(glass);
  addTearDown(appearance.dispose);
  addTearDown(() {
    ta.dispose();
    mail.dispose();
    shell.dispose();
    session.dispose();
    tester.view.reset();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: (glass ? AppTheme.dark : AppTheme.light).copyWith(
        platform: platform,
      ),
      builder: (_, child) =>
          BnbuLiquidGlassScope(controller: appearance, child: child!),
      home: RootShellPage(
        controller: session,
        shellController: shell,
        taCourseController: ta,
        mailIntentController: mail,
        pageOverrideBuilder: (tab) =>
            tab == AppTab.ispace ? null : const SizedBox(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

class _Session extends HomeNavigationFixture {
  @override
  List<CourseSummary> get courses => [
    CourseSummary(
      id: 1,
      fullName: 'Synthetic course',
      shortName: 'TEST 101',
      categoryName: '',
      progress: 0,
    ),
  ];
  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async =>
      [];
}
