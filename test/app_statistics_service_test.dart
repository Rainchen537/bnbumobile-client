import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bnbu_me/services/app_statistics_service.dart';
import 'package:bnbu_me/services/apple_statistics_bridge.dart';
import 'package:bnbu_me/state/app_statistics_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

class Store implements StatisticsStore {
  final data = <String, Map<String, dynamic>>{};
  Completer<void>? barrier;
  @override
  Future<Map<String, dynamic>?> load(String owner) async =>
      data[owner] == null ? null : copy(data[owner]!);
  @override
  Future<void> save(String owner, Map<String, dynamic> value) async {
    final snapshot = copy(value);
    await barrier?.future;
    data[owner] = snapshot;
  }
}

class Transport implements StatisticsTransport {
  bool enabled = true, offline = false;
  int calls = 0, code = 200;
  Completer<void>? barrier;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> status(String username) async {
    calls++;
    if (offline) throw StateError('offline');
    return {
      'consent_version': statisticsConsentVersion,
      'app_usage_enabled': enabled,
      'notification_stats_enabled': enabled,
    };
  }

  @override
  Future<int> send(
    String username,
    String endpoint,
    Map<String, dynamic> batch,
  ) async {
    sent.add({'username': username, 'endpoint': endpoint, ...copy(batch)});
    await barrier?.future;
    if (offline) throw StateError('offline');
    return code;
  }

  @override
  void dispose() {}
}

