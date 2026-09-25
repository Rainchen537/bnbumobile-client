import 'package:bnbu_me/state/personal_sync_controller.dart';
import 'package:bnbu_me/widgets/personal_sync_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'personal_sync_test.dart'
    show MemoryPersonalData, MemoryPersonalServer, MemoryPersonalStore;

void main() {
  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('en'),
      const Locale('zh', 'TW'),
    ]) {
      testWidgets('automatic sync without a switch at $width $locale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final store = MemoryPersonalStore(MemoryPersonalServer());
        final local = MemoryPersonalData()
          ..values['fixture'] = {'name:1': 'Local alias'};
        final controller = PersonalSyncController(local: local, store: store);
        await controller.bind('fixture');
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('en'),
              Locale('zh', 'TW'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
              brightness: width == 900 ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: PersonalSyncSettings(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SwitchListTile), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(controller.enabled, isTrue);
        expect(store.server.values['fixture']!.value, {
          'name:1': 'Local alias',
        });
        final calls = store.networkCalls;
        await tester.tap(find.byKey(const ValueKey('personal-sync-status')));
        await tester.pumpAndSettle();
        expect(store.networkCalls, calls);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    }
  }
}
