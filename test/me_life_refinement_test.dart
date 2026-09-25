import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/pages/campus_landmarks_page.dart';
import 'package:bnbu_me/services/landmark_review_service.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/community_avatar.dart';
import 'package:bnbu_me/widgets/landmark_reviews_section.dart';
import 'campus_landmarks_test.dart' as fixtures;
import 'landmark_reviews_section_test.dart' as reviews;

class LongReviews extends reviews.Reviews {
  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  }) async => LandmarkReviewPage.fromJson({
    'policy': reviews.policy,
    'summary': {
      'average': 9.0,
      'count': 2,
      'counts': [0, 0, 0, 1, 1],
    },
    'total': 8,
    'items': List.generate(
      8,
      (i) => {
        'id': 'comment-$i',
        'body': '公开体验内容，用于验证滚动和布局。',
        'version': 1,
        'created_at': '2026-09-14T00:00:00Z',
        'updated_at': '2026-09-14T00:00:00Z',
        'author': {'name': '匿名用户$i', 'seed': 'fixture-$i', 'anonymous': true},
        'stars': 5,
      },
    ),
  });
}

class WindowReviews extends reviews.Reviews {
  bool waiting = true;
  @override
  Future<LandmarkReviewMine> mine(String username, String id) async =>
      LandmarkReviewMine(
        stars: stars,
        canReview: true,
        nextEditAt: waiting
            ? DateTime.now().add(const Duration(hours: 24))
            : null,
      );
}

void main() {
  test('Glyphs identity is stable and public/anonymous images differ', () {
    final public = CommunityAvatar.svgForSeed('synthetic-public');
    expect(public, contains('<svg'));
    expect(CommunityAvatar.svgForSeed('synthetic-public'), public);
    expect(CommunityAvatar.svgForSeed('synthetic-anonymous'), isNot(public));
  });
  test(
    'pre-enrollment avatar is random, retained and account isolated',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = CommunityAvatarSeedStore();
      final first = await store.local('fixture-a');
      expect(await store.local('fixture-a'), first);
      expect(await store.local('fixture-b'), isNot(first));
      expect(first, matches(RegExp(r'^[a-f0-9]{32}$')));
    },
  );
  testWidgets(
    'stale client cooldown refreshes before blocking a zero interval',
    (tester) async {
      final service = WindowReviews()..stars = 4;
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
      service.waiting = false;
      await tester.tap(find.byKey(const ValueKey('me-rating-5')));
      await tester.pumpAndSettle();
      expect(service.ratingWrites, 1);
      expect(service.stars, 5);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 402.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'reference detail scroll title and rating layout $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 874);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final store = fixtures.MemoryStore();
          addTearDown(store.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: CampusLandmarkDetailPage(
                id: 'lrc',
                store: store,
                owner: 'fixture',
                reviewService: LongReviews(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final nav = find.byKey(const ValueKey('landmark-navbar-title'));
          expect(
            tester
                .getSize(find.byKey(const ValueKey('me-community-toolbar')))
                .height,
            lessThan(150),
          );
          expect(tester.widget<Opacity>(nav).opacity, 0);
          final avatar = tester.getSize(
            find.byKey(const ValueKey('landmark-open-gallery')),
          );
          expect(avatar.width / avatar.height, closeTo(1, .001));
          if (width == 402 && scale == 1) {
            expect(avatar.height, 90);
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('me-rating-card')))
                  .height,
              lessThanOrEqualTo(112),
            );
          }
          final scroll = tester
              .widget<SingleChildScrollView>(
                find.byKey(const ValueKey('landmark-detail-scroll')),
              )
              .controller!;
          final start = width >= 700 ? 150.0 : 42.0;
          scroll.jumpTo(start + 13);
          await tester.pump();
          expect(tester.widget<Opacity>(nav).opacity, closeTo(.5, .001));
          scroll.jumpTo(start + 40);
          await tester.pump();
          expect(tester.widget<Opacity>(nav).opacity, 1);
          scroll.jumpTo(0);
          await tester.pump();
          expect(tester.widget<Opacity>(nav).opacity, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
