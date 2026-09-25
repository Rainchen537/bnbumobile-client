import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/create_update_metadata.dart';

void main() {
  test(
    'Android metadata preserves desktop and root versions and hashes actual bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp('bnbu-metadata-');
      addTearDown(() => directory.delete(recursive: true));
      final artifact = await File(
        '${directory.path}/app.apk',
      ).writeAsBytes([1, 2, 3]);
      final existing = <String, dynamic>{
        'schema_version': 1,
        'version': '1.2.3',
        'build_number': 5,
        'release_notes': ['previous'],
        'platforms': <String, dynamic>{
          'android': {'download_url': 'old'},
          'macos': {'download_url': 'macos'},
          'windows': {
            'version': '1.2.2',
            'build_number': 3,
            'download_url': 'windows',
          },
        },
      };
      Future<Map<String, dynamic>> generate({int build = 6, String? url}) =>
          createAndroidLatestManifest(
            existing: existing,
            artifact: artifact,
            artifactUrl: Uri.parse(
              url ?? 'https://bnbu.yunwai.cloud/downloads/new.apk',
            ),
            version: '1.2.4',
            buildNumber: build,
            releaseNotes: ['Android update'],
          );
      final updated = await generate();
      final platforms = updated['platforms'] as Map;
      expect(updated['build_number'], 5);
      expect(updated['version'], '1.2.3');
      expect(platforms['macos'], (existing['platforms'] as Map)['macos']);
      expect(platforms['windows'], (existing['platforms'] as Map)['windows']);
      expect(platforms['android']['build_number'], 6);
      expect(
        platforms['android']['sha256'],
        sha256.convert([1, 2, 3]).toString(),
      );
      expect(platforms['android']['size_bytes'], 3);
      expect((existing['platforms'] as Map)['android'], {
        'download_url': 'old',
      });
      await expectLater(generate(build: 5), throwsFormatException);
      await expectLater(
        generate(url: 'https://bnbu.me/downloads/new.apk'),
        throwsFormatException,
      );
    },
  );
}
