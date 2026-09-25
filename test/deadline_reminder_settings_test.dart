import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/live_activity_preference_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    testWidgets('notification switches update on $platform without reopening', (
      tester,
    ) async {
      final reminderService = _MemoryDeadlineReminderService();
      final controller = AppSessionController(
        deadlineReminderService: reminderService,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: UserPage(controller: controller),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('通知与同步'));
      await tester.pumpAndSettle();

      expect(find.text('共享前台活跃状态'), findsNothing);
      expect(
        find.byKey(const ValueKey('usage-activity-sharing')),
        findsNothing,
      );
      expect(find.textContaining('此设备已开始共享'), findsNothing);
      expect(find.text('服务端同步与使用状态'), findsNothing);
      expect(_switchValue(tester, 'deadline-reminder-toggle'), isFalse);
      expect(_switchValue(tester, 'course-reminder-toggle'), isFalse);
      expect(
        find.byKey(const ValueKey('deadline-reminder-lead')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('course-reminder-lead')), findsNothing);
      await tester.tap(_switchFinder('deadline-reminder-toggle'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(reminderService.enabled, isTrue);
      expect(controller.isDeadlineReminderEnabled, isTrue);
      expect(_switchValue(tester, 'deadline-reminder-toggle'), isTrue);
      expect(
        find.byKey(const ValueKey('deadline-reminder-lead')),
        findsOneWidget,
      );
      expect(find.text('智能提醒 · 3 次'), findsOneWidget);

      await tester.tap(_switchFinder('course-reminder-toggle'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(reminderService.courseEnabled, isTrue);
      expect(controller.isCourseReminderEnabled, isTrue);
      expect(_switchValue(tester, 'course-reminder-toggle'), isTrue);
      expect(reminderService.enabled, isTrue);
      expect(
        find.byKey(const ValueKey('course-reminder-lead')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('course-reminder-lead')),
          matching: find.text('15 分钟'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('course-reminder-lead')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 分钟'));
      await tester.pumpAndSettle();

      expect(reminderService.courseLeadMinutes, 30);
      expect(controller.courseReminderLeadMinutes, 30);
      expect(find.text('30 分钟'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('deadline-reminder-lead')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('deadline-smart-explanation')),
      );
      await tester.pumpAndSettle();
      expect(find.text('智能提醒如何工作'), findsOneWidget);
      expect(find.text('默认三次提醒'), findsOneWidget);
      expect(find.text('自动避开免打扰'), findsOneWidget);
      expect(find.text('睡前统一提醒'), findsOneWidget);
      expect(find.text('避免连续打扰'), findsOneWidget);
      expect(find.text('两个例子'), findsNothing);
      expect(
        find.text(
          '23:59 截止的较晚提醒会尽量提前到 22:00 左右；10:00 截止时，夜间提醒会提前到前一晚，08:00 的最后提醒仍可保留。',
        ),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('deadline-smart-explanation-close')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('deadline-reminder-settings-modal')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('deadline-reminder-count-2')));
      await tester.tap(
        find.byKey(const ValueKey('deadline-reminder-settings-save')),
      );
      await tester.pumpAndSettle();

      expect(reminderService.deadlinePreferences.reminderCount, 2);
      expect(controller.deadlineReminderPreferences.reminderCount, 2);
      expect(find.text('智能提醒 · 2 次'), findsOneWidget);

      await tester.tap(_switchFinder('course-reminder-toggle'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('course-reminder-lead')), findsNothing);
      expect(
        find.byKey(const ValueKey('deadline-reminder-lead')),
        findsOneWidget,
      );

      await tester.tap(_switchFinder('deadline-reminder-toggle'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('deadline-reminder-lead')),
        findsNothing,
      );

      await tester.tap(_switchFinder('course-reminder-toggle'));
      await tester.tap(_switchFinder('deadline-reminder-toggle'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('30 分钟'), findsOneWidget);
      expect(find.text('智能提醒 · 2 次'), findsOneWidget);
      expect(controller.courseReminderLeadMinutes, 30);
      expect(controller.deadlineReminderPreferences.reminderCount, 2);
    });
  }

  testWidgets('自定义课表通知时间接受 5–120 分钟', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reminderService = _MemoryDeadlineReminderService();
    final controller = AppSessionController(
      deadlineReminderService: reminderService,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: UserPage(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('通知与同步'));
    await tester.pumpAndSettle();
    await tester.tap(_switchFinder('course-reminder-toggle'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.courseReminderLeadMinutes, 15);
    await tester.tap(find.byKey(const ValueKey('course-reminder-lead')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notification-lead-option-5')),
      findsOneWidget,
    );
    expect(find.text('1 分钟'), findsNothing);
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(find.text('5–120 分钟'), findsOneWidget);
    final input = find.byKey(
      const ValueKey('ios-live-activity-custom-time-input'),
    );
    final save = find.byKey(
      const ValueKey('ios-live-activity-custom-time-save'),
    );
    await tester.enterText(input, '0');
    await tester.tap(save);
    await tester.pump();
    expect(find.text('请输入 5–120 分钟'), findsOneWidget);

    await tester.enterText(input, '5');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(controller.courseReminderLeadMinutes, 5);
    expect(reminderService.courseLeadMinutes, 5);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('course-reminder-lead')),
        matching: find.text('5 分钟'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('DDL 自定义时间在同一弹层内添加并保存', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reminderService = _MemoryDeadlineReminderService();
    final controller = AppSessionController(
      deadlineReminderService: reminderService,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: UserPage(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('通知与同步'));
    await tester.pumpAndSettle();
    await tester.tap(_switchFinder('deadline-reminder-toggle'));
    await tester.pump(const Duration(milliseconds: 500));
    final deadlineLead = find.byKey(const ValueKey('deadline-reminder-lead'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(deadlineLead);
    await tester.pumpAndSettle();
    await tester.tap(find.text('固定提醒'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('deadline-fixed-lead-1440')));
    await tester.tap(find.byKey(const ValueKey('deadline-fixed-lead-480')));
    await tester.tap(find.byKey(const ValueKey('deadline-fixed-lead-120')));
    await tester.tap(
      find.byKey(const ValueKey('deadline-reminder-add-custom')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('deadline-custom-hours-input')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('deadline-custom-minutes-input')),
      '15',
    );
    await tester.tap(find.byKey(const ValueKey('deadline-custom-add')));
    await tester.pump();

    expect(find.text('1 小时 15 分钟'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('deadline-reminder-settings-modal')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('deadline-reminder-settings-save')),
    );
    await tester.pumpAndSettle();

    expect(
      reminderService.deadlinePreferences.mode,
      DeadlineReminderMode.fixed,
    );
    expect(reminderService.deadlinePreferences.fixedLeadMinutes, <int>[75]);
    expect(find.text('1 小时 15 分钟'), findsOneWidget);
  });

  testWidgets('DDL 提醒逻辑入口与基准时间左边缘对齐', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reminderService = _MemoryDeadlineReminderService();
    final controller = AppSessionController(
      deadlineReminderService: reminderService,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: UserPage(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('通知与同步'));
    await tester.pumpAndSettle();
    await tester.tap(_switchFinder('deadline-reminder-toggle'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deadline-reminder-lead')));
    await tester.pumpAndSettle();

    final baseline = find.text('约提前 24 小时、8 小时、2 小时');
    final explanation = find.byKey(
      const ValueKey('deadline-smart-explanation'),
    );
    final infoIcon = find.descendant(
      of: explanation,
      matching: find.byIcon(LucideIcons.info300),
    );
    expect(infoIcon, findsOneWidget);
    expect(
      tester.getTopLeft(infoIcon).dx,
      closeTo(tester.getTopLeft(baseline).dx, 0.5),
    );
  });

  testWidgets('通知内容与灵动岛内容可独立选择', (tester) async {
    final reminderService = _MemoryDeadlineReminderService();
    final controller = AppSessionController(
      deadlineReminderService: reminderService,
    );
    final liveActivityController = LiveActivityPreferenceController();
    addTearDown(controller.dispose);
    addTearDown(liveActivityController.dispose);
    await liveActivityController.restore();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: UserPage(
          controller: controller,
          liveActivityController: liveActivityController,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('通知与同步'));
    await tester.pumpAndSettle();

    final courseNotification = find.byKey(
      const ValueKey('course-reminder-toggle'),
    );
    final deadlineNotification = find.byKey(
      const ValueKey('deadline-reminder-toggle'),
    );
    final courseIsland = find.byKey(
      const ValueKey('ios-live-activity-course-enabled'),
    );
    final deadlineIsland = find.byKey(
      const ValueKey('ios-live-activity-deadline-enabled'),
    );

    expect(find.text('课表通知'), findsOneWidget);
    expect(find.text('DDL 通知'), findsOneWidget);
    expect(find.text('课表上岛'), findsOneWidget);
    expect(find.text('DDL 上岛'), findsOneWidget);

    await tester.tap(
      find.descendant(of: courseNotification, matching: find.byType(Switch)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(reminderService.courseEnabled, isTrue);
    expect(reminderService.enabled, isFalse);
    expect(liveActivityController.courseEnabled, isTrue);
    expect(liveActivityController.deadlineEnabled, isFalse);

    await tester.tap(
      find.descendant(of: deadlineIsland, matching: find.byType(Switch)),
    );
    await tester.pump();

    expect(liveActivityController.deadlineEnabled, isTrue);
    expect(reminderService.courseEnabled, isTrue);
    expect(reminderService.enabled, isFalse);
    expect(
      find.descendant(of: deadlineNotification, matching: find.byType(Switch)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: courseIsland, matching: find.byType(Switch)),
      findsOneWidget,
    );
  });
}

bool _switchValue(WidgetTester tester, String key) {
  final switchFinder = _switchFinder(key);
  expect(switchFinder, findsOneWidget);
  return tester.widget<Switch>(switchFinder).value;
}

Finder _switchFinder(String key) {
  return find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Switch),
  );
}

class _MemoryDeadlineReminderService extends DeadlineReminderService {
  bool enabled = false;
  bool courseEnabled = false;
  int deadlineLeadMinutes = DeadlineReminderService.defaultDeadlineLeadMinutes;
  DeadlineReminderPreferences deadlinePreferences =
      const DeadlineReminderPreferences();
  int courseLeadMinutes = DeadlineReminderService.defaultCourseLeadMinutes;

  @override
  Future<bool> loadEnabled() async => enabled;

  @override
  Future<String?> enable() async {
    enabled = true;
    return null;
  }

  @override
  Future<void> disable() async {
    enabled = false;
  }

  @override
  Future<void> synchronize(List<TimelineItem> items) async {}

  @override
  Future<int> loadDeadlineLeadMinutes() async => deadlineLeadMinutes;

  @override
  Future<int> setDeadlineLeadMinutes(int value) async {
    deadlineLeadMinutes = value;
    return value;
  }

  @override
  Future<DeadlineReminderPreferences> loadDeadlineReminderPreferences() async =>
      deadlinePreferences;

  @override
  Future<DeadlineReminderPreferences> setDeadlineReminderPreferences(
    DeadlineReminderPreferences value,
  ) async {
    deadlinePreferences = value;
    deadlineLeadMinutes = value.effectiveLeadMinutes.first;
    return value;
  }

  @override
  Future<bool> loadCourseEnabled() async => courseEnabled;

  @override
  Future<String?> enableCourseNotifications() async {
    courseEnabled = true;
    return null;
  }

  @override
  Future<void> disableCourseNotifications() async {
    courseEnabled = false;
  }

  @override
  Future<int> loadCourseLeadMinutes() async => courseLeadMinutes;

  @override
  Future<int> setCourseLeadMinutes(int value) async {
    courseLeadMinutes = value;
    return value;
  }
}
