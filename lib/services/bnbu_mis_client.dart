import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_sm/dart_sm.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../config/app_config.dart';
import '../config/ispace_tls_trust.dart';
import '../models/grade_report.dart';
import '../models/exam_timetable.dart';
import '../models/official_web_target.dart';
import '../models/portal_account_profile.dart';
import '../models/timetable_data.dart';
import '../models/web_session_snapshot.dart';

class BnbuMisException implements Exception {
  BnbuMisException(
    this.message, {
    this.isRetryable = false,
    this.requiresReauthentication = false,
  });

  final String message;
  final bool isRetryable;
  final bool requiresReauthentication;

  @override
  String toString() => 'BnbuMisException($message)';
}

class BnbuMisClient {
  BnbuMisClient({
    Duration requestTimeout = const Duration(seconds: 20),
    HttpClient? httpClient,
  }) : _httpClient =
           httpClient ??
           HttpClient(
             context: createBnbuSchoolSecurityContext(<String>[
               _ssoBaseUrl,
               _misBaseUrl,
               _portalBaseUrl,
             ]),
           ),
       _requestTimeout = requestTimeout {
    _httpClient.connectionTimeout = requestTimeout;
    _httpClient.idleTimeout = const Duration(seconds: 15);
    _httpClient.maxConnectionsPerHost = 6;
    _httpClient.userAgent =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0';
  }

  Uri _targetEntryUri(OfficialWebTarget target) {
    return Uri.parse(
      target == OfficialWebTarget.mis
          ? '$_misBaseUrl/mis/usr/index.do'
          : '$_portalBaseUrl/wui/index.html',
    );
  }

  void _invalidateTargetSession(OfficialWebTarget target) {
    final targetHost = _targetEntryUri(target).host.toLowerCase();
    _cookieJar.removeWhere((cookie) => cookie.domain == targetHost);
    switch (target) {
      case OfficialWebTarget.mis:
        _misSessionReady = false;
      case OfficialWebTarget.portal:
        _portalSessionReady = false;
    }
  }

