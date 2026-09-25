import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/ispace_tls_trust.dart';
import '../models/course_content.dart';
import '../models/course_grade_data.dart';
import '../models/course_summary.dart';
import '../models/moodle_runtime_profile.dart';
import '../models/moodle_module_access.dart';
import '../models/recent_course.dart';
import '../models/quiz_attempt_data.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../models/web_session_snapshot.dart';
import 'network_retry.dart';
import 'moodle_feedback_content.dart';

class AuthSession {
  AuthSession({
    required this.token,
    required this.fullName,
    required this.userId,
    required this.runtimeProfile,
  });

  final String token;
  final String fullName;
  final int userId;
  final MoodleRuntimeProfile runtimeProfile;
}

class ISpaceIdentity {
  const ISpaceIdentity({required this.name, this.avatar});
  final String name;
  final Uint8List? avatar;
}

class MoodleApiException implements Exception {
  MoodleApiException(this.message, {this.isRetryable = false});

  final String message;
  final bool isRetryable;

  @override
  String toString() => 'MoodleApiException($message)';
}

class MoodleAuthenticationException extends MoodleApiException {
  MoodleAuthenticationException(super.message);
}

class MoodleFeatureUnavailableException extends MoodleApiException {
  MoodleFeatureUnavailableException(this.functionName)
    : super('学校当前未向此账号开放所需的 iSpace 能力。');

  final String functionName;
}

