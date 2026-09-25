import 'me_identity_service.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/personal_sync_data.dart';
import 'network_retry.dart';
import 'usage_sync_service.dart';
import 'sync/account_sync_storage.dart';
import 'sync/device_session_provider.dart';

class PersonalSyncRevoked implements Exception {}

class PersonalSyncConflict implements Exception {}

class PersonalSyncControl {
  const PersonalSyncControl(this.enabled, this.epoch);
  final bool enabled;
  final int epoch;
  factory PersonalSyncControl.parse(Map<String, dynamic> value) {
    if (value['enabled'] is! bool ||
        value['epoch'] is! int ||
        (value['epoch'] as int) < 0) {
      throw const FormatException('Invalid sync control');
    }
    return PersonalSyncControl(value['enabled'] as bool, value['epoch'] as int);
  }
}

class PersonalSyncSnapshot {
  const PersonalSyncSnapshot(this.version, this.value);
  final int version;
  final PersonalSyncData value;
}

abstract interface class PersonalSyncStore {
  Future<Map<String, dynamic>?> loadLocal(String owner);
  Future<void> saveLocal(String owner, Map<String, dynamic> value);
  Future<PersonalSyncControl> ensure(String owner);
  Future<PersonalSyncSnapshot> fetch(String owner, int epoch);
  Future<void> put(String owner, int epoch, PersonalSyncSnapshot snapshot);
  void dispose();
}

class RemotePersonalSyncStore implements PersonalSyncStore {
  RemotePersonalSyncStore({
    http.Client? client,
    UsageSyncStore? devices,
    String? baseUrl,
    bool Function(String owner)? syncAllowed,
  }) : _client = client ?? createAppHttpClient(),
       _syncAllowed = syncAllowed ?? MeIdentityService.shared.syncEnabled,
       _ownsClient = client == null,
       _devices = devices ?? SecureUsageSyncStore(),
       _baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       );
  final http.Client _client;
  final bool _ownsClient;
  final bool Function(String owner) _syncAllowed;
  final UsageSyncStore _devices;
  final String _baseUrl;
  late final _local = SharedPreferencesAsync();
  String _key(String owner) =>
      'personal-sync.v1.${sha256.convert(utf8.encode(owner))}';

  @override
  Future<Map<String, dynamic>?> loadLocal(String owner) async {
    return AccountSyncStorage.shared.read(owner, 'personal-sync-me-v1');
  }

  @override
  Future<void> saveLocal(String owner, Map<String, dynamic> value) async {
    await AccountSyncStorage.shared.write(owner, 'personal-sync-me-v1', value);
    await AccountSyncStorage.shared.read(owner, 'personal-sync-me-v1');
    await _local.remove(_key(owner));
  }

  Future<Map<String, dynamic>> _request(
    String owner,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!_syncAllowed(owner)) {
      throw const MeBindingRequired();
    }
    final token = await DeviceSessionProvider(store: _devices).token(owner);
    final request =
        http.Request(method, Uri.parse('$_baseUrl/v1/personal-sync/$path'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 412) {
      await response.stream.listen((_) {}).cancel();
      throw PersonalSyncRevoked();
    }
    if (response.statusCode == 409) {
      await response.stream.listen((_) {}).cancel();
      throw PersonalSyncConflict();
    }
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      if (response.statusCode == 401) {
        await DeviceSessionProvider(
          store: _devices,
        ).invalidate(owner, token, origin: _baseUrl);
      }
      throw const FormatException('Personal sync unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 540 * 1024) {
        throw const FormatException('Sync response too large');
      }
    }
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  }

  @override
  Future<PersonalSyncControl> ensure(String owner) async =>
      PersonalSyncControl.parse(await _request(owner, 'POST', 'ensure'));
  @override
  Future<PersonalSyncSnapshot> fetch(String owner, int epoch) async {
    final result = await _request(
      owner,
      'GET',
      'data?epoch=$epoch&protocol_version=2',
    );
    if (result['epoch'] != epoch ||
        result['version'] is! int ||
        (result['version'] as int) < 0) {
      throw const FormatException('Invalid sync snapshot');
    }
    return PersonalSyncSnapshot(
      result['version'] as int,
      validatePersonalData(result['value']),
    );
  }

  @override
  Future<void> put(
    String owner,
    int epoch,
    PersonalSyncSnapshot snapshot,
  ) async {
    validatePersonalData(snapshot.value);
    final result = await _request(owner, 'PUT', 'data', {
      'epoch': epoch,
      'protocol_version': 2,
      'expected_version': snapshot.version,
      'value': snapshot.value,
    });
    if (result['epoch'] != epoch || result['version'] != snapshot.version + 1) {
      throw const FormatException('Invalid sync receipt');
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
