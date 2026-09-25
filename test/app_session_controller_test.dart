import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/exam_timetable.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';
import 'package:bnbu_me/models/recent_course.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/services/bnbu_mis_client.dart';
import 'package:bnbu_me/services/credential_store.dart';
import 'package:bnbu_me/models/mail_login_settings.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/state/mail_access_controller.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'package:bnbu_me/services/moodle_api_client.dart';
import 'package:bnbu_me/services/native_actions.dart';
import 'package:bnbu_me/services/timetable_cache_store.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/services/cis_checkin_client.dart';

import 'fixtures/cis_checkin_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CIS reuses central school credentials, not the independent mailbox password',
    () async {
      final logins = <Map<String, dynamic>>[];
      final client = CisCheckinClient(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            logins.add(
              (jsonDecode(request.body) as Map).cast<String, dynamic>(),
            );
            return http.Response(
              jsonEncode({
                'result': {'token': 'synthetic-cis'},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(checkinEnvelope([checkinProjectJson()])),
            200,
          );
        }),
      );
      final store = _MemoryCredentialStore();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        checkinClient: client,
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        mailVerifier: (_) async {},
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.loadCheckinProjects(),
        throwsA(isA<CisCheckinException>()),
      );
      expect(logins, isEmpty);
      await controller.login(username: 'synthetic-a', password: ' 学校原 密碼 ');
      await controller.mailAccess.connect('synthetic-mail-password');
      await controller.prewarmCheckinProjects();
      expect(controller.cachedCheckinProjects()!.items.single.checkedCount, 9);
      expect(
        (await controller.loadCheckinProjects()).items.single.checkedCount,
        9,
      );
      await controller.loadCheckinProjects();
      expect(logins, [
        {'username': 'synthetic-a', 'password': ' 学校原 密碼 '},
      ]);
      await controller.logout();
      expect(controller.cachedCheckinProjects(), isNull);
      await controller.login(
        username: 'synthetic-b',
        password: 'second-school-password',
      );
      await controller.loadCheckinProjects();
      expect(logins.last, {
        'username': 'synthetic-b',
        'password': 'second-school-password',
      });
      expect(logins, hasLength(2));
    },
  );

  test(
    'CIS late result cannot cross central logout and school session remains independent',
    () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      final client = CisCheckinClient(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'result': {'token': 'synthetic-cis'},
              }),
              200,
            );
          }
          entered.complete();
          await gate.future;
          return http.Response(
            jsonEncode(checkinEnvelope([checkinProjectJson()])),
            200,
          );
        }),
      );
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        checkinClient: client,
        credentialStore: _MemoryCredentialStore(),
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);
      await controller.login(username: 'synthetic', password: 'synthetic');
      final pending = expectLater(
        controller.loadCheckinProjects(),
        throwsA(isA<CisCheckinException>()),
      );
      await entered.future;
      await controller.logout();
      gate.complete();
      await pending;
      expect(controller.isLoggedIn, isFalse);
    },
  );

  test('study windows cannot create a live CIS session', () async {
    var calls = 0;
    final controller = AppSessionController.studyWindow(
      checkinClient: CisCheckinClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ),
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    await expectLater(
      controller.loadCheckinProjects(),
      throwsA(isA<CisCheckinException>()),
    );
    await expectLater(
      controller.loadCheckinRecords(),
      throwsA(isA<CisCheckinException>()),
    );
    expect(calls, 0);
  });

  test(
    'mail repair preserves primary login and is reused by every consumer',
    () async {
      final store = _MemoryCredentialStore();
      final attempts = <String>[];
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        mailVerifier: (credentials) async {
          attempts.add(credentials.password);
          if (credentials.password == 'school') {
            throw const MailAuthenticationException();
          }
        },
      );
      addTearDown(controller.dispose);
      await controller.login(username: 'student', password: 'school');
      expect(attempts, isEmpty);
      expect(await controller.loadMailAccessCredentials(), isNull);
      expect(controller.isLoggedIn, isTrue);
      expect(store.credentials?.password, 'school');
      await controller.mailAccess.connect(' 邮件 密碼 ');
      expect(
        (await controller.loadMailAccessCredentials())?.password,
        ' 邮件 密碼 ',
      );
      expect(store.credentials?.password, 'school');
      expect(store.credentials?.mail.password, ' 邮件 密碼 ');
      expect(attempts, ['school', ' 邮件 密碼 ']);
      await controller.logout();
      expect(store.credentials, isNull);
      expect(controller.mailAccess.credentials, isNull);
      expect(await controller.loadMailAccessCredentials(), isNull);
    },
  );

  test(
    'restored skipped mailbox makes no mail request and remains manually repairable',
    () async {
      final store = _MemoryCredentialStore(
        const StoredCredentials(
          username: 'student',
          password: 'school',
          mail: MailLoginSettings(skipped: true),
        ),
      );
      var attempts = 0;
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        mailVerifier: (_) async {
          attempts++;
        },
      );
      addTearDown(controller.dispose);
      await controller.restoreSessionIfPossible();
      expect(await controller.loadMailAccessCredentials(), isNull);
      expect(attempts, 0);
      expect(controller.mailAccess.shouldPrompt, isFalse);
      await controller.mailAccess.connect('mail');
      expect(attempts, 1);
      expect(controller.mailAccess.status, MailAccessStatus.connected);
    },
  );

  test(
    'logout while mail verification waits never resurrects secure credentials',
    () async {
      final gate = Completer<void>();
      final store = _MemoryCredentialStore();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        mailVerifier: (_) => gate.future,
      );
      addTearDown(controller.dispose);
      await controller.login(username: 'student', password: 'school');
      final verifying = controller.loadMailAccessCredentials();
      await controller.logout();
      gate.complete();
      expect(await verifying, isNull);
      expect(store.credentials, isNull);
      expect(controller.mailAccess.owner, isNull);
    },
  );

  test('concurrent Portal callers await one shared request', () async {
    final mis = _BlockingPortalMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: mis,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    final first = controller.refreshPortalProfile();
    final second = controller.refreshPortalProfile();
    await Future<void>.delayed(Duration.zero);
    expect(mis.calls, 1);
    var completed = false;
    final third = controller.refreshPortalProfile().then(
      (_) => completed = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    mis.result.complete(
      const PortalAccountProfile(
        fullName: 'Student',
        identity: 'Student',
        organization: 'University',
        department: 'Data Science',
        avatarPath: '',
      ),
    );
    await Future.wait([first, second, third]);
    expect(controller.portalProfile?.department, 'Data Science');
  });

  test('logout rejects a late Portal profile', () async {
    final mis = _BlockingPortalMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: mis,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    final pending = controller.refreshPortalProfile();
    await Future<void>.delayed(Duration.zero);
    await controller.logout();
    mis.result.complete(
      const PortalAccountProfile(
        fullName: 'Student',
        identity: 'Student',
        organization: '',
        department: 'Data Science',
        avatarPath: '',
      ),
    );
    await pending;
    expect(controller.portalProfile, isNull);
    expect(controller.isLoadingPortalProfile, isFalse);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'successful login persists credentials through CredentialStore',
    () async {
      final store = _MemoryCredentialStore();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      await controller.login(username: 'student', password: 'secret');

      expect(controller.isLoggedIn, isTrue);
      expect(store.credentials?.username, 'student');
      expect(store.credentials?.password, 'secret');
    },
  );

  test(
    'major preserves Portal name and falls back to MIS programme without organization',
    () {
      final controller = _IdentitySourcesController();
      addTearDown(controller.dispose);
      expect(controller.studentMajor, '');
      controller.profile = const PortalAccountProfile(
        fullName: 'Student',
        identity: 'Student',
        organization: 'University',
        department: '',
        avatarPath: '',
      );
      expect(controller.studentMajor, '');
      controller.profile = const PortalAccountProfile(
        fullName: 'Student',
        identity: 'Student',
        organization: 'University',
        department: 'Data Science',
        avatarPath: '',
      );
      expect(controller.studentMajor, 'Data Science');
      controller.data = _testTimetable();
      expect(controller.studentMajor, 'Data Science');
      controller.profile = null;
      expect(controller.studentMajor, 'Programme');
    },
  );

  test(
    'account switch clears old identity before the new Portal response',
    () async {
      final mis = _SwitchPortalMisClient();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: mis,
        credentialStore: _MemoryCredentialStore(),
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);
      await controller.login(username: 'student-a', password: 'test-a');
      await controller.refreshPortalProfile();
      expect(controller.studentMajor, 'Major A');
      await controller.login(username: 'student-b', password: 'test-b');
      expect(controller.portalProfile, isNull);
      expect(controller.studentMajor, isEmpty);
      final pending = controller.refreshPortalProfile();
      mis.second.complete(
        const PortalAccountProfile(
          fullName: 'B',
          identity: 'Student',
          organization: '',
          department: 'Major B',
          avatarPath: '',
        ),
      );
      await pending;
      expect(controller.studentMajor, 'Major B');
    },
  );

  test('Moodle catalog revision changes after refresh and logout', () async {
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    final initialRevision = controller.moodleCatalogRevision;
    await controller.login(username: 'student', password: 'secret');
    expect(controller.moodleCatalogRevision, greaterThan(initialRevision));

    final afterLogin = controller.moodleCatalogRevision;
    await controller.refreshCourses();
    expect(controller.moodleCatalogRevision, greaterThan(afterLogin));

    final afterRefresh = controller.moodleCatalogRevision;
    await controller.logout();
    expect(controller.moodleCatalogRevision, greaterThan(afterRefresh));
  });

  test('successful login always starts foreground activity sharing', () async {
    final usageSyncService = _RecordingUsageSyncService();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
      usageSyncService: usageSyncService,
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(usageSyncService.synchronizedUsers, <String>['student']);
    await controller.sendUsageHeartbeat();
    expect(usageSyncService.heartbeatUsers, <String>['student']);

    await controller.logout();
    await controller.sendUsageHeartbeat();
    expect(usageSyncService.heartbeatUsers, <String>['student']);
  });

  test(
    'Portal profile loads the same-origin student portrait in memory',
    () async {
      final misClient = _PortalPhotoMisClient();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: misClient,
        credentialStore: _MemoryCredentialStore(),
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      await controller.login(username: '2099000001', password: 'secret');
      await controller.refreshPortalProfile();

      expect(controller.portalProfile?.fullName, '测试学生');
      expect(controller.portalAvatarBytes, Uint8List.fromList([1, 2, 3, 4]));
      expect(controller.portalAvatarError, isNull);
      expect(misClient.requestedAvatarPath, '/student/photo.jpg');

      await controller.logout();
      expect(controller.portalAvatarBytes, isNull);
    },
  );

  test(
    'restoreSessionIfPossible loads credentials from CredentialStore',
    () async {
      final store = _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      );
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      await controller.restoreSessionIfPossible();

      expect(controller.isLoggedIn, isTrue);
      expect(controller.username, 'student');
    },
  );

  test(
    'study window reuses cached MIS data without opening a live school session',
    () async {
      final misClient = _ForbiddenOfficialMisClient();
      final apiClient = _FakeMoodleApiClient();
      final cachedTimetable = _testTimetable(studentId: 'cached-student');
      final controller = AppSessionController.studyWindow(
        apiClient: apiClient,
        misClient: misClient,
        credentialStore: _MemoryCredentialStore(
          const StoredCredentials(username: 'student', password: 'secret'),
        ),
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        timetableCacheStore: _MemoryTimetableCacheStore(
          cached: cachedTimetable,
        ),
      );
      addTearDown(controller.dispose);

      await controller.restoreSessionIfPossible();
      await controller.ensureTimetableLoaded();
      await controller.refreshPortalProfile();

      expect(controller.sessionScope, AppSessionScope.studyWindow);
      expect(controller.canOpenOfficialSchoolSession, isFalse);
      expect(controller.session, isNull);
      expect(apiClient.loginCalls, 0);
      expect(controller.timetable?.profile.studentId, 'cached-student');
      expect(misClient.timetableCalls, 0);
      expect(misClient.examCalls, 0);
      expect(misClient.portalCalls, 0);
      await expectLater(
        controller.prepareOfficialWebSession(OfficialWebTarget.mis),
        throwsA(isA<BnbuMisException>()),
      );
      expect(misClient.officialWebCalls, 0);
    },
  );

  test('logout clears persisted credentials', () async {
    final store = _MemoryCredentialStore(
      const StoredCredentials(username: 'student', password: 'secret'),
    );
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();
    await controller.logout();

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials, isNull);
  });

  test('logout invalidates a captured session lease immediately', () async {
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    final lease = controller.captureSessionLease();
    expect(lease, isNotNull);
    expect(lease!.isActive, isTrue);

    final logout = controller.logout();
    await Future<void>.delayed(Duration.zero);
    expect(lease.isActive, isFalse);
    await logout;
  });

  test('logout clears MIS cookies kept in memory', () async {
    final misClient = _OfflineMisClient();
    misClient.storeCookieForTesting(
      Cookie('session', 'secret')..path = '/',
      Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
    );
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.logout();

    expect(
      misClient.cookieHeaderForTesting(
        Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
      ),
      isEmpty,
    );
  });

  test(
    'logout invalidates MIS session before secure cleanup finishes',
    () async {
      final store = _BlockingClearCredentialStore();
      final misClient = _RecordingClearMisClient();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: misClient,
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      await controller.login(username: 'student', password: 'secret');
      final logoutFuture = controller.logout();
      await store.clearStarted.future;

      expect(misClient.sessionCleared, isTrue);

      store.allowClear.complete();
      await logoutFuture;
    },
  );

  test('logout reports missing native cleanup support', () async {
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _MissingPluginNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.logout();

    expect(controller.error, contains('部分本地登录数据清理失败'));
  });

  test('logout revokes memory state before secure cleanup finishes', () async {
    final store = _BlockingClearCredentialStore();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    final logoutFuture = controller.logout();
    await store.clearStarted.future;

    expect(controller.isLoggedIn, isFalse);
    expect(controller.username, isNull);
    expect(controller.isLoggingOut, isTrue);

    store.allowClear.complete();
    await logoutFuture;
  });

  test('a login completed after logout cannot restore the session', () async {
    final apiClient = _BlockingLoginMoodleApiClient();
    final store = _MemoryCredentialStore();
    final controller = AppSessionController(
      apiClient: apiClient,
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    final loginFuture = controller.login(
      username: 'student',
      password: 'secret',
    );
    await apiClient.loginStarted.future;
    await controller.logout();
    apiClient.loginResult.complete(
      AuthSession(
        token: 'late-token',
        fullName: 'Student',
        userId: 1,
        runtimeProfile: _testRuntimeProfile(),
      ),
    );
    await loginFuture;

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials, isNull);
  });

  test('temporary restore failures preserve saved credentials', () async {
    final store = _MemoryCredentialStore(
      const StoredCredentials(username: 'student', password: 'secret'),
    );
    final controller = AppSessionController(
      apiClient: _FailingLoginMoodleApiClient(
        MoodleApiException('Service unavailable'),
      ),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials?.username, 'student');
  });

  test(
    'transient stored login failure retries before showing an error',
    () async {
      final store = _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      );
      final apiClient = _TransientLoginMoodleApiClient();
      final controller = AppSessionController(
        apiClient: apiClient,
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        retryDelay: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.restoreSessionIfPossible();

      expect(apiClient.loginCount, 2);
      expect(controller.isLoggedIn, isTrue);
      expect(controller.error, isNull);
    },
  );

  test('login completes before post-login content refreshes finish', () async {
    final apiClient = _BlockingRefreshMoodleApiClient();
    final controller = AppSessionController(
      apiClient: apiClient,
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');

    expect(controller.isLoggedIn, isTrue);
    expect(controller.isLoggingIn, isFalse);
    expect(apiClient.refreshStarted, isTrue);

    apiClient.completeRefreshes();
    await Future<void>.delayed(Duration.zero);
  });

  test('invalid stored credentials are removed', () async {
    final store = _MemoryCredentialStore(
      const StoredCredentials(username: 'student', password: 'wrong'),
    );
    final controller = AppSessionController(
      apiClient: _FailingLoginMoodleApiClient(
        MoodleAuthenticationException('Invalid login'),
      ),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials, isNull);
  });

  test(
    'logout waits for an in-flight credential load before clearing',
    () async {
      final store = _BlockingLoadCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      );
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      final restoreFuture = controller.restoreSessionIfPossible();
      await store.loadStarted.future;
      final logoutFuture = controller.logout();
      store.allowLoad.complete();
      await Future.wait([restoreFuture, logoutFuture]);

      expect(controller.isLoggedIn, isFalse);
      expect(store.credentials, isNull);
    },
  );

  test('concurrent logout callers await the same cleanup', () async {
    final store = _BlockingClearCredentialStore();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    final first = controller.logout();
    await store.clearStarted.future;
    final second = controller.logout();

    expect(identical(first, second), isTrue);
    store.allowClear.complete();
    await Future.wait([first, second]);
  });

  test('login is rejected while logout cleanup is active', () async {
    final store = _BlockingClearCredentialStore();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    final logoutFuture = controller.logout();
    await store.clearStarted.future;
    await controller.login(username: 'other', password: 'new-secret');

    expect(controller.isLoggedIn, isFalse);
    expect(controller.error, contains('退出登录处理中'));
    store.allowClear.complete();
    await logoutFuture;
  });

  test('restore retries one transient credential read failure', () async {
    final store = _TransientLoadCredentialStore(
      const StoredCredentials(username: 'student', password: 'secret'),
    );
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();

    expect(store.loadCount, 2);
    expect(controller.isLoggedIn, isTrue);
  });

  test('invalid credential cleanup failures are surfaced', () async {
    final store = _FailingClearCredentialStore(
      const StoredCredentials(username: 'student', password: 'wrong'),
    );
    final controller = AppSessionController(
      apiClient: _FailingLoginMoodleApiClient(
        MoodleAuthenticationException('Invalid login'),
      ),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();

    expect(controller.isLoggedIn, isFalse);
    expect(controller.error, contains('本地登录信息清理失败'));
  });

  test('official web sessions use credentials from CredentialStore', () async {
    final misClient = _RecordingOfficialMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    await controller.restoreSessionIfPossible();

    final snapshot = await controller.prepareOfficialWebSession(
      OfficialWebTarget.portal,
    );

    expect(misClient.lastTarget, OfficialWebTarget.portal);
    expect(misClient.lastUsername, 'student');
    expect(misClient.lastPassword, 'secret');
    expect(snapshot.baseUrl, 'https://portal.bnbu.edu.cn');
  });

  test(
    'official web session retries one transient establishment failure',
    () async {
      final misClient = _RetryingOfficialMisClient(
        failures: <Object>[BnbuMisException('MIS 会话暂时不可用。', isRetryable: true)],
      );
      final retryDelays = <Duration>[];
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: misClient,
        credentialStore: _MemoryCredentialStore(
          const StoredCredentials(username: 'student', password: 'secret'),
        ),
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        retryDelay: (delay) async {
          retryDelays.add(delay);
        },
      );
      addTearDown(controller.dispose);
      await controller.restoreSessionIfPossible();

      final snapshot = await controller.prepareOfficialWebSession(
        OfficialWebTarget.mis,
      );

      expect(misClient.prepareCalls, 2);
      expect(misClient.invalidatedTargets, <OfficialWebTarget>[
        OfficialWebTarget.mis,
      ]);
      expect(retryDelays, <Duration>[const Duration(milliseconds: 350)]);
      expect(snapshot.cookies, hasLength(1));
    },
  );

  test('official web reset invalidates only the requested target', () async {
    final misClient = _RecordingClearMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(null),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.resetOfficialWebSession(OfficialWebTarget.mis);

    expect(misClient.invalidatedTargets, <OfficialWebTarget>[
      OfficialWebTarget.mis,
    ]);
    expect(misClient.sessionCleared, isFalse);
  });

  test(
    'official WebView cookies reconcile through the shared MIS client',
    () async {
      final misClient = _RecordingOfficialMisClient();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: misClient,
        credentialStore: _MemoryCredentialStore(
          const StoredCredentials(username: 'student', password: 'secret'),
        ),
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);
      await controller.restoreSessionIfPossible();

      await controller.reconcileOfficialWebSession(
        OfficialWebTarget.mis,
        const <WebSessionCookie>[
          WebSessionCookie(
            name: 'mis-session',
            value: 'rotated',
            domain: 'mis.bnbu.edu.cn',
            path: '/mis',
            hostOnly: true,
            secure: true,
            httpOnly: true,
          ),
        ],
      );

      expect(misClient.reconciledTarget, OfficialWebTarget.mis);
      expect(misClient.reconciledCookies.single.value, 'rotated');
    },
  );

  test('official web session does not retry authentication failures', () async {
    final misClient = _RetryingOfficialMisClient(
      failures: <Object>[BnbuMisException('统一认证登录失败。')],
    );
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'wrong'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
      retryDelay: (_) async {
        fail('authentication failures must not be retried');
      },
    );
    addTearDown(controller.dispose);
    await controller.restoreSessionIfPossible();

    await expectLater(
      controller.prepareOfficialWebSession(OfficialWebTarget.mis),
      throwsA(isA<BnbuMisException>()),
    );
    expect(misClient.prepareCalls, 1);
  });

  test('concurrent timetable ensure calls share one MIS request', () async {
    final misClient = _BlockingTimetableMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    final first = controller.ensureTimetableLoaded();
    final second = controller.ensureTimetableLoaded();
    await misClient.started.future;

    expect(misClient.fetchCalls, 1);
    misClient.complete(_testTimetable());
    await Future.wait([first, second]);
    expect(controller.timetable?.totalMeetings, 1);
  });

  test('timetable retries a transient MIS session failure', () async {
    final misClient = _RetryingTimetableMisClient(
      failures: <Object>[BnbuMisException('MIS 会话暂时不可用。', isRetryable: true)],
    );
    final retryDelays = <Duration>[];
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
      retryDelay: (delay) async {
        retryDelays.add(delay);
      },
    );
    addTearDown(controller.dispose);

    await controller.ensureTimetableLoaded();

    expect(misClient.fetchCalls, 2);
    expect(retryDelays, <Duration>[const Duration(milliseconds: 350)]);
    expect(controller.timetable?.totalMeetings, 1);
    expect(controller.timetableError, isNull);
  });

  test('timetable does not retry a permanent authentication failure', () async {
    final misClient = _RetryingTimetableMisClient(
      failures: <Object>[BnbuMisException('统一认证登录失败。')],
    );
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'wrong'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
      retryDelay: (_) async {
        fail('permanent authentication failures must not be retried');
      },
    );
    addTearDown(controller.dispose);

    await controller.ensureTimetableLoaded();

    expect(misClient.fetchCalls, 1);
    expect(controller.timetable, isNull);
    expect(controller.timetableError, '统一认证登录失败。');
  });

  test(
    'timetable publishes account cache while live MIS recovery fails',
    () async {
      final cached = _testTimetable(studentId: 'cached-student');
      final cacheStore = _MemoryTimetableCacheStore(cached: cached);
      final misClient = _RetryingTimetableMisClient(
        failures: <Object>[
          BnbuMisException('MIS 暂时不可用。', isRetryable: true),
          BnbuMisException('MIS 暂时不可用。', isRetryable: true),
          BnbuMisException('MIS 暂时不可用。', isRetryable: true),
        ],
      );
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: misClient,
        credentialStore: _MemoryCredentialStore(
          const StoredCredentials(username: 'student', password: 'secret'),
        ),
        timetableCacheStore: cacheStore,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
        retryDelay: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.ensureTimetableLoaded();

      expect(cacheStore.loadedUsernames, <String>['student']);
      expect(misClient.fetchCalls, 3);
      expect(controller.timetable?.profile.studentId, 'cached-student');
      expect(controller.timetableError, 'MIS 暂时不可用。');
    },
  );

  test('successful timetable refresh updates the account cache', () async {
    final cacheStore = _MemoryTimetableCacheStore();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _RetryingTimetableMisClient(failures: const <Object>[]),
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      timetableCacheStore: cacheStore,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.ensureTimetableLoaded();

    expect(cacheStore.savedUsernames, <String>['student']);
    expect(cacheStore.saved?.totalMeetings, 1);
  });

  test('timetable refresh automatically includes MIS exam times', () async {
    final cacheStore = _MemoryTimetableCacheStore();
    final misClient = _ExamTimetableMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      timetableCacheStore: cacheStore,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.ensureTimetableLoaded();

    expect(misClient.examFetchCalls, 1);
    expect(
      controller.timetable?.examAvailability,
      ExamTimetableAvailability.available,
    );
    expect(controller.timetable?.exams.single.courseCode, 'COMP1001');
    expect(cacheStore.saved?.exams.single.room, 'T2-101');
  });

  test(
    'logout rejects a late exam timetable failure without republishing timetable',
    () async {
      final cacheStore = _MemoryTimetableCacheStore();
      final misClient = _BlockingExamTimetableMisClient();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: misClient,
        credentialStore: _MemoryCredentialStore(
          const StoredCredentials(username: 'student', password: 'secret'),
        ),
        timetableCacheStore: cacheStore,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      final refresh = controller.ensureTimetableLoaded();
      await misClient.examStarted.future;
      await controller.logout();
      misClient.failExam();
      await refresh;

      expect(controller.timetable, isNull);
      expect(controller.timetableError, isNull);
      expect(cacheStore.savedUsernames, isEmpty);
    },
  );

  test('exam fallback requires both semester id and name to match', () async {
    final cached = _testTimetableForSemester(name: 'Semester 2')
        .withExamTimetable(
          ExamTimetableData(
            availability: ExamTimetableAvailability.available,
            entries: [
              ExamTimetableEntry(
                courseCode: 'COMP1001',
                courseName: 'Programming',
                date: DateTime(2026, 12, 15),
                startMinutes: 9 * 60,
                endMinutes: 11 * 60,
                room: 'T2-101',
                seat: '18',
                remark: '',
              ),
            ],
          ),
        );
    final cacheStore = _MemoryTimetableCacheStore(cached: cached);
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _FailingExamTimetableMisClient(),
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      timetableCacheStore: cacheStore,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.ensureTimetableLoaded();

    expect(controller.timetable?.selectedSemesterName, 'Semester 1');
    expect(controller.timetable?.exams, isEmpty);
  });

  test('missing exam entry keeps an exact-semester cached timetable', () async {
    final cached = _testTimetableForSemester(name: 'Semester 1')
        .withExamTimetable(
          ExamTimetableData(
            availability: ExamTimetableAvailability.available,
            entries: [
              ExamTimetableEntry(
                courseCode: 'COMP1001',
                courseName: 'Programming',
                date: DateTime(2026, 12, 15),
                startMinutes: 9 * 60,
                endMinutes: 11 * 60,
                room: 'T2-101',
                seat: '18',
                remark: '',
              ),
            ],
          ),
        );
    final cacheStore = _MemoryTimetableCacheStore(cached: cached);
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _UnavailableExamTimetableMisClient(),
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      timetableCacheStore: cacheStore,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.ensureTimetableLoaded();

    expect(
      controller.timetable?.examAvailability,
      ExamTimetableAvailability.available,
    );
    expect(controller.timetable?.exams.single.courseCode, 'COMP1001');
  });

  test(
    'timetable cache writes are serialized so the newer refresh wins',
    () async {
      final cacheStore = _BlockingTimetableCacheStore();
      final misClient = _SequentialTimetableMisClient();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: misClient,
        credentialStore: _MemoryCredentialStore(
          const StoredCredentials(username: 'student', password: 'secret'),
        ),
        timetableCacheStore: cacheStore,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(() {
        cacheStore.releaseFirstSave();
        controller.dispose();
      });

      final firstRefresh = controller.ensureTimetableLoaded();
      await cacheStore.firstSaveStarted.future;
      await controller.logout();
      await controller.login(username: 'student', password: 'secret');

      final secondRefresh = controller.ensureTimetableLoaded();
      await Future<void>.delayed(Duration.zero);
      expect(cacheStore.saveCalls, 1);

      cacheStore.releaseFirstSave();
      await Future.wait([firstRefresh, secondRefresh]);
      expect(cacheStore.persisted?.profile.studentId, 'new-student');
    },
  );

  test('logout cancels a pending timetable retry', () async {
    final misClient = _RetryingTimetableMisClient(
      failures: <Object>[BnbuMisException('MIS 会话暂时不可用。', isRetryable: true)],
    );
    final retryStarted = Completer<void>();
    final allowRetry = Completer<void>();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
      retryDelay: (_) {
        retryStarted.complete();
        return allowRetry.future;
      },
    );
    addTearDown(controller.dispose);

    final timetableFuture = controller.ensureTimetableLoaded();
    await retryStarted.future;
    await controller.logout();
    allowRetry.complete();
    await timetableFuture;

    expect(misClient.fetchCalls, 1);
    expect(controller.timetable, isNull);
    expect(controller.timetableError, isNull);
  });

  test('logout rejects a late timetable result', () async {
    final misClient = _BlockingTimetableMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    await controller.restoreSessionIfPossible();

    final timetableFuture = controller.ensureTimetableLoaded();
    await misClient.started.future;
    await controller.logout();
    misClient.complete(_testTimetable());
    await timetableFuture;

    expect(controller.timetable, isNull);
  });

  test('a new account does not reuse the previous timetable request', () async {
    final misClient = _AccountSwitchTimetableMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    await controller.login(username: 'student-a', password: 'secret-a');

    final first = controller.ensureTimetableLoaded();
    await misClient.firstStarted.future;
    await controller.logout();
    await controller.login(username: 'student-b', password: 'secret-b');

    final second = controller.ensureTimetableLoaded();
    await misClient.secondStarted.future;
    expect(misClient.usernames, ['student-a', 'student-b']);

    misClient.completeSecond(_testTimetable(studentId: 'student-b'));
    await second;
    expect(controller.timetable?.profile.studentId, 'student-b');

    misClient.completeFirst(_testTimetable(studentId: 'student-a'));
    await first;
    expect(controller.timetable?.profile.studentId, 'student-b');
  });

  test('logout rejects a late official web session snapshot', () async {
    final misClient = _BlockingOfficialMisClient();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    await controller.restoreSessionIfPossible();

    final sessionFuture = controller.prepareOfficialWebSession(
      OfficialWebTarget.mis,
    );
    await misClient.started.future;
    await controller.logout();
    misClient.complete();

    await expectLater(sessionFuture, throwsA(isA<BnbuMisException>()));
  });

  test(
    'a late reminder preference restore cannot overwrite a user toggle',
    () async {
      final reminderService = _BlockingDeadlineReminderService();
      final controller = AppSessionController(
        deadlineReminderService: reminderService,
      );
      addTearDown(controller.dispose);

      await reminderService.loadStarted.future;
      expect(await controller.setDeadlineReminderEnabled(true), isNull);
      expect(controller.isDeadlineReminderEnabled, isTrue);
      expect(controller.isLoadingDeadlineReminderPreference, isFalse);

      reminderService.completeLoad(false);
      await Future<void>.delayed(Duration.zero);

      expect(controller.isDeadlineReminderEnabled, isTrue);
      expect(controller.isLoadingDeadlineReminderPreference, isFalse);
    },
  );

  test('enabling reminders does not wait for background scheduling', () async {
    final apiClient = _TimelineMoodleApiClient();
    final reminderService = _BlockingSynchronizeDeadlineReminderService();
    final controller = AppSessionController(
      apiClient: apiClient,
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: reminderService,
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);
    addTearDown(reminderService.completeSynchronize);

    await controller.login(username: 'student', password: 'secret');
    await controller.refreshTimeline();

    final result = await controller
        .setDeadlineReminderEnabled(true)
        .timeout(const Duration(seconds: 1));

    expect(result, isNull);
    expect(controller.isDeadlineReminderEnabled, isTrue);
    expect(controller.isUpdatingDeadlineReminder, isFalse);
    await reminderService.synchronizeStarted.future;
  });
}

