import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/home_page.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/pages/login_page.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home uses one wide composition on tablet and desktop', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpAt(
      Size size, {
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: textScaler),
            child: HomePage(
              controller: controller,
              onGoToIspace: () {},
              onGoToSchedule: () {},
              onGoToUser: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpAt(const Size(900, 1000));
    final mediumDate = tester.getRect(
      find.byKey(const ValueKey('home-expanded-date-panel')),
    );
    final mediumCourse = tester.getRect(
      find.byKey(const ValueKey('home-next-course-card')),
    );
    final mediumDeadline = tester.getRect(
      find.byKey(const ValueKey('home-recent-task-card')),
    );
    final mediumAccent = tester.getRect(
      find.byKey(const ValueKey('home-course-accent')),
    );
    final mediumServices = tester.getRect(
      find.byKey(const ValueKey('home-quick-access-panel')),
    );
    expect(find.byKey(const ValueKey('home-wide-workspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-study-mode-panel')), findsNothing);
    expect(find.text('今日概览'), findsNothing);
    expect(find.text('校园服务'), findsNothing);
    expect(mediumCourse.left, closeTo(mediumDeadline.left, 0.1));
    expect(mediumCourse.top, closeTo(mediumDate.top, 0.1));
    expect(mediumDeadline.bottom, closeTo(mediumDate.bottom, 0.1));
    expect(mediumCourse.height, closeTo(mediumDeadline.height, 0.1));
    expect(mediumDeadline.top - mediumCourse.bottom, closeTo(12, 0.1));
    expect(mediumAccent.height, closeTo(mediumCourse.height, 0.1));
    expect(mediumServices.top, greaterThan(mediumDeadline.bottom));

    await pumpAt(const Size(1440, 1000));
    final expandedDate = tester.getRect(
      find.byKey(const ValueKey('home-expanded-date-panel')),
    );
    final expandedCourse = tester.getRect(
      find.byKey(const ValueKey('home-next-course-card')),
    );
    final expandedDeadline = tester.getRect(
      find.byKey(const ValueKey('home-recent-task-card')),
    );
    final expandedAccent = tester.getRect(
      find.byKey(const ValueKey('home-course-accent')),
    );
    final services = tester.getRect(
      find.byKey(const ValueKey('home-quick-access-panel')),
    );
    expect(find.byKey(const ValueKey('home-wide-workspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-study-mode-panel')), findsNothing);
    expect(find.text('学业模式'), findsNothing);
    expect(find.text('最近文件'), findsNothing);
    expect(find.text('最近动态'), findsNothing);
    expect(find.text('今日概览'), findsNothing);
    expect(find.text('校园服务'), findsNothing);
    expect(expandedCourse.left, closeTo(expandedDeadline.left, 0.1));
    expect(expandedCourse.top, closeTo(expandedDate.top, 0.1));
    expect(expandedDeadline.bottom, closeTo(expandedDate.bottom, 0.1));
    expect(expandedCourse.height, closeTo(expandedDeadline.height, 0.1));
    expect(expandedDeadline.top - expandedCourse.bottom, closeTo(12, 0.1));
    expect(expandedAccent.height, closeTo(expandedCourse.height, 0.1));
    expect(services.top, greaterThan(expandedDeadline.bottom));

    await pumpAt(
      const Size(1440, 1000),
      textScaler: const TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
    final largeTextDate = tester.getRect(
      find.byKey(const ValueKey('home-expanded-date-panel')),
    );
    final largeTextCourse = tester.getRect(
      find.byKey(const ValueKey('home-next-course-card')),
    );
    final largeTextDeadline = tester.getRect(
      find.byKey(const ValueKey('home-recent-task-card')),
    );
    expect(largeTextCourse.top, closeTo(largeTextDate.top, 0.1));
    expect(largeTextDeadline.bottom, closeTo(largeTextDate.bottom, 0.1));
  });

  testWidgets(
    'root shell keeps iSpace navigation reachable across rail widths',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final sessionController = _AdaptiveIspaceController();
      final shellController = RootShellController();
      final mailIntentController = MailAssistantIntentController();
      final taCourseController = TaCourseController(
        sessionController: sessionController,
      );
      shellController.selectTab(AppTab.ispace);
      addTearDown(sessionController.dispose);
      addTearDown(shellController.dispose);
      addTearDown(mailIntentController.dispose);
      addTearDown(taCourseController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RootShellPage(
            controller: sessionController,
            shellController: shellController,
            taCourseController: taCourseController,
            mailIntentController: mailIntentController,
            pageOverrideBuilder: (tab) => tab == AppTab.ispace
                ? IspacePage(
                    controller: sessionController,
                    onGoToUserTab: () {},
                  )
                : SizedBox(key: ValueKey('root-ispace-test-${tab.name}')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 240));

      expect(
        tester
            .getSize(find.byKey(const ValueKey('root-side-navigation-panel')))
            .width,
        72,
      );
      expect(
        find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
        findsOneWidget,
      );
      final coursesHeader = find.text('课程');
      expect(
        find.byKey(const ValueKey('ispace-primary-myCourses')),
        findsNothing,
      );
      await tester.tap(coursesHeader);
      await tester.pumpAndSettle();
      await tester.tap(coursesHeader);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ispace-timeline-filter-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ispace-my-courses-navigation-button')),
        findsNothing,
      );
      expect(find.byType(AppBar), findsNothing);

      shellController.setNavigationExpanded(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));

      expect(
        tester
            .getSize(find.byKey(const ValueKey('root-side-navigation-panel')))
            .width,
        72,
      );
      expect(
        find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const ValueKey('ispace-timeline-filter-control')),
        findsOneWidget,
      );
    },
  );

  testWidgets('login switches to a split workspace on large windows', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: LoginPage(controller: controller),
      ),
    );

    expect(find.byKey(const ValueKey('login-wide-layout')), findsOneWidget);
    expect(find.text('连接你的校园生活'), findsOneWidget);
    expect(find.text('课程、课表、邮箱和校园服务，在一个适合键盘与大屏使用的工作区中完成。'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'desktop-user');
    expect(find.text('desktop-user'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: LoginPage(controller: controller),
      ),
    );
    expect(find.byKey(const ValueKey('login-wide-layout')), findsNothing);
  });
}

class _AdaptiveIspaceController extends AppSessionController {
  @override
  bool get isLoggedIn => true;
}
