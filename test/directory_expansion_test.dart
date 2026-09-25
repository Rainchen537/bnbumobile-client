import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/pages/campus_directory_page.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/services/mail_recipient_directory.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';

Map<String, dynamic> organization(String name) => {
  'id': 'admin-ar',
  'category': 'administration',
  'name_cn': '教务处',
  'website_url': 'https://ar.bnbu.edu.cn/',
  'short_name': 'AR',
  'staff': [
    {
      'name': name,
      'name_en': 'Fixture Person',
      'email': 'fixture@bnbu.edu.cn',
      'person_kind': 'staff',
      'unit_names': ['教务处'],
      'responsibilities': ['学分置换'],
      'source_urls': ['https://ar.bnbu.edu.cn/about_us/staff.htm'],
    },
  ],
  'services': [
    {
      'name_cn': '学籍组',
      'responsibilities': ['证明开具'],
      'emails': ['record@bnbu.edu.cn'],
      'service_hours': '9:00–17:00',
    },
  ],
  'sources': [
    {'id': 'fixture', 'status': 'fetched'},
  ],
};

class DirectoryFixture implements CampusDirectoryService {
  String name = '陈测试';
  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async => [
    CampusDirectoryOrganization.fromJson(organization(name)),
  ];
  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async => OfficialTeacherPage.fromJson({
    'items': [organization(name)['staff'][0]],
    'total': 1,
    'offset': offset,
    'limit': limit,
    'units': ['教务处'],
  });
  @override
  void dispose() {}
}

class CollegeFixture extends DirectoryFixture {
  final offsets = <int>[];
  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async => [
    CampusDirectoryOrganization.fromJson({
      ...organization('补充职员'),
      'id': 'college-test',
      'category': 'college',
      'name_cn': '测试学院',
      'teacher_unit': '测试学院',
    }),
  ];
  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    offsets.add(offset);
    return OfficialTeacherPage.fromJson({
      'items': [
        {
          'name': offset == 0 ? '中央甲' : '中央乙',
          'email': 'central$offset@bnbu.edu.cn',
          'unit_names': ['测试学院'],
        },
      ],
      'total': 2,
      'offset': offset,
      'limit': limit,
      'units': ['测试学院'],
    });
  }
}

class BundleFixture extends CachingAssetBundle {
  BundleFixture({this.organizationId = 'admin-ar'});
  final String organizationId;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'organizations': [
            {...organization('陈测试'), 'id': organizationId},
          ],
        }),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'college supplements do not replace central faculty or change remote offsets',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppSessionController();
      addTearDown(controller.dispose);
      final service = CollegeFixture();
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
      expect(find.text('中央甲'), findsOneWidget);
      expect(find.text('补充职员'), findsOneWidget);
      final more = find.widgetWithText(OutlinedButton, '加载更多');
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(service.offsets, [0, 1]);
      expect(find.text('中央乙'), findsOneWidget);
      expect(find.text('补充职员'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'legacy independent rosters remain authoritative after bilingual enrichment',
    () async {
      for (final id in ['college-gs', 'research-ias']) {
        final remote = {...organization('当前人员'), 'id': id}..remove('sources');
        final service = RemoteCampusDirectoryService(
          baseUrl: 'https://example.test',
          assetBundle: BundleFixture(organizationId: id),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'organizations': [remote],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        addTearDown(service.dispose);
        final org = (await service.loadOrganizations()).single;
        expect(org.embeddedStaff.single.name, '当前人员');
      }
    },
  );
  test(
    'mail candidates reflect changed staff and include service responsibilities',
    () async {
      final fixture = DirectoryFixture();
      final directory = MailRecipientDirectory(directoryService: fixture);
      addTearDown(directory.dispose);
      expect(
        (await directory.searchLocal('陈测试')).single.email,
        'fixture@bnbu.edu.cn',
      );
      fixture.name = '李测试';
      expect(await directory.searchLocal('陈测试'), isEmpty);
      expect(
        (await directory.searchLocal('李测试')).single.email,
        'fixture@bnbu.edu.cn',
      );
      expect(
        (await directory.searchLocal('证明开具')).single.email,
        'record@bnbu.edu.cn',
      );
    },
  );
  test(
    'legacy server keeps its fields and receives only sourced bundled additions',
    () async {
      final remote = {...organization('旧人员')};
      remote.remove('sources');
      remote.remove('staff');
      remote.remove('services');
      remote['office'] = '远端办公室';
      final service = RemoteCampusDirectoryService(
        baseUrl: 'https://example.test',
        assetBundle: BundleFixture(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'organizations': [remote],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(service.dispose);
      final org = (await service.loadOrganizations()).single;
      expect(org.office, '远端办公室');
      expect(org.embeddedStaff.single.name, '陈测试');
      expect(org.services.single.responsibilities, ['证明开具']);
    },
  );
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets(
      'administrative staff are reachable and have no teacher reviews at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controller = AppSessionController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: CampusDirectoryPage(
              controller: controller,
              directoryService: DirectoryFixture(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('政务'));
        await tester.pumpAndSettle();
        if (width < 900) {
          await tester.tap(find.text('教务处').first);
          await tester.pumpAndSettle();
        }
        expect(find.text('人员'), findsOneWidget);
        expect(find.text('陈测试'), findsOneWidget);
        await tester.tap(find.text('陈测试'));
        await tester.pumpAndSettle();
        expect(find.text('fixture@bnbu.edu.cn'), findsOneWidget);
        expect(find.text('学分置换'), findsOneWidget);
        expect(find.text('同学评价'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
