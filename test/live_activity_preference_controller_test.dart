import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/state/live_activity_preference_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('灵动岛提醒规则使用安全默认值并持久化用户选择', () async {
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.restore();
    expect(controller.enabled, isTrue);
    expect(controller.courseEnabled, isTrue);
    expect(controller.deadlineEnabled, isFalse);
    expect(controller.classLeadMinutes, 15);
    expect(controller.courseDismissAfterStartMinutes, 5);
    expect(controller.deadlineLeadMinutes, 720);

    await controller.setEnabled(false);
    await controller.setClassLeadMinutes(73);
    await controller.setCourseDismissAfterStartMinutes(17);
    await controller.setDeadlineLeadMinutes(90);

    final restored = LiveActivityPreferenceController();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.enabled, isFalse);
    expect(restored.courseEnabled, isTrue);
    expect(restored.deadlineEnabled, isTrue);
    expect(restored.classLeadMinutes, 73);
    expect(restored.courseDismissAfterStartMinutes, 17);
    expect(restored.deadlineLeadMinutes, 90);
    expect(restored.toJson(), <String, Object>{
      'enabled': false,
      'courseEnabled': true,
      'deadlineEnabled': true,
      'classLeadMinutes': 73,
      'courseDismissAfterStartMinutes': 17,
      'deadlineLeadMinutes': 90,
    });
  });

  test('课程与 DDL 上岛内容可以独立选择并恢复', () async {
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.setDeadlineEnabled(true);
    await controller.setCourseEnabled(false);
    expect(controller.courseEnabled, isFalse);
    expect(controller.deadlineEnabled, isTrue);

    final restored = LiveActivityPreferenceController();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.courseEnabled, isFalse);
    expect(restored.deadlineEnabled, isTrue);
    expect(restored.classLeadMinutes, 15);
    expect(restored.deadlineLeadMinutes, 720);
  });

  test('上课与 DDL 可以分别选择不提醒', () async {
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.setClassLeadMinutes(0);
    await controller.setDeadlineLeadMinutes(0);

    final restored = LiveActivityPreferenceController();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.classLeadMinutes, 0);
    expect(restored.deadlineLeadMinutes, 0);
    expect(restored.courseEnabled, isFalse);
    expect(restored.deadlineEnabled, isFalse);
  });

  test('重新开启已设为不提醒的内容会恢复安全默认时间', () async {
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.setClassLeadMinutes(0);
    await controller.setDeadlineLeadMinutes(0);
    await controller.setCourseEnabled(true);
    await controller.setDeadlineEnabled(true);

    expect(controller.courseEnabled, isTrue);
    expect(controller.deadlineEnabled, isTrue);
    expect(controller.classLeadMinutes, 15);
    expect(controller.deadlineLeadMinutes, 720);
  });

  test('DDL 自定义提醒最早可设为提前 30 分钟', () async {
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.setDeadlineLeadMinutes(30);

    final restored = LiveActivityPreferenceController();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.deadlineLeadMinutes, 30);
  });

  test('课程灵动岛提前时间接受 5–120 分钟', () async {
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.setClassLeadMinutes(5);
    expect(controller.classLeadMinutes, 5);

    await controller.setClassLeadMinutes(120);
    final restored = LiveActivityPreferenceController();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.classLeadMinutes, 120);
  });

  test('旧版一至四分钟课程上岛设置迁移为五分钟', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LiveActivityPreferenceController.classLeadMinutesPreferenceKey: 1,
    });
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.classLeadMinutes, 5);
    expect(controller.courseEnabled, isTrue);
  });

  test('课程灵动岛可在上课当刻至二十分钟后关闭', () async {
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.setCourseDismissAfterStartMinutes(0);
    expect(controller.courseDismissAfterStartMinutes, 0);
    expect(controller.courseEnabled, isTrue);

    await controller.setCourseDismissAfterStartMinutes(20);
    final restored = LiveActivityPreferenceController();
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.courseDismissAfterStartMinutes, 20);
    expect(restored.courseEnabled, isTrue);
  });

  test('非法的提醒提前时间恢复为默认规则', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LiveActivityPreferenceController.classLeadMinutesPreferenceKey: 999,
      LiveActivityPreferenceController
              .courseDismissAfterStartMinutesPreferenceKey:
          21,
      LiveActivityPreferenceController.deadlineLeadMinutesPreferenceKey: -1,
    });
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.classLeadMinutes, 15);
    expect(controller.courseDismissAfterStartMinutes, 5);
    expect(controller.deadlineLeadMinutes, 720);
  });

  test('旧版 DDL 小时设置会换算为分钟', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LiveActivityPreferenceController.legacyDeadlineLeadHoursPreferenceKey: 24,
    });
    final controller = LiveActivityPreferenceController();
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.deadlineLeadMinutes, 1440);
  });
}
