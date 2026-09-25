import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const brandName = 'BNBU.ME';
  const legacyNames = <String>['掌上BNBU', '掌上 BNBU', 'BNBU Mobile'];

  String read(String path) => File(path).readAsStringSync();

  test('all platform display names use BNBU.ME', () {
    final androidManifest = read('android/app/src/main/AndroidManifest.xml');
    final iosInfo = read('ios/Runner/Info.plist');
    final iosProject = read('ios/Runner.xcodeproj/project.pbxproj');
    final macAppInfo = read('macos/Runner/Configs/AppInfo.xcconfig');
    final macInfo = read('macos/Runner/Info.plist');
    final macWindow = read('macos/Runner/MainFlutterWindow.swift');
    final windowsRunner = read('windows/runner/main.cpp');
    final windowsResources = read('windows/runner/Runner.rc');
    final windowsInstaller = read('windows/installer/bnbu_me.iss');
    final webIndex = read('web/index.html');
    final webManifest = read('web/manifest.json');

    expect(androidManifest, contains('android:label="$brandName"'));
    expect(iosInfo, contains('<string>$brandName</string>'));
    expect(
      'INFOPLIST_KEY_CFBundleDisplayName = "$brandName";'.allMatches(
        iosProject,
      ),
      hasLength(3),
      reason: 'Apple Watch 的 Debug/Profile/Release 必须使用统一显示名',
    );
    expect(macAppInfo, contains('PRODUCT_NAME = $brandName'));
    expect(macInfo, contains('<string>$brandName</string>'));
    expect(macWindow, contains('self.title = "$brandName"'));
    expect(windowsRunner, contains('window.Create(L"$brandName"'));
    expect(windowsResources, contains('"ProductName", "$brandName"'));
    expect(windowsInstaller, contains('AppName=$brandName'));
    expect(webIndex, contains('<title>$brandName</title>'));
    expect(webManifest, contains('"name": "$brandName"'));
  });

  test('current app surfaces do not display legacy names', () {
    const paths = <String>[
      'android/app/src/main/AndroidManifest.xml',
      'apple/BnbuWidgets/BnbuLiveActivityWidget.swift',
      'apple/BnbuWidgets/BnbuWidget.swift',
      'ios/Runner.xcodeproj/project.pbxproj',
      'ios/Runner/Info.plist',
      'lib/main.dart',
      'macos/Runner.xcodeproj/project.pbxproj',
      'macos/Runner/Configs/AppInfo.xcconfig',
      'macos/Runner/Info.plist',
      'macos/Runner/MainFlutterWindow.swift',
      'web/index.html',
      'web/manifest.json',
      'windows/installer/bnbu_me.iss',
      'windows/runner/Runner.rc',
      'windows/runner/main.cpp',
    ];

    for (final path in paths) {
      final source = read(path);
      for (final legacyName in legacyNames) {
        expect(
          source,
          isNot(contains(legacyName)),
          reason: '$path 不应继续展示旧名称 $legacyName',
        );
      }
    }
  });
}