  SameSite? _sameSiteFromWebCookie(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'lax' => SameSite.lax,
      'strict' => SameSite.strict,
      'none' => SameSite.none,
      _ => null,
    };
  }

  static final String _ssoBaseUrl = AppConfig.normalizedHttpsBaseUrl(
    AppConfig.bnbuSsoBaseUrl,
    settingName: 'BNBU_SSO_BASE_URL',
  );
  static final String _misBaseUrl = AppConfig.normalizedHttpsBaseUrl(
    AppConfig.bnbuMisBaseUrl,
    settingName: 'BNBU_MIS_BASE_URL',
  );
  static final String _portalBaseUrl = AppConfig.normalizedHttpsBaseUrl(
    AppConfig.bnbuPortalBaseUrl,
    settingName: 'BNBU_PORTAL_BASE_URL',
  );
  static final String _cookieDomain = AppConfig.normalizedCookieDomain(
    AppConfig.bnbuCookieDomain,
  );
  static const String _misServiceId = AppConfig.bnbuMisServiceId;
  static const String _portalServiceId = AppConfig.bnbuPortalServiceId;
  static final String _misLaunchUrl =
      '$_ssoBaseUrl/auth/sso/ssoLogin?service=$_misServiceId';
  static final String _portalLaunchUrl =
      '$_ssoBaseUrl/auth/sso/ssoLogin?service=$_portalServiceId';
  static final List<Uri> _trustedCookieOrigins = <Uri>[
    Uri.parse(_ssoBaseUrl),
    Uri.parse(_misBaseUrl),
    Uri.parse(_portalBaseUrl),
  ];
  static const String _htmlAcceptHeader = 'text/html,application/xhtml+xml,*/*';

  final HttpClient _httpClient;
  final Duration _requestTimeout;
  final List<_StoredCookie> _cookieJar = <_StoredCookie>[];
  final Random _random = Random();
  Future<void> _operationQueue = Future<void>.value();
  int _sessionGeneration = 0;
  int? _activeSessionGeneration;
  String? _sessionUsername;
  bool _misSessionReady = false;
  bool _portalSessionReady = false;
  bool _isDisposed = false;

  void dispose() {
    _isDisposed = true;
    _sessionGeneration++;
    _resetSessionState();
    _httpClient.close(force: true);
  }

  void clearSession() {
    _sessionGeneration++;
    _resetSessionState();
  }

  Future<void> invalidateOfficialWebSession(OfficialWebTarget target) {
    return _serializeSessionOperation(() async {
      _invalidateTargetSession(target);
    });
  }

  Future<void> reconcileOfficialWebSession({
    required OfficialWebTarget target,
    required List<WebSessionCookie> cookies,
  }) {
    if (cookies.isEmpty) {
      return Future<void>.value();
    }
    return _serializeSessionOperation(() async {
      final targetUri = _targetEntryUri(target);
      final targetHost = targetUri.host.toLowerCase();
      final now = DateTime.now();
      for (final cookie in cookies) {
        final normalizedDomain = cookie.domain
            .trim()
            .toLowerCase()
            .replaceFirst(RegExp(r'^\.+'), '');
        final normalizedPath = cookie.path.trim();
        if (cookie.name.isEmpty ||
            cookie.name.length > 256 ||
            cookie.value.length > 8192 ||
            normalizedDomain != targetHost ||
            !cookie.hostOnly ||
            !cookie.secure ||
            !normalizedPath.startsWith('/') ||
            normalizedPath.contains(';') ||
            cookie.expiresAt?.isAfter(now) == false) {
          continue;
        }
        final sameIdentity = _cookieJar.where(
          (existing) =>
              existing.name == cookie.name && existing.path == normalizedPath,
        );
        final hasExactTargetCookie = sameIdentity.any(
          (existing) => existing.domain == targetHost,
        );
        final hasOnlyParentCookie =
            !hasExactTargetCookie && sameIdentity.isNotEmpty;
        if (hasOnlyParentCookie) {
          continue;
        }
        _cookieJar.removeWhere(
          (existing) =>
              existing.name == cookie.name &&
              existing.domain == targetHost &&
              existing.path == normalizedPath,
        );
        _cookieJar.add(
          _StoredCookie(
            name: cookie.name,
            value: cookie.value,
            domain: targetHost,
            path: normalizedPath,
            hostOnly: true,
            secure: true,
            httpOnly: cookie.httpOnly,
            sameSite: _sameSiteFromWebCookie(cookie.sameSite),
            expires: cookie.expiresAt,
          ),
        );
      }
    });
  }

  @visibleForTesting
  ({String method, String? body, Map<String, String> headers})
  redirectRequestForTesting({
    required String method,
    required Uri currentUri,
    required Uri targetUri,
    required int statusCode,
    String? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    final redirect = _prepareRedirect(
      method: method,
      currentUri: currentUri,
      targetUri: targetUri,
      statusCode: statusCode,
      body: body,
      headers: headers,
    );
    return (
      method: redirect.method,
      body: redirect.body,
      headers: redirect.headers,
    );
  }

  @visibleForTesting
  void storeCookieForTesting(Cookie cookie, Uri origin) {
    _storeCookies(<Cookie>[cookie], origin);
  }

  @visibleForTesting
  String cookieHeaderForTesting(Uri target) {
    return _matchingCookies(
      target,
    ).map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  @visibleForTesting
  bool isTrustedRequestUriForTesting(Uri uri) => _isTrustedRequestUri(uri);

  @visibleForTesting
  WebSessionSnapshot officialWebSessionForTesting(OfficialWebTarget target) {
    return _officialWebSession(target);
  }

  @visibleForTesting
  bool timetableResponseNeedsSessionRebuildForTesting({
    required Uri uri,
    required String body,
  }) {
    return _timetableResponseNeedsSessionRebuild(
      _Response(uri: uri, statusCode: HttpStatus.ok, body: body),
    );
  }

  @visibleForTesting
  bool portalAccountResponseIsAuthenticatedForTesting(
    Map<String, dynamic> response,
  ) {
    return _portalAccountResponseIsAuthenticated(response);
  }

  @visibleForTesting
  Uri? portalAvatarUriForTesting(String avatarPath) {
    return _resolvePortalAvatarUri(avatarPath);
  }

  @visibleForTesting
  bool hasTargetHostCookieForTesting(OfficialWebTarget target) {
    return _hasTargetHostCookie(target);
  }

  @visibleForTesting
  Uri? examTimetableUriForTesting({
    required Uri pageUri,
    required String body,
  }) {
    return _findExamTimetableUri(pageUri: pageUri, body: body);
  }

  @visibleForTesting
  BnbuMisException? examTimetableIndexErrorForTesting(int statusCode) {
    return _examTimetableIndexError(statusCode);
  }

  @visibleForTesting
  BnbuMisException? examTimetablePageErrorForTesting(int statusCode) {
    return _examTimetablePageError(statusCode);
  }

  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) {
    return _serializeSessionOperation(() async {
      await _ensureMisSession(username: username, password: password);
      var didReauthenticate = false;
      late _Response response;
      while (true) {
        try {
          response = await _requestTimetable();
        } on BnbuMisException catch (error) {
          if (didReauthenticate || !error.requiresReauthentication) {
            rethrow;
          }
          didReauthenticate = true;
          _misSessionReady = false;
          await _ensureMisSession(
            username: username,
            password: password,
            forceRebuild: true,
          );
          continue;
        }
        if (!_timetableResponseNeedsSessionRebuild(response)) {
          break;
        }
        if (didReauthenticate) {
          _misSessionReady = false;
          throw BnbuMisException(
            'MIS 登录状态已失效，请稍后重试。',
            isRetryable: true,
            requiresReauthentication: true,
          );
        }
        didReauthenticate = true;
        _misSessionReady = false;
        await _ensureMisSession(
          username: username,
          password: password,
          forceRebuild: true,
        );
      }
      final data = TimetableData.fromHtml(response.body);
      if (data.courses.isEmpty) {
        throw BnbuMisException('MIS 课表解析失败，请稍后重试。', isRetryable: true);
      }
      return data;
    });
  }

  Future<ExamTimetableData> fetchExamTimetable({
    required String username,
    required String password,
  }) {
    return _serializeSessionOperation(() async {
      for (var attempt = 0; attempt < 2; attempt++) {
        await _ensureMisSession(
          username: username,
          password: password,
          forceRebuild: attempt > 0,
        );
        final indexResponse = await _request(
          'GET',
          Uri.parse('$_misBaseUrl/mis/usr/index.do'),
          headers: <String, String>{
            HttpHeaders.acceptHeader: _htmlAcceptHeader,
          },
        );
        if (_timetableResponseNeedsSessionRebuild(indexResponse)) {
          _misSessionReady = false;
          if (attempt == 0) continue;
          throw BnbuMisException(
            'MIS 登录状态已失效，请稍后重试。',
            isRetryable: true,
            requiresReauthentication: true,
          );
        }
        final indexError = _examTimetableIndexError(indexResponse.statusCode);
        if (indexError != null) {
          if (indexError.requiresReauthentication) {
            _misSessionReady = false;
            if (attempt == 0) continue;
          }
          throw indexError;
        }
        final examUri = _findExamTimetableUri(
          pageUri: indexResponse.uri,
          body: indexResponse.body,
        );
        if (examUri == null) {
          return const ExamTimetableData.unavailable();
        }
        final response = await _request(
          'GET',
          examUri,
          headers: <String, String>{
            'X-Requested-With': 'XMLHttpRequest',
            HttpHeaders.refererHeader: indexResponse.uri.toString(),
            HttpHeaders.acceptHeader: _htmlAcceptHeader,
          },
        );
        if (_timetableResponseNeedsSessionRebuild(response)) {
          _misSessionReady = false;
          if (attempt == 0) continue;
          throw BnbuMisException(
            'MIS 考试时间登录状态已失效，请稍后重试。',
            isRetryable: true,
            requiresReauthentication: true,
          );
        }
        final responseError = _examTimetablePageError(response.statusCode);
        if (responseError != null) {
          if (responseError.requiresReauthentication) {
            _misSessionReady = false;
            if (attempt == 0) continue;
          }
          throw responseError;
        }
        return ExamTimetableData.fromHtml(response.body);
      }
      return const ExamTimetableData.unavailable();
    });
  }

  static const String _gradeReportPath =
      '/mis/student/ssm/gradepublish/webReport.do';

  /// Read all academic years through the existing MIS session and serial queue.
  /// Both report requests share one authentication recovery budget.
  Future<GradeReport> fetchGradeReport({
    required String username,
    required String password,
  }) {
    return _serializeSessionOperation(() async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await _ensureMisSession(
            username: username,
            password: password,
            forceRebuild: attempt > 0,
          );
          var page = await _requestGradeReport();
          _validateGradeReportResponse(page);
          final scope = MisAcademicYearOption.allAcademicYearsIn(page.body);
          if (scope == null || scope.value.isEmpty) {
            throw BnbuMisException('成绩报告缺少完整学年范围。');
          }
          if (!scope.selected) {
            page = await _requestGradeReportScope(scope.value);
            _validateGradeReportResponse(page);
          }
          final report = GradeReport.fromHtml(page.body);
          if (!report.isAllAcademicYears ||
              report.availability == GradeReportAvailability.unavailable) {
            throw BnbuMisException('成绩报告范围或格式无效，请稍后重试。');
          }
          return report;
        } on BnbuMisException catch (error) {
          if (!error.requiresReauthentication) rethrow;
          _invalidateTargetSession(OfficialWebTarget.mis);
          if (attempt > 0) rethrow;
        }
      }
      throw BnbuMisException('成绩报告登录状态已失效。', requiresReauthentication: true);
    });
  }

  void _validateGradeReportResponse(_Response response) {
    // A 5xx login-looking body is a service failure, never permission to log in.
    final statusError = _gradeReportStatusError(response.statusCode);
    if (statusError != null) throw statusError;
    if (_timetableResponseNeedsSessionRebuild(response)) {
      throw BnbuMisException(
        '成绩报告登录状态已失效，请稍后重试。',
        requiresReauthentication: true,
      );
    }
  }

  /// 学校报表入口只需已建立的 MIS 会话；实测无需先访问 MIS 首页或任何菜单页。
  Future<_Response> _requestGradeReport() {
    return _request(
      'GET',
      Uri.parse('$_misBaseUrl$_gradeReportPath'),
      headers: <String, String>{
        HttpHeaders.acceptHeader: _htmlAcceptHeader,
        HttpHeaders.refererHeader: '$_misBaseUrl/mis/usr/index.do',
      },
      maxResponseBytes: _gradeReportMaxResponseBytes,
    );
  }

  /// 成绩范围选择器是 `method="post" action=""` 的普通表单；实测 GET 传同名参数会被忽略。
  /// 目标固定使用本客户端配置的 MIS 精确来源，绝不复用可能被跳转的响应地址。
  Future<_Response> _requestGradeReportScope(String scopeValue) {
    return _request(
      'POST',
      Uri.parse('$_misBaseUrl$_gradeReportPath'),
      headers: <String, String>{
        HttpHeaders.acceptHeader: _htmlAcceptHeader,
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
        HttpHeaders.refererHeader: '$_misBaseUrl$_gradeReportPath',
      },
      body: Uri(
        queryParameters: <String, String>{'id': scopeValue, 'button': 'Go'},
      ).query,
      maxResponseBytes: _gradeReportMaxResponseBytes,
    );
  }

  static const int _gradeReportMaxResponseBytes = 2 * 1024 * 1024;

  BnbuMisException? _gradeReportStatusError(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return null;
    }
    return BnbuMisException(
      '成绩报告请求失败（HTTP $statusCode）。',
      isRetryable: _isRetryableStatus(statusCode),
      requiresReauthentication:
          statusCode == HttpStatus.unauthorized ||
          statusCode == HttpStatus.forbidden,
    );
  }

  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) {
    return _serializeSessionOperation(() async {
      await _ensurePortalSession(username: username, password: password);

      final response = await _requestJson(
        'GET',
        Uri.parse(
          '$_portalBaseUrl/api/hrm/login/getAccountList'
          '?__random__=${DateTime.now().millisecondsSinceEpoch}',
        ),
        headers: <String, String>{
          HttpHeaders.acceptHeader: '*/*',
          'X-Requested-With': 'XMLHttpRequest',
          HttpHeaders.refererHeader: '$_portalBaseUrl/wui/index.html',
        },
      );
      if (_stringOf(response['status']) != '1') {
        throw BnbuMisException('统一门户用户信息加载失败。');
      }

      var profile = PortalAccountProfile.fromPortalJson(
        _mapOf(response['data']),
      );
      if (profile.isEmpty) {
        throw BnbuMisException('未获取到统一门户账号信息。');
      }
      if (profile.portalUserId != null) {
        try {
          final resourceCardUri =
              Uri.parse(
                '$_portalBaseUrl/api/hrm/resource/getResourceCard',
              ).replace(
                queryParameters: <String, String>{
                  'operation': 'getResourceBaseView',
                  'id': profile.portalUserId.toString(),
                  'cmd': 'getResourceBaseData',
                },
              );
          final resourceCard = await _requestJson(
            'GET',
            resourceCardUri,
            headers: <String, String>{
              HttpHeaders.acceptHeader: '*/*',
              'X-Requested-With': 'XMLHttpRequest',
              HttpHeaders.refererHeader: '$_portalBaseUrl/wui/index.html',
            },
          );
          profile = profile.mergeResourceCardJson(resourceCard);
        } on BnbuMisException {
          // 详细人事卡片不可用时仍保留已验证的门户基础资料。
        } on FormatException {
          // 学校接口临时返回非 JSON 内容时不影响姓名、学院和照片加载。
        } on TimeoutException {
          // 可选资料请求超时不影响门户基础资料加载。
        } on SocketException {
          // 可选资料请求断网不影响门户基础资料加载。
        } on HttpException {
          // 可选资料请求失败不影响门户基础资料加载。
        }
      }
      return profile;
    });
  }

  Future<Uint8List?> fetchPortalAccountAvatar({
    required String username,
    required String password,
    required String avatarPath,
  }) {
    return _serializeSessionOperation(() async {
      final avatarUri = _resolvePortalAvatarUri(avatarPath);
      if (avatarUri == null) {
        return null;
      }
      await _ensurePortalSession(username: username, password: password);
      final response = await _request(
        'GET',
        avatarUri,
        headers: <String, String>{
          HttpHeaders.acceptHeader: 'image/avif,image/webp,image/*,*/*;q=0.8',
          HttpHeaders.refererHeader: '$_portalBaseUrl/wui/index.html',
        },
        maxResponseBytes: 5 * 1024 * 1024,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BnbuMisException(
          '统一门户学生照片加载失败（HTTP ${response.statusCode}）。',
          isRetryable: _isRetryableStatus(response.statusCode),
        );
      }
      final contentType = response.contentType?.toLowerCase() ?? '';
      if (!contentType.startsWith('image/') || response.bodyBytes.isEmpty) {
        throw BnbuMisException('统一门户学生照片格式异常。');
      }
      return Uint8List.fromList(response.bodyBytes);
    });
  }

  Uri? _resolvePortalAvatarUri(String avatarPath) {
    final value = avatarPath.trim();
    if (value.isEmpty || value.length > 2048) {
      return null;
    }
    final baseUri = Uri.parse(_portalBaseUrl);
    var candidate = Uri.tryParse(value);
    if (candidate == null || candidate.userInfo.isNotEmpty) {
      return null;
    }
    candidate = candidate.hasScheme
        ? candidate
        : value.startsWith('//')
        ? Uri.tryParse('https:$value')
        : baseUri.resolveUri(candidate);
    if (candidate == null) {
      return null;
    }
    if (candidate.scheme.toLowerCase() == 'http' &&
        candidate.host.toLowerCase() == baseUri.host.toLowerCase() &&
        (!candidate.hasPort || candidate.port == 80)) {
      candidate = candidate.replace(scheme: 'https', port: 443);
    }
    return _hasSameOrigin(candidate, baseUri) ? candidate : null;
  }

  Future<WebSessionSnapshot> prepareOfficialWebSession({
    required OfficialWebTarget target,
    required String username,
    required String password,
  }) {
    return _serializeSessionOperation(() async {
      if (target == OfficialWebTarget.mis) {
        await _ensureMisSession(username: username, password: password);
      } else {
        await _ensurePortalSession(username: username, password: password);
      }
      var snapshot = _officialWebSession(target);
      if (!_hasTargetHostCookie(target)) {
        if (target == OfficialWebTarget.mis) {
          await _ensureMisSession(
            username: username,
            password: password,
            forceRebuild: true,
          );
        } else {
          await _ensurePortalSession(
            username: username,
            password: password,
            forceRebuild: true,
          );
        }
        snapshot = _officialWebSession(target);
      }
      if (snapshot.cookies.isEmpty || !_hasTargetHostCookie(target)) {
        throw BnbuMisException('学校系统会话建立失败，请稍后重试。', isRetryable: true);
      }
      return snapshot;
    });
  }

  Future<T> _serializeSessionOperation<T>(Future<T> Function() operation) {
    final expectedGeneration = _sessionGeneration;
    final result = _operationQueue.then<T>((_) async {
      if (_isDisposed || expectedGeneration != _sessionGeneration) {
        throw BnbuMisException('登录状态已变化，请重新打开页面。');
      }
      _activeSessionGeneration = expectedGeneration;
      try {
        final value = await operation();
        _ensureActiveSession();
        return value;
      } finally {
        if (_activeSessionGeneration == expectedGeneration) {
          _activeSessionGeneration = null;
        }
      }
    });
    _operationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _ensureActiveSession() {
    final expectedGeneration = _activeSessionGeneration;
    if (_isDisposed ||
        expectedGeneration == null ||
        expectedGeneration != _sessionGeneration) {
      throw BnbuMisException('登录状态已变化，请重新打开页面。');
    }
  }

  void _resetSessionState() {
    _cookieJar.clear();
    _sessionUsername = null;
    _misSessionReady = false;
    _portalSessionReady = false;
  }

  Future<void> _ensureMisSession({
    required String username,
    required String password,
    bool forceRebuild = false,
  }) async {
    final hasSameSsoSession = _sessionUsername == username;
    if (!forceRebuild &&
        hasSameSsoSession &&
        _misSessionReady &&
        await _hasValidMisSession()) {
      return;
    }
    if (forceRebuild) {
      _invalidateTargetSession(OfficialWebTarget.mis);
    } else {
      _misSessionReady = false;
    }

    if (hasSameSsoSession) {
      try {
        await _openMisSession(username: username);
        return;
      } on BnbuMisException catch (error) {
        if (!error.requiresReauthentication) {
          rethrow;
        }
      }
    }

    await _loginToSso(username: username, password: password);
    await _openMisSession(username: username);
  }

  Future<void> _ensurePortalSession({
    required String username,
    required String password,
    bool forceRebuild = false,
  }) async {
    final hasSameSsoSession = _sessionUsername == username;
    if (!forceRebuild &&
        hasSameSsoSession &&
        _portalSessionReady &&
        await _hasValidPortalSession()) {
      return;
    }
    if (forceRebuild) {
      _invalidateTargetSession(OfficialWebTarget.portal);
    } else {
      _portalSessionReady = false;
    }

    if (hasSameSsoSession) {
      try {
        await _openPortalSession(username: username);
        return;
      } on BnbuMisException catch (error) {
        if (!error.requiresReauthentication) {
          rethrow;
        }
      }
    }

    await _loginToSso(username: username, password: password);
    await _openPortalSession(username: username);
  }

  Future<void> _loginToSso({
    required String username,
    required String password,
  }) async {
    _ensureActiveSession();
    _resetSessionState();
    await _request(
      'GET',
      Uri.parse('$_ssoBaseUrl/'),
      headers: <String, String>{HttpHeaders.acceptHeader: _htmlAcceptHeader},
    );

    final publicKey = await _loadSm2PublicKey();
    final loginResponse = await _requestJson(
      'POST',
      Uri.parse('$_ssoBaseUrl/auth/pwd/tencent/login'),
      body: <String, dynamic>{
        'userName': username,
        'password': _encryptPassword(password, publicKey),
        'randomP': _randomPayload(),
      },
    );
    final loginData = _mapOf(loginResponse['data']);
    final message = _stringOf(loginData['message']);
    if (_boolOf(loginData['success']) != true) {
      if (_boolOf(loginData['needVerifyCode']) == true) {
        throw BnbuMisException(
          message.isNotEmpty ? message : '统一认证要求验证码，当前版本暂不支持。',
        );
      }
      throw BnbuMisException(message.isNotEmpty ? message : '统一认证登录失败。');
    }
    _sessionUsername = username;
  }

  Future<_Response> _requestTimetable() async {
    final response = await _request(
      'GET',
      Uri.parse('$_misBaseUrl/mis/student/tts/timetable_min.do'),
      headers: <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
        HttpHeaders.refererHeader: '$_misBaseUrl/mis/usr/index.do',
        HttpHeaders.acceptHeader: '*/*',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BnbuMisException(
        '课表请求失败（HTTP ${response.statusCode}）。',
        isRetryable: _isRetryableStatus(response.statusCode),
        requiresReauthentication:
            response.statusCode == HttpStatus.unauthorized ||
            response.statusCode == HttpStatus.forbidden,
      );
    }
    return response;
  }

  Uri? _findExamTimetableUri({required Uri pageUri, required String body}) {
    final document = html_parser.parse(body);
    final marker = RegExp(
      r'exam(?:ination)?\s*time\s*table|exam\s*schedule|考试时间表|考试安排',
      caseSensitive: false,
    );
    for (final element in document.querySelectorAll('a, area, form')) {
      final searchable = <String>[
        element.text,
        element.attributes['title'] ?? '',
        element.attributes['aria-label'] ?? '',
        element.attributes['name'] ?? '',
        element.attributes['id'] ?? '',
      ].join(' ');
      if (!marker.hasMatch(searchable)) continue;
      for (final attribute in <String>['href', 'action', 'onclick']) {
        final raw = element.attributes[attribute];
        if (raw == null || raw.trim().isEmpty) continue;
        for (final candidate in _uriCandidates(raw)) {
          final resolved = pageUri.resolve(candidate);
          if (_isAllowedExamTimetableUri(resolved)) return resolved;
        }
      }
    }
    return null;
  }

  Iterable<String> _uriCandidates(String raw) sync* {
    final normalized = raw.trim();
    if (!normalized.toLowerCase().startsWith('javascript:') &&
        !normalized.startsWith('#') &&
        RegExp(r'^[A-Za-z0-9_./?&=%:-]+$').hasMatch(normalized)) {
      yield normalized;
    }
    for (final match in RegExp(r'''['"]([^'"]+)['"]''').allMatches(raw)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) yield value;
    }
  }

  bool _isAllowedExamTimetableUri(Uri uri) {
    return _looksLikeMisUri(uri) &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.userInfo.isEmpty &&
        uri.path.startsWith('/mis/');
  }

  BnbuMisException? _examTimetableIndexError(int statusCode) {
    return _examTimetableStatusError(statusCode, target: '入口');
  }

  BnbuMisException? _examTimetablePageError(int statusCode) {
    return _examTimetableStatusError(statusCode, target: '页面');
  }

  BnbuMisException? _examTimetableStatusError(
    int statusCode, {
    required String target,
  }) {
    if (statusCode >= 200 && statusCode < 300) {
      return null;
    }
    final requiresReauthentication =
        statusCode == HttpStatus.unauthorized ||
        statusCode == HttpStatus.forbidden;
    return BnbuMisException(
      '考试时间$target请求失败（HTTP $statusCode）。',
      isRetryable: _isRetryableStatus(statusCode),
      requiresReauthentication: requiresReauthentication,
    );
  }

  bool _timetableResponseNeedsSessionRebuild(_Response response) {
    if (!_looksLikeMisUri(response.uri)) {
      return true;
    }
    final body = response.body.toLowerCase();
    return body.contains('/auth/pwd/tencent/login') ||
        body.contains('统一身份认证') ||
        body.contains('统一认证登录') ||
        body.contains('请先登录') ||
        body.contains('登录超时') ||
        body.contains('会话已过期') ||
        body.contains('session expired') ||
        body.contains('session timeout') ||
        (body.contains('<form') &&
            body.contains('password') &&
            body.contains('login'));
  }

  Future<String> _loadSm2PublicKey() async {
    final response = await _requestJson(
      'GET',
      Uri.parse('$_ssoBaseUrl/auth/flow/login/getSm2PubK'),
    );
    final key = _stringOf(response['data']);
    if (key.isEmpty) {
      throw BnbuMisException('未获取到统一认证公钥。', isRetryable: true);
    }
    return key;
  }

  void _checkSessionResponseStatus(_Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw BnbuMisException(
      '学校会话检查失败（HTTP ${response.statusCode}）。',
      isRetryable: _isRetryableStatus(response.statusCode),
      requiresReauthentication:
          response.statusCode == 401 || response.statusCode == 403,
    );
  }

  bool _isAuthenticationResponse(_Response response) {
    final body = response.body.toLowerCase();
    return (body.contains('<form') &&
            body.contains('password') &&
            body.contains('login')) ||
        body.contains('统一认证登录') ||
        body.contains('请先登录') ||
        body.contains('会话已过期') ||
        body.contains('session expired') ||
        (_hasSameOrigin(response.uri, Uri.parse(_ssoBaseUrl)) &&
            (response.uri.path == '/' ||
                response.uri.path.startsWith('/login')));
  }

  Future<void> _openMisSession({required String username}) async {
    final launchCandidates = <Uri>[
      Uri.parse(
        '$_ssoBaseUrl/auth/sso/login/$_misServiceId'
        '?service=$_misServiceId&accountName=${Uri.encodeQueryComponent(username)}',
      ),
      Uri.parse(_misLaunchUrl),
    ];

    _Response? launch;
    var requiresAuthentication = false;
    for (final candidate in launchCandidates) {
      final response = await _request(
        'GET',
        candidate,
        headers: <String, String>{HttpHeaders.acceptHeader: _htmlAcceptHeader},
      );
      _checkSessionResponseStatus(response);
      final settled = await _followHtmlRedirectPages(response);
      _checkSessionResponseStatus(settled);
      requiresAuthentication |= _isAuthenticationResponse(settled);
      if (_looksLikeMisUri(settled.uri)) {
        launch = settled;
        break;
      }
    }

    if (launch == null) {
      throw BnbuMisException(
        '未能打开 MIS 单点登录入口。',
        isRetryable: true,
        requiresReauthentication: requiresAuthentication,
      );
    }

    final indexResponse = await _request(
      'GET',
      Uri.parse('$_misBaseUrl/mis/usr/index.do'),
      headers: <String, String>{HttpHeaders.acceptHeader: _htmlAcceptHeader},
    );
    _checkSessionResponseStatus(indexResponse);
    if (!_looksLikeMisUri(indexResponse.uri) ||
        !indexResponse.body.contains('BNBU MIS') ||
        _timetableResponseNeedsSessionRebuild(indexResponse)) {
      throw BnbuMisException(
        'MIS 会话建立失败，请重新登录后重试。',
        isRetryable: true,
        requiresReauthentication:
            requiresAuthentication || _isAuthenticationResponse(indexResponse),
      );
    }
    _misSessionReady = true;
  }

  Future<void> _openPortalSession({required String username}) async {
    final launchCandidates = <Uri>[
      Uri.parse(
        '$_ssoBaseUrl/auth/sso/login/$_portalServiceId'
        '?service=$_portalServiceId&accountName=${Uri.encodeQueryComponent(username)}',
      ),
      Uri.parse(_portalLaunchUrl),
      Uri.parse(_portalBaseUrl),
      Uri.parse('$_portalBaseUrl/wui/index.html'),
    ];

    _Response? launch;
    var requiresAuthentication = false;
    for (final candidate in launchCandidates) {
      final response = await _request(
        'GET',
        candidate,
        headers: <String, String>{HttpHeaders.acceptHeader: _htmlAcceptHeader},
      );
      _checkSessionResponseStatus(response);
      final settled = await _followHtmlRedirectPages(response);
      _checkSessionResponseStatus(settled);
      requiresAuthentication |= _isAuthenticationResponse(settled);
      if (_looksLikePortalUri(settled.uri)) {
        launch = settled;
        break;
      }
    }

    if (launch == null) {
      throw BnbuMisException(
        '未能打开统一门户入口。',
        isRetryable: true,
        requiresReauthentication: requiresAuthentication,
      );
    }

    final indexResponse = await _request(
      'GET',
      Uri.parse('$_portalBaseUrl/wui/index.html'),
      headers: <String, String>{HttpHeaders.acceptHeader: _htmlAcceptHeader},
    );
    _checkSessionResponseStatus(indexResponse);
    if (indexResponse.statusCode < 200 ||
        indexResponse.statusCode >= 300 ||
        !_looksLikePortalUri(indexResponse.uri) ||
        _isAuthenticationResponse(indexResponse)) {
      throw BnbuMisException(
        '统一门户会话建立失败，请重新登录后重试。',
        isRetryable: true,
        requiresReauthentication:
            requiresAuthentication || _isAuthenticationResponse(indexResponse),
      );
    }
    final accountResponse = await _requestPortalAccountList();
    if (!_portalAccountResponseIsAuthenticated(accountResponse)) {
      throw BnbuMisException(
        '统一门户会话建立失败，请重新登录后重试。',
        isRetryable: true,
        requiresReauthentication:
            requiresAuthentication || _isAuthenticationResponse(indexResponse),
      );
    }
    _portalSessionReady = true;
  }

  Future<bool> _hasValidMisSession() async {
    try {
      final response = await _request(
        'GET',
        Uri.parse('$_misBaseUrl/mis/usr/index.do'),
        headers: <String, String>{HttpHeaders.acceptHeader: _htmlAcceptHeader},
      );
      _checkSessionResponseStatus(response);
      final valid =
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          _looksLikeMisUri(response.uri) &&
          response.body.contains('BNBU MIS') &&
          !_timetableResponseNeedsSessionRebuild(response);
      _misSessionReady = valid;
      return valid;
    } on BnbuMisException catch (error) {
      if (!error.requiresReauthentication) rethrow;
      _misSessionReady = false;
      return false;
    }
  }

  Future<bool> _hasValidPortalSession() async {
    try {
      final response = await _requestPortalAccountList();
      final valid = _portalAccountResponseIsAuthenticated(response);
      _portalSessionReady = valid;
      return valid;
    } on BnbuMisException catch (error) {
      if (!error.requiresReauthentication) rethrow;
      _portalSessionReady = false;
      return false;
    }
  }

  Future<Map<String, dynamic>> _requestPortalAccountList() {
    return _requestJson(
      'GET',
      Uri.parse(
        '$_portalBaseUrl/api/hrm/login/getAccountList'
        '?__random__=${DateTime.now().millisecondsSinceEpoch}',
      ),
      headers: <String, String>{
        HttpHeaders.acceptHeader: '*/*',
        'X-Requested-With': 'XMLHttpRequest',
        HttpHeaders.refererHeader: '$_portalBaseUrl/wui/index.html',
      },
    );
  }

  bool _portalAccountResponseIsAuthenticated(Map<String, dynamic> response) {
    return _stringOf(response['status']) == '1' &&
        _mapOf(response['data']).isNotEmpty;
  }

  bool _hasTargetHostCookie(OfficialWebTarget target) {
    final targetUri = _targetEntryUri(target);
    final targetHost = targetUri.host.toLowerCase();
    final now = DateTime.now();
    return _cookieJar.any(
      (cookie) =>
          !cookie.isExpired(now) &&
          cookie.domain == targetHost &&
          cookie.matches(targetUri),
    );
  }

  WebSessionSnapshot _officialWebSession(OfficialWebTarget target) {
    final baseUrl = target == OfficialWebTarget.mis
        ? _misBaseUrl
        : _portalBaseUrl;
    final targetUri = Uri.parse(baseUrl).resolve(
      target == OfficialWebTarget.mis ? '/mis/usr/index.do' : '/wui/index.html',
    );
    final now = DateTime.now();
    final targetHost = targetUri.host.toLowerCase();
    final selectedCookies = <(String, String), _StoredCookie>{};
    for (final cookie in _cookieJar) {
      if (cookie.isExpired(now) || !cookie.matches(targetUri)) {
        continue;
      }
      final key = (cookie.name, cookie.path);
      final existing = selectedCookies[key];
      if (existing == null ||
          _exportCookiePriority(cookie, targetHost) >
              _exportCookiePriority(existing, targetHost)) {
        selectedCookies[key] = cookie;
      }
    }
    final cookies = selectedCookies.values
        .map(
          (cookie) => WebSessionCookie(
            name: cookie.name,
            value: cookie.value,
            domain: targetHost,
            path: cookie.path,
            hostOnly: true,
            secure: cookie.secure,
            httpOnly: cookie.httpOnly,
            sameSite: cookie.sameSite?.name.toLowerCase(),
            expiresAt: cookie.expires,
          ),
        )
        .toList(growable: false);
    return WebSessionSnapshot(
      baseUrl: baseUrl,
      cookies: cookies,
      allowedOrigins: <String>[baseUrl],
      useEphemeralSession: true,
    );
  }

  int _exportCookiePriority(_StoredCookie cookie, String targetHost) {
    if (cookie.domain == targetHost) {
      return cookie.hostOnly ? 1 << 30 : 1 << 29;
    }
    return cookie.domain.length;
  }

  String _encryptPassword(String password, String rawPublicKey) {
    final encrypted = SM2.encrypt(password, '04$rawPublicKey');
    return encrypted.startsWith('04') ? encrypted : '04$encrypted';
  }

  String _randomPayload() {
    final left = (_random.nextDouble()).toStringAsFixed(5);
    final right = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$left$right';
  }

  bool _looksLikeMisUri(Uri uri) {
    return _hasSameOrigin(uri, Uri.parse(_misBaseUrl));
  }

  bool _looksLikePortalUri(Uri uri) {
    return _hasSameOrigin(uri, Uri.parse(_portalBaseUrl));
  }

  Future<_Response> _followHtmlRedirectPages(
    _Response response, {
    int limit = 6,
  }) async {
    var current = response;
    for (var index = 0; index < limit; index++) {
      if (_looksLikeMisUri(current.uri) || _looksLikePortalUri(current.uri)) {
        return current;
      }
      final redirectPath = _extractHtmlRedirectPath(current.body);
      if (redirectPath == null) {
        return current;
      }
      current = await _request(
        'GET',
        current.uri.resolve(redirectPath),
        headers: <String, String>{HttpHeaders.acceptHeader: _htmlAcceptHeader},
      );
    }
    return current;
  }

  String? _extractHtmlRedirectPath(String body) {
    if (body.isEmpty) {
      return null;
    }

    final patterns = <RegExp>[
      RegExp(r'''redirect\(['"]([^'"]+)['"]\)''', caseSensitive: false),
      RegExp(
        r'''location\.replace\(['"]([^'"]+)['"]\)''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<meta[^>]+http-equiv=['"]refresh['"][^>]+url=([^'"> ]+)''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      final path = match?.group(1)?.trim();
      if (path != null && path.isNotEmpty) {
        return path;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      method,
      uri,
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json',
        if (headers != null) ...headers,
      },
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BnbuMisException(
        '请求失败（HTTP ${response.statusCode}）。',
        isRetryable: _isRetryableStatus(response.statusCode),
        requiresReauthentication:
            response.statusCode == 401 || response.statusCode == 403,
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw BnbuMisException('接口返回格式异常。', isRetryable: true);
    }
    if (decoded is! Map<String, dynamic>) {
      throw BnbuMisException('接口返回格式异常。', isRetryable: true);
    }
    return decoded;
  }

  Future<_Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    int redirectLimit = 8,
    int? maxResponseBytes,
  }) async {
    var currentMethod = method.toUpperCase();
    var currentUri = uri;
    var currentBody = body;
    var currentHeaders = Map<String, String>.from(
      headers ?? const <String, String>{},
    );

    for (
      var redirectCount = 0;
      redirectCount <= redirectLimit;
      redirectCount++
    ) {
      _ensureActiveSession();
      if (!_isTrustedRequestUri(currentUri)) {
        throw BnbuMisException('请求跳转到了不受信任的学校地址。');
      }
      late final HttpClientRequest request;
      try {
        request = await _httpClient
            .openUrl(currentMethod, currentUri)
            .timeout(_requestTimeout);
      } on TlsException catch (error) {
        final failure = classifySchoolTlsFailure(error);
        throw BnbuMisException(
          failure.message,
          isRetryable: failure.isRetryable,
        );
      }
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'zh-CN,zh;q=0.9,en;q=0.8',
      );
      currentHeaders.forEach(request.headers.set);
      for (final cookie in _matchingCookies(currentUri)) {
        request.cookies.add(cookie.toCookie());
      }
      if (currentBody != null) {
        request.write(currentBody);
      }

      late final HttpClientResponse response;
      try {
        response = await request.close().timeout(_requestTimeout);
      } on TlsException catch (error) {
        final failure = classifySchoolTlsFailure(error);
        throw BnbuMisException(
          failure.message,
          isRetryable: failure.isRetryable,
        );
      }
      _ensureActiveSession();
      _storeCookies(response.cookies, currentUri);
      final bytes = await response
          .fold<List<int>>(<int>[], (buffer, chunk) {
            if (maxResponseBytes != null &&
                buffer.length + chunk.length > maxResponseBytes) {
              throw BnbuMisException('学校接口返回的数据超过安全大小限制。');
            }
            buffer.addAll(chunk);
            return buffer;
          })
          .timeout(_requestTimeout);
      _ensureActiveSession();

      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          return _Response(
            uri: currentUri,
            statusCode: response.statusCode,
            body: utf8.decode(bytes, allowMalformed: true),
            bodyBytes: bytes,
            contentType: response.headers.contentType?.mimeType,
          );
        }
        final targetUri = currentUri.resolve(location);
        final redirect = _prepareRedirect(
          method: currentMethod,
          currentUri: currentUri,
          targetUri: targetUri,
          statusCode: response.statusCode,
          body: currentBody,
          headers: currentHeaders,
        );
        currentUri = targetUri;
        currentMethod = redirect.method;
        currentBody = redirect.body;
        currentHeaders = redirect.headers;
        continue;
      }

      return _Response(
        uri: currentUri,
        statusCode: response.statusCode,
        body: utf8.decode(bytes, allowMalformed: true),
        bodyBytes: bytes,
        contentType: response.headers.contentType?.mimeType,
      );
    }

    throw BnbuMisException('请求跳转过多，请稍后重试。');
  }

  _RedirectRequest _prepareRedirect({
    required String method,
    required Uri currentUri,
    required Uri targetUri,
    required int statusCode,
    required String? body,
    required Map<String, String> headers,
  }) {
    if (!_isTrustedRequestUri(targetUri)) {
      throw BnbuMisException('请求跳转到了不受信任的学校地址。');
    }

    var nextMethod = method.toUpperCase();
    var nextBody = body;
    final nextHeaders = Map<String, String>.from(headers);
    if (statusCode == HttpStatus.seeOther ||
        ((statusCode == HttpStatus.movedPermanently ||
                statusCode == HttpStatus.found) &&
            nextMethod == 'POST')) {
      nextMethod = 'GET';
      nextBody = null;
    }

    if (!_hasSameOrigin(currentUri, targetUri)) {
      if (nextBody != null && nextBody.isNotEmpty) {
        throw BnbuMisException('为保护登录信息，已拒绝跨来源转发请求内容。');
      }
      _removeSensitiveRedirectHeaders(nextHeaders);
    }
    if (nextBody == null || nextBody.isEmpty) {
      _removeHeader(nextHeaders, HttpHeaders.contentTypeHeader);
      _removeHeader(nextHeaders, HttpHeaders.contentLengthHeader);
    }

    return _RedirectRequest(
      method: nextMethod,
      body: nextBody,
      headers: nextHeaders,
    );
  }

  void _removeSensitiveRedirectHeaders(Map<String, String> headers) {
    for (final name in <String>[
      HttpHeaders.authorizationHeader,
      HttpHeaders.cookieHeader,
      HttpHeaders.proxyAuthorizationHeader,
      HttpHeaders.refererHeader,
      HttpHeaders.wwwAuthenticateHeader,
      'origin',
    ]) {
      _removeHeader(headers, name);
    }
  }

  void _removeHeader(Map<String, String> headers, String name) {
    final normalizedName = name.toLowerCase();
    headers.removeWhere((key, _) => key.toLowerCase() == normalizedName);
  }

  bool _isTrustedRequestUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    return _trustedCookieOrigins.any((origin) => _hasSameOrigin(uri, origin));
  }

  bool _hasSameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        _effectivePort(left) == _effectivePort(right);
  }

  bool _isTrustedCookieOrigin(Uri uri) {
    return _trustedCookieOrigins.any((origin) => _hasSameOrigin(uri, origin));
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return switch (uri.scheme.toLowerCase()) {
      'http' => 80,
      'https' => 443,
      _ => -1,
    };
  }

  Iterable<_StoredCookie> _matchingCookies(Uri uri) sync* {
    if (!_isTrustedCookieOrigin(uri)) {
      return;
    }

    final now = DateTime.now();
    for (final cookie in _cookieJar) {
      if (cookie.isExpired(now)) {
        continue;
      }
      if (cookie.matches(uri)) {
        yield cookie;
      }
    }
  }

  void _storeCookies(List<Cookie> cookies, Uri uri) {
    if (!_isTrustedCookieOrigin(uri)) {
      return;
    }

    final now = DateTime.now();
    for (final cookie in cookies) {
      final stored = _StoredCookie.fromCookie(
        cookie,
        uri,
        trustedDomain: _cookieDomain,
        now: now,
      );
      if (stored == null) {
        continue;
      }
      _cookieJar.removeWhere(
        (existing) =>
            existing.name == stored.name &&
            existing.domain == stored.domain &&
            existing.path == stored.path,
      );
      if (!stored.isExpired(now)) {
        _cookieJar.add(stored);
      }
    }
  }

  bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == HttpStatus.requestTimeout ||
        statusCode == HttpStatus.tooManyRequests ||
        statusCode >= HttpStatus.internalServerError;
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  String _stringOf(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  bool? _boolOf(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return null;
  }
}

class _Response {
  const _Response({
    required this.uri,
    required this.statusCode,
    required this.body,
    this.bodyBytes = const <int>[],
    this.contentType,
  });

  final Uri uri;
  final int statusCode;
  final String body;
  final List<int> bodyBytes;
  final String? contentType;
}

class _RedirectRequest {
  const _RedirectRequest({
    required this.method,
    required this.body,
    required this.headers,
  });

  final String method;
  final String? body;
  final Map<String, String> headers;
}

class _StoredCookie {
  const _StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    required this.httpOnly,
    this.sameSite,
    this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final bool httpOnly;
  final SameSite? sameSite;
  final DateTime? expires;

  static _StoredCookie? fromCookie(
    Cookie cookie,
    Uri uri, {
    required String trustedDomain,
    required DateTime now,
  }) {
    final originHost = uri.host.trim().toLowerCase();
    final normalizedTrustedDomain = trustedDomain.trim().toLowerCase();
    if (originHost.isEmpty) {
      return null;
    }
    final rawDomain = (cookie.domain ?? '').trim().toLowerCase();
    final normalizedDomain = rawDomain.replaceFirst(RegExp(r'^\.+'), '');
    final hostOnly = normalizedDomain.isEmpty;
    final domain = hostOnly ? originHost : normalizedDomain;
    final isWithinTrustedDomain =
        normalizedTrustedDomain.isNotEmpty &&
        _domainMatches(originHost, normalizedTrustedDomain) &&
        _domainMatches(domain, normalizedTrustedDomain);
    if (domain.isEmpty ||
        domain.endsWith('.') ||
        (!hostOnly &&
            (!_domainMatches(originHost, domain) ||
                (domain != originHost && !isWithinTrustedDomain)))) {
      return null;
    }

    final rawPath = (cookie.path ?? '').trim();
    final path = rawPath.startsWith('/') ? rawPath : _defaultPath(uri);
    final maxAge = cookie.maxAge;
    final expires = maxAge == null
        ? cookie.expires
        : now.add(Duration(seconds: maxAge));
    return _StoredCookie(
      name: cookie.name,
      value: cookie.value,
      domain: domain,
      path: path,
      hostOnly: hostOnly,
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
      sameSite: cookie.sameSite,
      expires: expires,
    );
  }

  Cookie toCookie() {
    final cookie = Cookie(name, value);
    cookie.domain = domain;
    cookie.path = path;
    cookie.secure = secure;
    cookie.httpOnly = httpOnly;
    cookie.sameSite = sameSite;
    if (expires != null) {
      cookie.expires = expires;
    }
    return cookie;
  }

  bool matchesHost(Uri uri) {
    final host = uri.host.toLowerCase();
    final domainMatch = hostOnly
        ? host == domain
        : _domainMatches(host, domain);
    final secureMatch = !secure || uri.scheme.toLowerCase() == 'https';
    return domainMatch && secureMatch;
  }

  bool matches(Uri uri) {
    return matchesHost(uri) && _pathMatches(uri.path, path);
  }

  bool isExpired(DateTime now) {
    return expires != null && !expires!.isAfter(now);
  }

  static bool _domainMatches(String host, String domain) {
    return host == domain || host.endsWith('.$domain');
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    final normalizedRequestPath = requestPath.isEmpty ? '/' : requestPath;
    if (normalizedRequestPath == cookiePath) {
      return true;
    }
    if (!normalizedRequestPath.startsWith(cookiePath)) {
      return false;
    }
    return cookiePath.endsWith('/') ||
        normalizedRequestPath.length > cookiePath.length &&
            normalizedRequestPath[cookiePath.length] == '/';
  }

  static String _defaultPath(Uri origin) {
    final requestPath = origin.path;
    if (!requestPath.startsWith('/') || requestPath == '/') {
      return '/';
    }
    final lastSlash = requestPath.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : requestPath.substring(0, lastSlash);
  }
}
