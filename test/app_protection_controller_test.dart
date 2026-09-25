import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/state/app_protection_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/app_protection_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('已开启 Face ID 时首次进入自动验证', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppProtectionController.enabledPreferenceKey: true,
    });
    final authenticator = _FakeBiometricAuthenticator(
      results: <BiometricAuthenticationResult>[
        BiometricAuthenticationResult.success,
      ],
    );
    final controller = AppProtectionController(authenticator: authenticator);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.enabled, isTrue);
    expect(controller.isLocked, isFalse);
    expect(authenticator.authenticationCalls, 1);
  });

  test('系统生物识别提示使用 App 当前选择的语言', () async {
    const cases = <(Locale, String)>[
      (Locale('zh', 'CN'), '验证身份以解锁 BNBU.ME'),
      (Locale('zh', 'TW'), '驗證身份以解鎖 BNBU.ME'),
      (Locale('en'), 'Authenticate to unlock BNBU.ME'),
    ];

    for (final (locale, expectedReason) in cases) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppProtectionController.enabledPreferenceKey: true,
      });
      final authenticator = _FakeBiometricAuthenticator(
        results: <BiometricAuthenticationResult>[
          BiometricAuthenticationResult.success,
        ],
      );
      final controller = AppProtectionController(
        authenticator: authenticator,
        localizedAuthenticationReason: () => BnbuLocalizations(
          locale,
        ).text(AppProtectionController.defaultAuthenticationReason),
      );

      await controller.initialize();

      expect(authenticator.localizedReasons, <String>[expectedReason]);
      controller.dispose();
    }
  });

  test('只有 Face ID 验证成功才启用或关闭保护', () async {
    final authenticator = _FakeBiometricAuthenticator(
      results: <BiometricAuthenticationResult>[
        BiometricAuthenticationResult.cancelled,
        BiometricAuthenticationResult.success,
        BiometricAuthenticationResult.cancelled,
        BiometricAuthenticationResult.success,
      ],
    );
    final controller = AppProtectionController(authenticator: authenticator);
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(await controller.setEnabled(true), isNotNull);
    expect(controller.enabled, isFalse);
    expect(await controller.setEnabled(true), isNull);
    expect(controller.enabled, isTrue);
    expect(await controller.setEnabled(false), isNotNull);
    expect(controller.enabled, isTrue);
    expect(await controller.setEnabled(false), isNull);
    expect(controller.enabled, isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(AppProtectionController.enabledPreferenceKey),
      isFalse,
    );
  });

  test('进入后台立即锁定，返回前台重新验证', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppProtectionController.enabledPreferenceKey: true,
    });
    final authenticator = _FakeBiometricAuthenticator(
      results: <BiometricAuthenticationResult>[
        BiometricAuthenticationResult.success,
        BiometricAuthenticationResult.success,
      ],
    );
    final controller = AppProtectionController(authenticator: authenticator);
    addTearDown(controller.dispose);
    await controller.initialize();

    controller.lockForBackground();
    expect(controller.isLocked, isTrue);
    await controller.handleResumed();
    expect(controller.isLocked, isFalse);
    expect(authenticator.authenticationCalls, 2);
  });

  test('iPad Touch ID 机型使用 Touch ID 文案', () async {
    final controller = AppProtectionController(
      authenticator: _FakeBiometricAuthenticator(
        availableType: DeviceBiometricType.touchId,
      ),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.settingLabel, 'Touch ID 保护');
    expect(controller.unlockLabel, '使用 Touch ID 解锁');
  });

  test(
    'Android is supported without pretending its biometric class is Face ID',
    () {
      expect(
        LocalBiometricAuthenticator.supportsPlatform(TargetPlatform.android),
        isTrue,
      );
      expect(
        LocalBiometricAuthenticator.supportsPlatform(TargetPlatform.iOS),
        isTrue,
      );
      expect(
        LocalBiometricAuthenticator.supportsPlatform(TargetPlatform.macOS),
        isFalse,
      );
    },
  );

  test('Android generic biometric uses platform-neutral labels', () async {
    final controller = AppProtectionController(
      authenticator: _FakeBiometricAuthenticator(
        availableType: DeviceBiometricType.biometric,
      ),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.settingLabel, '生物识别保护');
    expect(controller.unlockLabel, '使用生物识别解锁');
  });

  test('iOS 声明 Face ID 用途', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(infoPlist, contains('<key>NSFaceIDUsageDescription</key>'));
    expect(infoPlist, contains('验证身份并解锁 BNBU.ME'));
  });

  test('Android declares and hosts biometric authentication correctly', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/me/bnbu/app/MainActivity.kt',
    ).readAsStringSync();
    final styles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.USE_BIOMETRIC'));
    expect(
      activity,
      contains('class MainActivity : FlutterFragmentActivity()'),
    );
    expect(styles, contains('Theme.AppCompat.DayNight.NoActionBar'));
  });

  test('Android disables backup and uses a dedicated status-bar icon', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final extractionRules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    final reminderSource = File(
      'lib/services/deadline_reminder_service.dart',
    ).readAsStringSync();

    expect(manifest, contains('android:dataExtractionRules'));
    expect(extractionRules, contains('<device-transfer>'));
    expect(extractionRules, contains('domain="sharedpref"'));
    expect(
      File(
        'android/app/src/main/res/drawable/ic_notification_status.xml',
      ).existsSync(),
      isTrue,
    );
    expect(reminderSource, contains("'ic_notification_status'"));
    expect(reminderSource, isNot(contains("icon: 'ic_notification'")));
  });

  testWidgets('锁定层遮挡主界面并保留其状态树', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppProtectionController.enabledPreferenceKey: true,
    });
    final authenticator = _FakeBiometricAuthenticator(
      results: <BiometricAuthenticationResult>[
        BiometricAuthenticationResult.cancelled,
        BiometricAuthenticationResult.success,
      ],
    );
    final controller = AppProtectionController(authenticator: authenticator);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppProtectionGate(
          controller: controller,
          child: const Text('受保护内容'),
        ),
      ),
    );
    await tester.pump();

    final protectedContent = tester.widget<Offstage>(
      find.byKey(const ValueKey('app-protection-content')),
    );
    expect(protectedContent.offstage, isTrue);
    expect(find.text('使用 Face ID 解锁'), findsOneWidget);

    await tester.tap(find.text('使用 Face ID 解锁'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Offstage>(
            find.byKey(const ValueKey('app-protection-content')),
          )
          .offstage,
      isFalse,
    );
  });

  testWidgets('App 锁界面随 App 语言切换', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppProtectionController.enabledPreferenceKey: true,
    });
    final controller = AppProtectionController(
      authenticator: _FakeBiometricAuthenticator(
        results: <BiometricAuthenticationResult>[
          BiometricAuthenticationResult.cancelled,
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    Widget app(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: BnbuLocalizations.supportedLocales,
      localizationsDelegates: const [
        BnbuLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      home: AppProtectionGate(
        controller: controller,
        child: const Text('protected content'),
      ),
    );

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pump();
    expect(find.text('Unlock with Face ID'), findsOneWidget);
    expect(find.text('Authentication was not completed.'), findsOneWidget);

    await tester.pumpWidget(app(const Locale('zh', 'TW')));
    await tester.pump();
    expect(find.text('使用 Face ID 解鎖'), findsOneWidget);
    expect(find.text('未完成身份驗證。'), findsOneWidget);
  });
}

class _FakeBiometricAuthenticator implements BiometricAuthenticator {
  _FakeBiometricAuthenticator({
    this.availableType = DeviceBiometricType.faceId,
    List<BiometricAuthenticationResult> results = const [],
  }) : _results = List<BiometricAuthenticationResult>.of(results);

  final DeviceBiometricType availableType;
  final List<BiometricAuthenticationResult> _results;
  int authenticationCalls = 0;
  final List<String> localizedReasons = <String>[];

  @override
  Future<DeviceBiometricType> getAvailableType() async => availableType;

  @override
  Future<BiometricAuthenticationResult> authenticate({
    required String localizedReason,
  }) async {
    authenticationCalls++;
    localizedReasons.add(localizedReason);
    return _results.isEmpty
        ? BiometricAuthenticationResult.cancelled
        : _results.removeAt(0);
  }
}
