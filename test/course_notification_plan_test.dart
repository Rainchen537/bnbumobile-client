import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';

void main() {
  test('课表通知按北京时间生成并遵守调休', () {
    final service = DeadlineReminderService();
    final timetable = TimetableData(
      profile: TimetableProfile(
        studentId: '2600000000',
        name: '测试学生',
        programme: 'FST',
        year: '1',
      ),
      semesters: [
        TimetableSemester(
          id: 'AY2026-27-S1',
          name: 'Semester 1 of AY2026-27',
          isSelected: true,
        ),
      ],
      selectedSemesterId: 'AY2026-27-S1',
      selectedSemesterName: 'Semester 1 of AY2026-27',
      courses: [
        TimetableCourse(
          section: '1001',
          category: '',
          code: 'TEST1001',
          name: '课程通知测试',
          teacher: '测试教师',
          meetings: [
            TimetableMeeting(
              weekday: DateTime.friday,
              dayLabel: 'Fri',
              startLabel: '10:00',
              endLabel: '11:50',
              startMinutes: 10 * 60,
              endMinutes: 11 * 60 + 50,
              room: 'T2-101',
            ),
          ],
          rooms: const ['T2-101'],
          units: '3',
          remark: '',
        ),
      ],
    );

    final plan = service.buildCourseNotificationPlanForTesting(
      timetable,
      now: DateTime.utc(2026, 9, 18, 16),
    );

    expect(plan, isNotEmpty);
    expect(plan.first['title'], '课程通知测试');
    expect(plan.first['body'], 'T2-101 · 北京时间 10:00–11:50');
    expect(
      (plan.first['triggerAt']! as DateTime).toUtc(),
      DateTime.utc(2026, 9, 20, 1, 45),
      reason: '9 月 20 日周日补周五课，应按默认值在北京时间 09:45 提醒',
    );
    expect(plan.first['payload'], 'bnbume://schedule');

    final customPlan = service.buildCourseNotificationPlanForTesting(
      timetable,
      now: DateTime.utc(2026, 9, 18, 16),
      leadMinutes: 30,
    );
    expect(
      (customPlan.first['triggerAt']! as DateTime).toUtc(),
      DateTime.utc(2026, 9, 20, 1, 30),
      reason: '用户选择提前 30 分钟后，应按该值重新计算通知时间',
    );
  });

  test('DDL 智能通知默认生成 24 小时、8 小时和 2 小时三次提醒', () {
    final service = DeadlineReminderService();
    final due = DateTime(2026, 9, 21, 12);
    final item = TimelineItem(
      id: 1,
      title: 'Essay',
      activityState: '',
      activityType: 'assignment',
      moduleName: 'assign',
      description: '',
      courseName: 'Academic English',
      courseId: 2,
      instanceId: 3,
      url: 'https://ispace.bnbu.edu.cn/mod/assign/view.php?id=1',
      sortTime: due,
      formattedTime: '',
      isOverdue: false,
    );

    final plan = service.buildDeadlineNotificationPlanForTesting([
      item,
    ], now: DateTime(2026, 9, 19));

    expect(plan, hasLength(3));
    expect(plan.map((entry) => entry['triggerAt']), <DateTime>[
      DateTime(2026, 9, 20, 12),
      DateTime(2026, 9, 20, 23, 50),
      DateTime(2026, 9, 21, 10),
    ]);
    expect(plan.every((entry) => entry['payload'] == item.url), isTrue);
  });

  test('DDL 夜间提醒提前到免打扰前并合并临近截止事项', () {
    final service = DeadlineReminderService();
    final items = <TimelineItem>[
      _deadline(id: 1, title: 'Morning quiz', due: DateTime(2026, 9, 22, 5)),
      _deadline(id: 2, title: 'Early essay', due: DateTime(2026, 9, 22, 6, 30)),
    ];

    final plan = service.buildDeadlineNotificationPlanForTesting(
      items,
      now: DateTime(2026, 9, 21, 12),
      preferences: const DeadlineReminderPreferences(
        quietStartMinutes: 0,
        quietEndMinutes: 360,
      ),
    );

    final digest = plan.where(
      (entry) => entry['triggerAt'] == DateTime(2026, 9, 21, 23, 50),
    );
    expect(digest, hasLength(1));
    expect(digest.single['title'], '免打扰前：2 项 DDL');
    expect(digest.single['body'], contains('Morning quiz'));
    expect(digest.single['body'], contains('Early essay'));
    expect(digest.single['payload'], 'bnbume://ispace');
  });

  test('DDL 固定提醒接受 30 分钟至 48 小时且最多三次', () {
    final service = DeadlineReminderService();
    final due = DateTime(2026, 9, 24, 18);
    final plan = service.buildDeadlineNotificationPlanForTesting(
      [_deadline(id: 3, title: 'Project', due: due)],
      now: DateTime(2026, 9, 21),
      preferences: const DeadlineReminderPreferences(
        mode: DeadlineReminderMode.fixed,
        fixedLeadMinutes: <int>[2880, 360, 30],
      ),
    );

    expect(plan, hasLength(3));
    expect(plan.map((entry) => entry['triggerAt']), <DateTime>[
      DateTime(2026, 9, 22, 18),
      DateTime(2026, 9, 24, 12),
      DateTime(2026, 9, 24, 17, 30),
    ]);
  });

  test('上午截止的 DDL 会把夜间提醒提前到自定义免打扰之前', () {
    final service = DeadlineReminderService();
    final plan = service.buildDeadlineNotificationPlanForTesting(
      [
        _deadline(
          id: 4,
          title: 'Morning submission',
          due: DateTime(2026, 9, 22, 10),
        ),
      ],
      now: DateTime(2026, 9, 21, 9),
      preferences: const DeadlineReminderPreferences(
        quietStartMinutes: 22 * 60,
        quietEndMinutes: 6 * 60,
      ),
    );

    expect(plan.map((entry) => entry['triggerAt']), <DateTime>[
      DateTime(2026, 9, 21, 10),
      DateTime(2026, 9, 21, 21, 50),
      DateTime(2026, 9, 22, 8),
    ]);
  });

  test('DDL 调整后不足两小时的提醒会合并', () {
    final service = DeadlineReminderService();
    final plan = service.buildDeadlineNotificationPlanForTesting([
      _deadline(id: 5, title: 'Early deadline', due: DateTime(2026, 9, 22, 7)),
    ], now: DateTime(2026, 9, 20, 12));

    expect(plan, hasLength(2));
    expect(plan.map((entry) => entry['triggerAt']), <DateTime>[
      DateTime(2026, 9, 21, 7),
      DateTime(2026, 9, 21, 23, 50),
    ]);
  });
}

TimelineItem _deadline({
  required int id,
  required String title,
  required DateTime due,
}) {
  return TimelineItem(
    id: id,
    title: title,
    activityState: '',
    activityType: 'assignment',
    moduleName: 'assign',
    description: '',
    courseName: 'Test Course',
    courseId: 2,
    instanceId: id,
    url: 'https://ispace.bnbu.edu.cn/mod/assign/view.php?id=$id',
    sortTime: due,
    formattedTime: '',
    isOverdue: false,
  );
}
