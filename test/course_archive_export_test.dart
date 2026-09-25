import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/course_archive_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/course_archive_export');
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  var active = true;
  var expireAfterCopy = false;
  var failCommit = false;
  late _Picker picker;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    active = true;
    expireAfterCopy = false;
    failCommit = false;
    picker = _Picker();
    binding.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'prepare') {
        expect(call.arguments, {
          'sourcePath': '/source.zip',
          'destinationPath': '/chosen/course.zip',
        });
        if (expireAfterCopy) active = false;
        return 'temporary-handle';
      }
      expect(call.arguments, {'id': 'temporary-handle'});
      if (call.method == 'commit' && failCommit) {
        throw PlatformException(code: 'test_failure');
      }
      return call.method == 'commit' ? true : null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.setMockMethodCallHandler(channel, null);
  });
  Future<bool> export() =>
      CourseArchiveExportService(picker: picker, channel: channel).export(
        sourcePath: '/source.zip',
        fileName: 'course.zip',
        dialogTitle: '保存 ZIP',
        isActive: () => active,
      );

  test('save panel cancel writes nothing', () async {
    picker.path = null;
    expect(await export(), isFalse);
    expect(calls, isEmpty);
  });
  test('inactive lease never opens a save panel', () async {
    active = false;
    expect(await export(), isFalse);
    expect(picker.calls, 0);
  });
  test(
    'macOS commits a prepared native export without creating a Dart sibling directory',
    () async {
      expect(await export(), isTrue);
      expect(calls, ['prepare', 'commit', 'discard']);
    },
  );
  test(
    'closing or changing account during copying discards without overwriting',
    () async {
      expireAfterCopy = true;
      expect(await export(), isFalse);
      expect(calls, ['prepare', 'discard']);
    },
  );
  test(
    'commit failure cleans temporary export and cannot report success',
    () async {
      failCommit = true;
      await expectLater(export(), throwsA(isA<PlatformException>()));
      expect(calls, ['prepare', 'commit', 'discard']);
    },
  );
  test(
    'main app permits Downloads and scoped user choices without disabling sandbox',
    () {
      for (final lane in [
        'Release',
        'ReleaseBuild',
        'DebugProfile',
        'Acceptance',
      ]) {
        final source = File(
          'macos/Runner/$lane.entitlements',
        ).readAsStringSync();
        expect(
          source,
          contains(
            '<key>com.apple.security.files.user-selected.read-write</key>',
          ),
        );
        expect(source, isNot(contains('files.user-selected.read-only')));
        expect(source, contains('<key>com.apple.security.app-sandbox</key>'));
        expect(source, contains('files.downloads.read-write'));
        expect(source, contains('files.bookmarks.app-scope'));
      }
      final widget = File(
        'macos/Runner/Widget.entitlements',
      ).readAsStringSync();
      expect(widget, isNot(contains('files.downloads.read-write')));
      expect(widget, isNot(contains('files.bookmarks.app-scope')));
    },
  );
}

class _Picker extends FilePicker {
  String? path = '/chosen/course.zip';
  int calls = 0;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls++;
    expect(type, FileType.custom);
    expect(allowedExtensions, ['zip']);
    expect(bytes, isNull); // Never load a 512 MB archive into a Dart channel.
    return path;
  }
}
