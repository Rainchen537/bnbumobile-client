import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/app_update.dart';
import 'app_version_service.dart';

enum AndroidInstallResult { permissionRequired, installerOpened }

class AndroidUpdateCancelled implements Exception {}

/// Public APKs only. No school client, cookies or device credentials are used.
class AndroidAppUpdateService {
  AndroidAppUpdateService({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? temporaryDirectory,
    MethodChannel? channel,
    this.requestTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 15),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _channel = channel ?? const MethodChannel('ispace/android_app_update');

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _temporaryDirectory;
  final MethodChannel _channel;
  final Duration requestTimeout;
  final Duration downloadTimeout;
  _DownloadOperation? _active;

  Future<File> download(
    AppUpdateRelease release, {
    required void Function(int receivedBytes) onProgress,
    required void Function() onVerifying,
  }) async {
    if (!release.canInstallInApp ||
        !isTrustedUpdateDownloadUri(release.downloadUri, release.platform)) {
      throw const FormatException('安卓安装包校验信息无效。');
    }
    if (_active != null) throw StateError('更新下载正在进行。');
    final operation = _DownloadOperation(_clientFactory());
    _active = operation;
    File? partial;
    IOSink? sink;
    final deadline = Timer(downloadTimeout, operation.timeout);
    try {
      final temporary = await _temporaryDirectory();
      operation.check();
      final directory = Directory('${temporary.path}/app_updates');
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}/${release.buildNumber}-${release.artifactSha256}.apk',
      );
      // Only remove files belonging to this updater, without following links.
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File &&
            entry.uri.pathSegments.last != file.uri.pathSegments.last &&
            RegExp(
              r'^\d+-[a-f0-9]{64}\.apk(?:\.partial)?$',
            ).hasMatch(entry.uri.pathSegments.last)) {
          await entry.delete();
        }
      }
      operation.check();
      if (await file.exists()) {
        onVerifying();
        if (await _matches(file, release)) {
          operation.check();
          return file;
        }
        await file.delete();
      }
      onProgress(0);
      partial = File('${file.path}.partial');
      final request = http.Request('GET', release.downloadUri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/vnd.android.package-archive';
      final response = await operation.client
          .send(request)
          .timeout(requestTimeout);
      operation.check();
      if (response.statusCode != 200 ||
          (response.request?.url ?? release.downloadUri) !=
              release.downloadUri ||
          (response.contentLength != null &&
              response.contentLength != release.artifactSize)) {
        await response.stream.listen(null).cancel();
        throw const FormatException('安装包下载响应无效。');
      }
      sink = partial.openWrite();
      // Observe write failures immediately, even while awaiting network data.
      unawaited(
        sink.done.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      );
      var received = 0;
      await for (final chunk in response.stream.timeout(requestTimeout)) {
        operation.check();
        received += chunk.length;
        if (received > release.artifactSize!) {
          throw const FormatException('安装包超过大小限制。');
        }
        sink.add(chunk);
        // Bound the write buffer rather than accumulating an APK in memory.
        await sink.flush();
        onProgress(received);
      }
      await sink.close();
      sink = null;
      operation.check();
      onVerifying();
      if (!await _matches(partial, release)) {
        throw const FormatException('安装包校验失败。');
      }
      operation.check();
      return await partial.rename(file.path);
    } catch (_) {
      operation.check();
      rethrow;
    } finally {
      deadline.cancel();
      operation.client.close();
      try {
        await sink?.close();
      } finally {
        if (identical(_active, operation)) _active = null;
        if (partial != null && await partial.exists()) await partial.delete();
      }
    }
  }

  Future<bool> _matches(File file, AppUpdateRelease release) async =>
      await file.length() == release.artifactSize &&
      (await sha256.bind(file.openRead()).first).toString() ==
          release.artifactSha256;

  Future<AndroidInstallResult> install(
    File file,
    AppUpdateRelease release,
  ) async {
    if (!release.canInstallInApp) {
      throw const FormatException('安卓安装包校验信息无效。');
    }
    final result = await _channel.invokeMethod<String>('install', {
      'path': file.path,
      'sha256': release.artifactSha256,
      'size': release.artifactSize,
      'buildNumber': release.buildNumber,
      'version': release.nativeVersion ?? release.version,
    });
    return switch (result) {
      'permissionRequired' => AndroidInstallResult.permissionRequired,
      'installerOpened' => AndroidInstallResult.installerOpened,
      _ => throw StateError('无法打开系统安装器。'),
    };
  }

  Future<bool> requestInstallPermission() async =>
      await _channel.invokeMethod<bool>('requestInstallPermission') ?? false;

  void cancelDownload() => _active?.cancel();

  void dispose() => cancelDownload();
}

class _DownloadOperation {
  _DownloadOperation(this.client);

  final http.Client client;
  bool cancelled = false;
  bool timedOut = false;

  void cancel() {
    cancelled = true;
    client.close();
  }

  void timeout() {
    timedOut = true;
    client.close();
  }

  void check() {
    if (cancelled) throw AndroidUpdateCancelled();
    if (timedOut) throw TimeoutException('安装包下载超时。');
  }
}
