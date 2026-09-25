import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_adaptive_modal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sheet surface covers bottom safe area while content avoids it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () {
                showBnbuAdaptiveModal<void>(
                  context: context,
                  bottomSheetBackgroundColor: Colors.transparent,
                  builder: (_, presentation) => BnbuModalFrame(
                    presentation: presentation,
                    title: 'Choice',
                    child: const SizedBox(
                      key: ValueKey('sheet-safe-content'),
                      height: 160,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final surface = find
        .descendant(
          of: find.byType(BnbuModalFrame),
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getRect(surface).bottom, closeTo(844, .1));
    expect(tester.widget<Material>(surface).color, isNot(Colors.transparent));
    expect(
      tester.getRect(find.byKey(const ValueKey('sheet-safe-content'))).bottom,
      lessThanOrEqualTo(810),
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('adaptive modal keeps a bottom sheet below 700 px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(699, 900);
    addTearDown(tester.view.reset);
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const ValueKey('open-adaptive-modal'),
                onPressed: () async {
                  result = await showBnbuAdaptiveModal<String>(
                    context: context,
                    dialogMaxWidth: 480,
                    dialogMaxHeight: 320,
                    semanticLabel: '测试弹窗',
                    contentKey: const ValueKey('test-adaptive-modal'),
                    builder: (modalContext, presentation) => SizedBox(
                      key: const ValueKey('test-adaptive-modal-content'),
                      height: 180,
                      child: Center(
                        child: FilledButton(
                          key: const ValueKey('close-adaptive-modal'),
                          onPressed: () => Navigator.of(modalContext).pop('完成'),
                          child: Text(presentation.name),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-adaptive-modal')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      findsNothing,
    );
    expect(find.text('bottomSheet'), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('test-adaptive-modal-content')))
          .bottom,
      closeTo(900, 0.1),
    );

    await tester.tap(find.byKey(const ValueKey('close-adaptive-modal')));
    await tester.pumpAndSettle();
    expect(result, '完成');
  });

  testWidgets('adaptive modal centers and bounds dialogs from 700 px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const ValueKey('open-adaptive-modal'),
                onPressed: () {
                  showBnbuAdaptiveModal<void>(
                    context: context,
                    dialogMaxWidth: 480,
                    dialogMaxHeight: 320,
                    semanticLabel: '测试弹窗',
                    contentKey: const ValueKey('test-adaptive-modal'),
                    builder: (_, presentation) => SizedBox(
                      height: 240,
                      child: Center(child: Text(presentation.name)),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-adaptive-modal')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('dialog'), findsOneWidget);
    final dialog = tester.getRect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
    );
    expect(dialog.width, lessThanOrEqualTo(480));
    expect(dialog.height, lessThanOrEqualTo(320));
    expect(dialog.center.dx, closeTo(350, 0.1));
    expect(dialog.center.dy, closeTo(450, 0.1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      findsNothing,
    );
  });

  testWidgets('adaptive modal keeps its desktop cap on a 1440 px window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () {
                  showBnbuAdaptiveModal<void>(
                    context: context,
                    dialogMaxWidth: 760,
                    dialogMaxHeight: 680,
                    builder: (_, _) => const SizedBox(height: 680),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
    );
    expect(dialog.width, closeTo(760, 0.1));
    expect(dialog.height, closeTo(680, 0.1));
    expect(dialog.center.dx, closeTo(720, 0.1));
    expect(dialog.center.dy, closeTo(500, 0.1));
  });

  testWidgets('modal frame keeps compact icon actions in the desktop header', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showBnbuAdaptiveModal<void>(
                context: context,
                dialogMaxWidth: 560,
                dialogMaxHeight: 420,
                builder: (modalContext, presentation) => BnbuModalFrame(
                  presentation: presentation,
                  title: '整理提示词',
                  icon: LucideIcons.slidersHorizontal300,
                  actions: [
                    IconButton(
                      tooltip: '恢复预设',
                      onPressed: () {},
                      icon: const Icon(LucideIcons.rotateCcw300),
                    ),
                  ],
                  child: const TextField(maxLines: 6),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('整理提示词'), findsOneWidget);
    expect(find.byTooltip('恢复预设'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'modal action keeps semantic surface contrast in ${brightness.name}',
      (tester) async {
        final tokens = AppTheme.monochromeTokens(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.monochrome(brightness),
            home: Scaffold(
              body: Center(
                child: BnbuModalActionButton(
                  tooltip: '保存',
                  onPressed: () {},
                  icon: LucideIcons.check300,
                ),
              ),
            ),
          ),
        );

        final button = tester.widget<IconButton>(find.byType(IconButton));
        expect(button.style?.backgroundColor?.resolve({}), tokens.surface);
        expect(button.style?.foregroundColor?.resolve({}), tokens.textPrimary);
        expect(button.style?.fixedSize?.resolve({}), const Size.square(40));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'adaptive modal stays operable in landscape with large text and reduced motion',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 500);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () {
                      showBnbuAdaptiveModal<void>(
                        context: context,
                        dialogMaxWidth: 760,
                        dialogMaxHeight: 680,
                        semanticLabel: '大字弹窗',
                        builder: (modalContext, _) => SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('可滚动的大字内容'),
                                IconButton(
                                  tooltip: '关闭',
                                  onPressed: () =>
                                      Navigator.of(modalContext).pop(),
                                  icon: const Icon(LucideIcons.x300),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      final dialog = tester.getRect(
        find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      );
      expect(dialog.left, greaterThanOrEqualTo(24));
      expect(dialog.top, greaterThanOrEqualTo(24));
      expect(dialog.right, lessThanOrEqualTo(876));
      expect(dialog.bottom, lessThanOrEqualTo(476));
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('adaptive modal closes the desktop focus loop', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    final openFocus = FocusNode();
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    addTearDown(() {
      openFocus.dispose();
      firstFocus.dispose();
      secondFocus.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                focusNode: openFocus,
                onPressed: () {
                  showBnbuAdaptiveModal<void>(
                    context: context,
                    dialogMaxWidth: 480,
                    dialogMaxHeight: 320,
                    builder: (modalContext, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          focusNode: firstFocus,
                          autofocus: true,
                          onPressed: () {},
                          child: const Text('第一项'),
                        ),
                        TextButton(
                          focusNode: secondFocus,
                          onPressed: () => Navigator.of(modalContext).pop(),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    openFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(firstFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(secondFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(firstFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(openFocus.hasFocus, isTrue);
  });
}
