import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/services/landmark_review_service.dart';
import 'package:bnbu_me/widgets/landmark_reviews_section.dart';
import 'package:bnbu_me/theme/app_theme.dart';

const policy = {
  'level': -1,
  'revision': 1,
  'read_comments': true,
  'read_ratings': true,
  'write_comments': true,
  'write_ratings': true,
  'react': true,
};

class Reviews extends Fake implements LandmarkReviewService {
  @override
  Future<CommunityPolicy> readPolicy(String id) async =>
      CommunityPolicy.fromJson(
        closed
            ? {
                ...policy,
                'level': 3,
                'read_comments': false,
                'read_ratings': false,
                'write_comments': false,
                'write_ratings': false,
                'react': false,
              }
            : policy,
      );
  int browseReads = 0;
  int? stars;
  int ratingWrites = 0, commentWrites = 0;
  bool closed = false;
  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  }) async {
    browseReads++;
    return LandmarkReviewPage.fromJson({
      'policy': closed
          ? {
              ...policy,
              'level': 3,
              'read_comments': false,
              'read_ratings': false,
              'write_comments': false,
              'write_ratings': false,
              'react': false,
            }
          : policy,
      'summary': {
        'average': stars == null ? null : stars! * 2,
        'count': stars == null ? 0 : 1,
        'counts': List.generate(5, (i) => stars == i + 1 ? 1 : 0),
      },
      'total': 0,
      'items': [],
    });
  }

  @override
  Future<LandmarkReviewMine> mine(String username, String id) async =>
      LandmarkReviewMine(stars: stars, canReview: true);
  @override
  Future<LandmarkReviewMine> rate(
    String username,
    String id, {
    required int version,
    required int stars,
  }) async {
    this.stars = stars;
    ratingWrites++;
    return mine(username, id);
  }

  @override
  Future<void> comment(
    String username,
    String id, {
    required int version,
    required String body,
    required bool anonymous,
    required String requestId,
    String? replyTo,
  }) async {
    commentWrites++;
  }

  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'remote closure disables publishing but keeps draft and close usable',
    (tester) async {
      final service = Reviews();
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
      await tester.ensureVisible(find.text('写评论'));
      await tester.tap(find.text('写评论'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留草稿');
      final beforePolicyCheck = service.browseReads;
      service.closed = true;
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(service.browseReads, beforePolicyCheck);
      expect(find.text('保留草稿'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('me-comment-submit')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(service.commentWrites, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('direct rating without comment at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.reset);
      final service = Reviews();
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
      expect(find.text('ME评分'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('me-rating-4')));
      await tester.pumpAndSettle();
      expect(service.ratingWrites, 1);
      expect(service.commentWrites, 0);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('8.0'), findsOneWidget);
      expect(find.text('暂无评论'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final beforePolicyCheck = service.browseReads;
      service.closed = true;
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(service.browseReads, beforePolicyCheck);
      expect(find.text('ME评分'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
