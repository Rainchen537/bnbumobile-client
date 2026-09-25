import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/services/app_version_service.dart';

void main() {
  Map<String, dynamic> manifestJson({
    int buildNumber = 2026082603,
    String androidUrl =
        'https://bnbu.yunwai.cloud/downloads/hands-bnbu-android-release.apk',
  }) {
    return {
      'schema_version': 1,
      'version': '1.2.3',
      'build_number': buildNumber,
      'release_notes': ['前往官网下载安装'],
      'platforms': {
        'android': <String, dynamic>{'download_url': androidUrl},
        'macos': {
          'download_url':
              'https://bnbu.yunwai.cloud/downloads/hands-bnbu-macos.dmg',
        },
        'windows': <String, dynamic>{
          'download_url':
              'https://bnbu.yunwai.cloud/downloads/hands-bnbu-windows.exe',
        },
      },
    };
  }

  AppVersionService serviceFor(Map<String, dynamic> manifest) {
    return AppVersionService(
      client: MockClient((request) async {
        expect(request.url, AppConfig.latestVersionManifestUrl);
        return http.Response.bytes(
          utf8.encode(jsonEncode(manifest)),
          200,
          request: request,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  test('returns a newer platform-specific official download', () async {
    final service = serviceFor(manifestJson());

    final android = await service.check(
      platform: AppUpdatePlatform.android,
      installedBuildNumber: 2026082602,
    );
    final macos = await service.check(
      platform: AppUpdatePlatform.macos,
      installedBuildNumber: 2026082602,
    );
    final windows = await service.check(
      platform: AppUpdatePlatform.windows,
      installedBuildNumber: 2026082602,
    );

    expect(android?.versionLabel, '1.2.3+2026082603');
    expect(android?.downloadUri.path, endsWith('.apk'));
    expect(macos?.downloadUri.path, endsWith('.dmg'));
    expect(windows?.downloadUri.path, endsWith('.exe'));
  });

  test(
    'platform release versions do not follow an unrelated platform build',
    () async {
      final manifest = manifestJson(buildNumber: 2026090601);
      final windows =
          (manifest['platforms'] as Map<String, dynamic>)['windows']
              as Map<String, dynamic>;
      windows['version'] = '1.2.2';
      windows['build_number'] = 2026082501;
      windows['release_notes'] = ['Windows release'];
      expect(
        await serviceFor(manifest).check(
          platform: AppUpdatePlatform.windows,
          installedBuildNumber: 2026082501,
        ),
        isNull,
      );
      expect(
        (await serviceFor(manifest).check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 2026082501,
        ))?.buildNumber,
        2026090601,
      );
    },
  );

  test(
    'manifest transport refuses redirects before another request is sent',
    () async {
      var count = 0;
      final service = AppVersionService(
        client: MockClient((request) async {
          count++;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://evil.example/manifest'},
          );
        }),
      );
      await expectLater(
        service.check(
          platform: AppUpdatePlatform.macos,
          installedBuildNumber: 1,
        ),
        throwsStateError,
      );
      expect(count, 1);
    },
  );

  test('does not prompt when the installed build is current', () async {
    final service = serviceFor(manifestJson());

    expect(
      await service.check(
        platform: AppUpdatePlatform.android,
        installedBuildNumber: 2026082603,
      ),
      isNull,
    );
  });

  test(
    'accepts verified Android artifacts and preserves legacy website fallback',
    () async {
      final json = manifestJson();
      final entry = (json['platforms'] as Map)['android'] as Map;
      entry['sha256'] = 'A' * 64;
      entry['size_bytes'] = 12345;
      final release = await serviceFor(
        json,
      ).check(platform: AppUpdatePlatform.android, installedBuildNumber: 1);
      expect(release!.artifactSha256, 'a' * 64);
      expect(release.artifactSize, 12345);
      expect(release.canInstallInApp, isTrue);
      final legacy = await serviceFor(
        manifestJson(),
      ).check(platform: AppUpdatePlatform.android, installedBuildNumber: 1);
      expect(legacy!.canInstallInApp, isFalse);
    },
  );

  test(
    'rejects incomplete, malformed, fractional and oversized artifact metadata',
    () async {
      for (final fields in [
        {'sha256': 'a' * 64},
        {'size_bytes': 10},
        {'sha256': 'invalid', 'size_bytes': 10},
        {'sha256': 123, 'size_bytes': 10},
        {'sha256': 'a' * 64, 'size_bytes': 0},
        {'sha256': 'a' * 64, 'size_bytes': 1.5},
        {'sha256': 'a' * 64, 'size_bytes': 512 * 1024 * 1024 + 1},
      ]) {
        final json = manifestJson();
        ((json['platforms'] as Map)['android'] as Map).addAll(fields);
        await expectLater(
          serviceFor(
            json,
          ).check(platform: AppUpdatePlatform.android, installedBuildNumber: 1),
          throwsFormatException,
        );
      }
    },
  );

  test('rejects mirrors, malicious suffixes, and wrong artifact types', () {
    for (final url in <String>[
      'https://bnbu.me/downloads/app.apk',
      'https://bnbu.yunwai.cloud.evil.example/downloads/app.apk',
      'https://user@bnbu.yunwai.cloud/downloads/app.apk',
      'https://bnbu.yunwai.cloud:444/downloads/app.apk',
      'https://bnbu.yunwai.cloud/updates/app.apk',
      'https://bnbu.yunwai.cloud/downloads/app.exe',
      'https://bnbu.yunwai.cloud/downloads/subdirectory/app.apk',
      'https://bnbu.yunwai.cloud/downloads/%2e%2e%2fapp.apk',
      'https://bnbu.yunwai.cloud/downloads/app.apk?token=x',
      'https://bnbu.yunwai.cloud/downloads/app.apk#fragment',
    ]) {
      final service = serviceFor(manifestJson(androidUrl: url));
      expect(
        () => service.check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 1,
        ),
        throwsFormatException,
        reason: url,
      );
    }
  });
}