class _MemoryCredentialStore implements CredentialStore {
  _MemoryCredentialStore([this.credentials]);

  StoredCredentials? credentials;

  @override
  Future<void> clear() async {
    credentials = null;
  }

  @override
  Future<StoredCredentials?> load() async => credentials;

  @override
  Future<void> save(StoredCredentials credentials) async {
    this.credentials = credentials;
  }
}

class _BlockingClearCredentialStore extends _MemoryCredentialStore {
  final Completer<void> clearStarted = Completer<void>();
  final Completer<void> allowClear = Completer<void>();

  @override
  Future<void> clear() async {
    clearStarted.complete();
    await allowClear.future;
    await super.clear();
  }
}

class _BlockingLoadCredentialStore extends _MemoryCredentialStore {
  _BlockingLoadCredentialStore(super.credentials);

  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> allowLoad = Completer<void>();

  @override
  Future<StoredCredentials?> load() async {
    loadStarted.complete();
    await allowLoad.future;
    return credentials;
  }
}

class _TransientLoadCredentialStore extends _MemoryCredentialStore {
  _TransientLoadCredentialStore(super.credentials);

  int loadCount = 0;

  @override
  Future<StoredCredentials?> load() async {
    loadCount++;
    if (loadCount == 1) {
      throw PlatformException(code: 'temporary_read_failure');
    }
    return credentials;
  }
}

