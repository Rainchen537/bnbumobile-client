import 'package:bnbu_me/services/me_identity_service.dart';
import 'dart:async';
import 'dart:convert';

import 'package:bnbu_me/services/personal_sync_service.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Devices implements UsageSyncStore {
  bool registered = true;
  UsageSyncDeviceRecord record = const UsageSyncDeviceRecord(
    installationId: 'fixture',
    deviceToken: 'synthetic_device',
  );
  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async =>
      registered ? record : null;
  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async {
    expect(record.installationId, this.record.installationId);
    expect(record.deviceToken, isNull, reason: 'Only invalidation is allowed');
    this.record = record;
  }
}

void main() {
  test(
    'wire ensures automatic account sync with device identity and epoch CAS',
    () async {
      final requests = <http.Request>[];
      final store = RemotePersonalSyncStore(
        syncAllowed: (_) => true,
        devices: _Devices(),
        baseUrl: 'https://fixture.invalid',
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('ensure')) {
            return http.Response('{"enabled":true,"epoch":3}', 200);
          }
          return http.Response(
            request.method == 'GET'
                ? '{"epoch":3,"version":5,"value":{"name:1":"Alias"}}'
                : '{"epoch":3,"version":6}',
            200,
          );
        }),
      );
      expect((await store.ensure('fixture')).epoch, 3);
      final snapshot = await store.fetch('fixture', 3);
      await store.put('fixture', 3, snapshot);
      expect(requests.every((r) => !r.followRedirects), isTrue);
      expect(
        requests.every(
          (r) => r.headers['Authorization'] == 'Bearer synthetic_device',
        ),
        isTrue,
      );
      expect(requests.first.method, 'POST');
      expect(requests.first.body, isEmpty);
      expect(requests.first.url.path, '/v1/personal-sync/ensure');
      expect(jsonDecode(requests.last.body), {
        'epoch': 3,
        'protocol_version': 2,
        'expected_version': 5,
        'value': {'name:1': 'Alias'},
      });
      expect(requests[1].url.queryParameters, {
        'epoch': '3',
        'protocol_version': '2',
      });
      store.dispose();
    },
  );

  for (final status in [302, 401, 409, 412, 500]) {
    test('HTTP $status cannot look like sync success', () async {
      final store = RemotePersonalSyncStore(
        syncAllowed: (_) => true,
        devices: _Devices(),
        baseUrl: 'https://fixture.invalid',
        client: MockClient(
          (_) async => http.Response('private error not surfaced', status),
        ),
      );
      await expectLater(
        store.fetch('fixture', 3),
        throwsA(
          status == 409
              ? isA<PersonalSyncConflict>()
              : status == 412
              ? isA<PersonalSyncRevoked>()
              : isA<FormatException>(),
        ),
      );
      store.dispose();
    });
  }

  test('unregistered device sends no request or registration', () async {
    var calls = 0;
    final store = RemotePersonalSyncStore(
      syncAllowed: (_) => true,
      devices: _Devices()..registered = false,
      baseUrl: 'https://fixture.invalid',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      store.ensure('fixture'),
      throwsA(isA<MeBindingRequired>()),
    );
    expect(calls, 0);
    store.dispose();
  });

  test('late 401 cannot erase a refreshed shared device identity', () async {
    final devices = _Devices();
    final sent = Completer<void>();
    final rejected = Completer<http.Response>();
    final store = RemotePersonalSyncStore(
      syncAllowed: (_) => true,
      devices: devices,
      baseUrl: 'https://fixture.invalid',
      client: MockClient((request) {
        expect(request.headers['Authorization'], 'Bearer synthetic_device');
        sent.complete();
        return rejected.future;
      }),
    );
    final pending = expectLater(
      store.fetch('fixture', 3),
      throwsFormatException,
    );
    await sent.future;
    devices.record = const UsageSyncDeviceRecord(
      installationId: 'fixture',
      deviceToken: 'synthetic_refreshed_device',
    );
    rejected.complete(http.Response('{}', 401));
    await pending;
    expect(devices.record.deviceToken, 'synthetic_refreshed_device');
    store.dispose();
  });
}
