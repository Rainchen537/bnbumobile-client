import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/upload_file_payload.dart';
import 'package:bnbu_me/services/assignment_file_selection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AssignmentFileSelection selection;
  final calls = <String>[];
  const channel = MethodChannel('desktop_drop');

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bnbu-drop-test-');
    selection = AssignmentFileSelection();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return true;
        });
  });
  tearDown(() async {
    selection.dispose();
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  Future<UploadFilePayload> file(String name, [int bytes = 5]) async {
    final target = File('${temp.path}/$name');
    await target.writeAsBytes(List.filled(bytes, 1));
    return UploadFilePayload(fileName: name, filePath: target.path);
  }

  Future<void> add(
    List<UploadFilePayload> files, {
    int count = 3,
    int bytes = 10,
  }) => selection.add(
    files,
    maxFiles: count,
    maxBytes: bytes,
    isCurrent: () => true,
  );

  test(
    'multiple drops and picker additions append, same path is deduplicated',
    () async {
      final a = await file('报告 一.txt');
      final b = await file('two.txt');
      await add([a]);
      await add([a, b]);
      expect(selection.files, [a, b]);
      selection.remove(a);
      expect(selection.files, [b]);
      expect(await File(a.filePath!).exists(), isTrue);
    },
  );

  test(
    'size is per file and oversize/count errors preserve existing selection',
    () async {
      final a = await file('a.txt', 10);
      final b = await file('b.txt', 10);
      await add([a, b]);
      expect(selection.files.length, 2); // Combined size is deliberately > 10.
      await expectLater(
        add([await file('big.txt', 11)]),
        throwsA(isA<AssignmentFileSelectionException>()),
      );
      await expectLater(
        add([await file('c.txt')], count: 2),
        throwsA(isA<AssignmentFileSelectionException>()),
      );
      expect(selection.files, [a, b]);
    },
  );

  test(
    'directories, missing files, links and colliding names are rejected',
    () async {
      final a = await file('a.txt');
      await add([a]);
      final dir = await Directory('${temp.path}/folder').create();
      final link = await Link('${temp.path}/shortcut').create(a.filePath!);
      for (final path in [dir.path, '${temp.path}/missing', link.path]) {
        await expectLater(
          add([UploadFilePayload(fileName: 'invalid', filePath: path)]),
          throwsA(isA<AssignmentFileSelectionException>()),
        );
      }
      final b = await file('b.txt');
      await expectLater(
        add([UploadFilePayload(fileName: 'A.TXT', filePath: b.filePath)]),
        throwsA(isA<AssignmentFileSelectionException>()),
      );
      expect(selection.files, [a]);
    },
  );

  test(
    'bookmarks remain active until removal and failed batches release them',
    () async {
      final a = await file('scoped.txt');
      final bookmark = Uint8List.fromList([1]);
      await selection.add(
        [a],
        maxFiles: 2,
        maxBytes: 10,
        isCurrent: () => true,
        bookmarks: {a: bookmark},
      );
      expect(calls, ['startAccessingSecurityScopedResource']);
      selection.remove(a);
      await Future<void>.delayed(Duration.zero);
      expect(calls.last, 'stopAccessingSecurityScopedResource');
      calls.clear();
      await expectLater(
        selection.add(
          [a],
          maxFiles: 2,
          maxBytes: 1,
          isCurrent: () => true,
          bookmarks: {a: bookmark},
        ),
        throwsA(isA<AssignmentFileSelectionException>()),
      );
      expect(selection.files, isEmpty);
      expect(calls, [
        'startAccessingSecurityScopedResource',
        'stopAccessingSecurityScopedResource',
      ]);
    },
  );

  test(
    'logout or disposal while native access is pending rejects late files',
    () async {
      final a = await file('late.txt');
      final started = Completer<void>();
      final release = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method.startsWith('start')) {
              started.complete();
              return release.future;
            }
            return true;
          });
      var current = true;
      final pending = selection.add(
        [a],
        maxFiles: 2,
        maxBytes: 10,
        isCurrent: () => current,
        bookmarks: {
          a: Uint8List.fromList([1]),
        },
      );
      await started.future;
      current = false;
      selection.dispose();
      release.complete(true);
      await pending;
      expect(selection.files, isEmpty);
      expect(calls.last, 'stopAccessingSecurityScopedResource');
    },
  );
}
