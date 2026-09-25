import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/state/assistant_presentation_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'floating anchor is clamped and restored from one atomic preference',
    () async {
      final controller = AssistantPresentationController();
      addTearDown(controller.dispose);

      controller.updateFloatingAnchor(const Offset(-4, 8));
      expect(controller.floatingAnchor, const Offset(0, 1));
      await controller.persistFloatingAnchor();

      final restored = AssistantPresentationController();
      addTearDown(restored.dispose);
      await restored.restoreFloatingAnchor();
      expect(restored.floatingAnchor, const Offset(0, 1));
    },
  );

  test('floating anchor persists the explicit edge-hidden state', () async {
    final controller = AssistantPresentationController();
    addTearDown(controller.dispose);

    controller.updateFloatingAnchor(const Offset(1, 0.4), edgeHidden: true);
    await controller.persistFloatingAnchor();

    final restored = AssistantPresentationController();
    addTearDown(restored.dispose);
    await restored.restoreFloatingAnchor();
    expect(restored.floatingAnchor, const Offset(1, 0.4));
    expect(restored.floatingEdgeHidden, isTrue);
  });

  test('runtime status only marks successful background replies as unseen', () {
    final controller = AssistantPresentationController();
    addTearDown(controller.dispose);

    controller.synchronizeAssistantRuntime(
      owner: 'Student01',
      isLoggedIn: true,
      isSending: false,
      successfulReplyCount: 4,
    );
    controller.synchronizeAssistantRuntime(
      owner: 'student01',
      isLoggedIn: true,
      isSending: true,
      successfulReplyCount: 4,
    );
    expect(controller.isAssistantBusy, isTrue);

    controller.synchronizeAssistantRuntime(
      owner: 'student01',
      isLoggedIn: true,
      isSending: false,
      successfulReplyCount: 4,
    );
    expect(controller.isAssistantBusy, isFalse);
    expect(controller.hasUnseenCompletedReply, isFalse);

    controller.synchronizeAssistantRuntime(
      owner: 'student01',
      isLoggedIn: true,
      isSending: true,
      successfulReplyCount: 4,
    );
    controller.synchronizeAssistantRuntime(
      owner: 'student01',
      isLoggedIn: true,
      isSending: false,
      successfulReplyCount: 5,
    );
    expect(controller.hasUnseenCompletedReply, isTrue);

    controller.synchronizeAssistantRuntime(
      owner: 'student02',
      isLoggedIn: true,
      isSending: false,
      successfulReplyCount: 9,
    );
    expect(controller.isAssistantBusy, isFalse);
    expect(controller.hasUnseenCompletedReply, isFalse);
  });

  test('floating overlay suppression is nested and releases only once', () {
    final controller = AssistantPresentationController();
    addTearDown(controller.dispose);

    final releaseFirst = controller.suppressFloatingOverlay();
    final releaseSecond = controller.suppressFloatingOverlay();
    expect(controller.isFloatingOverlaySuppressed, isTrue);

    releaseFirst();
    expect(controller.isFloatingOverlaySuppressed, isTrue);
    releaseFirst();
    expect(controller.isFloatingOverlaySuppressed, isTrue);

    releaseSecond();
    expect(controller.isFloatingOverlaySuppressed, isFalse);
  });

  test(
    'runtime draft survives route collapse and clears on account change',
    () async {
      final controller = AssistantPresentationController();
      addTearDown(controller.dispose);
      final attachment = AssistantInputAttachment(
        name: 'diagram.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
        localFilePath: '/private/runtime-only/diagram.png',
      );

      controller.synchronizeAssistantRuntime(
        owner: 'student01',
        isLoggedIn: true,
        isSending: false,
        successfulReplyCount: 0,
      );
      final firstOwnerToken = controller.assistantDraftOwnerToken;
      controller.updateAssistantDraft(
        ownerToken: firstOwnerToken,
        text: '未发送的内容',
        attachments: [attachment],
      );

      expect(controller.assistantDraftText, '未发送的内容');
      expect(controller.assistantDraftAttachments.single, same(attachment));
      await controller.persistFloatingAnchor();
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().map((key) => preferences.get(key)).join('\n'),
        isNot(contains('/private/runtime-only/diagram.png')),
      );
      expect(
        preferences.getKeys().map((key) => preferences.get(key)).join('\n'),
        isNot(contains('未发送的内容')),
      );

      controller.synchronizeAssistantRuntime(
        owner: 'student02',
        isLoggedIn: true,
        isSending: false,
        successfulReplyCount: 0,
      );
      expect(controller.assistantDraftText, isEmpty);
      expect(controller.assistantDraftAttachments, isEmpty);

      controller.updateAssistantDraft(
        ownerToken: firstOwnerToken,
        text: '旧页面晚到内容',
        attachments: [attachment],
      );
      expect(controller.assistantDraftText, isEmpty);
      expect(controller.assistantDraftAttachments, isEmpty);
    },
  );
}