class _FailingClearCredentialStore extends _MemoryCredentialStore {
  _FailingClearCredentialStore(super.credentials);

  @override
  Future<void> clear() {
    throw PlatformException(code: 'clear_failed');
  }
}

class _FakeDeadlineReminderService extends DeadlineReminderService {
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

class _BlockingDeadlineReminderService extends DeadlineReminderService {
  final Completer<void> loadStarted = Completer<void>();
  final Completer<bool> _loadResult = Completer<bool>();

  @override
  Future<bool> loadEnabled() {
    loadStarted.complete();
    return _loadResult.future;
  }

  @override
  Future<String?> enable() async => null;

  @override
  Future<void> synchronize(List<TimelineItem> items) async {}

  void completeLoad(bool enabled) {
    _loadResult.complete(enabled);
  }
}

class _BlockingSynchronizeDeadlineReminderService
    extends DeadlineReminderService {
  bool _enabled = false;
  final Completer<void> synchronizeStarted = Completer<void>();
  final Completer<void> _synchronizeResult = Completer<void>();

  @override
  Future<bool> loadEnabled() async => _enabled;

  @override
  Future<String?> enable() async {
    _enabled = true;
    return null;
  }

  @override
  Future<void> synchronize(List<TimelineItem> items) async {
    if (!_enabled) {
      return;
    }
    if (!synchronizeStarted.isCompleted) {
      synchronizeStarted.complete();
    }
    await _synchronizeResult.future;
  }

  void completeSynchronize() {
    if (!_synchronizeResult.isCompleted) {
      _synchronizeResult.complete();
    }
  }
}

class _FakeNativeActions extends NativeActions {
  const _FakeNativeActions();

