import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/services/widget_snapshot_service.dart';
import 'package:bnbu_me/state/app_language_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/live_activity_preference_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Watch language sync does not depend on timetable or login data',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final sessionController = AppSessionController();
      final taCourseController = TaCourseController(
        sessionController: sessionController,
      );
      final liveActivityController = LiveActivityPreferenceController();
      final languageController = AppLanguageController();
      final gateway = _RecordingWidgetSnapshotGateway();
      final coordinator = WidgetSnapshotCoordinator(
        sessionController: sessionController,
        taCourseController: taCourseController,
        liveActivityController: liveActivityController,
        languageController: languageController,
        gateway: gateway,
      );
      addTearDown(coordinator.dispose);
      addTearDown(taCourseController.dispose);
      addTearDown(liveActivityController.dispose);
      addTearDown(languageController.dispose);
      addTearDown(sessionController.dispose);

      await languageController.setMode(AppLanguageMode.english);
      coordinator.start();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(gateway.interfaceLanguages, <String>['en']);

      await languageController.setMode(AppLanguageMode.traditionalChinese);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(gateway.interfaceLanguages, <String>['en', 'zh-Hant']);

      await languageController.setMode(AppLanguageMode.chinese);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(gateway.interfaceLanguages, <String>['en', 'zh-Hant', 'zh-Hans']);
      expect(gateway.payloads, isEmpty);
      expect(gateway.clearCount, greaterThanOrEqualTo(3));
    },
  );

  test(
    'logged-in Mac writes an empty snapshot before school data loads',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final sessionController = _LoggedInSessionController();
      final taCourseController = TaCourseController(
        sessionController: sessionController,
      );
      final liveActivityController = LiveActivityPreferenceController();
      final gateway = _RecordingWidgetSnapshotGateway();
      final coordinator = WidgetSnapshotCoordinator(
        sessionController: sessionController,
        taCourseController: taCourseController,
        liveActivityController: liveActivityController,
        gateway: gateway,
      );
      addTearDown(coordinator.dispose);
      addTearDown(taCourseController.dispose);
      addTearDown(liveActivityController.dispose);
      addTearDown(sessionController.dispose);

      coordinator.start();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(gateway.payloads, hasLength(1));
      expect(gateway.payloads.single, contains('"courses":[]'));
      expect(gateway.payloads.single, contains('"deadlines":[]'));
    },
  );

  test(
    'transient shared-container failure retries the same snapshot',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final sessionController = _LoggedInSessionController();
      final taCourseController = TaCourseController(
        sessionController: sessionController,
      );
      final liveActivityController = LiveActivityPreferenceController();
      final gateway = _FailOnceWidgetSnapshotGateway();
      final coordinator = WidgetSnapshotCoordinator(
        sessionController: sessionController,
        taCourseController: taCourseController,
        liveActivityController: liveActivityController,
        gateway: gateway,
        debounceDuration: const Duration(milliseconds: 5),
        retryDuration: const Duration(milliseconds: 10),
      );
      addTearDown(coordinator.dispose);
      addTearDown(taCourseController.dispose);
      addTearDown(liveActivityController.dispose);
      addTearDown(sessionController.dispose);

      coordinator.start();
      await gateway.firstSuccessfulUpdate.future.timeout(
        const Duration(seconds: 5),
      );

      expect(gateway.updateAttempts, 2);
      expect(gateway.payloads, hasLength(1));
    },
  );
}

class _LoggedInSessionController extends AppSessionController {
  @override
  bool get isLoggedIn => true;

  @override
  TimetableData? get timetable => null;

  @override
  List<TimelineItem> get timelineItems => const <TimelineItem>[];
}

class _RecordingWidgetSnapshotGateway implements WidgetSnapshotGateway {
  final List<String> interfaceLanguages = <String>[];
  final List<String> payloads = <String>[];
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
  }

  @override
  Future<void> update(String json) async {
    payloads.add(json);
  }

  @override
  Future<void> updateInterfaceLanguage(String languageTag) async {
    interfaceLanguages.add(languageTag);
  }
}

class _FailOnceWidgetSnapshotGateway extends _RecordingWidgetSnapshotGateway {
  int updateAttempts = 0;
  final firstSuccessfulUpdate = Completer<void>();

  @override
  Future<void> update(String json) async {
    updateAttempts++;
    if (updateAttempts == 1) {
      throw PlatformException(code: 'widget_store_unavailable');
    }
    await super.update(json);
    if (!firstSuccessfulUpdate.isCompleted) firstSuccessfulUpdate.complete();
  }
}
