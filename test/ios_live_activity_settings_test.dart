import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/live_activity_preference_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('iPhone 用户可更改灵动岛提醒规则', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sessionController = AppSessionController();
    final liveActivityController = LiveActivityPreferenceController();
    addTearDown(sessionController.dispose);
    addTearDown(liveActivityController.dispose);
    await liveActivityController.restore();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: UserPage(
          controller: sessionController,
          liveActivityController: liveActivityController,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('通知与同步'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ios-live-activity-enabled')),
      findsOneWidget,
    );
    final courseSetting = find.byKey(
      const ValueKey('ios-live-activity-course-enabled'),
    );
    final deadlineSetting = find.byKey(
      const ValueKey('ios-live-activity-deadline-enabled'),
    );
    expect(courseSetting, findsOneWidget);
    expect(deadlineSetting, findsOneWidget);
    expect(find.text('课表上岛'), findsOneWidget);
    expect(find.text('DDL 上岛'), findsOneWidget);
    expect(find.text('提前 15 分钟'), findsOneWidget);
    expect(find.text('提前 12 小时'), findsNothing);
    expect(find.text('上课后关闭'), findsOneWidget);
    expect(liveActivityController.courseDismissAfterStartMinutes, 5);
    expect(find.text('5 分钟'), findsOneWidget);
    expect(liveActivityController.deadlineEnabled, isFalse);
    expect(
      find.byKey(const ValueKey('ios-live-activity-deadline-lead')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: deadlineSetting, matching: find.byType(Switch)),
    );
    await tester.pump();
    expect(liveActivityController.deadlineEnabled, isTrue);
    expect(find.text('提前 12 小时'), findsOneWidget);

    await tester.tap(
      find.descendant(of: courseSetting, matching: find.byType(Switch)),
    );
    await tester.pump();
    expect(liveActivityController.courseEnabled, isFalse);
    expect(liveActivityController.deadlineEnabled, isTrue);
    expect(
      find.byKey(const ValueKey('ios-live-activity-class-lead')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ios-live-activity-course-dismiss-delay')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ios-live-activity-deadline-lead')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: courseSetting, matching: find.byType(Switch)),
    );
    await tester.pump();
    expect(liveActivityController.courseEnabled, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-course-dismiss-delay')),
    );
    await tester.pumpAndSettle();
    expect(find.text('0–20 分钟'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('ios-live-activity-custom-time-input')),
      '15',
    );
    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-custom-time-save')),
    );
    await tester.pumpAndSettle();
    expect(liveActivityController.courseDismissAfterStartMinutes, 15);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('ios-live-activity-course-dismiss-delay'),
        ),
        matching: find.text('15 分钟'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-course-dismiss-delay')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ios-live-activity-custom-time-input')),
      '21',
    );
    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-custom-time-save')),
    );
    await tester.pump();
    expect(find.text('请输入 0–20 分钟'), findsOneWidget);
    expect(liveActivityController.courseDismissAfterStartMinutes, 15);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-class-lead')),
    );
    await tester.pumpAndSettle();
    expect(find.text('提前 5 分钟'), findsOneWidget);
    expect(find.text('提前 1 分钟'), findsNothing);
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('5–120 分钟'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey('ios-live-activity-custom-time-save')),
          )
          .bottom,
      lessThanOrEqualTo(524),
    );
    await tester.enterText(
      find.byKey(const ValueKey('ios-live-activity-custom-time-input')),
      '121',
    );
    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-custom-time-save')),
    );
    await tester.pump();
    expect(find.text('请输入 5–120 分钟'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('ios-live-activity-custom-time-input')),
      '120',
    );
    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-custom-time-save')),
    );
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pump();
    expect(liveActivityController.classLeadMinutes, 120);
    expect(find.text('提前 120 分钟'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-deadline-lead')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey('ios-live-activity-custom-deadline-time-save'),
            ),
          )
          .bottom,
      lessThanOrEqualTo(524),
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('ios-live-activity-custom-deadline-hours-input'),
      ),
      '0',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('ios-live-activity-custom-deadline-minutes-input'),
      ),
      '30',
    );
    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-custom-deadline-time-save')),
    );
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pump();
    expect(liveActivityController.deadlineLeadMinutes, 30);
    expect(find.text('提前 30 分钟'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ios-live-activity-deadline-lead')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('不提醒'));
    await tester.pumpAndSettle();
    expect(liveActivityController.deadlineLeadMinutes, 0);
    expect(liveActivityController.deadlineEnabled, isFalse);
    expect(
      find.byKey(const ValueKey('ios-live-activity-deadline-lead')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: deadlineSetting, matching: find.byType(Switch)),
    );
    await tester.pump();
    expect(liveActivityController.deadlineEnabled, isTrue);
    expect(liveActivityController.deadlineLeadMinutes, 720);
    expect(find.text('提前 12 小时'), findsOneWidget);

    final enabledSetting = find.byKey(
      const ValueKey('ios-live-activity-enabled'),
    );
    await tester.tap(
      find.descendant(of: enabledSetting, matching: find.byType(Switch)),
    );
    await tester.pump();

    expect(liveActivityController.enabled, isFalse);
    expect(
      find.byKey(const ValueKey('ios-live-activity-course-enabled')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ios-live-activity-deadline-enabled')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ios-live-activity-class-lead')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ios-live-activity-deadline-lead')),
      findsNothing,
    );
  });
}
