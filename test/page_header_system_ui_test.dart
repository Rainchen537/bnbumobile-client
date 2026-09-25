import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:bnbu_me/widgets/page_backdrop.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/pages/campus_directory_page.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/widgets/me_life_catalog.dart';
import 'me_life_catalog_test.dart' show CatalogFixture;

class EmptyDirectory extends Fake implements CampusDirectoryService {
  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async => [];
  @override
  void dispose() {}
}

class ScrollingDirectory extends EmptyDirectory {
  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async => [
    for (var i = 0; i < 25; i++)
      CampusDirectoryOrganization.fromJson({
        'id': 'college-$i',
        'category': 'college',
        'name_cn': '测试学院 $i',
        'name_en': 'Test College $i',
      }),
  ];
}

void main() {
  for (final page in ['directory', 'me-life']) {
    testWidgets('$page scrolls under the fixed translucent tail', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 600);
      addTearDown(tester.view.reset);
      final controller = AppSessionController();
      final store = CatalogFixture();
      addTearDown(controller.dispose);
      addTearDown(store.dispose);
      if (const bool.fromEnvironment('HEADER_PREVIEWS')) {
        await tester.runAsync(() async {
          final candidates = Directory(
            '/System/Library/AssetsV2/com_apple_MobileAsset_Font7',
          );
          if (candidates.existsSync()) {
            final font = candidates
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('/PingFang.ttc'))
                .first;
            await (FontLoader(
              'Roboto',
            )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
          }
          await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
                rootBundle.load(
                  'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
                ),
              ))
              .load();
        });
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: boundary,
            child: page == 'directory'
                ? CampusDirectoryPage(
                    controller: controller,
                    directoryService: ScrollingDirectory(),
                  )
                : MeLifeMobileCatalog(store: store, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fade = find.byKey(ValueKey('page-header-fade-$page'));
      final before = tester.getRect(fade);
      final list = find.byType(ListView).first;
      expect(
        tester.getRect(list).top,
        closeTo(before.bottom - PageHeaderOverlay.tailHeight, .1),
      );
      final first = page == 'directory'
          ? find.text('测试学院 0')
          : find.byKey(const ValueKey('life-unit-unit-0'));
      final initial = tester.getRect(first);
      expect(initial.top, greaterThanOrEqualTo(before.bottom));
      await tester.drag(list, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(tester.getRect(fade), before);
      expect(tester.getRect(first).top, lessThan(before.bottom));
      final mask = tester.widget<ShaderMask>(
        find.byKey(ValueKey('page-header-translucency-$page')),
      );
      expect(mask.blendMode, BlendMode.dstIn);
      if (const bool.fromEnvironment('HEADER_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/header-refinement/$page-scroll.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text(page == 'directory' ? '政务' : '美食商超'));
      await tester.pumpAndSettle();
      expect(first, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final brightness in Brightness.values) {
    for (final page in ['directory', 'me-life']) {
      testWidgets(
        '$page $brightness keeps the iOS status bar and restores root; fade includes categories',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(402, 874);
          tester.view.padding = const FakeViewPadding(top: 59);
          addTearDown(tester.view.reset);
          final nav = GlobalKey<NavigatorState>(),
              controller = AppSessionController(),
              store = CatalogFixture();
          addTearDown(controller.dispose);
          addTearDown(store.dispose);
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              theme: brightness == Brightness.light
                  ? AppTheme.light
                  : AppTheme.dark,
              builder: (context, child) => BnbuSystemUiScope(child: child!),
              home: const Scaffold(body: Text('root')),
            ),
          );
          await tester.pumpAndSettle();
          expect(SystemChrome.latestStyle!.statusBarBrightness, brightness);
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => page == 'directory'
                  ? CampusDirectoryPage(
                      controller: controller,
                      directoryService: EmptyDirectory(),
                    )
                  : MeLifeMobileCatalog(store: store, onOpen: (_) {}),
            ),
          );
          await tester.pumpAndSettle();
          expect(SystemChrome.latestStyle!.statusBarBrightness, brightness);
          expect(
            SystemChrome.latestStyle!.statusBarIconBrightness,
            brightness == Brightness.light ? Brightness.dark : Brightness.light,
          );
          final fade = find.byKey(ValueKey('page-header-fade-$page'));
          final category = find.text(page == 'directory' ? '政务' : '活动大全');
          expect(
            tester.getRect(fade).bottom,
            greaterThan(tester.getRect(category).bottom),
          );
          final gradient =
              (tester.widget<DecoratedBox>(fade).decoration as BoxDecoration)
                      .gradient!
                  as LinearGradient;
          expect(
            gradient.colors.last,
            brightness == Brightness.light
                ? BnbuThemeExtension.light.canvas
                : BnbuThemeExtension.dark.canvas,
          );
          nav.currentState!.pop();
          await tester.pumpAndSettle();
          expect(SystemChrome.latestStyle!.statusBarBrightness, brightness);
          // A deliberate opposite route must not leave its style behind on the homepage.
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => AnnotatedRegion<SystemUiOverlayStyle>(
                value: AppTheme.statusBarStyle(
                  brightness == Brightness.light
                      ? Brightness.dark
                      : Brightness.light,
                ),
                child: const Scaffold(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            SystemChrome.latestStyle!.statusBarBrightness,
            isNot(brightness),
          );
          nav.currentState!.pop();
          await tester.pumpAndSettle();
          expect(SystemChrome.latestStyle!.statusBarBrightness, brightness);
          await tester.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
