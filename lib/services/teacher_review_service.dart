import 'sync/device_session_provider.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../models/teacher_review.dart';
import 'device_identity_service.dart';
import 'network_retry.dart';
import 'usage_sync_service.dart';

abstract interface class TeacherReviewService {
  Future<TeacherReviewPageData> loadReviews(
    String teacherKey, {
    bool courseLinkedOnly = false,
    int offset = 0,
    int limit = 50,
  });

  Future<TeacherReviewMineState> loadMine(String username, String teacherKey);

  Future<TeacherReviewMineState> saveReview(
    String username,
    String teacherKey,
    TeacherReviewDraft draft,
  );

  void dispose();
}

class RemoteTeacherReviewService implements TeacherReviewService {
  RemoteTeacherReviewService({
    http.Client? client,
    UsageSyncStore? usageStore,
    Future<PackageInfo> Function()? packageInfoLoader,
    String? baseUrl,
    String? Function()? platformProvider,
    PhysicalDeviceIdentityProvider? deviceIdentityProvider,
    Future<void> Function(Duration delay)? retryDelay,
  }) : _client = client ?? createAppHttpClient(),
       _ownsClient = client == null,
       _usageStore = usageStore ?? SecureUsageSyncStore(),
       _baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       ),
       _retryDelay = retryDelay ?? Future<void>.delayed;

  final http.Client _client;
  final bool _ownsClient;
  final UsageSyncStore _usageStore;
  final String _baseUrl;
  final Future<void> Function(Duration delay) _retryDelay;

  @override
  Future<TeacherReviewPageData> loadReviews(
    String teacherKey, {
    bool courseLinkedOnly = false,
    int offset = 0,
    int limit = 50,
  }) async {
    _validateTeacherKey(teacherKey);
    if (offset < 0 || limit < 1 || limit > 50) {
      throw const TeacherReviewException('教师评价分页参数无效。');
    }
    final uri =
        Uri.parse(
          '$_baseUrl/v2/directory/public/teachers/$teacherKey/reviews',
        ).replace(
          queryParameters: {
            'course_linked_only': '$courseLinkedOnly',
            'offset': '$offset',
            'limit': '$limit',
          },
        );
    final response = await _requestWithRetry(
      () => _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12)),
    );
    _requireSuccess(response, operation: '加载教师评价');
    return TeacherReviewPageData.fromJson(_decodeObject(response.body));
  }

  @override
  Future<TeacherReviewMineState> loadMine(
    String username,
    String teacherKey,
  ) async {
    _validateTeacherKey(teacherKey);
    final email = schoolEmailForUsername(username);
    final record = await _usageStore.loadDevice(email);
    final token = record?.deviceToken;
    if (token == null || token.isEmpty) {
      return const TeacherReviewMineState(
        review: null,
        suspendedUntil: null,
        canReview: true,
      );
    }
    final response = await _requestWithRetry(
      () => _client
          .get(
            Uri.parse('$_baseUrl/v2/teacher-reviews/$teacherKey/mine'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12)),
    );
    if (response.statusCode == 401) {
      await _usageStore.saveDevice(
        email,
        UsageSyncDeviceRecord(
          installationId: record!.installationId,
          deviceToken: null,
        ),
      );
      return const TeacherReviewMineState(
        review: null,
        suspendedUntil: null,
        canReview: true,
      );
    }
    _requireSuccess(response, operation: '加载我的评价');
    return TeacherReviewMineState.fromJson(_decodeObject(response.body));
  }

  @override
  Future<TeacherReviewMineState> saveReview(
    String username,
    String teacherKey,
    TeacherReviewDraft draft,
  ) async {
    _validateTeacherKey(teacherKey);
    final email = schoolEmailForUsername(username);
    var token = await _ensureDeviceToken(email);
    var response = await _writeReview(token, teacherKey, draft);
    if (response.statusCode == 401) {
      final existing = await _usageStore.loadDevice(email);
      if (existing != null) {
        await _usageStore.saveDevice(
          email,
          UsageSyncDeviceRecord(
            installationId: existing.installationId,
            deviceToken: null,
          ),
        );
      }
      token = await _ensureDeviceToken(email);
      response = await _writeReview(token, teacherKey, draft);
    }
    if (response.statusCode == 403) {
      final detail = _decodeObject(response.body)['detail'];
      if (detail is Map && detail['code'] == 'teacher_review_suspended') {
        throw TeacherReviewSuspendedException(
          DateTime.tryParse('${detail['suspended_until']}'),
        );
      }
    }
    if (response.statusCode == 409) {
      throw const TeacherReviewConflictException();
    }
    _requireSuccess(response, operation: '保存教师评价');
    return TeacherReviewMineState.fromJson(_decodeObject(response.body));
  }

  Future<http.Response> _writeReview(
    String token,
    String teacherKey,
    TeacherReviewDraft draft,
  ) {
    return _requestWithRetry(
      () => _client
          .put(
            Uri.parse(
              '$_baseUrl/${draft.styleDimensions == null ? 'v1' : 'v2'}/teacher-reviews/$teacherKey',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(draft.toJson()),
          )
          .timeout(const Duration(seconds: 12)),
    );
  }

  /// Shared remote device identity only; no teacher request or school session.
  Future<String?> existingReviewDeviceToken(String username) async =>
      DeviceSessionProvider(store: _usageStore)
          .token(username)
          .then<String?>((value) => value, onError: (Object _) => null);

  Future<String> ensureReviewDeviceToken(
    String username, {
    required String consentVersion,
  }) => _ensureDeviceToken(
    schoolEmailForUsername(username),
    consentVersion: consentVersion,
  );

  Future<void> invalidateReviewDeviceToken(String username) async {
    final email = schoolEmailForUsername(username);
    final existing = await _usageStore.loadDevice(email);
    if (existing != null) {
      await _usageStore.saveDevice(
        email,
        UsageSyncDeviceRecord(
          installationId: existing.installationId,
          deviceToken: null,
        ),
      );
    }
  }

  Future<String> _ensureDeviceToken(
    String email, {
    String consentVersion = teacherReviewConsentVersion,
  }) => DeviceSessionProvider.mutate(
    '$_baseUrl:$email',
    () => _ensureDeviceTokenSerial(email, consentVersion: consentVersion),
  );

  Future<String> _ensureDeviceTokenSerial(
    String email, {
    String consentVersion = teacherReviewConsentVersion,
  }) => DeviceSessionProvider(store: _usageStore).token(email);

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await retryNetworkOperation(
        request,
        shouldRetryResult: (response) =>
            isTransientHttpStatus(response.statusCode),
        delay: _retryDelay,
      );
    } on Object catch (error) {
      if (isTransientNetworkError(error)) {
        throw const TeacherReviewException('教师评价网络连接不稳定，请稍后重试。');
      }
      rethrow;
    }
  }

  void _requireSuccess(
    http.Response response, {
    required String operation,
    int expectedStatus = 200,
  }) {
    if (response.statusCode != expectedStatus) {
      throw TeacherReviewException(
        '$operation失败（HTTP ${response.statusCode}）。',
      );
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const TeacherReviewException('教师评价响应格式无效。');
    }
    return decoded.cast<String, dynamic>();
  }

  void _validateTeacherKey(String teacherKey) {
    if (!RegExp(r'^tchr_[0-9a-f]{40}$').hasMatch(teacherKey)) {
      throw const TeacherReviewException('教师评价标识无效。');
    }
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class TeacherReviewException implements Exception {
  const TeacherReviewException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TeacherReviewConflictException extends TeacherReviewException {
  const TeacherReviewConflictException() : super('评价已在其他设备修改，请刷新后重试。');
}

class TeacherReviewSuspendedException extends TeacherReviewException {
  TeacherReviewSuspendedException(this.suspendedUntil)
    : super(
        suspendedUntil == null
            ? '评价功能当前不可用。'
            : '评价功能已暂停至 ${_formatSuspendedUntil(suspendedUntil)}。',
      );

  final DateTime? suspendedUntil;
}

String _formatSuspendedUntil(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
