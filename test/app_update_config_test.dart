import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/config/app_config.dart';

void main() {
  test('runtime update check uses the simple Beijing version endpoint', () {
    expect(
      AppConfig.latestVersionManifestUrl.toString(),
      'https://bnbu.yunwai.cloud/updates/latest.json',
    );
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('REQUEST_INSTALL_PACKAGES'));
  });

  test('desktop update profile matches the public key pinned by the app', () {
    final profile =
        jsonDecode(File('desktop_updater.keys.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(
      profile['feedUrl'],
      'https://bnbu.yunwai.cloud/updates/desktop/app-archive.json',
    );
    expect(
      Map<String, String>.from(profile['publicKeys'] as Map),
      AppConfig.desktopUpdateTrustedReleasePublicKeys,
    );
    expect(AppConfig.desktopUpdateArchiveUrl.toString(), profile['feedUrl']);
  });

  test('macOS helper policy is a local release-machine input', () {
    const trackedPolicy = 'macos/Runner/DesktopUpdaterHelperPolicy.json';
    const localPolicy = 'macos/Runner/DesktopUpdaterHelperPolicy.local.json';
    const templatePolicy =
        'macos/Runner/DesktopUpdaterHelperPolicy.local.json.example';
    final gitignore = File('.gitignore').readAsStringSync();
    final template =
        jsonDecode(File(templatePolicy).readAsStringSync())
            as Map<String, dynamic>;
    final buildScript = File('tool/build_macos_release.sh').readAsStringSync();

    expect(File(trackedPolicy).existsSync(), isFalse);
    expect(File(templatePolicy).existsSync(), isTrue);
    expect(gitignore, contains('/$localPolicy'));
    expect(template['applicationPackageId'], startsWith('app.example.'));
    expect(
      template['allowedApplicationSigner'].toString(),
      contains('REPLACE_WITH_APPLICATION_DESIGNATED_REQUIREMENT'),
    );
    expect(buildScript, contains('MACOS_DESKTOP_UPDATER_POLICY'));
    expect(buildScript, contains('git check-ignore -q'));
  });

  test('Windows install output is forced into the Flutter release bundle', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();

    expect(
      cmake,
      contains(
        'set(CMAKE_INSTALL_PREFIX "\${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)',
      ),
    );
    expect(
      cmake,
      isNot(contains('if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)')),
    );
  });
}
