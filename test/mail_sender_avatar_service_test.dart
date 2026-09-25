import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/services/mail_sender_avatar_service.dart';

void main() {
  test(
    'audited public roster portraits retain exact host and query boundaries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'directory-source-photo-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bytes = image.encodePng(image.Image(width: 96, height: 96));
      final requested = <Uri>[];
      final service = IoMailSenderAvatarService(
        directoryService: _TeacherDirectoryService(),
        cacheDirectoryLoader: () async => directory,
        imageClient: MockClient((r) async {
          requested.add(r.url);
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
        thumbnailCompressor: (source) async => source,
      );
      addTearDown(service.dispose);
      for (final url in [
        'https://ar.bnbu.edu.cn/virtual_attach_file.vsb?afc=public&oid=123&e=.jpg',
        'https://www.bnbu.edu.cn/boc/virtual_attach_file.vsb?afc=public&oid=456&e=.png',
      ]) {
        expect(await service.loadTeacherPortrait(url), isNotNull);
      }
      for (final url in [
        'https://ar.bnbu.edu.cn.evil.test/virtual_attach_file.vsb?afc=public&oid=123&e=.jpg',
        'https://ar.bnbu.edu.cn/virtual_attach_file.vsb?afc=public&oid=123&e=.jpg&token=secret',
        'https://ar.bnbu.edu.cn/other.jpg',
        'http://ar.bnbu.edu.cn/virtual_attach_file.vsb?afc=public&oid=123&e=.jpg',
      ]) {
        expect(await service.loadTeacherPortrait(url), isNull);
      }
      expect(requested.length, 2);
    },
  );
  test(
    'empty and corrupt disk portraits are repaired instead of cached as success',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'teacher-corrupt-cache-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bytes = image.encodePng(image.Image(width: 96, height: 96));
      var downloads = 0;
      IoMailSenderAvatarService makeCache() => IoMailSenderAvatarService(
        directoryService: _TeacherDirectoryService(),
        cacheDirectoryLoader: () async => directory,
        imageClient: MockClient((_) async {
          downloads++;
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
        thumbnailCompressor: (source) async => source,
      );
      const url = 'https://staff.bnbu.edu.cn/fixture.jpg';
      final first = makeCache();
      await first.loadTeacherPortrait(url);
      first.dispose();
      final file =
          (await directory
                      .list()
                      .where((e) => e.path.endsWith('.bin'))
                      .toList())
                  .single
              as File;
      for (final corrupt in [
        <int>[],
        [1, 2, 3],
      ]) {
        await file.writeAsBytes(corrupt);
        final cache = makeCache();
        final restored = await cache.loadTeacherPortrait(url);
        expect(restored, bytes);
        cache.dispose();
      }
      expect(downloads, 3);
    },
  );
  test(
    'teacher portrait is compressed and reused from the device cache',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'mail-avatar-cache-test-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));

      final source = image.Image(width: 360, height: 240);
      image.fill(source, color: image.ColorRgb8(42, 92, 146));
      final sourceBytes = image.encodePng(source);
      var imageRequests = 0;
      final directoryService = _TeacherDirectoryService();
      final service = IoMailSenderAvatarService(
        directoryService: directoryService,
        imageClient: MockClient((request) async {
          imageRequests++;
          expect(request.url.host, 'staff.bnbu.edu.cn');
          return http.Response.bytes(
            sourceBytes,
            HttpStatus.ok,
            headers: const {'content-type': 'image/png'},
          );
        }),
        cacheDirectoryLoader: () async => temporaryDirectory,
        retryDelay: (_) async {},
        thumbnailCompressor: (source) async =>
            compressMailAvatarThumbnail(source),
      );
      addTearDown(service.dispose);

      final thumbnail = await service.loadThumbnail(
        'Teacher Chen <teacher.chen@bnbu.edu.cn>',
      );

      expect(thumbnail, isNotNull);
      expect(thumbnail, hasLength(lessThan(96 * 1024)));
      final decoded = image.decodePng(thumbnail!);
      expect(decoded?.width, IoMailSenderAvatarService.thumbnailDimension);
      expect(decoded?.height, IoMailSenderAvatarService.thumbnailDimension);
      expect(directoryService.teacherRequests, 1);
      expect(imageRequests, 1);

      expect(
        await service.loadThumbnail('teacher.chen@bnbu.edu.cn'),
        thumbnail,
      );
      expect(directoryService.teacherRequests, 1);
      expect(imageRequests, 1);

      final cachedService = IoMailSenderAvatarService(
        directoryService: _FailingDirectoryService(),
        imageClient: MockClient((_) async {
          fail('a fresh device cache entry must avoid the network');
        }),
        cacheDirectoryLoader: () async => temporaryDirectory,
      );
      addTearDown(cachedService.dispose);

      final cached = await cachedService.loadThumbnail(
        'teacher.chen@bnbu.edu.cn',
      );

      expect(cached, thumbnail);
    },
  );

  test(
    'directory portrait variants persist and mailbox reuses the small URL cache',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'shared-teacher-portrait-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = image.Image(width: 520, height: 600);
      image.fill(source, color: image.ColorRgb8(33, 122, 170));
      final encoded = image.encodePng(source);
      var downloads = 0;
      final service = IoMailSenderAvatarService(
        directoryService: _TeacherDirectoryService(),
        imageClient: MockClient((request) async {
          downloads++;
          return http.Response.bytes(
            encoded,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
        cacheDirectoryLoader: () async => directory,
        thumbnailCompressor: (bytes) async =>
            compressMailAvatarThumbnail(bytes),
      );
      addTearDown(service.dispose);
      const url = 'https://staff.bnbu.edu.cn/public/teacher-chen.png';
      expect(await service.hasCachedTeacherPortrait(url), isFalse);
      final small = await service.loadTeacherPortrait(url);
      expect(await service.hasCachedTeacherPortrait(url), isTrue);
      final large = await service.loadTeacherPortrait(url, dimension: 320);
      expect(image.decodeImage(small!)!.width, 96);
      expect(image.decodeImage(large!)!.width, 320);
      expect(
        large.length,
        lessThanOrEqualTo(IoMailSenderAvatarService.maximumThumbnailBytes),
      );
      expect(downloads, 2);
      expect(await service.loadThumbnail('teacher.chen@bnbu.edu.cn'), small);
      expect(downloads, 2);
      final restarted = IoMailSenderAvatarService(
        directoryService: _FailingDirectoryService(),
        imageClient: MockClient((request) async => throw StateError('offline')),
        cacheDirectoryLoader: () async => directory,
      );
      addTearDown(restarted.dispose);
      expect(await restarted.hasCachedTeacherPortrait(url), isTrue);
      final expired = IoMailSenderAvatarService(
        directoryService: _FailingDirectoryService(),
        imageClient: MockClient((_) async => throw StateError('offline')),
        cacheDirectoryLoader: () async => directory,
        now: () => DateTime.now().add(const Duration(days: 31)),
      );
      addTearDown(expired.dispose);
      expect(await expired.hasCachedTeacherPortrait(url), isFalse);
      expect(await restarted.loadTeacherPortrait(url), small);
      expect(await restarted.loadTeacherPortrait(url, dimension: 320), large);
      expect(
        await restarted.loadTeacherPortrait(
          'https://staff.bnbu.edu.cn.evil.test/photo.png',
        ),
        isNull,
      );
      expect(downloads, 2);
    },
  );

  test('external senders do not query the official directory', () async {
    final directoryService = _FailingDirectoryService();
    final service = IoMailSenderAvatarService(
      directoryService: directoryService,
      imageClient: MockClient((_) async => http.Response('', 500)),
      cacheDirectoryLoader: () async => Directory.systemTemp,
    );
    addTearDown(service.dispose);

    expect(await service.loadThumbnail('Partner <person@example.com>'), isNull);
    expect(
      await service.loadThumbnail('Student <student01@mail.bnbu.edu.cn>'),
      isNull,
    );
    expect(directoryService.requests, 0);
  });

  test(
    'graduate school portrait uses its constrained public image URL',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'mail-avatar-graduate-test-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final source = image.Image(width: 120, height: 160);
      image.fill(source, color: image.ColorRgb8(110, 70, 140));
      final sourceBytes = image.encodeJpg(source);
      var imageRequests = 0;
      final service = IoMailSenderAvatarService(
        directoryService: _GraduateDirectoryService(),
        imageClient: MockClient((request) async {
          imageRequests++;
          expect(request.url.host, 'gs.bnbu.edu.cn');
          expect(request.url.path, '/graduate/virtual_attach_file.vsb');
          return http.Response.bytes(
            sourceBytes,
            HttpStatus.ok,
            headers: const {'content-type': 'image/jpeg'},
          );
        }),
        cacheDirectoryLoader: () async => temporaryDirectory,
        retryDelay: (_) async {},
        thumbnailCompressor: (source) async =>
            compressMailAvatarThumbnail(source),
      );
      addTearDown(service.dispose);

      final thumbnail = await service.loadThumbnail(
        'Graduate Teacher <graduate.teacher@bnbu.edu.cn>',
      );

      expect(thumbnail, isNotNull);
      expect(imageRequests, 1);
    },
  );

  test(
    'temporary directory failure is not cached as a missing teacher',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'mail-avatar-retry-test-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final failing = IoMailSenderAvatarService(
        directoryService: _FailingDirectoryService(),
        imageClient: MockClient((_) async => http.Response('', 500)),
        cacheDirectoryLoader: () async => temporaryDirectory,
        retryDelay: (_) async {},
      );
      addTearDown(failing.dispose);

      expect(await failing.loadThumbnail('teacher.chen@bnbu.edu.cn'), isNull);
      expect(
        temporaryDirectory.listSync().where(
          (entry) => entry.path.endsWith('.missing'),
        ),
        isEmpty,
      );

      final source = image.Image(width: 96, height: 96);
      image.fill(source, color: image.ColorRgb8(40, 120, 90));
      final sourceBytes = image.encodePng(source);
      final recoveredDirectory = _TeacherDirectoryService();
      final recovered = IoMailSenderAvatarService(
        directoryService: recoveredDirectory,
        imageClient: MockClient(
          (_) async => http.Response.bytes(
            sourceBytes,
            HttpStatus.ok,
            headers: const {'content-type': 'image/png'},
          ),
        ),
        cacheDirectoryLoader: () async => temporaryDirectory,
        retryDelay: (_) async {},
        thumbnailCompressor: (source) async =>
            compressMailAvatarThumbnail(source),
      );
      addTearDown(recovered.dispose);

      expect(
        await recovered.loadThumbnail('teacher.chen@bnbu.edu.cn'),
        isNotNull,
      );
      expect(recoveredDirectory.teacherRequests, 1);
    },
  );

  test('teacher portrait work is limited to four concurrent loads', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'mail-avatar-concurrency-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final directoryService = _ConcurrencyDirectoryService();
    final service = IoMailSenderAvatarService(
      directoryService: directoryService,
      imageClient: MockClient(
        (_) async => http.Response.bytes(
          const [1, 2, 3],
          HttpStatus.ok,
          headers: const {'content-type': 'image/png'},
        ),
      ),
      cacheDirectoryLoader: () async => temporaryDirectory,
      retryDelay: (_) async {},
      thumbnailCompressor: (_) async => Uint8List.fromList(const [4, 5, 6]),
    );
    addTearDown(service.dispose);

    final loads = List.generate(
      6,
      (index) => service.loadThumbnail('teacher$index@bnbu.edu.cn'),
    );
    while (directoryService.requests < 4) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(directoryService.requests, 4);
    expect(directoryService.peakActive, 4);
    directoryService.release.complete();
    expect(await Future.wait(loads), everyElement(isNotNull));
    expect(directoryService.requests, 6);
    expect(directoryService.peakActive, 4);
  });
}

