import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/course_archive_service.dart';

void main() {
  Future<CourseArchiveResult> buildBatch(
    CourseArchiveService service,
    Directory temp, {
    List<int> ids = const [1, 2, 3],
    bool Function()? active,
  }) => service.build(
    cacheDirectory: temp.path,
    archiveName: 'Course',
    baseUrl: 'https://ispace.example.edu',
    cookieHeader: 'MoodleSession=test',
    entries: ids
        .map(
          (id) => CourseArchiveEntry(
            url: 'https://ispace.example.edu/pluginfile.php/$id/slides.pdf',
            sectionName: 'Week $id',
            moduleName: 'Lecture',
            fileName: '$id.pdf',
            expectedBytes: 3,
          ),
        )
        .toList(),
    sessionIsActive: active ?? () => true,
  );

  test(
    'one failed file keeps successful files and retry produces one complete ZIP',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'course_partial_test_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final fetcher = _FlakyFetcher();
      final service = CourseArchiveService(
        fileFetcher: fetcher,
        continueOnFileError: true,
      );
      final partial = await buildBatch(service, temp);
      expect(partial.fileCount, 2);
      expect(partial.fileName, endsWith('-partial.zip'));
      expect(partial.failures.single.entry.fileName, '2.pdf');
      expect(partial.completedFileNames, ['1.pdf', '3.pdf']);
      final partialZip = ZipDecoder().decodeBytes(
        await File(partial.path).readAsBytes(),
      );
      expect(partialZip.files.where((f) => f.isFile).map((f) => f.name), [
        'Week 1/Lecture/1.pdf',
        'Week 3/Lecture/3.pdf',
      ]);
      fetcher.failing = false;
      final complete = await buildBatch(service, temp);
      expect(complete.failures, isEmpty);
      expect(complete.fileCount, 3);
      expect(complete.totalBytes, 9);
      expect(fetcher.calls, [1, 2, 3, 2]);
      final zip = ZipDecoder().decodeBytes(
        await File(complete.path).readAsBytes(),
      );
      expect(zip.files.where((f) => f.isFile), hasLength(3));
      expect(
        await temp
            .list(recursive: true)
            .where((f) => f.path.endsWith('.download'))
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'retry revalidates selection and never retains revoked cached files',
    () async {
      final temp = await Directory.systemTemp.createTemp('course_prune_test_');
      addTearDown(() => temp.delete(recursive: true));
      final fetcher = _FlakyFetcher();
      final service = CourseArchiveService(
        fileFetcher: fetcher,
        continueOnFileError: true,
      );
      await buildBatch(service, temp);
      fetcher.failing = false;
      final result = await buildBatch(service, temp, ids: [2, 3]);
      expect(result.completedFileNames, ['2.pdf', '3.pdf']);
      expect(fetcher.calls, [1, 2, 3, 2]);
    },
  );

  test(
    'expired lease clears the resume cache before another account builds',
    () async {
      final temp = await Directory.systemTemp.createTemp('course_lease_test_');
      addTearDown(() => temp.delete(recursive: true));
      final fetcher = _FlakyFetcher();
      final service = CourseArchiveService(
        fileFetcher: fetcher,
        continueOnFileError: true,
      );
      var active = true;
      await buildBatch(service, temp, active: () => active);
      active = false;
      fetcher.failing = false;
      await buildBatch(service, temp);
      expect(fetcher.calls, [1, 2, 3, 1, 2, 3]);
    },
  );

  test(
    'all failed files report reasons without publishing an empty ZIP',
    () async {
      final temp = await Directory.systemTemp.createTemp('course_empty_test_');
      addTearDown(() => temp.delete(recursive: true));
      final service = CourseArchiveService(
        fileFetcher: _FlakyFetcher(),
        continueOnFileError: true,
      );
      await expectLater(
        buildBatch(service, temp, ids: [2]),
        throwsA(
          isA<CourseArchiveException>().having(
            (e) => e.failures.length,
            'failed files',
            1,
          ),
        ),
      );
      expect(
        await temp.list(recursive: true).where((f) => f is File).toList(),
        isEmpty,
      );
    },
  );

  test(
    'transient failure retries once, permanent failure does not loop',
    () async {
      final temp = await Directory.systemTemp.createTemp('course_retry_test_');
      addTearDown(() => temp.delete(recursive: true));
      final fetcher = _FlakyFetcher()..transient = true;
      final service = CourseArchiveService(
        fileFetcher: fetcher,
        continueOnFileError: true,
      );
      final result = await buildBatch(service, temp);
      expect(fetcher.calls, [1, 2, 2, 3]);
      expect(result.failures.length, 1);
      service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        await temp
            .list(recursive: true)
            .where((f) => f.path.endsWith('.download'))
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'fatal size limit and old fail-fast mode never publish partial success',
    () async {
      for (final resilient in [false, true]) {
        final temp = await Directory.systemTemp.createTemp(
          'course_fatal_test_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final fetcher = _FlakyFetcher()..fatal = resilient;
        final service = CourseArchiveService(
          fileFetcher: fetcher,
          continueOnFileError: resilient,
        );
        await expectLater(
          buildBatch(service, temp),
          throwsA(isA<CourseArchiveException>()),
        );
        expect(fetcher.calls, [1, 2]);
        expect(
          await temp.list(recursive: true).where((f) => f is File).toList(),
          isEmpty,
        );
      }
    },
  );

  test('cancelling after the last file does not publish a ZIP', () async {
    final temp = await Directory.systemTemp.createTemp(
      'course_archive_cancel_',
    );
    addTearDown(() => temp.delete(recursive: true));
    var active = true;
    final service = CourseArchiveService(
      fileFetcher: _FakeFetcher({
        '/pluginfile.php/1/slides.pdf': [1, 2, 3],
      }),
    );
    await expectLater(
      service.build(
        cacheDirectory: temp.path,
        archiveName: 'Course',
        baseUrl: 'https://ispace.example.edu',
        cookieHeader: 'MoodleSession=test',
        entries: const [
          CourseArchiveEntry(
            url: 'https://ispace.example.edu/pluginfile.php/1/slides.pdf',
            sectionName: 'Week 1',
            moduleName: 'Lecture',
            fileName: 'slides.pdf',
            expectedBytes: 3,
          ),
        ],
        sessionIsActive: () => active,
        onProgress: (_) => active = false,
      ),
      throwsA(isA<CourseArchiveException>()),
    );
    expect(
      await temp.list(recursive: true).where((entry) => entry is File).toList(),
      isEmpty,
    );
  });

  test('builds a local ZIP organized by section and module', () async {
    final temp = await Directory.systemTemp.createTemp('course_archive_test_');
    addTearDown(() => temp.delete(recursive: true));
    final fetcher = _FakeFetcher({
      '/pluginfile.php/1/slides.pdf': [1, 2, 3],
      '/pluginfile.php/1/slides-copy.pdf': [4, 5],
    });
    final service = CourseArchiveService(fileFetcher: fetcher);

    final result = await service.build(
      cacheDirectory: temp.path,
      archiveName: 'C / Programming',
      baseUrl: 'https://ispace.example.edu',
      cookieHeader: 'MoodleSession=secret',
      entries: const [
        CourseArchiveEntry(
          url: 'https://ispace.example.edu/pluginfile.php/1/slides.pdf',
          sectionName: 'Week 1',
          moduleName: 'Lecture',
          fileName: 'slides.pdf',
          expectedBytes: 3,
        ),
        CourseArchiveEntry(
          url: 'https://ispace.example.edu/pluginfile.php/1/slides-copy.pdf',
          sectionName: 'Week 1',
          moduleName: 'Lecture',
          fileName: 'slides.pdf',
          expectedBytes: 2,
        ),
      ],
      sessionIsActive: () => true,
    );

    expect(result.fileName, 'C Programming.zip');
    expect(result.fileCount, 2);
    expect(result.totalBytes, 5);
    final archive = ZipDecoder().decodeBytes(
      await File(result.path).readAsBytes(),
    );
    expect(
      archive.files.map((file) => file.name),
      containsAll([
        'Week 1/Lecture/slides.pdf',
        'Week 1/Lecture/slides (2).pdf',
      ]),
    );
    expect(fetcher.cookieHeaders, everyElement('MoodleSession=secret'));
  });

  test('rejects cross-origin files before fetching', () async {
    final temp = await Directory.systemTemp.createTemp('course_archive_test_');
    addTearDown(() => temp.delete(recursive: true));
    final fetcher = _FakeFetcher(const {});
    final service = CourseArchiveService(fileFetcher: fetcher);

    await expectLater(
      service.build(
        cacheDirectory: temp.path,
        archiveName: 'Course',
        baseUrl: 'https://ispace.example.edu',
        cookieHeader: 'MoodleSession=secret',
        entries: const [
          CourseArchiveEntry(
            url: 'https://attacker.example/pluginfile.php/1/file.pdf',
            sectionName: 'Week 1',
            moduleName: 'Lecture',
            fileName: 'file.pdf',
            expectedBytes: 3,
          ),
        ],
        sessionIsActive: () => true,
      ),
      throwsA(
        isA<CourseArchiveException>().having(
          (error) => error.message,
          'message',
          contains('不安全'),
        ),
      ),
    );
    expect(fetcher.cookieHeaders, isEmpty);
  });
}

class _FlakyFetcher implements CourseArchiveFileFetcher {
  final calls = <int>[];
  bool failing = true;
  bool transient = false;
  bool fatal = false;
  @override
  Future<int> fetch({
    required Uri url,
    required Uri origin,
    required String cookieHeader,
    required File destination,
    required int remainingBytes,
    required bool Function() sessionIsActive,
  }) async {
    final id = int.parse(url.pathSegments[1]);
    calls.add(id);
    await destination.writeAsBytes([id, id, id]);
    if (id == 2 && failing) {
      if (transient) throw const SocketException('fake network failure');
      throw CourseArchiveException('文件链接返回了网页，无法作为课件下载。', fatal: fatal);
    }
    return 3;
  }
}

class _FakeFetcher implements CourseArchiveFileFetcher {
  _FakeFetcher(this.payloads);

  final Map<String, List<int>> payloads;
  final List<String> cookieHeaders = [];

  @override
  Future<int> fetch({
    required Uri url,
    required Uri origin,
    required String cookieHeader,
    required File destination,
    required int remainingBytes,
    required bool Function() sessionIsActive,
  }) async {
    cookieHeaders.add(cookieHeader);
    final payload = payloads[url.path]!;
    await destination.writeAsBytes(payload, flush: true);
    return payload.length;
  }
}
