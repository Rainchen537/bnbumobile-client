import 'dart:async';

import 'package:bnbu_me/l10n/bnbu_localizations.dart';
import 'package:bnbu_me/services/app_statistics_service.dart';
import 'package:bnbu_me/widgets/statistics_consent_settings.dart';
import 'package:bnbu_me/widgets/statistics_privacy_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_statistics_service_test.dart' show Store, Transport, Bridge;

class _FailingStore extends Store {
  @override
  Future<void> save(String owner, Map<String, dynamic> value) async =>
      throw StateError('disk unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Store store;
  late Transport transport;
  late Bridge bridge;
  late AppStatisticsService service;
  final now = DateTime.utc(2026, 9, 11, 12);
  AppStatisticsService make({Store? disk, TargetPlatform? platform}) =>
      AppStatisticsService(
        store: disk ?? store,
        transport: transport,
        bridge: bridge,
        platform: platform ?? TargetPlatform.iOS,
        clock: () => now,
        versionLoader: () async => '1.2.4+2026091107',
      );
  setUp(() {
    store = Store();
    transport = Transport();
    bridge = Bridge();
    service = make();
  });
  tearDown(() => service.dispose());

  test(
    'login acceptance persists before auth but cannot collect or send',
    () async {
      await service.acceptLoginPrivacy('student');
      await service.recordEntry();
      await service.poll();
      expect(service.hasAccount, false);
      expect(transport.calls, 0);
      expect(bridge.reads, 0);
      expect(transport.sent, isEmpty);
      await service.setAccount('student');
      expect(service.consented, true);
      expect(service.appUsageEnabled, true);
      expect(service.consentAt, now);
      expect(service.pendingCount, 0);
    },
  );

  test('old restored login stays unknown without collection', () async {
    await service.setAccount('student');
    await service.recordEntry();
    expect(service.hasConsentChoice, false);
    expect(service.consented, false);
    expect(transport.calls, 0);
    expect(bridge.reads, 0);
  });

  test('server-off state is not overridden by login default', () async {
    transport.enabled = false;
    await service.acceptLoginPrivacy('student');
    await service.setAccount('student');
    await service.recordEntry();
    expect(service.consented, true);
    expect(service.appUsageEnabled, false);
    expect(service.remindersEnabled, false);
    expect(transport.sent, isEmpty);
    expect(service.pendingCount, 0);
  });

  for (final legacy in [false, true]) {
    test('withdrawal is preserved after relogin, legacy=$legacy', () async {
      await service.setAccount('student');
      await service.setConsent(false);
      expect(service.hasConsentChoice, true);
      if (legacy) store.data[service.owner!]!.remove('consent_choice');
      await service.setAccount(null);
      await service.acceptLoginPrivacy('student');
      await service.setAccount('student');
      expect(service.consented, false);
      expect(service.hasConsentChoice, true);
      expect(transport.calls, 0);
    });
  }

  test(
    'accepted timestamp and offline queue survive repeated login agreement',
    () async {
      await service.acceptLoginPrivacy('student');
      await service.setAccount('student');
      transport.offline = true;
      await service.recordEntry();
      final snapshot = Map<String, dynamic>.from(store.data[service.owner!]!);
      await service.setAccount(null);
      await service.acceptLoginPrivacy('student');
      expect(store.data.values.single, snapshot);
      await service.setAccount('student');
      expect(service.pendingCount, 1);
      expect(service.consentAt, now);
    },
  );

  test('choices stay per account; Android remains isolated', () async {
    await service.acceptLoginPrivacy('first');
    await service.setAccount('second');
    expect(service.hasConsentChoice, false);
    await service.setAccount('first');
    expect(service.consented, true);
    final android = make(platform: TargetPlatform.android);
    addTearDown(android.dispose);
    await android.acceptLoginPrivacy('android');
    expect(store.data.length, 1);
  });

  test('failed persistence never becomes consent', () async {
    service.dispose();
    service = make(disk: _FailingStore());
    await expectLater(service.acceptLoginPrivacy('student'), throwsStateError);
    await service.setAccount('student');
    expect(service.hasConsentChoice, false);
    await expectLater(service.setConsent(true), throwsStateError);
    expect(service.consented, false);
    expect(transport.calls, 0);
  });

  test(
    'account switch while loading choice does not grant the other account',
    () async {
      store.barrier = Completer<void>();
      final accepting = service.acceptLoginPrivacy('first');
      await Future<void>.delayed(Duration.zero);
      final switching = service.setAccount('second');
      store.barrier!.complete();
      await accepting;
      await switching;
      expect(service.hasConsentChoice, false);
      expect(service.consented, false);
      expect(transport.calls, 0);
    },
  );

  Future<void> pumpGate(
    WidgetTester tester, {
    bool ready = true,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [BnbuLocalizations.delegate],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: StatisticsLoginGate(
          service: service,
          ready: ready,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets('restored notice persists decline at width $width large text', (
      tester,
    ) async {
      service.dispose();
      service = make();
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await service.setAccount('student');
      await pumpGate(tester, ready: false, scale: 1.5);
      expect(find.text('home'), findsOneWidget);
      await pumpGate(tester, scale: 1.5);
      expect(find.text('Privacy notice update'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.tap(find.text('Continue without statistics'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(service.hasConsentChoice, true);
      expect(service.consented, false);
      await service.setAccount(null);
      await service.setAccount('student');
      await tester.pumpAndSettle();
      expect(find.text('Privacy notice update'), findsNothing);
      expect(transport.calls, 0);
    });
  }

  testWidgets('restored agreement enables; settings re-enable without popup', (
    tester,
  ) async {
    service.dispose();
    service = make();
    await service.setAccount('student');
    await pumpGate(tester);
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(service.consented, true);
    expect(find.text('home'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatisticsConsentSettings(service: service)),
      ),
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(service.consented, false);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.consented, true);
  });
}
