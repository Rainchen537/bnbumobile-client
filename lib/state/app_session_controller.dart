import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/course_content.dart';
import '../models/cis_checkin.dart';
import '../models/academic_calendar.dart';
import '../models/course_grade_data.dart';
import '../models/course_summary.dart';
import '../models/exam_timetable.dart';
import '../models/grade_report.dart';
import '../models/mail_models.dart';
import '../models/moodle_runtime_profile.dart';
import '../models/moodle_module_access.dart';
import '../models/official_web_target.dart';
import '../models/portal_account_profile.dart';
import '../models/recent_course.dart';
import '../models/quiz_attempt_data.dart';
import '../models/timetable_data.dart';
import '../models/ta_course_entry.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../models/web_session_snapshot.dart';
import '../services/bnbu_mis_client.dart';
import '../services/cis_checkin_client.dart';
import '../services/credential_store.dart';
import '../models/mail_login_settings.dart';
import '../services/mail_service_factory.dart';
import 'mail_access_controller.dart';
import '../services/courseware_download_plan.dart';
import '../services/deadline_reminder_service.dart';
import '../services/moodle_api_client.dart';
import '../services/native_actions.dart';
import '../services/timetable_cache_store.dart';
import '../services/private_portrait_cache.dart';
import '../services/usage_sync_service.dart';
import '../services/app_statistics_service.dart';

enum _LoginOutcome { succeeded, permanentFailure, transientFailure, cancelled }

enum AppSessionScope { app, studyWindow }

abstract interface class AppSessionLease {
  String get owner;

  bool get isActive;
}

class AppSessionController extends ChangeNotifier {
  AppSessionController({
    MoodleApiClient? apiClient,
    BnbuMisClient? misClient,
    CisCheckinClient? checkinClient,
    CredentialStore? credentialStore,
    DeadlineReminderService? deadlineReminderService,
    NativeActions? nativeActions,
    TimetableCacheStore? timetableCacheStore,
    UsageSyncService? usageSyncService,
    Future<void> Function(Duration delay)? retryDelay,
    Future<void> Function(MailAccessCredentials)? mailVerifier,
    DateTime Function()? gradeReportClock,
  }) : sessionScope = AppSessionScope.app,
       mailAccess = MailAccessController(
         verify: mailVerifier ?? verifyMailCredentials,
       ),
       _apiClient = apiClient ?? MoodleApiClient(),
       _misClient = misClient ?? BnbuMisClient(),
       _checkinClient = checkinClient ?? CisCheckinClient(),
       _credentialStore = credentialStore ?? SecureCredentialStore(),
       _deadlineReminderService =
           deadlineReminderService ?? DeadlineReminderService(),
       _nativeActions = nativeActions ?? const NativeActions(),
       _timetableCacheStore =
           timetableCacheStore ?? SharedPreferencesTimetableCacheStore(),
       _usageSyncService = usageSyncService ?? RemoteUsageSyncService(),
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _gradeReportClock = gradeReportClock ?? DateTime.now {
    BnbuAcademicCalendar.revision.addListener(_calendarChanged);
    mailAccess.addListener(_mailAccessChanged);
    _deadlineReminderService.statistics = statistics;
    unawaited(_restoreDeadlineReminderPreference());
    unawaited(_restoreCourseReminderPreference());
  }

  AppSessionController.studyWindow({
    MoodleApiClient? apiClient,
    BnbuMisClient? misClient,
    CisCheckinClient? checkinClient,
    CredentialStore? credentialStore,
    DeadlineReminderService? deadlineReminderService,
    NativeActions? nativeActions,
    TimetableCacheStore? timetableCacheStore,
    UsageSyncService? usageSyncService,
    Future<void> Function(Duration delay)? retryDelay,
  }) : sessionScope = AppSessionScope.studyWindow,
       mailAccess = MailAccessController(verify: verifyMailCredentials),
       _apiClient = apiClient ?? MoodleApiClient(),
       _misClient = misClient ?? BnbuMisClient(),
       _checkinClient = checkinClient ?? CisCheckinClient(),
       _credentialStore = credentialStore ?? SecureCredentialStore(),
       _deadlineReminderService =
           deadlineReminderService ?? DeadlineReminderService(),
       _nativeActions = nativeActions ?? const NativeActions(),
       _timetableCacheStore =
           timetableCacheStore ?? SharedPreferencesTimetableCacheStore(),
       _usageSyncService = usageSyncService ?? RemoteUsageSyncService(),
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _gradeReportClock = DateTime.now {
    BnbuAcademicCalendar.revision.addListener(_calendarChanged);
    unawaited(_restoreDeadlineReminderPreference());
    unawaited(_restoreCourseReminderPreference());
  }

  final AppSessionScope sessionScope;
  final MailAccessController mailAccess;
  MailLoginSettings? _restoredMailSettings;
  late final AppStatisticsService statistics = AppStatisticsService();

  final MoodleApiClient _apiClient;
  final BnbuMisClient _misClient;
  final CisCheckinClient _checkinClient;
  final CredentialStore _credentialStore;
  final DeadlineReminderService _deadlineReminderService;
  final NativeActions _nativeActions;
  final TimetableCacheStore _timetableCacheStore;
  final UsageSyncService _usageSyncService;
  final Future<void> Function(Duration delay) _retryDelay;
  final DateTime Function() _gradeReportClock;
  GradeReport? _gradeReport;
  DateTime? _gradeReportLoadedAt;
  AppSessionLease? _gradeReportLease;
  Future<GradeReport>? _gradeReportFuture;
  int _gradeReportGeneration = 0;

  AuthSession? _session;
  List<TimelineItem> _timelineItems = const [];
  List<CourseSummary> _courses = const [];
  List<RecentCourse> _recentCourses = const [];
  PortalAccountProfile? _portalProfile;
  Uint8List? _portalAvatarBytes;
  TimetableData? _timetable;
  bool _isLoggingIn = false;
  bool _isLoggingOut = false;
  bool _isLoadingTimeline = false;
  bool _isLoadingCourses = false;
  bool _isLoadingRecentCourses = false;
  bool _isLoadingTimetable = false;
  bool _isLoadingPortalProfile = false;
  bool _isLoadingPortalAvatar = false;
  String? _error;
  String? _portalProfileError;
  String? _portalAvatarError;
  String? _timetableError;
  String? _username;
  String? _password;
  bool _isRestoringSession = false;
  bool _didAttemptRestore = false;
  bool _isDeadlineReminderEnabled = false;
  int _deadlineReminderLeadMinutes =
      DeadlineReminderService.defaultDeadlineLeadMinutes;
  DeadlineReminderPreferences _deadlineReminderPreferences =
      const DeadlineReminderPreferences();
  bool _isLoadingDeadlineReminderPreference = true;
  bool _isUpdatingDeadlineReminder = false;
  int _deadlineReminderPreferenceGeneration = 0;
  bool _isCourseReminderEnabled = false;
  int _courseReminderLeadMinutes =
      DeadlineReminderService.defaultCourseLeadMinutes;
  bool _isLoadingCourseReminderPreference = true;
  bool _isUpdatingCourseReminder = false;
  int _courseReminderPreferenceGeneration = 0;
  Future<AuthSession?>? _reloginFuture;
  Future<void>? _logoutFuture;
  Future<void>? _timetableLoadFuture;
  int? _timetableLoadGeneration;
  Future<void>? _portalProfileLoadFuture;
  int? _portalProfileLoadGeneration;
  Future<void> _credentialMutation = Future<void>.value();
  Future<void> _timetableCacheMutation = Future<void>.value();
  int _authGeneration = 0;
  int _moodleCatalogRevision = 0;
  bool _isDisposed = false;

  Future<ISpaceIdentity> readISpaceIdentity() => _withSessionRetry(
    (session) => _apiClient.fetchIdentity(token: session.token),
  );

  bool get canUpdateISpacePicture =>
      _session?.runtimeProfile.uploadFiles == true &&
      _session!.runtimeProfile.supportsFunctions(const [
        'core_user_update_picture',
        'core_files_get_unused_draft_itemid',
      ]);
  bool _updatingISpacePicture = false;
  Future<void> updateISpacePicture(Uint8List jpeg) async {
    if (_updatingISpacePicture) throw MoodleApiException('头像正在更新');
    final session = _session;
    if (session == null) throw MoodleApiException('请先登录 iSpace 账号。');
    final generation = _authGeneration;
    _updatingISpacePicture = true;
    try {
      await _apiClient.updateOwnPicture(token: session.token, jpeg: jpeg);
      if (!_isCurrentAuthOperation(generation)) {
        throw MoodleApiException('登录状态已变化，请重试。');
      }
      notifyListeners();
    } finally {
      _updatingISpacePicture = false;
    }
  }

  AuthSession? get session => _session;

