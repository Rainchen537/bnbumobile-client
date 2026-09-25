import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_adaptive.dart';
import 'package:bnbu_me/widgets/bnbu_menu.dart';
import 'package:bnbu_me/widgets/file_preview_frame.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    for (final width in [390.0, 900.0, 1440.0]) {
      testWidgets(
        'automatic back matches map glyph and painted size at $width on $platform',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              theme: AppTheme.light.copyWith(platform: platform),
              home: const Scaffold(body: Text('root')),
            ),
          );
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(appBar: FilePreviewAppBar(title: 'map')),
            ),
          );
          await tester.pumpAndSettle();
          final referenceIcon = find.byIcon(LucideIcons.chevronLeft300);
          final referenceRect = tester.getRect(referenceIcon);
          final referenceButton = tester.getRect(
            find
                .ancestor(of: referenceIcon, matching: find.byType(IconButton))
                .first,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: BnbuSecondaryAppBar(
                  bar: AppBar(title: const Text('secondary')),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final automaticIcon = find.descendant(
            of: find.byType(BackButtonIcon),
            matching: find.byType(Icon),
          );
          expect(
            tester.widget<Icon>(automaticIcon).icon,
            LucideIcons.chevronLeft300,
          );
          expect(tester.getRect(automaticIcon), referenceRect);
          expect(
            tester.getRect(
              find
                  .ancestor(
                    of: automaticIcon,
                    matching: find.byType(IconButton),
                  )
                  .first,
            ),
            referenceButton,
          );
          expect(referenceRect.size, const Size(24, 24));
          expect(referenceButton.height, greaterThanOrEqualTo(44));
          await tester.tap(automaticIcon);
          await tester.pumpAndSettle();
          expect(find.text('root'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('local foreground survives a dark application theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          appBar: BnbuSecondaryAppBar(
            bar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              title: const Text('Campus Card'),
              leading: const BackButton(),
              actions: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final title = tester.renderObject<RenderParagraph>(
      find.text('Campus Card'),
    );
    expect(title.text.style!.color, Colors.black);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.iconTheme!.color, Colors.black);
    expect(appBar.actionsIconTheme!.color, Colors.black);
  });

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('header keeps native targets and safe area at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.reset);
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              padding: const EdgeInsets.only(top: 47),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                appBar: BnbuSecondaryAppBar(
                  bar: AppBar(
                    title: const Text('课程文件 Course documents'),
                    actions: [
                      IconButton(
                        key: const ValueKey('header-action'),
                        onPressed: () => tapped = true,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                body: const SizedBox.expand(
                  key: ValueKey('reading-canvas'),
                  child: Text('正文', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('reading-canvas'))).dy,
        47 + 44,
      );
      final box = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('header-action')),
      );
      final paintedSize =
          box.localToGlobal(box.size.bottomRight(Offset.zero)) -
          box.localToGlobal(Offset.zero);
      expect(paintedSize.dx, greaterThanOrEqualTo(44));
      expect(paintedSize.dy, greaterThanOrEqualTo(44));
      final title = tester.renderObject<RenderParagraph>(
        find.text('课程文件 Course documents'),
      );
      expect(title.text.style!.fontSize, 17);
      await tester.tap(find.byKey(const ValueKey('header-action')));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('back and shared popup preserve route behavior', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.light,
        home: const Scaffold(body: Text('入口')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: BnbuSecondaryAppBar(
            bar: AppBar(
              title: const Text('文件预览'),
              actions: [
                BnbuMenuButton<String>(
                  itemBuilder: (_) => [
                    BnbuMenuItem(value: 'download', child: const Text('下载')),
                  ],
                ),
              ],
            ),
          ),
          body: const Text('文件内容'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BnbuMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('下载'), findsOneWidget);
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('入口'), findsOneWidget);
    expect(find.text('文件内容'), findsNothing);
  });
}
