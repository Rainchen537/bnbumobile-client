import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/landmark_reviews_section.dart';
import 'package:bnbu_me/widgets/landmark_comment_editor.dart';
import 'landmark_reviews_section_test.dart' as fixtures;

Map<String, dynamic> comment(int i) => {
  'id': 'c$i',
  'body': '测试正文$i',
  'version': 1,
  'created_at': '2026-09-14T00:00:0${i}Z',
  'updated_at': '2026-09-14T00:00:0${i}Z',
  'author': {'name': '测试用户$i', 'seed': 'test-$i', 'anonymous': true},
};

class SortedReviews extends fixtures.Reviews {
  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  }) async => LandmarkReviewPage.fromJson({
    'policy': fixtures.policy,
    'summary': {
      'average': 9,
      'count': 2,
      'counts': [0, 0, 0, 1, 1],
    },
    'total': 3,
    'items': (sort == 'oldest' ? [1, 2, 3] : [3, 2, 1]).map(comment).toList(),
  });
  @override
  Future<LandmarkReviewMine> mine(String username, String id) async =>
      LandmarkReviewMine(
        review: LandmarkReview.fromJson(comment(1)),
        canReview: true,
      );
}

class DeletedReviews extends fixtures.Reviews {
  @override
  Future<LandmarkReviewMine> mine(String username, String id) async =>
      LandmarkReviewMine(
        review: LandmarkReview.fromJson({...comment(1), 'deleted': true}),
        canReview: true,
      );
}

class DelayedReviews extends SortedReviews {
  Completer<LandmarkReviewPage>? pending;
  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  }) =>
      pending?.future ??
      super.browse(id, offset: offset, sort: sort, rootId: rootId);
}

void main() {
  testWidgets(
    'sort refresh overlays the existing gap without shifting comments',
    (tester) async {
      tester.view.physicalSize = const Size(402, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = DelayedReviews();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: LandmarkReviewsSection(
                landmarkId: 'lrc',
                username: 'fixture',
                service: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gap = find.byKey(const ValueKey('me-comments-refresh-gap'));
      final beforeGap = tester.getRect(gap),
          beforeRow = tester.getRect(find.text('测试正文3'));
      service.pending = Completer<LandmarkReviewPage>();
      await tester.tap(find.text('最晚'));
      await tester.pump();
      expect(find.text('全部评论 / 3'), findsOneWidget);
      expect(tester.getRect(gap), beforeGap);
      expect(tester.getRect(find.text('测试正文3')), beforeRow);
      final progress = tester.getRect(
        find.byKey(const ValueKey('me-comments-refresh-progress')),
      );
      expect(progress.top, beforeGap.top);
      expect(progress.height, 2);
      service.pending!.complete(await SortedReviews().browse('lrc'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('me-comments-refresh-progress')),
        findsNothing,
      );
      expect(tester.getRect(find.text('测试正文3')), beforeRow);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'new comment defaults public, checkbox opts into anonymous and edit retains identity',
    (tester) async {
      tester.view.physicalSize = const Size(402, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> open(fixtures.Reviews service) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: LandmarkReviewsSection(
                  key: UniqueKey(),
                  landmarkId: 'lrc',
                  username: 'fixture',
                  service: service,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.text(service is SortedReviews ? '编辑我的评论' : '写评论');
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
      }

      await open(fixtures.Reviews());
      final checkbox = find.byKey(const ValueKey('me-comment-anonymous'));
      expect(tester.widget<Checkbox>(checkbox).value, false);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('me-comment-anonymous-visual')))
            .width,
        closeTo(Checkbox.width * .9, .01),
      );
      expect(tester.widget<Checkbox>(checkbox).side!.width, 1.2);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('me-comment-identity')))
            .height,
        greaterThanOrEqualTo(44),
      );

      expect(find.byType(PopupMenuButton<bool>), findsNothing);
      expect(
        tester.getCenter(checkbox).dx,
        lessThan(
          tester.getCenter(find.byKey(const ValueKey('me-comment-submit'))).dx,
        ),
      );
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox).value, true);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await open(DeletedReviews());
      expect(tester.widget<Checkbox>(checkbox).value, false);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await open(SortedReviews());
      expect(tester.widget<Checkbox>(checkbox).value, true);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'selected sort controls title and own comment obeys server order',
    (tester) async {
      tester.view.physicalSize = const Size(402, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: LandmarkReviewsSection(
                landmarkId: 'lrc',
                username: 'fixture',
                service: SortedReviews(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('热评 / 3'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('测试正文3')).dy,
        lessThan(tester.getTopLeft(find.text('测试正文1')).dy),
      );
      await tester.tap(find.text('最早'));
      await tester.pumpAndSettle();
      expect(find.text('全部评论 / 3'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('测试正文1')).dy,
        lessThan(tester.getTopLeft(find.text('测试正文3')).dy),
      );
      await tester.tap(find.text('最晚'));
      await tester.pumpAndSettle();
      expect(find.text('全部评论 / 3'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('测试正文3')).dy,
        lessThan(tester.getTopLeft(find.text('测试正文1')).dy),
      );
      expect(find.text('我的评论'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'editor rating saves immediately while closing leaves comment unpublished',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = fixtures.Reviews();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: LandmarkReviewsSection(
                landmarkId: 'lrc',
                title: '学习资源中心',
                username: 'fixture',
                service: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('写评论'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('me-editor-place-photo')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('me-editor-rating-4')));
      await tester.pumpAndSettle();
      expect(service.stars, 4);
      expect(service.ratingWrites, 1);
      expect(service.commentWrites, 0);
      await tester.enterText(find.byType(TextField), '未发布文字');
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(service.stars, 4);
      expect(service.commentWrites, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  for (final width in [320.0, 402.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final reply in [false, true]) {
        testWidgets(
          'editor keyboard and text scale $width/$scale/reply=$reply',
          (tester) async {
            tester.view.physicalSize = Size(width, 874);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final controller = TextEditingController(text: '可编辑正文');
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 874),
                    viewInsets: const EdgeInsets.only(bottom: 336),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: Align(
                      alignment: Alignment.bottomCenter,
                      child: LandmarkCommentEditor(
                        title: '学习资源中心 Learning Resource Centre',
                        controller: controller,
                        anonymous: true,
                        anonymousName: '匿名用户test',
                        onIdentityChanged: (_) {},
                        onClose: () {},
                        onSubmit: () {},
                        sending: false,
                        editing: true,
                        onDelete: () {},
                        onRate: (_) {},
                        stars: 4,
                        replyName: reply ? '被回复的用户' : null,
                        replyBody: reply ? '被引用的评论正文' : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const ValueKey('me-editor-rating-4')),
              reply ? findsNothing : findsOneWidget,
            );
            expect(
              tester
                  .getBottomLeft(
                    find.byKey(const ValueKey('me-comment-submit')),
                  )
                  .dy,
              lessThanOrEqualTo(538),
            );
            final field = tester.widget<TextField>(find.byType(TextField));
            expect(field.decoration!.focusedBorder, InputBorder.none);
            expect(find.byType(SwitchListTile), findsNothing);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
          },
        );
      }
    }
  }
}
