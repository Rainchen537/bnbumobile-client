import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_protection_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'About follows account and light desktop photo has no dark overlay',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 840);
      addTearDown(tester.view.reset);
      final controller = AppSessionController();
      addTearDown(controller.dispose);
      await _pumpUserPage(tester, controller);
      expect(
        tester.getRect(find.text('关于应用')).top,
        greaterThan(tester.getRect(find.text('账户与安全')).bottom),
      );
      expect(
        find.byKey(const ValueKey('user-desktop-background-overlay')),
        findsNothing,
      );
      await tester.tap(find.text('关于应用'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('BNBU.ME'), findsOneWidget);
      final icon = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/branding/app_logo.png',
      );
      expect(icon, findsOneWidget);
      expect(tester.getRect(icon).left, greaterThan(430));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings stay in the right pane across nested routes and resizing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      final controller = AppSessionController();
      addTearDown(controller.dispose);
      await _pumpUserPage(tester, controller);
      final hero = find.byKey(const ValueKey('user-desktop-split-layout'));
      await tester.tap(find.text('外观与语言'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(hero, findsOneWidget);
      expect(tester.getTopLeft(find.text('外观与语言').last).dx, greaterThan(430));
      await tester.tap(find.text('语言'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(hero, findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('English'), findsOneWidget);
      expect(hero, findsNothing);
      tester.view.physicalSize = const Size(900, 900);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(hero, findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('外观与语言'), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('账户与安全'), findsOneWidget);
    },
  );

  testWidgets(
    'personal page uses the supplied light photo without top overscroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 500);
      addTearDown(tester.view.reset);
      final controller = AppSessionController();
      addTearDown(controller.dispose);
      await _pumpUserPage(tester, controller);
      final background = tester.widget<Image>(
        find
            .descendant(
              of: find.byKey(const ValueKey('user-mobile-background')),
              matching: find.byType(Image),
            )
            .first,
      );
      expect(
        (background.image as AssetImage).assetName,
        'assets/user/user_header_light.png',
      );
      final scroll = find.byKey(const ValueKey('user-mobile-scroll-view'));
      final top = tester.getTopLeft(
        find.byKey(const ValueKey('user-mobile-identity-header')),
      );
      await tester.drag(scroll, const Offset(0, 180));
      await tester.pump();
      expect(
        tester.getTopLeft(
          find.byKey(const ValueKey('user-mobile-identity-header')),
        ),
        top,
      );
      await tester.drag(scroll, const Offset(0, -220));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('user-mobile-identity-header')),
            )
            .dy,
        lessThan(top.dy),
      );
    },
  );

  testWidgets('version information remains a sheet on compact layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await _pumpUserPage(tester, controller);
    await _openVersionInformation(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-version-info-modal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      findsNothing,
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey('user-version-info-modal'))),
    ).pop();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('version information uses a centered dialog on wide layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.reset);
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await _pumpUserPage(tester, controller);
    await _openVersionInformation(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('user-version-info-modal')),
      findsOneWidget,
    );
    final dialogRect = tester.getRect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
    );
    expect(dialogRect.width, lessThanOrEqualTo(480));
    expect(dialogRect.height, lessThanOrEqualTo(520));
    expect(dialogRect.center.dx, closeTo(450, 0.1));
    expect(dialogRect.center.dy, closeTo(450, 0.1));
    expect(find.byTooltip('关闭'), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const ValueKey('user-version-info-modal'))),
    ).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('user-version-info-modal')), findsNothing);
  });

  testWidgets('assistant disable action lives under account and security', (
    tester,
  ) async {
    final controller = AppSessionController();
    var disableCalls = 0;
    addTearDown(controller.dispose);

    await _pumpUserPage(
      tester,
      controller,
      onDisableAssistant: () async {
        disableCalls++;
      },
    );
    expect(find.text('停用小U'), findsNothing);

    await tester.tap(find.text('账户与安全'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('停用小U'), findsOneWidget);

    await tester.tap(find.text('停用小U'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('停用小U？'), findsOneWidget);
    expect(find.textContaining('AI 请求'), findsNothing);

    await tester.tap(find.text('停用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(disableCalls, 1);
  });

  testWidgets('iPhone account security can enable Face ID protection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sessionController = AppSessionController();
    final authenticator = _UserPageBiometricAuthenticator();
    final protectionController = AppProtectionController(
      authenticator: authenticator,
    );
    addTearDown(sessionController.dispose);
    addTearDown(protectionController.dispose);
    await protectionController.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: UserPage(
          controller: sessionController,
          appProtectionController: protectionController,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('账户与安全'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final setting = find.byKey(const ValueKey('biometric-protection-setting'));
    expect(setting, findsOneWidget);
    expect(protectionController.enabled, isFalse);

    await tester.tap(
      find.descendant(of: setting, matching: find.byType(Switch)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(protectionController.enabled, isTrue);
    expect(authenticator.authenticationCalls, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Android account security can enable biometric protection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sessionController = AppSessionController();
    final authenticator = _UserPageBiometricAuthenticator(
      availableType: DeviceBiometricType.biometric,
    );
    final protectionController = AppProtectionController(
      authenticator: authenticator,
    );
    addTearDown(sessionController.dispose);
    addTearDown(protectionController.dispose);
    await protectionController.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
        home: UserPage(
          controller: sessionController,
          appProtectionController: protectionController,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('账户与安全'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final setting = find.byKey(const ValueKey('biometric-protection-setting'));
    expect(setting, findsOneWidget);
    expect(find.text('生物识别保护'), findsOneWidget);

    await tester.tap(
      find.descendant(of: setting, matching: find.byType(Switch)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(protectionController.enabled, isTrue);
    expect(authenticator.authenticationCalls, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  });
}

class _UserPageBiometricAuthenticator implements BiometricAuthenticator {
  _UserPageBiometricAuthenticator({
    this.availableType = DeviceBiometricType.faceId,
  });

  final DeviceBiometricType availableType;
  int authenticationCalls = 0;

  @override
  Future<DeviceBiometricType> getAvailableType() async => availableType;

  @override
  Future<BiometricAuthenticationResult> authenticate({
    required String localizedReason,
  }) async {
    authenticationCalls++;
    return BiometricAuthenticationResult.success;
  }
}

Future<void> _pumpUserPage(
  WidgetTester tester,
  AppSessionController controller, {
  Future<void> Function()? onDisableAssistant,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: UserPage(
        controller: controller,
        onDisableAssistant: onDisableAssistant,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _openVersionInformation(WidgetTester tester) async {
  final about = find.text('关于应用').first;
  await tester.ensureVisible(about);
  await tester.tap(about);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));

  final trigger = find.text('版本信息').first;
  await tester.ensureVisible(trigger);
  await tester.tap(trigger);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}
