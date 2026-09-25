import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/assistant_resource.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/pages/course_detail_page.dart';
import 'package:bnbu_me/widgets/ispace_course_workspace.dart';
import 'package:bnbu_me/services/course_archive_service.dart';
import 'package:bnbu_me/services/native_actions.dart';
import 'package:bnbu_me/services/assistant_resource_library_store.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/assistant_resource_library_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/course_downloads');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final hiddenSection in [true, false]) {
    testWidgets(
      'batch selection excludes hidden ${hiddenSection ? 'sections' : 'modules'}',
      (tester) async {
        final source = _sectionWithFiles();
        final module = source.modules.single;
        final hidden = CourseContentSection(
          id: source.id,
          sectionNum: source.sectionNum,
          name: source.name,
          summary: '',
          userVisible: !hiddenSection,
          modules: [
            CourseModule(
              id: module.id,
              instance: module.instance,
              name: module.name,
              modName: module.modName,
              url: module.url,
              iconUrl: '',
              descriptionHtml: '',
              contents: module.contents,
              dates: [],
              userVisible: hiddenSection,
            ),
          ],
        );
        final controller = _CourseSessionController(
          sections: [hidden, _sectionWithClassifiedFiles()],
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: CourseDetailPage(
              controller: controller,
              course: _course(),
              initialBatchDownloadIntent: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('小U已选好打包内容'), findsOneWidget);
        expect(find.textContaining('IntroductionToOOP.pdf'), findsOneWidget);
        expect(find.textContaining('slides.pdf'), findsNothing);
        expect(find.textContaining('notes.pdf'), findsNothing);
      },
    );
  }

  testWidgets('confirmed batch rechecks visibility before reading file bytes', (
    tester,
  ) async {
    final controller = _ChangingCourseController();
    final archive = _FakeCourseArchiveBuilder();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CourseDetailPage(
          controller: controller,
          course: _course(),
          initialBatchDownloadIntent: true,
          archiveBuilder: archive,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('小U已选好打包内容'), findsOneWidget);
    await tester.tap(find.text('生成 ZIP'));
    await tester.pumpAndSettle();
    expect(controller.reads, 2);
    expect(archive.entries, isEmpty);
    expect(find.textContaining('课件列表已变化'), findsOneWidget);
  });

  testWidgets(
    'assistant batch intent safely selects all files and continues to ZIP',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getMailAttachmentCacheDir') {
          return '/tmp/course-download-test';
        }
        return '/Downloads/${(call.arguments as Map<Object?, Object?>)['filename']}';
      });
      final controller = _CourseSessionController(
        sections: [_sectionWithFiles()],
      );
      final archiveBuilder = _FakeCourseArchiveBuilder();
      final resourceStore = _MemoryArchiveResourceStore();
      final resourceLibrary = AssistantResourceLibraryController(
        sessionController: controller,
        store: resourceStore,
      );
      addTearDown(() {
        resourceLibrary.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: CourseDetailPage(
            controller: controller,
            course: _course(),
            initialBatchDownloadIntent: true,
            nativeActions: const NativeActions(channel: channel),
            archiveBuilder: archiveBuilder,
            resourceLibrary: resourceLibrary,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('小U已选好打包内容'), findsOneWidget);
      expect(find.textContaining('匹配了 2 个文件'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.tap(find.text('生成 ZIP'));
      await tester.pumpAndSettle();

      expect(archiveBuilder.entries, hasLength(2));
      for (final entry in archiveBuilder.entries) {
        final uri = Uri.parse(entry.url);
        expect(uri.scheme, 'https');
        expect(uri.host, 'ispace.example.edu');
        expect(uri.path, contains('/pluginfile.php'));
        expect(uri.queryParameters, isNot(contains('token')));
        expect(uri.queryParameters['forcedownload'], '1');
      }
      expect(archiveBuilder.cookieHeader, 'MoodleSession=session-value');
      expect(archiveBuilder.baseUrl, 'https://ispace.example.edu');
      expect(
        calls.map((call) => call.method),
        contains('getMailAttachmentCacheDir'),
      );
      expect(find.byKey(const ValueKey('course-archive-card')), findsOneWidget);
      expect(find.text('打开 ZIP'), findsOneWidget);
      expect(resourceLibrary.resources, hasLength(1));
      expect(resourceLibrary.resources.single.fileName, 'C Programming.zip');
      expect(resourceStore.lastSourcePath, contains('C Programming.zip'));
      expect(find.textContaining('保存到小U资源库'), findsOneWidget);
    },
  );

  testWidgets(
    'assistant presentation scope selects slides and PDF without a picker',
    (tester) async {
      final controller = _CourseSessionController(
        sections: [_sectionWithClassifiedFiles()],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CourseDetailPage(
            controller: controller,
            course: _course(),
            initialBatchDownloadIntent: true,
            initialBatchFileScope: AssistantCourseFileScope.presentationsAndPdf,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('小U已选好打包内容'), findsOneWidget);
      expect(find.textContaining('演示文稿与 PDF 课件'), findsOneWidget);
      expect(find.textContaining('IntroductionToOOP.pdf'), findsOneWidget);
      expect(find.textContaining('lecture-02.pptx'), findsOneWidget);
      expect(find.textContaining('lab-source.zip'), findsNothing);
      expect(find.textContaining('walkthrough.mp4'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    },
  );

  testWidgets('standalone course uses the same responsive iSpace workspace', (
    tester,
  ) async {
    final controller = _CourseSessionController(
      sections: [_sectionWithFiles(), _sectionWithClassifiedFiles()],
    );
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [390.0, 900.0, 1440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: CourseDetailPage(
            key: ValueKey(width),
            controller: controller,
            course: _course(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IspaceCourseWorkspace), findsOneWidget);
      expect(find.text('章节'), findsOneWidget);
      expect(find.text('成绩'), findsOneWidget);
      expect(find.text(_course().fullName), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ispace-course-sections')),
        width < 700 ? findsNothing : findsOneWidget,
      );
      if (width >= 700) {
        expect(
          tester
              .getSize(find.byKey(const ValueKey('ispace-course-sections')))
              .width,
          270,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });
}

class _FakeCourseArchiveBuilder implements CourseArchiveBuilder {
  List<CourseArchiveEntry> entries = const [];
  String cookieHeader = '';
  String baseUrl = '';

  @override
  Future<CourseArchiveResult> build({
    required String cacheDirectory,
    required String archiveName,
    required String baseUrl,
    required String cookieHeader,
    required List<CourseArchiveEntry> entries,
    required bool Function() sessionIsActive,
    void Function(CourseArchiveProgress progress)? onProgress,
  }) async {
    this.entries = entries;
    this.cookieHeader = cookieHeader;
    this.baseUrl = baseUrl;
    onProgress?.call(
      CourseArchiveProgress(
        completedFiles: entries.length,
        totalFiles: entries.length,
        currentFileName: entries.last.fileName,
      ),
    );
    return CourseArchiveResult(
      path: '$cacheDirectory/C Programming.zip',
      fileName: 'C Programming.zip',
      fileCount: entries.length,
      totalBytes: entries.fold(0, (sum, entry) => sum + entry.expectedBytes),
    );
  }
}

CourseSummary _course() {
  return CourseSummary(
    id: 7,
    fullName: 'Software Engineering',
    shortName: 'SE',
    categoryName: '2026',
    progress: 30,
  );
}

CourseContentSection _sectionWithFiles() {
  CourseModuleContent file(String name, String url, int size) {
    return CourseModuleContent(
      type: 'file',
      fileName: name,
      filePath: '/',
      fileUrl: url,
      fileSize: size,
      mimeType: 'application/pdf',
      timeModifiedEpoch: 0,
      sortOrder: 0,
      author: '',
      license: '',
    );
  }

  return CourseContentSection(
    id: 1,
    sectionNum: 1,
    name: 'Week 1',
    summary: '',
    modules: [
      CourseModule(
        id: 11,
        instance: 12,
        name: 'Lecture files',
        modName: 'resource',
        url: '',
        iconUrl: '',
        descriptionHtml: '',
        contents: [
          file(
            'slides.pdf',
            'https://ispace.example.edu/webservice/pluginfile.php/1/slides.pdf?token=secret-a',
            1024,
          ),
          file(
            'duplicate.pdf',
            'https://ispace.example.edu/webservice/pluginfile.php/1/slides.pdf?token=secret-b',
            1024,
          ),
          file(
            'notes.pdf',
            '/webservice/pluginfile.php/1/notes.pdf?token=secret-c',
            2048,
          ),
          file(
            'malicious.pdf',
            'https://attacker.example/pluginfile.php/1/malicious.pdf?token=secret-d',
            2048,
          ),
        ],
        dates: const [],
      ),
    ],
  );
}

CourseContentSection _sectionWithClassifiedFiles() {
  CourseModuleContent file(String name, String mimeType) {
    return CourseModuleContent(
      type: 'file',
      fileName: name,
      filePath: '/',
      fileUrl: 'https://ispace.example.edu/pluginfile.php/2/$name',
      fileSize: 1024,
      mimeType: mimeType,
      timeModifiedEpoch: 0,
      sortOrder: 0,
      author: '',
      license: '',
    );
  }

  return CourseContentSection(
    id: 2,
    sectionNum: 2,
    name: 'Week 2',
    summary: '',
    modules: [
      CourseModule(
        id: 21,
        instance: 22,
        name: 'Course slides',
        modName: 'resource',
        url: '',
        iconUrl: '',
        descriptionHtml: '',
        contents: [
          file('IntroductionToOOP.pdf', 'application/pdf'),
          file(
            'lecture-02.pptx',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          ),
          file('lab-source.zip', 'application/zip'),
          file('walkthrough.mp4', 'video/mp4'),
        ],
        dates: const [],
      ),
    ],
  );
}

class _CourseSessionController extends AppSessionController {
  _CourseSessionController({required this.sections});

  final List<CourseContentSection> sections;
  final _TestSessionLease lease = _TestSessionLease();

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student@example.edu';

  @override
  String get baseUrl => 'https://ispace.example.edu';

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    expect(courseId, 7);
    return sections;
  }

  @override
  AppSessionLease? captureSessionLease() => lease;

  @override
  Future<WebSessionSnapshot> prepareWebSession() async {
    return WebSessionSnapshot(
      baseUrl: baseUrl,
      cookies: [
        WebSessionCookie(
          name: 'MoodleSession',
          value: 'session-value',
          domain: 'ispace.example.edu',
          path: '/',
          hostOnly: true,
          secure: true,
          httpOnly: true,
        ),
      ],
    );
  }
}

class _ChangingCourseController extends _CourseSessionController {
  _ChangingCourseController() : super(sections: [_sectionWithFiles()]);
  int reads = 0;
  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    reads++;
    return reads == 1 ? sections : [];
  }
}

class _MemoryArchiveResourceStore implements AssistantResourceLibraryStore {
  String? lastSourcePath;
  final List<AssistantResourceItem> _items = [];

  @override
  Future<void> delete(String owner, AssistantResourceItem item) async {
    _items.removeWhere((candidate) => candidate.id == item.id);
  }

  @override
  Future<AssistantResourceItem> importFile(
    String owner, {
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required AssistantResourceKind kind,
    required String sourceTitle,
    required String summary,
  }) async {
    lastSourcePath = sourcePath;
    final item = AssistantResourceItem(
      id: 'resource-${_items.length + 1}',
      fileName: fileName,
      storedName: 'stored-$fileName',
      filePath: '/documents/$fileName',
      mimeType: mimeType,
      byteCount: 3072,
      createdAt: DateTime.utc(2026, 7, 24),
      kind: kind,
      sourceTitle: sourceTitle,
      summary: summary,
    );
    _items.add(item);
    return item;
  }

  @override
  Future<List<AssistantResourceItem>> load(String owner) async {
    return List.unmodifiable(_items);
  }
}

class _TestSessionLease implements AppSessionLease {
  bool active = true;

  @override
  bool get isActive => active;

  @override
  String get owner => 'student@example.edu';
}
