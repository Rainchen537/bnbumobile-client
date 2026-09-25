import 'dart:async';
import 'package:flutter/services.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/pages/web_mirror_page.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/state/ai_assistant_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/study_mode_controller.dart';
import 'package:bnbu_me/widgets/assistant_context_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'leaving a preview while preparing share does not open native UI',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final session = _StudySessionController();
      const channel = MethodChannel('ispace/native_actions');
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        session.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WebMirrorPage(
            controller: session,
            title: 'Resource page',
            showFileActions: true,
            pathOrUrl: '/mod/page/view.php?id=1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final pending = Completer<WebSessionSnapshot>();
      session.pendingSnapshot = pending;
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存或分享'));
      await tester.pump();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Closed'))),
      );
      pending.complete(
        WebSessionSnapshot(baseUrl: session.baseUrl, cookies: const []),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('file preview preserves viewport width at $width', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      final session = _StudySessionController();
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.reset();
        session.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WebMirrorPage(
            controller: session,
            title: 'Resource page',
            showFileActions: true,
            pathOrUrl: '/mod/page/view.php?id=1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final reader = find.byType(NativeMirrorWebView);
      expect(tester.getSize(reader).width, closeTo(width - 8, 0.1));
      expect(tester.getTopLeft(reader).dx, closeTo(4, 0.1));
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'wide file preview keeps the temporarily hidden study workspace inactive',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final session = _StudySessionController();
      final coordinator = AssistantContextCoordinator();
      final studyMode = StudyModeController();
      var openedDocuments = <AssistantStudyDocument>[];
      final assistant = AiAssistantController(
        sessionController: session,
        service: _StudyAssistantService(),
        coordinator: coordinator,
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.reset();
        studyMode.dispose();
        assistant.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AssistantContextScope(
            coordinator: coordinator,
            assistantController: assistant,
            studyModeController: studyMode,
            child: WebMirrorPage(
              controller: session,
              title: 'Lecture 01.pdf',
              pathOrUrl: '/pluginfile.php/lecture-01.pdf',
              showFileActions: true,
              studyItems: const ['Lecture 01.pdf', 'Lecture 02.pdf'],
              studyDocumentOpener: (document) async {
                openedDocuments = [...openedDocuments, document];
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('ispace-study-mode')), findsNothing);
      expect(studyMode.active, isFalse);
      expect(openedDocuments, isEmpty);
      await studyMode.open();
      expect(openedDocuments, isEmpty);
      expect(studyMode.active, isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class _StudyAssistantService implements AiAssistantService {
  @override
  Future<AssistantChatResult> chat({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) => throw UnimplementedError();

  @override
  void dispose() {}

  @override
  Future<bool> isEnabled(String username) async => true;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async =>
      const AssistantCapabilities(
        available: true,
        model: 'test',
        contextSources: {},
        actions: {},
        storesConversationContent: false,
        purchaseApiAvailable: false,
      );

  @override
  Future<AssistantQuota> loadQuota(String username) async => AssistantQuota(
    periodStart: DateTime.utc(2026),
    periodEnd: DateTime.utc(2026, 2),
    monthlyQuotaTokens: 1000,
    creditBalanceTokens: 0,
    usedTokens: 0,
    reservedTokens: 0,
    remainingTokens: 1000,
    unlimited: false,
  );

  @override
  Future<void> setEnabled(String username, bool enabled) async {}
}

class _StudySessionController extends AppSessionController {
  Completer<WebSessionSnapshot>? pendingSnapshot;
  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student@example.edu';

  @override
  String get baseUrl => 'https://ispace.example.edu';

  @override
  Future<WebSessionSnapshot> prepareWebSession() async {
    if (pendingSnapshot != null) return pendingSnapshot!.future;
    return WebSessionSnapshot(baseUrl: baseUrl, cookies: const []);
  }
}
