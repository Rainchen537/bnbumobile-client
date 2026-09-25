import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/services/android_app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  final bytes = utf8.encode('synthetic APK bytes; native installer is mocked');
  AppUpdateRelease release({String? digest, int? size}) => AppUpdateRelease(
    platform: AppUpdatePlatform.android,
    version: '1.2.4',
    buildNumber: 2026090901,
    downloadUri: Uri.parse('https://bnbu.yunwai.cloud/downloads/app.apk'),
    artifactSha256: digest ?? sha256.convert(bytes).toString(),
    artifactSize: size ?? bytes.length,
  );
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('bnbu-update-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'streams a public APK, checks bytes and reuses only a verified cache',
    () async {
      var requests = 0;
      final progress = <int>[];
      final service = AndroidAppUpdateService(
        temporaryDirectory: () async => temporary,
        clientFactory: () => MockClient((request) async {
          requests++;
          expect(request.followRedirects, isFalse);
          expect(request.headers.keys, isNot(contains('authorization')));
          expect(request.headers.keys, isNot(contains('cookie')));
          return http.Response.bytes(bytes, 200, request: request);
        }),
      );
      addTearDown(service.dispose);
      final file = await service.download(
        release(),
        onProgress: progress.add,
        onVerifying: () {},
      );
      expect(await file.readAsBytes(), bytes);
      expect(progress, [0, bytes.length]);
      await service.download(release(), onProgress: (_) {}, onVerifying: () {});
      expect(requests, 1);
      await file.writeAsBytes(List.filled(bytes.length, 0));
      await service.download(release(), onProgress: (_) {}, onVerifying: () {});
      expect(requests, 2);
      expect(await file.readAsBytes(), bytes);
    },
  );

  for (final scenario in [
    'redirect',
    'length',
    'overflow',
    'truncated',
    'digest',
  ]) {
    test('rejects $scenario and deletes incomplete APKs', () async {
      final service = AndroidAppUpdateService(
        temporaryDirectory: () async => temporary,
        clientFactory: () => MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            Stream.value(bytes),
            scenario == 'redirect' ? 302 : 200,
            request: request,
            contentLength: scenario == 'length' ? 1 : null,
          ),
        ),
      );
      addTearDown(service.dispose);
      final target = release(
        digest: scenario == 'digest' ? '0' * 64 : null,
        size: scenario == 'overflow'
            ? bytes.length - 1
            : scenario == 'truncated'
            ? bytes.length + 1
            : null,
      );
      await expectLater(
        service.download(target, onProgress: (_) {}, onVerifying: () {}),
        throwsFormatException,
      );
      expect(
        await Directory('${temporary.path}/app_updates').list().toList(),
        isEmpty,
      );
    });
  }

  test('cancellation cleans partial files and allows a new download', () async {
    late AndroidAppUpdateService service;
    service = AndroidAppUpdateService(
      temporaryDirectory: () async => temporary,
      clientFactory: () => MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 5), bytes.sublist(5)]),
          200,
        ),
      ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.download(
        release(),
        onProgress: (count) {
          if (count > 0) service.cancelDownload();
        },
        onVerifying: () {},
      ),
      throwsA(isA<AndroidUpdateCancelled>()),
    );
    expect(
      await Directory('${temporary.path}/app_updates').list().toList(),
      isEmpty,
    );
    final file = await service.download(
      release(),
      onProgress: (_) {},
      onVerifying: () {},
    );
    expect(await file.readAsBytes(), bytes);
  });

  test(
    'stalled response times out without leaving a partial download',
    () async {
      final stream = StreamController<List<int>>();
      final service = AndroidAppUpdateService(
        temporaryDirectory: () async => temporary,
        requestTimeout: const Duration(milliseconds: 30),
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(stream.stream, 200),
        ),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.download(release(), onProgress: (_) {}, onVerifying: () {}),
        throwsA(isA<TimeoutException>()),
      );
      await stream.close();
      expect(
        await Directory('${temporary.path}/app_updates').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'native installer receives integrity expectations and requires known outcomes',
    () async {
      const channel = MethodChannel('ispace/android_app_update');
      final calls = <MethodCall>[];
      var outcome = 'permissionRequired';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'requestInstallPermission' ? true : outcome;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = AndroidAppUpdateService(channel: channel);
      final file = File('${temporary.path}/app.apk');
      expect(
        await service.install(file, release()),
        AndroidInstallResult.permissionRequired,
      );
      expect(calls.single.arguments['sha256'], release().artifactSha256);
      expect(calls.single.arguments['size'], bytes.length);
      expect(calls.single.arguments['buildNumber'], 2026090901);
      expect(await service.requestInstallPermission(), isTrue);
      outcome = 'installerOpened';
      expect(
        await service.install(file, release()),
        AndroidInstallResult.installerOpened,
      );
      outcome = 'success';
      await expectLater(service.install(file, release()), throwsStateError);
    },
  );
}
