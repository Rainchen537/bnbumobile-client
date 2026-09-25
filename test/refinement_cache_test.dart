import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/services/private_portrait_cache.dart';
import 'package:bnbu_me/services/public_directory_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'private portraits are authenticated by account and source and erased at logout',
    () async {
      final dir = await Directory.systemTemp.createTemp('private-photo-test-');
      addTearDown(() => dir.delete(recursive: true));
      final key = await AesGcm.with256bits().newSecretKey();
      final cache = PrivatePortraitCache(
        directory: () async => dir,
        key: () async => key,
      );
      final data = Uint8List.fromList([1, 2, 3, 4]);
      await cache.save('student-a', '/photo-a', data);
      expect(await cache.load('student-a', '/photo-a'), data);
      expect(await cache.load('student-b', '/photo-a'), isNull);
      expect(await cache.load('student-a', '/photo-b'), isNull);
      final file =
          await dir.list(recursive: true).where((e) => e is File).first as File;
      expect(await file.readAsBytes(), isNot(data));
      await cache.clear('student-a');
      expect(await cache.load('student-a', '/photo-a'), isNull);
    },
  );
  test(
    'directory returns persisted snapshot while one shared refresh is pending',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'public-directory-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final uri = Uri.parse(
        'https://example.test/v1/directory/public/organizations',
      );
      final oldClient = PublicDirectoryCache(
        client: MockClient(
          (_) async => http.Response('{"organizations":[]}', 200),
        ),
        directory: () async => dir,
      );
      expect(
        (await oldClient.get(uri).timeout(const Duration(seconds: 3)))
            .statusCode,
        200,
      );
      final pending = Completer<http.Response>();
      var requests = 0;
      final restarted = PublicDirectoryCache(
        client: MockClient((_) {
          requests++;
          return pending.future;
        }),
        directory: () async => dir,
      );
      expect(
        (await restarted.get(uri).timeout(const Duration(seconds: 3))).body,
        '{"organizations":[]}',
      );
      expect(
        (await restarted.get(uri).timeout(const Duration(seconds: 3))).body,
        '{"organizations":[]}',
      );
      expect(requests, 1);
      pending.complete(http.Response('{"organizations":[],"version":2}', 200));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (await restarted.get(uri).timeout(const Duration(seconds: 3))).body,
        contains('version'),
      );
    },
  );
}
