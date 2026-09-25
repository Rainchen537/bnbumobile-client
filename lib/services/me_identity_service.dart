import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import 'network_retry.dart';
import 'sync/device_session_provider.dart';
import 'sync/me_installation_store.dart';
import 'usage_sync_service.dart';

class MeBindingRequired implements Exception {
  const MeBindingRequired();
  @override
  String toString() => '请先绑定 ME 账户后使用此功能';
}

/// One device-bound authorization shared by all BNBU.ME consumers. School
/// credentials are not an input to this service.
class MeIdentityService extends ChangeNotifier {
  MeIdentityService({
    UsageSyncStore? store,
    FlutterSecureStorage? secureStorage,
    Future<String> Function()? marker,
    http.Client Function()? clientFactory,
    Future<PackageInfo> Function()? packageInfoLoader,
    DateTime Function()? now,
  }) : _store = store ?? SecureUsageSyncStore(),
       _secure = secureStorage ?? MeInstallationStore.secure,
       _marker = marker ?? MeInstallationStore.marker,
       _clientFactory = clientFactory ?? createAppHttpClient,
       _packageInfo = packageInfoLoader ?? PackageInfo.fromPlatform,
       _now = now ?? DateTime.now;
  static final shared = MeIdentityService();
  final DateTime Function() _now;
  final Map<String, DateTime> _resendAt = {};
  int resendSeconds(String owner) {
    final until = _resendAt[_email(owner)];
    if (until == null) return 0;
    final ms = until.difference(_now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  final UsageSyncStore _store;
  final FlutterSecureStorage _secure;
  final Future<String> Function() _marker;
  final http.Client Function() _clientFactory;
  final Future<PackageInfo> Function() _packageInfo;
  String? _activeEmail;
  int _generation = 0;
  bool isCurrent(String owner) => _activeEmail == _email(owner);
  void setActiveOwner(String? owner) {
    final email = owner == null ? null : _email(owner);
    if (_activeEmail == email) return;
    _activeEmail = email;
    _generation++;
    notifyListeners();
  }

  void _requireCurrent(String owner, int generation) {
    if (!isCurrent(owner) || generation != _generation) {
      throw const UsageSyncException('登录账号已变化，请返回当前账号重新操作。');
    }
  }

  final Map<String, bool> _bound = {};
  final Map<String, bool> _sync = {};
  final Map<String, Future<void>> _restores = {};
  final Map<String, DateTime> _checked = {};
  final Map<String, Future<void>> _refreshes = {};
  String _email(String owner) => schoolEmailForUsername(owner);
  bool isBound(String? owner) =>
      owner != null && isCurrent(owner) && _bound[_email(owner)] == true;
  bool syncEnabled(String? owner) =>
      isBound(owner) && _sync[_email(owner!)] == true;

  Future<String> _key(String email) async =>
      'bnbu.me.installation.${await _marker()}.${sha256.convert(utf8.encode(email))}';
  Future<String> _secret(String email) async {
    final key = await _key(email);
    var value = await _secure.read(key: key);
    if (value == null) {
      value = 'mei_${MeInstallationStore.randomSecret()}';
      await _secure.write(key: key, value: value);
    }
    return value;
  }

  Future<void> restore(String owner) {
    final email = _email(owner);
    return _restores.putIfAbsent(email, () async {
      final record = await _store.loadDevice(email);
      _bound[email] = record?.deviceToken != null;
      _sync[email] =
          await _secure.read(key: '${await _key(email)}.sync') == 'true';
      notifyListeners();
    });
  }

  Future<void> setSync(String owner, bool enabled) async {
    final generation = _generation;
    _requireCurrent(owner, generation);
    if (!isBound(owner)) throw const MeBindingRequired();
    final email = _email(owner);
    await _request(email, '/v2/me/sync', body: {'enabled': enabled});
    _requireCurrent(owner, generation);
    await _secure.write(key: '${await _key(email)}.sync', value: '$enabled');
    _sync[email] = enabled;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _request(
    String email,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final generation = _generation;
    _requireCurrent(email, generation);
    final client = _clientFactory();
    try {
      final uri = Uri.parse(
        '${AppConfig.normalizedHttpsBaseUrl(AppConfig.syncServiceBaseUrl, settingName: 'SYNC_SERVICE_BASE_URL')}$path',
      );
      final device = await _store.loadDevice(email);
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer ${await _secret(email)}',
          'Content-Type': 'application/json',
          if (device?.deviceToken != null)
            'X-ME-Device-Token': device!.deviceToken!,
        });
      if (body != null) request.body = jsonEncode(body);
      _requireCurrent(email, generation);
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 25));
      final bytes = <int>[];
      await for (final chunk in streamed.stream.timeout(
        const Duration(seconds: 25),
      )) {
        if (bytes.length + chunk.length > 128 * 1024) {
          throw const UsageSyncException('身份服务响应过大');
        }
        bytes.addAll(chunk);
      }
      final response = http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
      );
      _requireCurrent(email, generation);
      if (response.statusCode == 401 && path != '/v2/me/installation') {
        await invalidate(email, expectedToken: device?.deviceToken);
        throw const MeBindingRequired();
      }
      if (response.statusCode == 429 && path == '/v2/me/email-challenges') {
        final retry = int.tryParse(response.headers['retry-after'] ?? '') ?? 40;
        _resendAt[email] = _now().add(Duration(seconds: retry.clamp(1, 3600)));
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? code;
        try {
          code =
              (jsonDecode(response.body)['detail'] as Map?)?['code'] as String?;
        } catch (_) {}
        throw UsageSyncException(switch (code) {
          'me_email_not_configured' => '邮箱验证尚未开放，请稍后再试。',
          'me_email_delivery_failed' => '验证邮件发送失败，请稍后重试。',
          'me_code_invalid_or_expired' => '验证码错误或已过期，请重新获取。',
          'me_verification_rate_limited' => '操作过于频繁，请稍后再试。',
          _ => 'ME 身份服务暂时不可用，请稍后重试。',
        });
      }
      _requireCurrent(email, generation);
      return (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } finally {
      client.close();
    }
  }

  Future<String> requestCode(String owner) {
    final generation = _generation;
    return DeviceSessionProvider.mutate('me-code:${_email(owner)}', () async {
      _requireCurrent(owner, generation);
      final email = _email(owner);
      if (resendSeconds(owner) > 0) {
        throw const UsageSyncException('操作过于频繁，请稍后再试。');
      }
      await _request(email, '/v2/me/installation', body: {});
      _requireCurrent(owner, generation);
      final result = await _request(
        email,
        '/v2/me/email-challenges',
        body: {'email': email},
      );
      _requireCurrent(owner, generation);
      final seconds = (result['resend_after'] as int? ?? 40).clamp(40, 3600);
      _resendAt[email] = _now().add(Duration(seconds: seconds));
      return result['challenge_id'] as String;
    });
  }

  Future<void> verify(String owner, String challenge, String code) async {
    final generation = _generation;
    _requireCurrent(owner, generation);
    final email = _email(owner);
    final info = await _packageInfo();
    final result = await _request(
      email,
      '/v2/me/email-challenges/verify',
      body: {
        'challenge_id': challenge,
        'code': code.trim(),
        'platform': defaultTargetPlatform.name,
        'device_label': 'BNBU.ME ${defaultTargetPlatform.name}',
        'app_version': '${info.version}+${info.buildNumber}',
      },
    );
    _requireCurrent(owner, generation);
    if (result['email'] != email || result['device_token'] is! String) {
      throw const MeBindingRequired();
    }
    await _store.saveDevice(
      email,
      UsageSyncDeviceRecord(
        installationId: await _marker(),
        deviceToken: result['device_token'] as String,
      ),
    );
    _requireCurrent(owner, generation);
    await _secure.write(key: '${await _key(email)}.sync', value: 'false');
    _sync[email] = false;
    _bound[email] = true;
    notifyListeners();
  }

  Future<void> refresh(String owner) {
    final key = '${_email(owner)}:$_generation';
    final existing = _refreshes[key];
    if (existing != null) return existing;
    final future = _refresh(owner);
    _refreshes[key] = future;
    return future.whenComplete(() {
      _refreshes.remove(key);
    });
  }

  Future<void> _refresh(String owner) async {
    if (!isCurrent(owner)) return;
    final generation = _generation;
    final email = _email(owner);
    final last = _checked[email];
    if (last != null && DateTime.now().difference(last).inMinutes < 5) return;
    await restore(owner);
    _requireCurrent(owner, generation);
    if (!isBound(owner)) return;
    final result = await _request(email, '/v2/me/status');
    _requireCurrent(owner, generation);
    if (result['bound'] != true || result['email'] != email) {
      await invalidate(owner);
    } else {
      final enabled = result['cloud_sync_enabled'] == true;
      if (_sync[email] != enabled) {
        await _secure.write(
          key: '${await _key(email)}.sync',
          value: '$enabled',
        );
        _requireCurrent(owner, generation);
        _sync[email] = enabled;
        notifyListeners();
      }
      _checked[email] = DateTime.now();
    }
  }

  Future<Map<String, dynamic>> legacyData(String owner) =>
      _request(_email(owner), '/v2/me/legacy-data');
  Future<Map<String, dynamic>> recoverData(
    String owner,
    List<String> domains, {
    List<String> memoryIds = const [],
  }) {
    _requireCurrent(owner, _generation);
    return _request(
      _email(owner),
      '/v2/me/legacy-data/recover',
      body: {'domains': domains, 'memory_ids': memoryIds},
    );
  }

  Future<List<Map<String, dynamic>>> devices(String owner) async {
    final result = await _request(_email(owner), '/v2/me/devices');
    return (result['devices'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> revoke(String owner, String deviceId) async {
    _requireCurrent(owner, _generation);
    await _request(
      _email(owner),
      '/v2/me/devices/revoke',
      body: {'device_id': deviceId},
    );
    _checked.remove(_email(owner));
    await refresh(owner);
  }

  void forgetBinding(String owner) {
    _bound[_email(owner)] = false;
    notifyListeners();
  }

  Future<void> invalidate(String owner, {String? expectedToken}) async {
    final email = _email(owner);
    final record = await _store.loadDevice(email);
    if (expectedToken != null && record?.deviceToken != expectedToken) return;
    if (record != null) {
      await _store.saveDevice(
        email,
        UsageSyncDeviceRecord(
          installationId: record.installationId,
          deviceToken: null,
        ),
      );
    }
    _bound[email] = false;
    notifyListeners();
  }
}
