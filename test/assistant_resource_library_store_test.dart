import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_resource.dart';
import 'package:bnbu_me/services/assistant_resource_library_store.dart';

void main() {
  test('resource library persists archives per normalized account', () async {
    final root = await Directory.systemTemp.createTemp(
      'assistant-resource-library-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final source = File('${root.path}/generated.zip');
    await source.writeAsBytes([1, 2, 3, 4], flush: true);
    final store = FileSystemAssistantResourceLibraryStore(
      documentsDirectoryLoader: () async => root,
      random: Random(7),
    );

    final saved = await store.importFile(
      'Student01',
      sourcePath: source.path,
      fileName: 'OOP / 课件.zip',
      mimeType: 'application/zip',
      kind: AssistantResourceKind.courseArchive,
      sourceTitle: 'Object-Oriented Programming',
      summary: '2 个课件',
    );

    expect(saved.fileName, '课件.zip');
    expect(await File(saved.filePath).readAsBytes(), [1, 2, 3, 4]);
    expect(await store.load('student01'), hasLength(1));
    expect(await store.load('another-student'), isEmpty);

    await store.delete('STUDENT01', saved);
    expect(await store.load('student01'), isEmpty);
    expect(await File(saved.filePath).exists(), isFalse);
  });
}
