import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/course_grade_data.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/pages/ispace_text_page.dart';
import 'package:bnbu_me/pages/timeline_detail_page.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/ispace_course_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final chinese = File('/System/Library/Fonts/STHeiti Light.ttc');
    if (await chinese.exists()) {
      for (final family in [
        'QA',
        'Roboto',
        'Ahem',
        '.SF Pro Text',
        '.SF Pro Display',
      ]) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(await chinese.readAsBytes())),
            ))
            .load();
      }
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.whereType<Map>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  testWidgets('Mac navigation refresh reloads the selected course', (
    tester,
  ) async {
    final controller = _RefreshCourses();
    tester.view.physicalSize = const Size(1000, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: IspacePage(controller: controller, onGoToUserTab: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ispace-navigation-course-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ispace-navigation-course-1')));
    await tester.pumpAndSettle();
    expect(controller.contentReads, 1);
    await tester.tap(find.byKey(const ValueKey('ispace-workspace-refresh')));
    await tester.pumpAndSettle();
    expect(controller.contentReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'iSpace module navigation stays in right pane and survives resizing',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 820);
      tester.view.devicePixelRatio = 1;
      final session = _Courses();
      addTearDown(() {
        session.dispose();
        tester.view.reset();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IspacePage(controller: session, onGoToUserTab: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ispace-navigation-course-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Essay'));
      await tester.pumpAndSettle();
      final pane = find.byKey(const ValueKey('ispace-desktop-navigation-pane'));
      expect(pane, findsOneWidget);
      expect(find.byType(TimelineDetailPage), findsOneWidget);
      expect(
        tester.getRect(find.byType(TimelineDetailPage)).left,
        tester.getRect(pane).right,
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(TimelineDetailPage), findsOneWidget);
      expect(pane, findsNothing);
      tester.view.physicalSize = const Size(1200, 820);
      await tester.pumpAndSettle();
      expect(pane, findsOneWidget);
      expect(find.byType(TimelineDetailPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Academic Writing'), findsOneWidget);
      expect(find.byType(TimelineDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'page files keep nested groups and real download actions at $width',
      (tester) async {
        final controller = _PageController();
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(fontFamily: 'QA'),
              appBarTheme: AppTheme.light.appBarTheme.copyWith(
                titleTextStyle: AppTheme.light.textTheme.titleLarge?.copyWith(
                  fontFamily: 'QA',
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: AppTheme.light.textButtonTheme.style?.copyWith(
                  textStyle: WidgetStatePropertyAll(
                    AppTheme.light.textTheme.labelLarge?.copyWith(
                      fontFamily: 'QA',
                    ),
                  ),
                ),
              ),
            ),
            home: RepaintBoundary(
              key: const ValueKey('refinement-preview'),
              child: IspaceTextPage(
                controller: controller,
                course: controller.courses.first,
                module: CourseModule.fromJson({
                  'id': 1,
                  'instance': 2,
                  'name': 'Teaching Materials',
                  'modname': 'page',
                  'uservisible': true,
                  'downloadcontent': true,
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lecture 01 - Introduction'), findsOneWidget);
        expect(find.text('Week 01 / Lab 01 - Digital'), findsOneWidget);
        expect(find.byTooltip('下载'), findsNWidgets(4));
        expect(find.text('下载本页文件'), findsOneWidget);
        final fileRow = find.ancestor(
          of: find.text('Lecture 01 - Introduction'),
          matching: find.byType(ListTile),
        );
        final expectedInset = width >= 700 ? 24.0 : 16.0;
        expect(tester.getTopLeft(fileRow).dx, closeTo(expectedInset, 0.1));
        expect(
          tester.getTopRight(fileRow).dx,
          closeTo(width - expectedInset, 0.1),
        );

        expect(tester.takeException(), isNull);
        await capture(tester, 'page-files-${width.toInt()}');
        controller.lease.active = false;
        controller.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('Lecture 01 - Introduction'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
  testWidgets(
    'course workspace keeps real module types and loads grades only on demand',
    (tester) async {
      final controller = _Courses();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <CourseModule>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(
            textTheme: AppTheme.light.textTheme.apply(fontFamily: 'QA'),
            primaryTextTheme: AppTheme.light.primaryTextTheme.apply(
              fontFamily: 'QA',
            ),
          ),
          home: Scaffold(
            body: IspaceCourseWorkspace(
              course: controller.courses.first,
              sections: await controller.loadCourseContents(1),
              controller: controller,
              loading: false,
              onRefresh: () async {},
              onOpenModule: opened.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hidden material'), findsNothing);
      await tester.tap(find.text('Essay'));
      expect(opened.single.modName, 'assign');
      expect(controller.gradeRequests, 0);
      await tester.tap(find.text('成绩'));
      await tester.pumpAndSettle();
      expect(controller.gradeRequests, 1);
      expect(find.text('暂无可见成绩'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final (width, dark, locale, scale) in [
    for (final width in [390.0, 900.0, 1440.0])
      (width, false, const Locale('zh', 'CN'), 1.0),
    for (final width in [390.0, 900.0, 1440.0])
      (width, true, const Locale('en'), 1.0),
    (375.0, false, const Locale('zh', 'TW'), 1.6),
  ]) {
    final labels = BnbuLocalizations(locale);
    final theme = dark ? AppTheme.dark : AppTheme.light;
    final variant =
        '${width.toInt()}-${dark ? 'dark' : 'light'}-${locale.toLanguageTag()}';
    testWidgets('native ispace navigation and course canvas at $variant', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final controller = _Courses();
      addTearDown(controller.dispose);
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: BnbuLocalizations.supportedLocales,
          localizationsDelegates: const [
            BnbuLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: scale > 1,
              padding: const EdgeInsets.only(top: 24),
            ),
            child: child!,
          ),
          theme: theme.copyWith(
            textButtonTheme: TextButtonThemeData(
              style: theme.textButtonTheme.style?.copyWith(
                textStyle: WidgetStatePropertyAll(
                  theme.textTheme.labelLarge?.copyWith(fontFamily: 'QA'),
                ),
              ),
            ),
            textTheme: theme.textTheme.apply(fontFamily: 'QA'),
            primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'QA'),
          ),
          home: RepaintBoundary(
            key: const ValueKey('refinement-preview'),
            child: IspacePage(controller: controller, onGoToUserTab: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text(labels.text('动态')), findsNothing);
      final navigation = find.byKey(
        const ValueKey('ispace-top-bar-navigation-button'),
      );
      final filter = find.byKey(
        const ValueKey('ispace-timeline-filter-control'),
      );
      final sort = find.byKey(const ValueKey('ispace-timeline-sort-control'));
      expect(
        tester.getCenter(navigation).dy,
        closeTo(tester.getCenter(filter).dy, 0.1),
      );
      expect(
        tester.getCenter(sort).dy,
        closeTo(tester.getCenter(filter).dy, 0.1),
      );
      await capture(tester, 'ispace-todo-$variant');
      if (width < 880) {
        await tester.tap(navigation);
        await tester.pumpAndSettle();
      }
      final coursesGroup = find.byKey(
        const ValueKey('ispace-courses-navigation-group'),
      );
      expect(find.text('ENG 101'), findsOneWidget);
      expect(find.text('More course materials'), findsOneWidget);
      expect(find.text(labels.text('动态')), findsNothing);
      expect(
        tester.getTopLeft(find.text('ENG 101')).dx -
            tester.getTopLeft(coursesGroup).dx,
        24,
      );
      await capture(tester, 'ispace-sidebar-$variant');
      await tester.tap(
        find.descendant(
          of: coursesGroup,
          matching: find.text(labels.text('课程')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ENG 101'), findsNothing);
      expect(filter, findsOneWidget);
      await tester.tap(
        find.descendant(
          of: coursesGroup,
          matching: find.text(labels.text('课程')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ispace-navigation-course-1')),
      );
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('ispace-section-header'));
      expect(
        find.descendant(of: header, matching: find.text(labels.text('课程'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.byType(IconButton)),
        findsNWidgets(width < 880 ? 2 : 1),
      );
      expect(filter, findsNothing);
      expect(find.text('Academic Writing'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Academic Writing')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(header).dy),
      );
      expect(find.text('Essay'), findsOneWidget);
      expect(find.text('Hidden material'), findsNothing);
      final workspaceRect = tester.getRect(find.byType(IspaceCourseWorkspace));
      final expectedInset = workspaceRect.width >= 700 ? 24.0 : 16.0;
      final courseRow = find.ancestor(
        of: find.text('Essay'),
        matching: find.byType(ListTile),
      );
      expect(
        tester.getTopLeft(find.text('Academic Writing')).dx,
        closeTo(workspaceRect.left + expectedInset, 0.1),
      );
      expect(
        tester.getTopLeft(courseRow).dx,
        closeTo(workspaceRect.left + expectedInset, 0.1),
      );
      expect(
        tester.getTopRight(courseRow).dx,
        closeTo(workspaceRect.right - expectedInset, 0.1),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'ispace-$variant');
      await tester.tap(find.text(labels.text('文件')));
      await tester.pumpAndSettle();
      expect(find.text('Essay'), findsNothing);
      await tester.tap(navigation);
      await tester.pumpAndSettle();
      if (width >= 880) {
        expect(
          find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
          findsNothing,
        );
        expect(find.text('Academic Writing'), findsOneWidget);
        await tester.tap(navigation);
        await tester.pumpAndSettle();
      }
      expect(find.text('ENG 101'), findsOneWidget);
      expect(find.text('Essay'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('ispace-navigation-course-2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('More course materials'), findsWidgets);
      await tester.tap(navigation);
      await tester.pumpAndSettle();
      if (width >= 880) {
        await tester.tap(navigation);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(labels.text('待办')));
      await tester.pumpAndSettle();
      expect(filter, findsOneWidget);
      expect(header, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('ecard bilingual reference geometry', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(
          textTheme: AppTheme.light.textTheme.apply(fontFamily: 'QA'),
          primaryTextTheme: AppTheme.light.primaryTextTheme.apply(
            fontFamily: 'QA',
          ),
        ),
        home: RepaintBoundary(
          key: const ValueKey('refinement-preview'),
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(402, 874),
              padding: EdgeInsets.only(top: 62, bottom: 34),
            ),
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                toolbarHeight: 44,
                backgroundColor: Colors.white,
                centerTitle: true,
                title: const Text(
                  'BNBU Campus Card',
                  style: TextStyle(fontSize: 17),
                ),
              ),
              body: const SafeArea(
                top: false,
                child: StudentEcardView(
                  data: StudentEcardData(
                    fullName: 'Student Example',
                    chineseName: '测试学生',
                    englishName: 'Student Example',
                    studentId: '2099000001',
                    department: 'FST',
                    identity: 'BNBU Student UG/STUDENT',
                    gender: '男/MALE',
                    residence: 'Example Hall',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chinese = tester.getRect(
      find.byKey(const ValueKey('student-ecard-chinese-name')),
    );
    final english = tester.getRect(
      find.byKey(const ValueKey('student-ecard-name')),
    );
    final barcode = tester.getRect(
      find.byKey(const ValueKey('student-ecard-barcode')),
    );
    expect(chinese.bottom, lessThan(english.top));
    expect(english.bottom, lessThan(barcode.top));
    expect(barcode.width, 354);
    expect(barcode.center.dx, 201);
    expect(tester.takeException(), isNull);
    await capture(tester, 'ecard-402');
  });
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('refinement-preview')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory('build/refinement/previews');
    await out.create(recursive: true);
    await File(
      '${out.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _Courses extends AppSessionController {
  int gradeRequests = 0;
  @override
  bool get isLoggedIn => true;
  @override
  String get username => 'fixture';
  @override
  List<CourseSummary> get courses => [
    CourseSummary(
      id: 1,
      fullName: 'Academic Writing',
      shortName: 'ENG 101',
      categoryName: '',
      progress: 20,
      showGrades: true,
    ),
    CourseSummary(
      id: 2,
      fullName: 'More course materials',
      shortName: '',
      categoryName: '',
      progress: 0,
    ),
  ];
  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async => [
    CourseContentSection(
      id: 1,
      sectionNum: 1,
      name: 'Week 1',
      summary: '',
      modules: [
        for (final entry in [
          ('Essay', 'assign', true),
          ('Reading materials', 'resource', true),
          ('Hidden material', 'resource', false),
        ])
          CourseModule(
            id: entry.$1.hashCode,
            instance: 1,
            name: entry.$1,
            modName: entry.$2,
            url: '',
            iconUrl: '',
            descriptionHtml: '',
            contents: [],
            dates: [],
            userVisible: entry.$3,
          ),
      ],
    ),
  ];
  @override
  Future<CourseGradeSnapshot> loadCourseGrades(int courseId) async {
    gradeRequests++;
    return CourseGradeSnapshot(courseId: courseId, items: []);
  }
}

class _PageLease implements AppSessionLease {
  bool active = true;
  @override
  bool get isActive => active;
  @override
  String get owner => 'fixture';
}

class _PageController extends _Courses {
  final lease = _PageLease();
  @override
  AppSessionLease captureSessionLease() => lease;
  @override
  String get baseUrl => 'https://school.example';
  @override
  Future<String> loadCoursePageHtml(int courseId, CourseModule target) async =>
      '<h3>Week 01</h3><ul><li><a href="/pluginfile.php/1/Lecture.pptx">Lecture 01 - Introduction</a></li>'
      '<li><a href="/pluginfile.php/1/Lab.pptx">Lab 01 - Digital</a><ul>'
      '<li><a href="/pluginfile.php/1/Digital.zip">Digital.zip</a></li>'
      '<li><a href="/pluginfile.php/1/LabMaterial.zip">Lab Material</a></li></ul></li></ul>';
}

class _RefreshCourses extends _Courses {
  int contentReads = 0;
  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) {
    contentReads++;
    return super.loadCourseContents(courseId);
  }
}
