import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/services/native_actions.dart';

void main() {
  test(
    'decoded gzip bytes are not compared with encoded content length',
    () async {
      final root = await Directory.systemTemp.createTemp('bnbu-preview-gzip-');
      addTearDown(() => root.delete(recursive: true));
      final actions = NativeActions(
        temporaryDirectoryProvider: () async => root,
        previewClientFactory: () => MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            Stream.value([1, 2, 3]),
            200,
            contentLength: 23,
            headers: {'content-encoding': 'gzip'},
          ),
        ),
      );
      final path = await actions.cachePreviewFile(
        url: 'https://example.test/file.pdf',
        filename: 'file.pdf',
      );
      expect(await File(path).readAsBytes(), [1, 2, 3]);
    },
  );
  test(
    'response filename identifies extensionless desktop resources',
    () async {
      final root = await Directory.systemTemp.createTemp('bnbu-preview-name-');
      addTearDown(() => root.delete(recursive: true));
      final actions = NativeActions(
        temporaryDirectoryProvider: () async => root,
        previewClientFactory: () => MockClient(
          (_) async => http.Response(
            '%PDF-1.4 synthetic',
            200,
            headers: {
              'content-type': 'application/pdf',
              'content-disposition':
                  "attachment; filename*=UTF-8''Week%201.pdf",
            },
          ),
        ),
      );
      final path = await actions.cachePreviewFile(
        url: 'https://example.test/mod/resource/view.php?id=1',
        filename: 'view.php',
      );
      expect(path, endsWith('/Week 1.pdf'));
    },
  );

  test('truncated responses never publish a file', () async {
    final root = await Directory.systemTemp.createTemp('bnbu-preview-short-');
    addTearDown(() => root.delete(recursive: true));
    final actions = NativeActions(
      temporaryDirectoryProvider: () async => root,
      previewClientFactory: () => MockClient.streaming(
        (_, __) async =>
            http.StreamedResponse(Stream.value([1, 2]), 200, contentLength: 20),
      ),
    );
    await expectLater(
      actions.cachePreviewFile(
        url: 'https://example.test/file.pdf',
        filename: 'file.pdf',
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(
      await Directory('${root.path}/bnbu-file-preview').list().toList(),
      isEmpty,
    );
  });

  test(
    'preview uses a private file and strips cookies on cross-origin redirect',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bnbu-preview-download-',
      );
      addTearDown(() => root.delete(recursive: true));
      var requests = 0;
      final actions = NativeActions(
        temporaryDirectoryProvider: () async => root,
        previewClientFactory: () => MockClient((request) async {
          requests++;
          if (requests == 1) {
            expect(request.headers['Cookie'], 'session=fixture');
            return http.Response(
              '',
              302,
              headers: {'location': 'https://files.example.test/test.pdf'},
            );
          }
          expect(request.headers.containsKey('Cookie'), isFalse);
          return http.Response(
            '%PDF-1.4 synthetic',
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }),
      );
      final path = await actions.cachePreviewFile(
        url: 'https://school.example.test/test.pdf',
        filename: 'test.pdf',
        cookieHeader: 'session=fixture',
        cookieOrigin: 'https://school.example.test',
      );
      expect(path, startsWith(root.path));
      expect(await File(path).readAsString(), '%PDF-1.4 synthetic');
      expect(requests, 2);
    },
  );
  test(
    'login HTML is rejected and partial preview directory is cleaned',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bnbu-preview-reject-',
      );
      addTearDown(() => root.delete(recursive: true));
      final actions = NativeActions(
        temporaryDirectoryProvider: () async => root,
        previewClientFactory: () => MockClient(
          (_) async => http.Response(
            '<html>login</html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      await expectLater(
        actions.cachePreviewFile(
          url: 'https://school.example.test/test.pdf',
          filename: 'test.pdf',
        ),
        throwsA(anything),
      );
      expect(
        await Directory('${root.path}/bnbu-file-preview').list().toList(),
        isEmpty,
      );
    },
  );
  test('oversized responses are cancelled before writing a preview', () async {
    final root = await Directory.systemTemp.createTemp('bnbu-preview-size-');
    addTearDown(() => root.delete(recursive: true));
    final actions = NativeActions(
      temporaryDirectoryProvider: () async => root,
      previewClientFactory: () => MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          const Stream.empty(),
          200,
          contentLength: 65 * 1024 * 1024,
        ),
      ),
    );
    await expectLater(
      actions.cachePreviewFile(
        url: 'https://example.test/large.pdf',
        filename: 'large.pdf',
      ),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'download_too_large',
        ),
      ),
    );
    expect(
      await Directory('${root.path}/bnbu-file-preview').list().toList(),
      isEmpty,
    );
  });
}
