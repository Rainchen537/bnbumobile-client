import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/timeline_detail_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/pages/folder_detail_page.dart';
import 'package:bnbu_me/pages/timeline_detail_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/pages/web_mirror_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final assignment in [true, false]) {
    testWidgets('HTML body reaches the native document loader ($assignment)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });
      const body = '<p>正文 body &amp; 中文</p><table><tr><td>42</td></tr></table>';
      final module = _folderModule(description: body);
      final controller = _HtmlController(module);
      addTearDown(controller.dispose);
      final item = _timelineItem();
      await tester.pumpWidget(
        _localizedApp(
          assignment
              ? TimelineDetailPage(
                  controller: controller,
                  item: item,
                  initialDetail: TimelineDetailData(
                    item: item,
                    type: TimelineDetailType.assignment,
                    assignmentId: 42,
                    assignmentIntroHtml: body,
                  ),
                )
              : FolderDetailPage(
                  controller: controller,
                  course: _course(),
                  module: module,
                ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      final params = view.creationParams! as Map;
      expect(params['htmlContent'], contains('<p>正文 body &amp; 中文</p>'));
      expect(params['htmlContent'], contains('<td>42</td>'));
      expect(params['initialUrl'], isNull);
      expect(params['contentType'], 'html');
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('dark forum retains a readable continuous text canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _ForumController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ForumDiscussionPage(
          controller: controller,
          discussion: ForumDiscussion(
            id: 91,
            subject: 'Course discussion',
            messagePreview: '',
            author: 'Teacher',
            timeModifiedEpoch: 0,
            replyCount: 0,
            pinned: false,
            locked: false,
            discussionUrl: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = find.text('Synthetic discussion body');
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.text.style?.fontSize, 16);
    expect(paragraph.text.style?.color, BnbuThemeExtension.dark.textPrimary);
    final surface = tester.widget<Container>(
      find
          .ancestor(
            of: text,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          )
          .first,
    );
    expect((surface.decoration as BoxDecoration).color, isNot(Colors.white));
    expect(tester.getRect(find.byType(ListView)).left, 184);
    expect(tester.getRect(find.byType(ListView)).right, 1256);
    expect(tester.takeException(), isNull);
  });

  testWidgets('App-generated folder HTML shares the dark reading colors', (
    tester,
  ) async {
    final module = _folderModule(description: '<p>Fixture reading</p>');
    final controller = _FolderController(module);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: FolderDetailPage(
          controller: controller,
          course: _course(),
          module: module,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final panel = tester.widget<MirrorWebViewPanel>(
      find.byType(MirrorWebViewPanel),
    );
    final html = panel.content.value;
    expect(html, contains('background: #14171b'));
    expect(html, contains('color: #eef2f6'));
    expect(html, contains('font-size: 16px'));
  });

  testWidgets('tablet assignment detail separates overview and submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = AppSessionController();
    addTearDown(controller.dispose);
    final item = _timelineItem();

    await tester.pumpWidget(
      _localizedApp(
        TimelineDetailPage(
          controller: controller,
          item: item,
          initialDetail: TimelineDetailData(
            item: item,
            type: TimelineDetailType.assignment,
            assignmentId: 42,
            assignmentName: 'Research proposal',
            dueDateEpoch: 1788134400,
            submissionStatus: '尚未提交',
            gradingStatus: '未评分',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('timeline-assignment-tablet-split-layout')),
      findsOneWidget,
    );
    final split = tester.getRect(
      find.byKey(const ValueKey('timeline-assignment-tablet-split-layout')),
    );
    expect(split.left, 24);
    expect(split.right, 1000);
    expect(find.text('作业'), findsOneWidget);
    expect(find.text('当前作业未开放文件提交。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet folder detail keeps overview beside file list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final module = _folderModule();
    final controller = _FolderController(module);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _localizedApp(
        FolderDetailPage(
          controller: controller,
          course: _course(),
          module: module,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('folder-tablet-split-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('folder-tablet-overview-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('folder-tablet-files-pane')),
      findsOneWidget,
    );
    final split = tester.getRect(
      find.byKey(const ValueKey('folder-tablet-split-layout')),
    );
    expect(split.left, 24);
    expect(split.right, 1000);
    expect(find.text('Week 1.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ForumController extends AppSessionController {
  @override
  Future<List<ForumPost>> loadForumDiscussionPosts(int discussionId) async => [
    ForumPost(
      id: 91,
      subject: 'Course discussion',
      message: 'Synthetic discussion body',
      author: 'Teacher',
      timeCreatedEpoch: 0,
      parentId: 0,
      isPrivateReply: false,
    ),
  ];
}

Widget _localizedApp(Widget home) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: BnbuLocalizations.supportedLocales,
    localizationsDelegates: const [
      BnbuLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

TimelineItem _timelineItem() {
  return TimelineItem(
    id: 42,
    title: 'Research proposal',
    activityState: 'Due',
    activityType: 'assign',
    moduleName: 'assign',
    description: '',
    courseName: 'Academic English',
    courseId: 7,
    instanceId: 42,
    url: '',
    sortTime: DateTime.utc(2026, 8, 31),
    formattedTime: '',
    isOverdue: false,
  );
}

CourseSummary _course() {
  return CourseSummary(
    id: 7,
    fullName: 'Academic English',
    shortName: 'AE',
    categoryName: '2026',
    progress: 50,
  );
}

CourseModule _folderModule({String description = ''}) {
  return CourseModule(
    id: 12,
    instance: 13,
    name: 'Week 1 files',
    modName: 'folder',
    url: 'https://ispace.example.edu/mod/folder/view.php?id=12',
    iconUrl: '',
    descriptionHtml: description,
    contents: [
      CourseModuleContent(
        type: 'file',
        fileName: 'Week 1.pdf',
        filePath: '/',
        fileUrl: 'https://ispace.example.edu/pluginfile.php/7/Week%201.pdf',
        fileSize: 2048,
        mimeType: 'application/pdf',
        timeModifiedEpoch: 0,
        sortOrder: 1,
        author: '',
        license: '',
      ),
    ],
    dates: const [],
  );
}

class _FolderController extends AppSessionController {
  _FolderController(this.module);

  final CourseModule module;

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    return [
      CourseContentSection(
        id: 1,
        sectionNum: 1,
        name: 'Week 1',
        summary: '',
        modules: [module],
      ),
    ];
  }
}

class _HtmlController extends _FolderController {
  _HtmlController(super.module);

  @override
  Future<WebSessionSnapshot> prepareWebSession() async => WebSessionSnapshot(
    baseUrl: 'https://ispace.example.edu',
    cookies: const [],
  );
}