  /// Portal provides the display name; MIS may provide a programme code.
  /// Organization/college are distinct identity fields and are never a major.
  String get studentMajor {
    final name = portalProfile?.majorName.trim() ?? '';
    return name.isNotEmpty ? name : timetable?.profile.programme.trim() ?? '';
  }

  Future<void> ensureIdentityProfileLoaded() async {
    if (!isLoggedIn || !canOpenOfficialSchoolSession) return;
    await Future.wait<void>([
      ensureTimetableLoaded(),
      if (portalProfile == null) refreshPortalProfile(),
    ]);
  }

  MoodleRuntimeProfile? get moodleRuntimeProfile => _session?.runtimeProfile;
  int get moodleCatalogRevision => _moodleCatalogRevision;
  List<TimelineItem> get timelineItems => _timelineItems;
  List<CourseSummary> get courses => _courses;
  List<RecentCourse> get recentCourses => _recentCourses;
  PortalAccountProfile? get portalProfile => _portalProfile;
  Uint8List? get portalAvatarBytes => _portalAvatarBytes;
  TimetableData? get timetable => _timetable;
  bool get isLoggingIn => _isLoggingIn;
  bool get isLoggingOut => _isLoggingOut;
  bool get isLoadingTimeline => _isLoadingTimeline;
  bool get isLoadingCourses => _isLoadingCourses;
  bool get isLoadingRecentCourses => _isLoadingRecentCourses;
  bool get isLoadingTimetable => _isLoadingTimetable;
  bool get isLoadingPortalProfile => _isLoadingPortalProfile;
  bool get isLoadingPortalAvatar => _isLoadingPortalAvatar;
  bool get isRestoringSession => _isRestoringSession;
  bool get isDeadlineReminderEnabled => _isDeadlineReminderEnabled;
  int get deadlineReminderLeadMinutes => _deadlineReminderLeadMinutes;
  DeadlineReminderPreferences get deadlineReminderPreferences =>
      _deadlineReminderPreferences;
  bool get isLoadingDeadlineReminderPreference =>
      _isLoadingDeadlineReminderPreference;
  bool get isUpdatingDeadlineReminder => _isUpdatingDeadlineReminder;
  bool get isCourseReminderEnabled => _isCourseReminderEnabled;
  int get courseReminderLeadMinutes => _courseReminderLeadMinutes;
  bool get isLoadingCourseReminderPreference =>
      _isLoadingCourseReminderPreference;
  bool get isUpdatingCourseReminder => _isUpdatingCourseReminder;
  bool get isBusy =>
      _isLoggingIn ||
      _isLoggingOut ||
      _isLoadingTimeline ||
      _isLoadingCourses ||
      _isLoadingRecentCourses ||
      _isLoadingTimetable ||
      _isRestoringSession;
  bool get isLoggedIn =>
      _session != null ||
      (sessionScope == AppSessionScope.studyWindow &&
          (_username?.isNotEmpty ?? false) &&
          (_password?.isNotEmpty ?? false));
  String? get error => _error;

  List<DateTime> deadlineReminderTimesFor(TimelineItem item, {DateTime? now}) {
    if (!_isDeadlineReminderEnabled) return const <DateTime>[];
    return _deadlineReminderService.previewDeadlineReminderTimes(
      item,
      preferences: _deadlineReminderPreferences,
      now: now,
    );
  }

  String? get portalProfileError => _portalProfileError;
  String? get portalAvatarError => _portalAvatarError;
  String? get timetableError => _timetableError;
  String? get username => _username;
  String get baseUrl => _apiClient.baseUrl;
  bool get canOpenOfficialSchoolSession => sessionScope == AppSessionScope.app;

  AppSessionLease? captureSessionLease() {
    final session = _session;
    final username = _username;
    if (session == null ||
        username == null ||
        username.isEmpty ||
        _isLoggingOut) {
      return null;
    }
    return _AppSessionLease(this, _authGeneration, session, username);
  }

  Future<MailAccessCredentials?> loadMailAccessCredentials() async {
    if (sessionScope == AppSessionScope.studyWindow || !isLoggedIn) {
      return null;
    }
    final generation = _authGeneration;
    await mailAccess.ensureVerified();
    return _isCurrentAuthOperation(generation) ? mailAccess.credentials : null;
  }

