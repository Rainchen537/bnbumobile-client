import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/campus_time.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'fixed_schedule_weeks_test.dart' show calendarTimetable, weeklyEntry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final pending = <int, Map<String, Object?>>{};
  var failSchedule = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({'course_reminders.enabled': true});
    pending.clear();
    failSchedule = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'pendingNotificationRequests':
              return pending.values.toList();
            case 'cancel':
              pending.remove(call.arguments);
              return null;
            case 'zonedSchedule':
              if (failSchedule) {
                throw PlatformException(code: 'permission_denied');
              }
              final args = call.arguments as Map;
              pending[args['id'] as int] = {
                'id': args['id'],
                'title': args['title'],
                'body': args['body'],
                'payload': args['payload'],
              };
              return null;
            default:
              throw StateError('Unexpected native operation: ${call.method}');
          }
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'native queue uses saved weeks, cancels removed instances and respects disabled switch',
    () async {
      final service = DeadlineReminderService();
      final now = toBnbuCampusClock(DateTime.now());
      final week = TaCourseEntry.normalizeWeekStart(
        DateTime(now.year, now.month, now.day + 7),
      );
      final entry = weeklyEntry(weeks: [week]);
      final timetable = calendarTimetable(name: 'synthetic');
      await service.synchronizeCourses(timetable, fixedSchedules: [entry]);
      expect(pending, hasLength(1));
      final firstIds = pending.keys.toSet();
      await service.synchronizeCourses(timetable, fixedSchedules: [entry]);
      expect(pending.keys.toSet(), firstIds);
      await service.synchronizeCourses(
        timetable,
        fixedSchedules: [entry.copyWith(activeWeekStarts: [])],
      );
      expect(pending, isEmpty);
      await service.synchronizeCourses(timetable, fixedSchedules: [entry]);
      expect(pending, hasLength(1));
      await service.disableCourseNotifications();
      expect(pending, isEmpty);
      await service.synchronizeCourses(timetable, fixedSchedules: [entry]);
      expect(pending, isEmpty);
    },
  );
  test(
    'failed system scheduling is observable and leaves no successful instance',
    () async {
      final service = DeadlineReminderService();
      final now = toBnbuCampusClock(DateTime.now());
      final week = TaCourseEntry.normalizeWeekStart(
        DateTime(now.year, now.month, now.day + 7),
      );
      failSchedule = true;
      await expectLater(
        service.synchronizeCourses(
          calendarTimetable(name: 'synthetic'),
          fixedSchedules: [
            weeklyEntry(weeks: [week]),
          ],
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(pending, isEmpty);
    },
  );
}
