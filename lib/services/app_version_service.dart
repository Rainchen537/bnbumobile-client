import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/app_update.dart';

class AppVersionService {
  AppVersionService({http.Client? client, Uri? manifestUri})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      manifestUri = manifestUri ?? AppConfig.latestVersionManifestUrl;

  final http.Client _client;
  final bool _ownsClient;
  final Uri manifestUri;

  Future<AppUpdateRelease?> check({
    required AppUpdatePlatform platform,
    required int installedBuildNumber,
  }) async {
    if (!_isTrustedManifestUri(manifestUri)) {
      throw const FormatException('版本清单地址无效。');
    }
    final request = http.Request('GET', manifestUri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        (response.contentLength != null &&
            response.contentLength! > 64 * 1024)) {
      await response.stream.listen(null).cancel();
      throw StateError('版本清单暂不可用。');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > 64 * 1024) {
        throw const FormatException('版本清单超过大小限制。');
      }
      bytes.addAll(chunk);
    }
    final finalUri = response.request?.url ?? manifestUri;
    if (finalUri != manifestUri) {
      throw const FormatException('版本清单发生了意外跳转。');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('版本清单必须是 JSON 对象。');
    }
    final release = _parseRelease(decoded, platform);
    return release.buildNumber! > installedBuildNumber ? release : null;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

AppUpdateRelease _parseRelease(
  Map<String, dynamic> json,
  AppUpdatePlatform platform,
) {
  if (json['schema_version'] != 1) {
    throw const FormatException('版本清单协议不受支持。');
  }
  final platforms = json['platforms'];
  final platformKey = switch (platform) {
    AppUpdatePlatform.android => 'android',
    AppUpdatePlatform.macos => 'macos',
    AppUpdatePlatform.windows => 'windows',
    AppUpdatePlatform.ios ||
    AppUpdatePlatform.unsupported => throw const FormatException('平台不受支持。'),
  };
  if (platforms is! Map<String, dynamic> ||
      platforms[platformKey] is! Map<String, dynamic>) {
    throw const FormatException('版本清单包含无效的平台发布信息。');
  }
  final platformEntry = platforms[platformKey] as Map<String, dynamic>;
  final version = platformEntry['version'] ?? json['version'];
  final buildNumber = platformEntry['build_number'] ?? json['build_number'];
  if (version is! String ||
      version.trim().isEmpty ||
      version.length > 64 ||
      buildNumber is! int ||
      buildNumber <= 0) {
    throw const FormatException('版本清单包含无效的发布信息。');
  }
  final downloadUrl = platformEntry['download_url'];
  final downloadUri = downloadUrl is String ? Uri.tryParse(downloadUrl) : null;
  if (downloadUri == null ||
      !isTrustedUpdateDownloadUri(downloadUri, platform)) {
    throw const FormatException('官网下载地址无效。');
  }
  final rawNotes = platformEntry['release_notes'] ?? json['release_notes'];
  if (rawNotes is! List || rawNotes.length > 8) {
    throw const FormatException('版本说明无效。');
  }
  final notes = <String>[];
  for (final note in rawNotes) {
    if (note is! String || note.trim().isEmpty || note.length > 200) {
      throw const FormatException('版本说明无效。');
    }
    notes.add(note.trim());
  }
  final sha256 = platformEntry['sha256'];
  final size = platformEntry['size_bytes'];
  if (platform == AppUpdatePlatform.android &&
      (sha256 != null || size != null)) {
    if (sha256 is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256) ||
        size is! int ||
        size <= 0 ||
        size > AppUpdateRelease.maxAndroidArtifactBytes) {
      throw const FormatException('安卓安装包校验信息无效。');
    }
  }
  return AppUpdateRelease(
    platform: platform,
    version: version.trim(),
    buildNumber: buildNumber,
    downloadUri: downloadUri,
    releaseNotes: List.unmodifiable(notes),
    artifactSha256: platform == AppUpdatePlatform.android
        ? (sha256 as String?)?.toLowerCase()
        : null,
    artifactSize: platform == AppUpdatePlatform.android ? size as int? : null,
  );
}

bool _isTrustedManifestUri(Uri uri) {
  return uri.scheme == 'https' &&
      uri.host == 'bnbu.yunwai.cloud' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.path == '/updates/latest.json';
}

bool isTrustedUpdateDownloadUri(Uri uri, AppUpdatePlatform platform) {
  final expectedSuffix = switch (platform) {
    AppUpdatePlatform.android => '.apk',
    AppUpdatePlatform.macos => '.dmg',
    AppUpdatePlatform.windows => '.exe',
    AppUpdatePlatform.ios || AppUpdatePlatform.unsupported => '',
  };
  return uri.scheme == 'https' &&
      uri.host == 'bnbu.yunwai.cloud' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      RegExp(r'^/downloads/[a-zA-Z0-9][a-zA-Z0-9._-]*$').hasMatch(uri.path) &&
      uri.path.toLowerCase().endsWith(expectedSuffix);
}