class Bridge extends AppleStatisticsBridge {
  int reads = 0;
  List<Map<String, dynamic>> values = [];
  Completer<void>? barrier;
  @override
  Future<List<Map<String, dynamic>>> readDelivered({
    required String owner,
    required DateTime consentAt,
  }) async {
    reads++;
    await barrier?.future;
    return values;
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Store store;
  late Transport transport;
  late Bridge bridge;
  late AppStatisticsService service;
  late DateTime now;
  AppStatisticsService make({TargetPlatform platform = TargetPlatform.iOS}) =>
      AppStatisticsService(
        transport: transport,
        store: store,
        bridge: bridge,
        platform: platform,
        clock: () => now,
        versionLoader: () async => '1.2.4+2026091106',
        environment: 'development',
      );
  Future<void> enable() async {
    await service.setAccount('student');
    await service.setConsent(true);
  }

  Map<String, dynamic> observed(String id, {String kind = 'ddl'}) => {
    'notification_id': id,
    'occurred_at': now.toUtc().toIso8601String(),
    'kind': kind,
    'stage': 'displayed',
    'evidence': 'observed_notification_center',
    'environment': 'development',
    'app_version': '1.2.4+2026091106',
  };
  const id1 = '11111111-1111-4111-8111-111111111111';
  const id2 = '22222222-2222-4222-8222-222222222222';
  const id3 = '33333333-3333-4333-8333-333333333333';
  setUp(() {
    store = Store();
    transport = Transport();
    bridge = Bridge();
    now = DateTime.utc(2026, 9, 11, 15, 59);
    service = make();
  });
  tearDown(() => service.dispose());

  test(
    'wire fixture contains actual client-built batches for server validation',
    () async {
      now = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await enable();
      await service.recordEntry();
      bridge.values = [observed(id1)];
      await service.poll();
      expect(transport.sent.length, 2);
      final batches = {
        for (final item in transport.sent)
          item['endpoint'] as String: {
            for (final key in ['consent_version', 'consented_at', 'events'])
              key: item[key],
          },
      };
      final path = Platform.environment['BNBU_STATISTICS_FIXTURE_PATH'];
      if (path != null) await File(path).writeAsString(jsonEncode(batches));
    },
  );

  test(
    'without new consent there is no collection, native read or request',
    () async {
      await service.setAccount('student');
      await service.recordEntry();
      await service.observeReminders();
      await service.poll();
      expect(transport.calls, 0);
      expect(bridge.reads, 0);
      expect(service.pendingCount, 0);
    },
  );
  test(
    'remote off is not implicitly enabled and no schedule stamp is made',
    () async {
      transport.enabled = false;
      await enable();
      await service.recordEntry();
      expect(
        await service.notificationPayload(
          kind: 'ddl',
          id: 1,
          triggerAt: now,
          payload: 'local-url',
        ),
        'local-url',
      );
      expect(service.pendingCount, 0);
      expect(bridge.reads, 0);
    },
  );
  test('Android remains isolated and inactive in Apple branch', () async {
    final android = make(platform: TargetPlatform.android);
    await android.setAccount('student');
    await android.setConsent(true);
    await android.recordEntry();
    expect(android.supported, false);
    expect(transport.calls, 0);
    android.dispose();
  });
  test(
    'offline retry and restart retain exact event IDs and occurrence day',
    () async {
      await enable();
      await service.recordEntry();
      transport.offline = true;
      await service.poll();
      final first = copy(transport.sent.single);
      service.dispose();
      service = make();
      now = now.add(const Duration(hours: 1)); // next Beijing day
      await service.setAccount('student');
      expect(transport.sent.last['events'], first['events']);
      expect(
        (transport.sent.last['events'] as List).single['occurred_at'],
        '2026-09-11T15:59:00.000Z',
      );
      transport.offline = false;
      now = now.add(const Duration(hours: 1));
      await service.poll();
      expect(service.pendingCount, 0);
    },
  );
  test(
    'success removes acknowledged events and repeated polling adds none',
    () async {
      await enable();
      await service.recordEntry();
      await service.poll();
      await service.poll();
      expect(transport.sent.length, 1);
      expect(service.pendingCount, 0);
      expect(
        transport.sent.single.keys,
        containsAll(['consent_version', 'consented_at', 'events']),
      );
    },
  );
  test('100-event batches with bounded replay', () async {
    await enable();
    for (var i = 0; i < 103; i++) {
      await service.recordEntry();
    }
    await service.poll();
    expect((transport.sent.single['events'] as List).length, 100);
    expect(service.pendingCount, 3);
    await service.poll();
    expect(service.pendingCount, 0);
  });
  test('expired offline events are not rewritten as new events', () async {
    await enable();
    await service.recordEntry();
    now = now.add(const Duration(days: 32));
    await service.poll();
    expect(transport.sent, isEmpty);
    expect(service.pendingCount, 0);
  });
  test(
    'schedule success, cancellation and regrouping are not observations',
    () async {
      await enable();
      final first = await service.notificationPayload(
        kind: 'ddl',
        id: 10,
        triggerAt: now.add(const Duration(hours: 1)),
        payload: 'SECRET-TITLE',
      );
      final repeat = await service.notificationPayload(
        kind: 'ddl',
        id: 10,
        triggerAt: now.add(const Duration(hours: 1)),
        payload: 'SECRET-TITLE',
      );
      expect(first, repeat); // cancelled and re-scheduled same OS instance
      final changed = await service.notificationPayload(
        kind: 'ddl',
        id: 10,
        triggerAt: now.add(const Duration(hours: 2)),
        payload: 'SECRET-TITLE',
      );
      expect(
        jsonDecode(first!)['bnbu_statistics']['notification_id'],
        isNot(jsonDecode(changed!)['bnbu_statistics']['notification_id']),
      );
      await service.poll();
      expect(transport.sent, isEmpty);
      expect(jsonEncode(store.data), isNot(contains('SECRET-TITLE')));
    },
  );
  test(
    'three actual notifications count three; a grouped notification counts one',
    () async {
      await enable();
      bridge.values = [
        observed(id1),
        observed(id2),
        observed(id3, kind: 'schedule'),
      ];
      await service.observeReminders();
      await service.observeReminders();
      await service.poll();
      final events = transport.sent.single['events'] as List;
      expect(events.length, 3);
      expect(events.where((e) => e['kind'] == 'ddl').length, 2);
      await service.poll();
      expect(transport.sent.length, 1);
    },
  );
  test(
    'read/permission unavailable, pending, failed, test and island never count',
    () async {
      await enable();
      bridge.values = [
        {...observed(id1), 'stage': 'scheduled'},
        {...observed(id2), 'evidence': 'time_elapsed'},
        {...observed(id3), 'kind': 'test'},
        {...observed(id1), 'kind': 'live_activity'},
      ];
      await service.observeReminders();
      await service.poll();
      expect(transport.sent, isEmpty);
    },
  );
  test('native extra fields cannot leak to wire', () async {
    await enable();
    bridge.values = [
      {...observed(id1), 'body': 'secret', 'title': 'secret'},
    ];
    await service.poll();
    expect(jsonEncode(transport.sent), isNot(contains('secret')));
    expect((transport.sent.single['events'] as List).single.keys.length, 9);
  });
  test(
    'a development notification cannot become a production observation after update',
    () async {
      await enable();
      bridge.values = [
        {...observed(id1), 'environment': 'production'},
      ];
      await service.observeReminders();
      expect(service.pendingCount, 0);
    },
  );
  test('different device instances have independent random IDs', () async {
    await enable();
    final payload = await service.notificationPayload(
      kind: 'ddl',
      id: 10,
      triggerAt: now,
      payload: null,
    );
    final other = AppStatisticsService(
      transport: Transport(),
      store: Store(),
      bridge: Bridge(),
      platform: TargetPlatform.iOS,
      clock: () => now,
      versionLoader: () async => '1.2.4',
    );
    await other.setAccount('student');
    await other.setConsent(true);
    final second = await other.notificationPayload(
      kind: 'ddl',
      id: 10,
      triggerAt: now,
      payload: null,
    );
    expect(
      jsonDecode(payload!)['bnbu_statistics']['notification_id'],
      isNot(jsonDecode(second!)['bnbu_statistics']['notification_id']),
    );
    other.dispose();
  });
  test(
    'withdraw immediately invalidates queued events even when storage waits',
    () async {
      await enable();
      store.barrier = Completer();
      final pending = service.recordEntry();
      final revoke = service.setConsent(false);
      expect(service.consented, false);
      store.barrier!.complete();
      await pending;
      await revoke;
      expect(service.pendingCount, 0);
      expect(transport.sent, isEmpty);
    },
  );
  test(
    'logout during native observation cannot report as another account',
    () async {
      await enable();
      bridge.values = [observed(id1)];
      bridge.barrier = Completer();
      final reading = service.observeReminders();
      await service.setAccount(null);
      await service.setAccount('different');
      bridge.barrier!.complete();
      await reading;
      expect(service.pendingCount, 0);
      expect(service.consented, false);
    },
  );
  test('429 waits an hour without fabricating new IDs', () async {
    await enable();
    await service.recordEntry();
    transport.code = 429;
    await service.poll();
    final events = transport.sent.single['events'];
    now = now.add(const Duration(minutes: 59));
    await service.poll();
    expect(transport.sent.length, 1);
    now = now.add(const Duration(minutes: 1));
    transport.code = 200;
    await service.poll();
    expect(transport.sent.last['events'], events);
    expect(service.pendingCount, 0);
  });
  test(
    'protocol rejection retains data and stops automatic poison retries',
    () async {
      await enable();
      await service.recordEntry();
      transport.code = 409;
      await service.poll();
      now = now.add(const Duration(hours: 2));
      await service.poll();
      expect(transport.sent.length, 1);
      expect(service.pendingCount, 1);
    },
  );
  test(
    're-consent clears old bindings; old notifications cannot cross epochs',
    () async {
      await enable();
      final old = await service.notificationPayload(
        kind: 'ddl',
        id: 1,
        triggerAt: now,
        payload: null,
      );
      await service.setConsent(false);
      now = now.add(const Duration(minutes: 5));
      await service.setConsent(true);
      final fresh = await service.notificationPayload(
        kind: 'ddl',
        id: 1,
        triggerAt: now,
        payload: null,
      );
      expect(old, isNot(fresh));
      bridge.values = [
        {
          ...observed(id1),
          'occurred_at': now
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
        },
      ];
      await service.observeReminders();
      expect(service.pendingCount, 0);
    },
  );
  test(
    'entry tracker ignores Face ID and focus, but counts real background return',
    () {
      final entry = AppEntryTracker();
      expect(entry.take(enabled: true), false);
      entry.unlocked = true;
      expect(entry.take(enabled: true), true);
      expect(entry.take(enabled: true), false);
      entry.inactive();
      entry.resume();
      expect(entry.take(enabled: true), false);
      entry.background();
      entry.unlocked = false;
      entry.resume();
      expect(entry.take(enabled: true), false);
      entry.unlocked = true;
      expect(entry.take(enabled: true), true);
      entry.background();
      entry.resume();
      expect(entry.take(enabled: false), false);
      expect(entry.take(enabled: true), true);
    },
  );
}
