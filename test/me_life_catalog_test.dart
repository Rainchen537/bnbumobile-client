import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/models/me_life_presentation.dart';
import 'package:bnbu_me/services/campus_landmark_store.dart';
import 'package:bnbu_me/widgets/me_life_catalog.dart';
import 'package:bnbu_me/widgets/me_life_badge.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'campus_landmarks_test.dart' show fixture;
import 'landmark_reviews_section_test.dart' show Reviews;
import 'package:bnbu_me/pages/campus_landmarks_page.dart';

const openPolicy = {
  'read_comments': true,
  'read_ratings': true,
  'level': -1,
  'revision': 1,
};

class CatalogFixture extends CampusLandmarkStore {
  int reads = 0, policyReads = 0;
  bool closed = false;
  CatalogFixture() {
    final json = fixture();
    json['catalog']['title'] = {'zh-Hans': 'ME生活'};
    json['catalog']['categories'] = [
      for (final e in const {
        'campus-buildings': '校园建筑',
        'food-and-shops': '美食商超',
        'club-fair': '百团大战',
        'off-campus': '校外推荐',
        'all-events': '活动大全',
      }.entries)
        {
          'id': e.key,
          'names': {'zh-Hans': e.value},
        },
    ];
    json['catalog']['styles'] = [
      {
        'id': 'brand',
        'template': 'brand',
        'foreground': '#f7e7ca',
        'background': '#5b4027',
        'accent': '#332819',
      },
      {
        'id': 'flame',
        'template': 'flame',
        'foreground': '#ff5c00',
        'background': '#fff6e4',
        'accent': '#ffe7ab',
      },
      {
        'id': 'rank',
        'template': 'rank',
        'foreground': '#92521d',
        'background': '#fff4e4',
        'accent': '#ffe4b8',
      },
      {'id': 'gray', 'template': 'plain'},
      {
        'id': 'green',
        'template': 'plain',
        'foreground': '#12af62',
        'border': '#8cdeb3',
      },
      {
        'id': 'orange',
        'template': 'plain',
        'foreground': '#ff633c',
        'border': '#ffb6a4',
      },
    ];
    json['catalog']['tag_definitions'] = [
      for (final e in const {
        'brand': '校园',
        'hours': '24小时开放',
        'study': '自习空间',
        'hidden': '不会显示的搜索词',
      }.entries)
        {
          'id': e.key,
          'texts': {'zh-Hans': e.value},
        },
    ];
    final original = json['catalog']['landmarks'][0] as Map;
    json['catalog']['landmarks'] = [
      for (var i = 0; i < 4; i++)
        {
          ...original,
          'id': 'unit-$i',
          'category_id': 'campus-buildings',
          'names': {'zh-Hans': i.isEven ? '学习资源中心' : '大学生活动中心'},
          'locations': {'zh-Hans': '校园北侧 · 中央广场'},
          'descriptions': {'zh-Hans': '图书借阅、电子资源与安静的学习空间'},
          'photos': [
            {'id': 'a' * 64, 'focus_x': .5, 'focus_y': .5},
          ],
          'cover': {'id': 'a' * 64, 'focus_x': .5, 'focus_y': .5},
          'list_image_ratio': i == 1 ? '4:3' : '1:1',
          if (i == 2)
            'spotlight': {
              'modes': ['tag'],
            },
          'tag_slots': {
            'score_after': {'tag_id': 'study', 'style_id': 'green'},
            'image_top_left': {'tag_id': 'brand', 'style_id': 'brand'},
            'score_below': [
              {'tag_id': 'hours', 'style_id': 'gray'},
              {'tag_id': 'study', 'style_id': 'green'},
            ],
            'hidden': 'hidden',
          },
        },
    ];
    catalog = LandmarkCatalog.fromJson(json);
  }
  @override
  Future<File?> photo(LandmarkPhoto photo, {bool full = false}) async =>
      File('assets/me_life/header-campus.png');
  @override
  Future<void> refresh() async {
    presentationEpoch++;
    notifyListeners();
  }

  @override
  Future<void> loadLocal() async {}
  @override
  Future<LifeUnitPresentation> presentation(String id, int cursor) async {
    reads++;
    return LifeUnitPresentation.fromJson({
      'policy': openPolicy,
      'score': 9.0,
      'rating_count': 2,
      'content': {
        'kind': 'review',
        'text': id == 'unit-0'
            ? '安静'
            : cursor.isEven
            ? '靠窗的位置很舒服，适合安静地读书。'
            : '找资料很方便。',
        'style_id': id == 'unit-1' ? 'rank' : 'flame',
      },
    });
  }

