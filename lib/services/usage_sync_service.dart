import 'sync/device_session_provider.dart';
import 'sync/me_installation_store.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import 'device_identity_service.dart';
import 'network_retry.dart';
import 'secure_storage_options.dart';

const usageDataConsentVersion = 'usage-status.2026-09-02';

abstract interface class UsageSyncService {
  Future<void> synchronize(String username);

  Future<void> heartbeat(String username);

  void dispose();
}

class RemoteUsageSyncService implements UsageSyncService {
  RemoteUsageSyncService({
    http.Client? client,
    UsageSyncStore? store,
    Future<PackageInfo> Function()? packageInfoLoader,
    String? baseUrl,
    String? Function()? platformProvider,
    PhysicalDeviceIdentityProvider? deviceIdentityProvider,
    Future<void> Function(Duration delay)? retryDelay,
  }) : _client = client ?? createAppHttpClient(),
       _ownsClient = client == null,
       _store = store ?? SecureUsageSyncStore(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       ),
       _platformProvider = platformProvider ?? _currentPlatform,
       _retryDelay = retryDelay ?? Future<void>.delayed;

  final http.Client _client;
  final bool _ownsClient;
  final UsageSyncStore _store;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final String _baseUrl;
  final String? Function() _platformProvider;
  final Future<void> Function(Duration delay) _retryDelay;

  @override
  Future<void> synchronize(String username) => DeviceSessionProvider.refresh(
    '$_baseUrl:${schoolEmailForUsername(username)}',
    () => _synchronize(username),
  );

  Future<void> _synchronize(String username) async {
    await DeviceSessionProvider(store: _store).token(username);
  }

  @override
  Future<void> heartbeat(String username) async {
    final email = schoolEmailForUsername(username);
    final token = await DeviceSessionProvider(store: _store).token(username);
    final metadata = await _metadata();
    final response = await _requestWithRetry(
      () => _client
          .post(
            Uri.parse('$_baseUrl/v1/devices/current/heartbeat'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'platform': metadata.platform,
              'app_version': metadata.appVersion,
            }),
          )
          .timeout(const Duration(seconds: 12)),
    );
    if (response.statusCode == 204) {
      return;
    }
    if (response.statusCode == 401) {
      await DeviceSessionProvider(
        store: _store,
      ).invalidate(email, token, origin: _baseUrl);
      await synchronize(username);
      return;
    }
    if (response.statusCode == 403) {
      await synchronize(username);
      return;
    }
    throw UsageSyncException('活跃状态同步失败（HTTP ${response.statusCode}）。');
  }

  Future<_UsageMetadata> _metadata() async {
    final platform = _platformProvider();
    if (platform == null) {
      throw const UsageSyncException('当前平台不支持前台活跃状态共享。');
    }
    final packageInfo = await _packageInfoLoader();
    final version = packageInfo.version.trim();
    final buildNumber = packageInfo.buildNumber.trim();
    final appVersion = buildNumber.isEmpty ? version : '$version+$buildNumber';
    if (appVersion.isEmpty) {
      throw const UsageSyncException('无法读取当前 App 版本。');
    }
    return _UsageMetadata(
      platform: platform,
      appVersion: appVersion,
      deviceLabel: switch (platform) {
        'ios' => 'iOS device',
        'android' => 'Android device',
        'macos' => 'Mac device',
        'windows' => 'Windows device',
        _ => 'BNBU device',
      },
    );
  }

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
        throw const UsageSyncException('服务端网络连接不稳定，请稍后重试。');
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static String? _currentPlatform() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      _ => null,
    };
  }
}

abstract interface class UsageSyncStore {
  Future<UsageSyncDeviceRecord?> loadDevice(String email);

  Future<void> saveDevice(String email, UsageSyncDeviceRecord record);
}

class SecureUsageSyncStore implements UsageSyncStore {
  SecureUsageSyncStore({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(mOptions: macOsSecureStorageOptions);

  final FlutterSecureStorage _secureStorage;

  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async {
    final raw = await _secureStorage.read(key: await _deviceKey(email));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final installationId = data['installation_id'];
      final deviceToken = data['device_token'];
      if (installationId is! String || installationId.length < 32) {
        return null;
      }
      if (deviceToken != null && deviceToken is! String) {
        return null;
      }
      return UsageSyncDeviceRecord(
        installationId: installationId,
        deviceToken: deviceToken as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async {
    return _secureStorage.write(
      key: await _deviceKey(email),
      value: jsonEncode({
        'installation_id': record.installationId,
        'device_token': record.deviceToken,
      }),
    );
  }

  Future<String> _deviceKey(String email) async =>
      'bnbu.me.device.v1.${await MeInstallationStore.marker()}.${_emailKey(email)}';

  String _emailKey(String email) =>
      sha256.convert(utf8.encode(email)).toString();
}

class UsageSyncDeviceRecord {
  const UsageSyncDeviceRecord({
    required this.installationId,
    required this.deviceToken,
  });

  final String installationId;
  final String? deviceToken;
}

class UsageSyncException implements Exception {
  const UsageSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

String schoolEmailForUsername(String username) {
  final localPart = username.trim().split('@').first.toLowerCase();
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(localPart)) {
    throw const UsageSyncException('无法从当前账号生成有效的学校邮箱。');
  }
  return '$localPart@mail.bnbu.edu.cn';
}

class _UsageMetadata {
  const _UsageMetadata({
    required this.platform,
    required this.appVersion,
    required this.deviceLabel,
  });

  final String platform;
  final String appVersion;
  final String deviceLabel;
}