  @override
  Future<void> clearWebSession() async {}
}

class _MissingPluginNativeActions extends NativeActions {
  const _MissingPluginNativeActions();

  @override
  Future<void> clearWebSession() {
    throw MissingPluginException('clearWebSession unavailable');
  }
}

class _FakeMoodleApiClient extends MoodleApiClient {
  _FakeMoodleApiClient() : super(baseUrl: 'https://example.com');

  int loginCalls = 0;

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    loginCalls++;
    return AuthSession(
      token: 'token',
      fullName: username,
      userId: 1,
      runtimeProfile: _testRuntimeProfile(),
    );
  }

  @override
  Future<List<TimelineItem>> fetchAllTimeline({required String token}) async {
    return const [];
  }

  @override
  Future<List<CourseSummary>> fetchMyCourses({
    required String token,
    required int userId,
  }) async {
    return const [];
  }

  @override
  Future<List<RecentCourse>> fetchRecentCourses({
    required String token,
    required int userId,
    int limit = 10,
  }) async {
    return const [];
  }
}

class _TimelineMoodleApiClient extends _FakeMoodleApiClient {
  @override
  Future<List<TimelineItem>> fetchAllTimeline({required String token}) async {
    return <TimelineItem>[
      TimelineItem(
        id: 1,
        title: 'Assignment',
        activityState: 'due',
        activityType: 'assign',
        moduleName: 'assign',
        description: '',
        courseName: 'Course',
        courseId: 1,
        instanceId: 1,
        url: 'https://example.com/assignment',
        sortTime: DateTime.now().add(const Duration(days: 1)),
        formattedTime: '',
        isOverdue: false,
      ),
    ];
  }
}

