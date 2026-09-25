import 'dart:convert';
import 'package:bnbu_me/services/app_statistics_service.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class DeviceStore implements UsageSyncStore {
  bool enrolled = true;
  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async {
    expect(email, 'student@mail.bnbu.edu.cn');
    return enrolled
        ? const UsageSyncDeviceRecord(
            installationId: 'test-only-installation',
            deviceToken: 'test-only-device-token',
          )
        : null;
  }

  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async =>
      fail('must not enroll or overwrite identity');
}

void main() {
  test(
    'existing Bearer, strict capability response and both receipt schemas',
    () async {
      final paths = <String>[];
      final transport = RemoteStatisticsTransport(
        store: DeviceStore(),
        baseUrl: 'https://stats.example',
        client: MockClient((request) async {
          paths.add(request.url.path);
          expect(
            request.headers['Authorization'],
            'Bearer test-only-device-token',
          );
          expect(request.headers.keys, isNot(contains('cookie')));
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'consent_version': 'statistics.v1',
                'app_usage_enabled': false,
                'notification_stats_enabled': true,
              }),
              200,
            );
          }
          final body = jsonDecode(request.body) as Map;
          expect(body.containsKey('username'), false);
          expect(body['consent_version'], 'statistics.v1');
          return http.Response('{"accepted":0,"duplicates":1}', 200);
        }),
      );
      expect((await transport.status('student'))['app_usage_enabled'], false);
      for (final endpoint in ['app-usage', 'notification-events']) {
        expect(
          await transport.send('student', endpoint, {
            'consent_version': 'statistics.v1',
            'consented_at': '2026-09-11T00:00:00Z',
            'events': [
              {'event_id': 'fixture'},
            ],
          }),
          200,
        );
      }
      expect(paths, [
        '/v1/devices/current/statistics',
        '/v1/devices/current/app-usage',
        '/v1/devices/current/notification-events',
      ]);
      transport.dispose();
    },
  );
  test(
    'bad receipt, invalid status, missing enrollment and oversized body fail closed',
    () async {
      final store = DeviceStore();
      var requests = 0;
      final transport = RemoteStatisticsTransport(
        store: store,
        baseUrl: 'https://stats.example',
        client: MockClient((_) async {
          requests++;
          return http.Response('{"accepted":0,"duplicates":0}', 200);
        }),
      );
      await expectLater(transport.status('student'), throwsStateError);
      await expectLater(
        transport.send('student', 'app-usage', {
          'events': [{}],
        }),
        throwsStateError,
      );
      await expectLater(
        transport.send('student', 'other', {}),
        throwsArgumentError,
      );
      await expectLater(
        transport.send('student', 'app-usage', {
          'events': ['x' * 65536],
        }),
        throwsArgumentError,
      );
      expect(requests, 2);
      store.enrolled = false;
      await expectLater(transport.status('student'), throwsStateError);
      expect(requests, 2);
      transport.dispose();
    },
  );
}
