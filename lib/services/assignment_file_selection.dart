import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';

import '../models/upload_file_payload.dart';

class AssignmentFileSelectionException implements Exception {
  const AssignmentFileSelectionException(this.message);
  final String message;
}

/// Page-local file references. No upload occurs until the user submits.
class AssignmentFileSelection {
  AssignmentFileSelection({List<UploadFilePayload> initialFiles = const []})
    : _files = List.of(initialFiles);

  List<UploadFilePayload> _files;
  final Map<UploadFilePayload, Uint8List> _bookmarks = {};
  int _generation = 0;
  bool _disposed = false;

  List<UploadFilePayload> get files => List.unmodifiable(_files);

  Future<void> add(
    List<UploadFilePayload> candidates, {
    required int maxFiles,
    required int maxBytes,
    required bool Function() isCurrent,
    Map<UploadFilePayload, Uint8List> bookmarks = const {},
  }) async {
    final generation = _generation;
    bool active() => !_disposed && generation == _generation && isCurrent();
    final accepted = <UploadFilePayload>[];
    final acquired = <UploadFilePayload, Uint8List>{};
    try {
      for (final candidate in candidates) {
        if (!active()) return;
        if (_files
            .followedBy(accepted)
            .any(
              (file) =>
                  candidate.filePath != null &&
                  file.filePath == candidate.filePath,
            )) {
          continue;
        }
        if (_files
            .followedBy(accepted)
            .any(
              (file) =>
                  file.fileName.toLowerCase() ==
                  candidate.fileName.toLowerCase(),
            )) {
          throw const AssignmentFileSelectionException(
            '存在同名文件，请先移除旧文件或重命名后添加。',
          );
        }
        if (maxFiles > 0 && _files.length + accepted.length >= maxFiles) {
          throw const AssignmentFileSelectionException('所选文件数量超过该作业允许的上限。');
        }
        final bookmark = bookmarks[candidate];
        if (bookmark != null && bookmark.isNotEmpty) {
          final opened = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
          if (opened) acquired[candidate] = bookmark;
          // Some sources already grant access; filesystem validation below
          // remains authoritative when startAccessing returns false.
        }
        if (!active()) return;
        final size = await _readableSize(candidate);
        if (maxBytes > 0 && size > maxBytes) {
          throw const AssignmentFileSelectionException('所选文件大小超过该作业允许的上限。');
        }
        accepted.add(candidate);
      }
      if (!active()) return;
      _files = [..._files, ...accepted];
      _bookmarks.addAll(acquired);
      acquired.clear();
    } on AssignmentFileSelectionException {
      rethrow;
    } catch (_) {
      throw const AssignmentFileSelectionException('选择的文件不可读取，请重试。');
    } finally {
      await _release(acquired.values);
    }
  }

  Future<int> _readableSize(UploadFilePayload payload) async {
    if (payload.filePath case final path?) {
      if (path.isEmpty ||
          await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const AssignmentFileSelectionException('请添加文件，不支持文件夹或快捷方式。');
      }
      final handle = await File(path).open();
      try {
        return await handle.length();
      } finally {
        await handle.close();
      }
    }
    if (payload.bytes case final bytes? when bytes.isNotEmpty) {
      return bytes.length;
    }
    throw const AssignmentFileSelectionException('选择的文件不可读取，请重试。');
  }

  void remove(UploadFilePayload file) {
    _generation++;
    _files.remove(file);
    final bookmark = _bookmarks.remove(file);
    if (bookmark != null) unawaited(_release([bookmark]));
  }

  void clear() {
    _generation++;
    _files = [];
    final bookmarks = _bookmarks.values.toList();
    _bookmarks.clear();
    unawaited(_release(bookmarks));
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  static Future<void> _release(Iterable<Uint8List> bookmarks) async {
    for (final bookmark in bookmarks) {
      try {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      } catch (_) {
        // Never expose native bookmark contents or filesystem paths in errors.
      }
    }
  }
}
