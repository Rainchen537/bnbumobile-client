import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'notification lead times use safe defaults and persist choices',
    () async {
      final service = DeadlineReminderService();

      expect(
        await service.loadCourseLeadMinutes(),
        DeadlineReminderService.defaultCourseLeadMinutes,
      );
      expect(
        await service.loadDeadlineLeadMinutes(),
        DeadlineReminderService.defaultDeadlineLeadMinutes,
      );

      expect(await service.setCourseLeadMinutes(5), 5);
      expect(await service.setDeadlineLeadMinutes(75), 75);
      expect(await service.loadCourseLeadMinutes(), 5);
      expect(await service.loadDeadlineLeadMinutes(), 75);
    },
  );

  test(
    'legacy one-to-four-minute course reminders migrate to five minutes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'course_reminders.lead_minutes': 1,
      });
      final service = DeadlineReminderService();

      expect(await service.loadCourseLeadMinutes(), 5);
      expect(await service.setCourseLeadMinutes(4), 5);
    },
  );

  test(
    'out-of-range notification lead times return to safe defaults',
    () async {
      final service = DeadlineReminderService();

      expect(
        await service.setCourseLeadMinutes(121),
        DeadlineReminderService.defaultCourseLeadMinutes,
      );
      expect(
        await service.setDeadlineLeadMinutes(2881),
        DeadlineReminderService.defaultDeadlineLeadMinutes,
      );
    },
  );

  test(
    'new DDL preferences default to three smart reminders and midnight quiet hours',
    () async {
      final service = DeadlineReminderService();

      final preferences = await service.loadDeadlineReminderPreferences();

      expect(preferences.mode, DeadlineReminderMode.smart);
      expect(preferences.reminderCount, 3);
      expect(preferences.quietStartMinutes, 0);
      expect(preferences.quietEndMinutes, 360);
      expect(preferences.effectiveLeadMinutes, <int>[1440, 480, 120]);
    },
  );

  test(
    'legacy single DDL lead time migrates without unexpectedly adding reminders',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'deadline_reminders.lead_minutes': 75,
      });
      final service = DeadlineReminderService();

      final preferences = await service.loadDeadlineReminderPreferences();

      expect(preferences.mode, DeadlineReminderMode.fixed);
      expect(preferences.fixedLeadMinutes, <int>[75]);
    },
  );
}