class _BlockingLoginMoodleApiClient extends _FakeMoodleApiClient {
  final Completer<void> loginStarted = Completer<void>();
  final Completer<AuthSession> loginResult = Completer<AuthSession>();

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    loginStarted.complete();
    return loginResult.future;
  }
}

class _TransientLoginMoodleApiClient extends _FakeMoodleApiClient {
  int loginCount = 0;

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    loginCount++;
    if (loginCount == 1) {
      throw MoodleApiException('Service unavailable', isRetryable: true);
    }
    return super.loginWithPassword(username: username, password: password);
  }
}

class _BlockingRefreshMoodleApiClient extends _FakeMoodleApiClient {
  final Completer<void> _refreshGate = Completer<void>();
  bool refreshStarted = false;

  void completeRefreshes() {
    if (!_refreshGate.isCompleted) {
      _refreshGate.complete();
    }
  }

  Future<void> _waitForRefresh() async {
    refreshStarted = true;
    await _refreshGate.future;
  }

  @override
  Future<List<TimelineItem>> fetchAllTimeline({required String token}) async {
    await _waitForRefresh();
    return const [];
  }

  @override
  Future<List<CourseSummary>> fetchMyCourses({
    required String token,
    required int userId,
  }) async {
    await _waitForRefresh();
    return const [];
  }

