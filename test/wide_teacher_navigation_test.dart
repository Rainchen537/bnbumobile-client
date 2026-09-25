import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/models/teacher_review.dart';
import 'package:bnbu_me/pages/campus_directory_page.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/services/teacher_review_service.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import '../tool/home_navigation_fixtures.dart';

class _Directory extends RemoteCampusDirectoryService {
  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async => OfficialTeacherPage.fromJson({
    'total': 1,
    'items': [
      {
        'name': '测试教师',
        'match_type': 'exact',
        'profile_url': 'https://staff.bnbu.edu.cn/fixture/en',
      },
    ],
  });
}

class _DelayedDirectory extends _Directory {
  final responses = <Completer<OfficialTeacherPage>>[];
  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) {
    final response = Completer<OfficialTeacherPage>();
    responses.add(response);
    return response.future;
  }
}

class _Reviews extends RemoteTeacherReviewService {
  @override
  Future<TeacherReviewPageData> loadReviews(
    String teacherKey, {
    bool courseLinkedOnly = false,
    int offset = 0,
    int limit = 50,
  }) async => TeacherReviewPageData.fromJson({});
  @override
  Future<TeacherReviewMineState> loadMine(
    String username,
    String teacherKey,
  ) async => TeacherReviewMineState.fromJson({});
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final outcome in ['success', 'back', 'retry']) {
    testWidgets('teacher navigation precedes slow lookup: $outcome', (
      tester,
    ) async {
      final session = HomeNavigationFixture();
      final directory = _DelayedDirectory();
      final reviews = _Reviews();
      addTearDown(() {
        session.dispose();
        directory.dispose();
        reviews.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openOfficialTeacherByName(
                  context,
                  controller: session,
                  teacherName: '测试教师',
                  directoryService: directory,
                  reviewService: reviews,
                ),
                child: const Text('打开教师'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开教师'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('teacher-profile-loading')),
        findsOneWidget,
      );
      expect(find.byType(BackButton), findsOneWidget);
      expect(directory.responses, hasLength(1));
      if (outcome == 'back') {
        await tester.pageBack();
        await tester.pumpAndSettle();
      } else if (outcome == 'retry') {
        directory.responses.first.completeError(StateError('offline'));
        await tester.pumpAndSettle();
        expect(find.text('教师档案加载失败'), findsOneWidget);
        await tester.tap(find.text('重试'));
        await tester.pump();
        expect(directory.responses, hasLength(2));
      }
      directory.responses.last.complete(await _Directory().loadTeachers());
      await tester.pumpAndSettle();
      expect(
        find.byType(OfficialTeacherDetailPage),
        outcome == 'back' ? findsNothing : findsOneWidget,
      );
      if (outcome == 'back') expect(find.text('打开教师'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final tab in [AppTab.home, AppTab.schedule]) {
    testWidgets(
      'direct teacher route keeps side navigation and its history from $tab',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        final session = HomeNavigationFixture();
        final shell = RootShellController()..selectTab(tab);
        final mail = MailAssistantIntentController();
        final ta = TaCourseController(sessionController: session);
        final directory = _Directory();
        final reviews = _Reviews();
        addTearDown(() {
          tester.view.reset();
          directory.dispose();
          reviews.dispose();
          ta.dispose();
          mail.dispose();
          shell.dispose();
          session.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: RootShellPage(
              controller: session,
              shellController: shell,
              taCourseController: ta,
              mailIntentController: mail,
              pageOverrideBuilder: (_) => Builder(
                builder: (context) => TextButton(
                  onPressed: () => openOfficialTeacherByName(
                    context,
                    controller: session,
                    teacherName: '测试教师',
                    directoryService: directory,
                    reviewService: reviews,
                  ),
                  child: const Text('打开教师'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开教师'));
        await tester.pumpAndSettle();
        expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('root-side-navigation-panel')),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byType(OfficialTeacherDetailPage)).left,
          greaterThanOrEqualTo(72),
        );
        shell.selectTab(AppTab.user);
        await tester.pumpAndSettle();
        shell.selectTab(tab);
        await tester.pumpAndSettle();
        expect(find.byType(OfficialTeacherDetailPage), findsOneWidget);
        tester.view.physicalSize = const Size(390, 1000);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('root-bottom-navigation')),
          findsNothing,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('打开教师'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
