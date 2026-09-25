import 'package:bnbu_me/l10n/bnbu_localizations.dart';
import 'package:bnbu_me/widgets/statistics_consent_settings.dart';
import 'package:bnbu_me/services/app_statistics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_statistics_service_test.dart' show Store, Transport, Bridge;

void main() {
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets(
      'explicit opt-in, cancellation and withdrawal at width $width',
      (tester) async {
        tester.view.reset();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final transport = Transport()..enabled = false;
        final service = AppStatisticsService(
          transport: transport,
          store: Store(),
          bridge: Bridge(),
          platform: TargetPlatform.iOS,
          versionLoader: () async => '1.2.4',
        );
        await service.setAccount('student');
        addTearDown(service.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [BnbuLocalizations.delegate],
            home: Scaffold(body: StatisticsConsentSettings(service: service)),
          ),
        );
        expect(find.text('App Usage & Reminder Statistics'), findsOneWidget);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(service.consented, false);
        expect(transport.calls, 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(service.consented, false);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(service.consented, true);
        expect(service.appUsageEnabled, false);
        expect(
          find.text('Consented; waiting for server activation'),
          findsOneWidget,
        );
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(service.consented, false);
        expect(service.pendingCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('open consent dialog cannot consent a newly switched account', (
    tester,
  ) async {
    final service = AppStatisticsService(
      transport: Transport(),
      store: Store(),
      bridge: Bridge(),
      platform: TargetPlatform.iOS,
      versionLoader: () async => '1.2.4',
    );
    await service.setAccount('student');
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatisticsConsentSettings(service: service)),
      ),
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await service.setAccount('another');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(service.consented, false);
  });
}