class _TeacherDirectoryService implements CampusDirectoryService {
  int teacherRequests = 0;

  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async =>
      const [];

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    teacherRequests++;
    return const OfficialTeacherPage(
      items: [
        OfficialTeacherProfile(
          name: '陈老师',
          nameEn: 'Teacher Chen',
          email: 'teacher.chen@bnbu.edu.cn',
          title: '副教授',
          titleEn: 'Associate Professor',
          position: '',
          office: '',
          telephone: '',
          academicCn: '',
          academicEn: '',
          educationCn: '',
          educationEn: '',
          unitNames: ['工商管理学院'],
          photoUrl: 'https://staff.bnbu.edu.cn/public/teacher-chen.png',
          profileUrl: '',
          sourceUpdatedAt: null,
        ),
      ],
      total: 1,
      offset: 0,
      limit: 10,
      units: ['工商管理学院'],
    );
  }

  @override
  void dispose() {}
}

class _FailingDirectoryService implements CampusDirectoryService {
  int requests = 0;

  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async {
    requests++;
    throw const CampusDirectoryException('offline');
  }

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    requests++;
    throw const CampusDirectoryException('offline');
  }

  @override
  void dispose() {}
}

class _GraduateDirectoryService implements CampusDirectoryService {
  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async => [
    CampusDirectoryOrganization(
      id: 'graduate-school',
      category: CampusDirectoryCategory.college,
      nameCn: '研究生院',
      nameEn: 'Graduate School',
      shortName: 'GS',
      websiteUrl: 'https://gs.bnbu.edu.cn',
      facultyUrl: '',
      teacherUnit: '研究生院',
      office: '',
      phones: const [],
      emails: const ['gs@bnbu.edu.cn'],
      responsibilities: const [],
      contacts: const [],
      embeddedStaff: const [
        OfficialTeacherProfile(
          name: '研究生教师',
          nameEn: 'Graduate Teacher',
          email: 'graduate.teacher@bnbu.edu.cn',
          title: '教授',
          titleEn: 'Professor',
          position: '',
          office: '',
          telephone: '',
          academicCn: '',
          academicEn: '',
          educationCn: '',
          educationEn: '',
          unitNames: ['研究生院'],
          photoUrl:
              'https://gs.bnbu.edu.cn/graduate/virtual_attach_file.vsb?afc=public-token&oid=1707097125&e=.jpg',
          profileUrl: 'https://gs.bnbu.edu.cn/graduate/about/jzy.htm',
          sourceUpdatedAt: null,
        ),
      ],
      sourceUrls: const ['https://gs.bnbu.edu.cn/graduate/about/jzy.htm'],
    ),
  ];

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    throw const CampusDirectoryException('offline');
  }

  @override
  void dispose() {}
}

class _ConcurrencyDirectoryService implements CampusDirectoryService {
  final Completer<void> release = Completer<void>();
  int requests = 0;
  int active = 0;
  int peakActive = 0;

  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async =>
      const [];

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    requests++;
    active++;
    if (active > peakActive) {
      peakActive = active;
    }
    await release.future;
    active--;
    return OfficialTeacherPage(
      items: [
        OfficialTeacherProfile(
          name: query,
          nameEn: '',
          email: query,
          title: '',
          titleEn: '',
          position: '',
          office: '',
          telephone: '',
          academicCn: '',
          academicEn: '',
          educationCn: '',
          educationEn: '',
          unitNames: const [],
          photoUrl: 'https://staff.bnbu.edu.cn/public/$query.png',
          profileUrl: '',
          sourceUpdatedAt: null,
        ),
      ],
      total: 1,
      offset: 0,
      limit: limit,
      units: const [],
    );
  }

  @override
  void dispose() {}
}
