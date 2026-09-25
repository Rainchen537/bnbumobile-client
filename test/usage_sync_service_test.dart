import 'package:bnbu_me/services/me_identity_service.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('school email is derived without retaining the submitted password', () {
    expect(
      schoolEmailForUsername(' Student01@mail.bnbu.edu.cn '),
      'student01@mail.bnbu.edu.cn',
    );
    expect(
      () => schoolEmailForUsername('student+tag'),
      throwsA(isA<UsageSyncException>()),
    );
  });

  test('unbound background usage never enrolls a school email', () async {
    var requests = 0;
    final service = RemoteUsageSyncService(
      store: _MemoryUsageSyncStore(),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    await expectLater(
      service.synchronize('student01'),
      throwsA(isA<MeBindingRequired>()),
    );
    await expectLater(
      service.heartbeat('student01'),
      throwsA(isA<MeBindingRequired>()),
    );
    expect(requests, 0);
    service.dispose();
  });

  test('heartbeat authenticates with the stored device token', () async {
    final store = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://sync.example/v1/devices/current/heartbeat',
      );
      expect(request.headers['authorization'], 'Bearer dev_existing-token');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload, {'platform': 'android', 'app_version': '1.2.0+7'});
      return http.Response('', 204);
    });
    final service = RemoteUsageSyncService(
      client: client,
      store: store,
      baseUrl: 'https://sync.example',
      platformProvider: () => 'android',
      packageInfoLoader: () async => PackageInfo(
        appName: 'BNBU.ME',
        packageName: 'me.bnbu.app',
        version: '1.2.0',
        buildNumber: '7',
      ),
    );

    await service.heartbeat('student01');
  });

  test('heartbeat retries a transient gateway failure', () async {
    final store = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    var attempts = 0;
    final service = RemoteUsageSyncService(
      client: MockClient((_) async {
        attempts++;
        return http.Response('', attempts == 1 ? 503 : 204);
      }),
      store: store,
      baseUrl: 'https://sync.example',
      platformProvider: () => 'ios',
      packageInfoLoader: () async => PackageInfo(
        appName: 'BNBU.ME',
        packageName: 'dev.example.bnbu.test',
        version: '1.2.0',
        buildNumber: '42',
      ),
      retryDelay: (_) async {},
    );

    await service.heartbeat('student01');

    expect(attempts, 2);
  });
}

class _MemoryUsageSyncStore implements UsageSyncStore {
  _MemoryUsageSyncStore({this.record});

  UsageSyncDeviceRecord? record;

  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async => record;

  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async {
    this.record = record;
  }
}
