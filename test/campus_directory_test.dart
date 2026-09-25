import 'package:bnbu_me/widgets/campus_organization_avatar.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/pages/campus_directory_page.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('teacher review identity prefers the stable official profile URL', () {
    final fromProfile = buildTeacherReviewKey(
      profileUrl: ' https://staff.bnbu.edu.cn/Teacher/en ',
      email: 'first@bnbu.edu.cn',
      name: '教师甲',
    );
    final renamed = buildTeacherReviewKey(
      profileUrl: 'https://staff.bnbu.edu.cn/teacher/en',
      email: 'second@bnbu.edu.cn',
      name: '教师乙',
    );

    expect(fromProfile, renamed);
    expect(fromProfile, 'tchr_77245fdd166aea0585c47731675ed7241bd11e35');
    expect(fromProfile, matches(RegExp(r'^tchr_[0-9a-f]{40}$')));
  });

  test('public build has a valid empty offline directory', () async {
    final service = RemoteCampusDirectoryService(
      client: MockClient((_) async => http.Response('{}', 503)),
      baseUrl: 'https://directory.example',
      retryDelay: (_) async {},
    );
    addTearDown(service.dispose);
    expect(await service.loadOrganizations(), isEmpty);
  });

  test(
    'remote organization directory takes priority over bundled snapshot',
    () async {
      late Uri requested;
      final service = RemoteCampusDirectoryService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({
              'updated_at': '2026-07-29',
              'organizations': [
                {
                  'id': 'research-ias',
                  'category': 'research_institute',
                  'name_cn': '高等研究院',
                  'name_en': 'BNBU Institute for Advanced Study',
                  'short_name': 'IAS',
                  'website_url': 'https://ias.bnbu.edu.cn/',
                  'faculty_url':
                      'https://ias.bnbu.edu.cn/faculty_people/people.htm',
                  'teacher_unit': '高等研究院',
                  'office': '',
                  'phones': ['0756-3677713'],
                  'emails': ['ias@bnbu.edu.cn'],
                  'responsibilities': ['前沿研究与创新'],
                  'contacts': [],
                  'staff': [],
                  'source_urls': ['https://ias.bnbu.edu.cn/'],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        baseUrl: 'https://directory.example',
      );
      addTearDown(service.dispose);

      final organizations = await service.loadOrganizations();

      expect(requested.path, '/v1/directory/public/organizations');
      expect(organizations, hasLength(1));
      expect(
        organizations.single.category,
        CampusDirectoryCategory.researchInstitute,
      );
    },
  );

  test('remote teacher browse keeps unit and paging parameters', () async {
    late Uri requested;
    final service = RemoteCampusDirectoryService(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'name': '陈老师',
                'name_en': 'Teacher Chen',
                'email': 'teacher.chen@bnbu.edu.cn',
                'title': '副教授',
                'title_en': 'Associate Professor',
                'position': '课程主任',
                'office': 'T3-602',
                'telephone': '0756-3620000',
                'academic_cn': '人工智能',
                'academic_en': 'Artificial intelligence',
                'education_cn': '博士',
                'education_en': 'PhD',
                'unit_names': ['理工科技学院'],
                'primary_appointments': [
                  {'name': '数据科学', 'url': 'https://fst.bnbu.edu.cn/'},
                ],
                'cross_appointments': [
                  {'name': '人工智能重点实验室', 'url': 'https://fst.bnbu.edu.cn/lab'},
                ],
                'timetable': {
                  'name': '2026 春季课表',
                  'url': 'https://staff.bnbu.edu.cn/attachment/timetable.pdf',
                },
                'profile_links': [
                  {'name': 'DBLP Homepage', 'url': 'https://dblp.org/pid/1'},
                ],
                'sections': [
                  {
                    'name': '自我介绍',
                    'type': 'content',
                    'items': [
                      {'title': '', 'content': '教师自我介绍', 'link': ''},
                    ],
                  },
                ],
                'photo_url': '',
                'profile_url': '',
                'source_updated_at': null,
              },
            ],
            'total': 1,
            'offset': 20,
            'limit': 20,
            'units': ['理工科技学院'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'https://directory.example/',
    );
    addTearDown(service.dispose);

    final result = await service.loadTeachers(
      query: '陈老师',
      unit: '理工科技学院',
      offset: 20,
      limit: 20,
    );

    expect(requested.path, '/v1/directory/public/teachers');
    expect(requested.queryParameters['q'], '陈老师');
    expect(requested.queryParameters['unit'], '理工科技学院');
    expect(requested.queryParameters['offset'], '20');
    expect(requested.queryParameters['limit'], '20');
    expect(result.total, 1);
    expect(result.items.single.office, 'T3-602');
    expect(result.items.single.academicCn, '人工智能');
    expect(result.items.single.timetable?.name, '2026 春季课表');
    expect(result.items.single.primaryAppointments.single.name, '数据科学');
    expect(result.items.single.crossAppointments.single.name, '人工智能重点实验室');
    expect(result.items.single.profileLinks.single.name, 'DBLP Homepage');
    expect(result.items.single.sections.single.name, '自我介绍');
    expect(result.items.single.sections.single.items.single.content, '教师自我介绍');
  });

  test('remote teacher browse retries a transient gateway failure', () async {
    var attempts = 0;
    final service = RemoteCampusDirectoryService(
      client: MockClient((_) async {
        attempts++;
        if (attempts == 1) {
          return http.Response('', 503);
        }
        return http.Response(
          jsonEncode({
            'items': <Object>[],
            'total': 0,
            'offset': 0,
            'limit': 20,
            'units': <Object>[],
          }),
          200,
        );
      }),
      baseUrl: 'https://directory.example',
      retryDelay: (_) async {},
    );
    addTearDown(service.dispose);

    final result = await service.loadTeachers(limit: 20);

    expect(result.total, 0);
    expect(attempts, 2);
  });

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('directory search stays compact and bounded at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = AppSessionController();
      final service = _FakeCampusDirectoryService();
      addTearDown(controller.dispose);
      addTearDown(service.dispose);
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
      expect(find.text('高研院'), findsNothing);
      expect(find.text('高等研究院'), findsOneWidget);
      expect(find.byType(CampusOrganizationAvatar), findsWidgets);
      await tester.tap(find.text('高等研究院'));
      await tester.pumpAndSettle();
      expect(find.text('ias@bnbu.edu.cn'), findsOneWidget);
      if (width < 900) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      } else {
        expect(
          find.byKey(const ValueKey('campus-directory-detail-research-ias')),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('政务'));
      await tester.pumpAndSettle();
      expect(find.text('高等研究院'), findsNothing);
      expect(find.text('教务处'), findsWidgets);
      await tester.tap(find.text('学院'));
      await tester.pumpAndSettle();
      expect(find.text('高等研究院'), findsOneWidget);
      final field = find.byKey(const ValueKey('campus-directory-search'));
      final input = tester.widget<TextField>(field);
      expect(input.focusNode!.hasFocus, isFalse);
      expect(tester.getSize(field).width, width >= 900 ? 560 : 100);
      // The resting narrow affordance also responds at the expanded left edge.
      await tester.tapAt(
        Offset(width >= 900 ? width / 2 : 24, tester.getCenter(field).dy),
      );
      await tester.pumpAndSettle();
      expect(input.focusNode!.hasFocus, isTrue);
      expect(tester.getSize(field).width, width >= 900 ? 560 : width - 32);
      // A tap on recessed content dismisses without opening that organization.
      await tester.tapAt(tester.getCenter(find.text('高等研究院')));
      await tester.pumpAndSettle();
      if (width < 900) {
        expect(find.byType(CampusDirectoryOrganizationView), findsNothing);
      } else {
        expect(
          find.byKey(const ValueKey('campus-directory-detail-research-ias')),
          findsNothing,
        );
      }
      expect(input.focusNode!.hasFocus, isFalse);
      expect(tester.getSize(field).width, width >= 900 ? 560 : 100);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '教务');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-directory-search-results')),
        findsOneWidget,
      );
      await tester.tapAt(Offset(width - 2, 820));
      await tester.pumpAndSettle();
      expect(input.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(input.controller!.text, '教务');
      expect(
        find.byKey(const ValueKey('campus-directory-search-results')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('campus-directory-search-close')),
      );
      await tester.pumpAndSettle();
      expect(input.controller!.text, isEmpty);
      expect(tester.getSize(field).width, width >= 900 ? 560 : 100);
      final searchBandAndCategoryInset =
          tester.getTopLeft(find.text('学院')).dy -
          tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(searchBandAndCategoryInset, lessThanOrEqualTo(72));
      final search = find.byKey(const ValueKey('campus-directory-search'));
      expect(tester.getCenter(search).dx, closeTo(width / 2, 0.1));
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(tester.getSize(search).width, lessThanOrEqualTo(560));
      expect(tester.getSize(search).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final startInPadding in [false, true]) {
      testWidgets(
        '$platform directory drag from ${startInPadding ? 'padding' : 'teacher'} retains results and navigation',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final controller = AppSessionController();
          final service = _ScrollableCampusDirectoryService();
          addTearDown(controller.dispose);
          addTearDown(service.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: CampusDirectoryPage(
                controller: controller,
                directoryService: service,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final field = find.byKey(const ValueKey('campus-directory-search'));
          final results = find.byKey(
            const ValueKey('campus-directory-search-results'),
          );
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.enterText(field, 'demo');
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          final input = tester.widget<TextField>(field);
          expect(input.focusNode!.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          final firstTeacher = find.byKey(
            const ValueKey('directory-search-teacher-demo0@example.invalid'),
          );
          // A result tap must navigate on the first attempt, even while typing.
          await tester.tap(firstTeacher);
          await tester.pumpAndSettle();
          expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(input.controller!.text, 'demo');
          expect(results, findsOneWidget);
          await tester.tap(field);
          await tester.pumpAndSettle();
          final start = tester.getCenter(firstTeacher);
          final scrollable = find.descendant(
            of: results,
            matching: find.byType(Scrollable),
          );
          final position = tester.state<ScrollableState>(scrollable).position;
          await tester.dragFrom(
            startInPadding ? Offset(4, start.dy) : start,
            const Offset(0, -90),
          );
          await tester.pumpAndSettle();
          expect(input.focusNode!.hasFocus, isFalse);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(input.controller!.text, 'demo');
          expect(results, findsOneWidget);
          expect(position.pixels, greaterThan(0));
          expect(service.requestedQueries, ['demo']);

          final teacher = find.byKey(
            const ValueKey('directory-search-teacher-demo2@example.invalid'),
          );
          await tester.ensureVisible(teacher);
          await tester.pumpAndSettle();
          final offsetBeforeDetails = position.pixels;
          await tester.tap(teacher);
          await tester.pumpAndSettle();
          expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
          expect(find.text('Demo Teacher 2'), findsWidgets);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(results, findsOneWidget);
          expect(input.controller!.text, 'demo');
          expect(position.pixels, closeTo(offsetBeforeDetails, 0.1));
          expect(service.requestedQueries, ['demo']);

          await tester.tap(
            find.byKey(const ValueKey('campus-directory-search-close')),
          );
          await tester.pumpAndSettle();
          expect(input.controller!.text, isEmpty);
          expect(results, findsNothing);
          expect(find.text('学院'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('directory search covers every category and pinyin content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppSessionController();
    final service = _FakeCampusDirectoryService();
    addTearDown(controller.dispose);
    addTearDown(service.dispose);
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

    expect(find.text('工商管理学院'), findsOneWidget);
    expect(find.text('教务处'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('campus-directory-search')),
      'kechengzhuce',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('campus-directory-search-results')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<CampusDirectoryCategory>), findsNothing);
    expect(find.text('工商管理学院'), findsNothing);
    expect(find.text('教务处'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('campus-directory-search')),
      'xuxiaodong',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('徐晓冬'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('directory-search-group-college-fbm')),
      findsOneWidget,
    );
    expect(service.requestedQueries, contains('xuxiaodong'));
  });

  testWidgets('wide directory keeps native master detail and teacher detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppSessionController();
    final service = _FakeCampusDirectoryService();
    addTearDown(controller.dispose);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CampusDirectoryPage(
          controller: controller,
          directoryService: service,
          mailCredentialsLoader: () async => MailAccessCredentials.fromUserId(
            userId: 'student01',
            password: 'test-password',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('campus-directory-master-pane')),
      findsOneWidget,
    );
    expect(find.text('工商管理学院'), findsWidgets);
    expect(find.text('fbm@bnbu.edu.cn'), findsOneWidget);
    expect(service.requestedUnits, ['工商管理学院']);
    expect(
      find.byKey(const ValueKey('teacher-search-college-fbm')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('campus-directory-search')),
      'xuxiaodong',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('campus-directory-search-results')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('campus-directory-master-pane')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('campus-directory-detail-college-fbm')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('directory-search-group-college-fbm')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('campus-directory-search')),
      '',
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('soft-search-dismiss-barrier')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('陈老师'),
      360,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('陈老师'));
    await tester.pumpAndSettle();

    expect(find.text('teacher.chen@bnbu.edu.cn'), findsOneWidget);
    expect(find.text('T3-602'), findsOneWidget);
    expect(find.text('人工智能'), findsOneWidget);
    expect(find.text('教育经历'), findsOneWidget);

    await tester.tap(find.text('teacher.chen@bnbu.edu.cn'));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeMailPage), findsOneWidget);
    expect(find.textContaining('teacher.chen@bnbu.edu.cn'), findsWidgets);
  });

  testWidgets('directory search grid reflows at medium and expanded widths', (
    tester,
  ) async {
    final controller = AppSessionController();
    final service = _FakeCampusDirectoryService();
    addTearDown(controller.dispose);
    addTearDown(service.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    Future<double> searchAtWidth(double width) async {
      tester.view.physicalSize = Size(width, 900);
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
      await tester.enterText(
        find.byKey(const ValueKey('campus-directory-search')),
        'xuxiaodong',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      return tester
          .getSize(
            find.byKey(
              const ValueKey('directory-search-teacher-xiaodongxu@bnbu.edu.cn'),
            ),
          )
          .width;
    }

    final mediumCardWidth = await searchAtWidth(900);
    final expandedCardWidth = await searchAtWidth(1440);

    expect(mediumCardWidth, closeTo(428, 1));
    expect(expandedCardWidth, closeTo(461.33, 1));
  });
}

class _ScrollableCampusDirectoryService extends _FakeCampusDirectoryService {
  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    requestedQueries.add(query);
    return OfficialTeacherPage(
      items: List.generate(
        20,
        (index) => OfficialTeacherProfile.fromJson({
          'name': 'Demo Teacher $index',
          'name_en': 'Demo Teacher $index',
          'email': 'demo$index@example.invalid',
          'unit_names': ['工商管理学院'],
        }),
      ),
      total: 20,
      offset: 0,
      limit: 60,
      units: ['工商管理学院'],
    );
  }
}

class _FakeCampusDirectoryService implements CampusDirectoryService {
  final List<String> requestedUnits = [];
  final List<String> requestedQueries = [];

  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async {
    return [
      CampusDirectoryOrganization(
        id: 'college-fbm',
        category: CampusDirectoryCategory.college,
        nameCn: '工商管理学院',
        nameEn: 'Faculty of Business and Management',
        shortName: 'FBM',
        websiteUrl: 'https://fbm.bnbu.edu.cn/',
        facultyUrl: 'https://fbm.bnbu.edu.cn/staff/Faculty_Members.htm',
        teacherUnit: '工商管理学院',
        office: 'T1-602',
        phones: const ['0756-3620423'],
        emails: const ['fbm@bnbu.edu.cn'],
        responsibilities: const ['工商管理教育'],
        contacts: const [],
        embeddedStaff: const [],
        sourceUrls: const ['https://fbm.bnbu.edu.cn/'],
      ),
      CampusDirectoryOrganization.fromJson({
        'id': 'research-ias',
        'category': 'research_institute',
        'name_cn': '高等研究院',
        'name_en': 'Institute for Advanced Study',
        'short_name': 'IAS',
        'emails': ['ias@bnbu.edu.cn'],
      }),
      CampusDirectoryOrganization(
        id: 'administration-ar',
        category: CampusDirectoryCategory.administration,
        nameCn: '教务处',
        nameEn: 'Academic Registry',
        shortName: 'AR',
        websiteUrl: 'https://ar.bnbu.edu.cn/',
        facultyUrl: '',
        teacherUnit: '',
        office: 'AD-201',
        phones: const ['0756-3620303'],
        emails: const ['ar@bnbu.edu.cn'],
        responsibilities: const ['课程注册'],
        contacts: const [],
        embeddedStaff: const [],
        sourceUrls: const ['https://ar.bnbu.edu.cn/'],
      ),
    ];
  }

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    requestedUnits.add(unit);
    requestedQueries.add(query);
    final teacher = query == 'xuxiaodong'
        ? const OfficialTeacherProfile(
            name: '徐晓冬',
            nameEn: 'Xiaodong Xu',
            email: 'xiaodongxu@bnbu.edu.cn',
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
            photoUrl: '',
            profileUrl: '',
            sourceUpdatedAt: null,
          )
        : const OfficialTeacherProfile(
            name: '陈老师',
            nameEn: 'Teacher Chen',
            email: 'teacher.chen@bnbu.edu.cn',
            title: '副教授',
            titleEn: 'Associate Professor',
            position: '课程主任',
            office: 'T3-602',
            telephone: '0756-3620000',
            academicCn: '人工智能',
            academicEn: 'Artificial intelligence',
            educationCn: '博士',
            educationEn: 'PhD',
            unitNames: ['工商管理学院'],
            photoUrl: '',
            profileUrl: '',
            sourceUpdatedAt: null,
          );
    return OfficialTeacherPage(
      items: [teacher],
      total: 1,
      offset: 0,
      limit: 60,
      units: ['工商管理学院'],
    );
  }

  @override
  void dispose() {}
}
