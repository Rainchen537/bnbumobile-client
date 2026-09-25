import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../config/app_config.dart';
import '../models/assistant_models.dart';
import '../pages/ai_assistant_page.dart';
import '../state/ai_assistant_controller.dart';
import '../state/app_session_controller.dart';
import '../state/assistant_presentation_controller.dart';
import '../state/mail_assistant_intent_controller.dart';
import '../state/root_shell_controller.dart';
import '../state/ta_course_controller.dart';
import '../widgets/bnbu_notice.dart';
import 'ai_assistant_action_executor.dart';
import 'assistant_history_store.dart';
import 'study_window_manager.dart';
import 'mail_service.dart';

class AppNavigationCoordinator {
  AppNavigationCoordinator({
    required GlobalKey<NavigatorState> navigatorKey,
    required AppSessionController sessionController,
    required AiAssistantController assistantController,
    required AssistantPresentationController assistantPresentationController,
    required TaCourseController taCourseController,
    required RootShellController rootShellController,
    required MailAssistantIntentController mailIntentController,
    MailService Function()? mailServiceFactory,
  }) : _navigatorKey = navigatorKey,
       _sessionController = sessionController,
       _assistantController = assistantController,
       _assistantPresentationController = assistantPresentationController,
       _actionExecutor = AiAssistantActionExecutor(
         navigatorKey: navigatorKey,
         controller: sessionController,
         onActionOutcome: (action, status) =>
             unawaited(assistantController.recordActionOutcome(action, status)),
         mailServiceFactory: mailServiceFactory,
         beforeNavigation: assistantPresentationController.dismissAssistant,
         taCourseController: taCourseController,
         rootShellController: rootShellController,
         mailIntentController: mailIntentController,
       ) {
    _lastSessionOwner = _normalizedSessionOwner;
    _sessionController.addListener(_handleSessionChanged);
    _assistantController.addListener(_handleAssistantChanged);
    _synchronizeAssistantPresentationState();
  }

  final GlobalKey<NavigatorState> _navigatorKey;
  final AppSessionController _sessionController;
  final AiAssistantController _assistantController;
  final AssistantPresentationController _assistantPresentationController;
  final AiAssistantActionExecutor _actionExecutor;
  String? _lastSessionOwner;
  String? _trackedAssistantOperationId;
  String? _trackedAssistantConversationId;
  int _trackedAssistantReplyBaseline = 0;
  int _successfulReplyRevision = 0;

  String? get _normalizedSessionOwner {
    final value = _sessionController.username?.trim().toLowerCase() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> openAssistant() async {
    return _presentAssistant();
  }

  /// Opens a new 小U draft with a typed mail reference.  This never converts
  /// the mail into an uploaded file and does not send a prompt on the user's
  /// behalf.
  Future<void> openAssistantWithMailReference(
    AssistantMailReference reference,
  ) async {
    final ownerBeforeInitialization = _normalizedSessionOwner;
    if (!_sessionController.isLoggedIn || ownerBeforeInitialization == null) {
      return;
    }
    await _assistantController.initialize();
    // Initialization can asynchronously restore a different account's local
    // history after logout/re-login. Never attach the current user's mail to
    // a conversation that was initialized for another owner.
    if (!_sessionController.isLoggedIn ||
        ownerBeforeInitialization != _normalizedSessionOwner) {
      return;
    }
    await _assistantController.startFreshConversation();
    await _presentAssistant(
      initialAttachments: [AssistantInputAttachment.mailReference(reference)],
    );
  }

  Future<void> _presentAssistant({
    List<AssistantInputAttachment> initialAttachments = const [],
  }) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    await _assistantPresentationController.presentAssistant(
      navigator: navigator,
      routeBuilder: () => AssistantPageRoute(
        settings: const RouteSettings(name: 'ai-assistant'),
        builder: (_) => AiAssistantPage(
          assistantController: _assistantController,
          onExecuteAction: executeAssistantAction,
          onOpenStudyDocument: openStudyDocument,
          initialAttachments: initialAttachments,
        ),
      ),
    );
  }

  Future<void> openStudyDocument(AssistantStudyDocument document) async {
    if (!AppConfig.studyModeEnabled) return;
    await dismissAssistant();
    if (!StudyWindowManager.supported) return;
    try {
      await StudyWindowManager.open(document);
    } catch (_) {
      final context = _navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('学业窗口暂时无法打开，请重试。')));
      }
    }
  }

  Future<void> executeAssistantAction(
    AssistantAction action, {
    required bool userConfirmed,
  }) {
    _assistantController.beginActionExecution(action);
    return _actionExecutor.execute(action, userConfirmed: userConfirmed);
  }

  Future<void> dismissAssistant() {
    return _assistantPresentationController.dismissAssistant();
  }

  void _handleSessionChanged() {
    final owner = _normalizedSessionOwner;
    final ownerChanged = owner != _lastSessionOwner;
    _lastSessionOwner = owner;
    _synchronizeAssistantPresentationState();
    if (!_sessionController.isLoggedIn || ownerChanged) {
      unawaited(dismissAssistant());
    }
  }

  void _handleAssistantChanged() {
    _synchronizeAssistantPresentationState();
    if (!_assistantController.enabled &&
        !_assistantController.requiresMeBinding) {
      unawaited(dismissAssistant());
    }
  }

  void _synchronizeAssistantPresentationState() {
    final pendingTurn = _assistantController.pendingTurn;
    if (pendingTurn != null &&
        pendingTurn.operationId != _trackedAssistantOperationId) {
      _trackedAssistantOperationId = pendingTurn.operationId;
      _trackedAssistantConversationId = pendingTurn.conversationId;
      _trackedAssistantReplyBaseline = _assistantReplyCount(
        pendingTurn.conversationId,
      );
    } else if (pendingTurn == null && _trackedAssistantOperationId != null) {
      final conversationId = _trackedAssistantConversationId;
      if (conversationId != null &&
          _assistantReplyCount(conversationId) >
              _trackedAssistantReplyBaseline) {
        _successfulReplyRevision += 1;
      }
      _trackedAssistantOperationId = null;
      _trackedAssistantConversationId = null;
      _trackedAssistantReplyBaseline = 0;
    }
    _assistantPresentationController.synchronizeAssistantRuntime(
      owner: _normalizedSessionOwner,
      isLoggedIn: _sessionController.isLoggedIn,
      isSending: _assistantController.sending,
      successfulReplyCount: _successfulReplyRevision,
    );
  }

  int _assistantReplyCount(String conversationId) {
    for (final conversation in _assistantController.conversations) {
      if (conversation.id == conversationId) {
        return conversation.messages
            .where((message) => message.role == 'assistant')
            .length;
      }
    }
    return 0;
  }

  void dispose() {
    _assistantController.removeListener(_handleAssistantChanged);
    _sessionController.removeListener(_handleSessionChanged);
  }
}

/// Android 保留系统返回；其他平台继续通过明确的退出操作收起小U。
class AssistantPageRoute extends MaterialPageRoute<void> {
  AssistantPageRoute({required super.builder, super.settings});

  @override
  bool get popGestureEnabled =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      super.popGestureEnabled;
}
