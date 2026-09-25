import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseOptions(arguments);
  final platform = options['platform'];
  final artifact = File(_required(options, 'artifact'));
  final output = File(_required(options, 'output'));
  final artifactUrl = Uri.parse(_required(options, 'artifact-url'));
  final version = _required(options, 'version');
  final buildNumber = int.parse(_required(options, 'build-number'));
  if (!await artifact.exists()) {
    throw StateError('更新产物不存在：${artifact.path}');
  }
  if (artifactUrl.scheme != 'https' ||
      artifactUrl.host != 'bnbu.yunwai.cloud' ||
      artifactUrl.userInfo.isNotEmpty ||
      artifactUrl.hasQuery ||
      artifactUrl.hasFragment) {
    throw const FormatException('更新产物 URL 必须位于 https://bnbu.yunwai.cloud。');
  }
  await output.parent.create(recursive: true);
  switch (platform) {
    case 'android':
      await _writeAndroidManifest(
        latestManifest: File(_required(options, 'latest-manifest')),
        artifact: artifact,
        output: output,
        artifactUrl: artifactUrl,
        version: version,
        buildNumber: buildNumber,
        releaseNotes: options['release-note'] ?? '',
      );
    case 'windows':
      await _writeWindowsDescriptor(
        artifact: artifact,
        output: output,
        artifactUrl: artifactUrl,
        version: version,
        buildNumber: buildNumber,
      );
    default:
      throw const FormatException('--platform 必须是 android 或 windows。');
  }
}

Future<void> _writeAndroidManifest({
  required File latestManifest,
  required File artifact,
  required File output,
  required Uri artifactUrl,
  required String version,
  required int buildNumber,
  required String releaseNotes,
}) async {
  final notes = releaseNotes
      .split('|')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (await output.exists()) throw StateError('输出文件已存在，拒绝覆盖。');
  final json = await createAndroidLatestManifest(
    existing:
        jsonDecode(await latestManifest.readAsString()) as Map<String, dynamic>,
    artifact: artifact,
    artifactUrl: artifactUrl,
    version: version,
    buildNumber: buildNumber,
    releaseNotes: notes,
  );
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    flush: true,
  );
}

/// Extends the existing public manifest without advancing other platforms.
Future<Map<String, dynamic>> createAndroidLatestManifest({
  required Map<String, dynamic> existing,
  required File artifact,
  required Uri artifactUrl,
  required String version,
  required int buildNumber,
  required List<String> releaseNotes,
}) async {
  if (existing['schema_version'] != 1 ||
      existing['platforms'] is! Map<String, dynamic>) {
    throw const FormatException('必须提供现有 latest.json 平台清单。');
  }
  if (artifactUrl.scheme != 'https' ||
      artifactUrl.host != 'bnbu.yunwai.cloud' ||
      artifactUrl.hasPort ||
      artifactUrl.userInfo.isNotEmpty ||
      artifactUrl.hasQuery ||
      artifactUrl.hasFragment ||
      !RegExp(
        r'^/downloads/[a-zA-Z0-9][a-zA-Z0-9._-]*\.apk$',
      ).hasMatch(artifactUrl.path)) {
    throw const FormatException('安卓安装包必须来自北京官网下载目录。');
  }
  if (version.trim().isEmpty ||
      version.length > 64 ||
      buildNumber <= 0 ||
      buildNumber > 2100000000 ||
      releaseNotes.length > 8 ||
      releaseNotes.any((note) => note.trim().isEmpty || note.length > 200)) {
    throw const FormatException('安卓发布版本或说明无效。');
  }
  final size = await artifact.length();
  if (size <= 0 || size > 512 * 1024 * 1024) {
    throw const FormatException('安卓安装包大小无效。');
  }
  final platforms = Map<String, dynamic>.from(existing['platforms'] as Map);
  final previous = platforms['android'];
  final previousBuild = previous is Map
      ? (previous['build_number'] ?? existing['build_number'])
      : null;
  if (previousBuild is! int || buildNumber <= previousBuild) {
    throw const FormatException('安卓 build number 必须递增。');
  }
  platforms['android'] = {
    'version': version.trim(),
    'build_number': buildNumber,
    'release_notes': releaseNotes.map((note) => note.trim()).toList(),
    'download_url': artifactUrl.toString(),
    'sha256': await _sha256File(artifact),
    'size_bytes': size,
  };
  return {...existing, 'platforms': platforms};
}

Future<void> _writeWindowsDescriptor({
  required File artifact,
  required File output,
  required Uri artifactUrl,
  required String version,
  required int buildNumber,
}) async {
  final descriptor = <String, Object?>{
    'schemaVersion': 3,
    'packageId': 'bnbu_me',
    'appName': 'BNBU.ME',
    'version': version,
    'buildNumber': buildNumber,
    'platform': 'windows',
    'channel': 'stable',
    'artifact': {
      'kind': 'innoInstaller',
      'url': artifactUrl.toString(),
      'sha256': await _sha256File(artifact),
      'length': await artifact.length(),
    },
    'install': {
      'strategy': 'innoInstaller',
      'inno': {
        'silentArgs': const <String>[
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
        ],
        'inheritInstallDirectory': true,
        'logFileName': 'hands_bnbu_update.log',
        'relaunchAfterInstall': true,
        'requiresElevation': 'auto',
        'authenticode': {
          'required': false,
          'sha256Thumbprints': const <String>[],
        },
      },
    },
    'minimumUpdaterVersion': '3.1.6',
    'minimumOS': {'windows': '10.0.17763'},
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(descriptor)}\n',
    flush: true,
  );
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Map<String, String> _parseOptions(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final key = arguments[index];
    if (!key.startsWith('--') || index + 1 >= arguments.length) {
      throw const FormatException('参数必须使用 --key value。');
    }
    options[key.substring(2)] = arguments[index + 1];
  }
  return options;
}

String _required(Map<String, String> options, String key) {
  final value = options[key]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('缺少 --$key。');
  }
  return value;
}