  @override
  Future<List<RecentCourse>> fetchRecentCourses({
    required String token,
    required int userId,
    int limit = 10,
  }) async {
    await _waitForRefresh();
    return const [];
  }
}

class _FailingLoginMoodleApiClient extends _FakeMoodleApiClient {
  _FailingLoginMoodleApiClient(this.error);

  final MoodleApiException error;

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) {
    throw error;
  }
}

class _OfflineMisClient extends BnbuMisClient {
  @override
  Future<ExamTimetableData> fetchExamTimetable({
    required String username,
    required String password,
  }) async {
    return const ExamTimetableData.unavailable();
  }

  @override
  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) async {
    throw BnbuMisException('offline in tests');
  }
}

class _ForbiddenOfficialMisClient extends _OfflineMisClient {
  int timetableCalls = 0;
  int examCalls = 0;
  int portalCalls = 0;
  int officialWebCalls = 0;

  @override
  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) async {
    timetableCalls++;
    throw StateError('Study windows must not fetch live MIS data.');
  }

  @override
  Future<ExamTimetableData> fetchExamTimetable({
    required String username,
    required String password,
  }) async {
    examCalls++;
    throw StateError('Study windows must not fetch live MIS exam data.');
  }

  @override
  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) async {
    portalCalls++;
    throw StateError('Study windows must not fetch live Portal data.');
  }

  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession({
    required OfficialWebTarget target,
    required String username,
    required String password,
  }) async {
    officialWebCalls++;
    throw StateError('Study windows must not open official web sessions.');
  }
}

