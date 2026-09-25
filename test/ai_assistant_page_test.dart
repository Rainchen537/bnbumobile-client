import 'package:bnbu_me/widgets/bnbu_menu.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/assistant_resource.dart';
import 'package:bnbu_me/pages/ai_assistant_page.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/app_navigation_coordinator.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/assistant_location_service.dart';
import 'package:bnbu_me/services/assistant_resource_library_store.dart';
import 'package:bnbu_me/state/ai_assistant_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/assistant_resource_library_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/assistant_context_scope.dart';
import 'package:bnbu_me/widgets/small_u_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单按钮原位切换；等待期间只推进常规帧。
Future<void> _expectThinkingMode(
  WidgetTester tester,
  AssistantThinkingMode mode,
) async {
  await tester.pump();
  final control = find.byKey(const ValueKey('assistant-thinking-mode-control'));
  expect(tester.getSemantics(control).value, mode.label);
  expect(
    find.descendant(of: control, matching: find.byType(IconButton)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: control,
      matching: find.byIcon(
        mode == AssistantThinkingMode.high
            ? LucideIcons.brain300
            : LucideIcons.messageCircle300,
      ),
    ),
    findsOneWidget,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'cached remote history stays in sidebar until explicitly selected',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final now = DateTime.utc(2026, 9, 10);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        coordinator.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          openFixtureHistory: false,
          historyStore: _MemoryHistoryStore([
            AssistantConversation(
              id: 'remote-sidebar',
              title: 'Remote title',
              createdAt: now,
              updatedAt: now,
              messages: [
                AssistantStoredMessage(
                  role: 'user',
                  content: 'Remote message body',
                  createdAt: now,
                ),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remote title'), findsOneWidget);
      expect(find.text('Remote message body'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('assistant-conversation-remote-sidebar')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remote message body'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('history ink stays clipped below fixed shortcuts at $width', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = width < 700
          ? TargetPlatform.iOS
          : TargetPlatform.macOS;
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final boundaryKey = GlobalKey();
      final now = DateTime.utc(2026, 9, 9);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        coordinator.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: _TestHost(
            controller: controller,
            coordinator: coordinator,
            service: _FakeAssistantService(enabled: true),
            historyStore: _MemoryHistoryStore([
              for (var i = 0; i < 50; i++)
                AssistantConversation(
                  id: 'clip-$i',
                  title: 'Conversation $i',
                  createdAt: now.subtract(Duration(minutes: i)),
                  updatedAt: now.subtract(Duration(minutes: i)),
                  messages: [
                    AssistantStoredMessage(
                      role: 'user',
                      content: 'Question',
                      createdAt: now,
                    ),
                  ],
                ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 700) {
        await tester.dragFrom(const Offset(40, 180), const Offset(180, 0));
        await tester.pumpAndSettle();
      }
      final first = find.byKey(const ValueKey('assistant-conversation-clip-0'));
      await tester.tap(first);
      await tester.pumpAndSettle();
      if (width < 700) {
        await tester.dragFrom(const Offset(40, 180), const Offset(180, 0));
        await tester.pumpAndSettle();
      }
      final list = find.ancestor(of: first, matching: find.byType(ListView));
      final viewport = tester.getRect(list);
      Future<List<int>> fixedPixels() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        final result = <int>[];
        for (var y = 0; y < viewport.top.floor(); y++) {
          result.addAll(
            bytes.sublist(
              (y * image.width + viewport.left.ceil()) * 4,
              (y * image.width + viewport.right.floor()) * 4,
            ),
          );
        }
        image.dispose();
        return result;
      }

      final before = await tester.runAsync(fixedPixels);
      final gesture = await tester.startGesture(tester.getCenter(list));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(first).top, lessThan(viewport.top));
      expect(
        listEquals(await tester.runAsync(fixedPixels), before),
        isTrue,
        reason: 'selected ink must never paint over fixed shortcuts',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    testWidgets(
      'only the latest reply owns inline branches at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        final session = _AssistantController();
        final coordinator = AssistantContextCoordinator();
        final now = DateTime.utc(2026, 9, 9);
        final history = _MemoryHistoryStore([
          for (var branch = 0; branch < 2; branch++)
            AssistantConversation(
              id: 'branch-$branch',
              branchGroupId: 'family',
              title: 'Question',
              createdAt: now.add(Duration(seconds: branch)),
              updatedAt: now.add(Duration(seconds: branch)),
              messages: [
                AssistantStoredMessage(
                  role: 'user',
                  content: 'Question one',
                  createdAt: now,
                ),
                AssistantStoredMessage(
                  role: 'assistant',
                  content: 'Earlier reply',
                  createdAt: now,
                ),
                AssistantStoredMessage(
                  role: 'user',
                  content: 'Question two',
                  createdAt: now,
                ),
                AssistantStoredMessage(
                  role: 'assistant',
                  content: 'Latest reply $branch',
                  createdAt: now,
                ),
              ],
            ),
        ]);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          session.dispose();
          coordinator.dispose();
        });
        await tester.pumpWidget(
          _TestHost(
            controller: session,
            coordinator: coordinator,
            service: _FakeAssistantService(enabled: true),
            historyStore: history,
          ),
        );
        await tester.pumpAndSettle();
        final switcher = find.byKey(
          const ValueKey('assistant-branch-position'),
        );
        expect(switcher, findsOneWidget);
        final rows = find.byKey(const ValueKey('assistant-response-actions'));
        expect(rows, findsNWidgets(2));
        expect(
          find.descendant(of: rows.first, matching: switcher),
          findsNothing,
        );
        expect(
          find.descendant(of: rows.last, matching: switcher),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: switcher, matching: find.byType(AppBar)),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: switcher,
            matching: find.byKey(const ValueKey('assistant-workspace-header')),
          ),
          findsNothing,
        );
        final copy = find.byKey(const ValueKey('assistant-response-copy')).last;
        final icon = find.descendant(
          of: copy,
          matching: find.byIcon(LucideIcons.copy300),
        );
        expect(
          tester.getTopLeft(icon).dx,
          closeTo(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('assistant-response-content')).last,
                )
                .dx,
            .1,
          ),
        );
        expect(tester.getSize(copy).width, greaterThanOrEqualTo(32));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }),
    );
  }

  testWidgets(
    'phone rightward swipe opens history without exiting and back remains explicit',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.reset();
        controller.dispose();
        coordinator.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          historyStore: _MemoryHistoryStore(),
          openFromLauncher: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-assistant-test-route')));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.panelLeft300), findsNothing);
      expect(find.byType(DrawerButton), findsNothing);
      final route = ModalRoute.of(
        tester.element(find.byType(AiAssistantPage)),
      )!;
      expect(route.popGestureEnabled, isFalse);
      await tester.dragFrom(const Offset(290, 180), const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('assistant-history-swipe')),
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScaffoldState>(
              find
                  .descendant(
                    of: find.byType(AiAssistantPage),
                    matching: find.byType(Scaffold),
                  )
                  .first,
            )
            .isDrawerOpen,
        isTrue,
      );
      await tester.tapAt(const Offset(370, 300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assistant-compact-back')));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'starter prompts follow the locale without sending or rewriting drafts',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService(enabled: true);
      final historyStore = _MemoryHistoryStore();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        coordinator.dispose();
      });
      Future<void> showLocale(Locale locale) async {
        await tester.pumpWidget(
          _TestHost(
            controller: controller,
            coordinator: coordinator,
            service: service,
            historyStore: historyStore,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
      }

      await showLocale(const Locale('en'));
      const englishPrompts = [
        'Plan my classes and deadlines for today',
        'Help me write an email about a course',
        'Check recent iSpace assignments',
        'Where am I now?',
      ];
      for (final prompt in englishPrompts) {
        expect(find.widgetWithText(ActionChip, prompt), findsOneWidget);
        await tester.tap(find.widgetWithText(ActionChip, prompt));
        await tester.pump();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller!
              .text,
          prompt,
        );
        expect(service.messages, isEmpty);
      }
      expect(tester.takeException(), isNull);

      await showLocale(const Locale('zh', 'TW'));
      final input = find.byType(TextField).last;
      expect(
        tester.widget<TextField>(input).controller!.text,
        englishPrompts.last,
      );
      const traditionalPrompt = '幫我寫一封課程郵件';
      expect(
        find.widgetWithText(ActionChip, traditionalPrompt),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ActionChip, traditionalPrompt));
      await tester.pump();
      expect(
        tester.widget<TextField>(input).controller!.text,
        traditionalPrompt,
      );
      expect(service.messages, isEmpty);

      await tester.tap(find.byKey(const ValueKey('assistant-send-button')));
      await tester.pumpAndSettle();
      expect(service.messages, [traditionalPrompt]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assistant opens as a full page and enables without extra consent',
    (tester) async {
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService(enabled: false);
      final historyStore = _MemoryHistoryStore();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        coordinator.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: service,
          historyStore: historyStore,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(find.byType(SmallULogo), findsWidgets);
      final appBar = find.byType(AppBar);
      expect(
        find.descendant(of: appBar, matching: find.byType(SmallULogo)),
        findsNothing,
      );
      expect(
        find.descendant(of: appBar, matching: find.text('小U')),
        findsOneWidget,
      );
      expect(find.text('今天想做什么？'), findsOneWidget);
      expect(find.text('同意并启用小U'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(service.enableCalls, 1);
      expect(service.enabled, isTrue);
    },
  );

  testWidgets('desktop assistant has a persistent pane and explicit exit', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
      coordinator.dispose();
    });
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
        openFromLauncher: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-assistant-test-route')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('assistant-desktop-history-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assistant-desktop-back')),
      findsOneWidget,
    );
    expect(
      find.byType(SmallULogo),
      findsOneWidget,
      reason: '侧栏品牌使用文字，正文空状态保留标志',
    );

    await tester.tap(find.byKey(const ValueKey('assistant-desktop-back')));
    await tester.pumpAndSettle();
    expect(find.byType(AiAssistantPage), findsNothing);
  });

  testWidgets('tablet landscape keeps assistant history visible', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
      coordinator.dispose();
    });
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('assistant-desktop-history-pane')),
      findsOneWidget,
    );
    expect(find.byType(DrawerButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop conversation actions use a hover overflow menu', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final conversation = AssistantConversation(
      id: 'hover-menu',
      title: '课程安排',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      messages: [
        AssistantStoredMessage(
          role: 'user',
          content: '课程安排',
          createdAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      controller.dispose();
      coordinator.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore([conversation]),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(
      const ValueKey('assistant-conversation-hover-menu'),
    );
    final opacity = find.descendant(
      of: tile,
      matching: find.byType(AnimatedOpacity),
    );
    final menuFinder = find.byKey(
      const ValueKey('assistant-conversation-menu-hover-menu'),
    );
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
    expect(find.text('停用小U'), findsNothing);
    expect((tester.widget<BnbuMenuButton>(menuFinder).icon! as Icon).size, 18);
    final listTile = tester.widget<ListTile>(
      find.descendant(of: tile, matching: find.byType(ListTile)),
    );
    expect(listTile.contentPadding, const EdgeInsets.only(left: 16, right: 8));
    expect(listTile.selected, isTrue);
    expect(listTile.selectedTileColor, isNotNull);
    expect(listTile.shape, isA<RoundedRectangleBorder>());
    expect(tester.getSize(tile).height, 28);
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('assistant-conversation-title-hover-menu')),
    );
    expect(title.style?.fontSize, closeTo(13.6, 0.01));
    expect(title.style?.letterSpacing, 0);
    expect(title.style?.fontWeight, FontWeight.w600);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tile));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);

    await tester.tap(menuFinder);
    await tester.pumpAndSettle();
    expect(find.text('删除对话'), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2300), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile conversation overflow menu stays visible', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final conversation = AssistantConversation(
      id: 'mobile-menu',
      title: '邮件',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      messages: [
        AssistantStoredMessage(
          role: 'user',
          content: '邮件',
          createdAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      controller.dispose();
      coordinator.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore([conversation]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('assistant-history-swipe')),
      const Offset(180, 0),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(
      const ValueKey('assistant-conversation-mobile-menu'),
    );
    final opacity = find.descendant(
      of: tile,
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    expect(tester.getSize(tile).height, 44);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('assistant-resource-heading')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      find.byKey(const ValueKey('assistant-conversation-menu-mobile-menu')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('sidebar shortcuts share the conversation list outer rhythm', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final conversation = AssistantConversation(
      id: 'sidebar-rhythm',
      title: '课程安排',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      messages: [
        AssistantStoredMessage(
          role: 'user',
          content: '课程安排',
          createdAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      controller.dispose();
      coordinator.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore([conversation]),
      ),
    );
    await tester.pumpAndSettle();

    final conversationRect = tester.getRect(
      find.byKey(const ValueKey('assistant-conversation-sidebar-rhythm')),
    );
    // 资源库和记忆是所有桌面侧栏都会显示的紧凑快捷行；学业模式
    // 仅在支持的桌面平台呈现，不能作为跨平台行距断言的前提。
    for (final key in <ValueKey<String>>[
      const ValueKey('assistant-resource-heading'),
      const ValueKey('assistant-memory-heading'),
    ]) {
      final shortcut = find.byKey(key);
      expect(shortcut, findsOneWidget);
      expect(tester.getRect(shortcut).left, conversationRect.left);
      expect(tester.getSize(shortcut).height, conversationRect.height);
    }
    final resourceRect = tester.getRect(
      find.byKey(const ValueKey('assistant-resource-heading')),
    );
    final memoryRect = tester.getRect(
      find.byKey(const ValueKey('assistant-memory-heading')),
    );
    expect(memoryRect.top, resourceRect.bottom);
    final brand = tester.getRect(
      find.byKey(const ValueKey('assistant-sidebar-brand')),
    );
    final newChat = tester.getRect(
      find.byKey(const ValueKey('assistant-new-conversation')),
    );
    expect(brand.bottom, lessThan(newChat.top));
    expect(newChat.bottom, lessThan(resourceRect.top));
    expect(
      find.byKey(const ValueKey('assistant-new-conversation')),
      findsOneWidget,
    );
    final composer = find.byKey(const ValueKey('assistant-composer-input'));
    // “问问小U”区域在不改变文字大小的前提下提高约 70%。
    expect(tester.getSize(composer).height, greaterThanOrEqualTo(54));
    expect(tester.widget<TextField>(composer).style?.fontSize, 14);
    final add = tester.widget<IconButton>(
      find.byKey(const ValueKey('assistant-add-content')),
    );
    expect(add.style?.backgroundColor?.resolve({}), Colors.transparent);
    expect(
      find.byKey(const ValueKey('assistant-study-mode-heading')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('smart thinking button toggles only Low and High', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      coordinator.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();

    // 二态图标常驻输入区，不需要先打开任何弹层。
    final control = find.byKey(
      const ValueKey('assistant-thinking-mode-control'),
    );
    expect(control, findsOneWidget);
    expect(find.byType(MenuAnchor), findsNothing);
    expect(
      find.byKey(const ValueKey('assistant-thinking-mode-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assistant-thinking-mode-toggle')),
      findsOneWidget,
    );
    expect(find.text('Medium'), findsNothing);
    expect(find.textContaining('智能 ·'), findsNothing);
    expect(find.text('12 轮'), findsNothing);
    expect(find.text('32 轮'), findsNothing);
    expect(
      find.descendant(of: control, matching: find.byIcon(LucideIcons.zap300)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: control,
        matching: find.byIcon(LucideIcons.chevronDown300),
      ),
      findsNothing,
    );

    expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
    final initialSemantics = tester.getSemantics(control);
    expect(initialSemantics.label, contains('选择思考强度'));
    expect(find.byTooltip('Low，简单问题'), findsOneWidget);
    expect(find.byTooltip('High，复杂问题'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('assistant-thinking-mode-toggle')),
    );
    await tester.pump();
    await _expectThinkingMode(tester, AssistantThinkingMode.high);
    await tester.tap(
      find.byKey(const ValueKey('assistant-thinking-mode-toggle')),
    );
    await tester.pump();
    await _expectThinkingMode(tester, AssistantThinkingMode.low);
    semantics.dispose();
  });

  testWidgets('memory sync state sits beside the title without false success', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      controller.dispose();
      coordinator.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('assistant-memory-heading')));
    await tester.pumpAndSettle();

    final modal = find.byKey(const ValueKey('assistant-memory-modal'));
    final badge = find.byKey(const ValueKey('assistant-memory-sync-badge'));
    final title = find.descendant(of: modal, matching: find.text('记忆'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('仅本机')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: modal, matching: find.text('已同步')),
      findsNothing,
    );
    expect(
      tester.getRect(badge).left,
      greaterThan(tester.getRect(title).right),
    );
    expect(
      tester.getRect(badge).right,
      lessThan(tester.getRect(find.byTooltip('添加记忆')).left),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('composer switches and persists the thinking mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final service = _FakeAssistantService(enabled: true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      coordinator.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('assistant-composer-surface')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const ValueKey('assistant-composer-surface'))),
      isA<DecoratedBox>(),
    );
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('assistant-composer-input')),
    );
    expect(input.decoration?.filled, isFalse);
    expect(input.textAlignVertical, TextAlignVertical.center);
    expect(
      tester.getSize(find.byKey(const ValueKey('assistant-send-button'))),
      const Size.square(44),
    );
    final visibleSend = tester.getSize(
      find.byKey(const ValueKey('assistant-send-button-visible')),
    );
    expect(visibleSend.width, closeTo(36.96, 0.001));
    expect(visibleSend.height, closeTo(36.96, 0.001));
    final unfocusedDecoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('assistant-composer-surface')),
                )
                .decoration
            as BoxDecoration;
    await tester.tap(find.byKey(const ValueKey('assistant-composer-input')));
    await tester.pump();
    final focusedDecoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('assistant-composer-surface')),
                )
                .decoration
            as BoxDecoration;
    expect(focusedDecoration.border, isNot(unfocusedDecoration.border));
    expect(find.text('12 轮'), findsNothing);
    expect(find.text('32 轮'), findsNothing);
    await _expectThinkingMode(tester, AssistantThinkingMode.low);
    expect(find.text('Medium'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('assistant-thinking-mode-toggle')),
    );
    await tester.pumpAndSettle();

    await _expectThinkingMode(tester, AssistantThinkingMode.high);
    final preferences = await SharedPreferences.getInstance();
    final modeKey = preferences.getKeys().singleWhere(
      (key) => key.startsWith('bnbu.ai_assistant.thinking_mode.v1.'),
    );
    expect(preferences.getString(modeKey), 'high');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile tap outside composer releases the input focus', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
      coordinator.dispose();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('assistant-composer-input'));
    await tester.tap(input);
    await tester.pump();
    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isTrue);

    await tester.tap(find.text('今天想做什么？'));
    await tester.pump();

    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isFalse);
  });

  testWidgets('assistant automatically selects the minimum mail context', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final registration = coordinator.register(
      AssistantContextContribution(
        currentPage: () =>
            const AssistantCurrentPageContext(pageType: 'mail', title: '邮箱'),
        mailSummaries: () => [
          AssistantMailSummaryContext(
            senderName: 'Teacher',
            senderEmail: 'teacher@bnbu.edu.cn',
            subject: 'Course update',
            receivedAt: DateTime.utc(2026, 7, 21),
            preview: 'Please read the update.',
          ),
        ],
      ),
    );
    final service = _FakeAssistantService(enabled: true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      registration.dispose();
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '整理一下最近的邮件');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(
      service.lastContext?.sources,
      contains(AssistantContextSource.mailSummaries),
    );
    expect(service.lastContext?.mailSummaries, hasLength(1));
    expect(find.text('已整理。'), findsOneWidget);
  });

  testWidgets(
    'assistant page overrides and then releases root page semantics',
    (tester) async {
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final rootRegistration = coordinator.register(
        AssistantContextContribution(
          currentPage: () =>
              const AssistantCurrentPageContext(pageType: 'home', title: '首页'),
        ),
      );
      final service = _FakeAssistantService(enabled: true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        rootRegistration.dispose();
        coordinator.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: service,
          historyStore: _MemoryHistoryStore(),
        ),
      );
      await tester.pumpAndSettle();

      final assistantPage = coordinator.snapshot().currentPage;
      expect(assistantPage?.pageType, 'ai_assistant');
      expect(assistantPage?.title, '小U');
      expect(assistantPage?.summary, contains('对话历史'));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(coordinator.snapshot().currentPage?.pageType, 'home');
    },
  );

  testWidgets('composer attaches an image and sends it without nested controls', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final service = _FakeAssistantService(enabled: true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
        attachmentPicker: () async => [
          AssistantInputAttachment(
            name: 'campus.png',
            mimeType: 'image/png',
            bytes: base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('添加内容'), findsOneWidget);
    await tester.tap(find.byTooltip('添加内容'));
    await tester.pumpAndSettle();
    expect(find.text('资源库'), findsOneWidget);
    expect(find.text('相机'), findsOneWidget);
    expect(find.text('照片'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('assistant-attachment-source-files')),
    );
    await tester.pumpAndSettle();
    expect(find.text('campus.png'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assistant-attachment-0')),
      findsOneWidget,
    );
    expect(find.text('图片 · 68 B'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);

    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.lastAttachments, hasLength(1));
    expect(service.lastAttachments.single.name, 'campus.png');
    expect(find.textContaining('附件：campus.png'), findsNothing);
    expect(
      find.byKey(const ValueKey('assistant-user-attachment-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assistant-user-image-thumbnail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assistant-user-text-bubble')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('assistant-user-copy')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-user-edit')), findsNothing);
  });

  testWidgets(
    'user text and structured attachments render as separate right-aligned rows',
    (tester) async {
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final now = DateTime.utc(2026, 9, 8, 8);
      final runtimeImage = AssistantInputAttachment(
        name: 'campus.png',
        mimeType: 'image/png',
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      final history = _MemoryHistoryStore([
        AssistantConversation(
          id: 'attachments',
          title: '附件展示',
          createdAt: now,
          updatedAt: now,
          messages: [
            AssistantStoredMessage(
              role: 'user',
              content: '请整理这些内容',
              createdAt: now,
              attachmentReferences: const [
                AssistantAttachmentReference(
                  kind: AssistantAttachmentReferenceKind.file,
                  name: 'syllabus.pdf',
                ),
                AssistantAttachmentReference(
                  kind: AssistantAttachmentReferenceKind.image,
                  name: 'campus.png',
                ),
              ],
              runtimeAttachments: [runtimeImage],
              mailReferences: [
                AssistantMailReference.message(
                  folder: 'inbox',
                  uid: 9,
                  mailboxUidValidity: 12,
                  sender: 'teacher@bnbu.edu.cn',
                  subject: 'Week 2 update',
                  receivedAt: now,
                ),
              ],
            ),
          ],
        ),
      ]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        coordinator.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          historyStore: history,
        ),
      );
      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('assistant-user-text-bubble'));
      final file = find.byKey(const ValueKey('assistant-user-attachment-0'));
      final image = find.byKey(const ValueKey('assistant-user-attachment-1'));
      final mail = find.byKey(
        const ValueKey('assistant-user-mail-attachment-0'),
      );
      final copy = find.byKey(const ValueKey('assistant-user-copy'));
      expect(find.text('请整理这些内容'), findsOneWidget);
      expect(find.text('syllabus.pdf'), findsOneWidget);
      expect(find.text('campus.png'), findsOneWidget);
      expect(find.text('Week 2 update'), findsOneWidget);
      expect(
        tester.getTopLeft(file).dy,
        greaterThan(tester.getBottomLeft(bubble).dy),
      );
      expect(
        tester.getTopLeft(image).dy,
        greaterThan(tester.getTopLeft(file).dy),
      );
      expect(
        tester.getTopLeft(mail).dy,
        greaterThan(tester.getTopLeft(image).dy),
      );
      expect(
        tester.getTopLeft(copy).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(mail).dy),
      );
      expect(
        tester.getRect(file).right,
        closeTo(tester.getRect(image).right, 0.1),
      );
      expect(
        tester.getRect(image).right,
        closeTo(tester.getRect(mail).right, 0.1),
      );
      expect(
        find.byKey(const ValueKey('assistant-user-image-thumbnail')),
        findsOneWidget,
      );
    },
  );

  testWidgets('assistant keeps attachment choices as a compact bottom sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加内容'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      findsNothing,
    );
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey('assistant-attachment-source-modal')),
          )
          .bottom,
      closeTo(844, 0.1),
    );
  });

  testWidgets('assistant uses bounded dialogs for every wide modal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    final controller = _LoggedInAssistantController();
    final coordinator = AssistantContextCoordinator();
    final resource = AssistantResourceItem(
      id: 'resource-wide',
      fileName: 'Wide resource.zip',
      storedName: 'resource-wide.zip',
      filePath: '/tmp/wide-resource.zip',
      mimeType: 'application/zip',
      byteCount: 2048,
      createdAt: DateTime.utc(2026, 7, 30),
      kind: AssistantResourceKind.courseArchive,
      sourceTitle: 'Wide Course',
      summary: 'Wide summary',
    );
    final resourceLibrary = AssistantResourceLibraryController(
      sessionController: controller,
      store: _MemoryResourceLibraryStore([resource]),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      resourceLibrary.dispose();
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
        resourceLibrary: resourceLibrary,
        theme: AppTheme.dark,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加内容'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('assistant-attachment-source-modal')),
      findsOneWidget,
    );
    expect(find.byTooltip('关闭'), findsOneWidget);
    var dialogRect = tester.getRect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
    );
    expect(dialogRect.width, lessThanOrEqualTo(520));
    expect(dialogRect.center.dx, closeTo(450, 0.1));
    expect(dialogRect.center.dy, closeTo(450, 0.1));

    await tester.tap(
      find.byKey(const ValueKey('assistant-attachment-source-resource')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('assistant-resource-library-modal')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
    dialogRect = tester.getRect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
    );
    expect(dialogRect.width, lessThanOrEqualTo(760));
    expect(dialogRect.height, lessThanOrEqualTo(680));
    expect(dialogRect.center.dx, closeTo(450, 0.1));
    expect(dialogRect.center.dy, closeTo(450, 0.1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('assistant-resource-library-modal')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('assistant-thinking-mode-toggle')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    // 思考强度是输入区内联控件，任何宽度都不得再借用弹层。
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      findsNothing,
    );
    final controlRect = tester.getRect(
      find.byKey(const ValueKey('assistant-thinking-mode-control')),
    );
    // 测试字体每个字形都是等宽方块，会放大标签宽度；这里只保证控件仍是
    // 输入区里的一个小部件，而不是占满整行。
    expect(controlRect.width, lessThanOrEqualTo(320));
    expect(controlRect.bottom, lessThan(900));
    expect(
      controlRect.right,
      lessThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey('assistant-composer-surface')))
            .right,
      ),
    );
  });

  testWidgets('dark assistant send arrow contrasts with its light button', (
    tester,
  ) async {
    final controller = _LoggedInAssistantController();
    final coordinator = AssistantContextCoordinator();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore(),
        theme: AppTheme.dark,
      ),
    );
    await tester.pumpAndSettle();

    final visible = tester.widget<Container>(
      find.byKey(const ValueKey('assistant-send-button-visible')),
    );
    final decoration = visible.decoration! as BoxDecoration;
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('assistant-send-button-visible')),
        matching: find.byIcon(LucideIcons.arrowUp300),
      ),
    );
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, isNotNull);
    expect(icon.color, isNot(decoration.color));
  });

  testWidgets(
    'pointer composer keeps its hit target around a 20 percent enlarged send circle',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final controller = _LoggedInAssistantController();
      final coordinator = AssistantContextCoordinator();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        coordinator.dispose();
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          historyStore: _MemoryHistoryStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const ValueKey('assistant-send-button'))),
        const Size.square(32),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('assistant-send-button-visible')),
        ),
        predicate<Size>(
          (size) =>
              (size.width - 26.88).abs() < 0.001 &&
              (size.height - 26.88).abs() < 0.001,
        ),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'resource library stays above conversations and adds a reference',
    (tester) async {
      final controller = _LoggedInAssistantController();
      final coordinator = AssistantContextCoordinator();
      final resource = AssistantResourceItem(
        id: 'resource-1',
        fileName: 'OOP 课件.zip',
        storedName: 'resource-1_OOP 课件.zip',
        filePath: '/tmp/OOP 课件.zip',
        mimeType: 'application/zip',
        byteCount: 4096,
        createdAt: DateTime.utc(2026, 7, 24),
        kind: AssistantResourceKind.courseArchive,
        sourceTitle: 'Object-Oriented Programming',
        summary: '包含 12 个演示文稿与 PDF 课件。',
      );
      final resourceLibrary = AssistantResourceLibraryController(
        sessionController: controller,
        store: _MemoryResourceLibraryStore([resource]),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        resourceLibrary.dispose();
        coordinator.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          historyStore: _MemoryHistoryStore(),
          resourceLibrary: resourceLibrary,
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('assistant-history-swipe')),
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();

      final resourceHeading = tester.getTopLeft(find.text('资源库').first).dy;
      final conversationHeading = tester.getTopLeft(find.text('对话')).dy;
      expect(resourceHeading, lessThan(conversationHeading));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('assistant-resource-heading')),
          matching: find.byIcon(LucideIcons.archive300),
        ),
        findsOneWidget,
      );
      expect(find.text('查看全部'), findsNothing);
      final headingTile = tester.widget<ListTile>(
        find.byKey(const ValueKey('assistant-resource-heading')),
      );
      expect(headingTile.onTap, isNotNull);
      expect(find.text('OOP 课件.zip'), findsOneWidget);

      await tester.tap(find.byTooltip('添加 OOP 课件.zip'));
      await tester.pumpAndSettle();

      expect(find.text('OOP 课件.zip'), findsOneWidget);
      expect(find.textContaining('资源库引用'), findsOneWidget);
    },
  );

  testWidgets(
    'mobile history closes before presenting the resource library sheet',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      final controller = _LoggedInAssistantController();
      final coordinator = AssistantContextCoordinator();
      final resourceLibrary = AssistantResourceLibraryController(
        sessionController: controller,
        store: _MemoryResourceLibraryStore(const []),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.reset();
        resourceLibrary.dispose();
        coordinator.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          historyStore: _MemoryHistoryStore(),
          resourceLibrary: resourceLibrary,
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('assistant-history-swipe')),
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assistant-resource-heading')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('assistant-resource-heading')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('assistant-resource-heading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('assistant-resource-library-modal')),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('资源库'), findsOneWidget);
    },
  );

  testWidgets(
    'assistant reads location only for an explicit location request',
    (tester) async {
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService(
        enabled: true,
        contextSources: const {'current_page', 'current_location'},
      );
      final locationService = _FakeLocationService();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        coordinator.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: service,
          historyStore: _MemoryHistoryStore(),
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '我现在在哪里？');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(locationService.calls, 1);
      expect(service.lastContext?.currentLocation?.latitude, 22.35);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.currentLocation),
      );
    },
  );

  testWidgets(
    'assistant choices appear above composer and submit a safe turn',
    (tester) async {
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService(
        enabled: true,
        responseSuggestions: const [
          AssistantSuggestion(
            label: '每周重复',
            message: '请把这门 TA 课设置为每周重复。',
            isOther: false,
          ),
          AssistantSuggestion(label: '其他', message: '', isOther: true),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        coordinator.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: service,
          historyStore: _MemoryHistoryStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '帮我决定下一步');
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('assistant-suggestion-strip')),
        findsOneWidget,
      );
      expect(find.text('每周重复'), findsOneWidget);
      expect(find.text('其他'), findsOneWidget);
      final firstChoice = tester.getRect(
        find.byKey(const ValueKey('assistant-suggestion-0')),
      );
      final secondChoice = tester.getRect(
        find.byKey(const ValueKey('assistant-suggestion-1')),
      );
      expect(firstChoice.left, secondChoice.left);
      expect(firstChoice.width, secondChoice.width);
      expect(secondChoice.top, greaterThan(firstChoice.bottom));

      await tester.tap(find.text('每周重复'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(service.messages.last, '请把这门 TA 课设置为每周重复。');
      expect(service.messages, hasLength(2));
    },
  );

  testWidgets('other assistant choice focuses free-form input', (tester) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final service = _FakeAssistantService(
      enabled: true,
      responseSuggestions: const [
        AssistantSuggestion(
          label: '每周重复',
          message: '请把这门 TA 课设置为每周重复。',
          isOther: false,
        ),
        AssistantSuggestion(label: '其他', message: '', isOther: true),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '帮我决定下一步');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('其他'));
    await tester.pump();

    final input = tester.widget<TextField>(find.byType(TextField).last);
    expect(input.focusNode?.hasFocus, isTrue);
    expect(service.messages, hasLength(1));
  });

  testWidgets('assistant memory proposal requires an explicit save', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final service = _FakeAssistantService(
      enabled: true,
      responseMemorySuggestions: const [
        AssistantMemorySuggestion(content: '用户长期倾向软件开发方向。'),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '我的倾向是软件开发');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('assistant-memory-suggestion-panel')),
      findsOneWidget,
    );
    expect(find.text('用户长期倾向软件开发方向。'), findsOneWidget);
    final page = tester.widget<AiAssistantPage>(find.byType(AiAssistantPage));
    expect(page.assistantController.memories, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('assistant-memory-suggestion-save')),
    );
    await tester.pumpAndSettle();

    expect(page.assistantController.memories.single.content, '用户长期倾向软件开发方向。');
    expect(
      find.byKey(const ValueKey('assistant-memory-suggestion-panel')),
      findsNothing,
    );
  });

  testWidgets('reply continues after page pop and is visible when reopened', (
    tester,
  ) async {
    final sessionController = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final chatCompleter = Completer<AssistantChatResult>();
    final service = _FakeAssistantService(
      enabled: true,
      chatCompleter: chatCompleter,
    );
    final assistantController = AiAssistantController(
      sessionController: sessionController,
      service: service,
      coordinator: coordinator,
      historyStore: _MemoryHistoryStore(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      assistantController.dispose();
      coordinator.dispose();
      sessionController.dispose();
    });

    Widget page() => MaterialApp(
      home: AiAssistantPage(
        assistantController: assistantController,
        onExecuteAction: (_, {required userConfirmed}) async {},
      ),
    );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '后台继续回答');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(find.text('正在向小U发送请求'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-thinking-logo')), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('其他页面'))),
    );
    chatCompleter.complete(_chatResult(answer: '后台已完成。'));
    await tester.pumpAndSettle();

    expect(
      assistantController.currentConversation?.messages.last.content,
      '后台已完成。',
    );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('后台已完成。'), findsOneWidget);
  });

  testWidgets('reply keeps the composer editable and disables only send', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final chatCompleter = Completer<AssistantChatResult>();
    final service = _FakeAssistantService(
      enabled: true,
      chatCompleter: chatCompleter,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('assistant-composer-input'));
    await tester.enterText(input, '先回答这条');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();

    expect(tester.widget<TextField>(input).enabled, isTrue);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('发送'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(input, '回复期间保留的草稿');
    expect(find.text('回复期间保留的草稿'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('assistant-thinking-mode-toggle')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await _expectThinkingMode(tester, AssistantThinkingMode.high);
    expect(find.text('回复期间保留的草稿'), findsOneWidget);

    chatCompleter.complete(_chatResult(answer: '完成'));
    await tester.pumpAndSettle();
  });

  testWidgets('desktop enter sends and shift enter inserts a line break', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final service = _FakeAssistantService(enabled: true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('assistant-composer-input'));
    await tester.enterText(input, '第一行');
    final inputController = tester.widget<TextField>(input).controller!;
    inputController.selection = TextSelection.collapsed(
      offset: inputController.text.length,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(service.messages, isEmpty);
    final field = tester.widget<TextField>(input);
    expect(field.controller?.text, '第一行\n');

    await tester.enterText(input, '第一行\n第二行');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(service.messages, ['第一行\n第二行']);
  });

  testWidgets('network failure stays in the activity timeline with retry', (
    tester,
  ) async {
    final sessionController = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    final service = _FakeAssistantService(enabled: true);
    final now = DateTime.utc(2026, 7, 23);
    final history = _MemoryHistoryStore([
      AssistantConversation(
        id: 'failed-conversation',
        title: 'OOP 课件',
        createdAt: now,
        updatedAt: now,
        messages: [
          AssistantStoredMessage(
            role: 'user',
            content: '请重试上一轮请求',
            createdAt: now,
          ),
          AssistantStoredMessage(
            role: 'assistant',
            content: '网络暂时没有恢复，这轮问题已经保留。',
            createdAt: now,
            isError: true,
            compactError: true,
            retryMessage: '请重试上一轮请求',
            activities: const [
              AssistantActivity(label: '网络恢复结束 · provider_connection_timeout'),
              AssistantActivity(label: '网络连接暂未恢复，已保留这轮问题', failed: true),
            ],
          ),
        ],
      ),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      sessionController.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: sessionController,
        coordinator: coordinator,
        service: service,
        historyStore: history,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('这轮请求没有完成'), findsNothing);
    expect(find.textContaining('provider_connection_timeout'), findsNothing);
    expect(find.textContaining('网络连接暂未恢复'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assistant-message-retry')),
      findsOneWidget,
    );
    expect(find.byType(SmallULogo), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('assistant-activity-disclosure')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('provider_connection_timeout'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assistant-message-retry')));
    await tester.pumpAndSettle();

    expect(service.messages, ['请重试上一轮请求']);
    expect(find.text('已整理。'), findsOneWidget);
    expect(find.text('请重试上一轮请求'), findsOneWidget);
  });

  testWidgets(
    'message actions support feedback, editing, and branch switching',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      final session = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService(enabled: true);
      final now = DateTime.utc(2026, 8, 2, 8);
      final history = _MemoryHistoryStore([
        AssistantConversation(
          id: 'branch-root',
          title: '原问题',
          createdAt: now,
          updatedAt: now,
          messages: [
            AssistantStoredMessage(
              role: 'user',
              content: '原问题',
              createdAt: now,
            ),
            AssistantStoredMessage(
              role: 'assistant',
              content: '原回答',
              createdAt: now.add(const Duration(seconds: 1)),
            ),
          ],
        ),
      ]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.reset();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        coordinator.dispose();
        session.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: session,
          coordinator: coordinator,
          service: service,
          historyStore: history,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('assistant-user-edit')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assistant-response-regenerate')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('assistant-user-copy')));
      await tester.pumpAndSettle();
      expect(copiedText, '原问题');
      await tester.tap(find.byKey(const ValueKey('assistant-response-like')));
      await tester.pumpAndSettle();
      expect(
        history.conversations.first.messages.last.feedback,
        AssistantMessageFeedback.up,
      );

      await tester.tap(find.byKey(const ValueKey('assistant-user-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('assistant-edit-message-field')),
        '编辑后的问题',
      );
      await tester.tap(find.text('从这里发送'));
      await tester.pumpAndSettle();

      expect(service.messages, ['编辑后的问题']);
      expect(
        find.byKey(const ValueKey('assistant-branch-position')),
        findsOneWidget,
      );
      expect(find.text('2/2'), findsOneWidget);
      final switcher = find.byKey(const ValueKey('assistant-branch-position'));
      expect(
        find.ancestor(of: switcher, matching: find.byType(AppBar)),
        findsNothing,
      );
      final actions = find
          .byKey(const ValueKey('assistant-response-actions'))
          .last;
      expect(find.descendant(of: actions, matching: switcher), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('assistant-previous-branch')))
            .dx,
        greaterThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('assistant-response-dislike')).last,
              )
              .dx,
        ),
      );
      final copyIcon = find.descendant(
        of: find.byKey(const ValueKey('assistant-response-copy')).last,
        matching: find.byIcon(LucideIcons.copy300),
      );
      expect(
        tester.getTopLeft(copyIcon).dx,
        closeTo(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('assistant-response-content')).last,
              )
              .dx,
          .1,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('assistant-previous-branch')));
      await tester.pumpAndSettle();
      expect(find.text('原回答'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
    },
  );

  testWidgets('email action enters the native flow without an AI dialog', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    AssistantAction? executedAction;
    final conversation = AssistantConversation(
      id: 'conversation-1',
      title: '邮件',
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
      messages: [
        AssistantStoredMessage(
          role: 'assistant',
          content: '邮件已准备好。',
          createdAt: DateTime.utc(2026, 7, 21),
          actions: const [
            AssistantAction(
              type: AssistantActionType.composeEmail,
              title: '发送邮件',
              requiresConfirmation: true,
              targetId: '',
              url: '',
              recipient: 'teacher@bnbu.edu.cn',
              subject: 'Original subject',
              body: 'Original body',
              placeQuery: '',
            ),
          ],
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore([conversation]),
        onExecuteAction: (action, {required userConfirmed}) async {
          expect(userConfirmed, isTrue);
          executedAction = action;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('发送邮件'));
    await tester.pumpAndSettle();
    expect(find.text('确认邮件草稿'), findsNothing);

    expect(executedAction?.recipient, 'teacher@bnbu.edu.cn');
    expect(executedAction?.subject, 'Original subject');
    expect(executedAction?.body, 'Original body');
  });

  testWidgets('a freshly generated email action opens the native flow', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    AssistantAction? executedAction;
    final service = _FakeAssistantService(
      enabled: true,
      responseActions: const [
        AssistantAction(
          actionId: 'compose-ar',
          type: AssistantActionType.composeEmail,
          title: '打开邮件草稿',
          requiresConfirmation: true,
          targetId: '',
          url: '',
          recipient: 'ar@bnbu.edu.cn',
          subject: '课程注册咨询',
          body: '您好，我想咨询课程注册。',
          placeQuery: '',
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
        onExecuteAction: (action, {required userConfirmed}) async {
          expect(userConfirmed, isTrue);
          executedAction = action;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '帮我给 AR 写邮件');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(executedAction?.type, AssistantActionType.composeEmail);
    expect(executedAction?.recipient, 'ar@bnbu.edu.cn');
    expect(executedAction?.subject, '课程注册咨询');
    expect(find.text('确认邮件草稿'), findsNothing);
  });

  testWidgets('action button honors a declared confirmation requirement', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    AssistantAction? executedAction;
    final conversation = AssistantConversation(
      id: 'conversation-confirm-button',
      title: '课程资料',
      createdAt: DateTime.utc(2026, 7, 22),
      updatedAt: DateTime.utc(2026, 7, 22),
      messages: [
        AssistantStoredMessage(
          role: 'assistant',
          content: '资料清单已准备。',
          createdAt: DateTime.utc(2026, 7, 22),
          actions: const [
            AssistantAction(
              actionId: 'course-pack',
              type: AssistantActionType.prepareCoursePack,
              title: '准备资料清单',
              requiresConfirmation: true,
              targetId: '42',
              url: '',
              recipient: '',
              subject: '',
              body: '',
              placeQuery: '',
            ),
          ],
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore([conversation]),
        onExecuteAction: (action, {required userConfirmed}) async {
          expect(userConfirmed, isTrue);
          executedAction = action;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('准备资料清单'));
    await tester.pumpAndSettle();
    expect(find.text('确认操作'), findsNothing);
    expect(executedAction?.actionId, 'course-pack');
  });

  testWidgets('native side effects hand off without assistant dialogs', (
    tester,
  ) async {
    final controllers = <_AssistantController>[];
    final coordinators = <AssistantContextCoordinator>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final coordinator in coordinators) {
        coordinator.dispose();
      }
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    final testCases = [
      (
        action: const AssistantAction(
          actionId: 'download-attachment',
          type: AssistantActionType.downloadAttachment,
          title: '下载报告附件',
          requiresConfirmation: true,
          targetId: '',
          url: '',
          recipient: '',
          subject: '',
          body: '',
          placeQuery: '',
          mailUid: 17,
          mailFolder: 'inbox',
          mailboxUidValidity: 9001,
          mailPartId: '2.1',
          attachmentName: 'report.pdf',
        ),
        dialogTitle: '确认附件下载',
        summary: '小U会打开原生邮件详情，重新校验附件后才开始下载。',
        detail: 'report.pdf',
        confirmLabel: '打开邮件并下载',
      ),
      (
        action: const AssistantAction(
          actionId: 'batch-course-files',
          type: AssistantActionType.batchDownloadCourseFiles,
          title: '批量下载课程资料',
          requiresConfirmation: true,
          targetId: '42',
          url: '',
          recipient: '',
          subject: '',
          body: '',
          placeQuery: '',
        ),
        dialogTitle: '确认打包课程资料',
        summary:
            '小U会重新读取原生课程文件清单，按要求预选并分类显示文件；'
            '显示实际数量与大小供你确认后，App 会自动下载并在本机生成 ZIP。',
        detail: '课程 ID',
        confirmLabel: '读取并打包',
      ),
      (
        action: const AssistantAction(
          actionId: 'upload-assignment-file',
          type: AssistantActionType.uploadAssignmentFile,
          title: '上传作业文件',
          requiresConfirmation: true,
          targetId: '7',
          url: '',
          recipient: '',
          subject: '',
          body: '',
          placeQuery: '',
        ),
        dialogTitle: '确认作业文件上传',
        summary: '小U只会打开原生作业页和文件选择器，不会自动提交文件。',
        detail: '作业 ID',
        confirmLabel: '打开文件选择器',
      ),
      (
        action: const AssistantAction(
          actionId: 'delete-mail',
          type: AssistantActionType.deleteMail,
          title: '删除课程邮件',
          requiresConfirmation: true,
          targetId: '',
          url: '',
          recipient: '',
          subject: '',
          body: '',
          placeQuery: '',
          mailUid: 17,
          mailFolder: 'inbox',
          mailboxUidValidity: 9001,
        ),
        dialogTitle: '确认删除邮件',
        summary: '小U会前往原生邮箱重新读取邮件；删除前仍需在邮箱页面最终确认。',
        detail: 'inbox',
        confirmLabel: '前往邮箱确认删除',
      ),
      (
        action: const AssistantAction(
          actionId: 'restore-mail',
          type: AssistantActionType.restoreMail,
          title: '恢复课程邮件',
          requiresConfirmation: true,
          targetId: '',
          url: '',
          recipient: '',
          subject: '',
          body: '',
          placeQuery: '',
          mailUid: 18,
          mailFolder: 'trash',
          mailboxUidValidity: 9002,
        ),
        dialogTitle: '确认恢复邮件',
        summary: '小U会前往原生邮箱重新读取邮件；恢复前仍需在邮箱页面最终确认。',
        detail: 'trash',
        confirmLabel: '前往邮箱确认恢复',
      ),
    ];

    for (final testCase in testCases) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      controllers.add(controller);
      coordinators.add(coordinator);
      AssistantAction? executedAction;
      bool? didConfirm;
      final conversation = AssistantConversation(
        id: 'conversation-${testCase.action.actionId}',
        title: '原生交接',
        createdAt: DateTime.utc(2026, 7, 23),
        updatedAt: DateTime.utc(2026, 7, 23),
        messages: [
          AssistantStoredMessage(
            role: 'assistant',
            content: '操作已准备。',
            createdAt: DateTime.utc(2026, 7, 23),
            actions: [testCase.action],
          ),
        ],
      );

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          historyStore: _MemoryHistoryStore([conversation]),
          onExecuteAction: (action, {required userConfirmed}) async {
            executedAction = action;
            didConfirm = userConfirmed;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(testCase.action.title));
      await tester.pumpAndSettle();
      expect(find.text(testCase.dialogTitle), findsNothing);
      expect(executedAction?.actionId, testCase.action.actionId);
      expect(didConfirm, isTrue);
    }
  });

  testWidgets(
    'Markdown action link honors a declared confirmation requirement',
    (tester) async {
      final controller = _AssistantController();
      final coordinator = AssistantContextCoordinator();
      AssistantAction? executedAction;
      final conversation = AssistantConversation(
        id: 'conversation-confirm-link',
        title: '邮件',
        createdAt: DateTime.utc(2026, 7, 22),
        updatedAt: DateTime.utc(2026, 7, 22),
        messages: [
          AssistantStoredMessage(
            role: 'assistant',
            content: '[打开邮件详情](assistant-action:mail-17)',
            createdAt: DateTime.utc(2026, 7, 22),
            actions: const [
              AssistantAction(
                actionId: 'mail-17',
                type: AssistantActionType.openMail,
                title: '打开原邮件',
                requiresConfirmation: true,
                targetId: '',
                url: '',
                recipient: '',
                subject: '',
                body: '',
                placeQuery: '',
                mailUid: 17,
                mailFolder: 'inbox',
                mailboxUidValidity: 9001,
              ),
            ],
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        coordinator.dispose();
        controller.dispose();
      });

      await tester.pumpWidget(
        _TestHost(
          controller: controller,
          coordinator: coordinator,
          service: _FakeAssistantService(enabled: true),
          historyStore: _MemoryHistoryStore([conversation]),
          onExecuteAction: (action, {required userConfirmed}) async {
            expect(userConfirmed, isTrue);
            executedAction = action;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开邮件详情'));
      await tester.pumpAndSettle();
      expect(find.text('确认操作'), findsNothing);
      expect(executedAction?.actionId, 'mail-17');
    },
  );

  testWidgets('TA course action enters the native editor directly', (
    tester,
  ) async {
    final controller = _AssistantController();
    final coordinator = AssistantContextCoordinator();
    AssistantAction? executedAction;
    final conversation = AssistantConversation(
      id: 'conversation-ta',
      title: 'TA 课',
      createdAt: DateTime.utc(2026, 7, 23),
      updatedAt: DateTime.utc(2026, 7, 23),
      messages: [
        AssistantStoredMessage(
          role: 'assistant',
          content: 'TA 课草稿已准备。',
          createdAt: DateTime.utc(2026, 7, 23),
          actions: const [
            AssistantAction(
              actionId: 'ta-add',
              type: AssistantActionType.addTaCourse,
              title: '新增 TA 课',
              requiresConfirmation: true,
              targetId: '',
              url: '',
              recipient: '',
              subject: '',
              body: '',
              placeQuery: '',
              taTitle: 'Programming TA',
              taLocation: 'B201',
              taWeekday: DateTime.tuesday,
              taStartMinutes: 10 * 60,
              taEndMinutes: 10 * 60 + 50,
              taRepeatType: 'weekly',
              taExpectedCollectionRevision: 2,
            ),
          ],
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _TestHost(
        controller: controller,
        coordinator: coordinator,
        service: _FakeAssistantService(enabled: true),
        historyStore: _MemoryHistoryStore([conversation]),
        onExecuteAction: (action, {required userConfirmed}) async {
          expect(userConfirmed, isTrue);
          executedAction = action;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增 TA 课'));
    await tester.pumpAndSettle();
    expect(find.text('确认新增 TA 课'), findsNothing);
    expect(executedAction?.taTitle, 'Programming TA');
    expect(executedAction?.taLocation, 'B201');
    expect(executedAction?.taStartMinutes, 10 * 60);
    expect(executedAction?.taEndMinutes, 10 * 60 + 50);
    expect(executedAction?.taExpectedCollectionRevision, 2);
  });
}

class _TestHost extends StatefulWidget {
  const _TestHost({
    required this.controller,
    required this.coordinator,
    required this.service,
    required this.historyStore,
    this.locationService,
    this.onExecuteAction,
    this.attachmentPicker,
    this.resourceLibrary,
    this.openFromLauncher = false,
    this.openFixtureHistory = true,
    this.theme,
    this.locale,
  });

  final AppSessionController controller;
  final AssistantContextCoordinator coordinator;
  final AiAssistantService service;
  final AssistantHistoryStore historyStore;
  final AssistantLocationService? locationService;
  final AssistantActionExecutionCallback? onExecuteAction;
  final AssistantAttachmentPicker? attachmentPicker;
  final AssistantResourceLibraryController? resourceLibrary;
  final bool openFromLauncher;
  final bool openFixtureHistory;
  final ThemeData? theme;
  final Locale? locale;

  @override
  State<_TestHost> createState() => _TestHostState();
}

class _TestHostState extends State<_TestHost> {
  late final AiAssistantController _assistantController = AiAssistantController(
    sessionController: widget.controller,
    service: widget.service,
    coordinator: widget.coordinator,
    historyStore: widget.historyStore,
    locationService: widget.locationService,
  );

  @override
  void initState() {
    super.initState();
    if (widget.openFixtureHistory) {
      _assistantController.addListener(_openFixtureConversation);
    }
  }

  void _openFixtureConversation() {
    if (_assistantController.currentConversation == null) return;
    _assistantController.removeListener(_openFixtureConversation);
    // These cases exercise an explicitly opened fixture conversation. Cold
    // start selection is covered separately by the controller regression.
    final history = _assistantController.conversationHistory;
    if (history.isNotEmpty) {
      _assistantController.selectConversation(history.first.id);
    }
  }

  @override
  void dispose() {
    _assistantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assistantPage = AiAssistantPage(
      assistantController: _assistantController,
      attachmentPicker: widget.attachmentPicker,
      resourceLibrary: widget.resourceLibrary,
      onExecuteAction:
          widget.onExecuteAction ?? (_, {required userConfirmed}) async {},
    );
    return AssistantContextScope(
      coordinator: widget.coordinator,
      assistantController: _assistantController,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: widget.theme,
        locale: widget.locale,
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: [
          if (widget.locale != null) BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: widget.openFromLauncher
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      key: const ValueKey('open-assistant-test-route'),
                      onPressed: () => Navigator.of(context).push<void>(
                        AssistantPageRoute(builder: (_) => assistantPage),
                      ),
                      child: const Text('打开小U'),
                    ),
                  ),
                ),
              )
            : assistantPage,
      ),
    );
  }
}

class _AssistantController extends AppSessionController {
  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';
}

class _LoggedInAssistantController extends _AssistantController {
  @override
  bool get isLoggedIn => true;
}

class _MemoryResourceLibraryStore implements AssistantResourceLibraryStore {
  _MemoryResourceLibraryStore(this.items);

  final List<AssistantResourceItem> items;

  @override
  Future<void> delete(String owner, AssistantResourceItem item) async {
    items.removeWhere((candidate) => candidate.id == item.id);
  }

  @override
  Future<AssistantResourceItem> importFile(
    String owner, {
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required AssistantResourceKind kind,
    required String sourceTitle,
    required String summary,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AssistantResourceItem>> load(String owner) async {
    return List.unmodifiable(items);
  }
}

class _FakeAssistantService
    implements AiAssistantService, AiAssistantAttachmentService {
  _FakeAssistantService({
    required this.enabled,
    this.chatCompleter,
    this.responseSuggestions = const [],
    this.responseActions = const [],
    this.responseMemorySuggestions = const [],
    this.contextSources = const {
      'courses',
      'deadlines',
      'schedule',
      'mail_summaries',
      'selected_mail',
      'school_activities',
      'current_page',
      'current_location',
    },
  });

  bool enabled;
  final Completer<AssistantChatResult>? chatCompleter;
  final List<AssistantSuggestion> responseSuggestions;
  final List<AssistantAction> responseActions;
  final List<AssistantMemorySuggestion> responseMemorySuggestions;
  final Set<String> contextSources;
  int enableCalls = 0;
  final List<String> messages = [];
  AssistantContextPayload? lastContext;
  List<AssistantInputAttachment> lastAttachments = const [];

  @override
  Future<AssistantChatResult> chat({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    messages.add(message);
    lastContext = context;
    final pending = chatCompleter;
    if (pending != null) {
      return pending.future;
    }
    return _chatResult(
      answer: '已整理。',
      actions: responseActions,
      suggestions: messages.length == 1 ? responseSuggestions : const [],
      memorySuggestions: messages.length == 1
          ? responseMemorySuggestions
          : const [],
    );
  }

  @override
  Future<AssistantChatResult> chatWithAttachments({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    required List<AssistantInputAttachment> attachments,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    lastContext = context;
    lastAttachments = List.unmodifiable(attachments);
    return _chatResult(answer: '已整理。');
  }

  @override
  void dispose() {}

  @override
  Future<bool> isEnabled(String username) async => enabled;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    return AssistantCapabilities(
      available: true,
      model: 'test-model',
      contextSources: contextSources,
      actions: const {'compose_email', 'submit_assignment'},
      thinkingModes: const {
        AssistantThinkingMode.low,
        AssistantThinkingMode.medium,
        AssistantThinkingMode.high,
      },
      storesConversationContent: false,
      purchaseApiAvailable: false,
    );
  }

  @override
  Future<AssistantQuota> loadQuota(String username) async => _quota();

  @override
  Future<void> setEnabled(String username, bool enabled) async {
    enableCalls++;
    this.enabled = enabled;
  }
}

class _MemoryHistoryStore implements AssistantHistoryStore {
  _MemoryHistoryStore([List<AssistantConversation> initial = const []])
    : conversations = List.of(initial);

  List<AssistantConversation> conversations;

  @override
  Future<List<AssistantConversation>> load(String username) async {
    return List.of(conversations);
  }

  @override
  Future<void> save(
    String username,
    List<AssistantConversation> conversations,
  ) async {
    this.conversations = List.of(conversations);
  }
}

class _FakeLocationService implements AssistantLocationService {
  int calls = 0;

  @override
  Future<AssistantCurrentLocationContext> currentLocation() async {
    calls++;
    return AssistantCurrentLocationContext(
      latitude: 22.35,
      longitude: 114.17,
      accuracyMeters: 8,
      observedAt: DateTime.utc(2026, 7, 21, 10),
    );
  }
}

AssistantChatResult _chatResult({
  required String answer,
  List<AssistantAction> actions = const [],
  List<AssistantSuggestion> suggestions = const [],
  List<AssistantMemorySuggestion> memorySuggestions = const [],
}) {
  return AssistantChatResult(
    requestId: 'request-id',
    answer: answer,
    actions: actions,
    suggestions: suggestions,
    memorySuggestions: memorySuggestions,
    usage: const AssistantTokenUsage(
      inputTokens: 10,
      outputTokens: 5,
      totalTokens: 15,
    ),
    quota: _quota(remaining: 9985),
  );
}

AssistantQuota _quota({int remaining = 10000}) {
  return AssistantQuota(
    periodStart: DateTime.utc(2026, 7),
    periodEnd: DateTime.utc(2026, 8),
    monthlyQuotaTokens: 10000,
    creditBalanceTokens: 0,
    usedTokens: 10000 - remaining,
    reservedTokens: 0,
    remainingTokens: remaining,
  );
}
