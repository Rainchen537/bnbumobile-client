import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Exports only after the system save panel grants the selected destination.
/// macOS grants a file, not its parent directory: stage via Foundation's safe
/// replacement API instead of attempting to create an adjacent Dart directory.
class CourseArchiveExportService {
  const CourseArchiveExportService({
    FilePicker? picker,
    MethodChannel channel = const MethodChannel('ispace/course_archive_export'),
  }) : _picker = picker,
       _channel = channel;

  final FilePicker? _picker;
  final MethodChannel _channel;

  Future<bool> export({
    required String sourcePath,
    required String fileName,
    required String dialogTitle,
    required bool Function() isActive,
    List<String> allowedExtensions = const ['zip'],
  }) async {
    if (!isActive()) return false;
    final path = await (_picker ?? FilePicker.platform).saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (path == null || !isActive()) return false;
    if (File(sourcePath).absolute.path == File(path).absolute.path) return true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      final id = await _channel.invokeMethod<String>('prepare', {
        'sourcePath': sourcePath,
        'destinationPath': path,
      });
      if (id == null) throw StateError('File export preparation failed.');
      try {
        if (!isActive()) return false;
        final committed = await _channel.invokeMethod<bool>('commit', {
          'id': id,
        });
        if (committed != true) throw StateError('File export commit failed.');
        return true;
      } finally {
        await _channel.invokeMethod<void>('discard', {'id': id});
      }
    }
    // Windows has no App Sandbox extension restricting the selected parent.
    final staging = await File(path).parent.createTemp('.bnbu-courseware-');
    try {
      final copy = await File(sourcePath).copy('${staging.path}/archive.zip');
      if (!isActive()) return false;
      await copy.rename(path);
      return true;
    } finally {
      await staging.delete(recursive: true);
    }
  }
}