class _PortalPhotoMisClient extends _OfflineMisClient {
  String? requestedAvatarPath;

  @override
  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) async {
    return const PortalAccountProfile(
      fullName: '测试学生',
      identity: 'BNBU Student UG/STUDENT',
      organization: 'FST',
      department: 'Data Science',
      avatarPath: '/student/photo.jpg',
    );
  }

  @override
  Future<Uint8List?> fetchPortalAccountAvatar({
    required String username,
    required String password,
    required String avatarPath,
  }) async {
    requestedAvatarPath = avatarPath;
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

class _BlockingTimetableMisClient extends _OfflineMisClient {
  final Completer<void> started = Completer<void>();
  final Completer<TimetableData> _result = Completer<TimetableData>();
  int fetchCalls = 0;

  @override
  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) {
    fetchCalls++;
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void complete(TimetableData timetable) {
    _result.complete(timetable);
  }
}

class _RetryingTimetableMisClient extends _OfflineMisClient {
  _RetryingTimetableMisClient({required List<Object> failures})
    : _failures = List<Object>.from(failures);

  final List<Object> _failures;
  int fetchCalls = 0;

  @override
  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) async {
    fetchCalls++;
    if (_failures.isNotEmpty) {
      throw _failures.removeAt(0);
    }
    return _testTimetable();
  }
}

class _ExamTimetableMisClient extends _RetryingTimetableMisClient {
  _ExamTimetableMisClient() : super(failures: const <Object>[]);

  int examFetchCalls = 0;

  @override
  Future<ExamTimetableData> fetchExamTimetable({
    required String username,
    required String password,
  }) async {
    examFetchCalls++;
    return ExamTimetableData(
      availability: ExamTimetableAvailability.available,
      entries: [
        ExamTimetableEntry(
          courseCode: 'COMP1001',
          courseName: 'Programming',
          date: DateTime(2026, 12, 15),
          startMinutes: 9 * 60,
          endMinutes: 11 * 60,
          room: 'T2-101',
          seat: '18',
          remark: '',
        ),
      ],
    );
  }
}

class _BlockingExamTimetableMisClient extends _RetryingTimetableMisClient {
  _BlockingExamTimetableMisClient() : super(failures: const <Object>[]);

  final Completer<void> examStarted = Completer<void>();
  final Completer<ExamTimetableData> _examResult =
      Completer<ExamTimetableData>();

  @override
  Future<ExamTimetableData> fetchExamTimetable({
    required String username,
    required String password,
  }) {
    examStarted.complete();
    return _examResult.future;
  }

  void failExam() {
    _examResult.completeError(BnbuMisException('MIS session invalidated'));
  }
}

class _FailingExamTimetableMisClient extends _OfflineMisClient {
  @override
  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) async {
    return _testTimetableForSemester(name: 'Semester 1');
  }

  @override
  Future<ExamTimetableData> fetchExamTimetable({
    required String username,
    required String password,
  }) {
    throw BnbuMisException('Exam timetable unavailable');
  }
}

class _UnavailableExamTimetableMisClient
    extends _FailingExamTimetableMisClient {
  @override
  Future<ExamTimetableData> fetchExamTimetable({
    required String username,
    required String password,
  }) async {
    return const ExamTimetableData.unavailable();
  }
}

class _SequentialTimetableMisClient extends _OfflineMisClient {
  int _fetchCalls = 0;

  @override
  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) async {
    _fetchCalls++;
    return _testTimetable(
      studentId: _fetchCalls == 1 ? 'old-student' : 'new-student',
    );
  }
}

class _MemoryTimetableCacheStore implements TimetableCacheStore {
  _MemoryTimetableCacheStore({this.cached});

  TimetableData? cached;
  TimetableData? saved;
  final List<String> loadedUsernames = <String>[];
  final List<String> savedUsernames = <String>[];

  @override
  Future<TimetableData?> load(String username) async {
    loadedUsernames.add(username);
    return cached;
  }

  @override
  Future<void> save(String username, TimetableData timetable) async {
    savedUsernames.add(username);
    saved = timetable;
  }
}

class _BlockingTimetableCacheStore implements TimetableCacheStore {
  final Completer<void> firstSaveStarted = Completer<void>();
  final Completer<void> _allowFirstSave = Completer<void>();
  int saveCalls = 0;
  TimetableData? persisted;

  @override
  Future<TimetableData?> load(String username) async => null;

  @override
  Future<void> save(String username, TimetableData timetable) async {
    saveCalls++;
    if (saveCalls == 1) {
      firstSaveStarted.complete();
      await _allowFirstSave.future;
    }
    persisted = timetable;
  }

  void releaseFirstSave() {
    if (!_allowFirstSave.isCompleted) {
      _allowFirstSave.complete();
    }
  }
}

class _RetryingOfficialMisClient extends _OfflineMisClient {
  _RetryingOfficialMisClient({required List<Object> failures})
    : _failures = List<Object>.from(failures);

