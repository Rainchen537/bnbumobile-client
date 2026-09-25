import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/pages/campus_directory_page.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';

class DirectoryFixture
    implements CampusDirectoryService, VersionedCampusDirectoryService {
  bool failNext = false;
  bool changeVersion = false;
  final calls = <(String, int, String, bool)>[];
  Completer<OfficialTeacherPage>? delayed;
  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async => [
    CampusDirectoryOrganization.fromJson({
      'id': 'college-test',
      'category': 'college',
      'name_cn': '测试学院',
      'teacher_unit': '测试学院',
      'staff': [],
    }),
  ];
  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) => loadTeacherSnapshot(
    query: query,
    unit: unit,
    offset: offset,
    limit: limit,
  );
  @override
  Future<OfficialTeacherPage> loadTeacherSnapshot({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
    String snapshotVersion = '',
    bool refresh = false,
  }) async {
    calls.add((query, offset, snapshotVersion, refresh));
    if (query.isEmpty) {
      return const OfficialTeacherPage(
        items: [],
        total: 0,
        offset: 0,
        limit: 60,
        units: [],
      );
    }
    if (query == 'old' && delayed != null) return delayed!.future;
    if (failNext) {
      failNext = false;
      throw const CampusDirectoryException('network');
    }
    if (changeVersion && offset > 0) {
      throw const CampusDirectoryException('changed', snapshotChanged: true);
    }
    return page(query, offset, version: changeVersion ? 'v2' : 'v1');
  }

  OfficialTeacherPage page(String query, int offset, {String version = 'v1'}) =>
      OfficialTeacherPage(
        items: List.generate(
          offset == 0 ? 2 : 1,
          (i) => OfficialTeacherProfile.fromJson({
            'name': '$query ${offset + i}',
            'name_en': '$query ${offset + i}',
            'email': 'person${offset + i}@example.invalid',
            'unit_names': ['测试学院'],
          }),
        ),
        total: 3,
        offset: offset,
        limit: 60,
        units: ['测试学院'],
        sync: DirectorySyncInfo(version: version),
      );
  @override
  void dispose() {}
}

Future<void> mount(
  WidgetTester tester,
  DirectoryFixture service, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = AppSessionController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: CampusDirectoryPage(
        controller: controller,
        directoryService: service,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> query(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('campus-directory-search')),
    text,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'snapshot transport preserves metadata and detects version conflicts',
    () async {
      var requestCount = 0;
      final service = RemoteCampusDirectoryService(
        baseUrl: 'https://directory.example',
        client: MockClient((request) async {
          requestCount++;
          if (requestCount == 1) {
            return http.Response(
              jsonEncode({
                'items': [],
                'total': 0,
                'offset': 0,
                'limit': 60,
                'units': [],
                'sync': {
                  'version': 'v1',
                  'status': 'current',
                  'last_success_at': '2026-09-14T07:35:00Z',
                },
              }),
              200,
            );
          }
          expect(request.url.queryParameters['snapshot_version'], 'v1');
          return http.Response('{}', 409);
        }),
      );
      addTearDown(service.dispose);
      final first = await service.loadTeacherSnapshot(query: 'Demo');
      expect(first.sync?.version, 'v1');
      expect(first.sync?.lastSuccessAt, DateTime.utc(2026, 9, 14, 7, 35));
      await expectLater(
        service.loadTeacherSnapshot(
          query: 'Demo',
          offset: 60,
          snapshotVersion: 'v1',
        ),
        throwsA(
          isA<CampusDirectoryException>().having(
            (e) => e.snapshotChanged,
            'snapshotChanged',
            true,
          ),
        ),
      );
      final legacy = OfficialTeacherPage.fromJson({
        'items': [],
        'total': 0,
        'offset': 0,
        'limit': 60,
        'units': [],
      });
      expect(legacy.sync, isNull);
    },
  );

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('pagination retains first page and retries at $width', (
      tester,
    ) async {
      final service = DirectoryFixture();
      await mount(tester, service, width: width);
      await query(tester, 'Demo');
      expect(find.textContaining('2 / 3'), findsOneWidget);
      service.failNext = true;
      await click(tester, 'directory-search-load-more');
      expect(find.text('Demo 0'), findsOneWidget);
      expect(find.text('师资目录加载失败'), findsOneWidget);
      expect(find.text('没有匹配的政教信息'), findsNothing);
      await click(tester, 'directory-search-retry');
      expect(find.textContaining('3 / 3'), findsOneWidget);
      expect(find.text('Demo 2'), findsOneWidget);
      expect(service.calls.last, ('Demo', 2, 'v1', true));
      expect(
        find.byKey(const ValueKey('directory-search-load-more')),
        findsNothing,
      );
    });
  }
  testWidgets('changed snapshot reloads first page without mixing', (
    tester,
  ) async {
    final service = DirectoryFixture();
    await mount(tester, service);
    await query(tester, 'Demo');
    service.changeVersion = true;
    await click(tester, 'directory-search-load-more');
    expect(find.text('师资目录已更新，请重新加载'), findsOneWidget);
    expect(find.text('Demo 0'), findsOneWidget);
    await click(tester, 'directory-search-retry');
    expect(service.calls.last, ('Demo', 0, '', true));
    expect(find.textContaining('2 / 3'), findsOneWidget);
  });
  testWidgets('first page failure differs from empty and can retry', (
    tester,
  ) async {
    final service = DirectoryFixture();
    await mount(tester, service);
    service.failNext = true;
    await query(tester, 'Nobody');
    expect(find.text('没有匹配的政教信息'), findsNothing);
    expect(find.text('师资目录加载失败'), findsOneWidget);
    await click(tester, 'directory-search-retry');
    expect(find.text('Nobody 0'), findsOneWidget);
  });
  testWidgets('late request cannot replace another query', (tester) async {
    final service = DirectoryFixture()..delayed = Completer();
    await mount(tester, service);
    await tester.enterText(
      find.byKey(const ValueKey('campus-directory-search')),
      'old',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await query(tester, 'New');
    service.delayed!.complete(service.page('old', 0));
    await tester.pumpAndSettle();
    expect(find.text('New 0'), findsOneWidget);
    expect(find.text('old 0'), findsNothing);
  });
}
