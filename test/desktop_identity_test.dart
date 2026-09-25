import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/secure_storage_options.dart';

Map<String, String> _readXcconfig(String path) {
  final values = <String, String>{};
  for (final line in File(path).readAsLinesSync()) {
    final match = RegExp(r'^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$').firstMatch(line);
    if (match != null) {
      values[match.group(1)!] = match.group(2)!;
    }
  }
  return values;
}

Map<String, String>? _showMacBuildSettings({
  required String target,
  required String configuration,
}) {
  final result = Process.runSync('xcodebuild', <String>[
    '-project',
    'macos/Runner.xcodeproj',
    '-target',
    target,
    '-configuration',
    configuration,
    '-sdk',
    'macosx',
    '-showBuildSettings',
    'CODE_SIGNING_ALLOWED=NO',
  ]);
  if (result.exitCode != 0) {
    return null;
  }
  final values = <String, String>{};
  for (final line in (result.stdout as String).split('\n')) {
    final match = RegExp(r'^\s*([A-Z0-9_]+) = (.*)$').firstMatch(line);
    if (match != null) {
      values[match.group(1)!] = match.group(2)!;
    }
  }
  return values;
}

void main() {
  test('development secure storage is isolated from release defaults', () {
    expect(
      macOsSecureStorageAccountName,
      macOsDevelopmentSecureStorageAccountName,
    );
    expect(
      macOsSecureStorageOptions.toMap(),
      containsPair('accountName', macOsDevelopmentSecureStorageAccountName),
    );
    expect(
      macOsSecureStorageOptions.toMap(),
      containsPair('usesDataProtectionKeychain', 'false'),
    );
    expect(macOsReleaseSecureStorageAccountName, startsWith('invalid.local.'));
    expect(
      macOsLegacyReleaseSecureStorageAccountName,
      'flutter_secure_storage_service',
    );
  });

  test('tracked macOS configs contain only isolated safe defaults', () {
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final info = File('macos/Runner/Info.plist').readAsStringSync();
    final development = File(
      'macos/Flutter/Signing.development.xcconfig',
    ).readAsStringSync();
    final release = File(
      'macos/Flutter/Signing.release.xcconfig',
    ).readAsStringSync();
    final releaseScript = File(
      'tool/build_macos_release.sh',
    ).readAsStringSync();
    final developmentExample = _readXcconfig(
      'macos/Flutter/Signing.local.xcconfig.example',
    );
    final releaseExample = _readXcconfig(
      'macos/Flutter/Signing.release.local.xcconfig.example',
    );

    expect(project, contains(r'$(BNBU_MACOS_APP_BUNDLE_IDENTIFIER)'));
    expect(project, contains(r'$(BNBU_MACOS_WIDGET_BUNDLE_IDENTIFIER)'));
    expect(info, contains(r'$(BNBU_MACOS_APP_BUNDLE_IDENTIFIER)'));
    expect(info, contains(r'$(BNBU_MACOS_APP_GROUP_IDENTIFIER)'));
    expect(development, contains('BNBU_APPLE_IDENTITY_CONFIGURED = NO'));
    expect(development, contains('CODE_SIGNING_ALLOWED = NO'));
    expect(development, contains('#include? "Signing.local.xcconfig"'));
    expect(release, contains('BNBU_APPLE_IDENTITY_CONFIGURED = NO'));
    expect(release, contains('CODE_SIGNING_ALLOWED = NO'));
    expect(release, contains('#include? "Signing.release.local.xcconfig"'));
    expect(releaseScript, contains('MACOS_CODESIGN_IDENTITY is required'));
    expect(releaseScript, contains('BNBU_MACOS_TEAM_IDENTIFIER'));
    expect(releaseScript, contains('DesktopUpdaterHelperPolicy.local.json'));
    expect(releaseScript, contains(r'/usr/bin/xattr -cr "$application"'));
    expect(releaseScript, contains('codesign_with_retry'));
    expect(releaseScript, contains('for attempt in 1 2 3'));
    expect(releaseScript, contains(r'/usr/bin/xattr -cr "$target"'));
    expect(releaseScript, contains('verify_signed_application'));
    expect(
      releaseScript,
      contains('Signed macOS code does not match the configured Team.'),
    );
    expect(
      releaseScript.indexOf(r'/usr/bin/xattr -cr "$application"'),
      lessThan(releaseScript.indexOf('TARGET_BUILD_DIR=')),
    );
    expect(releaseScript, isNot(contains('security find-identity')));
    expect(releaseScript, isNot(contains('installed_team')));
    expect(
      File('macos/Runner/DesktopUpdaterHelperPolicy.json').existsSync(),
      isFalse,
    );
    expect(
      File(
        'macos/Runner/DesktopUpdaterHelperPolicy.local.json.example',
      ).existsSync(),
      isTrue,
    );
    for (final example in <Map<String, String>>[
      developmentExample,
      releaseExample,
    ]) {
      expect(example['BNBU_MACOS_TEAM_IDENTIFIER'], 'YOURTEAMID');
      expect(
        example['BNBU_MACOS_APP_GROUP_IDENTIFIER'],
        startsWith('YOURTEAMID.'),
      );
      expect(
        example['BNBU_MACOS_APP_GROUP_IDENTIFIER'],
        isNot(startsWith('group.')),
      );
    }
  });

  test('macOS App Group is injected through Info.plist and entitlements', () {
    final paths = <String>[
      'macos/Runner/Acceptance.entitlements',
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
      'macos/Runner/Widget.entitlements',
    ];
    for (final path in paths) {
      expect(
        File(path).readAsStringSync(),
        contains(r'$(BNBU_MACOS_APP_GROUP_IDENTIFIER)'),
      );
    }
    final runnerSource = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final widgetSource = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync();
    expect(
      runnerSource,
      contains('forInfoDictionaryKey: "BnbuAppGroupIdentifier"'),
    );
    expect(
      widgetSource,
      contains('forInfoDictionaryKey: "BnbuAppGroupIdentifier"'),
    );
  });

  test(
    'sandboxed macOS runner configurations can read and save selected files',
    () {
      const paths = <String>[
        'macos/Runner/Acceptance.entitlements',
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner/Release.entitlements',
        'macos/Runner/ReleaseBuild.entitlements',
      ];
      for (final path in paths) {
        expect(
          File(path).readAsStringSync(),
          contains('com.apple.security.files.user-selected.read-write'),
          reason: '$path must allow user-picked attachments and ZIP exports.',
        );
      }
    },
  );

  test('local xcodebuild resolution keeps macOS targets in their lane', () {
    const developmentPath = 'macos/Flutter/Signing.local.xcconfig';
    const releasePath = 'macos/Flutter/Signing.release.local.xcconfig';
    if (!File(developmentPath).existsSync() ||
        !File(releasePath).existsSync()) {
      return;
    }
    final development = _readXcconfig(developmentPath);
    final release = _readXcconfig(releasePath);

    for (final configuration in const <String>['Debug', 'Profile', 'Release']) {
      final expected = configuration == 'Release' ? release : development;
      final runner = _showMacBuildSettings(
        target: 'Runner',
        configuration: configuration,
      );
      final widget = _showMacBuildSettings(
        target: 'BnbuWidgets',
        configuration: configuration,
      );
      final runnerMatches =
          runner != null &&
          runner['BNBU_APPLE_IDENTITY_CONFIGURED'] == 'YES' &&
          runner['PRODUCT_BUNDLE_IDENTIFIER'] ==
              expected['BNBU_MACOS_APP_BUNDLE_IDENTIFIER'] &&
          runner['BNBU_MACOS_APP_GROUP_IDENTIFIER'] ==
              expected['BNBU_MACOS_APP_GROUP_IDENTIFIER'];
      final widgetMatches =
          widget != null &&
          widget['BNBU_APPLE_IDENTITY_CONFIGURED'] == 'YES' &&
          widget['PRODUCT_BUNDLE_IDENTIFIER'] ==
              expected['BNBU_MACOS_WIDGET_BUNDLE_IDENTIFIER'] &&
          widget['BNBU_MACOS_APP_GROUP_IDENTIFIER'] ==
              expected['BNBU_MACOS_APP_GROUP_IDENTIFIER'];
      expect(
        runnerMatches && widgetMatches,
        isTrue,
        reason: 'A macOS target did not resolve from its expected local lane.',
      );
    }
  });
}
