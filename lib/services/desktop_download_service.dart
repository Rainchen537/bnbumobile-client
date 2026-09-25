import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum DesktopDownloadPurpose { single, archive }

/// Device-local destinations. They must never enter account/server sync.
/// macOS owns security-scoped bookmarks natively; a path alone is not a grant.
class DesktopDownloadService {
  const DesktopDownloadService({
    MethodChannel channel = const MethodChannel('ispace/desktop_downloads'),
    FilePicker? picker,
    Future<Directory?> Function()? downloadsProvider,
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _channel = channel,
       _picker = picker,
       _downloadsProvider = downloadsProvider,
       _preferencesProvider = preferencesProvider;

  final MethodChannel _channel;
  final FilePicker? _picker;
  final Future<Directory?> Function()? _downloadsProvider;
  final Future<SharedPreferences> Function()? _preferencesProvider;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);
  bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;
  String _key(DesktopDownloadPurpose purpose) =>
      'desktop_download_directory_v1_${purpose.name}';
  String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';

  Future<void> openSavedFile(String path) async {
    if (_mac) {
      if (await _channel.invokeMethod<bool>('openSavedFile', {'path': path}) !=
          true) {
        throw StateError('File could not be opened');
      }
    } else if (!await launchUrl(
      Uri.file(path),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('File could not be opened');
    }
  }

  Future<String> directory(DesktopDownloadPurpose purpose) async {
    if (_mac) {
      final path = await _channel.invokeMethod<String>('directory', {
        'purpose': purpose.name,
      });
      if (path == null || path.isEmpty) {
        throw StateError('Download directory unavailable');
      }
      return path;
    }
    final prefs =
        await (_preferencesProvider ?? SharedPreferences.getInstance)();
    final custom = prefs.getString(_key(purpose));
    if (custom != null && custom.isNotEmpty) return custom;
    final downloads = await (_downloadsProvider ?? getDownloadsDirectory)();
    if (downloads == null) throw StateError('System Downloads unavailable');
    return downloads.path;
  }

  Future<String?> chooseDirectory(DesktopDownloadPurpose purpose) async {
    if (_mac) {
      return _channel.invokeMethod<String>('chooseDirectory', {
        'purpose': purpose.name,
      });
    }
    final path = await (_picker ?? FilePicker.platform).getDirectoryPath();
    if (path == null) return null;
    if (!await Directory(path).exists()) {
      throw StateError('Directory unavailable');
    }
    final prefs =
        await (_preferencesProvider ?? SharedPreferences.getInstance)();
    if (!await prefs.setString(_key(purpose), path)) {
      throw StateError('Directory was not saved');
    }
    return path;
  }

  Future<String> resetDirectory(DesktopDownloadPurpose purpose) async {
    if (_mac) {
      final path = await _channel.invokeMethod<String>('resetDirectory', {
        'purpose': purpose.name,
      });
      if (path == null) throw StateError('Download directory unavailable');
      return path;
    }
    final prefs =
        await (_preferencesProvider ?? SharedPreferences.getInstance)();
    if (!await prefs.remove(_key(purpose))) {
      throw StateError('Directory was not reset');
    }
    return directory(purpose);
  }

  /// Null means the account/page lease expired; never report this as saved.
  Future<String?> save({
    required String sourcePath,
    required String fileName,
    required bool Function() isActive,
    DesktopDownloadPurpose purpose = DesktopDownloadPurpose.single,
  }) async {
    if (!isActive()) return null;
    if (!supported) throw UnsupportedError('Desktop downloads only');
    final name = fileName
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[:*?"<>|\x00-\x1F\x7F]'), '_')
        .trim();
    if (name.isEmpty || name == '.' || name == '..') {
      throw const FormatException('Invalid filename');
    }
    if (_mac) {
      final id = await _channel.invokeMethod<String>('prepare', {
        'purpose': purpose.name,
        'sourcePath': sourcePath,
        'fileName': name,
      });
      if (id == null) throw StateError('Download preparation failed');
      try {
        if (!isActive()) return null;
        final path = await _channel.invokeMethod<String>('commit', {'id': id});
        if (path == null || path.isEmpty) {
          throw StateError('Download commit failed');
        }
        return path;
      } finally {
        await _channel.invokeMethod<void>('discard', {'id': id});
      }
    }
    final destination = Directory(await directory(purpose));
    if (!isActive()) return null;
    // A missing/disconnected user choice is an error, never silently save elsewhere.
    if (!await destination.exists()) {
      throw StateError('Download directory unavailable');
    }
    final staging = await destination.createTemp('.bnbu-download-');
    try {
      final source = File(sourcePath);
      final length = await source.length();
      if (length > 1024 * 1024 * 1024) throw StateError('Download too large');
      final copy = await source.copy(_join(staging.path, 'download'));
      if (await copy.length() != length) throw StateError('Incomplete copy');
      if (!isActive()) return null;
      var target = _join(destination.path, name);
      if (await FileSystemEntity.type(target) !=
          FileSystemEntityType.notFound) {
        final dot = name.lastIndexOf('.');
        final stem = dot > 0 ? name.substring(0, dot) : name;
        final extension = dot > 0 ? name.substring(dot) : '';
        final unique = staging.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last
            .substring(15);
        target = _join(destination.path, '$stem ($unique)$extension');
      }
      if (!isActive()) return null;
      if (await FileSystemEntity.type(target) !=
          FileSystemEntityType.notFound) {
        throw StateError('Download destination already exists');
      }
      await copy.rename(target);
      return target;
    } finally {
      await staging.delete(recursive: true);
    }
  }
}
