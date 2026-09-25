import 'dart:async';

import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/grade_report.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';
import 'package:bnbu_me/models/recent_course.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/services/bnbu_mis_client.dart';
import 'package:bnbu_me/services/credential_store.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'package:bnbu_me/services/moodle_api_client.dart';
import 'package:bnbu_me/services/native_actions.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'grade_report_parser_test.dart' show gradeReportFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'on demand only, in-flight merge, force refresh, failure retention and age limits',
    () async {
      var now = DateTime(2031);
      final mis = _Mis();
      final controller = _controller(mis, clock: () => now);
      addTearDown(controller.dispose);
      await expectLater(
        controller.loadGradeReport(),
        throwsA(isA<BnbuMisException>()),
      );
      await controller.login(username: 'synthetic-a', password: ' 原 密碼 ');
      expect(mis.calls, 0);
      expect(controller.cachedGradeReport, isNull);
      final gate = Completer<GradeReport>();
      mis.pending = gate;
      final a = controller.loadGradeReport();
      final b = controller.loadGradeReport(forceRefresh: true);
      expect(identical(a, b), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(mis.calls, 1);
      expect(mis.passwords.single, ' 原 密碼 ');
      gate.complete(mis.report);
      expect(await a, same(await b));
      expect(controller.cachedGradeReport, same(mis.report));
      mis.pending = null;
      await controller.loadGradeReport();
      expect(mis.calls, 1);
      await controller.loadGradeReport(forceRefresh: true);
      expect(mis.calls, 2);
      now = now.subtract(const Duration(minutes: 1));
      expect(controller.cachedGradeReport, isNull);
      await controller.loadGradeReport();
      expect(mis.calls, 3);
      now = now.add(const Duration(minutes: 3));
      mis.fail = true;
      await expectLater(
        controller.loadGradeReport(),
        throwsA(isA<BnbuMisException>()),
      );
      expect(controller.cachedGradeReport, same(mis.report));
      now = now.add(const Duration(minutes: 28));
      expect(controller.cachedGradeReport, isNull);
      mis.fail = false;
      await controller.loadGradeReport();
      expect(mis.calls, 5);
    },
  );

  for (final change in ['logout', 'switch', 'relogin', 'dispose']) {
    test(
      '$change clears cache and rejects late response without disturbing new flight',
      () async {
        final mis = _Mis();
        final controller = _controller(mis);
        if (change != 'dispose') addTearDown(controller.dispose);
        await controller.login(username: 'synthetic-a', password: 'test-only');
        await controller.loadGradeReport();
        final oldGate = Completer<GradeReport>();
        mis.pending = oldGate;
        final old = controller.loadGradeReport(forceRefresh: true);
        final rejected = expectLater(old, throwsA(isA<BnbuMisException>()));
        await Future<void>.delayed(Duration.zero);
        if (change == 'dispose') {
          controller.dispose();
        } else if (change == 'logout') {
          await controller.logout();
        } else {
          await controller.login(
            username: change == 'switch' ? 'synthetic-b' : 'synthetic-a',
            password: 'new-test-only',
          );
        }
        expect(controller.cachedGradeReport, isNull);
        Completer<GradeReport>? newGate;
        Future<GradeReport>? fresh;
        if (change == 'switch' || change == 'relogin') {
          newGate = Completer<GradeReport>();
          mis.pending = newGate;
          fresh = controller.loadGradeReport();
          await Future<void>.delayed(Duration.zero);
        }
        oldGate.complete(mis.report);
        await rejected;
        expect(controller.cachedGradeReport, isNull);
        if (fresh != null) {
          expect(controller.loadGradeReport(), same(fresh));
          newGate!.complete(mis.report);
          await fresh;
          expect(controller.cachedGradeReport, same(mis.report));
        }
      },
    );
  }

  test(
    'study window never accesses MIS even after restoring a session',
    () async {
      final mis = _Mis();
      final controller = AppSessionController.studyWindow(
        misClient: mis,
        apiClient: _Moodle(),
        credentialStore: _Store()
          ..credentials = const StoredCredentials(
            username: 'synthetic',
            password: 'test-only',
          ),
        deadlineReminderService: _Reminders(),
      );
      addTearDown(controller.dispose);
      await controller.restoreSessionIfPossible();
      await expectLater(
        controller.loadGradeReport(),
        throwsA(isA<BnbuMisException>()),
      );
      expect(controller.cachedGradeReport, isNull);
      expect(mis.calls, 0);
    },
  );

  test('invalid fake result cannot replace a successful snapshot', () async {
    final mis = _Mis();
    final controller = _controller(mis);
    addTearDown(controller.dispose);
    await controller.login(username: 'synthetic', password: 'test-only');
    final good = await controller.loadGradeReport();
    mis.report = const GradeReport.unavailable();
    await expectLater(
      controller.loadGradeReport(forceRefresh: true),
      throwsA(isA<BnbuMisException>()),
    );
    expect(controller.cachedGradeReport, same(good));
  });
}

AppSessionController _controller(_Mis mis, {DateTime Function()? clock}) =>
    AppSessionController(
      misClient: mis,
      apiClient: _Moodle(),
      credentialStore: _Store(),
      gradeReportClock: clock,
      deadlineReminderService: _Reminders(),
      nativeActions: const _Native(),
      mailVerifier: (_) async {},
    );

class _Mis extends BnbuMisClient {
  int calls = 0;
  bool fail = false;
  Completer<GradeReport>? pending;
  GradeReport report = GradeReport.fromHtml(gradeReportFixture());
  final passwords = <String>[];
  @override
  Future<GradeReport> fetchGradeReport({
    required String username,
    required String password,
  }) async {
    calls++;
    passwords.add(password);
    if (fail) throw BnbuMisException('synthetic failure');
    return pending == null ? report : await pending!.future;
  }

  @override
  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) async => throw BnbuMisException('synthetic offline');
}

class _Moodle extends MoodleApiClient {
  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async => AuthSession(
    token: 'synthetic',
    fullName: 'Synthetic',
    userId: 1,
    runtimeProfile: MoodleRuntimeProfile(
      release: 'test',
      version: 'test',
      functionVersions: const {},
      downloadFiles: false,
      uploadFiles: false,
      advancedFeatures: const {},
      userMaxUploadFileSize: 0,
    ),
  );
  @override
  Future<List<TimelineItem>> fetchAllTimeline({required String token}) async =>
      [];
  @override
  Future<List<CourseSummary>> fetchMyCourses({
    required String token,
    required int userId,
  }) async => [];
  @override
  Future<List<RecentCourse>> fetchRecentCourses({
    required String token,
    required int userId,
    int limit = 10,
  }) async => [];
}

class _Store implements CredentialStore {
  StoredCredentials? credentials;
  @override
  Future<void> clear() async {
    credentials = null;
  }

  @override
  Future<StoredCredentials?> load() async => credentials;
  @override
  Future<void> save(StoredCredentials value) async {
    credentials = value;
  }
}

class _Reminders extends DeadlineReminderService {
  @override
  Future<bool> loadEnabled() async => false;
  @override
  Future<void> disable() async {}
  @override
  Future<void> disableCourseNotifications() async {}
  @override
  Future<void> synchronize(List<TimelineItem> items) async {}
  @override
  Future<void> cancelAll() async {}
}

class _Native extends NativeActions {
  const _Native();
  @override
  Future<void> clearWebSession() async {}
}