  @override
  Future<CommunityPolicy> presentationPolicy(String id) async {
    policyReads++;
    return CommunityPolicy.fromJson(
      closed ? {'level': 3, 'revision': 2} : openPolicy,
    );
  }
}

void main() {
  test(
    'policy closure invalidates cached public selections before row remount',
    () async {
      var closed = false, reads = 0;
      final client = MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.followRedirects, isFalse);
        final caps = closed ? {'level': 3, 'revision': 2} : openPolicy;
        if (request.url.path.endsWith('/policy')) {
          return http.Response(jsonEncode(caps), 200);
        }
        reads++;
        return http.Response(
          jsonEncode({
            'policy': caps,
            'score': closed ? null : 9.0,
            'content': closed
                ? null
                : {
                    'kind': 'review',
                    'text': 'test',
                    'style_id': 'flame-orange',
                  },
          }),
          200,
        );
      });
      final store = CampusLandmarkStore(
        client: client,
        baseUrl: 'https://content.example',
      );
      addTearDown(store.dispose);
      expect((await store.presentation('lrc', 0)).content, isNotNull);
      await store.presentation('lrc', 0);
      expect(reads, 1);
      closed = true;
      await store.presentationPolicy('lrc');
      expect((await store.presentation('lrc', 0)).content, isNull);
      expect(reads, 2);
    },
  );
  test('source rotation alternates refresh steps and skips empty sources', () {
    expect(
      List.generate(
        8,
        (i) => lifeRotationItem(['a1', 'a2'], ['r1', 'r2', 'r3'], i),
      ),
      ['a1', 'r1', 'a2', 'r2', 'a1', 'r3', 'a2', 'r1'],
    );
    expect(lifeRotationItem(<String>[], ['r1', 'r2'], 3), 'r2');
    expect(lifeRotationItem(<String>[], <String>[], 0), isNull);
    expect(
      () => LifeSpotlight.fromJson({
        'modes': ['tag', 'review'],
      }),
      throwsFormatException,
    );
    expect(LifeSpotlight.fromJson({'review_limit': null}).reviewLimit, isNull);
  });
  test('sheet top pull has resistance and bounded spring return', () {
    const physics = LifeSheetPhysics();
    FixedScrollMetrics metrics(double pixels) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 600,
      pixels: pixels,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 3,
    );
    expect(physics.applyPhysicsToUserOffset(metrics(0), 100), 18);
    expect(physics.applyPhysicsToUserOffset(metrics(-12), 100), lessThan(5));
    expect(physics.applyBoundaryConditions(metrics(-20), -70), -46);
    final spring = physics.createBallisticSimulation(metrics(-18), 0)!;
    expect(spring.x(5), closeTo(0, .01));
  });
  testWidgets('fixed photograph stays in place while only sheet resists pull', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.reset);
    final store = CatalogFixture();
    final reviews = Reviews();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CampusLandmarkDetailPage(
          id: 'unit-0',
          store: store,
          owner: 'fixture',
          reviewService: reviews,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final background = find.byKey(const ValueKey('landmark-fixed-background'));
    final rect = tester.getRect(background);
    final scrolling = find.byKey(const ValueKey('landmark-detail-scroll'));
    final gesture = await tester.startGesture(tester.getCenter(scrolling));
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump();
    expect(tester.getRect(background), rect);
    final state = tester.state<ScrollableState>(
      find.descendant(of: scrolling, matching: find.byType(Scrollable)).first,
    );
    expect(state.position.pixels, lessThanOrEqualTo(0));
    expect(state.position.pixels, greaterThanOrEqualTo(-24));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.position.pixels, closeTo(0, .1));
    expect(reviews.browseReads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 402.0]) {
    testWidgets(
      'catalog at $width preserves static selection during policy checks',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 874);
        addTearDown(tester.view.reset);
        final store = CatalogFixture();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AnimatedBuilder(
              animation: store,
              builder: (context, _) =>
                  MeLifeMobileCatalog(store: store, onOpen: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('活动大全'), findsOneWidget);
        expect(find.text('9.0分'), findsWidgets);
        expect(
          tester.widget<Text>(find.text('9.0分').first).style!.color,
          BnbuThemeExtension.light.brandBlue,
        );
        for (final id in ['unit-0', 'unit-2']) {
          final row = find.byKey(ValueKey('landmark-$id'));
          final labels = find.descendant(
            of: row,
            matching: find.byType(LifeBadge),
          );
          final target = labels.evaluate().firstWhere((e) {
            final b = e.widget as LifeBadge;
            return b.text == (id == 'unit-0' ? '安静' : '自习空间');
          });
          final rect = tester.getRect(find.byWidget(target.widget));
          expect(rect.width, lessThan(width * .25));
          expect(rect.right, lessThanOrEqualTo(tester.getRect(row).right));
        }

        expect(find.text('不会显示的搜索词'), findsNothing);
        final reads = store.reads;
        await tester.pump(const Duration(seconds: 21));
        await tester.pumpAndSettle();
        expect(store.reads, reads);
        expect(store.policyReads, greaterThan(0));
        store.closed = true;
        await tester.pump(const Duration(seconds: 21));
        await tester.pumpAndSettle();
        expect(find.text('9.0分'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('render reference scale styles and five category pairs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 410);
    addTearDown(tester.view.reset);
    final render = Platform.environment['ME_LIFE_RENDER'] == '1';
    if (render) {
      await tester.runAsync(() async {
        final path = Platform.environment['ME_LIFE_FONT'];
        if (path != null) {
          final loader = FontLoader('ReviewFont');
          loader.addFont(
            File(path).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
          await loader.load();
          for (final family in ['Roboto', 'MaterialIcons']) {
            final f = FontLoader(family);
            f.addFont(
              family == 'MaterialIcons'
                  ? rootBundle.load('fonts/MaterialIcons-Regular.otf')
                  : File(
                      path,
                    ).readAsBytes().then((b) => ByteData.sublistView(b)),
            );
            await f.load();
          }
          await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
                rootBundle.load(
                  'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
                ),
              ))
              .load();
        }
      });
    }
    final store = CatalogFixture();
    addTearDown(store.dispose);
    final baseTheme = Platform.environment['ME_LIFE_RENDER_DARK'] == '1'
        ? AppTheme.dark
        : AppTheme.light;
    final theme = baseTheme.copyWith(
      appBarTheme: render
          ? baseTheme.appBarTheme.copyWith(
              titleTextStyle: const TextStyle(fontFamily: 'ReviewFont'),
            )
          : baseTheme.appBarTheme,
      textTheme: baseTheme.textTheme.apply(
        fontFamily: render ? 'ReviewFont' : null,
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final selected in [false, true])
                    Row(
                      children: [
                        for (final c in store.catalog!.categories)
                          Expanded(
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 64,
                                  child: LifeCategoryImage(
                                    category: c,
                                    selected: selected,
                                    store: store,
                                  ),
                                ),
                                Text(
                                  c.names['zh-Hans']!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  for (final style in store.catalog!.styles)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: LifeBadge(
                        text: style.template == 'brand'
                            ? '品牌'
                            : style.template == 'flame'
                            ? '近期141人好评'
                            : style.template == 'rank'
                            ? '校园人气学习空间榜'
                            : '24小时营业',
                        style: style,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (render) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/me-life-catalog/styles-review.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    if (render) {
      await tester.runAsync(() async {
        final file = File('assets/me_life/header-campus.png');
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        final frame = await codec.getNextFrame();
        codec.dispose();
        final provider = FileImage(file);
        PaintingBinding.instance.imageCache.evict(provider);
        PaintingBinding.instance.imageCache.putIfAbsent(
          provider,
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame.image)),
          ),
        );
      });
      await tester.runAsync(() async {
        for (final asset in [
          'assets/me_life/header-campus.png',
          'assets/me_life/header-campus-dark.png',
        ]) {
          final provider = AssetImage(asset);
          final assetKey = await provider.obtainKey(ImageConfiguration.empty);
          final data = await rootBundle.load(asset);
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          codec.dispose();
          PaintingBinding.instance.imageCache.evict(assetKey);
          PaintingBinding.instance.imageCache.putIfAbsent(
            assetKey,
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: frame.image)),
            ),
          );
        }
      });
      tester.view.physicalSize = const Size(402, 874);
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigation,
          theme: theme,
          home: const SizedBox(),
        ),
      );
      navigation.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => RepaintBoundary(
            key: key,
            child: MeLifeMobileCatalog(store: store, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/me-life-catalog/mobile-layout-review.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