  final List<Object> _failures;
  int prepareCalls = 0;
  final List<OfficialWebTarget> invalidatedTargets = <OfficialWebTarget>[];

  @override
  Future<void> invalidateOfficialWebSession(OfficialWebTarget target) async {
    invalidatedTargets.add(target);
  }

  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession({
    required OfficialWebTarget target,
    required String username,
    required String password,
  }) async {
    prepareCalls++;
    if (_failures.isNotEmpty) {
      throw _failures.removeAt(0);
    }
    return WebSessionSnapshot(
      baseUrl: 'https://mis.bnbu.edu.cn',
      cookies: const <WebSessionCookie>[
        WebSessionCookie(
          name: 'session',
          value: 'opaque',
          domain: 'mis.bnbu.edu.cn',
          path: '/mis',
          hostOnly: true,
          secure: true,
          httpOnly: true,
        ),
      ],
      allowedOrigins: const <String>['https://mis.bnbu.edu.cn'],
      useEphemeralSession: true,
    );
  }
}

class _AccountSwitchTimetableMisClient extends _OfflineMisClient {
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> secondStarted = Completer<void>();
  final Completer<TimetableData> _firstResult = Completer<TimetableData>();
  final Completer<TimetableData> _secondResult = Completer<TimetableData>();
  final List<String> usernames = [];

  @override
  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) {
    usernames.add(username);
    if (usernames.length == 1) {
      firstStarted.complete();
      return _firstResult.future;
    }
    secondStarted.complete();
    return _secondResult.future;
  }

  void completeFirst(TimetableData timetable) {
    _firstResult.complete(timetable);
  }

  void completeSecond(TimetableData timetable) {
    _secondResult.complete(timetable);
  }
}

class _RecordingClearMisClient extends _OfflineMisClient {
  bool sessionCleared = false;
  final List<OfficialWebTarget> invalidatedTargets = <OfficialWebTarget>[];

  @override
  Future<void> invalidateOfficialWebSession(OfficialWebTarget target) async {
    invalidatedTargets.add(target);
  }

  @override
  void clearSession() {
    sessionCleared = true;
    super.clearSession();
  }
}

class _RecordingOfficialMisClient extends _OfflineMisClient {
  OfficialWebTarget? lastTarget;
  String? lastUsername;
  String? lastPassword;
  OfficialWebTarget? reconciledTarget;
  List<WebSessionCookie> reconciledCookies = const <WebSessionCookie>[];

  @override
  Future<void> reconcileOfficialWebSession({
    required OfficialWebTarget target,
    required List<WebSessionCookie> cookies,
  }) async {
    reconciledTarget = target;
    reconciledCookies = List<WebSessionCookie>.from(cookies);
  }

  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession({
    required OfficialWebTarget target,
    required String username,
    required String password,
  }) async {
    lastTarget = target;
    lastUsername = username;
    lastPassword = password;
    return WebSessionSnapshot(
      baseUrl: target == OfficialWebTarget.portal
          ? 'https://portal.bnbu.edu.cn'
          : 'https://mis.bnbu.edu.cn',
      cookies: const <WebSessionCookie>[],
      useEphemeralSession: true,
    );
  }
}

TimetableData _testTimetable({String studentId = 'student'}) {
  return TimetableData(
    profile: TimetableProfile(
      studentId: studentId,
      name: 'Student',
      programme: 'Programme',
      year: '1',
    ),
    semesters: const [],
    selectedSemesterId: 'semester',
    selectedSemesterName: 'Semester',
    courses: [
      TimetableCourse(
        section: '1',
        category: '',
        code: 'COMP1001',
        name: 'C Language',
        teacher: 'Teacher',
        meetings: [
          TimetableMeeting(
            weekday: DateTime.monday,
            dayLabel: 'Mon',
            startLabel: '09:00',
            endLabel: '10:00',
            startMinutes: 540,
            endMinutes: 600,
            room: 'T3-101',
          ),
        ],
        rooms: const ['T3-101'],
        units: '3',
        remark: '',
      ),
    ],
  );
}

MoodleRuntimeProfile _testRuntimeProfile() => MoodleRuntimeProfile(
  release: 'test',
  version: 'test',
  functionVersions: const {},
  downloadFiles: false,
  uploadFiles: false,
  advancedFeatures: const {},
  userMaxUploadFileSize: 0,
);

TimetableData _testTimetableForSemester({required String name}) {
  final timetable = _testTimetable();
  return TimetableData(
    profile: timetable.profile,
    semesters: timetable.semesters,
    selectedSemesterId: 'semester',
    selectedSemesterName: name,
    courses: timetable.courses,
  );
}

class _BlockingOfficialMisClient extends _OfflineMisClient {
  final Completer<void> started = Completer<void>();
  final Completer<WebSessionSnapshot> _result = Completer<WebSessionSnapshot>();

  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession({
    required OfficialWebTarget target,
    required String username,
    required String password,
  }) {
    started.complete();
    return _result.future;
  }

  void complete() {
    _result.complete(
      WebSessionSnapshot(
        baseUrl: 'https://mis.bnbu.edu.cn',
        cookies: const <WebSessionCookie>[],
        useEphemeralSession: true,
      ),
    );
  }
}

class _RecordingUsageSyncService implements UsageSyncService {
  final List<String> synchronizedUsers = <String>[];
  final List<String> heartbeatUsers = <String>[];

  @override
  Future<void> synchronize(String username) async {
    synchronizedUsers.add(username);
  }

  @override
  Future<void> heartbeat(String username) async {
    heartbeatUsers.add(username);
  }

  @override
  void dispose() {}
}

class _BlockingPortalMisClient extends _OfflineMisClient {
  int calls = 0;
  final result = Completer<PortalAccountProfile>();
  @override
  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) {
    calls++;
    return result.future;
  }
}

class _IdentitySourcesController extends AppSessionController {
  PortalAccountProfile? profile;
  TimetableData? data;
  @override
  PortalAccountProfile? get portalProfile => profile;
  @override
  TimetableData? get timetable => data;
}

class _SwitchPortalMisClient extends _OfflineMisClient {
  final second = Completer<PortalAccountProfile>();
  @override
  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) async {
    if (username == 'student-b') return second.future;
    return const PortalAccountProfile(
      fullName: 'A',
      identity: 'Student',
      organization: '',
      department: 'Major A',
      avatarPath: '',
    );
  }
}
