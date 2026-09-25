import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

String _resolvedValue(Map<String, String> values, String key) {
  var value = values[key]!;
  final variable = RegExp(r'\$\(([A-Z0-9_]+)\)');
  for (var depth = 0; depth < 8 && variable.hasMatch(value); depth += 1) {
    value = value.replaceAllMapped(variable, (match) {
      return values[match.group(1)!] ?? match.group(0)!;
    });
  }
  return value;
}

Map<String, String>? _showBuildSettings({
  required String target,
  required String configuration,
}) {
  final result = Process.runSync('xcodebuild', <String>[
    '-project',
    'ios/Runner.xcodeproj',
    '-target',
    target,
    '-configuration',
    configuration,
    '-sdk',
    'iphoneos',
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
  test('tracked iOS configs isolate development and release identities', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final debugConfig = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
    final profileConfig = File(
      'ios/Flutter/Profile.xcconfig',
    ).readAsStringSync();
    final releaseConfig = File(
      'ios/Flutter/Release.xcconfig',
    ).readAsStringSync();
    final developmentSigning = File(
      'ios/Flutter/Signing.development.xcconfig',
    ).readAsStringSync();
    final releaseSigning = File(
      'ios/Flutter/Signing.release.xcconfig',
    ).readAsStringSync();
    final developmentTemplate = File(
      'ios/Flutter/Signing.local.xcconfig.example',
    ).readAsStringSync();
    final releaseTemplate = File(
      'ios/Flutter/Signing.release.local.xcconfig.example',
    ).readAsStringSync();

    expect(debugConfig, contains('#include "Signing.development.xcconfig"'));
    expect(debugConfig, isNot(contains('Signing.release.xcconfig')));
    expect(profileConfig, contains('#include "Signing.development.xcconfig"'));
    expect(profileConfig, isNot(contains('Signing.release.xcconfig')));
    expect(releaseConfig, contains('#include "Signing.release.xcconfig"'));
    expect(releaseConfig, isNot(contains('Signing.development.xcconfig')));
    expect(
      developmentSigning,
      isNot(contains('BNBU_APPLE_IDENTITY_CONFIGURED')),
    );
    expect(developmentSigning, contains('CODE_SIGNING_ALLOWED = YES'));
    expect(developmentSigning, contains('#include? "Signing.local.xcconfig"'));
    expect(releaseSigning, isNot(contains('BNBU_APPLE_IDENTITY_CONFIGURED')));
    expect(releaseSigning, contains('CODE_SIGNING_ALLOWED = YES'));
    expect(
      releaseSigning,
      contains('#include? "Signing.release.local.xcconfig"'),
    );

    const requiredDevelopmentKeys = <String>[
      'BNBU_IOS_DEVELOPMENT_TEAM',
      'BNBU_IOS_DEVELOPMENT_BUNDLE_IDENTIFIER',
      'BNBU_IOS_DEVELOPMENT_WIDGET_BUNDLE_IDENTIFIER',
      'BNBU_IOS_DEVELOPMENT_WATCH_BUNDLE_IDENTIFIER',
      'BNBU_IOS_DEVELOPMENT_APP_GROUP_IDENTIFIER',
    ];
    const requiredReleaseKeys = <String>[
      'BNBU_IOS_RELEASE_TEAM',
      'BNBU_IOS_RELEASE_BUNDLE_IDENTIFIER',
      'BNBU_IOS_RELEASE_WIDGET_BUNDLE_IDENTIFIER',
      'BNBU_IOS_RELEASE_WATCH_BUNDLE_IDENTIFIER',
      'BNBU_IOS_RELEASE_APP_GROUP_IDENTIFIER',
    ];
    for (final key in requiredDevelopmentKeys) {
      expect(developmentTemplate, contains(key));
    }
    expect(
      developmentTemplate,
      contains('BNBU_APPLE_IDENTITY_CONFIGURED = YES'),
    );
    for (final key in requiredReleaseKeys) {
      expect(releaseTemplate, contains(key));
    }
    expect(releaseTemplate, contains('BNBU_APPLE_IDENTITY_CONFIGURED = YES'));

    expect(project, contains(r'$(BNBU_IOS_DEVELOPMENT_BUNDLE_IDENTIFIER)'));
    expect(project, contains(r'$(BNBU_IOS_RELEASE_BUNDLE_IDENTIFIER)'));
    expect(
      project,
      contains(r'$(BNBU_IOS_DEVELOPMENT_WIDGET_BUNDLE_IDENTIFIER)'),
    );
    expect(project, contains(r'$(BNBU_IOS_RELEASE_WIDGET_BUNDLE_IDENTIFIER)'));
    expect(
      project,
      contains(r'$(BNBU_IOS_DEVELOPMENT_WATCH_BUNDLE_IDENTIFIER)'),
    );
    expect(project, contains(r'$(BNBU_IOS_RELEASE_WATCH_BUNDLE_IDENTIFIER)'));
    expect(project, isNot(contains('DEVELOPMENT_TEAM = "";')));

    final iosGitignore = File('ios/.gitignore').readAsStringSync();
    expect(iosGitignore, contains('Flutter/Signing.local.xcconfig'));
    expect(iosGitignore, contains('Flutter/Signing.release.local.xcconfig'));
  });

  test('local xcodebuild resolution keeps every iOS target in its lane', () {
    const developmentPath = 'ios/Flutter/Signing.local.xcconfig';
    const releasePath = 'ios/Flutter/Signing.release.local.xcconfig';
    if (!File(developmentPath).existsSync() ||
        !File(releasePath).existsSync()) {
      return;
    }

    final development = _readXcconfig(developmentPath);
    final release = _readXcconfig(releasePath);
    final checks =
        <
          ({
            String configuration,
            String target,
            String team,
            String bundle,
            String? appGroup,
          })
        >[
          for (final configuration in const <String>['Debug', 'Profile']) ...<
            ({
              String configuration,
              String target,
              String team,
              String bundle,
              String? appGroup,
            })
          >[
            (
              configuration: configuration,
              target: 'Runner',
              team: _resolvedValue(development, 'BNBU_IOS_DEVELOPMENT_TEAM'),
              bundle: _resolvedValue(
                development,
                'BNBU_IOS_DEVELOPMENT_BUNDLE_IDENTIFIER',
              ),
              appGroup: _resolvedValue(
                development,
                'BNBU_IOS_DEVELOPMENT_APP_GROUP_IDENTIFIER',
              ),
            ),
            (
              configuration: configuration,
              target: 'BnbuWidgets',
              team: _resolvedValue(development, 'BNBU_IOS_DEVELOPMENT_TEAM'),
              bundle: _resolvedValue(
                development,
                'BNBU_IOS_DEVELOPMENT_WIDGET_BUNDLE_IDENTIFIER',
              ),
              appGroup: _resolvedValue(
                development,
                'BNBU_IOS_DEVELOPMENT_APP_GROUP_IDENTIFIER',
              ),
            ),
            (
              configuration: configuration,
              target: 'BnbuWatchApp',
              team: _resolvedValue(development, 'BNBU_IOS_DEVELOPMENT_TEAM'),
              bundle: _resolvedValue(
                development,
                'BNBU_IOS_DEVELOPMENT_WATCH_BUNDLE_IDENTIFIER',
              ),
              appGroup: null,
            ),
          ],
          (
            configuration: 'Release',
            target: 'Runner',
            team: _resolvedValue(release, 'BNBU_IOS_RELEASE_TEAM'),
            bundle: _resolvedValue(
              release,
              'BNBU_IOS_RELEASE_BUNDLE_IDENTIFIER',
            ),
            appGroup: _resolvedValue(
              release,
              'BNBU_IOS_RELEASE_APP_GROUP_IDENTIFIER',
            ),
          ),
          (
            configuration: 'Release',
            target: 'BnbuWidgets',
            team: _resolvedValue(release, 'BNBU_IOS_RELEASE_TEAM'),
            bundle: _resolvedValue(
              release,
              'BNBU_IOS_RELEASE_WIDGET_BUNDLE_IDENTIFIER',
            ),
            appGroup: _resolvedValue(
              release,
              'BNBU_IOS_RELEASE_APP_GROUP_IDENTIFIER',
            ),
          ),
          (
            configuration: 'Release',
            target: 'BnbuWatchApp',
            team: _resolvedValue(release, 'BNBU_IOS_RELEASE_TEAM'),
            bundle: _resolvedValue(
              release,
              'BNBU_IOS_RELEASE_WATCH_BUNDLE_IDENTIFIER',
            ),
            appGroup: null,
          ),
        ];

    for (final check in checks) {
      final settings = _showBuildSettings(
        target: check.target,
        configuration: check.configuration,
      );
      final hasSettings = settings != null;
      final configured = settings?['BNBU_APPLE_IDENTITY_CONFIGURED'] == 'YES';
      final teamMatches = settings?['DEVELOPMENT_TEAM'] == check.team;
      final bundleMatches =
          settings?['PRODUCT_BUNDLE_IDENTIFIER'] == check.bundle;
      final appGroupMatches =
          check.appGroup == null ||
          settings?['BNBU_IOS_APP_GROUP_IDENTIFIER'] == check.appGroup;
      final matches =
          hasSettings &&
          configured &&
          teamMatches &&
          bundleMatches &&
          appGroupMatches;
      expect(
        matches,
        isTrue,
        reason:
            '${check.target}/${check.configuration} resolution failed '
            '(settings=$hasSettings, configured=$configured, '
            'team=$teamMatches, bundle=$bundleMatches, '
            'appGroup=$appGroupMatches).',
      );
    }
  });
}
