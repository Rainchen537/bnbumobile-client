import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/pages/campus_landmarks_page.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_reveal_search.dart';
import '../tool/home_navigation_fixtures.dart';
import 'campus_landmarks_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final dark in [false, true]) {
    testWidgets('five-row units remain readable with large text dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = fixtures.MemoryStore();
      addTearDown(store.dispose);
      final data = fixtures.fixture();
      const title = 'Learning Resource Centre and Collaborative Study Spaces';
      const location = 'North entrance beside the covered pedestrian walkway';
      data['catalog']['landmarks'][0]['names'] = {'zh-Hans': title};
      data['catalog']['landmarks'][0]['locations'] = {'zh-Hans': location};
      store.catalog = LandmarkCatalog.fromJson(data);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CampusLandmarksPage(
            store: store,
            reviewService: fixtures.EmptyReviews(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('landmark-lrc'));
      final photo = find.descendant(
        of: card,
        matching: find.byType(LandmarkPhotoView),
      );
      final photoBounds = tester.getRect(photo);
      for (final text in [title, location]) {
        final finder = find.text(text);
        final bounds = tester.getRect(finder);
        expect(bounds.left, greaterThan(photoBounds.right));
        expect(tester.getRect(card).contains(bounds.topLeft), isTrue);
        final theme = tester.element(finder).bnbuTheme;
        expect(
          tester.widget<Text>(finder).style!.color,
          text == title ? theme.textPrimary : theme.textSecondary,
        );
        expect(tester.widget<Text>(finder).maxLines, 1);
      }
      final pin = find.descendant(
        of: card,
        matching: find.byIcon(LucideIcons.mapPin300),
      );
      expect(
        tester.widget<Icon>(pin).color,
        tester.element(pin).bnbuTheme.textSecondary,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 390.0, 699.0, 700.0, 900.0, 1440.0]) {
    testWidgets('landmark columns and location at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = fixtures.MemoryStore();
      addTearDown(store.dispose);
      final data = fixtures.fixture();
      final landmarks = data['catalog']['landmarks'] as List;
      landmarks[0]['locations'] = {'zh-Hans': 'T1 北门入口'};
      for (var i = 0; i < 3; i++) {
        landmarks.add({
          ...landmarks[0] as Map<String, dynamic>,
          'id': 'extra-$i',
        });
      }
      store.catalog = LandmarkCatalog.fromJson(data);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CampusLandmarksPage(
            store: store,
            reviewService: fixtures.EmptyReviews(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('landmark-lrc'));
      final second = find.byKey(const ValueKey('landmark-extra-0'));
      final third = find.byKey(const ValueKey('landmark-extra-1'));
      final fourth = find.byKey(const ValueKey('landmark-extra-2'));
      if (width < 1000) {
        expect(
          tester.getRect(second).top,
          greaterThan(tester.getRect(first).bottom),
        );
        expect(tester.getRect(second).left, tester.getRect(first).left);
        expect(
          tester.getRect(third).top,
          greaterThan(tester.getRect(second).bottom),
        );
      } else {
        expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
        expect(
          tester.getRect(second).left,
          greaterThan(tester.getRect(first).right),
        );
        expect(
          tester.getTopLeft(third).dy,
          greaterThan(tester.getTopLeft(first).dy),
        );
        expect(tester.getTopLeft(fourth).dy, tester.getTopLeft(third).dy);
      }
      final location = find.descendant(
        of: first,
        matching: find.text('T1 北门入口'),
      );
      final icon = find.descendant(
        of: first,
        matching: find.byIcon(LucideIcons.mapPin300),
      );
      expect(icon, findsOneWidget);
      expect(
        tester.widget<Text>(location).style!.fontSize,
        closeTo(
          12 * (width < 700 ? (width / 402).clamp(.75, 1.15) : 1.1),
          .001,
        ),
      );
      final name = find.descendant(of: first, matching: find.text('学习资源中心'));
      expect(
        tester.widget<Text>(name).style!.fontSize,
        closeTo(
          14 * (width < 700 ? (width / 402).clamp(.75, 1.15) : 1.1),
          .001,
        ),
      );
      expect(
        tester.getRect(icon).right,
        lessThan(tester.getRect(location).left),
      );
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.mapPin300), findsOneWidget);
      expect(find.text('T1 北门入口'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [390.0, 900.0]) {
    testWidgets('outside tap closes landmark search at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = fixtures.MemoryStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CampusLandmarksPage(
            store: store,
            reviewService: fixtures.EmptyReviews(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(BnbuRevealSearch),
        matching: find.byType(TextField),
      );
      final restingWidth = tester.getSize(field).width;
      if (width < 700) {
        await tester.tapAt(Offset(24, tester.getCenter(field).dy));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('landmark-lrc'))),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CampusLandmarkDetailPage), findsNothing);
        expect(tester.getSize(field).width, restingWidth);
      }
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '学习');
      await tester.pumpAndSettle();
      expect(tester.getSize(field).width, greaterThan(restingWidth));
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '学习');
      await tester.tapAt(const Offset(8, 850));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(tester.getSize(field).width, closeTo(restingWidth, 0.1));
      expect(find.text('校园建筑'), findsOneWidget);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '咖啡');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('landmark-coffee')));
      await tester.pumpAndSettle();
      expect(find.byType(CampusLandmarkDetailPage), findsOneWidget);
    });
  }
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('iSpace toolbar stays fixed during pull and scroll at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);
      final session = HomeNavigationFixture();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
          ),
          home: IspacePage(controller: session, onGoToUserTab: () {}),
        ),
      );
      await tester.pumpAndSettle();
      final toolbar = find.byKey(
        ValueKey(
          width >= 880 ? 'ispace-desktop-top-bar' : 'ispace-compact-top-bar',
        ),
      );
      final card = find.byKey(const ValueKey('ispace-timeline-card-1'));
      final navigation = find.byKey(
        const ValueKey('ispace-top-bar-navigation-button'),
      );
      final icon = find.descendant(
        of: navigation,
        matching: find.byIcon(LucideIcons.menu300),
      );
      final before = tester.getRect(toolbar);
      expect(
        tester.getRect(icon).left,
        closeTo(tester.getRect(card).left, 0.1),
      );
      expect(tester.getSize(navigation).width, greaterThanOrEqualTo(44));
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('ispace-timeline-filter-control')),
            )
            .left,
        closeTo(tester.getRect(card).left + (width >= 880 ? 48 : 60), 0.1),
      );

      final cardY = tester.getTopLeft(card).dy;
      final gesture = await tester.startGesture(tester.getCenter(card));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 160));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(toolbar), before);
      expect(tester.getTopLeft(card).dy, greaterThan(cardY));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(session.deadlineRefreshes, greaterThan(0));
      await tester.drag(card, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(toolbar), before);
      await tester.tapAt(
        tester.getRect(navigation).topLeft + const Offset(2, 24),
      );
      await tester.pumpAndSettle();
      if (width < 880) {
        expect(find.byType(Drawer), findsOneWidget);
      } else {
        expect(
          find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
