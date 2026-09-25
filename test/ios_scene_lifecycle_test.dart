import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native presentation and UI lifecycle use the owning scene', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final scene = File('ios/Runner/BnbuSceneDelegate.swift').readAsStringSync();
    expect(delegate, isNot(contains('window?.rootViewController')));
    expect(delegate, contains('presentationRegistrar?.viewController'));
    expect(scene, contains('override func sceneDidBecomeActive'));
    expect(scene, contains('override func sceneWillResignActive'));
    expect(scene, contains('synchronizeLiveActivityFromCachedSnapshot()'));
    expect(scene, contains('restoreEcardBrightness()'));
  });

  test(
    'iOS uses UIScene and registers plugins after engine initialization',
    () {
      final fvmConfig = File('.fvmrc').readAsStringSync();
      final info = File('ios/Runner/Info.plist').readAsStringSync();
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      final sceneDelegate = File(
        'ios/Runner/BnbuSceneDelegate.swift',
      ).readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final launchSetup = delegate.substring(
        0,
        delegate.indexOf('  private func mailAttachmentCacheDirectory'),
      );

      expect(fvmConfig, contains('"flutter": "3.44.9"'));
      expect(info, contains('<key>UIApplicationSceneManifest</key>'));
      expect(
        info,
        contains(r'<string>$(PRODUCT_MODULE_NAME).BnbuSceneDelegate</string>'),
      );
      expect(
        sceneDelegate,
        contains('class BnbuSceneDelegate: FlutterSceneDelegate'),
      );
      expect(sceneDelegate, contains('super.scene('));
      expect(delegate, contains('FlutterImplicitEngineDelegate'));
      expect(
        delegate,
        contains(
          'didInitializeImplicitFlutterEngine('
          '_ engineBridge: FlutterImplicitEngineBridge)',
        ),
      );
      expect(
        delegate,
        contains(
          'GeneratedPluginRegistrant.register('
          'with: engineBridge.pluginRegistry)',
        ),
      );
      expect(
        delegate,
        isNot(contains('GeneratedPluginRegistrant.register(with: self)')),
      );
      expect(launchSetup, isNot(contains('window?.rootViewController')));
      expect(pubspec, contains('enable-swift-package-manager: false'));
    },
  );
}
