import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/l10n/bnbu_localizations.dart';
import 'package:bnbu_me/pages/me_identity_page.dart';
import 'package:bnbu_me/services/me_identity_service.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';

class _EmptyStore implements UsageSyncStore {
  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async => null;
  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets('ME binding retains usable fields at width $width', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final identity = MeIdentityService(
        store: _EmptyStore(),
        marker: () async => 'synthetic-installation-0000000000',
      );
      identity.setActiveOwner('synthetic');
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        identity.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: [
            BnbuLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: BnbuLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.6 : 1)),
            child: child!,
          ),
          home: MeIdentityPage(owner: 'synthetic', identity: identity),
        ),
      );
      await tester.pump();
      expect(find.text('synthetic@mail.bnbu.edu.cn'), findsOneWidget);
      expect(find.text('获取验证码'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<ExpansionTile>(find.byType(ExpansionTile))
            .initiallyExpanded,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      identity.setActiveOwner('another');
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('登录账号已变化，请返回当前账号重新操作。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