class MoodleApiClient {
  MoodleApiClient({
    http.Client? client,
    HttpClient? webHttpClient,
    String? baseUrl,
    String? cookieDomain,
  }) : _httpClient =
           client ??
           createAppHttpClient(
             securityContext: createIsSpaceSecurityContext(
               baseUrl ?? AppConfig.ispaceBaseUrl,
             ),
           ),
       _webHttpClient =
           webHttpClient ??
           createAppDartHttpClient(
             securityContext: createIsSpaceSecurityContext(
               baseUrl ?? AppConfig.ispaceBaseUrl,
             ),
           ),
       baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.ispaceBaseUrl,
         settingName: 'ISPACE_BASE_URL',
       ),
       cookieDomain = AppConfig.normalizedCookieDomain(
         cookieDomain ?? AppConfig.ispaceCookieDomain,
       ) {
    _webHttpClient.connectionTimeout = _requestTimeout;
    _webHttpClient.idleTimeout = const Duration(seconds: 15);
    _webHttpClient.maxConnectionsPerHost = 6;
    _webHttpClient.userAgent =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';
  }

  final http.Client _httpClient;
  final String baseUrl;
  final String cookieDomain;
  final HttpClient _webHttpClient;
  final List<_StoredWebCookie> _webCookies = <_StoredWebCookie>[];
  Future<void> _webSessionOperationQueue = Future<void>.value();
  int _webSessionGeneration = 0;
  int? _activeWebSessionGeneration;
  String? _webSessionUser;
  bool _isDisposed = false;
  String? _runtimeProfileToken;
  MoodleRuntimeProfile? _runtimeProfile;

  static const int _timelinePageSize = 50;
  static const int _maxTimelinePages = 50;
  static const Duration _requestTimeout = Duration(seconds: 20);

  void clearWebSession() {
    _webSessionGeneration++;
    _webCookies.clear();
    _webSessionUser = null;
  }

  void clearRuntimeProfile() {
    _runtimeProfileToken = null;
    _runtimeProfile = null;
  }

  @visibleForTesting
  void cacheRuntimeProfileForTesting({
    required String token,
    required MoodleRuntimeProfile profile,
  }) {
    _runtimeProfileToken = token;
    _runtimeProfile = profile;
  }

  @visibleForTesting
  int get webSessionGenerationForTesting => _webSessionGeneration;

  @visibleForTesting
  String decoratePluginFileUrlWithTokenForTesting(
    String url, {
    required String token,
  }) {
    return _decoratePluginFileUrlWithToken(url, token: token);
  }

  @visibleForTesting
  void cacheWebCookieForTesting(
    Cookie cookie,
    Uri origin, {
    int? expectedGeneration,
  }) {
    _cacheWebCookies(
      <Cookie>[cookie],
      origin,
      expectedGeneration: expectedGeneration ?? _webSessionGeneration,
    );
  }

  @visibleForTesting
  String webCookieHeaderForTesting(Uri target) {
    return _buildCookieHeader(target);
  }

  @visibleForTesting
  List<WebSessionCookie> webSessionCookiesForTesting(Uri target) {
    return _webSessionCookiesFor(target);
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    clearRuntimeProfile();
    clearWebSession();
    _httpClient.close();
    _webHttpClient.close(force: true);
  }

  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    clearRuntimeProfile();
    final uri = Uri.parse('$baseUrl/login/token.php');
    final response = await _postForm(uri, <String, String>{
      'username': username,
      'password': password,
      'service': 'moodle_mobile_app',
    }, operation: '登录');

    if (response.statusCode != 200) {
      throw MoodleApiException(
        '登录接口失败（HTTP ${response.statusCode}）。',
        isRetryable: _isRetryableHttpStatus(response.statusCode),
      );
    }

    final json = _decodeJsonMap(response.body);
    final token = (json['token'] as String?)?.trim();
    if (token == null || token.isEmpty) {
      final errorCode = (json['errorcode'] as String?)?.trim().toLowerCase();
      final message = _extractWsError(json, fallback: '未获取到 token，登录失败。');
      if (errorCode == 'invalidlogin') {
        throw MoodleAuthenticationException(message);
      }
      if (errorCode == 'requirecorrectaccess') {
        throw MoodleApiException('iSpace 登录地址与学校当前站点不一致，请更新客户端后重试。');
      }
      throw MoodleApiException(message);
    }

    final siteInfoRaw = await _callWebService(
      token: token,
      functionName: 'core_webservice_get_site_info',
      parameters: const {},
    );
    final siteInfo = _asJsonMap(siteInfoRaw);
    final runtimeProfile = MoodleRuntimeProfile.fromSiteInfo(siteInfo);
    _runtimeProfileToken = token;
    _runtimeProfile = runtimeProfile;

    return AuthSession(
      token: token,
      fullName: (siteInfo['fullname'] as String?)?.trim().isNotEmpty == true
          ? (siteInfo['fullname'] as String).trim()
          : username,
      userId: _toInt(siteInfo['userid']),
      runtimeProfile: runtimeProfile,
    );
  }

  Future<ISpaceIdentity> fetchIdentity({required String token}) async {
    final data = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'core_webservice_get_site_info',
        parameters: const {},
      ),
    );
    final name = (data['fullname'] as String? ?? '').trim();
    final uri = Uri.tryParse(data['userpictureurl'] as String? ?? '');
    Uint8List? avatar;
    final origin = Uri.parse(baseUrl);
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host == origin.host &&
        uri.port == origin.port &&
        uri.userInfo.isEmpty &&
        uri.path.contains('/pluginfile.php') &&
        !uri.queryParameters.containsKey('token')) {
      final request = http.Request(
        'GET',
        Uri.parse(
          _decoratePluginFileUrlWithToken(uri.toString(), token: token),
        ),
      )..followRedirects = false;
      final response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200 &&
          (response.headers['content-type'] ?? '').startsWith('image/')) {
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 12),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 768 * 1024) throw MoodleApiException('头像图片过大');
        }
        avatar = Uint8List.fromList(bytes);
      } else {
        await response.stream.drain<void>();
      }
    }
    return ISpaceIdentity(name: name, avatar: avatar);
  }

  Future<void> updateOwnPicture({
    required String token,
    required Uint8List jpeg,
  }) async {
    if (jpeg.isEmpty || jpeg.length > 768 * 1024) {
      throw MoodleApiException('头像图片过大');
    }
    final profile = _runtimeProfile;
    if (_runtimeProfileToken != token ||
        profile == null ||
        !profile.uploadFiles ||
        !profile.supportsFunctions(const [
          'core_user_update_picture',
          'core_files_get_unused_draft_itemid',
        ])) {
      throw MoodleFeatureUnavailableException('core_user_update_picture');
    }
    final draft = await _createDraftItemId(token: token);
    await _uploadDraftFile(
      token: token,
      draftItemId: draft,
      file: UploadFilePayload(fileName: 'avatar.jpg', bytes: jpeg),
    );
    final result = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'core_user_update_picture',
        parameters: {'draftitemid': draft, 'delete': 0, 'userid': 0},
      ),
    );
    if (!_toBool(result['success'])) throw MoodleApiException('iSpace未接受头像更新');
    if ((result['warnings'] as List? ?? const []).isNotEmpty) {
      throw MoodleApiException('头像更新未被iSpace完整接受');
    }
  }

  Future<List<TimelineItem>> fetchAllTimeline({required String token}) async {
    final items = <TimelineItem>[];
    final seenIds = <int>{};
    var afterEventId = 0;

    for (var page = 0; page < _maxTimelinePages; page++) {
      final response = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'core_calendar_get_action_events_by_timesort',
          parameters: <String, dynamic>{
            'timesortfrom': 0,
            'timesortto': 4102444800, // UTC 2100-01-01
            'limitnum': _timelinePageSize,
            'aftereventid': afterEventId,
          },
        ),
      );

      final events = _extractEvents(response);
      if (events.isEmpty) {
        break;
      }

      for (final event in events) {
        final item = TimelineItem.fromJson(event);
        if (item.id <= 0 || !seenIds.add(item.id)) {
          continue;
        }
        items.add(item);
      }

      final canLoadMore = _toBool(response['canloadmore']);
      final nextCursor = _extractNextCursor(response, events, afterEventId);
      if (!canLoadMore && events.length < _timelinePageSize) {
        break;
      }
      if (nextCursor <= afterEventId) {
        break;
      }
      afterEventId = nextCursor;
    }

    items.sort((a, b) => _timeSortValue(a).compareTo(_timeSortValue(b)));
    return items;
  }

  Future<WebSessionSnapshot> prepareWebSession({
    required String username,
    required String password,
  }) {
    final expectedGeneration = _webSessionGeneration;
    final result = _webSessionOperationQueue.then<WebSessionSnapshot>((
      _,
    ) async {
      _ensureActiveWebSession(expectedGeneration);
      _activeWebSessionGeneration = expectedGeneration;
      try {
        await _ensureWebSession(username: username, password: password);
        _ensureActiveWebSession(expectedGeneration);
        final baseUri = Uri.parse(baseUrl);
        return WebSessionSnapshot(
          baseUrl: baseUrl,
          cookies: _webSessionCookiesFor(baseUri),
        );
      } finally {
        if (_activeWebSessionGeneration == expectedGeneration) {
          _activeWebSessionGeneration = null;
        }
      }
    });
    _webSessionOperationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  List<WebSessionCookie> _webSessionCookiesFor(Uri uri) {
    final snapshotHost = uri.host.toLowerCase();
    final selectedCookies = <(String, String), _StoredWebCookie>{};
    for (final cookie in _matchingWebCookies(uri)) {
      final key = (cookie.name, cookie.path);
      final existing = selectedCookies[key];
      if (existing == null ||
          _webCookieExportPriority(cookie, snapshotHost) >
              _webCookieExportPriority(existing, snapshotHost)) {
        selectedCookies[key] = cookie;
      }
    }
    return selectedCookies.values
        .map(
          (cookie) => WebSessionCookie(
            name: cookie.name,
            value: cookie.value,
            domain: snapshotHost,
            path: cookie.path,
            hostOnly: cookie.hostOnly || cookie.domain != snapshotHost,
            secure: cookie.secure,
            httpOnly: cookie.httpOnly,
            sameSite: cookie.sameSite?.name.toLowerCase(),
            expiresAt: cookie.expires,
          ),
        )
        .toList(growable: false);
  }

  int _webCookieExportPriority(_StoredWebCookie cookie, String targetHost) {
    if (cookie.domain == targetHost) {
      return cookie.hostOnly ? 1 << 30 : 1 << 29;
    }
    return cookie.domain.length;
  }

  Future<List<CourseSummary>> fetchMyCourses({
    required String token,
    required int userId,
  }) async {
    final response = await _callWebService(
      token: token,
      functionName: 'core_enrol_get_users_courses',
      parameters: <String, dynamic>{'userid': userId},
    );

    if (response case {'courses': List<dynamic> courses}) {
      return courses
          .whereType<Map>()
          .map((item) => CourseSummary.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    if (response is List) {
      return response
          .whereType<Map>()
          .map((item) => CourseSummary.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    return const [];
  }

  Future<List<RecentCourse>> fetchRecentCourses({
    required String token,
    required int userId,
    int limit = 10,
  }) async {
    final response = await _callWebService(
      token: token,
      functionName: 'core_course_get_recent_courses',
      parameters: <String, dynamic>{'userid': userId, 'limit': limit},
    );

    if (response is List) {
      return response
          .whereType<Map>()
          .map((item) => RecentCourse.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    if (response case {'courses': List<dynamic> courses}) {
      return courses
          .whereType<Map>()
          .map((item) => RecentCourse.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    return const [];
  }

  Future<List<CourseContentSection>> fetchCourseContents({
    required String token,
    required int courseId,
  }) async {
    final response = await _callWebService(
      token: token,
      functionName: 'core_course_get_contents',
      parameters: <String, dynamic>{'courseid': courseId},
    );

    if (response is! List) {
      return const [];
    }

    final sections = response
        .whereType<Map>()
        .map(
          (item) => CourseContentSection.fromJson(item.cast<String, dynamic>()),
        )
        .toList();
    sections.sort((a, b) => a.sectionNum.compareTo(b.sectionNum));
    return sections;
  }

  /// Reads only the selected course's Page HTML for local attachment discovery.
  /// The caller intersects the result with fresh visible/downloadable modules.
  Future<Map<int, String>> fetchCoursewarePageHtml({
    required String token,
    required int courseId,
    required Set<int> allowedInstances,
  }) async {
    if (allowedInstances.isEmpty) return const {};
    if (_runtimeProfileToken != token ||
        _runtimeProfile?.downloadFiles != true) {
      throw MoodleApiException('学校当前未开放文件读取。');
    }
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_page_get_pages_by_courses',
        parameters: {
          'courseids': [courseId],
        },
      ),
    );
    final pages = response['pages'];
    if (pages is! List) throw MoodleApiException('学校未返回页面正文。');
    final result = <int, String>{};
    var totalBytes = 0;
    for (final page in pages.whereType<Map>()) {
      final id = _toInt(page['id']);
      if (_toInt(page['course']) != courseId ||
          !allowedInstances.contains(id) ||
          page['content'] is! String) {
        continue;
      }
      final html = page['content'] as String;
      final bytes = utf8.encode(html).length;
      totalBytes += bytes;
      if (bytes > 1024 * 1024 || totalBytes > 4 * 1024 * 1024) {
        throw MoodleApiException('课程页面内容超过安全读取上限。');
      }
      result[id] = html;
    }
    return result;
  }

  Future<List<String>> fetchCourseTeacherNames({
    required String token,
    required int courseId,
  }) async {
    final response = await _callWebService(
      token: token,
      functionName: 'core_course_get_courses_by_field',
      parameters: <String, dynamic>{
        'field': 'id',
        'value': courseId.toString(),
      },
    );
    if (response is! Map) {
      return const [];
    }
    final courses = response['courses'];
    if (courses is! List || courses.isEmpty || courses.first is! Map) {
      return const [];
    }
    final contacts = (courses.first as Map)['contacts'];
    if (contacts is! List) {
      return const [];
    }
    final teachers = <String>[];
    for (final contact in contacts.whereType<Map>()) {
      final name = _pickString(contact.cast<String, dynamic>(), const [
        'fullname',
        'displayname',
      ]);
      if (name.isNotEmpty && !teachers.contains(name)) {
        teachers.add(name);
      }
      if (teachers.length == 8) {
        break;
      }
    }
    return List.unmodifiable(teachers);
  }

  Future<CourseGradeSnapshot> fetchCourseGrades({
    required String token,
    required int courseId,
    required int userId,
  }) async {
    if (courseId <= 0 || userId <= 0) {
      throw MoodleApiException('成绩查询缺少有效的课程或用户标识。');
    }
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'gradereport_user_get_grade_items',
        parameters: <String, dynamic>{
          'courseid': courseId,
          'userid': userId,
          'groupid': 0,
        },
      ),
    );
    return CourseGradeSnapshot.fromJson(
      response,
      courseId: courseId,
      userId: userId,
    );
  }

  Future<MoodleModuleAccessSnapshot> fetchModuleAccess({
    required String token,
    required String moduleType,
    required int instanceId,
    required int courseId,
  }) async {
    if (instanceId <= 0 || courseId <= 0) {
      throw MoodleApiException('活动访问检查缺少有效的模块标识。');
    }
    switch (moduleType.trim().toLowerCase()) {
      case 'choice':
        final response = _asJsonMap(
          await _callWebService(
            token: token,
            functionName: 'mod_choice_get_choice_options',
            parameters: <String, dynamic>{'choiceid': instanceId},
          ),
        );
        final validOptions = _jsonMapList(response['options'])
            .map(
              (option) => MoodleChoiceOption(
                id: _toInt(option['id']),
                label: _boundedQuizText(
                  _stripHtml(_pickString(option, const ['text'])),
                  500,
                ),
                selected: _toBool(option['checked']),
                disabled: _toBool(option['disabled']),
                maxAnswers: _toInt(option['maxanswers']).clamp(0, 1000000),
              ),
            )
            .where((option) => option.id > 0 && option.label.isNotEmpty)
            .toList(growable: false);
        final options = validOptions.take(40).toList(growable: false);
        final choicesResponse = _asJsonMap(
          await _callWebService(
            token: token,
            functionName: 'mod_choice_get_choices_by_courses',
            parameters: <String, dynamic>{
              'courseids': <int>[courseId],
            },
          ),
        );
        final choiceMatches = _jsonMapList(
          choicesResponse['choices'],
        ).where((choice) => _toInt(choice['id']) == instanceId).toList();
        final choiceConfig = choiceMatches.length == 1
            ? choiceMatches.single
            : const <String, dynamic>{};
        final allowMultiple = _toBool(choiceConfig['allowmultiple']);
        final allowUpdate = _toBool(choiceConfig['allowupdate']);
        final warnings = [
          ..._warningMessages(response),
          ..._warningMessages(choicesResponse),
          if (choiceConfig.isEmpty) '未能确认该 Choice 的活动配置。',
          if (options.any((option) => option.selected) && !allowUpdate)
            '该 Choice 已提交且不允许更新。',
        ];
        return MoodleModuleAccessSnapshot(
          moduleType: 'choice',
          canRead: true,
          canWrite:
              warnings.isEmpty && options.any((option) => !option.disabled),
          statusMessage: warnings.join(' '),
          choiceOptions: List.unmodifiable(options),
          choiceOptionsTruncated: validOptions.length > options.length,
          choiceAllowMultiple: allowMultiple,
          choiceAllowUpdate: allowUpdate,
        );
      case 'feedback':
        final response = _asJsonMap(
          await _callWebService(
            token: token,
            functionName: 'mod_feedback_get_feedback_access_information',
            parameters: <String, dynamic>{
              'feedbackid': instanceId,
              'courseid': courseId,
            },
          ),
        );
        final isOpen = _toBool(response['isopen']);
        final isEmpty = _toBool(response['isempty']);
        final submitted = _toBool(response['isalreadysubmitted']);
        final canWrite =
            _toBool(response['cancomplete']) &&
            _toBool(response['cansubmit']) &&
            isOpen &&
            !isEmpty &&
            !submitted;
        final labels = <String>[
          if (!isOpen) '该 Feedback 当前未开放。',
          if (isEmpty) '该 Feedback 当前没有可回答项目。',
          if (submitted) '该 Feedback 已提交。',
          if (_toBool(response['isanonymous'])) '该 Feedback 使用匿名提交。',
          ..._warningMessages(response),
        ];
        return MoodleModuleAccessSnapshot(
          moduleType: 'feedback',
          canRead: true,
          canWrite: canWrite,
          statusMessage: labels.join(' '),
        );
      case 'lesson':
        final response = _asJsonMap(
          await _callWebService(
            token: token,
            functionName: 'mod_lesson_get_lesson_access_information',
            parameters: <String, dynamic>{'lessonid': instanceId},
          ),
        );
        final reasons = _jsonMapList(response['preventaccessreasons'])
            .map(
              (reason) => _boundedQuizText(
                _stripHtml(_pickString(reason, const ['message', 'reason'])),
                500,
              ),
            )
            .where((reason) => reason.isNotEmpty)
            .take(8)
            .toList(growable: false);
        return MoodleModuleAccessSnapshot(
          moduleType: 'lesson',
          canRead: true,
          canWrite: reasons.isEmpty && _toInt(response['firstpageid']) > 0,
          statusMessage: [...reasons, ..._warningMessages(response)].join(' '),
        );
      default:
        throw MoodleApiException('该活动类型没有受支持的访问检查。');
    }
  }

  Future<void> updateManualCompletion({
    required String token,
    required int courseId,
    required int courseModuleId,
    required int userId,
    required bool completed,
  }) async {
    if (courseId <= 0 || courseModuleId <= 0 || userId <= 0) {
      throw MoodleApiException('完成状态更新缺少有效的课程模块标识。');
    }
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName:
            'core_completion_update_activity_completion_status_manually',
        parameters: <String, dynamic>{
          'cmid': courseModuleId,
          'completed': completed ? 1 : 0,
        },
      ),
    );
    if (!_toBool(response['status']) || _warningMessages(response).isNotEmpty) {
      throw MoodleApiException('iSpace 未接受完成状态更新。');
    }
    final verification = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'core_completion_get_activities_completion_status',
        parameters: <String, dynamic>{'courseid': courseId, 'userid': userId},
      ),
    );
    final matches = _jsonMapList(
      verification['statuses'],
    ).where((status) => _toInt(status['cmid']) == courseModuleId);
    if (matches.length != 1 ||
        _toInt(matches.single['tracking']) != 1 ||
        (_toInt(matches.single['state']) != 0) != completed) {
      throw MoodleApiException('iSpace 已返回，但完成状态尚未通过回读确认。');
    }
  }

  Future<MoodleModuleAccessSnapshot> submitChoice({
    required String token,
    required int courseId,
    required int choiceId,
    required List<int> optionIds,
  }) async {
    final uniqueIds = optionIds.toSet();
    if (uniqueIds.isEmpty || uniqueIds.length != optionIds.length) {
      throw MoodleApiException('Choice 选项标识无效。');
    }
    final access = await fetchModuleAccess(
      token: token,
      moduleType: 'choice',
      instanceId: choiceId,
      courseId: courseId,
    );
    final allowedIds = {
      for (final option in access.choiceOptions)
        if (!option.disabled) option.id,
    };
    if (!access.canWrite || !allowedIds.containsAll(uniqueIds)) {
      throw MoodleApiException('该 Choice 当前不允许提交所选选项。');
    }
    if (!access.choiceAllowMultiple && uniqueIds.length != 1) {
      throw MoodleApiException('该 Choice 当前只允许选择一个选项。');
    }
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_choice_submit_choice_response',
        parameters: <String, dynamic>{
          'choiceid': choiceId,
          'responses': optionIds,
        },
      ),
    );
    if (_warningMessages(response).isNotEmpty) {
      throw MoodleApiException('iSpace 未接受 Choice 提交。');
    }
    final returnedIds = _jsonMapList(
      response['answers'],
    ).map((answer) => _toInt(answer['optionid'])).where((id) => id > 0).toSet();
    if (!returnedIds.containsAll(uniqueIds)) {
      throw MoodleApiException('Choice 提交已返回，但选项尚未通过结果确认。');
    }
    final verified = await fetchModuleAccess(
      token: token,
      moduleType: 'choice',
      instanceId: choiceId,
      courseId: courseId,
    );
    final selectedIds = {
      for (final option in verified.choiceOptions)
        if (option.selected) option.id,
    };
    if (!selectedIds.containsAll(uniqueIds)) {
      throw MoodleApiException('Choice 提交已返回，但选项尚未通过回读确认。');
    }
    return verified;
  }

  List<String> _warningMessages(Map<String, dynamic> response) {
    return _jsonMapList(response['warnings'])
        .map(
          (warning) => _boundedQuizText(
            _stripHtml(_pickString(warning, const ['message'])),
            500,
          ),
        )
        .where((message) => message.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  Future<TimelineDetailData> fetchTimelineDetail({
    required String token,
    required TimelineItem item,
  }) async {
    if (_looksLikeAssignment(item)) {
      return _fetchAssignmentDetail(token: token, item: item);
    }
    if (_looksLikeForum(item)) {
      return _fetchForumDetail(token: token, item: item);
    }
    if (_looksLikeMediaSite(item)) {
      return _fetchMediaSiteDetail(token: token, item: item);
    }
    return TimelineDetailData(
      item: item,
      type: TimelineDetailType.generic,
      hints: const ['该事件类型暂未完全原生化，后续会继续搬运。'],
    );
  }

  Future<TimelineDetailData> _fetchAssignmentDetail({
    required String token,
    required TimelineItem item,
  }) async {
    final resolvedAssignId = await _resolveAssignId(token: token, item: item);
    if (resolvedAssignId <= 0) {
      return TimelineDetailData(
        item: item,
        type: TimelineDetailType.assignment,
        hints: const ['未能识别作业实例 ID，暂无法获取提交状态。'],
      );
    }

    try {
      final assignmentSummary = await _fetchAssignmentSummary(
        token: token,
        courseId: item.courseId,
        assignmentId: resolvedAssignId,
      );
      final submissionStatus = await _fetchAssignmentSubmissionStatus(
        token: token,
        assignmentId: resolvedAssignId,
      );
      final introRaw = _pickString(assignmentSummary, const [
        'intro',
        'activity',
      ]);
      final introFiles = _extractAssignmentIntroFiles(
        assignmentSummary,
        token: token,
      );

      final submission = _asJsonMapOrEmpty(submissionStatus['submission']);
      final lastAttempt = _asJsonMapOrEmpty(submissionStatus['lastattempt']);
      final submissionDrafts = _toBool(assignmentSummary['submissiondrafts']);
      final teamSubmission = _toBool(assignmentSummary['teamsubmission']);
      final preventSubmissionNotInGroup = _toBool(
        assignmentSummary['preventsubmissionnotingroup'],
      );
      final timeLimitSeconds = _toInt(assignmentSummary['timelimit']);
      final submissionsEnabled = _toBool(lastAttempt['submissionsenabled']);
      final submissionLocked = _toBool(lastAttempt['locked']);
      final canSubmit = _toBool(lastAttempt['cansubmit']);
      final safeNativeSubmission =
          !teamSubmission &&
          !preventSubmissionNotInGroup &&
          timeLimitSeconds <= 0;

      return TimelineDetailData(
        item: item,
        type: TimelineDetailType.assignment,
        assignmentId: resolvedAssignId,
        assignmentName: _pickString(assignmentSummary, const [
          'name',
        ], item.title),
        assignmentIntro: _stripHtml(introRaw),
        assignmentIntroHtml: _normalizeAssignmentIntroHtml(
          introRaw,
          introFiles: introFiles,
          token: token,
        ),
        assignmentIntroFiles: introFiles,
        openDateEpoch: _toInt(assignmentSummary['allowsubmissionsfromdate']),
        dueDateEpoch: _toInt(assignmentSummary['duedate']),
        cutoffDateEpoch: _toInt(assignmentSummary['cutoffdate']),
        gradingDueDateEpoch: _toInt(assignmentSummary['gradingduedate']),
        submissionStatus: _pickString(submission, const [
          'status',
          'submissionstatus',
        ]),
        gradingStatus: _pickString(lastAttempt, const ['gradingstatus']),
        canEditSubmission:
            safeNativeSubmission &&
            submissionsEnabled &&
            !submissionLocked &&
            (_toBool(lastAttempt['canedit']) ||
                _toBool(lastAttempt['caneditowner'])),
        feedbackSummary: _extractFeedback(submission),
        supportsFileSubmission:
            _assignmentConfigEnabled(assignmentSummary, 'file', 'enabled') ||
            _submissionPluginExists(submission, 'file'),
        supportsOnlineTextSubmission:
            _assignmentConfigEnabled(
              assignmentSummary,
              'onlinetext',
              'enabled',
            ) ||
            _submissionPluginExists(submission, 'onlinetext'),
        maxFileSubmissions: _assignmentConfigInt(
          assignmentSummary,
          'file',
          'maxfilesubmissions',
        ),
        maxSubmissionSizeBytes: _assignmentConfigInt(
          assignmentSummary,
          'file',
          'maxsubmissionsizebytes',
        ),
        submissionFiles: _extractSubmissionFiles(submission),
        submissionDrafts: submissionDrafts,
        requiresSubmissionStatement: _toBool(
          assignmentSummary['requiresubmissionstatement'],
        ),
        submissionStatement: _stripHtml(
          _pickString(assignmentSummary, const ['submissionstatement']),
        ),
        teamSubmission: teamSubmission,
        requireAllTeamMembersSubmit: _toBool(
          assignmentSummary['requireallteammemberssubmit'],
        ),
        preventSubmissionNotInGroup: preventSubmissionNotInGroup,
        timeLimitSeconds: timeLimitSeconds,
        submissionsEnabled: submissionsEnabled,
        submissionLocked: submissionLocked,
        canFinalizeSubmission:
            submissionDrafts &&
            safeNativeSubmission &&
            submissionsEnabled &&
            !submissionLocked &&
            canSubmit &&
            _pickString(submission, const ['status']) == 'draft',
        hints: const [],
      );
    } on MoodleApiException catch (error) {
      if (_isAssignRecordError(error.message)) {
        return TimelineDetailData(
          item: item,
          type: TimelineDetailType.assignment,
          assignmentId: 0,
          hints: const ['该 Timeline 事件的作业记录在服务端不可用，已切换为安全降级展示。'],
        );
      }
      rethrow;
    }
  }

  Future<TimelineDetailData> _fetchForumDetail({
    required String token,
    required TimelineItem item,
  }) async {
    final forumId = await _resolveModuleInstanceId(
      token: token,
      item: item,
      moduleName: 'forum',
    );
    if (forumId <= 0) {
      return TimelineDetailData(
        item: item,
        type: TimelineDetailType.forum,
        hints: const ['未能识别论坛实例 ID，已切换为基础展示。'],
      );
    }

    String forumName = item.title;
    String forumDescription = '';
    if (item.courseId > 0) {
      try {
        final forumsRaw = await _callWebService(
          token: token,
          functionName: 'mod_forum_get_forums_by_courses',
          parameters: <String, dynamic>{
            'courseids': <int>[item.courseId],
          },
        );
        final forums = _extractForums(forumsRaw);
        for (final forum in forums) {
          if (_toInt(forum['id']) == forumId) {
            forumName = _pickString(forum, const ['name'], forumName);
            forumDescription = _stripHtml(
              _pickString(forum, const ['intro', 'description']),
            );
            break;
          }
        }
      } on MoodleApiException {
        forumName = item.title;
        forumDescription = '';
      }
    }

    var canStartDiscussion = false;
    try {
      final accessInfo = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_forum_get_forum_access_information',
          parameters: <String, dynamic>{'forumid': forumId},
        ),
      );
      canStartDiscussion = _toBool(accessInfo['canstartdiscussion']);
    } on MoodleApiException {
      canStartDiscussion = false;
    }

    List<ForumDiscussion> discussions = const [];
    try {
      final usePaginated =
          _runtimeProfile?.supportsFunction(
            'mod_forum_get_forum_discussions_paginated',
          ) ??
          false;
      final discussionResponse = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: usePaginated
              ? 'mod_forum_get_forum_discussions_paginated'
              : 'mod_forum_get_forum_discussions',
          parameters: usePaginated
              ? <String, dynamic>{
                  'forumid': forumId,
                  'sortby': 'timemodified',
                  'sortdirection': 'DESC',
                  'page': 0,
                  'perpage': 10,
                }
              : <String, dynamic>{
                  'forumid': forumId,
                  'sortorder': -1,
                  'page': 0,
                  'perpage': 10,
                  'groupid': 0,
                },
        ),
      );
      discussions = _extractForumDiscussions(discussionResponse['discussions']);
    } on MoodleApiException {
      discussions = const [];
    }

    return TimelineDetailData(
      item: item,
      type: TimelineDetailType.forum,
      forumId: forumId,
      forumName: forumName,
      forumDescription: forumDescription,
      forumDiscussions: discussions,
      canStartDiscussion: canStartDiscussion,
      hints: discussions.isEmpty ? const ['当前没有可见讨论，或课程暂未发布讨论帖。'] : const [],
    );
  }

  Future<TimelineDetailData> _fetchMediaSiteDetail({
    required String token,
    required TimelineItem item,
  }) async {
    final mediasiteId = await _resolveModuleInstanceId(
      token: token,
      item: item,
      moduleName: 'mediasite',
    );
    return TimelineDetailData(
      item: item,
      type: TimelineDetailType.mediasite,
      assignmentId: mediasiteId,
      assignmentName: item.title,
      mediasiteLaunchUrl: item.url,
      hints: const ['已支持识别 Mediasite 活动并展示基础信息。', '后续将补齐播放/上传等原生交互能力。'],
    );
  }

  Future<Uint8List> readAssistantFile({
    required String token,
    required String fileUrl,
  }) async {
    if (_runtimeProfileToken != token) throw MoodleApiException('学校会话已变化。');
    final uri = Uri.parse(fileUrl);
    final origin = Uri.parse(baseUrl);
    if (uri.scheme != 'https' ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        !(uri.path.startsWith('/webservice/pluginfile.php/') ||
            uri.path.startsWith('/pluginfile.php/'))) {
      throw MoodleApiException('课程文件来源不在当前学校会话内。');
    }
    if (_runtimeProfile?.supports(MoodleNormalizedCapability.fileDownload) !=
        true) {
      throw MoodleApiException('学校当前未开放文件读取。');
    }
    final target = uri.replace(
      path: uri.path.startsWith('/pluginfile.php/')
          ? '/webservice${uri.path}'
          : uri.path,
      queryParameters: {...uri.queryParameters, 'token': token},
    );
    final request = http.Request('GET', target)..followRedirects = false;
    final response = await _httpClient.send(request).timeout(_requestTimeout);
    if (response.statusCode != 200) throw MoodleApiException('课程文件当前无法读取。');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(_requestTimeout)) {
      bytes.add(chunk);
      if (bytes.length > 64 * 1024 * 1024) {
        throw MoodleApiException('文件超过本机解析内存预算。');
      }
    }
    return bytes.takeBytes();
  }

  Future<String> readAssistantModuleText({
    required String token,
    required int courseId,
    required int instanceId,
    required String moduleType,
    int pageId = 0,
  }) async {
    if (moduleType == 'page') {
      final response = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_page_get_pages_by_courses',
          parameters: {
            'courseids': [courseId],
          },
        ),
      );
      final pages = response['pages'];
      if (pages is! List) throw MoodleApiException('学校未返回页面正文。');
      final page = pages
          .whereType<Map>()
          .where((p) => _toInt(p['id']) == instanceId)
          .toList();
      if (page.length != 1 || page.single['content'] is! String) {
        throw MoodleApiException('页面正文当前不可用。');
      }
      return _stripHtml(page.single['content'] as String);
    }
    if (moduleType == 'feedback') {
      final response = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_feedback_get_items',
          parameters: {'feedbackid': instanceId, 'courseid': courseId},
        ),
      );
      final items = response['items'];
      if (items is! List) throw MoodleApiException('学校未返回问卷题目。');
      final warnings = response['warnings'];
      if (warnings != null && (warnings is! List || warnings.isNotEmpty)) {
        throw MoodleApiException('学校当前未允许完整读取该问卷。');
      }
      return moodleFeedbackItemsText(items);
    }
    if (moduleType == 'lesson') {
      final response = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_lesson_get_pages',
          parameters: {'lessonid': instanceId},
        ),
      );
      final pages = response['pages'];
      if (pages is! List) throw MoodleApiException('学校未返回课程页面。');
      if (pageId == 0) {
        return pages
            .whereType<Map>()
            .map(
              (p) => '${p['id']}: ${_stripHtml((p['title'] ?? '').toString())}',
            )
            .join('\n');
      }
      if (!pages.whereType<Map>().any((p) => _toInt(p['id']) == pageId)) {
        throw MoodleApiException('课程页面引用已失效。');
      }
      final data = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_lesson_get_page_data',
          parameters: {
            'lessonid': instanceId,
            'pageid': pageId,
            'returncontents': 1,
          },
        ),
      );
      final page = data['page'];
      if (page is! Map || page['contents'] is! String) {
        throw MoodleApiException('课程页面正文当前不可用。');
      }
      return _stripHtml(page['contents'] as String);
    }
    throw MoodleApiException('该模块尚无独立正文接口。');
  }

  Future<List<ForumDiscussion>> readAssistantForumPage({
    required String token,
    required int forumId,
    required int page,
  }) async {
    final paginated =
        _runtimeProfile?.supportsFunction(
          'mod_forum_get_forum_discussions_paginated',
        ) ==
        true;
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: paginated
            ? 'mod_forum_get_forum_discussions_paginated'
            : 'mod_forum_get_forum_discussions',
        parameters: {
          'forumid': forumId,
          'page': page,
          'perpage': 10,
          if (paginated) ...{
            'sortby': 'timemodified',
            'sortdirection': 'DESC',
          } else ...{
            'sortorder': -1,
            'groupid': 0,
          },
        },
      ),
    );
    return _extractForumDiscussions(response['discussions']);
  }

  Future<List<ForumPost>> fetchForumDiscussionPosts({
    required String token,
    required int discussionId,
  }) async {
    if (discussionId <= 0) {
      return const [];
    }
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_forum_get_discussion_posts',
        parameters: <String, dynamic>{'discussionid': discussionId},
      ),
    );
    final postsValue = response['posts'];
    if (postsValue is! List) {
      return const [];
    }
    final posts = <ForumPost>[];
    for (final raw in postsValue.whereType<Map>()) {
      final data = raw.cast<String, dynamic>();
      posts.add(
        ForumPost(
          id: _toInt(data['id']),
          subject: _pickString(data, const ['subject'], '无标题'),
          message: _stripHtml(_pickString(data, const ['message'])),
          author: _pickString(data, const ['userfullname'], '未知用户'),
          timeCreatedEpoch: _toInt(
            data['modified'] ?? data['created'] ?? data['timecreated'],
          ),
          parentId: _toInt(data['parent']),
          isPrivateReply: _toBool(data['isprivatereply']),
        ),
      );
    }
    posts.sort((a, b) => a.timeCreatedEpoch.compareTo(b.timeCreatedEpoch));
    return posts;
  }

  Future<QuizAttemptSnapshot> fetchQuizAttempt({
    required String token,
    required TimelineItem item,
    int startPage = 0,
    int pageBudget = 20,
  }) async {
    final quizId = item.instanceId;
    if (quizId <= 0) {
      throw MoodleApiException('该测验缺少有效的 Quiz 实例标识。');
    }
    final quizAccess = await _fetchQuizAccess(token: token, quizId: quizId);
    final attemptsResponse = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_quiz_get_user_attempts',
        parameters: <String, dynamic>{
          'quizid': quizId,
          'status': 'unfinished',
          'includepreviews': 0,
        },
      ),
    );
    final attempts = _jsonMapList(attemptsResponse['attempts']);
    final activeAttempts =
        attempts
            .where(
              (attempt) =>
                  _pickString(attempt, const ['state']) == 'inprogress',
            )
            .toList()
          ..sort(
            (left, right) => _toInt(right['id']).compareTo(_toInt(left['id'])),
          );
    if (activeAttempts.isEmpty) {
      final canStart =
          quizAccess.canAttempt &&
          !quizAccess.isFinished &&
          !quizAccess.requiresPreflight &&
          quizAccess.preventAccessReasons.isEmpty &&
          quizAccess.preventNewAttemptReasons.isEmpty;
      return QuizAttemptSnapshot(
        itemId: item.id.toString(),
        quizId: quizId,
        attemptId: 0,
        state: 'not_started',
        canStart: canStart,
        canSave: false,
        canFinish: false,
        questions: const [],
        accessMessage: _boundedQuizText(
          [
            quizAccess.message,
            _quizMessages(attemptsResponse),
          ].where((value) => value.isNotEmpty).join(' '),
          1000,
        ),
      );
    }

    final attempt = activeAttempts.first;
    final attemptId = _toInt(attempt['id']);
    if (attemptId <= 0) {
      throw MoodleApiException('测验作答记录缺少有效标识。');
    }
    final attemptAccess = quizAccess;
    if (!attemptAccess.canAttempt ||
        attemptAccess.preventAccessReasons.isNotEmpty ||
        attemptAccess.requiresPreflight) {
      return QuizAttemptSnapshot(
        itemId: item.id.toString(),
        quizId: quizId,
        attemptId: attemptId,
        state: _pickString(attempt, const ['state'], 'inprogress'),
        canStart: false,
        canSave: false,
        canFinish: false,
        questions: const [],
        accessMessage: attemptAccess.message,
      );
    }
    final questions = <QuizQuestionData>[];
    final seenSlots = <int>{};
    var page = startPage;
    int? remainingPage;
    var accessMessage = attemptAccess.message;
    var truncated = false;
    for (var pageCount = 0; pageCount < pageBudget; pageCount++) {
      final pageResponse = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_quiz_get_attempt_data',
          parameters: <String, dynamic>{'attemptid': attemptId, 'page': page},
        ),
      );
      accessMessage = [
        accessMessage,
        _quizMessages(pageResponse),
      ].where((value) => value.trim().isNotEmpty).join(' ').trim();
      for (final raw in _jsonMapList(pageResponse['questions'])) {
        final parsed = _parseQuizQuestion(raw);
        if (parsed != null && seenSlots.add(parsed.slot)) {
          questions.add(parsed);
        }
      }
      final nextPage = _toInt(pageResponse['nextpage']);
      if (nextPage < 0 || nextPage == page) break;
      if (pageCount == pageBudget - 1) {
        truncated = true;
        remainingPage = nextPage;
        break;
      }
      page = nextPage;
    }
    questions.sort((left, right) => left.slot.compareTo(right.slot));
    return QuizAttemptSnapshot(
      itemId: item.id.toString(),
      quizId: quizId,
      attemptId: attemptId,
      state: _pickString(attempt, const ['state'], 'inprogress'),
      canStart: false,
      canSave: questions.any((question) => question.fields.isNotEmpty),
      canFinish: true,
      questions: List.unmodifiable(questions),
      accessMessage: accessMessage,
      truncated: truncated,
      nextPage: remainingPage,
    );
  }

  Future<QuizAttemptSnapshot> startQuizAttempt({
    required String token,
    required TimelineItem item,
  }) async {
    final quizId = item.instanceId;
    if (quizId <= 0) {
      throw MoodleApiException('该测验缺少有效的 Quiz 实例标识。');
    }
    final access = await _fetchQuizAccess(token: token, quizId: quizId);
    if (!access.canAttempt ||
        access.isFinished ||
        access.requiresPreflight ||
        access.preventAccessReasons.isNotEmpty ||
        access.preventNewAttemptReasons.isNotEmpty) {
      throw MoodleApiException(
        access.message.isNotEmpty ? access.message : '该测验当前不允许开始作答。',
      );
    }
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_quiz_start_attempt',
        parameters: <String, dynamic>{'quizid': quizId, 'forcenew': 0},
      ),
    );
    final startedAttempt = _asJsonMapOrEmpty(response['attempt']);
    final startedAttemptId = _toInt(startedAttempt['id']);
    if (startedAttemptId <= 0 || _warningMessages(response).isNotEmpty) {
      throw MoodleApiException('Quiz 开始请求未被 iSpace 确认。');
    }
    final verified = await fetchQuizAttempt(token: token, item: item);
    if (!verified.hasActiveAttempt || verified.attemptId != startedAttemptId) {
      throw MoodleApiException('Quiz 开始请求已返回，但尚未通过回读确认。');
    }
    return verified;
  }

  Future<void> saveQuizAttempt({
    required String token,
    required QuizAttemptSnapshot snapshot,
    required List<QuizAnswerDraft> answers,
  }) async {
    final access = await _fetchQuizAccess(
      token: token,
      quizId: snapshot.quizId,
      attemptId: snapshot.attemptId,
    );
    if (!access.canAttempt ||
        access.requiresPreflight ||
        access.preventAccessReasons.isNotEmpty) {
      throw MoodleApiException(
        access.message.isNotEmpty ? access.message : '该测验当前不允许保存答案。',
      );
    }
    final data = _validatedQuizData(snapshot, answers);
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_quiz_save_attempt',
        parameters: <String, dynamic>{
          'attemptid': snapshot.attemptId,
          'data': data,
        },
      ),
    );
    if (!_toBool(response['status']) || _warningMessages(response).isNotEmpty) {
      throw MoodleApiException('Quiz 答案保存请求未被 iSpace 确认。');
    }
  }

  Future<void> finishQuizAttempt({
    required String token,
    required QuizAttemptSnapshot snapshot,
    required List<QuizAnswerDraft> answers,
  }) async {
    final access = await _fetchQuizAccess(
      token: token,
      quizId: snapshot.quizId,
      attemptId: snapshot.attemptId,
    );
    if (!access.canAttempt ||
        access.requiresPreflight ||
        access.preventAccessReasons.isNotEmpty) {
      throw MoodleApiException(
        access.message.isNotEmpty ? access.message : '该测验当前不允许最终提交。',
      );
    }
    final data = _validatedQuizData(snapshot, answers);
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_quiz_process_attempt',
        parameters: <String, dynamic>{
          'attemptid': snapshot.attemptId,
          'data': data,
          'finishattempt': 1,
          'timeup': 0,
        },
      ),
    );
    if (_pickString(response, const ['state']) != 'finished' ||
        _warningMessages(response).isNotEmpty) {
      throw MoodleApiException('Quiz 最终提交未被 iSpace 确认。');
    }
    final attemptsResponse = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_quiz_get_user_attempts',
        parameters: <String, dynamic>{
          'quizid': snapshot.quizId,
          'status': 'all',
          'includepreviews': 0,
        },
      ),
    );
    final verifiedAttempts = _jsonMapList(
      attemptsResponse['attempts'],
    ).where((attempt) => _toInt(attempt['id']) == snapshot.attemptId);
    if (verifiedAttempts.length != 1 ||
        _pickString(verifiedAttempts.single, const ['state']) != 'finished') {
      throw MoodleApiException('Quiz 提交请求已返回，但尚未通过回读确认最终状态。');
    }
    final profile = _runtimeProfile;
    if (profile != null &&
        profile.supports(MoodleNormalizedCapability.quizReview)) {
      final review = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_quiz_get_attempt_review',
          parameters: <String, dynamic>{
            'attemptid': snapshot.attemptId,
            'page': -1,
          },
        ),
      );
      final attempt = review['attempt'];
      final state = attempt is Map
          ? _pickString(attempt.cast<String, dynamic>(), const ['state'])
          : '';
      if (state != 'finished') {
        throw MoodleApiException('Quiz 提交请求已返回，但尚未确认最终交卷状态。');
      }
    }
  }

  Future<_QuizAccessSnapshot> _fetchQuizAccess({
    required String token,
    required int quizId,
    int attemptId = 0,
  }) async {
    final quizAccess = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_quiz_get_quiz_access_information',
        parameters: <String, dynamic>{'quizid': quizId},
      ),
    );
    final attemptAccess = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_quiz_get_attempt_access_information',
        parameters: <String, dynamic>{'quizid': quizId, 'attemptid': attemptId},
      ),
    );
    final preventAccess = _quizStringList(quizAccess['preventaccessreasons']);
    final preventNew = _quizStringList(
      attemptAccess['preventnewattemptreasons'],
    );
    final requiresPreflight = _toBool(
      attemptAccess['ispreflightcheckrequired'],
    );
    final messages = <String>[
      ...preventAccess,
      ...preventNew,
      if (requiresPreflight) '该测验需要在 iSpace 页面完成额外访问检查。',
      _quizMessages(quizAccess),
      _quizMessages(attemptAccess),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    return _QuizAccessSnapshot(
      canAttempt: _toBool(quizAccess['canattempt']),
      isFinished: _toBool(attemptAccess['isfinished']),
      requiresPreflight: requiresPreflight,
      preventAccessReasons: preventAccess,
      preventNewAttemptReasons: preventNew,
      message: _boundedQuizText(messages.join(' '), 1000),
    );
  }

  List<String> _quizStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => _boundedQuizText(_stripHtml(item.toString()), 500))
        .where((item) => item.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  List<Map<String, String>> _validatedQuizData(
    QuizAttemptSnapshot snapshot,
    List<QuizAnswerDraft> answers,
  ) {
    if (!snapshot.hasActiveAttempt) {
      throw MoodleApiException('测验作答状态已变化，请重新读取题目。');
    }
    if (answers.isEmpty) {
      throw MoodleApiException('没有可保存的测验答案。');
    }
    final questions = {for (final item in snapshot.questions) item.slot: item};
    final seenNames = <String>{};
    final result = <Map<String, String>>[];
    final touchedSlots = <int>{};
    for (final answer in answers) {
      final question = questions[answer.slot];
      if (question == null || !seenNames.add(answer.fieldName)) {
        throw MoodleApiException('测验答案字段已变化，请重新生成答案。');
      }
      final matches = question.fields.where(
        (field) => field.name == answer.fieldName,
      );
      if (matches.length != 1) {
        throw MoodleApiException('测验答案字段已变化，请重新生成答案。');
      }
      final field = matches.single;
      if (answer.value.length > field.maxLength) {
        throw MoodleApiException('测验答案超过允许长度。');
      }
      if (field.options.isNotEmpty &&
          !field.options.any((option) => option.value == answer.value)) {
        throw MoodleApiException('测验选项已变化，请重新生成答案。');
      }
      result.add(<String, String>{
        'name': answer.fieldName,
        'value': answer.value,
      });
      touchedSlots.add(answer.slot);
    }
    for (final slot in touchedSlots) {
      final question = questions[slot]!;
      if (question.sequenceCheckName.isEmpty ||
          question.sequenceCheck.isEmpty) {
        throw MoodleApiException('测验题目版本信息缺失，请重新打开原生测验页面。');
      }
      result.add(<String, String>{
        'name': question.sequenceCheckName,
        'value': question.sequenceCheck,
      });
    }
    return result;
  }

  QuizQuestionData? _parseQuizQuestion(Map<String, dynamic> raw) {
    final slot = _toInt(raw['slot']);
    final html = _pickString(raw, const ['html']);
    if (slot <= 0 || html.trim().isEmpty) return null;
    final document = html_parser.parseFragment(html);
    final sequenceInput = document.querySelector(
      r'input[name$=":sequencecheck"]',
    );
    final sequenceName = sequenceInput?.attributes['name']?.trim() ?? '';
    final sequenceValue = sequenceInput?.attributes['value']?.trim() ?? '';
    final fields = <QuizAnswerField>[];
    final groupedChoices = <String, List<Element>>{};
    for (final input in document.querySelectorAll('input[name]')) {
      final name = input.attributes['name']?.trim() ?? '';
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (!_quizFieldMatchesSlot(name, slot) ||
          name == sequenceName ||
          input.attributes.containsKey('disabled') ||
          input.attributes.containsKey('readonly')) {
        continue;
      }
      if (type == 'radio' || type == 'checkbox') {
        groupedChoices.putIfAbsent(name, () => <Element>[]).add(input);
      } else if (type == 'text' || type == 'number') {
        fields.add(
          QuizAnswerField(
            name: name,
            kind: QuizAnswerFieldKind.text,
            label: _quizInputLabel(document, input),
            currentValues: [input.attributes['value'] ?? ''],
            options: const [],
            maxLength:
                int.tryParse(
                  input.attributes['maxlength'] ?? '',
                )?.clamp(1, 4000) ??
                4000,
          ),
        );
      }
    }
    for (final entry in groupedChoices.entries) {
      final options = entry.value
          .map(
            (input) => QuizAnswerOption(
              value: input.attributes['value'] ?? '',
              label: _quizInputLabel(document, input),
            ),
          )
          .where((option) => option.value.isNotEmpty)
          .toList(growable: false);
      if (options.isEmpty) continue;
      fields.add(
        QuizAnswerField(
          name: entry.key,
          kind: QuizAnswerFieldKind.choice,
          label: '',
          currentValues: entry.value
              .where((input) => input.attributes.containsKey('checked'))
              .map((input) => input.attributes['value'] ?? '')
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
          options: options,
          multiple: entry.value.any(
            (input) =>
                (input.attributes['type'] ?? '').toLowerCase() == 'checkbox',
          ),
          maxLength: 500,
        ),
      );
    }
    for (final textarea in document.querySelectorAll('textarea[name]')) {
      final name = textarea.attributes['name']?.trim() ?? '';
      if (!_quizFieldMatchesSlot(name, slot) ||
          textarea.attributes.containsKey('disabled') ||
          textarea.attributes.containsKey('readonly')) {
        continue;
      }
      fields.add(
        QuizAnswerField(
          name: name,
          kind: QuizAnswerFieldKind.text,
          label: _quizInputLabel(document, textarea),
          currentValues: [textarea.text],
          options: const [],
          maxLength: 4000,
        ),
      );
    }
    for (final select in document.querySelectorAll('select[name]')) {
      final name = select.attributes['name']?.trim() ?? '';
      if (!_quizFieldMatchesSlot(name, slot) ||
          select.attributes.containsKey('disabled')) {
        continue;
      }
      final options = select
          .querySelectorAll('option')
          .map(
            (option) => QuizAnswerOption(
              value: option.attributes['value'] ?? '',
              label: _boundedQuizText(option.text, 500),
            ),
          )
          .toList(growable: false);
      fields.add(
        QuizAnswerField(
          name: name,
          kind: QuizAnswerFieldKind.select,
          label: _quizInputLabel(document, select),
          currentValues: select
              .querySelectorAll('option[selected]')
              .map((option) => option.attributes['value'] ?? '')
              .toList(growable: false),
          options: options,
          multiple: select.attributes.containsKey('multiple'),
          maxLength: 500,
        ),
      );
    }
    return QuizQuestionData(
      slot: slot,
      number: _boundedQuizText(
        document.querySelector('.qno')?.text ??
            raw['number']?.toString() ??
            '$slot',
        40,
      ),
      type: _pickString(raw, const ['type'], 'unknown'),
      prompt: _boundedQuizText(
        document.querySelector('.qtext')?.text ?? '',
        4000,
      ),
      status: _boundedQuizText(
        document.querySelector('.state')?.text ??
            _pickString(raw, const ['status']),
        120,
      ),
      sequenceCheckName: sequenceName,
      sequenceCheck: sequenceValue,
      fields: List.unmodifiable(fields),
    );
  }

  bool _quizFieldMatchesSlot(String name, int slot) {
    return RegExp('^q[0-9]+:${RegExp.escape('$slot')}_').hasMatch(name);
  }

  String _quizInputLabel(DocumentFragment document, Element input) {
    final id = input.attributes['id'];
    Element? label;
    if (id != null && id.isNotEmpty) {
      label = document.querySelector('label[for="${_cssEscape(id)}"]');
    }
    label ??= input.parent?.localName == 'label' ? input.parent : null;
    return _boundedQuizText(label?.text ?? '', 500);
  }

  String _cssEscape(String value) => value.replaceAll('"', r'\"');

  String _boundedQuizText(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return normalized.substring(0, maxLength);
  }

  String _quizMessages(Map<String, dynamic> response) {
    return _jsonMapList(response['messages'])
        .map((item) => _pickString(item, const ['message']))
        .where((item) => item.trim().isNotEmpty)
        .take(4)
        .join(' ');
  }

  List<Map<String, dynamic>> _jsonMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) {
          return item.map((key, value) => MapEntry(key.toString(), value));
        })
        .toList(growable: false);
  }

  Future<AssignmentSubmissionOutcome> submitAssignmentOnlineText({
    required String token,
    required int assignmentId,
    required String text,
  }) async {
    final state = await _loadAssignmentMutationState(
      token: token,
      assignmentId: assignmentId,
    );
    _requireSafeAssignmentMutation(state);
    if (!_assignmentConfigEnabled(state.summary, 'onlinetext', 'enabled') &&
        !_submissionPluginExists(state.submission, 'onlinetext')) {
      throw MoodleApiException('该作业当前未开放在线文本提交。');
    }
    if (text.trim().isEmpty) {
      throw MoodleApiException('提交内容不能为空。');
    }

    final response = await _callWebService(
      token: token,
      functionName: 'mod_assign_save_submission',
      parameters: <String, dynamic>{
        'assignmentid': assignmentId,
        'plugindata': <String, dynamic>{
          'onlinetext_editor': <String, dynamic>{
            'text': text.trim(),
            'format': 1,
            'itemid': 0,
          },
        },
      },
    );
    _requireNoAssignmentWarnings(response, operation: '保存作业内容');
    return _verifyAssignmentSave(
      token: token,
      assignmentId: assignmentId,
      submissionDrafts: _toBool(state.summary['submissiondrafts']),
    );
  }

  Future<AssignmentSubmissionOutcome> submitAssignmentFiles({
    required String token,
    required int assignmentId,
    required List<UploadFilePayload> files,
  }) async {
    final state = await _loadAssignmentMutationState(
      token: token,
      assignmentId: assignmentId,
    );
    _requireSafeAssignmentMutation(state);
    if (!_assignmentConfigEnabled(state.summary, 'file', 'enabled') &&
        !_submissionPluginExists(state.submission, 'file')) {
      throw MoodleApiException('该作业当前未开放文件提交。');
    }
    final profile = _runtimeProfile;
    if (profile == null ||
        !profile.supports(MoodleNormalizedCapability.fileUpload)) {
      throw MoodleApiException('学校当前未开放 iSpace 文件上传能力。');
    }
    final validFiles = files.where((file) => file.hasUsableContent).toList();
    if (validFiles.isEmpty) {
      throw MoodleApiException('请至少选择一个有效文件再提交。');
    }
    final maxFiles = _assignmentConfigInt(
      state.summary,
      'file',
      'maxfilesubmissions',
    );
    if (maxFiles > 0 && validFiles.length > maxFiles) {
      throw MoodleApiException('所选文件数量超过该作业允许的上限。');
    }
    final maxBytes = _assignmentConfigInt(
      state.summary,
      'file',
      'maxsubmissionsizebytes',
    );
    if (maxBytes > 0) {
      for (final file in validFiles) {
        if (await _uploadPayloadSize(file) > maxBytes) {
          throw MoodleApiException('所选文件大小超过该作业允许的上限。');
        }
      }
    }

    final draftItemId = await _createDraftItemId(token: token);
    for (final file in validFiles) {
      await _uploadDraftFile(
        token: token,
        draftItemId: draftItemId,
        file: file,
      );
    }

    final response = await _callWebService(
      token: token,
      functionName: 'mod_assign_save_submission',
      parameters: <String, dynamic>{
        'assignmentid': assignmentId,
        'plugindata': <String, dynamic>{'files_filemanager': draftItemId},
      },
    );
    _requireNoAssignmentWarnings(response, operation: '保存作业文件');
    return _verifyAssignmentSave(
      token: token,
      assignmentId: assignmentId,
      submissionDrafts: _toBool(state.summary['submissiondrafts']),
    );
  }

  Future<AssignmentSubmissionOutcome> finalizeAssignment({
    required String token,
    required int assignmentId,
    required bool acceptSubmissionStatement,
  }) async {
    final state = await _loadAssignmentMutationState(
      token: token,
      assignmentId: assignmentId,
    );
    _requireSafeAssignmentMutation(state);
    if (!_toBool(state.summary['submissiondrafts'])) {
      throw MoodleApiException('该作业不使用独立的最终提交步骤。');
    }
    if (_pickString(state.submission, const ['status']) != 'draft' ||
        !_toBool(state.lastAttempt['cansubmit'])) {
      throw MoodleApiException('该作业当前没有可最终提交的草稿。');
    }
    final requiresStatement = _toBool(
      state.summary['requiresubmissionstatement'],
    );
    if (requiresStatement && !acceptSubmissionStatement) {
      throw MoodleApiException('最终提交前必须接受学校显示的作业提交声明。');
    }
    final response = await _callWebService(
      token: token,
      functionName: 'mod_assign_submit_for_grading',
      parameters: <String, dynamic>{
        'assignmentid': assignmentId,
        'acceptsubmissionstatement': acceptSubmissionStatement ? 1 : 0,
      },
    );
    _requireNoAssignmentWarnings(response, operation: '最终提交作业');
    final after = await _fetchAssignmentSubmissionStatus(
      token: token,
      assignmentId: assignmentId,
    );
    final status = _pickString(_asJsonMapOrEmpty(after['submission']), const [
      'status',
    ]);
    if (status != 'submitted') {
      throw MoodleApiException('作业提交请求已返回，但尚未确认最终提交状态。');
    }
    return AssignmentSubmissionOutcome(
      status: status,
      draftSaved: false,
      finalSubmitted: true,
    );
  }

  Future<AssignmentSubmissionOutcome> _verifyAssignmentSave({
    required String token,
    required int assignmentId,
    required bool submissionDrafts,
  }) async {
    final after = await _fetchAssignmentSubmissionStatus(
      token: token,
      assignmentId: assignmentId,
    );
    final status = _pickString(_asJsonMapOrEmpty(after['submission']), const [
      'status',
    ]);
    final valid = submissionDrafts
        ? status == 'draft' || status == 'submitted'
        : status == 'submitted';
    if (!valid) {
      throw MoodleApiException('作业保存请求已返回，但尚未确认提交状态。');
    }
    return AssignmentSubmissionOutcome(
      status: status,
      draftSaved: submissionDrafts && status == 'draft',
      finalSubmitted: status == 'submitted',
    );
  }

  Future<
    ({
      Map<String, dynamic> summary,
      Map<String, dynamic> lastAttempt,
      Map<String, dynamic> submission,
    })
  >
  _loadAssignmentMutationState({
    required String token,
    required int assignmentId,
  }) async {
    if (assignmentId <= 0) {
      throw MoodleApiException('作业缺少有效的实例标识。');
    }
    final summary = await _fetchAssignmentSummary(
      token: token,
      courseId: 0,
      assignmentId: assignmentId,
    );
    if (summary.isEmpty || _toBool(summary['nosubmissions'])) {
      throw MoodleApiException('该作业当前不接受学生提交。');
    }
    final status = await _fetchAssignmentSubmissionStatus(
      token: token,
      assignmentId: assignmentId,
    );
    return (
      summary: summary,
      lastAttempt: _asJsonMapOrEmpty(status['lastattempt']),
      submission: _asJsonMapOrEmpty(status['submission']),
    );
  }

  void _requireSafeAssignmentMutation(
    ({
      Map<String, dynamic> summary,
      Map<String, dynamic> lastAttempt,
      Map<String, dynamic> submission,
    })
    state,
  ) {
    if (_toBool(state.summary['teamsubmission']) ||
        _toBool(state.summary['preventsubmissionnotingroup']) ||
        _toInt(state.summary['timelimit']) > 0) {
      throw MoodleApiException('该作业需要在 iSpace 页面完成当前提交流程。');
    }
    if (!_toBool(state.lastAttempt['submissionsenabled']) ||
        _toBool(state.lastAttempt['locked']) ||
        (!_toBool(state.lastAttempt['canedit']) &&
            !_toBool(state.lastAttempt['caneditowner']))) {
      throw MoodleApiException('该作业当前不允许编辑提交内容。');
    }
  }

  void _requireNoAssignmentWarnings(
    dynamic response, {
    required String operation,
  }) {
    final warnings = response is List
        ? response
        : response is Map && response['warnings'] is List
        ? response['warnings'] as List
        : const [];
    if (warnings.isNotEmpty) {
      throw MoodleApiException('$operation未被 iSpace 接受，请刷新状态后重试。');
    }
  }

  Future<int> _createDraftItemId({required String token}) async {
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'core_files_get_unused_draft_itemid',
        parameters: const <String, dynamic>{},
      ),
    );
    final draftItemId = _toInt(response['itemid']);
    if (draftItemId <= 0) {
      throw MoodleApiException('未能创建文件草稿空间，请稍后重试。');
    }
    return draftItemId;
  }

  Future<int> _uploadPayloadSize(UploadFilePayload file) async {
    final bytes = file.bytes;
    if (bytes != null) return bytes.length;
    final path = file.filePath?.trim() ?? '';
    if (path.isEmpty) return 0;
    try {
      return await File(path).length();
    } on FileSystemException {
      throw MoodleApiException('所选文件已无法读取，请重新选择。');
    }
  }

  Future<void> _uploadDraftFile({
    required String token,
    required int draftItemId,
    required UploadFilePayload file,
  }) async {
    final uri = Uri.parse('$baseUrl/webservice/upload.php').replace(
      queryParameters: <String, String>{
        'token': token,
        'itemid': '$draftItemId',
        'filepath': '/',
      },
    );

    final request = http.MultipartRequest('POST', uri);
    request.fields['license'] = 'unknown';

    if (file.filePath != null && file.filePath!.trim().isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'file_1',
          file.filePath!,
          filename: file.fileName,
        ),
      );
    } else if (file.bytes != null && file.bytes!.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file_1',
          file.bytes!,
          filename: file.fileName,
        ),
      );
    } else {
      throw MoodleApiException('文件 ${file.fileName} 无法读取。');
    }

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw MoodleApiException('文件上传失败（HTTP ${response.statusCode}）。');
    }

    final decoded = _decodeDynamicJson(body);
    if (decoded is Map<String, dynamic>) {
      final exception = decoded['exception'];
      if (exception is String && exception.trim().isNotEmpty) {
        throw MoodleApiException(_extractWsError(decoded));
      }
      throw MoodleApiException('文件上传返回格式异常。');
    }
    if (decoded is! List || decoded.isEmpty) {
      throw MoodleApiException('文件上传返回格式异常。');
    }
  }

  void _ensureActiveWebSession(int expectedGeneration) {
    if (_isDisposed || expectedGeneration != _webSessionGeneration) {
      throw MoodleApiException('登录状态已变化，请重新打开页面。');
    }
  }

  int _requireActiveWebSession() {
    final expectedGeneration = _activeWebSessionGeneration;
    if (expectedGeneration == null) {
      throw MoodleApiException('登录状态已变化，请重新打开页面。');
    }
    _ensureActiveWebSession(expectedGeneration);
    return expectedGeneration;
  }

  Future<void> _ensureWebSession({
    required String username,
    required String password,
  }) async {
    _requireActiveWebSession();
    final sameUser = _webSessionUser != null && _webSessionUser == username;
    final hasCookies = _matchingWebCookies(Uri.parse(baseUrl)).isNotEmpty;
    if (sameUser && hasCookies) {
      final checkUri = Uri.parse('$baseUrl/my/');
      final probe = await _sendWebRequest(method: 'GET', uri: checkUri);
      final finalProbe = probe.isRedirect
          ? await _followRedirects(probe, origin: checkUri)
          : probe;
      // Transport failures do not establish expiry and must not submit a
      // password again or export an unverified snapshot to a WebView.
      if (finalProbe.statusCode != 401 && finalProbe.statusCode != 403) {
        _checkWebSessionResponse(finalProbe);
        if (!_looksLikeLoginPage(finalProbe.body)) return;
      }
    }
    _requireActiveWebSession();
    await _loginWebSession(username: username, password: password);
  }

  Future<void> _loginWebSession({
    required String username,
    required String password,
  }) async {
    _requireActiveWebSession();
    _webCookies.clear();
    _webSessionUser = null;

    final loginUri = Uri.parse('$baseUrl/login/index.php');
    final loginPage = await _sendWebRequest(method: 'GET', uri: loginUri);
    _checkWebSessionResponse(loginPage);
    final logintoken = _extractLoginToken(loginPage.body);
    if (logintoken.isEmpty) {
      throw MoodleApiException('未能获取官网登录令牌（logintoken）。');
    }

    var step = await _sendWebRequest(
      method: 'POST',
      uri: loginUri,
      body: Uri(
        queryParameters: <String, String>{
          'logintoken': logintoken,
          'username': username,
          'password': password,
        },
      ).query,
      contentType: ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      ),
    );

    if (step.isRedirect) {
      step = await _followRedirects(step, origin: loginUri);
    }

    final verify = await _sendWebRequest(
      method: 'GET',
      uri: Uri.parse('$baseUrl/my/'),
    );
    final finalVerify = verify.isRedirect
        ? await _followRedirects(verify, origin: Uri.parse('$baseUrl/my/'))
        : verify;

    _checkWebSessionResponse(finalVerify);
    if (_looksLikeLoginPage(finalVerify.body)) {
      throw MoodleApiException('官网会话建立失败，请检查账号密码后重试。');
    }

    _requireActiveWebSession();
    _webSessionUser = username;
  }

  void _checkWebSessionResponse(_WebResponse response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw MoodleApiException(
      'iSpace 网页会话检查失败（HTTP ${response.statusCode}）。',
      isRetryable:
          response.statusCode == 408 ||
          response.statusCode == 429 ||
          response.statusCode >= 500,
    );
  }

  Future<_WebResponse> _followRedirects(
    _WebResponse firstResponse, {
    required Uri origin,
  }) async {
    var current = firstResponse;
    var currentUri = origin;
    for (var i = 0; i < 8; i++) {
      final location = current.location;
      if (!current.isRedirect || location == null || location.trim().isEmpty) {
        return current;
      }
      currentUri = currentUri.resolve(location);
      current = await _sendWebRequest(method: 'GET', uri: currentUri);
    }
    return current;
  }

  Future<_WebResponse> _sendWebRequest({
    required String method,
    required Uri uri,
    String? body,
    ContentType? contentType,
  }) async {
    final expectedGeneration = _requireActiveWebSession();
    try {
      final request = await _webHttpClient
          .openUrl(method, uri)
          .timeout(_requestTimeout);
      _ensureActiveWebSession(expectedGeneration);
      request.followRedirects = false;
      request.maxRedirects = 0;
      final cookieHeader = _buildCookieHeader(uri);
      if (cookieHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      if (contentType != null) {
        request.headers.contentType = contentType;
      }
      if (body != null && body.isNotEmpty) {
        request.add(utf8.encode(body));
      }

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_requestTimeout);
      _ensureActiveWebSession(expectedGeneration);
      _cacheWebCookies(
        response.cookies,
        uri,
        expectedGeneration: expectedGeneration,
      );
      return _WebResponse(
        statusCode: response.statusCode,
        body: responseBody,
        location: response.headers.value(HttpHeaders.locationHeader),
      );
    } on TlsException catch (error) {
      final failure = classifySchoolTlsFailure(error);
      throw MoodleApiException(
        failure.message,
        isRetryable: failure.isRetryable,
      );
    } on TimeoutException {
      throw MoodleApiException('网页登录请求超时，请稍后重试。', isRetryable: true);
    } on SocketException {
      throw MoodleApiException('网页登录网络连接失败，请稍后重试。', isRetryable: true);
    } on HttpException {
      throw MoodleApiException('网页登录网络连接失败，请稍后重试。', isRetryable: true);
    }
  }

  List<_StoredWebCookie> _matchingWebCookies(Uri uri) {
    final baseUri = Uri.parse(baseUrl);
    if (!_hasSameOrigin(uri, baseUri)) {
      return const <_StoredWebCookie>[];
    }

    final now = DateTime.now();
    _webCookies.removeWhere((cookie) => cookie.isExpired(now));
    final matches = _webCookies
        .where((cookie) => cookie.matches(uri, now))
        .toList(growable: false);
    matches.sort(
      (left, right) => right.path.length.compareTo(left.path.length),
    );
    return matches;
  }

  String _buildCookieHeader(Uri uri) {
    return _matchingWebCookies(
      uri,
    ).map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  void _cacheWebCookies(
    List<Cookie> cookies,
    Uri origin, {
    required int expectedGeneration,
  }) {
    if (_isDisposed || expectedGeneration != _webSessionGeneration) {
      return;
    }
    final baseUri = Uri.parse(baseUrl);
    if (!_hasSameOrigin(origin, baseUri)) {
      return;
    }

    final now = DateTime.now();
    for (final cookie in cookies) {
      final stored = _StoredWebCookie.fromCookie(
        cookie,
        origin,
        trustedDomain: cookieDomain,
        now: now,
      );
      if (stored == null) {
        continue;
      }
      _webCookies.removeWhere((existing) => existing.hasSameIdentity(stored));
      if (!stored.isExpired(now)) {
        _webCookies.add(stored);
      }
    }
  }

  String _extractLoginToken(String html) {
    final matches = RegExp(
      "name=[\"']logintoken[\"']\\s+value=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    if (matches == null || matches.groupCount < 1) {
      return '';
    }
    return matches.group(1)?.trim() ?? '';
  }

  bool _looksLikeLoginPage(String html) {
    final normalized = html.toLowerCase();
    return normalized.contains('name="logintoken"') ||
        normalized.contains("name='logintoken'") ||
        normalized.contains('/login/index.php');
  }

  Future<dynamic> _callWebService({
    required String token,
    required String functionName,
    required Map<String, dynamic> parameters,
  }) async {
    if (functionName != 'core_webservice_get_site_info') {
      final profile = _runtimeProfile;
      if (_runtimeProfileToken != token ||
          profile == null ||
          !profile.supportsFunction(functionName)) {
        throw MoodleFeatureUnavailableException(functionName);
      }
    }
    final uri = Uri.parse('$baseUrl/webservice/rest/server.php');
    final formBody = <String, String>{
      'wstoken': token,
      'moodlewsrestformat': 'json',
      'wsfunction': functionName,
    };

    for (final entry in parameters.entries) {
      _appendFormField(formBody, entry.key, entry.value);
    }

    if (kDebugMode) {
      debugPrint('[Moodle] wsfunction=$functionName');
    }

    final response = await _postForm(
      uri,
      formBody,
      operation: '接口 $functionName',
    );
    if (response.statusCode != 200) {
      throw MoodleApiException(
        '接口 $functionName 调用失败（HTTP ${response.statusCode}）。',
        isRetryable: _isRetryableHttpStatus(response.statusCode),
      );
    }

    final body = _decodeDynamicJson(response.body);
    if (body is Map<String, dynamic>) {
      final exception = body['exception'];
      if (exception is String && exception.isNotEmpty) {
        throw MoodleApiException(_extractWsError(body));
      }
      return body;
    }
    if (body is List) {
      return body;
    }

    throw MoodleApiException('接口 $functionName 返回格式异常。');
  }

  Future<http.Response> _postForm(
    Uri uri,
    Map<String, String> body, {
    required String operation,
  }) async {
    try {
      return await _httpClient.post(uri, body: body).timeout(_requestTimeout);
    } on TimeoutException {
      throw MoodleApiException('$operation请求超时，请稍后重试。', isRetryable: true);
    } on TlsException catch (error) {
      final failure = classifySchoolTlsFailure(error);
      throw MoodleApiException(
        failure.message,
        isRetryable: failure.isRetryable,
      );
    } on SocketException {
      throw MoodleApiException('$operation网络连接失败，请稍后重试。', isRetryable: true);
    } on http.ClientException {
      throw MoodleApiException('$operation网络连接失败，请稍后重试。', isRetryable: true);
    }
  }

  bool _isRetryableHttpStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  List<Map<String, dynamic>> _extractEvents(Map<String, dynamic> response) {
    final dynamic eventsValue = response['events'];
    if (eventsValue is List) {
      return eventsValue
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }

    final dynamic data = response['data'];
    if (data is Map<String, dynamic>) {
      final nestedEvents = data['events'];
      if (nestedEvents is List) {
        return nestedEvents
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
    }
    return const [];
  }

  int _extractNextCursor(
    Map<String, dynamic> response,
    List<Map<String, dynamic>> events,
    int currentCursor,
  ) {
    final fromResponse = _toInt(response['lastid']) != 0
        ? _toInt(response['lastid'])
        : _toInt(response['lasteventid']);
    if (fromResponse > currentCursor) {
      return fromResponse;
    }
    var maxEventId = currentCursor;
    for (final event in events) {
      final eventId = _toInt(event['id']);
      if (eventId > maxEventId) {
        maxEventId = eventId;
      }
    }
    return maxEventId;
  }

  bool _looksLikeAssignment(TimelineItem item) {
    final module = item.moduleName.toLowerCase();
    final activity = item.activityType.toLowerCase();
    final url = item.url.toLowerCase();
    return module.contains('assign') ||
        activity.contains('assign') ||
        url.contains('/mod/assign/');
  }

  bool _looksLikeForum(TimelineItem item) {
    final module = item.moduleName.toLowerCase();
    final activity = item.activityType.toLowerCase();
    final url = item.url.toLowerCase();
    return module.contains('forum') ||
        activity.contains('forum') ||
        url.contains('/mod/forum/');
  }

  bool _looksLikeMediaSite(TimelineItem item) {
    final module = item.moduleName.toLowerCase();
    final activity = item.activityType.toLowerCase();
    final url = item.url.toLowerCase();
    return module.contains('mediasite') ||
        activity.contains('mediasite') ||
        url.contains('/mod/mediasite/');
  }

  Future<int> _resolveAssignId({
    required String token,
    required TimelineItem item,
  }) async {
    return _resolveModuleInstanceId(
      token: token,
      item: item,
      moduleName: 'assign',
    );
  }

  Future<int> _resolveModuleInstanceId({
    required String token,
    required TimelineItem item,
    required String moduleName,
  }) async {
    final cmid = _extractCourseModuleId(item.url);
    if (cmid > 0) {
      final fromCourseModule = await _resolveModuleInstanceFromCourseModule(
        token: token,
        cmid: cmid,
        moduleName: moduleName,
      );
      if (fromCourseModule > 0) {
        return fromCourseModule;
      }
      if (cmid == item.id &&
          item.instanceId > 0 &&
          item.moduleName.trim().toLowerCase() == moduleName.toLowerCase()) {
        // A v4 module_ref is re-resolved from the current course contents before
        // this pseudo Timeline item is created, so the cmid/instance pair is
        // already bound to the logged-in session.
        return item.instanceId;
      }
    }

    if (item.instanceId > 0) {
      final fromMaybeCmid = await _resolveModuleInstanceFromCourseModule(
        token: token,
        cmid: item.instanceId,
        moduleName: moduleName,
      );
      if (fromMaybeCmid > 0) {
        return fromMaybeCmid;
      }

      final fromInstance = await _resolveModuleInstanceByInstance(
        token: token,
        moduleName: moduleName,
        moduleInstanceId: item.instanceId,
      );
      if (fromInstance > 0) {
        return fromInstance;
      }
    }

    return 0;
  }

  Future<int> _resolveModuleInstanceFromCourseModule({
    required String token,
    required int cmid,
    required String moduleName,
  }) async {
    try {
      final raw = await _callWebService(
        token: token,
        functionName: 'core_course_get_course_module',
        parameters: <String, dynamic>{'cmid': cmid},
      );
      final data = _asJsonMap(raw);
      final cm = data['cm'];
      if (cm is Map) {
        final modname = (cm['modname'] as String?)?.toLowerCase() ?? '';
        if (modname != moduleName.toLowerCase()) {
          return 0;
        }
        return _toInt(cm['instance']);
      }
    } on MoodleApiException {
      return 0;
    }
    return 0;
  }

  Future<int> _resolveModuleInstanceByInstance({
    required String token,
    required String moduleName,
    required int moduleInstanceId,
  }) async {
    try {
      final raw = await _callWebService(
        token: token,
        functionName: 'core_course_get_course_module_by_instance',
        parameters: <String, dynamic>{
          'module': moduleName,
          'instance': moduleInstanceId,
        },
      );
      final data = _asJsonMap(raw);
      final cm = data['cm'];
      if (cm is Map) {
        final modname = (cm['modname'] as String?)?.toLowerCase() ?? '';
        if (modname != moduleName.toLowerCase()) {
          return 0;
        }
        return _toInt(cm['instance']);
      }
    } on MoodleApiException {
      return 0;
    }
    return 0;
  }

  Future<Map<String, dynamic>> _fetchAssignmentSummary({
    required String token,
    required int courseId,
    required int assignmentId,
  }) async {
    Map<String, dynamic> searchInResponse(dynamic rawResponse) {
      final response = _asJsonMap(rawResponse);
      final courses = response['courses'];
      if (courses is List) {
        for (final course in courses.whereType<Map>()) {
          final assignments = course['assignments'];
          if (assignments is List) {
            for (final assign in assignments.whereType<Map>()) {
              final candidateId = _toInt(assign['id']);
              if (candidateId == assignmentId) {
                return assign.cast<String, dynamic>();
              }
            }
          }
        }
      }
      return const {};
    }

    final scopedParams = <String, dynamic>{};
    if (courseId > 0) {
      scopedParams['courseids'] = <int>[courseId];
    }

    final scopedRaw = await _callWebService(
      token: token,
      functionName: 'mod_assign_get_assignments',
      parameters: scopedParams,
    );
    final fromScoped = searchInResponse(scopedRaw);
    if (fromScoped.isNotEmpty || courseId <= 0) {
      return fromScoped;
    }

    final globalRaw = await _callWebService(
      token: token,
      functionName: 'mod_assign_get_assignments',
      parameters: const <String, dynamic>{},
    );
    return searchInResponse(globalRaw);
  }

  Future<Map<String, dynamic>> _fetchAssignmentSubmissionStatus({
    required String token,
    required int assignmentId,
  }) async {
    final raw = await _callWebService(
      token: token,
      functionName: 'mod_assign_get_submission_status',
      parameters: <String, dynamic>{'assignid': assignmentId},
    );
    final response = _asJsonMap(raw);
    final lastAttempt = _asJsonMapOrEmpty(response['lastattempt']);
    final submission = _asJsonMapOrEmpty(lastAttempt['submission']);
    return <String, dynamic>{
      'lastattempt': lastAttempt,
      'submission': submission,
    };
  }

  bool _assignmentConfigEnabled(
    Map<String, dynamic> assignment,
    String plugin,
    String name,
  ) {
    final value = _assignmentConfigValue(assignment, plugin, name);
    return _toBool(value);
  }

  int _assignmentConfigInt(
    Map<String, dynamic> assignment,
    String plugin,
    String name,
  ) {
    final value = _assignmentConfigValue(assignment, plugin, name);
    return _toInt(value);
  }

  dynamic _assignmentConfigValue(
    Map<String, dynamic> assignment,
    String plugin,
    String name,
  ) {
    final configs = assignment['configs'];
    if (configs is! List) {
      return null;
    }
    for (final config in configs.whereType<Map>()) {
      final pluginName = (config['plugin'] as String?)?.toLowerCase() ?? '';
      final configName = (config['name'] as String?)?.toLowerCase() ?? '';
      if (pluginName == plugin.toLowerCase() &&
          configName == name.toLowerCase()) {
        return config['value'];
      }
    }
    return null;
  }

  bool _submissionPluginExists(
    Map<String, dynamic> submission,
    String pluginType,
  ) {
    final plugins = submission['plugins'];
    if (plugins is! List) {
      return false;
    }
    for (final plugin in plugins.whereType<Map>()) {
      final type = (plugin['type'] as String?)?.toLowerCase() ?? '';
      if (type == pluginType.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  List<SubmissionFile> _extractSubmissionFiles(
    Map<String, dynamic> submission,
  ) {
    final files = <SubmissionFile>[];
    final plugins = submission['plugins'];
    if (plugins is! List) {
      return files;
    }

    for (final plugin in plugins.whereType<Map>()) {
      final type = (plugin['type'] as String?)?.toLowerCase() ?? '';
      if (!type.contains('file')) {
        continue;
      }

      final fileAreas = plugin['fileareas'];
      if (fileAreas is! List) {
        continue;
      }

      for (final area in fileAreas.whereType<Map>()) {
        final areaFiles = area['files'];
        if (areaFiles is! List) {
          continue;
        }
        for (final file in areaFiles.whereType<Map>()) {
          files.add(
            SubmissionFile(
              fileName: _pickString(file.cast<String, dynamic>(), const [
                'filename',
                'fullname',
              ], '未命名文件'),
              fileUrl: _pickString(file.cast<String, dynamic>(), const [
                'fileurl',
                'url',
              ]),
              fileSize: _toInt(file['filesize'] ?? file['size']),
              mimeType: _pickString(file.cast<String, dynamic>(), const [
                'mimetype',
              ]),
              modifiedEpoch: _toInt(
                file['timemodified'] ?? file['datemodified'],
              ),
            ),
          );
        }
      }
    }

    return files;
  }

  List<SubmissionFile> _extractAssignmentIntroFiles(
    Map<String, dynamic> assignment, {
    required String token,
  }) {
    final files = <SubmissionFile>[];
    final attachments =
        assignment['introattachments'] ?? assignment['introfiles'];
    if (attachments is! List) {
      return files;
    }
    for (final raw in attachments.whereType<Map>()) {
      final data = raw.cast<String, dynamic>();
      files.add(
        SubmissionFile(
          fileName: _pickString(data, const ['filename', 'fullname'], '未命名文件'),
          fileUrl: _decoratePluginFileUrlWithToken(
            _pickString(data, const ['fileurl', 'url']),
            token: token,
          ),
          fileSize: _toInt(data['filesize'] ?? data['size']),
          mimeType: _pickString(data, const ['mimetype']),
          modifiedEpoch: _toInt(data['timemodified'] ?? data['datemodified']),
        ),
      );
    }
    return files;
  }

  List<ForumDiscussion> _extractForumDiscussions(dynamic value) {
    if (value is! List) {
      return const [];
    }
    final discussions = <ForumDiscussion>[];
    for (final raw in value.whereType<Map>()) {
      final data = raw.cast<String, dynamic>();
      final discussionId = _toInt(data['discussion'] ?? data['id']);
      discussions.add(
        ForumDiscussion(
          id: discussionId,
          subject: _pickString(data, const ['subject', 'name'], '无标题讨论'),
          messagePreview: _stripHtml(
            _pickString(data, const ['message', 'intro']),
          ),
          author: _pickString(data, const [
            'userfullname',
            'usermodifiedfullname',
            'usercreatedfullname',
          ], '未知用户'),
          timeModifiedEpoch: _toInt(
            data['timemodified'] ?? data['timecreated'],
          ),
          replyCount: _toInt(data['numreplies']),
          pinned: _toBool(data['pinned']),
          locked: _toBool(data['locked']),
          discussionUrl: discussionId <= 0
              ? ''
              : '$baseUrl/mod/forum/discuss.php?d=$discussionId',
        ),
      );
    }
    return discussions;
  }

  List<Map<String, dynamic>> _extractForums(dynamic response) {
    if (response is List) {
      return response
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    if (response is Map<String, dynamic>) {
      final forums = response['forums'];
      if (forums is List) {
        return forums
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
    }
    return const [];
  }

  String _extractFeedback(Map<String, dynamic> submission) {
    final plugins = submission['plugins'];
    if (plugins is! List) {
      return '';
    }
    for (final plugin in plugins.whereType<Map>()) {
      final type = (plugin['type'] as String?)?.toLowerCase() ?? '';
      if (!type.contains('feedback')) {
        continue;
      }
      final editorFields = plugin['editorfields'];
      if (editorFields is List) {
        for (final field in editorFields.whereType<Map>()) {
          final text = field['text'];
          if (text is String && text.trim().isNotEmpty) {
            return text.trim();
          }
        }
      }
    }
    return '';
  }

  int _extractCourseModuleId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return 0;
    }
    return _toInt(uri.queryParameters['id']);
  }

  String _normalizeAssignmentIntroHtml(
    String rawHtml, {
    required List<SubmissionFile> introFiles,
    required String token,
  }) {
    var html = rawHtml.trim();
    if (html.isEmpty) {
      return '';
    }

    for (final file in introFiles) {
      final url = _decoratePluginFileUrlWithToken(file.fileUrl, token: token);
      if (url.isEmpty) {
        continue;
      }
      final fileName = file.fileName.trim();
      if (fileName.isEmpty) {
        continue;
      }
      final encoded = Uri.encodeComponent(fileName);
      html = html.replaceAll('@@PLUGINFILE@@/$fileName', url);
      html = html.replaceAll('@@PLUGINFILE@@/$encoded', url);
    }

    html = html.replaceAllMapped(
      RegExp(
        '(https?://[^"\\s>]*?/pluginfile\\.php[^"\\s>]*)',
        caseSensitive: false,
      ),
      (match) =>
          _decoratePluginFileUrlWithToken(match.group(1) ?? '', token: token),
    );

    html = html.replaceAllMapped(
      RegExp(
        '(https?://[^"\\s>]*?/webservice/pluginfile\\.php[^"\\s>]*)',
        caseSensitive: false,
      ),
      (match) =>
          _decoratePluginFileUrlWithToken(match.group(1) ?? '', token: token),
    );

    html = html.replaceAll('@@PLUGINFILE@@', baseUrl);
    return html;
  }

  String _decoratePluginFileUrlWithToken(String url, {required String token}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return trimmed;
    }
    if (!uri.path.contains('/pluginfile.php')) {
      return trimmed;
    }
    final configuredBaseUri = Uri.parse(baseUrl);
    if ((uri.isAbsolute || uri.hasAuthority) &&
        !_hasSameOrigin(uri, configuredBaseUri)) {
      return trimmed;
    }
    if (uri.queryParameters['token']?.trim().isNotEmpty ?? false) {
      return trimmed;
    }
    final query = Map<String, String>.from(uri.queryParameters);
    query['token'] = token;
    return uri.replace(queryParameters: query).toString();
  }

  bool _hasSameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        _effectivePort(left) == _effectivePort(right);
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

  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    throw MoodleApiException('接口返回格式异常，预期对象。');
  }

  Map<String, dynamic> _asJsonMapOrEmpty(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  dynamic _decodeDynamicJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw MoodleApiException('服务端返回了不可解析的 JSON。');
    }
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final decoded = _decodeDynamicJson(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw MoodleApiException('服务端返回结构异常。');
  }

  String _extractWsError(
    Map<String, dynamic> json, {
    String fallback = '接口调用失败。',
  }) {
    final message = json['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    final error = json['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    final errorCode = json['errorcode'];
    if (errorCode is String && errorCode.trim().isNotEmpty) {
      return errorCode.trim();
    }
    final debuginfo = json['debuginfo'];
    if (debuginfo is String && debuginfo.trim().isNotEmpty) {
      return debuginfo.trim();
    }
    return fallback;
  }

  void _appendFormField(Map<String, String> form, String key, dynamic value) {
    if (value == null) {
      return;
    }
    if (value is Map<String, dynamic>) {
      for (final entry in value.entries) {
        _appendFormField(form, '$key[${entry.key}]', entry.value);
      }
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _appendFormField(form, '$key[$i]', value[i]);
      }
      return;
    }
    form[key] = value.toString();
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  bool _isAssignRecordError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains(
          "can't find data record in database table assign",
        ) ||
        normalized.contains('invalidrecord');
  }

  int _timeSortValue(TimelineItem item) {
    final millis = item.sortTime?.millisecondsSinceEpoch;
    if (millis == null || millis <= 0) {
      return 253402300799000; // 9999-12-31
    }
    return millis;
  }

  String _stripHtml(String input) {
    if (input.isEmpty) {
      return '';
    }
    return input
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _pickString(
    Map<String, dynamic> json,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }
}

class _QuizAccessSnapshot {
  const _QuizAccessSnapshot({
    required this.canAttempt,
    required this.isFinished,
    required this.requiresPreflight,
    required this.preventAccessReasons,
    required this.preventNewAttemptReasons,
    required this.message,
  });

  final bool canAttempt;
  final bool isFinished;
  final bool requiresPreflight;
  final List<String> preventAccessReasons;
  final List<String> preventNewAttemptReasons;
  final String message;
}

class _StoredWebCookie {
  const _StoredWebCookie({
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

  static _StoredWebCookie? fromCookie(
    Cookie cookie,
    Uri origin, {
    required String trustedDomain,
    required DateTime now,
  }) {
    final originHost = origin.host.trim().toLowerCase();
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
    final path = rawPath.startsWith('/') ? rawPath : _defaultPath(origin);
    final maxAge = cookie.maxAge;
    final expires = maxAge == null
        ? cookie.expires
        : now.add(Duration(seconds: maxAge));
    return _StoredWebCookie(
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

  bool hasSameIdentity(_StoredWebCookie other) {
    return name == other.name && domain == other.domain && path == other.path;
  }

  bool matches(Uri uri, DateTime now) {
    if (isExpired(now) || (secure && uri.scheme.toLowerCase() != 'https')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    final domainMatches = hostOnly
        ? host == domain
        : _domainMatches(host, domain);
    return domainMatches && _pathMatches(uri.path, path);
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

class _WebResponse {
  _WebResponse({
    required this.statusCode,
    required this.body,
    required this.location,
  });

  final int statusCode;
  final String body;
  final String? location;

  bool get isRedirect =>
      statusCode == 301 || statusCode == 302 || statusCode == 303;
}
