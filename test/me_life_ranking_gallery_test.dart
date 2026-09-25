import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bnbu_me/widgets/me_life_catalog.dart';
import 'me_life_catalog_test.dart' show CatalogFixture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/services/campus_landmark_store.dart';
import 'package:bnbu_me/widgets/landmark_gallery_page.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'campus_landmarks_test.dart' show fixture, MemoryStore;

class PhotoStore extends MemoryStore {
  @override
  Future<File?> photo(LandmarkPhoto photo, {bool full = false}) async =>
      File('assets/me_life/header-campus.png');
}

void main() {
  testWidgets(
    'selected category is blue and mobile address uses detail map pin',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = CatalogFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MeLifeMobileCatalog(store: store, onOpen: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final selected = tester.widget<Text>(find.text('校园建筑'));
      expect(selected.style?.color, BnbuThemeExtension.light.brandBlue);
      expect(find.byIcon(LucideIcons.mapPin300), findsWidgets);
      await tester.tap(find.text('美食商超'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('美食商超')).style?.color,
        BnbuThemeExtension.light.brandBlue,
      );
      expect(
        tester.widget<Text>(find.text('校园建筑')).style?.color,
        BnbuThemeExtension.light.textPrimary,
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  test(
    'ranking refresh handles 304, invalid ids, stale version and failure',
    () async {
      final dir = await Directory.systemTemp.createTemp('me-ranking-test-');
      var phase = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/ranking')) {
          if (phase == 3) return http.Response('', 503);
          return http.Response(
            jsonEncode({
              'version': phase == 2 ? 0 : 1,
              'ids': phase == 1 ? ['coffee', 'coffee'] : ['coffee', 'lrc'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return phase == 0
            ? http.Response(
                jsonEncode(fixture()),
                200,
                headers: {'content-type': 'application/json'},
              )
            : http.Response('', 304);
      });
      final store = CampusLandmarkStore(
        client: client,
        directory: () async => dir,
        baseUrl: 'https://example.org',
      );
      await store.refresh();
      expect(store.rankedLandmarks.map((i) => i.id), ['coffee', 'lrc']);
      for (phase = 1; phase <= 3; phase++) {
        await store.refresh();
        expect(store.rankedLandmarks.map((i) => i.id), ['coffee', 'lrc']);
        expect(store.failed, isFalse);
      }
      expect(store.presentationEpoch, 4);
      store.dispose();
      await dir.delete(recursive: true);
    },
  );
  test('photo sources preserve legacy and reject unsafe external links', () {
    final base = {'id': 'a' * 64, 'focus_x': .5, 'focus_y': .5};
    expect(LandmarkPhoto.fromJson(base).source, '');
    expect(
      () => LandmarkPhoto.fromJson({
        ...base,
        'source_url': 'javascript:alert(1)',
      }),
      throwsFormatException,
    );
  });
  for (final size in [
    const Size(390, 844),
    const Size(900, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('gallery uses entire screen and changes attribution at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = PhotoStore();
      final photos = [
        for (final x in ['a', 'b'])
          LandmarkPhoto.fromJson({
            'id': x * 64,
            'focus_x': .5,
            'focus_y': .5,
            'source': 'Source $x',
            'author': 'Author $x',
          }),
      ];
      final capture = GlobalKey();
      if (Platform.environment['ME_LIFE_RENDER'] == '1') {
        await tester.runAsync(() async {
          final loader = FontLoader('PingFang SC')
            ..addFont(
              File(
                Platform.environment['ME_LIFE_FONT']!,
              ).readAsBytes().then((b) => ByteData.sublistView(b)),
            );
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          final file = File('assets/me_life/header-campus.png');
          final codec = await ui.instantiateImageCodec(
            await file.readAsBytes(),
          );
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
      }
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: (size.width == 900 ? AppTheme.dark : AppTheme.light).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontFamily: 'PingFang SC'),
              ),
            ),
            textTheme: AppTheme.light.textTheme.apply(
              fontFamily: 'PingFang SC',
            ),
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(size.width == 900 ? 2 : 1),
              disableAnimations: true,
              padding: const EdgeInsets.only(top: 59, bottom: 34),
            ),
            child: RepaintBoundary(
              key: capture,
              child: LandmarkGalleryPage(
                store: store,
                photos: photos,
                title: '测试图集',
                defaultLanguage: 'zh-Hans',
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      if (Platform.environment['ME_LIFE_RENDER'] == '1' && size.width == 390) {
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/me-life-ranking/gallery-phone.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final canvas = find.byKey(const ValueKey('landmark-fullscreen-canvas'));
      expect(tester.getRect(canvas), Offset.zero & size);
      final images = find.descendant(of: canvas, matching: find.byType(Image));
      if (images.evaluate().isNotEmpty) {
        expect(
          tester.getCenter(images.first),
          Offset(size.width / 2, size.height / 2),
        );
      }
      expect(find.text('Source a · Author a'), findsOneWidget);
      if (size.width >= 700) {
        await tester.tap(find.byTooltip('下一张'));
      } else {
        await tester.drag(canvas, Offset(-size.width * .8, 0));
      }
      await tester.pumpAndSettle();
      expect(find.text('Source b · Author b'), findsOneWidget);
      expect(find.text('Source a · Author a'), findsNothing);
      expect(tester.getCenter(canvas), Offset(size.width / 2, size.height / 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
}
