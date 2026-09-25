import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/models/me_life_presentation.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/me_life_content.dart';
import 'package:bnbu_me/pages/campus_landmarks_page.dart';
import 'package:bnbu_me/widgets/me_life_badge.dart';
import 'package:bnbu_me/widgets/me_life_catalog.dart';
import 'package:bnbu_me/widgets/landmark_reviews_section.dart';
import 'me_life_catalog_test.dart' show CatalogFixture;
import 'landmark_reviews_section_test.dart' show Reviews, policy;

class PreviewReviews extends Reviews {
  int replyReads = 0;
  Map<String, dynamic> entry(String id, String text) => {
    'id': id,
    'body': text,
    'author': {'name': '测试同学', 'seed': id},
    'version': 2,
    'created_at': '2026-09-16T00:00:00Z',
    'updated_at': '2026-09-16T01:00:00Z',
  };
  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  }) async {
    if (rootId != null) replyReads++;
    return LandmarkReviewPage.fromJson({
      'policy': {...policy, 'read_ratings': false, 'write_ratings': false},
      'summary': {
        'average': null,
        'count': 0,
        'counts': [0, 0, 0, 0, 0],
      },
      'total': rootId == null ? 1 : 2,
      'items': rootId == null
          ? [
              {
                ...entry('main', '第一行\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行'),
                'edited_at': '2026-09-16T01:00:00Z',
                'reply_count': 2,
                'reply_preview': entry('reply1', '默认可见的一条回复'),
              },
            ]
          : [entry('reply1', '默认可见的一条回复'), entry('reply2', '展开后的第二条回复')],
    });
  }
}

void main() {
  if (Platform.environment['ME_LIFE_RENDER'] == '1') {
    setUpAll(() async {
      final font =
          Platform.environment['ME_LIFE_FONT'] ??
          '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
      for (final family in ['Roboto', 'Preview']) {
        await (FontLoader(family)..addFont(
              File(font).readAsBytes().then((b) => ByteData.sublistView(b)),
            ))
            .load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
            rootBundle.load(
              'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
            ),
          ))
          .load();
    });
  }
  if (Platform.environment['ME_LIFE_RENDER'] == '1') {
    testWidgets('render wave2 detail', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);
      final store = CatalogFixture();
      final json = store.catalog!.json;
      final tags = json['catalog']['tag_definitions'] as List;
      for (var i = 0; i < 8; i++) {
        tags.add({
          'id': 'more-$i',
          'texts': {'zh-Hans': '服务标签$i'},
        });
      }
      (json['catalog']['landmarks'] as List)[0]['tag_slots']['bottom'] = [
        for (var i = 0; i < 8; i++) {'tag_id': 'more-$i', 'style_id': 'green'},
      ];
      store.catalog = LandmarkCatalog.fromJson(json);
      await tester.runAsync(() async {
        final provider = FileImage(File('assets/me_life/header-campus.png'));
        final codec = await ui.instantiateImageCodec(
          await provider.file.readAsBytes(),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        PaintingBinding.instance.imageCache.putIfAbsent(
          provider,
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame.image)),
          ),
        );
      });
      final dark = Platform.environment['ME_LIFE_RENDER_DARK'] == '1';
      final theme = (dark ? AppTheme.dark : AppTheme.light);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Preview'),
            textButtonTheme: TextButtonThemeData(
              style: theme.textButtonTheme.style?.copyWith(
                textStyle: WidgetStatePropertyAll(
                  theme.textTheme.labelLarge!.copyWith(fontFamily: 'Preview'),
                ),
              ),
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: CampusLandmarkDetailPage(
              id: 'unit-0',
              owner: 'fixture',
              store: store,
              reviewService: PreviewReviews(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ImageFiltered), findsOneWidget);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/me-life-wave2').create(recursive: true);
        await File(
          'build/me-life-wave2/detail-${dark ? 'dark' : 'light'}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byTooltip('展开标签'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
  testWidgets('long comments and one reply preview survive expand/collapse', (
    tester,
  ) async {
    final service = PreviewReviews();
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
    expect(find.byKey(const ValueKey('me-rating-card')), findsNothing);
    expect(find.text('默认可见的一条回复'), findsOneWidget);
    expect(find.text('已编辑'), findsOneWidget);
    expect(service.replyReads, 0);
    expect(find.text('展开全文'), findsOneWidget);
    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    await tester.ensureVisible(find.text('查看回复 (2)'));
    await tester.tap(find.text('查看回复 (2)'));
    await tester.pumpAndSettle();
    expect(service.replyReads, 1);
    expect(find.text('默认可见的一条回复'), findsOneWidget);
    expect(find.text('展开后的第二条回复'), findsOneWidget);
    await tester.ensureVisible(find.text('收起回复'));
    await tester.tap(find.text('收起回复'));
    await tester.pumpAndSettle();
    expect(find.text('展开后的第二条回复'), findsNothing);
    await tester.ensureVisible(find.text('写评论'));
    await tester.tap(find.text('写评论'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('me-editor-rating-1')), findsNothing);
    expect(find.byType(TextField), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tag overflow is whole, accessible only after expanding', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const key = ValueKey('strip');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 160,
              child: LifeTagStrip(
                key: key,
                expandable: true,
                children: [
                  for (final text in ['First', 'Second', 'Third', 'Fourth'])
                    LifeBadge(
                      text: text,
                      style: LifeStyle.fallback,
                      truncate: false,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getSemantics(find.byKey(key)).toStringDeep();
    expect(before, contains('First'));
    expect(before, isNot(contains('Fourth')));
    await tester.tap(find.byTooltip('展开标签'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(key)).toStringDeep(),
      contains('Fourth'),
    );
    await tester.tap(find.byTooltip('收起标签'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(key)).toStringDeep(),
      isNot(contains('Fourth')),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  for (final width in [320.0, 402.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('unit layout $width / $scale without score placeholder', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = CatalogFixture();
        final json = store.catalog!.json;
        final unit = (json['catalog']['landmarks'] as List)[0] as Map;
        unit['rating_enabled'] = false;
        unit['icon_row'] = [
          {
            'icon': 'info',
            'source': 'text',
            'texts': {'zh-Hans': '校内服务'},
          },
        ];
        final catalog = LandmarkCatalog.fromJson(json);
        final item = catalog.landmarks.first;
        const boundary = ValueKey('wave2-boundary');
        await tester.pumpWidget(
          MaterialApp(
            theme: (Platform.environment['ME_LIFE_RENDER_DARK'] == '1'
                ? AppTheme.dark
                : AppTheme.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: Builder(
                  builder: (context) => Column(
                    children: [
                      LifeUnitRow(
                        item: item,
                        catalog: catalog,
                        store: store,
                        epoch: 1,
                        scale: 1,
                        onOpen: () {},
                      ),
                      LifeTagStrip(
                        expandable: true,
                        children: lifeUnitBadges(
                          context,
                          item,
                          catalog,
                          detail: true,
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
        expect(find.text('校内服务'), findsOneWidget);
        expect(find.text('—'), findsNothing);
        expect(find.text('9.3分'), findsNothing);
        expect(tester.takeException(), isNull);
        if (Platform.environment['ME_LIFE_RENDER'] == '1' &&
            width == 402 &&
            scale == 1) {
          await tester.runAsync(() async {
            final image =
                await (tester.renderObject(find.byKey(boundary))
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/me-life-wave2').create(recursive: true);
            await File(
              'build/me-life-wave2/unit.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      });
    }
  }
}
