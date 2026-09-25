import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/landmark_review.dart';
import 'network_retry.dart';
import 'teacher_review_service.dart';

abstract class LandmarkReviewService {
  Future<CommunityPolicy> readPolicy(String id);
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  });
  Future<LandmarkReviewMine> mine(String username, String id);
  Future<LandmarkReviewMine> rate(
    String username,
    String id, {
    required int version,
    required int stars,
  });
  Future<void> comment(
    String username,
    String id, {
    required int version,
    required String body,
    required bool anonymous,
    required String requestId,
    String? replyTo,
  });
  Future<void> remove(String username, String id, LandmarkReview review);
  Future<void> helpful(
    String username,
    String id,
    String commentId,
    bool active,
  );
  Future<void> syncProfile(
    String username, {
    required String name,
    required int version,
    List<int>? avatar,
  });
  void dispose();
}

class RemoteLandmarkReviewService implements LandmarkReviewService {
  RemoteLandmarkReviewService({
    http.Client? client,
    RemoteTeacherReviewService? identity,
    String? baseUrl,
  }) : _client = client ?? createAppHttpClient(),
       _identityOverride = identity,
       _baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       );
  final http.Client _client;
  final RemoteTeacherReviewService? _identityOverride;
  late final _identity =
      _identityOverride ??
      RemoteTeacherReviewService(client: _client, baseUrl: _baseUrl);
  final String _baseUrl;
  final Map<String, String> _reviewSnapshots = {};
  void _id(String id) {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id)) {
      throw const FormatException('landmark id');
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, Object>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 12));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 512 * 1024) {
        throw const FormatException('review response limit');
      }
    }
    if (response.statusCode == 401) {
      throw const LandmarkReviewHttpException(401, '登录状态已失效，请重试');
    }
    if (response.statusCode == 409) {
      if (utf8
          .decode(bytes, allowMalformed: true)
          .contains('review_snapshot_changed')) {
        throw const LandmarkReviewHttpException(409, '评价数据已更新，请刷新后继续。');
      }
      throw const LandmarkReviewHttpException(409, '评价已在其他设备修改，请刷新后重试。');
    }
    if (response.statusCode == 403) {
      throw const LandmarkReviewHttpException(403, '评价功能当前不可用。');
    }
    if (response.statusCode == 429) {
      throw const LandmarkReviewHttpException(429, '暂未到可修改评分时间，请稍后重试');
    }
    if (response.statusCode == 426) {
      throw const LandmarkReviewHttpException(426, '请升级客户端后使用ME生活');
    }
    if (response.statusCode == 404) {
      throw const LandmarkReviewHttpException(404, '地标已下架或不存在');
    }
    if (response.statusCode != 200) {
      throw LandmarkReviewHttpException(response.statusCode, '评价服务暂不可用');
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  @override
  Future<CommunityPolicy> readPolicy(String id) async {
    _id(id);
    return CommunityPolicy.fromJson(
      await _request('GET', '/v2/public/community/policy?topic=landmark:$id'),
    );
  }

  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  }) async {
    _id(id);
    final key = '$id:$sort';
    if (rootId == null && offset == 0) _reviewSnapshots.remove(key);
    final snapshot = offset > 0 ? _reviewSnapshots[key] : null;
    final data = await _request(
      'GET',
      '/v2/public/landmarks/$id/community?include_external=true&offset=$offset&sort=$sort${rootId == null ? '' : '&root_id=$rootId'}${snapshot == null || rootId != null ? '' : '&snapshot_version=$snapshot'}',
    );
    if (rootId == null && data['snapshot_version'] is String) {
      _reviewSnapshots[key] = data['snapshot_version'] as String;
    }
    return LandmarkReviewPage.fromJson(data);
  }

  @override
  Future<LandmarkReviewMine> mine(String username, String id) async {
    _id(id);
    final token = await _identity.existingReviewDeviceToken(username);
    if (token == null) return const LandmarkReviewMine();
    try {
      return LandmarkReviewMine.fromJson(
        await _request('GET', '/v2/landmarks/$id/community/mine', token: token),
      );
    } on LandmarkReviewHttpException catch (e) {
      if (e.status != 401) rethrow;
      await _identity.invalidateReviewDeviceToken(username);
      return const LandmarkReviewMine();
    }
  }

  Future<Map<String, dynamic>> _write(
    String username,
    String method,
    String path,
    Map<String, Object>? body,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _identity.ensureReviewDeviceToken(
        username,
        consentVersion: landmarkReviewConsentVersion,
      );
      try {
        return await _request(method, path, token: token, body: body);
      } on LandmarkReviewHttpException catch (e) {
        if (e.status != 401 || attempt == 1) rethrow;
        await _identity.invalidateReviewDeviceToken(username);
      }
    }
    throw const LandmarkReviewHttpException(401, '登录状态已失效，请重试');
  }

  @override
  Future<LandmarkReviewMine> rate(
    String username,
    String id, {
    required int version,
    required int stars,
  }) async {
    _id(id);
    if (stars < 1 || stars > 5 || version < 0) {
      throw const FormatException('rating');
    }
    return LandmarkReviewMine.fromJson(
      await _write(username, 'PUT', '/v2/landmarks/$id/community/rating', {
        'expected_version': version,
        'stars': stars,
        'consent_version': landmarkReviewConsentVersion,
      }),
    );
  }

  @override
  Future<void> comment(
    String username,
    String id, {
    required int version,
    required String body,
    required bool anonymous,
    required String requestId,
    String? replyTo,
  }) async {
    _id(id);
    await _write(username, 'PUT', '/v2/landmarks/$id/community/comment', {
      'expected_version': version,
      'body': body,
      'anonymous': anonymous,
      'request_id': requestId,
      if (replyTo != null) 'reply_to': replyTo,
      'consent_version': landmarkReviewConsentVersion,
    });
  }

  @override
  Future<void> remove(String username, String id, LandmarkReview review) async {
    _id(id);
    await _write(
      username,
      'DELETE',
      '/v2/landmarks/$id/community/comments/${review.id}?expected_version=${review.version}',
      null,
    );
  }

  @override
  Future<void> helpful(
    String username,
    String id,
    String commentId,
    bool active,
  ) async {
    _id(id);
    await _write(
      username,
      'PUT',
      '/v2/landmarks/$id/community/comments/$commentId/helpful',
      {'active': active},
    );
  }

  @override
  Future<void> syncProfile(
    String username, {
    required String name,
    required int version,
    List<int>? avatar,
  }) async {
    await _write(username, 'PUT', '/v2/community/profile', {
      'display_name': name,
      'expected_version': version,
      if (avatar != null) 'avatar_base64': base64Encode(avatar),
      'consent_version': landmarkReviewConsentVersion,
    });
  }

  /// Reads an existing community identity without enrolling or publishing one.
  Future<String?> publicAvatarSeed(String username) async {
    final token = await _identity.existingReviewDeviceToken(username);
    if (token == null) return null;
    final data = await _request('GET', '/v2/community/profile', token: token);
    return data['public_seed'] as String?;
  }

  Future<LandmarkReview> readComment(String id, String commentId) async {
    _id(id);
    final data = await _request(
      'GET',
      '/v2/public/landmarks/$id/community/comments/$commentId',
    );
    return LandmarkReview.fromJson(
      Map<String, dynamic>.from(data['comment'] as Map),
    );
  }

  @override
  void dispose() {
    if (_identityOverride == null) _identity.dispose();
    _client.close();
  }
}

class LandmarkReviewHttpException implements Exception {
  const LandmarkReviewHttpException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Local placeholders never use school identity as the image seed. The hash is
/// only a namespaced storage key; an existing server identity wins on refresh.
class CommunityAvatarSeedStore {
  String _key(String username) =>
      'community.public-avatar.v1.${sha256.convert(utf8.encode('${AppConfig.syncServiceBaseUrl}:${username.trim().toLowerCase()}'))}';
  Future<String> local(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(username);
    final existing = prefs.getString(key);
    if (existing != null) return existing;
    final random = Random.secure();
    final value = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString(key, value);
    return value;
  }

  Future<String?> refresh(String username) async {
    final service = RemoteLandmarkReviewService();
    try {
      final remote = await service.publicAvatarSeed(username);
      if (remote != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key(username), remote);
      }
      return remote;
    } finally {
      service.dispose();
    }
  }
}
