import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first use enables both reminders without persisting preferences',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = DeadlineReminderService();

      expect(await service.loadEnabled(), isTrue);
      expect(await service.loadCourseEnabled(), isTrue);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(await service.loadCourseLeadMinutes(), 15);
    },
  );

  for (final ddl in <bool>[false, true]) {
    for (final course in <bool>[false, true]) {
      test('preserves saved DDL=$ddl and course=$course choices', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'deadline_reminders.enabled': ddl,
          'course_reminders.enabled': course,
        });
        final service = DeadlineReminderService();

        expect(await service.loadEnabled(), ddl);
        expect(await service.loadCourseEnabled(), course);
      });
    }
  }

  test('missing course preference does not overwrite disabled DDL', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deadline_reminders.enabled': false,
    });
    final service = DeadlineReminderService();
    expect(await service.loadEnabled(), isFalse);
    expect(await service.loadCourseEnabled(), isTrue);
  });

  test('missing DDL preference does not overwrite disabled course', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'course_reminders.enabled': false,
    });
    final service = DeadlineReminderService();
    expect(await service.loadEnabled(), isTrue);
    expect(await service.loadCourseEnabled(), isFalse);
  });
}
