import 'dart:async';
import 'dart:ui' show SemanticsAction;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';
import 'package:bnbu_me/pages/ai_assistant_page.dart';
import 'package:bnbu_me/pages/campus_navigation_page.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/app_navigation_coordinator.dart';
import 'package:bnbu_me/services/assistant_action_runtime.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/moodle_api_client.dart';
import 'package:bnbu_me/state/ai_assistant_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/assistant_presentation_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/study_mode_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/widgets/ai_assistant_overlay.dart';
import 'package:bnbu_me/widgets/assistant_context_scope.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';
import 'package:bnbu_me/widgets/small_u_logo.dart';
import 'package:bnbu_me/widgets/small_u_glass_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'unbound floating entry stays open with local history and binding action',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      var requests = 0;
      final remote = _UnboundAssistantService(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      final harness = _NavigationHarness(controllerService: remote);
      _disposeHarnessAfterUnmount(tester, harness);
      addTearDown(remote.dispose);
      await harness.pump(tester);
      expect(harness.assistantController.requiresMeBinding, isTrue);
      expect(harness.assistantController.enabled, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('assistant-overlay-drag-target')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(harness.presentationController.isAssistantPresented, isTrue);
      expect(find.text('绑定 ME 账户，继续使用小U'), findsOneWidget);
      harness.assistantController.clearError();
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(requests, 0);
    },
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('semantic tap opens, closes, and expands the assistant ball', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
      Future<void> activate(String label) async {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
      }

      await activate('打开小U AI 助手');
      expect(find.byType(AiAssistantPage), findsOneWidget);
      await activate('收起小U AI 助手');
      expect(find.byType(AiAssistantPage), findsNothing);
      harness.presentationController.updateFloatingAnchor(
        const Offset(1, 1),
        edgeHidden: true,
      );
      await tester.pumpAndSettle();
      await activate('展开小U AI 助手');
      expect(harness.presentationController.floatingEdgeHidden, isFalse);
      expect(find.byType(AiAssistantPage), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('iPhone assistant glass follows appearance $brightness', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final appearance = AppThemeModeController(
        liquidGlassSupportLoader: () async => true,
      );
      addTearDown(appearance.dispose);
      await appearance.restore();
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(
        tester,
        appearanceController: appearance,
        theme: ThemeData(platform: TargetPlatform.iOS, brightness: brightness),
        pageOverrides: (_) => const SizedBox.shrink(),
      );
      final ball = find.byKey(const ValueKey('assistant-overlay-drag-target'));
      final glass = find.byKey(
        const ValueKey('assistant-overlay-liquid-glass'),
      );
      final solid = find.byKey(
        const ValueKey('assistant-overlay-solid-surface'),
      );
      expect(glass, findsOneWidget);
      expect(solid, findsNothing);
      expect(tester.widget<SmallUGlassLogo>(glass).size, 56);
      expect(
        find.descendant(
          of: ball,
          matching: find.byType(BnbuLiquidGlassSurface),
        ),
        findsNothing,
      );
      expect(tester.getSize(ball), const Size.square(56));
      expect(
        find.descendant(of: ball, matching: find.byType(SmallULogo)),
        findsNothing,
      );
      final original = tester.getRect(ball);
      await appearance.setLiquidGlassEnabled(false);
      await tester.pumpAndSettle();
      expect(glass, findsNothing);
      expect(solid, findsOneWidget);
      final logo = tester.widget<SmallULogo>(
        find.descendant(of: ball, matching: find.byType(SmallULogo)),
      );
      expect(logo.size, 35.1);
      expect(logo.monochrome, isTrue);
      expect(tester.getRect(ball), original);
      expect(
        (tester.widget<Container>(solid).decoration! as BoxDecoration).color,
        brightness == Brightness.dark ? Colors.black : Colors.white,
      );
      await appearance.setLiquidGlassEnabled(true);
      await tester.pumpAndSettle();
      expect(glass, findsOneWidget);
      await _dragAssistantBall(tester, const Offset(-120, -100));
      await tester.pumpAndSettle();
      expect(tester.getRect(ball).top, lessThan(original.top));
      expect(find.byType(AiAssistantPage), findsNothing);
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(ball, findsOneWidget);
      expect(glass, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assistant-compact-back')));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsNothing);
      expect(glass, findsOneWidget);
      await _dragAssistantBall(tester, const Offset(-450, 0));
      await tester.pumpAndSettle();
      expect(harness.presentationController.floatingEdgeHidden, isTrue);
      final hiddenPosition = tester.getRect(ball);
      await appearance.setLiquidGlassEnabled(false);
      await tester.pumpAndSettle();
      expect(tester.getRect(ball), hiddenPosition);
      await appearance.setLiquidGlassEnabled(true);
      await tester.pumpAndSettle();
      expect(tester.getRect(ball), hiddenPosition);
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(harness.presentationController.floatingEdgeHidden, isFalse);
      expect(find.byType(AiAssistantPage), findsNothing);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      expect(glass, findsNothing);
      expect(solid, findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets('assistant keeps solid fallback on $platform', (tester) async {
      final appearance = AppThemeModeController(
        liquidGlassSupportLoader: () async => platform != TargetPlatform.iOS,
      );
      addTearDown(appearance.dispose);
      await appearance.restore();
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(
        tester,
        appearanceController: appearance,
        theme: ThemeData(platform: platform),
        pageOverrides: (_) => const SizedBox.shrink(),
      );
      expect(
        find.byKey(const ValueKey('assistant-overlay-liquid-glass')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('assistant-overlay-solid-surface')),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'compact ball rests freely, docks, hides and reveals before opening',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
      final ball = find.byKey(const ValueKey('assistant-overlay-drag-target'));
      await _dragAssistantBall(tester, const Offset(-170, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(ball).left, inExclusiveRange(30, 300));
      expect(harness.presentationController.floatingEdgeHidden, isFalse);
      expect(find.byType(AiAssistantPage), findsNothing);

      final delta = 5 - tester.getRect(ball).left;
      await _dragAssistantBall(tester, Offset(delta, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(ball).left, closeTo(12, .1));
      expect(harness.presentationController.floatingEdgeHidden, isFalse);

      await _dragAssistantBall(tester, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(ball).left, lessThan(0));
      expect(harness.presentationController.floatingEdgeHidden, isTrue);
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(tester.getRect(ball).left, closeTo(12, .1));
      expect(find.byType(AiAssistantPage), findsNothing);
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
    },
  );

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets(
      'assistant keeps its launcher and tapping restores the original route at $width',
      (tester) async {
        debugDefaultTargetPlatformOverride = width < 700
            ? TargetPlatform.iOS
            : TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final harness = _NavigationHarness();
        _disposeHarnessAfterUnmount(tester, harness);
        await harness.pump(
          tester,
          theme: ThemeData(platform: TargetPlatform.iOS),
          pageOverrides: (_) => const Text('original page'),
        );
        harness.presentationController.updateFloatingAnchor(
          const Offset(.5, .25),
        );
        await tester.pumpAndSettle();
        final ball = find.byKey(
          const ValueKey('assistant-overlay-drag-target'),
        );
        final before = tester.getRect(ball);
        unawaited(
          harness.navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'original-detail'),
              builder: (_) => const Scaffold(body: Text('original detail')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tapAssistantBall(tester);
        await tester.pumpAndSettle();
        expect(find.byType(AiAssistantPage), findsOneWidget);
        expect(ball, findsOneWidget);
        expect(
          harness.presentationController.floatingAnchor,
          const Offset(.5, .25),
        );
        await _tapAssistantBall(tester);
        await tester.pumpAndSettle();
        expect(find.byType(AiAssistantPage), findsNothing);
        expect(tester.getRect(ball), before);
        expect(find.text('original detail'), findsOneWidget);
        expect(harness.observer.stackNames, ['/', 'original-detail']);
        await _tapAssistantBall(tester);
        await tester.pumpAndSettle();
        expect(find.byType(AiAssistantPage), findsOneWidget);
        expect(ball, findsOneWidget);
        expect(harness.observer.stackNames, [
          '/',
          'original-detail',
          'ai-assistant',
        ]);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('hidden study mode cannot replace the normal small U route', (
    tester,
  ) async {
    final harness = _NavigationHarness();
    final studyMode = StudyModeController();
    var openCount = 0;
    final owner = Object();
    studyMode.activate(owner, () async {
      openCount += 1;
    });
    addTearDown(studyMode.dispose);
    _disposeHarnessAfterUnmount(tester, harness);
    await harness.pump(tester, studyModeController: studyMode);

    expect(openCount, 0);
    await _tapAssistantBall(tester);
    await tester.pumpAndSettle();

    expect(openCount, 0);
    expect(find.byType(AiAssistantPage), findsOneWidget);
  });

  testWidgets('compact mailbox keeps the floating assistant available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = _NavigationHarness();
    _disposeHarnessAfterUnmount(tester, harness);
    await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
    expect(find.byType(FloatingActionButton), findsOneWidget);
    harness.shellController.selectTab(AppTab.mail);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    harness.shellController.selectTab(AppTab.home);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'floating assistant stays above the compact keyboard without changing its anchor',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.viewInsets = const FakeViewPadding();
        debugDefaultTargetPlatformOverride = null;
      });
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
      harness.presentationController.updateFloatingAnchor(
        const Offset(1, 1),
        edgeHidden: true,
      );
      await tester.pumpAndSettle();
      final anchorBeforeKeyboard =
          harness.presentationController.floatingAnchor;

      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();

      final dragTarget = find.byKey(
        const ValueKey('assistant-overlay-drag-target'),
      );
      expect(dragTarget, findsOneWidget);
      expect(tester.getBottomRight(dragTarget).dy, lessThanOrEqualTo(508 - 12));
      expect(
        harness.presentationController.floatingAnchor,
        anchorBeforeKeyboard,
      );
      expect(harness.presentationController.floatingEdgeHidden, isTrue);
      expect(
        tester.getRect(dragTarget).width -
            (390 - tester.getRect(dragTarget).left),
        closeTo(33.6, 0.1),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Android opens history from the leading button and system back preserves drafts',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      });
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
      final draftAttachment = AssistantInputAttachment(
        name: 'draft.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      harness.presentationController.updateAssistantDraft(
        ownerToken: harness.presentationController.assistantDraftOwnerToken,
        text: '保留这段未发送内容',
        attachments: [draftAttachment],
      );

      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();

      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assistant-compact-back')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('assistant-desktop-history')),
        findsNothing,
      );
      expect(find.text('保留这段未发送内容'), findsOneWidget);
      expect(find.text('draft.pdf'), findsOneWidget);
      final history = find.byKey(const ValueKey('assistant-android-history'));
      expect(history, findsOneWidget);
      expect((tester.widget<IconButton>(history).icon as Icon).size, 21.6);
      expect(tester.getSize(history).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(history).height, greaterThanOrEqualTo(44));

      final ball = find.byKey(const ValueKey('assistant-overlay-drag-target'));
      expect(ball, findsOneWidget);
      final route = ModalRoute.of(
        tester.element(find.byType(AiAssistantPage)),
      )!;
      expect(route.popGestureEnabled, isTrue);
      await tester.tap(history);
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(
        find
            .descendant(
              of: find.byType(AiAssistantPage),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      expect(scaffold.isDrawerOpen, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isFalse);
      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(ball, findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsNothing);
      expect(ball, findsOneWidget);
      expect(harness.presentationController.isAssistantPresented, isFalse);
      expect(harness.presentationController.assistantDraftText, '保留这段未发送内容');
      expect(harness.observer.stackNames, ['/']);

      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(find.text('保留这段未发送内容'), findsOneWidget);
      expect(find.text('draft.pdf'), findsOneWidget);
      expect(harness.observer.stackNames, ['/', 'ai-assistant']);

      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsNothing);
      expect(harness.presentationController.isAssistantPresented, isFalse);
      expect(harness.presentationController.assistantDraftText, '保留这段未发送内容');
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(find.text('保留这段未发送内容'), findsOneWidget);
      expect(find.text('draft.pdf'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'assistant keeps the launcher above the composer when the keyboard opens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.viewInsets = const FakeViewPadding();
      });
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
      harness.presentationController.updateFloatingAnchor(const Offset(1, 1));
      await tester.pumpAndSettle();
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();

      final sendRect = tester.getRect(
        find.byKey(const ValueKey('assistant-send-button')),
      );
      expect(sendRect.bottom, lessThanOrEqualTo(844 - 336));
      expect(
        find.byKey(const ValueKey('assistant-overlay-drag-target')),
        findsOneWidget,
      );
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('assistant-overlay-drag-target')),
            )
            .bottom,
        lessThanOrEqualTo(
          harness.presentationController.assistantComposerRect!.top - 12,
        ),
      );
      expect(harness.presentationController.floatingAnchor, const Offset(1, 1));
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assistant-overlay-drag-target')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'assistant at the lowest anchor avoids the composer without covering send',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
      harness.presentationController.updateFloatingAnchor(const Offset(1, 1));
      await tester.pumpAndSettle();
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('assistant-overlay-drag-target')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('assistant-send-button')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('assistant-overlay-drag-target')),
            )
            .bottom,
        lessThanOrEqualTo(
          harness.presentationController.assistantComposerRect!.top - 12,
        ),
      );
      expect(harness.presentationController.floatingAnchor, const Offset(1, 1));
    },
  );

  testWidgets('eCard suppresses and restores the assistant overlay', (
    tester,
  ) async {
    final harness = _NavigationHarness();
    _disposeHarnessAfterUnmount(tester, harness);
    await harness.pump(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    unawaited(
      harness.navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StudentEcardPage(
            controller: harness.sessionController,
            onGoToUser: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StudentEcardPage), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(harness.presentationController.isFloatingOverlaySuppressed, isTrue);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.byType(StudentEcardPage), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(harness.presentationController.isFloatingOverlaySuppressed, isFalse);
  });

  testWidgets(
    'direct entry keeps the launcher visible and explicit suppression hides it',
    (tester) async {
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester, pageOverrides: (_) => const SizedBox.shrink());
      final ball = find.byKey(const ValueKey('assistant-overlay-drag-target'));
      unawaited(harness.navigationCoordinator.openAssistant());
      await tester.pumpAndSettle();
      expect(ball, findsOneWidget);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(AiAssistantPage)),
          builder: (_) => const AlertDialog(content: Text('测试弹层')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试弹层'), findsOneWidget);
      expect(ball, findsOneWidget);
      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(ball, findsOneWidget);

      final release = harness.presentationController.suppressFloatingOverlay();
      await harness.presentationController.dismissAssistant();
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsNothing);
      expect(ball, findsNothing);
      release();
      await tester.pumpAndSettle();
      expect(ball, findsOneWidget);
      expect(harness.observer.stackNames, ['/']);
    },
  );

  testWidgets(
    'assistant action dismisses assistant, restores FAB, then opens destination at root',
    (tester) async {
      final harness = _NavigationHarness(
        conversations: [
          _conversationWithAction(
            const AssistantAction(
              actionId: 'place-t3',
              type: AssistantActionType.showCampusPlace,
              title: '打开校园导航',
              requiresConfirmation: false,
              targetId: '',
              url: '',
              recipient: '',
              subject: '',
              body: '',
              placeQuery: 'T3',
              sessionOwner: 'student01',
            ),
          ),
        ],
      );
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester);

      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await tester.tap(find.text('打开校园导航'));
      await tester.pumpAndSettle();

      expect(find.byType(AiAssistantPage), findsNothing);
      expect(find.byType(CampusNavigationPage), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(harness.presentationController.isAssistantPresented, isFalse);
      expect(harness.observer.stackNames, ['/', 'CampusNavigationPage']);
    },
  );

  testWidgets('root tab action dismisses assistant and reuses IndexedStack', (
    tester,
  ) async {
    final harness = _NavigationHarness(
      conversations: [
        _conversationWithAction(
          const AssistantAction(
            actionId: 'tab-schedule',
            type: AssistantActionType.openAppTab,
            title: '打开课表',
            requiresConfirmation: false,
            targetId: 'schedule',
            url: '',
            recipient: '',
            subject: '',
            body: '',
            placeQuery: '',
            sessionOwner: 'student01',
          ),
        ),
      ],
    );
    _disposeHarnessAfterUnmount(tester, harness);
    await harness.pump(tester);

    await _tapAssistantBall(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开课表'));
    await tester.pumpAndSettle();

    expect(find.byType(AiAssistantPage), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(harness.shellController.selectedTab, AppTab.schedule);
    expect(harness.presentationController.isAssistantPresented, isFalse);
    expect(harness.observer.stackNames, ['/']);
  });

  testWidgets('mail mutation dismisses assistant and hands off to mail tab', (
    tester,
  ) async {
    final identity = AssistantActionRuntime.mailIdentity(
      folder: MailFolder.inbox,
      uid: 17,
      mailboxUidValidity: 9001,
    );
    final harness = _NavigationHarness(
      conversations: [
        _conversationWithAction(
          AssistantAction(
            actionId: 'delete-mail-17',
            type: AssistantActionType.deleteMail,
            title: '删除课程邮件',
            requiresConfirmation: true,
            targetId: '',
            url: '',
            recipient: '',
            subject: '',
            body: '',
            placeQuery: '',
            sessionOwner: 'student01',
            targetIdentity: identity,
            mailUid: 17,
            mailFolder: 'inbox',
            mailboxUidValidity: 9001,
          ),
        ),
      ],
    );
    _disposeHarnessAfterUnmount(tester, harness);
    await harness.pump(tester);

    await _tapAssistantBall(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除课程邮件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AiAssistantPage), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(harness.shellController.selectedTab, AppTab.mail);
    expect(harness.presentationController.isAssistantPresented, isFalse);
    expect(harness.observer.stackNames, ['/']);
  });

  testWidgets(
    'pending reply continues after action dismisses assistant route',
    (tester) async {
      final chatCompleter = Completer<AssistantChatResult>();
      final harness = _NavigationHarness(chatCompleter: chatCompleter);
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester);

      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      unawaited(harness.assistantController.send('后台继续回答'));
      for (
        var attempt = 0;
        attempt < 20 && harness.assistantController.pendingTurn == null;
        attempt++
      ) {
        await tester.pump();
      }
      expect(harness.assistantController.pendingTurn, isNotNull);
      await _tapAssistantBall(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AiAssistantPage), findsNothing);
      expect(harness.observer.stackNames, ['/']);
      expect(harness.assistantController.pendingTurn, isNotNull);
      await _tapAssistantBall(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      unawaited(
        harness.navigationCoordinator.executeAssistantAction(
          const AssistantAction(
            actionId: 'place-library',
            type: AssistantActionType.showCampusPlace,
            title: '打开校园导航',
            requiresConfirmation: false,
            targetId: '',
            url: '',
            recipient: '',
            subject: '',
            body: '',
            placeQuery: '图书馆',
            sessionOwner: 'student01',
          ),
          userConfirmed: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(AiAssistantPage), findsNothing);
      expect(find.byType(CampusNavigationPage), findsOneWidget);
      expect(harness.assistantController.pendingTurn, isNotNull);
      expect(
        find.byKey(const ValueKey('assistant-overlay-loading-indicator')),
        findsOneWidget,
      );

      chatCompleter.complete(_chatResult(answer: '后台已完成。'));
      await tester.pumpAndSettle();
      expect(
        harness.assistantController.currentConversation?.messages.last.content,
        '后台已完成。',
      );
      expect(
        find.byKey(const ValueKey('assistant-overlay-completion-indicator')),
        findsOneWidget,
      );

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      expect(find.text('后台已完成。'), findsOneWidget);
      expect(harness.presentationController.hasUnseenCompletedReply, isFalse);
    },
  );

  testWidgets('assistant entry follows medium-window safe bounds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _NavigationHarness();
    _disposeHarnessAfterUnmount(tester, harness);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    await harness.pump(tester);

    final dragTarget = find.byKey(
      const ValueKey('assistant-overlay-drag-target'),
    );
    expect(dragTarget, findsOneWidget);
    final initialCenter = tester.getCenter(dragTarget);

    await _dragAssistantBall(tester, const Offset(-1200, -1200));
    await tester.pumpAndSettle();

    final topLeft = tester.getTopLeft(dragTarget);
    expect(find.byKey(const ValueKey('root-side-navigation')), findsOneWidget);
    // Wide windows keep the entire ball inside the actual window edge.
    expect(topLeft.dx, closeTo(12, 0.1));
    expect(topLeft.dy, greaterThanOrEqualTo(10));
    expect(tester.getCenter(dragTarget), isNot(initialCenter));

    await _dragAssistantBall(tester, const Offset(1800, 1800));
    await tester.pumpAndSettle();

    final bottomRight = tester.getBottomRight(dragTarget);
    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(bottomRight.dx, closeTo(screenSize.width - 12, 0.1));
    expect(bottomRight.dy, lessThanOrEqualTo(screenSize.height - 10));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().contains('assistant.floating_anchor.v1'),
      isTrue,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'legacy sidebar preference keeps assistant at one window position',
    (tester) async {
      tester.view.physicalSize = const Size(1480, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      harness.presentationController.updateFloatingAnchor(
        const Offset(0.35, 0.65),
      );
      await harness.pump(tester);

      final dragTarget = find.byKey(
        const ValueKey('assistant-overlay-drag-target'),
      );
      final initialRect = tester.getRect(dragTarget);

      void expectSameWindowPosition() {
        final rect = tester.getRect(dragTarget);
        expect(rect.left, closeTo(initialRect.left, 0.01));
        expect(rect.top, closeTo(initialRect.top, 0.01));
      }

      harness.shellController.toggleNavigationExpanded();
      await tester.pump();
      expectSameWindowPosition();
      await tester.pump(const Duration(milliseconds: 110));
      expectSameWindowPosition();
      await tester.pump(const Duration(milliseconds: 130));
      expectSameWindowPosition();

      harness.shellController.toggleNavigationExpanded();
      await tester.pump();
      expectSameWindowPosition();
      await tester.pump(const Duration(milliseconds: 110));
      expectSameWindowPosition();
      await tester.pump(const Duration(milliseconds: 130));
      expectSameWindowPosition();
    },
  );

  testWidgets(
    'presentation cleanup removes assistant route without blind pop',
    (tester) async {
      final harness = _NavigationHarness();
      _disposeHarnessAfterUnmount(tester, harness);
      await harness.pump(tester);

      await _tapAssistantBall(tester);
      await tester.pumpAndSettle();
      harness.navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'blocking-route'),
          builder: (_) => const Scaffold(body: Text('无关页面')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('无关页面'), findsOneWidget);

      await harness.presentationController.dismissAssistant();
      await tester.pumpAndSettle();

      expect(find.text('无关页面'), findsOneWidget);
      expect(find.byType(AiAssistantPage), findsNothing);
      expect(harness.observer.stackNames, ['/', 'blocking-route']);
    },
  );
}

Future<void> _tapAssistantBall(WidgetTester tester) async {
  await tester.tapAt(_assistantBallVisibleCenter(tester));
}

Future<void> _dragAssistantBall(WidgetTester tester, Offset offset) async {
  await tester.dragFrom(_assistantBallVisibleCenter(tester), offset);
}

Offset _assistantBallVisibleCenter(WidgetTester tester) {
  final dragTarget = find.byKey(
    const ValueKey('assistant-overlay-drag-target'),
  );
  final targetRect = tester.getRect(dragTarget);
  final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  final visibleRect = targetRect.intersect(Offset.zero & viewSize);
  expect(visibleRect.isEmpty, isFalse);
  return visibleRect.center;
}

void _disposeHarnessAfterUnmount(
  WidgetTester tester,
  _NavigationHarness harness,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });
}

class _NavigationHarness {
  _NavigationHarness({
    List<AssistantConversation> conversations = const [],
    Completer<AssistantChatResult>? chatCompleter,
    AiAssistantService? controllerService,
  }) : navigatorKey = GlobalKey<NavigatorState>(),
       sessionController = _LoggedInSessionController(),
       shellController = RootShellController(),
       mailIntentController = MailAssistantIntentController(),
       presentationController = AssistantPresentationController(),
       coordinator = AssistantContextCoordinator(),
       service = _FakeAssistantService(chatCompleter: chatCompleter),
       historyStore = _MemoryHistoryStore(conversations),
       observer = _RecordingNavigatorObserver() {
    taCourseController = TaCourseController(
      sessionController: sessionController,
    );
    assistantController = AiAssistantController(
      sessionController: sessionController,
      service: controllerService ?? service,
      coordinator: coordinator,
      historyStore: historyStore,
      taCourseController: taCourseController,
    );
    navigationCoordinator = AppNavigationCoordinator(
      navigatorKey: navigatorKey,
      sessionController: sessionController,
      assistantController: assistantController,
      assistantPresentationController: presentationController,
      rootShellController: shellController,
      mailIntentController: mailIntentController,
      taCourseController: taCourseController,
    );
  }

  final GlobalKey<NavigatorState> navigatorKey;
  final _LoggedInSessionController sessionController;
  final RootShellController shellController;
  final MailAssistantIntentController mailIntentController;
  late final TaCourseController taCourseController;
  final AssistantPresentationController presentationController;
  final AssistantContextCoordinator coordinator;
  final _FakeAssistantService service;
  final _MemoryHistoryStore historyStore;
  final _RecordingNavigatorObserver observer;
  late final AiAssistantController assistantController;
  late final AppNavigationCoordinator navigationCoordinator;

  Future<void> pump(
    WidgetTester tester, {
    StudyModeController? studyModeController,
    RootShellPageOverrideBuilder? pageOverrides,
    AppThemeModeController? appearanceController,
    ThemeData? theme,
  }) async {
    await assistantController.initialize();
    final history = assistantController.conversationHistory;
    if (history.isNotEmpty) {
      assistantController.selectConversation(history.first.id);
    }
    final app = MaterialApp(
      theme: theme,
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      home: RootShellPage(
        pageOverrideBuilder: pageOverrides,
        controller: sessionController,
        shellController: shellController,
        taCourseController: taCourseController,
        mailIntentController: mailIntentController,
      ),
      builder: (context, child) => AssistantContextScope(
        coordinator: coordinator,
        assistantController: assistantController,
        presentationController: presentationController,
        studyModeController: studyModeController,
        openAssistant: navigationCoordinator.openAssistant,
        child: Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            AiAssistantOverlay(
              shellController: shellController,
              sessionController: sessionController,
              presentationController: presentationController,
              navigationCoordinator: navigationCoordinator,
              studyModeController: studyModeController,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      appearanceController == null
          ? app
          : BnbuLiquidGlassScope(controller: appearanceController, child: app),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    navigationCoordinator.dispose();
    assistantController.dispose();
    service.dispose();
    coordinator.dispose();
    presentationController.dispose();
    taCourseController.dispose();
    mailIntentController.dispose();
    shellController.dispose();
    sessionController.dispose();
  }
}

class _LoggedInSessionController extends AppSessionController {
  @override
  AuthSession? get session => AuthSession(
    token: 'test-token',
    fullName: 'Test Student',
    userId: 1,
    runtimeProfile: MoodleRuntimeProfile(
      release: 'test',
      version: 'test',
      functionVersions: const {},
      downloadFiles: false,
      uploadFiles: false,
      advancedFeatures: const {},
      userMaxUploadFileSize: 0,
    ),
  );

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  PortalAccountProfile? get portalProfile => const PortalAccountProfile(
    fullName: '测试学生',
    identity: 'BNBU Student UG/STUDENT',
    organization: 'FST',
    department: 'Data Science',
    avatarPath: '',
  );

  @override
  AppSessionLease? captureSessionLease() => const _TestSessionLease();
}

class _TestSessionLease implements AppSessionLease {
  const _TestSessionLease();

  @override
  String get owner => 'student01';

  @override
  bool get isActive => true;
}

class _FakeAssistantService implements AiAssistantService {
  _FakeAssistantService({this.chatCompleter});

  final Completer<AssistantChatResult>? chatCompleter;
  bool disposed = false;

  @override
  Future<AssistantChatResult> chat({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) {
    return chatCompleter?.future ?? Future.value(_chatResult(answer: '完成。'));
  }

  @override
  void dispose() {
    disposed = true;
  }

  @override
  Future<bool> isEnabled(String username) async => true;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    return const AssistantCapabilities(
      available: true,
      model: 'test-model',
      contextSources: {'current_page'},
      actions: {'show_campus_place'},
      storesConversationContent: false,
      purchaseApiAvailable: false,
    );
  }

  @override
  Future<AssistantQuota> loadQuota(String username) async => _quota();

  @override
  Future<void> setEnabled(String username, bool enabled) async {}
}

class _MemoryHistoryStore implements AssistantHistoryStore {
  _MemoryHistoryStore(this.conversations);

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

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  List<String?> get stackNames =>
      _stack.map(_routeName).toList(growable: false);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) {
      if (newRoute != null) _stack.add(newRoute);
      return;
    }
    final index = _stack.indexOf(oldRoute);
    if (index == -1) {
      if (newRoute != null) _stack.add(newRoute);
    } else if (newRoute == null) {
      _stack.removeAt(index);
    } else {
      _stack[index] = newRoute;
    }
  }

  String? _routeName(Route<dynamic> route) {
    return route.settings.name ?? route.settings.arguments?.toString();
  }
}

AssistantConversation _conversationWithAction(AssistantAction action) {
  return AssistantConversation(
    id: 'conversation-action',
    title: '导航',
    createdAt: DateTime.utc(2026, 7, 22),
    updatedAt: DateTime.utc(2026, 7, 22),
    messages: [
      AssistantStoredMessage(
        role: 'assistant',
        content: '可以打开校园导航。',
        createdAt: DateTime.utc(2026, 7, 22),
        actions: [action],
      ),
    ],
  );
}

AssistantChatResult _chatResult({required String answer}) {
  return AssistantChatResult(
    requestId: 'request-id',
    answer: answer,
    actions: const [],
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

class _UnboundAssistantService extends RemoteAiAssistantService {
  _UnboundAssistantService({required super.client});
  @override
  Future<Set<String>> loadHistoryDeletions(String owner) async => {};
}
