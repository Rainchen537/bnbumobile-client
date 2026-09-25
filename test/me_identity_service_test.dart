import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:bnbu_me/services/me_identity_service.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';

class _Store implements UsageSyncStore {
  final records = <String, UsageSyncDeviceRecord>{};
  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async =>
      records[email];
  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async {
    records[email] = record;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  MeIdentityService service(
    _Store store,
    Future<http.Response> Function(http.Request) handler,
  ) => MeIdentityService(
    store: store,
    marker: () async => 'synthetic-installation-marker-00000000',
    clientFactory: () => MockClient(handler),
    packageInfoLoader: () async => PackageInfo(
      appName: 'Test',
      packageName: 'test',
      version: '1.2.5',
      buildNumber: '1',
    ),
  );

  test(
    'email resend waits forty seconds and survives page reconstruction',
    () async {
      var now = DateTime.utc(2026, 9, 26);
      var sends = 0;
      final identity = MeIdentityService(
        store: _Store(),
        marker: () async => 'synthetic-installation-marker-00000000',
        now: () => now,
        clientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/installation')) {
            return http.Response('{}', 201);
          }
          sends++;
          return http.Response(
            '{"challenge_id":"challenge","resend_after":40}',
            201,
          );
        }),
      );
      identity.setActiveOwner('first');
      await identity.requestCode('first');
      expect(identity.resendSeconds('first'), 40);
      await expectLater(
        identity.requestCode('first'),
        throwsA(isA<UsageSyncException>()),
      );
      now = now.add(const Duration(seconds: 39));
      expect(identity.resendSeconds('first'), 1);
      await expectLater(
        identity.requestCode('first'),
        throwsA(isA<UsageSyncException>()),
      );
      now = now.add(const Duration(seconds: 1));
      await identity.requestCode('first');
      expect(sends, 2);
    },
  );

  test(
    'school login and restore do not register or transmit anything',
    () async {
      var requests = 0;
      final identity = service(_Store(), (_) async {
        requests++;
        return http.Response('{}', 500);
      });
      identity.setActiveOwner('synthetic');
      await identity.restore('synthetic');
      expect(identity.isBound('synthetic'), isFalse);
      expect(requests, 0);
      await expectLater(
        identity.setSync('synthetic', true),
        throwsA(isA<MeBindingRequired>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'accounts on one installation have distinct secrets and keep independent bindings',
    () async {
      final store = _Store();
      final secrets = <String>[];
      final identity = service(store, (request) async {
        if (request.url.path.endsWith('/installation')) {
          secrets.add(request.headers['Authorization']!);
          expect(request.body, '{}');
          expect(request.followRedirects, isFalse);
          return http.Response('{"ready":true}', 201);
        }
        if (request.url.path.endsWith('/verify')) {
          final owner = secrets.length == 1 ? 'first' : 'second';
          return http.Response(
            jsonEncode({
              'email': '$owner@mail.bnbu.edu.cn',
              'device_token': 'dev_$owner',
            }),
            200,
          );
        }
        return http.Response('{"challenge_id":"synthetic-challenge"}', 201);
      });
      for (final owner in ['first', 'second']) {
        identity.setActiveOwner(owner);
        await identity.restore(owner);
        final challenge = await identity.requestCode(owner);
        await identity.verify(owner, challenge, '123456');
        expect(identity.isBound(owner), isTrue);
        expect(identity.syncEnabled(owner), isFalse);
      }
      expect(secrets[0], isNot(secrets[1]));
      expect(store.records.length, 2);
      expect(identity.isBound('first'), isFalse);
      identity.setActiveOwner('first');
      expect(identity.isBound('first'), isTrue);
      expect(identity.isBound('second'), isFalse);
      identity.setActiveOwner(null);
      expect(identity.isBound('first'), isFalse);
    },
  );

  test('late unauthorized response after A B A cannot erase A grant', () async {
    final store = _Store();
    store.records['first@mail.bnbu.edu.cn'] = const UsageSyncDeviceRecord(
      installationId: 'synthetic',
      deviceToken: 'dev_first',
    );
    final pending = Completer<http.Response>();
    final entered = Completer<void>();
    final identity = service(store, (_) async {
      entered.complete();
      return pending.future;
    });
    identity.setActiveOwner('first');
    await identity.restore('first');
    final result = identity.refresh('first');
    final assertion = expectLater(result, throwsA(isA<UsageSyncException>()));
    await entered.future;
    identity.setActiveOwner('second');
    identity.setActiveOwner('first');
    pending.complete(http.Response('{}', 401));
    await assertion;
    expect(identity.isBound('first'), isTrue);
    expect(store.records['first@mail.bnbu.edu.cn']!.deviceToken, 'dev_first');
  });

  test(
    'verification completed after account switch cannot publish authorization',
    () async {
      final store = _Store();
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      final identity = service(store, (request) async {
        entered.complete();
        return pending.future;
      });
      identity.setActiveOwner('first');
      final verification = identity.verify('first', 'challenge', '123456');
      final assertion = expectLater(
        verification,
        throwsA(isA<UsageSyncException>()),
      );
      await entered.future;
      identity.setActiveOwner('second');
      pending.complete(
        http.Response(
          '{"email":"first@mail.bnbu.edu.cn","device_token":"dev_late"}',
          200,
        ),
      );
      await assertion;
      expect(store.records, isEmpty);
      expect(identity.isBound('first'), isFalse);
      expect(identity.isBound('second'), isFalse);
    },
  );

  test(
    'restore retains local binding; synchronization remains opt in',
    () async {
      final store = _Store();
      store.records['first@mail.bnbu.edu.cn'] = const UsageSyncDeviceRecord(
        installationId: 'synthetic-installation-marker-00000000',
        deviceToken: 'dev_existing',
      );
      var requests = 0;
      final identity = service(store, (_) async {
        requests++;
        return http.Response('{}', 500);
      });
      identity.setActiveOwner('first');
      await identity.restore('first');
      expect(identity.isBound('first'), isTrue);
      expect(identity.syncEnabled('first'), isFalse);
      expect(
        store.records['first@mail.bnbu.edu.cn']!.deviceToken,
        'dev_existing',
      );
      expect(requests, 0);
    },
  );
}