  void _mailAccessChanged() {
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _bindMailAccess(
    String username,
    String password,
    int generation, {
    required bool fromStorage,
    required bool persistCredentials,
  }) async {
    MailLoginSettings settings = const MailLoginSettings();
    try {
      if (fromStorage && _restoredMailSettings != null) {
        settings = _restoredMailSettings!;
      } else {
        final saved = await _withCredentialMutation(_credentialStore.load);
        if (saved?.username.trim().toLowerCase() ==
            username.trim().toLowerCase()) {
          settings = saved!.mail;
        }
      }
    } catch (_) {
      // A failed credential read must not turn an iSpace success into failure.
      // Do not guess a stored mail password; allow explicit repair on this device.
      settings = const MailLoginSettings(needsPassword: true);
    }
    if (!_isCurrentAuthOperation(generation)) return;
    mailAccess.bind(
      owner: username,
      schoolPassword: password,
      settings: settings,
      persist: (mail) async {
        if (!persistCredentials && !fromStorage) return;
        await _withCredentialMutation(() async {
          if (!_isCurrentAuthOperation(generation) || _username != username) {
            return;
          }
          await _credentialStore.save(
            StoredCredentials(
              username: username,
              password: password,
              mail: mail,
            ),
          );
        });
      },
    );
  }

  Future<void> login({
    required String username,
    required String password,
    bool fromStorage = false,
    bool persistCredentials = true,
  }) async {
    await _login(
      username: username,
      password: password,
      fromStorage: fromStorage,
      persistCredentials: persistCredentials,
    );
  }

  Future<_LoginOutcome> _login({
    required String username,
    required String password,
    required bool fromStorage,
    required bool persistCredentials,
  }) async {
    if (_isLoggingOut || _logoutFuture != null) {
      _error = '退出登录处理中，请稍后再登录。';
      notifyListeners();
      return _LoginOutcome.cancelled;
    }
    _didAttemptRestore = true;
    final authGeneration = ++_authGeneration;
    _clearGradeReport();
    _checkinClient.clearSession();
    if (_username != null && _username != username) {
      _clearSessionState();
      _apiClient.clearWebSession();
      _misClient.clearSession();
    }
    _isLoggingIn = true;
    _error = null;
    notifyListeners();

    try {
      final session = await _loginWithRetry(
        username: username,
        password: password,
        authGeneration: authGeneration,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _persistSession(session: session, username: username, password: password);
      await _bindMailAccess(
        username,
        password,
        authGeneration,
        fromStorage: fromStorage,
        persistCredentials: persistCredentials,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      var credentialsSaved = true;
      if (persistCredentials) {
        credentialsSaved = await _saveCredentials(
          username: username,
          password: password,
          expectedAuthGeneration: authGeneration,
        );
      }
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      if (!credentialsSaved && _isCurrentAuthOperation(authGeneration)) {
        const warning = '登录成功，但本地安全存储不可用；下次启动时可能需要重新登录。';
        _error = _error == null ? warning : '${_error!}\n$warning';
      }
      notifyListeners();
      unawaited(
        _synchronizeUsageData(
          username: username,
          expectedAuthGeneration: authGeneration,
        ),
      );
      unawaited(
        Future.wait<void>([
          refreshTimeline(),
          refreshCourses(),
          refreshRecentCourses(),
          refreshPortalProfile(),
        ]),
      );
      return _isCurrentAuthOperation(authGeneration)
          ? _LoginOutcome.succeeded
          : _LoginOutcome.cancelled;
    } on MoodleAuthenticationException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _error = error.message;
      _clearSessionState();
      if (fromStorage) {
        final cleared = await _clearSavedCredentials(
          expectedAuthGeneration: authGeneration,
        );
        if (!cleared && _isCurrentAuthOperation(authGeneration)) {
          _error = '${error.message}；本地登录信息清理失败，请再次退出登录。';
        }
      }
      if (_isCurrentAuthOperation(authGeneration)) {
        notifyListeners();
      }
      return _LoginOutcome.permanentFailure;
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _error = error.message;
      _clearSessionState();
      notifyListeners();
      return _LoginOutcome.transientFailure;
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _error = '登录失败，请检查网络后重试。';
      _clearSessionState();
      notifyListeners();
      return _LoginOutcome.transientFailure;
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoggingIn = false;
        notifyListeners();
      }
    }
  }

  Future<AuthSession> _loginWithRetry({
    required String username,
    required String password,
    required int authGeneration,
  }) async {
    const retryDelays = [
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];
    for (var attempt = 0; ; attempt++) {
      try {
        return await _apiClient.loginWithPassword(
          username: username,
          password: password,
        );
      } on MoodleAuthenticationException {
        rethrow;
      } on MoodleApiException catch (error) {
        if (!error.isRetryable || attempt >= retryDelays.length) {
          rethrow;
        }
      } on TimeoutException {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      } on SocketException {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      } on HttpException {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      }
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw MoodleApiException('登录状态已变化，请重试。');
      }
      await _retryDelay(retryDelays[attempt]);
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw MoodleApiException('登录状态已变化，请重试。');
      }
    }
  }

  Future<void> restoreSessionIfPossible() async {
    if (_didAttemptRestore || _session != null || _isLoggingOut) {
      return;
    }
    _didAttemptRestore = true;
    final authGeneration = _authGeneration;
    _isRestoringSession = true;
    notifyListeners();
    try {
      final credentials = await _loadSavedCredentialsWithRetry();
      if (credentials == null ||
          authGeneration != _authGeneration ||
          _isLoggingOut) {
        return;
      }
      if (sessionScope == AppSessionScope.studyWindow) {
        _username = credentials.$1;
        _password = credentials.$2;
        return;
      }
      final outcome = await _login(
        username: credentials.$1,
        password: credentials.$2,
        fromStorage: true,
        persistCredentials: false,
      );
      if (outcome == _LoginOutcome.transientFailure && !_isLoggingOut) {
        _didAttemptRestore = false;
      }
    } catch (_) {
      if (_isCurrentAuthOperation(authGeneration)) {
        _didAttemptRestore = false;
        _error = '本地登录信息读取失败，请稍后重试。';
      }
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<void> refreshRecentCourses() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final authGeneration = _authGeneration;

    _isLoadingRecentCourses = true;
    _error = null;
    notifyListeners();

    try {
      final courses = await _withSessionRetry((liveSession) {
        return _apiClient.fetchRecentCourses(
          token: liveSession.token,
          userId: liveSession.userId,
        );
      });
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _recentCourses = courses;
      notifyListeners();
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = '最近访问课程加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingRecentCourses = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshTimeline() async {
    final session = _session;
    if (session == null) {
      _error = '请先登录 iSpace 账号。';
      notifyListeners();
      return;
    }
    final authGeneration = _authGeneration;

    _isLoadingTimeline = true;
    _error = null;
    notifyListeners();

    try {
      final items = await _withSessionRetry((liveSession) {
        return _apiClient.fetchAllTimeline(token: liveSession.token);
      });
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timelineItems = items;
      notifyListeners();
      unawaited(_syncDeadlineReminders(items));
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = 'Timeline 拉取失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingTimeline = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshCourses() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final authGeneration = _authGeneration;

    _isLoadingCourses = true;
    _error = null;
    notifyListeners();

    try {
      final courses = await _withSessionRetry((liveSession) {
        return _apiClient.fetchMyCourses(
          token: liveSession.token,
          userId: liveSession.userId,
        );
      });
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _courses = courses;
      _moodleCatalogRevision++;
      notifyListeners();
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = '课程列表加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingCourses = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshTimetable() {
    return _loadTimetable(force: true);
  }

  Future<void> ensureTimetableLoaded() {
    return _loadTimetable(force: false);
  }

  Future<void> _loadTimetable({required bool force}) {
    if (!force && _timetable != null) {
      return Future<void>.value();
    }
    final authGeneration = _authGeneration;
    final active = _timetableLoadFuture;
    if (active != null && _timetableLoadGeneration == authGeneration) {
      return active;
    }
    final future = _refreshTimetableOnce(authGeneration);
    _timetableLoadFuture = future;
    _timetableLoadGeneration = authGeneration;
    return future.whenComplete(() {
      if (identical(_timetableLoadFuture, future) &&
          _timetableLoadGeneration == authGeneration) {
        _timetableLoadFuture = null;
        _timetableLoadGeneration = null;
      }
    });
  }

  Future<void> _refreshTimetableOnce(int authGeneration) async {
    final credentials = await _currentCredentials();
    if (credentials == null || !_isCurrentAuthOperation(authGeneration)) {
      if (_isCurrentAuthOperation(authGeneration)) {
        _timetableError = '请先登录后加载课表。';
        notifyListeners();
      }
      return;
    }

    _isLoadingTimetable = true;
    _timetableError = null;
    notifyListeners();

    if (_timetable == null) {
      try {
        final cached = await _timetableCacheStore.load(credentials.$1);
        if (cached != null && _isCurrentAuthOperation(authGeneration)) {
          _timetable = cached;
          notifyListeners();
          unawaited(_syncCourseReminders(cached));
        }
      } catch (_) {
        // A damaged or unavailable local cache must never block live MIS data.
      }
    }

    // A desktop study window runs in another Flutter engine. It may restore
    // the shared credential record for iSpace file access, but must never
    // create a second live SSO/MIS/Portal session. It can consume only the
    // account-scoped timetable cache written by the main app engine.
    if (!canOpenOfficialSchoolSession) {
      if (_isCurrentAuthOperation(authGeneration)) {
        _isLoadingTimetable = false;
        notifyListeners();
      }
      return;
    }

    try {
      var timetable = await _fetchTimetableWithRetry(
        credentials: credentials,
        authGeneration: authGeneration,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      try {
        final examTimetable = await _misClient.fetchExamTimetable(
          username: credentials.$1,
          password: credentials.$2,
        );
        if (!_isCurrentAuthOperation(authGeneration)) return;
        final cachedExamTimetable = _cachedExamTimetableFor(timetable);
        timetable =
            examTimetable.availability ==
                    ExamTimetableAvailability.unavailable &&
                cachedExamTimetable != null
            ? timetable.withExamTimetable(cachedExamTimetable)
            : timetable.withExamTimetable(examTimetable);
      } on Object {
        if (!_isCurrentAuthOperation(authGeneration)) {
          return;
        }
        final cachedExamTimetable = _cachedExamTimetableFor(timetable);
        if (cachedExamTimetable != null) {
          timetable = timetable.withExamTimetable(cachedExamTimetable);
        }
      }
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timetable = timetable;
      notifyListeners();
      unawaited(_syncCourseReminders(timetable));
      try {
        await _saveTimetableCache(
          username: credentials.$1,
          timetable: timetable,
          expectedAuthGeneration: authGeneration,
        );
      } catch (_) {
        // Keep a successful live refresh independent from local cache writes.
      }
    } on BnbuMisException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timetableError = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timetableError = '课表加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingTimetable = false;
        notifyListeners();
      }
    }
  }

  Future<TimetableData> _fetchTimetableWithRetry({
    required (String, String) credentials,
    required int authGeneration,
  }) async {
    const retryDelays = <Duration>[
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];
    for (var attempt = 0; ; attempt++) {
      try {
        return await _misClient.fetchTimetable(
          username: credentials.$1,
          password: credentials.$2,
        );
      } on BnbuMisException catch (error) {
        if (!error.isRetryable || attempt >= retryDelays.length) {
          rethrow;
        }
      } on TimeoutException catch (_) {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      } on SocketException catch (_) {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      } on HttpException catch (_) {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      }
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw BnbuMisException('登录状态已变化，请重新打开页面。');
      }
      await _retryDelay(retryDelays[attempt]);
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw BnbuMisException('登录状态已变化，请重新打开页面。');
      }
    }
  }

  Future<void> refreshPortalProfile() {
    final generation = _authGeneration;
    final active = _portalProfileLoadFuture;
    if (active != null && _portalProfileLoadGeneration == generation) {
      return active;
    }
    final future = _refreshPortalProfileOnce(generation);
    _portalProfileLoadFuture = future;
    _portalProfileLoadGeneration = generation;
    return future.whenComplete(() {
      if (identical(_portalProfileLoadFuture, future)) {
        _portalProfileLoadFuture = null;
        _portalProfileLoadGeneration = null;
      }
    });
  }

  Future<void> _refreshPortalProfileOnce(int authGeneration) async {
    if (!canOpenOfficialSchoolSession) {
      return;
    }
    final credentials = await _currentCredentials();
    if (credentials == null || !_isCurrentAuthOperation(authGeneration)) {
      if (_isCurrentAuthOperation(authGeneration)) {
        _portalProfile = null;
        _portalAvatarBytes = null;
        _portalAvatarError = null;
        _portalProfileError = '请先登录后同步统一门户资料。';
        notifyListeners();
      }
      return;
    }

    _isLoadingPortalProfile = true;
    _isLoadingPortalAvatar = false;
    _portalProfileError = null;
    _portalAvatarError = null;
    notifyListeners();

    try {
      final profile = await _misClient.fetchPortalAccountProfile(
        username: credentials.$1,
        password: credentials.$2,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      if (_portalProfile?.avatarPath != profile.avatarPath) {
        _portalAvatarBytes = null;
      }
      _portalProfile = profile;
      notifyListeners();
      if (profile.avatarPath.isNotEmpty) {
        final cached = await PrivatePortraitCache.shared.load(
          credentials.$1,
          profile.avatarPath,
        );
        if (!_isCurrentAuthOperation(authGeneration)) return;
        if (cached != null) {
          _portalAvatarBytes = cached;
          notifyListeners();
        }
        _isLoadingPortalAvatar = true;
        notifyListeners();
        try {
          final avatarBytes = await _misClient.fetchPortalAccountAvatar(
            username: credentials.$1,
            password: credentials.$2,
            avatarPath: profile.avatarPath,
          );
          if (!_isCurrentAuthOperation(authGeneration)) {
            return;
          }
          if (avatarBytes != null) {
            _portalAvatarBytes = avatarBytes;
            await PrivatePortraitCache.shared.save(
              credentials.$1,
              profile.avatarPath,
              avatarBytes,
            );
            if (!_isCurrentAuthOperation(authGeneration)) return;
          }
          if (avatarBytes == null) {
            _portalAvatarError = '统一门户未提供可用的学生照片。';
          }
        } on BnbuMisException catch (error) {
          if (!_isCurrentAuthOperation(authGeneration)) {
            return;
          }
          _portalAvatarError = error.message;
        } catch (_) {
          if (!_isCurrentAuthOperation(authGeneration)) {
            return;
          }
          _portalAvatarError = '统一门户学生照片加载失败，请稍后重试。';
        } finally {
          if (_isCurrentAuthOperation(authGeneration)) {
            _isLoadingPortalAvatar = false;
            notifyListeners();
          }
        }
      } else {
        _portalAvatarError = '统一门户未提供学生照片地址。';
      }
    } on BnbuMisException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _portalProfileError = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _portalProfileError = '统一门户用户信息加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingPortalProfile = false;
        notifyListeners();
      }
    }
  }

  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后查看课程内容。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchCourseContents(
        token: liveSession.token,
        courseId: courseId,
      );
    });
  }

  Future<String> loadCoursePageHtml(int courseId, CourseModule target) async {
    final lease = captureSessionLease();
    if (lease == null) throw MoodleApiException('请先登录后查看课程内容。');
    return _withSessionRetry((session) async {
      final sections = await _apiClient.fetchCourseContents(
        token: session.token,
        courseId: courseId,
      );
      final matches = [
        for (final section in sections.where((s) => s.visible && s.userVisible))
          for (final m in section.modules)
            if (m.visible &&
                m.userVisible &&
                m.id == target.id &&
                m.instance == target.instance &&
                m.modName == 'page')
              m,
      ];
      if (!lease.isActive || matches.length != 1) {
        throw MoodleApiException('内容暂不可用');
      }
      final pages = await _apiClient.fetchCoursewarePageHtml(
        token: session.token,
        courseId: courseId,
        allowedInstances: {target.instance},
      );
      if (!lease.isActive || !pages.containsKey(target.instance)) {
        throw MoodleApiException('内容暂不可用');
      }
      return pages[target.instance]!;
    });
  }

  Future<CoursewareDownloadPlan> loadCoursewareDownloadPlan(
    int courseId,
  ) async {
    final lease = captureSessionLease();
    if (lease == null) throw MoodleApiException('请先登录后下载课件。');
    return _withSessionRetry((liveSession) async {
      if (!liveSession.runtimeProfile.downloadFiles) {
        throw MoodleApiException('学校当前未开放文件读取。');
      }
      final sections = await _apiClient.fetchCourseContents(
        token: liveSession.token,
        courseId: courseId,
      );
      if (!lease.isActive) throw MoodleApiException('登录状态已变化，请重新打开课程页面。');
      final pageIds = {
        for (final section in sections)
          if (section.visible && section.userVisible)
            for (final module in section.modules)
              if (module.visible &&
                  module.userVisible &&
                  module.downloadContent &&
                  module.modName == 'page')
                module.instance,
      };
      var pages = <int, String>{};
      try {
        pages = await _apiClient.fetchCoursewarePageHtml(
          token: liveSession.token,
          courseId: courseId,
          allowedInstances: pageIds,
        );
      } on MoodleAuthenticationException {
        rethrow;
      } on MoodleApiException {
        // The picker explicitly reports incomplete page discovery. Available
        // REST resources remain selectable; never call that a complete course.
      }
      if (!lease.isActive) throw MoodleApiException('登录状态已变化，请重新打开课程页面。');
      return buildCoursewareDownloadPlan(
        baseUrl: baseUrl,
        sections: sections,
        pageHtmlByInstance: pages,
        unavailablePages: pageIds.difference(pages.keys.toSet()).length,
      );
    });
  }

  Future<List<String>> loadCourseTeacherNames(int courseId) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后查看课程教师。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchCourseTeacherNames(
        token: liveSession.token,
        courseId: courseId,
      );
    });
  }

  Future<CourseGradeSnapshot> loadCourseGrades(int courseId) async {
    final session = _session;
    if (session == null) {
      throw MoodleApiException('请先登录后查看成绩。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchCourseGrades(
        token: liveSession.token,
        courseId: courseId,
        userId: liveSession.userId,
      );
    });
  }

  Future<MoodleModuleAccessSnapshot> loadModuleAccess({
    required String moduleType,
    required int instanceId,
    required int courseId,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后检查活动权限。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchModuleAccess(
        token: liveSession.token,
        moduleType: moduleType,
        instanceId: instanceId,
        courseId: courseId,
      );
    });
  }

  Future<void> setAssistantModuleCompletion({
    required String moduleRef,
    required bool completed,
  }) async {
    final lease = captureSessionLease();
    final profile = moodleRuntimeProfile;
    if (lease == null ||
        profile == null ||
        !profile.supports(MoodleNormalizedCapability.completionManualWrite)) {
      throw MoodleApiException('学校当前未开放手动完成状态更新。');
    }
    final target = await _resolveAssistantModule(moduleRef);
    if (!lease.isActive) {
      throw MoodleApiException('登录状态已变化，请重新读取课程模块。');
    }
    if (target.module.completionTracking != 1 ||
        target.module.completionData?.isTrackedUser != true ||
        target.module.completionData?.userVisible != true) {
      throw MoodleApiException('该课程模块不支持手动完成状态。');
    }
    await _withSessionRetry((liveSession) {
      return _apiClient.updateManualCompletion(
        token: liveSession.token,
        courseId: target.course.id,
        courseModuleId: target.module.id,
        userId: liveSession.userId,
        completed: completed,
      );
    });
    _moodleCatalogRevision++;
  }

  Future<bool> assistantModuleCompletionState(String moduleRef) async {
    final target = await _resolveAssistantModule(moduleRef);
    if (target.module.completionTracking != 1 ||
        target.module.completionData?.isTrackedUser != true ||
        target.module.completionData?.userVisible != true) {
      throw MoodleApiException('该课程模块不支持手动完成状态。');
    }
    return (target.module.completionData?.state ?? 0) != 0;
  }

  Future<MoodleModuleAccessSnapshot> loadAssistantModuleAccess(
    String moduleRef,
  ) async {
    final target = await _resolveAssistantModule(moduleRef);
    return loadModuleAccess(
      moduleType: target.module.modName.trim().toLowerCase(),
      instanceId: target.module.instance,
      courseId: target.course.id,
    );
  }

  Future<MoodleModuleAccessSnapshot> submitAssistantChoice({
    required String moduleRef,
    required List<int> optionIds,
  }) async {
    final lease = captureSessionLease();
    final profile = moodleRuntimeProfile;
    if (lease == null ||
        profile == null ||
        !profile.supports(MoodleNormalizedCapability.choiceWrite)) {
      throw MoodleApiException('学校当前未开放 Choice 提交能力。');
    }
    final target = await _resolveAssistantModule(moduleRef);
    if (!lease.isActive) {
      throw MoodleApiException('登录状态已变化，请重新读取课程模块。');
    }
    if (target.module.modName.trim().toLowerCase() != 'choice') {
      throw MoodleApiException('目标课程模块不是 Choice。');
    }
    final result = await _withSessionRetry((liveSession) {
      return _apiClient.submitChoice(
        token: liveSession.token,
        courseId: target.course.id,
        choiceId: target.module.instance,
        optionIds: optionIds,
      );
    });
    _moodleCatalogRevision++;
    return result;
  }

  Future<({CourseSummary course, CourseModule module})> _resolveAssistantModule(
    String moduleRef,
  ) async {
    final match = RegExp(
      r'^m1:([1-9][0-9]{0,19}):([1-9][0-9]{0,19}):'
      r'([1-9][0-9]{0,19}):([a-z][a-z0-9_]{0,79})$',
    ).firstMatch(moduleRef.trim());
    if (match == null) {
      throw MoodleApiException('iSpace 课程模块引用无效。');
    }
    final courseId = int.tryParse(match.group(1)!) ?? 0;
    final moduleId = int.tryParse(match.group(2)!) ?? 0;
    final instanceId = int.tryParse(match.group(3)!) ?? 0;
    final moduleType = match.group(4)!;
    final courseMatches = _courses.where(
      (course) => course.id == courseId && course.visible && !course.hidden,
    );
    if (courseMatches.length != 1) {
      throw MoodleApiException('iSpace 课程模块引用已失效。');
    }
    final course = courseMatches.single;
    final sections = await loadCourseContents(course.id);
    final moduleMatches = sections
        .expand((section) => section.modules)
        .where(
          (module) =>
              module.id == moduleId &&
              module.instance == instanceId &&
              module.modName.trim().toLowerCase() == moduleType &&
              module.userVisible,
        );
    if (moduleMatches.length != 1) {
      throw MoodleApiException('iSpace 课程模块引用已失效。');
    }
    return (course: course, module: moduleMatches.single);
  }

  Future<TimelineItem> resolveAssistantModuleTimelineItem(
    String moduleRef,
  ) async {
    final target = await _resolveAssistantModule(moduleRef);
    DateTime? sortTime;
    for (final date in target.module.dates) {
      final kind = '${date.dataId} ${date.label}'.toLowerCase();
      if (kind.contains('due') ||
          kind.contains('close') ||
          kind.contains('end')) {
        sortTime = date.dateTime;
        if (sortTime != null) break;
      }
    }
    return TimelineItem(
      id: target.module.id,
      title: target.module.name,
      activityState: '',
      activityType: target.module.modName,
      moduleName: target.module.modName,
      description: '',
      courseName: target.course.fullName,
      courseId: target.course.id,
      instanceId: target.module.instance,
      url: target.module.url,
      sortTime: sortTime,
      formattedTime: '',
      isOverdue: false,
    );
  }

  Future<TimelineDetailData> loadTimelineDetail(TimelineItem item) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后查看详情。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchTimelineDetail(
        token: liveSession.token,
        item: item,
      );
    });
  }

  Future<QuizAttemptSnapshot> loadQuizAttempt(TimelineItem item) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后读取测验。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchQuizAttempt(token: liveSession.token, item: item);
    });
  }

  Future<QuizAttemptSnapshot> startQuizAttempt(TimelineItem item) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后开始测验。');
    }
    final result = await _withSessionRetry((liveSession) {
      return _apiClient.startQuizAttempt(token: liveSession.token, item: item);
    });
    _moodleCatalogRevision++;
    return result;
  }

  Future<void> saveQuizAttempt({
    required QuizAttemptSnapshot snapshot,
    required List<QuizAnswerDraft> answers,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后保存测验答案。');
    }
    await _withSessionRetry((liveSession) {
      return _apiClient.saveQuizAttempt(
        token: liveSession.token,
        snapshot: snapshot,
        answers: answers,
      );
    });
    _moodleCatalogRevision++;
  }

  Future<void> finishQuizAttempt({
    required QuizAttemptSnapshot snapshot,
    required List<QuizAnswerDraft> answers,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后提交测验。');
    }
    await _withSessionRetry((liveSession) {
      return _apiClient.finishQuizAttempt(
        token: liveSession.token,
        snapshot: snapshot,
        answers: answers,
      );
    });
    _moodleCatalogRevision++;
  }

  Future<Uint8List> readAssistantCourseFile(String url) => _withSessionRetry(
    (session) =>
        _apiClient.readAssistantFile(token: session.token, fileUrl: url),
  );

  Future<String> readAssistantModuleText({
    required int courseId,
    required int instanceId,
    required String moduleType,
    int pageId = 0,
  }) => _withSessionRetry(
    (session) => _apiClient.readAssistantModuleText(
      token: session.token,
      courseId: courseId,
      instanceId: instanceId,
      moduleType: moduleType,
      pageId: pageId,
    ),
  );

  Future<QuizAttemptSnapshot> readAssistantQuizPage(
    TimelineItem item,
    int page,
  ) => _withSessionRetry(
    (session) => _apiClient.fetchQuizAttempt(
      token: session.token,
      item: item,
      startPage: page,
      pageBudget: 1,
    ),
  );

  Future<List<ForumDiscussion>> readAssistantForumPage(int forumId, int page) =>
      _withSessionRetry(
        (session) => _apiClient.readAssistantForumPage(
          token: session.token,
          forumId: forumId,
          page: page,
        ),
      );

  Future<List<ForumPost>> loadForumDiscussionPosts(int discussionId) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后查看讨论内容。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchForumDiscussionPosts(
        token: liveSession.token,
        discussionId: discussionId,
      );
    });
  }

  Future<WebSessionSnapshot> prepareWebSession() async {
    final authGeneration = _authGeneration;
    if (_isLoggingOut) {
      throw MoodleApiException('退出登录处理中，请稍后重试。');
    }
    if (_session == null && sessionScope == AppSessionScope.app) {
      await _refreshSessionFromSavedCredentials();
    }
    final credentials = await _currentCredentials();
    if (credentials == null ||
        authGeneration != _authGeneration ||
        _isLoggingOut) {
      throw MoodleApiException('请先登录后再加载官网页面。');
    }
    final snapshot = await _apiClient.prepareWebSession(
      username: credentials.$1,
      password: credentials.$2,
    );
    if (authGeneration != _authGeneration || _isLoggingOut) {
      _apiClient.clearWebSession();
      throw MoodleApiException('登录状态已变化，请重新打开页面。');
    }
    return snapshot;
  }

  /// Session-only snapshot; stale results remain visible for at most 30 minutes.
  GradeReport? get cachedGradeReport {
    final loadedAt = _gradeReportLoadedAt;
    final age = loadedAt == null
        ? null
        : _gradeReportClock().difference(loadedAt);
    if (!canOpenOfficialSchoolSession ||
        _isDisposed ||
        _isLoggingIn ||
        _reloginFuture != null ||
        _gradeReportLease?.isActive != true ||
        age == null ||
        age.isNegative ||
        age >= const Duration(minutes: 30)) {
      return null;
    }
    return _gradeReport;
  }

  Future<GradeReport> loadGradeReport({bool forceRefresh = false}) {
    final lease = captureSessionLease();
    if (!canOpenOfficialSchoolSession ||
        _isDisposed ||
        _isLoggingIn ||
        _reloginFuture != null ||
        lease == null ||
        !lease.isActive) {
      return Future.error(BnbuMisException('当前会话无法读取成绩报告。'));
    }
    final pending = _gradeReportFuture;
    if (pending != null) return pending;
    final cached = cachedGradeReport;
    final loadedAt = _gradeReportLoadedAt;
    final age = loadedAt == null
        ? null
        : _gradeReportClock().difference(loadedAt);
    if (!forceRefresh &&
        cached != null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(minutes: 2)) {
      return Future.value(cached);
    }
    final generation = _gradeReportGeneration;
    final authGeneration = _authGeneration;
    void ensureActive() {
      if (!lease.isActive ||
          generation != _gradeReportGeneration ||
          !_isCurrentAuthOperation(authGeneration)) {
        throw BnbuMisException('成绩报告会话已变更，请重新读取。');
      }
    }

    late final Future<GradeReport> future;
    future = (() async {
      try {
        final credentials = await _currentCredentials();
        ensureActive();
        if (credentials == null) throw BnbuMisException('请重新登录后读取成绩报告。');
        final report = await _misClient.fetchGradeReport(
          username: credentials.$1,
          password: credentials.$2,
        );
        ensureActive();
        if (!report.isAllAcademicYears ||
            report.availability == GradeReportAvailability.unavailable) {
          throw BnbuMisException('成绩报告范围或格式无效，请稍后重试。');
        }
        _gradeReport = report;
        _gradeReportLoadedAt = _gradeReportClock();
        _gradeReportLease = lease;
        notifyListeners();
        return report;
      } finally {
        if (identical(_gradeReportFuture, future)) _gradeReportFuture = null;
      }
    })();
    _gradeReportFuture = future;
    return future;
  }

  void _clearGradeReport() {
    _gradeReportGeneration++;
    _gradeReport = null;
    _gradeReportLoadedAt = null;
    _gradeReportLease = null;
    _gradeReportFuture = null;
  }

  CisCheckinPageData<CisCheckinProject>? cachedCheckinProjects() =>
      captureSessionLease()?.isActive == true
      ? _checkinClient.cachedProjects()
      : null;

  CisCheckinPageData<CisCheckinRecord>? cachedCheckinRecords({
    String? projectId,
  }) => captureSessionLease()?.isActive == true
      ? _checkinClient.cachedRecords(projectId: projectId)
      : null;

  Future<void> prewarmCheckinProjects() async {
    if (!canOpenOfficialSchoolSession) return;
    try {
      await loadCheckinProjects();
    } catch (_) {
      // Preloading must not interrupt the home page; opening the page can retry.
    }
  }

  Future<CisCheckinPageData<CisCheckinProject>> loadCheckinProjects({
    int page = 1,
    bool forceRefresh = false,
  }) => _withCheckinSession(
    (username, password) => _checkinClient.fetchProjects(
      username: username,
      password: password,
      page: page,
      forceRefresh: forceRefresh,
    ),
  );

  Future<CisCheckinPageData<CisCheckinRecord>> loadCheckinRecords({
    String? projectId,
    int page = 1,
    bool forceRefresh = false,
  }) => _withCheckinSession(
    (username, password) => _checkinClient.fetchRecords(
      username: username,
      password: password,
      projectId: projectId,
      page: page,
      forceRefresh: forceRefresh,
    ),
  );

  Future<T> _withCheckinSession<T>(
    Future<T> Function(String, String) read,
  ) async {
    final lease = captureSessionLease();
    if (!canOpenOfficialSchoolSession || lease == null || !lease.isActive) {
      throw const CisCheckinException(CisCheckinFailure.sessionChanged);
    }
    final credentials = await _currentCredentials();
    if (credentials == null || !lease.isActive) {
      throw const CisCheckinException(CisCheckinFailure.sessionChanged);
    }
    final result = await read(credentials.$1, credentials.$2);
    if (!lease.isActive) {
      throw const CisCheckinException(CisCheckinFailure.sessionChanged);
    }
    return result;
  }

  Future<WebSessionSnapshot> prepareOfficialWebSession(
    OfficialWebTarget target,
  ) async {
    if (!canOpenOfficialSchoolSession) {
      throw BnbuMisException('请返回 BNBU.ME 主窗口打开 MIS 或统一门户。');
    }
    final authGeneration = _authGeneration;
    if (_isLoggingOut) {
      throw BnbuMisException('退出登录处理中，请稍后重试。');
    }
    final credentials = await _currentCredentials();
    if (credentials == null ||
        authGeneration != _authGeneration ||
        _isLoggingOut) {
      throw BnbuMisException('请先登录后再加载学校官网页面。');
    }
    final snapshot = await _prepareOfficialWebSessionWithRetry(
      target: target,
      credentials: credentials,
      authGeneration: authGeneration,
    );
    if (authGeneration != _authGeneration || _isLoggingOut) {
      throw BnbuMisException('登录状态已变化，请重新打开页面。');
    }
    return snapshot;
  }

  Future<void> resetOfficialWebSession(OfficialWebTarget target) {
    if (_isLoggingOut || !canOpenOfficialSchoolSession) {
      return Future<void>.value();
    }
    return _misClient.invalidateOfficialWebSession(target);
  }

  Future<void> reconcileOfficialWebSession(
    OfficialWebTarget target,
    List<WebSessionCookie> cookies,
  ) async {
    final authGeneration = _authGeneration;
    if (_isLoggingOut ||
        !canOpenOfficialSchoolSession ||
        _session == null ||
        cookies.isEmpty) {
      return;
    }
    await _misClient.reconcileOfficialWebSession(
      target: target,
      cookies: cookies,
    );
    if (!_isCurrentAuthOperation(authGeneration)) {
      return;
    }
  }

  Future<WebSessionSnapshot> _prepareOfficialWebSessionWithRetry({
    required OfficialWebTarget target,
    required (String, String) credentials,
    required int authGeneration,
  }) async {
    const retryDelays = [
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];
    for (var attempt = 0; ; attempt++) {
      try {
        return await _misClient.prepareOfficialWebSession(
          target: target,
          username: credentials.$1,
          password: credentials.$2,
        );
      } on BnbuMisException catch (error) {
        if (!error.isRetryable || attempt >= retryDelays.length) {
          rethrow;
        }
      } on TimeoutException catch (_) {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      } on SocketException catch (_) {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      } on HttpException catch (_) {
        if (attempt >= retryDelays.length) {
          rethrow;
        }
      }
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw BnbuMisException('登录状态已变化，请重新打开页面。');
      }
      await _misClient.invalidateOfficialWebSession(target);
      await _retryDelay(retryDelays[attempt]);
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw BnbuMisException('登录状态已变化，请重新打开页面。');
      }
    }
  }

  Future<TimelineDetailData> loadAssignmentDetailByCourseModule({
    required int courseId,
    required int courseModuleId,
    required String title,
    required String courseName,
    required String url,
  }) async {
    final pseudoItem = TimelineItem(
      id: -courseModuleId,
      title: title,
      activityState: 'Assignment is due',
      activityType: 'assign',
      moduleName: 'assign',
      description: '',
      courseName: courseName,
      courseId: courseId,
      instanceId: courseModuleId,
      url: url,
      sortTime: null,
      formattedTime: '',
      isOverdue: false,
    );
    return loadTimelineDetail(pseudoItem);
  }

  Future<AssignmentSubmissionOutcome> submitAssignmentOnlineText({
    required int assignmentId,
    required String text,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后提交作业。');
    }
    final result = await _withSessionRetry((liveSession) {
      return _apiClient.submitAssignmentOnlineText(
        token: liveSession.token,
        assignmentId: assignmentId,
        text: text,
      );
    });
    _moodleCatalogRevision++;
    return result;
  }

  Future<AssignmentSubmissionOutcome> submitAssignmentFiles({
    required int assignmentId,
    required List<UploadFilePayload> files,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后提交作业。');
    }
    final result = await _withSessionRetry((liveSession) {
      return _apiClient.submitAssignmentFiles(
        token: liveSession.token,
        assignmentId: assignmentId,
        files: files,
      );
    });
    _moodleCatalogRevision++;
    return result;
  }

  Future<AssignmentSubmissionOutcome> finalizeAssignment({
    required int assignmentId,
    required bool acceptSubmissionStatement,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后最终提交作业。');
    }
    final result = await _withSessionRetry((liveSession) {
      return _apiClient.finalizeAssignment(
        token: liveSession.token,
        assignmentId: assignmentId,
        acceptSubmissionStatement: acceptSubmissionStatement,
      );
    });
    _moodleCatalogRevision++;
    return result;
  }

  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    notifyListeners();
  }

  Future<void> sendUsageHeartbeat() async {
    final username = _username;
    if (username == null || _session == null || _isLoggingOut) {
      return;
    }
    try {
      await _usageSyncService.heartbeat(username);
    } catch (_) {
      // Foreground presence is best-effort and never blocks school features.
    }
  }

  /// Only reschedule existing local plans to attach the newly consented epoch.
  Future<void> refreshReminderStatisticsBindings() async {
    if (!isLoggedIn || _isLoggingOut) return;
    await _syncDeadlineReminders(_timelineItems);
    final timetable = _timetable;
    if (timetable != null) await _syncCourseReminders(timetable);
  }

  Future<void> _synchronizeUsageData({
    required String username,
    required int expectedAuthGeneration,
  }) async {
    if (!_isCurrentAuthOperation(expectedAuthGeneration)) {
      return;
    }
    try {
      await _usageSyncService.synchronize(username);
    } catch (_) {
      // Enrollment retries on the next foreground heartbeat.
    }
  }

  Future<void> logout() {
    final activeLogout = _logoutFuture;
    if (activeLogout != null) {
      return activeLogout;
    }

    final completer = Completer<void>();
    final logoutFuture = completer.future;
    _logoutFuture = logoutFuture;
    unawaited(() async {
      try {
        await _performLogout();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_logoutFuture, logoutFuture)) {
          _logoutFuture = null;
        }
      }
    }());
    return logoutFuture;
  }

  Future<void> _performLogout() async {
    final departingOwner = username;
    _authGeneration++;
    _isLoggingOut = true;
    _isLoggingIn = false;
    _isRestoringSession = false;
    _error = null;
    _clearSessionState();
    _apiClient.clearWebSession();
    _misClient.clearSession();
    notifyListeners();

    if (sessionScope == AppSessionScope.studyWindow) {
      _isLoggingOut = false;
      notifyListeners();
      return;
    }

    if (departingOwner != null) {
      await PrivatePortraitCache.shared.clear(departingOwner);
    }
    final credentialsCleared = await _clearSavedCredentials();
    var localSessionCleared = true;
    try {
      await Future.wait([
        (() async {
          await _deadlineReminderService.disable();
          await _deadlineReminderService.disableCourseNotifications();
          await _deadlineReminderService.cancelAll();
        })(),
        _nativeActions.clearWebSession(),
      ]);
    } on MissingPluginException {
      localSessionCleared = false;
    } catch (_) {
      localSessionCleared = false;
    }

    _isLoggingOut = false;
    if (!credentialsCleared || !localSessionCleared) {
      _error = '已退出登录，但部分本地登录数据清理失败；请在错误消失前保持应用打开并再次退出。';
    } else {
      _error = null;
    }
    notifyListeners();
  }

  Future<String?> setDeadlineReminderEnabled(bool enabled) async {
    if (_isUpdatingDeadlineReminder) {
      return 'DDL 提醒设置处理中，请稍后再试。';
    }

    _deadlineReminderPreferenceGeneration++;
    _isLoadingDeadlineReminderPreference = false;
    _isUpdatingDeadlineReminder = true;
    notifyListeners();

    try {
      if (!enabled) {
        await _deadlineReminderService.disable();
        _isDeadlineReminderEnabled = false;
        return null;
      }

      final permissionError = await _deadlineReminderService.enable();
      if (permissionError != null) {
        _isDeadlineReminderEnabled = false;
        return permissionError;
      }

      _isDeadlineReminderEnabled = true;
      notifyListeners();

      if (_timelineItems.isEmpty) {
        unawaited(refreshTimeline());
      } else {
        unawaited(_syncDeadlineReminders(_timelineItems));
      }
      return null;
    } catch (_) {
      return enabled ? 'DDL 提醒开启失败，请稍后重试。' : 'DDL 提醒关闭失败，请稍后重试。';
    } finally {
      _isUpdatingDeadlineReminder = false;
      notifyListeners();
    }
  }

  Future<String?> setCourseReminderEnabled(bool enabled) async {
    if (_isUpdatingCourseReminder) {
      return '课表通知设置处理中，请稍后再试。';
    }

    _courseReminderPreferenceGeneration++;
    _isLoadingCourseReminderPreference = false;
    _isUpdatingCourseReminder = true;
    notifyListeners();

    try {
      if (!enabled) {
        await _deadlineReminderService.disableCourseNotifications();
        _isCourseReminderEnabled = false;
        return null;
      }

      final permissionError = await _deadlineReminderService
          .enableCourseNotifications();
      if (permissionError != null) {
        _isCourseReminderEnabled = false;
        return permissionError;
      }

      _isCourseReminderEnabled = true;
      notifyListeners();

      final timetable = _timetable;
      if (timetable == null) {
        unawaited(ensureTimetableLoaded());
      } else {
        unawaited(_syncCourseReminders(timetable));
      }
      return null;
    } catch (_) {
      return enabled ? '课表通知开启失败，请稍后重试。' : '课表通知关闭失败，请稍后重试。';
    } finally {
      _isUpdatingCourseReminder = false;
      notifyListeners();
    }
  }

  Future<String?> setDeadlineReminderLeadMinutes(int value) async {
    return setDeadlineReminderPreferences(
      DeadlineReminderPreferences(
        mode: DeadlineReminderMode.fixed,
        reminderCount: 1,
        fixedLeadMinutes: <int>[value],
        quietStartMinutes: _deadlineReminderPreferences.quietStartMinutes,
        quietEndMinutes: _deadlineReminderPreferences.quietEndMinutes,
      ),
    );
  }

  Future<String?> setDeadlineReminderPreferences(
    DeadlineReminderPreferences value,
  ) async {
    _deadlineReminderPreferenceGeneration++;
    _isLoadingDeadlineReminderPreference = false;
    try {
      _deadlineReminderPreferences = await _deadlineReminderService
          .setDeadlineReminderPreferences(value);
      _deadlineReminderLeadMinutes =
          _deadlineReminderPreferences.effectiveLeadMinutes.first;
      notifyListeners();
      if (_isDeadlineReminderEnabled) {
        if (_timelineItems.isEmpty) {
          unawaited(refreshTimeline());
        } else {
          unawaited(_syncDeadlineReminders(_timelineItems));
        }
      }
      return null;
    } catch (_) {
      return 'DDL 通知设置保存失败，请稍后重试。';
    }
  }

  Future<String?> setCourseReminderLeadMinutes(int value) async {
    _courseReminderPreferenceGeneration++;
    _isLoadingCourseReminderPreference = false;
    try {
      _courseReminderLeadMinutes = await _deadlineReminderService
          .setCourseLeadMinutes(value);
      notifyListeners();
      if (_isCourseReminderEnabled) {
        final timetable = _timetable;
        if (timetable == null) {
          unawaited(ensureTimetableLoaded());
        } else {
          unawaited(_syncCourseReminders(timetable));
        }
      }
      return null;
    } catch (_) {
      return '课表通知时间保存失败，请稍后重试。';
    }
  }

  Future<String?> scheduleAssistantReminder({
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    final lease = captureSessionLease();
    if (lease == null) {
      return '请先登录后再让小U设置提醒。';
    }
    try {
      final error = await _deadlineReminderService.scheduleAssistantReminder(
        title: title,
        body: body,
        scheduledAt: scheduledAt,
      );
      if (!lease.isActive) {
        return '登录状态已变化，请重新设置提醒。';
      }
      return error;
    } catch (_) {
      return '提醒设置失败，请稍后重试。';
    }
  }

  Future<T> _withSessionRetry<T>(
    Future<T> Function(AuthSession session) request,
  ) async {
    final authGeneration = _authGeneration;
    final initialSession = _session;
    if (initialSession == null) {
      throw MoodleApiException('请先登录 iSpace 账号。');
    }
    var liveSession = initialSession;
    const retryDelays = [
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];
    var retryAttempt = 0;
    var didRefreshToken = false;
    while (true) {
      try {
        final result = await request(liveSession);
        if (!_isCurrentAuthOperation(authGeneration)) {
          throw MoodleApiException('登录状态已变化，请重试。');
        }
        return result;
      } on MoodleApiException catch (error) {
        if (!_isCurrentAuthOperation(authGeneration)) {
          rethrow;
        }
        if (!didRefreshToken && _looksLikeTokenExpired(error.message)) {
          final refreshed = await _refreshSessionFromSavedCredentials();
          if (refreshed == null || !_isCurrentAuthOperation(authGeneration)) {
            rethrow;
          }
          liveSession = refreshed;
          didRefreshToken = true;
          continue;
        }
        if (!error.isRetryable || retryAttempt >= retryDelays.length) {
          rethrow;
        }
      }
      await _retryDelay(retryDelays[retryAttempt]);
      retryAttempt++;
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw MoodleApiException('登录状态已变化，请重试。');
      }
    }
  }

  bool _looksLikeTokenExpired(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('invalidtoken') ||
        normalized.contains('invalid token') ||
        normalized.contains('token is invalid') ||
        normalized.contains('accessexception');
  }

  Future<AuthSession?> _refreshSessionFromSavedCredentials() async {
    if (_isLoggingOut) {
      return null;
    }
    if (_reloginFuture != null) {
      return _reloginFuture!;
    }
    _reloginFuture = _doRefreshSession();
    try {
      return await _reloginFuture;
    } finally {
      _reloginFuture = null;
    }
  }

  Future<AuthSession?> _doRefreshSession() async {
    _clearGradeReport();
    final authGeneration = _authGeneration;
    final credentials = await _currentCredentials();
    if (credentials == null || !_isCurrentAuthOperation(authGeneration)) {
      return null;
    }
    try {
      final session = await _loginWithRetry(
        username: credentials.$1,
        password: credentials.$2,
        authGeneration: authGeneration,
      );
      if (!_isCurrentAuthOperation(authGeneration) || _session == null) {
        return null;
      }
      _persistSession(
        session: session,
        username: credentials.$1,
        password: credentials.$2,
      );
      await _saveCredentials(
        username: credentials.$1,
        password: credentials.$2,
        expectedAuthGeneration: authGeneration,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return null;
      }
      notifyListeners();
      return session;
    } on MoodleAuthenticationException catch (error) {
      final cleared = await _clearSavedCredentials(
        expectedAuthGeneration: authGeneration,
      );
      if (_isCurrentAuthOperation(authGeneration)) {
        _authGeneration++;
        _error = cleared
            ? error.message
            : '${error.message}；本地登录信息清理失败，请再次退出登录。';
        _clearSessionState();
        notifyListeners();
      }
      return null;
    } on MoodleApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshAccountReminderHabits() async {
    await _restoreDeadlineReminderPreference();
    await _restoreCourseReminderPreference();
    if (isLoggedIn) await _syncDeadlineReminders(timelineItems);
  }

  Future<void> _restoreDeadlineReminderPreference() async {
    final generation = _deadlineReminderPreferenceGeneration;
    try {
      final enabled = await _deadlineReminderService.loadEnabled();
      final reminderPreferences = await _deadlineReminderService
          .loadDeadlineReminderPreferences();
      if (generation != _deadlineReminderPreferenceGeneration || _isDisposed) {
        return;
      }
      _isDeadlineReminderEnabled = enabled;
      _deadlineReminderPreferences = reminderPreferences;
      _deadlineReminderLeadMinutes =
          reminderPreferences.effectiveLeadMinutes.first;
    } catch (_) {
      if (generation == _deadlineReminderPreferenceGeneration && !_isDisposed) {
        _isDeadlineReminderEnabled = false;
      }
    } finally {
      if (generation == _deadlineReminderPreferenceGeneration && !_isDisposed) {
        _isLoadingDeadlineReminderPreference = false;
        notifyListeners();
      }
    }
  }

  Future<void> _restoreCourseReminderPreference() async {
    final generation = _courseReminderPreferenceGeneration;
    try {
      final enabled = await _deadlineReminderService.loadCourseEnabled();
      final leadMinutes = await _deadlineReminderService
          .loadCourseLeadMinutes();
      if (generation != _courseReminderPreferenceGeneration || _isDisposed) {
        return;
      }
      _isCourseReminderEnabled = enabled;
      _courseReminderLeadMinutes = leadMinutes;
      final timetable = _timetable;
      if (enabled && timetable != null) {
        unawaited(_syncCourseReminders(timetable));
      }
    } catch (_) {
      if (generation == _courseReminderPreferenceGeneration && !_isDisposed) {
        _isCourseReminderEnabled = false;
      }
    } finally {
      if (generation == _courseReminderPreferenceGeneration && !_isDisposed) {
        _isLoadingCourseReminderPreference = false;
        notifyListeners();
      }
    }
  }

  Future<void> _syncDeadlineReminders(List<TimelineItem> items) async {
    if (!_isDeadlineReminderEnabled) {
      return;
    }
    try {
      await _deadlineReminderService.synchronize(items);
    } catch (_) {
      // Keep timeline refresh independent from reminder scheduling failures.
    }
  }

  List<TaCourseEntry> _fixedSchedulesForReminders = const [];
  String? _fixedScheduleReminderOwner;

  /// Receives only the current owner's validated local schedules. School
  /// sessions and native notification mutations remain owned here.
  void updateFixedScheduleReminders(
    List<TaCourseEntry> entries, {
    required String owner,
  }) {
    if (!isLoggedIn ||
        _isLoggingOut ||
        _isDisposed ||
        owner != _username?.trim().toLowerCase()) {
      return;
    }
    _fixedSchedulesForReminders = List.unmodifiable(entries);
    _fixedScheduleReminderOwner = owner;
    final timetable = _timetable;
    if (timetable != null) unawaited(_syncCourseReminders(timetable));
  }

  Future<void> _syncCourseReminders(TimetableData timetable) async {
    if (!_isCourseReminderEnabled) {
      return;
    }
    try {
      await _deadlineReminderService.synchronizeCourses(
        timetable,
        fixedSchedules:
            _fixedScheduleReminderOwner == _username?.trim().toLowerCase()
            ? _fixedSchedulesForReminders
            : const [],
      );
    } catch (_) {
      // Keep timetable refresh independent from notification scheduling.
    }
  }

  Future<(String, String)?> _currentCredentials() async {
    if (_isLoggingOut) {
      return null;
    }
    final authGeneration = _authGeneration;
    final username = (_username ?? '').trim();
    final password = _password ?? '';
    if (username.isNotEmpty && password.isNotEmpty) {
      return (username, password);
    }
    final (String, String)? saved;
    try {
      saved = await _loadSavedCredentials();
    } catch (_) {
      return null;
    }
    if (saved == null || authGeneration != _authGeneration || _isLoggingOut) {
      return null;
    }
    _username = saved.$1;
    _password = saved.$2;
    return saved;
  }

  void _persistSession({
    required AuthSession session,
    required String username,
    required String password,
  }) {
    _session = session;
    _username = username;
    _password = password;
    _moodleCatalogRevision++;
  }

  void _clearSessionState() {
    _clearGradeReport();
    _checkinClient.clearSession();
    _restoredMailSettings = null;
    mailAccess.reset();
    _moodleCatalogRevision++;
    _apiClient.clearRuntimeProfile();
    _session = null;
    _username = null;
    _fixedSchedulesForReminders = const [];
    _fixedScheduleReminderOwner = null;
    _password = null;
    _timelineItems = const [];
    _courses = const [];
    _recentCourses = const [];
    _isLoadingTimeline = false;
    _isLoadingCourses = false;
    _isLoadingRecentCourses = false;
    _isLoadingTimetable = false;
    _isLoadingPortalProfile = false;
    _isLoadingPortalAvatar = false;
    _portalProfile = null;
    _portalAvatarBytes = null;
    _timetable = null;
    _portalProfileError = null;
    _portalAvatarError = null;
    _timetableError = null;
    _isDeadlineReminderEnabled = false;
    _isCourseReminderEnabled = false;
  }

  bool _isCurrentAuthOperation(int authGeneration) {
    return !_isDisposed && authGeneration == _authGeneration && !_isLoggingOut;
  }

  bool _hasSameSelectedSemester(TimetableData left, TimetableData right) {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalize(left.selectedSemesterId) ==
            normalize(right.selectedSemesterId) &&
        normalize(left.selectedSemesterName) ==
            normalize(right.selectedSemesterName);
  }

  ExamTimetableData? _cachedExamTimetableFor(TimetableData timetable) {
    final cached = _timetable;
    if (cached == null ||
        !_hasSameSelectedSemester(cached, timetable) ||
        cached.exams.isEmpty) {
      return null;
    }
    return ExamTimetableData(
      availability: ExamTimetableAvailability.available,
      entries: cached.exams,
    );
  }

  Future<void> _saveTimetableCache({
    required String username,
    required TimetableData timetable,
    required int expectedAuthGeneration,
  }) {
    return _withTimetableCacheMutation(() async {
      if (!_isCurrentAuthOperation(expectedAuthGeneration)) {
        return;
      }
      await _timetableCacheStore.save(username, timetable);
    });
  }

  Future<bool> _saveCredentials({
    required String username,
    required String password,
    int? expectedAuthGeneration,
  }) async {
    try {
      return await _withCredentialMutation(() async {
        if (expectedAuthGeneration != null &&
            expectedAuthGeneration != _authGeneration) {
          return true;
        }
        await _credentialStore.save(
          StoredCredentials(
            username: username,
            password: password,
            mail: mailAccess.settings,
          ),
        );
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<(String, String)?> _loadSavedCredentialsWithRetry() async {
    try {
      return await _loadSavedCredentials();
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return _loadSavedCredentials();
    }
  }

  Future<(String, String)?> _loadSavedCredentials() async {
    final generation = _authGeneration;
    final credentials = await _withCredentialMutation(_credentialStore.load);
    if (credentials == null) {
      return null;
    }
    if (_isCurrentAuthOperation(generation)) {
      _restoredMailSettings = credentials.mail;
    }
    return (credentials.username, credentials.password);
  }

  Future<bool> _clearSavedCredentials({int? expectedAuthGeneration}) async {
    try {
      return await _withCredentialMutation(() async {
        if (expectedAuthGeneration != null &&
            expectedAuthGeneration != _authGeneration) {
          return true;
        }
        await _credentialStore.clear();
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<T> _withCredentialMutation<T>(Future<T> Function() operation) async {
    final previous = _credentialMutation;
    final completer = Completer<void>();
    _credentialMutation = completer.future;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
    }
  }

  Future<T> _withTimetableCacheMutation<T>(
    Future<T> Function() operation,
  ) async {
    final previous = _timetableCacheMutation;
    final completer = Completer<void>();
    _timetableCacheMutation = completer.future;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
    }
  }

  void _calendarChanged() {
    notifyListeners();
    final timetable = _timetable;
    if (timetable != null && sessionScope == AppSessionScope.app) {
      unawaited(_syncCourseReminders(timetable));
    }
  }

  @override
  void dispose() {
    BnbuAcademicCalendar.revision.removeListener(_calendarChanged);
    _isDisposed = true;
    _clearGradeReport();
    mailAccess.removeListener(_mailAccessChanged);
    mailAccess.dispose();
    _authGeneration++;
    _apiClient.dispose();
    _misClient.dispose();
    _checkinClient.dispose();
    _usageSyncService.dispose();
    statistics.dispose();
    super.dispose();
  }
}

class _AppSessionLease implements AppSessionLease {
  const _AppSessionLease(
    this._controller,
    this._authGeneration,
    this._session,
    this._username,
  );

  final AppSessionController _controller;
  final int _authGeneration;
  final AuthSession _session;
  final String _username;

  @override
  String get owner => _username;

  @override
  bool get isActive =>
      _controller._authGeneration == _authGeneration &&
      identical(_controller._session, _session) &&
      _controller._username == _username &&
      !_controller._isLoggingOut;
}
