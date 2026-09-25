import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/services/course_archive_service.dart';
import 'package:bnbu_me/services/course_archive_export_service.dart';
import 'package:bnbu_me/services/desktop_download_service.dart';
import 'package:bnbu_me/services/courseware_download_plan.dart';
import 'package:bnbu_me/services/native_actions.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/ispace_course_workspace.dart';
import 'package:bnbu_me/widgets/courseware_download_button.dart';

final course = CourseSummary(
  id: 7,
  fullName: 'Database Management Systems and Advanced Computer Science',
  shortName: 'COMP TEST',
  categoryName: '',
  progress: null,
);
final files = List.generate(
  2,
  (index) => CourseArchiveEntry(
    url: 'https://ispace.example.edu/pluginfile.php/1/slides$index.pptx',
    sectionName: 'Week 1',
    moduleName: 'Lectures',
    fileName: 'slides$index.pptx',
    expectedBytes: 3,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> showPicker(
    WidgetTester tester,
    _Controller controller,
    _Builder builder, {
    Size size = const Size(900, 800),
    bool english = false,
    double textScale = 1,
    CourseArchiveExportService exporter = const CourseArchiveExportService(),
    DesktopDownloadService downloads = const DesktopDownloadService(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: Locale(english ? 'en' : 'zh'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: CoursewareDownloadButton(
              controller: controller,
              course: course,
              nativeActions: _Native(),
              archiveBuilder: builder,
              archiveExporter: exporter,
              desktopDownloads: downloads,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('ispace-download-all-courseware')),
    );
    await tester.pumpAndSettle();
  }

  for (final outcome in ['saved', 'cancelled', 'failed']) {
    testWidgets(
      'desktop ZIP export reports $outcome accurately',
      (tester) async {
        final downloads = _Downloads(outcome);
        await showPicker(
          tester,
          _Controller(),
          _Builder(),
          downloads: downloads,
        );
        expect(
          find.byKey(const ValueKey('download-directory-archive')),
          findsOneWidget,
        );
        await tester.tap(find.text('下载并生成 ZIP'));
        await tester.pumpAndSettle();
        expect(downloads.calls, 1);
        expect(
          find.text('ZIP 已保存到所选位置'),
          outcome == 'saved' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('ZIP 保存失败，请重试。'),
          outcome == 'failed' ? findsOneWidget : findsNothing,
        );
        expect(find.text('打开 ZIP'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'defaults to all, allows deselection, downloads only after confirmation',
    (tester) async {
      final controller = _Controller();
      final builder = _Builder();
      await showPicker(tester, controller, builder);
      expect(builder.entries, isEmpty);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == true),
        isTrue,
      );
      await tester.tap(find.text('slides0.pptx'));
      await tester.pump();
      await tester.tap(find.text('下载并生成 ZIP'));
      await tester.pumpAndSettle();
      expect(builder.entries.map((file) => file.fileName), ['slides1.pptx']);
      expect(controller.planCalls, 2);
      expect(controller.webCalls, 1);
      expect(find.text('ZIP 已生成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changed permission blocks previously selected files', (
    tester,
  ) async {
    final controller = _Controller();
    final builder = _Builder();
    await showPicker(tester, controller, builder);
    controller.plan = const CoursewareDownloadPlan(files: []);
    await tester.tap(find.text('下载并生成 ZIP'));
    await tester.pumpAndSettle();
    expect(builder.entries, isEmpty);
    expect(controller.webCalls, 0);
    expect(find.text('课件清单已变化，请重新选择。'), findsOneWidget);
  });

  for (final size in [
    const Size(390, 844),
    const Size(900, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('partial result reports file errors and retries at $size', (
      tester,
    ) async {
      final builder = _Builder()..partial = true;
      final controller = _Controller();
      await showPicker(
        tester,
        controller,
        builder,
        size: size,
        english: true,
        textScale: 1.5,
      );
      await tester.tap(find.text('Download ZIP'));
      await tester.pumpAndSettle();
      expect(find.text('Partial ZIP is ready'), findsOneWidget);
      expect(find.text('ZIP is ready'), findsNothing);
      expect(find.text('Downloaded 1 / 2'), findsOneWidget);
      expect(find.text('slides1.pptx'), findsOneWidget);
      expect(tester.takeException(), isNull);
      builder.partial = false;
      await tester.tap(find.text('Retry failed files'));
      await tester.pumpAndSettle();
      expect(find.text('ZIP is ready'), findsOneWidget);
      expect(find.text('Retry failed files'), findsNothing);
      expect(controller.planCalls, 3);
      expect(controller.webCalls, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing while downloading invalidates the archive lease', (
    tester,
  ) async {
    final controller = _Controller();
    final builder = _Builder()..pending = Completer<CourseArchiveResult>();
    await showPicker(tester, controller, builder);
    await tester.tap(find.text('下载并生成 ZIP'));
    await tester.pump();
    expect(builder.active!(), isTrue);
    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();
    expect(builder.active!(), isFalse);
    builder.pending!.completeError(const CourseArchiveException('下载已取消。'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change clears file list and download action', (
    tester,
  ) async {
    final controller = _Controller();
    await showPicker(tester, controller, _Builder());
    controller.expire();
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('下载并生成 ZIP'), findsNothing);
    expect(find.text('登录状态已变化，请重新打开课程页面。'), findsOneWidget);
  });

  for (final size in [
    const Size(390, 844),
    const Size(900, 600),
    const Size(1440, 900),
    const Size(390, 380),
  ]) {
    testWidgets('English picker fits $size with large text', (tester) async {
      final controller = _Controller()
        ..plan = CoursewareDownloadPlan(
          files: files,
          unavailablePages: 1,
          skippedLinks: 1,
        );
      await showPicker(
        tester,
        controller,
        _Builder(),
        size: size,
        english: true,
        textScale: 1.5,
      );
      expect(find.text('Download ZIP'), findsOneWidget);
      expect(find.text('下载全部课件'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty course gives a clear non-downloadable state', (
    tester,
  ) async {
    final controller = _Controller()
      ..plan = const CoursewareDownloadPlan(files: []);
    await showPicker(tester, controller, _Builder());
    expect(find.text('当前课程没有可下载的课件。'), findsOneWidget);
    final download = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下载并生成 ZIP'),
    );
    expect(download.onPressed, isNull);
  });

  testWidgets('entry belongs to the selected course workspace', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: IspacePage(controller: controller, onGoToUserTab: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(course.shortName), findsOneWidget);
    await tester.tap(find.text(course.shortName));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('ispace-download-all-courseware'));
    final card = find
        .ancestor(of: button, matching: find.byType(IspaceCourseWorkspace))
        .first;
    expect(
      find.descendant(of: card, matching: find.text(course.fullName)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CoursewareDownloadButton>(
            find.byType(CoursewareDownloadButton),
          )
          .course
          .id,
      course.id,
    );
    expect(tester.takeException(), isNull);
  });
}

class _Controller extends AppSessionController {
  final lease = _Lease();
  CoursewareDownloadPlan plan = CoursewareDownloadPlan(files: files);
  int planCalls = 0;
  int webCalls = 0;
  @override
  bool get isLoggedIn => true;
  @override
  String get baseUrl => 'https://ispace.example.edu';
  @override
  List<CourseSummary> get courses => [course];
  @override
  AppSessionLease captureSessionLease() => lease;
  void expire() {
    lease.active = false;
    notifyListeners();
  }

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async =>
      [];
  @override
  Future<CoursewareDownloadPlan> loadCoursewareDownloadPlan(
    int courseId,
  ) async {
    expect(courseId, 7);
    planCalls++;
    return plan;
  }

  @override
  Future<WebSessionSnapshot> prepareWebSession() async {
    webCalls++;
    return WebSessionSnapshot(
      baseUrl: baseUrl,
      cookies: [
        WebSessionCookie(
          name: 'MoodleSession',
          value: 'test-session',
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

class _Lease implements AppSessionLease {
  bool active = true;
  @override
  bool get isActive => active;
  @override
  String get owner => 'test@example.edu';
}

class _Downloads extends DesktopDownloadService {
  _Downloads(this.outcome);
  final String outcome;
  int calls = 0;

  @override
  Future<String> directory(DesktopDownloadPurpose purpose) async =>
      '/Downloads/Courseware';
  @override
  Future<String?> save({
    required String sourcePath,
    required String fileName,
    required bool Function() isActive,
    DesktopDownloadPurpose purpose = DesktopDownloadPurpose.single,
  }) async {
    calls++;
    expect(isActive(), isTrue);
    expect(fileName, 'course.zip');
    expect(purpose, DesktopDownloadPurpose.archive);
    if (outcome == 'failed') throw StateError('test export failure');
    return outcome == 'saved' ? '/Downloads/Courseware/course.zip' : null;
  }
}

class _Native extends NativeActions {
  @override
  Future<String> getMailAttachmentCacheDirectory() async =>
      '/tmp/courseware-widget-test';
}

class _Builder implements CourseArchiveBuilder {
  bool partial = false;
  List<CourseArchiveEntry> entries = [];
  bool Function()? active;
  Completer<CourseArchiveResult>? pending;
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
    active = sessionIsActive;
    return pending?.future ??
        CourseArchiveResult(
          path: '$cacheDirectory/course.zip',
          fileName: 'course.zip',
          fileCount: partial ? 1 : entries.length,
          totalBytes: 3,
          failures: partial
              ? [
                  CourseArchiveFailure(
                    entry: entries.last,
                    message: '文件链接返回了网页，无法作为课件下载。',
                  ),
                ]
              : const [],
        );
  }
}
