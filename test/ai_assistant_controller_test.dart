import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/assistant_memory.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/timeline_detail_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/assistant/assistant_mail_content_reader.dart';
import 'package:bnbu_me/services/assistant_context_builder.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/assistant_location_service.dart';
import 'package:bnbu_me/services/mail_service_factory.dart';
import 'package:bnbu_me/services/ta_course_repository.dart';
import 'package:bnbu_me/state/ai_assistant_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assistant drops an owner when the school session ends', () async {
    SharedPreferences.setMockInitialValues({});
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    await harness.assistantController.initialize();
    expect(harness.assistantController.currentConversation, isNotNull);

    // The account name can outlive a session during logout or restoration.
    harness.sessionController.setAuthenticated(false);
    expect(harness.sessionController.username, 'student01');
    expect(harness.assistantController.currentConversation, isNull);
    await harness.assistantController.initialize();
    await harness.assistantController.send('Synthetic request');
    expect(harness.service.chatCalls, 0);
  });

  test(
    'completed reply records elapsed time and title generation never blocks it',
    () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 9, 8, 12);
      final service = _TitleService();
      final harness = _ControllerHarness(service: service, now: () => now);
      addTearDown(harness.dispose);
      await harness.assistantController.initialize();
      final sent = harness.assistantController.send(
        'Explain academic writing techniques.',
      );
      await service.chatStarted.future;
      now = now.add(const Duration(seconds: 75));
      await sent;
      expect(
        harness
            .assistantController
            .currentConversation!
            .messages
            .last
            .activities
            .last
            .label,
        '用时 75 秒',
      );
      expect(harness.assistantController.sending, isFalse);
      service.title.complete('本周各课程待交作业');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        harness.assistantController.currentConversation!.title,
        '本周各课程待交作业',
      );
      expect(service.calls, 1);
      harness.assistantController.selectConversation(
        harness.assistantController.currentConversation!.id,
      );
      expect(service.calls, 1);
    },
  );

  test(
    'iSpace follow-up target stays in its own conversation and account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final session = _FocusSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _FocusAgentService();
      final controller = AiAssistantController(
        sessionController: session,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();
      await controller.send('Read Q1 in C Language.');
      expect(controller.currentConversation!.messages.last.isError, isFalse);
      await controller.send('Please continue with the questions.');
      expect(service.messages.last, contains('"Q1"'));
      expect(service.messages.last, contains('"C Language"'));
      expect(service.messages.last, isNot(contains('m1:')));
      expect(
        controller.currentConversation!.messages
            .where((m) => m.isUser)
            .last
            .content,
        'Please continue with the questions.',
      );

      await controller.startNewConversation();
      await controller.send('Please continue with the questions.');
      expect(service.messages.last, 'Please continue with the questions.');
      session.switchOwner('synthetic-other');
      await controller.initialize();
      await controller.send('Please continue with the questions.');
      expect(service.messages.last, 'Please continue with the questions.');
    },
  );

  test(
    'explicit mail attachment does not inherit the previous iSpace target',
    () async {
      SharedPreferences.setMockInitialValues({});
      final session = _FocusSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _FocusAgentService();
      final reader = _SelectedMailReferenceReader();
      final controller = AiAssistantController(
        sessionController: session,
        coordinator: coordinator,
        service: service,
        historyStore: _MemoryHistoryStore(),
        mailContentReader: reader,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();
      await controller.send('Read Q1 in C Language.');
      expect(controller.currentConversation!.messages.last.isError, isFalse);
      await controller.send(
        'Please continue with the questions in this email.',
        attachments: [
          AssistantInputAttachment.mailReference(
            AssistantMailReference.message(
              folder: MailFolder.inbox.name,
              uid: 86,
              mailboxUidValidity: 1234,
              sender: 'teacher@bnbu.edu.cn',
              subject: 'Project feedback',
              receivedAt: DateTime.parse('2026-09-07T19:00:00+08:00'),
            ),
          ),
        ],
      );
      expect(controller.currentConversation!.messages.last.isError, isFalse);
      expect(reader.readCalls, 1);
      expect(
        service.lastChatMessage,
        'Please continue with the questions in this email.',
      );
    },
  );

  test('动作回执回到发起会话并且重复回调只保存一次', () async {
    final session = _CourseSessionController();
    final coordinator = AssistantContextCoordinator();
    final controller = AiAssistantController(
      sessionController: session,
      coordinator: coordinator,
      historyStore: _MemoryHistoryStore(),
      service: _FakeAssistantService(
        resultActions: const [
          AssistantAction(
            actionId: 'campus-calendar',
            type: AssistantActionType.openCampusPage,
            title: '打开校历',
            requiresConfirmation: false,
            targetId: 'academic_calendar',
            url: '',
            recipient: '',
            subject: '',
            body: '',
            placeQuery: '',
          ),
        ],
      ),
    );
    addTearDown(() {
      controller.dispose();
      coordinator.dispose();
      session.dispose();
    });
    await controller.initialize();
    await controller.send('打开校历');
    final origin = controller.currentConversation!;
    final action = origin.messages.last.actions.single.copyWith(
      subject: '用户在预览中编辑的主题',
    );
    controller.beginActionExecution(action);
    await controller.startNewConversation();
    await controller.recordActionOutcome(action, 'opened');
    await controller.recordActionOutcome(action, 'opened');
    expect(controller.currentConversation!.messages, isEmpty);
    final saved = controller.conversations.singleWhere(
      (item) => item.id == origin.id,
    );
    expect(
      saved.messages.where((message) => message.receiptKey.isNotEmpty).length,
      1,
    );
  });

  test('empty assistant state is not reported as sending', () async {
    final sessionController = AppSessionController();
    final controller = AiAssistantController(
      sessionController: sessionController,
      service: _FakeAssistantService(),
      coordinator: AssistantContextCoordinator(),
    );

    expect(controller.pendingTurn, isNull);
    expect(controller.currentConversationId, isNull);
    expect(controller.isSendingCurrentConversation, isFalse);

    await pumpEventQueue(times: 10);
    controller.dispose();
    sessionController.dispose();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'editable memories persist and synchronize through the account',
    () async {
      final service = _MemoryAssistantService();
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);

      await harness.assistantController.initialize();
      await harness.assistantController.addMemory('我更喜欢中文回答。');
      await pumpEventQueue(times: 20);

      expect(harness.assistantController.memories, hasLength(1));
      expect(harness.assistantController.memories.single.content, '我更喜欢中文回答。');
      expect(service.entries.single.content, '我更喜欢中文回答。');

      final id = harness.assistantController.memories.single.id;
      await harness.assistantController.updateMemory(id, '先给结论。');
      await pumpEventQueue(times: 20);
      expect(service.entries.single.content, '先给结论。');

      await harness.assistantController.deleteMemory(id);
      await pumpEventQueue(times: 20);
      expect(harness.assistantController.memories, isEmpty);
      expect(service.entries.single.deleted, isTrue);
    },
  );

  test('initial memory synchronization is exposed as pending', () async {
    final service = _DelayedMemoryAssistantService();
    final harness = _ControllerHarness(service: service);
    addTearDown(harness.dispose);

    final initialization = harness.assistantController.initialize();
    await pumpEventQueue(times: 10);

    expect(harness.assistantController.memoriesSyncAvailable, isTrue);
    expect(harness.assistantController.memoriesSyncing, isTrue);

    service.loaded.complete(
      const AssistantMemorySnapshot(version: 0, entries: []),
    );
    await initialization;

    expect(harness.assistantController.memoriesSyncing, isFalse);
    expect(harness.assistantController.memoriesSyncFailed, isFalse);
  });

  test(
    'assistant memory suggestions stay pending until saved and edited',
    () async {
      final service = _MemoryAssistantService(
        resultMemorySuggestions: const [
          AssistantMemorySuggestion(
            content: '用户倾向软件开发方向。',
            memoryType: 'persona',
            sourceId: 'mem-software-1',
          ),
        ],
      );
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);

      await harness.assistantController.initialize();
      await harness.assistantController.send('我的倾向是软件开发');

      final message =
          harness.assistantController.currentConversation!.messages.last;
      final suggestion = message.memorySuggestions.single;
      expect(harness.assistantController.memories, isEmpty);
      expect(suggestion.status, AssistantMemorySuggestionStatus.pending);

      await harness.assistantController.saveMemorySuggestion(
        message,
        suggestion,
        editedContent: '我长期倾向软件开发与系统工程。',
      );
      await pumpEventQueue(times: 20);

      expect(service.entries.single.content, '我长期倾向软件开发与系统工程。');
      expect(service.entries.single.memoryType, 'persona');
      expect(service.entries.single.sourceId, 'mem-software-1');
      expect(
        harness
            .assistantController
            .currentConversation!
            .messages
            .last
            .memorySuggestions
            .single
            .status,
        AssistantMemorySuggestionStatus.saved,
      );
    },
  );

  test(
    'study conversation stays isolated from the current general chat',
    () async {
      final harness = _ControllerHarness();
      addTearDown(harness.dispose);
      await harness.assistantController.initialize();
      final generalId = harness.assistantController.currentConversationId;
      const document = AssistantStudyDocument(
        key: 'lecture-01',
        title: 'Lecture 01.pdf',
        sourceUrl: 'https://ispace.example.edu/lecture-01.pdf',
      );
      final studyId = await harness.assistantController.ensureStudyConversation(
        document,
      );

      await harness.assistantController.send(
        '只依据第 3 页回答',
        visibleMessage: '这段代码为什么会循环？',
        conversationId: studyId,
        studyContext: const AssistantStudyMessageContext(
          type: AssistantStudyEntryType.question,
          pages: [3],
          scope: 'current_page',
        ),
      );

      expect(harness.assistantController.currentConversationId, generalId);
      expect(harness.assistantController.conversationHistory, isEmpty);
      expect(
        harness.assistantController.studyConversationHistory,
        hasLength(1),
      );
      final study = harness.assistantController.conversationById(studyId!);
      expect(study?.studyDocument?.title, 'Lecture 01.pdf');
      expect(study?.messages.first.content, '这段代码为什么会循环？');
      expect(study?.messages.last.studyContext?.pages, [3]);
    },
  );

  test(
    'study documents can keep multiple synchronized question sessions',
    () async {
      final harness = _ControllerHarness();
      addTearDown(harness.dispose);
      await harness.assistantController.initialize();
      const document = AssistantStudyDocument(
        key: 'lecture-multi',
        title: 'Lecture.pdf',
        sourceUrl: 'https://ispace.example.edu/lecture.pdf',
      );

      final firstId = await harness.assistantController.ensureStudyConversation(
        document,
      );
      await harness.assistantController.send(
        '第一页问题',
        conversationId: firstId,
        studyContext: const AssistantStudyMessageContext(
          type: AssistantStudyEntryType.question,
          pages: [1],
          scope: 'current_page',
        ),
      );
      final secondId = await harness.assistantController
          .createStudyConversation(document);

      expect(secondId, isNot(firstId));
      expect(
        harness.assistantController.studyConversationHistory,
        hasLength(1),
      );

      await harness.assistantController.send(
        '第二页问题',
        conversationId: secondId,
        studyContext: const AssistantStudyMessageContext(
          type: AssistantStudyEntryType.question,
          pages: [2],
          scope: 'current_page',
        ),
      );

      expect(
        harness.assistantController.studyConversationHistory,
        hasLength(2),
      );
      expect(
        harness.assistantController.studyConversationHistory
            .map((item) => item.id)
            .toSet(),
        {firstId, secondId},
      );
    },
  );

  test('network failures recover ten times with one stable request ID', () async {
    final harness = _ControllerHarness(
      service: _FakeAssistantService(networkFailuresBeforeSuccess: 10),
    );
    addTearDown(harness.dispose);
    final progress = <String>[];
    harness.assistantController.addListener(() {
      final value = harness.assistantController.pendingTurn?.progress;
      if (value != null) progress.add(value);
    });

    await harness.assistantController.initialize();
    await harness.assistantController.send('你好');

    expect(harness.service.chatCalls, 11);
    expect(harness.service.clientRequestIds.toSet(), hasLength(1));
    expect(
      harness.service.clientRequestIds.first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(progress, contains('重试中…10/10'));
    expect(
      harness.assistantController.currentConversation?.messages.last.content,
      '完成。',
    );
  });

  test('the eleventh network failure stops without another retry', () async {
    final harness = _ControllerHarness(
      service: _FakeAssistantService(networkFailuresBeforeSuccess: 11),
    );
    addTearDown(harness.dispose);

    await harness.assistantController.initialize();
    await harness.assistantController.send('你好');

    expect(harness.service.chatCalls, 11);
    expect(harness.assistantController.pendingTurn, isNull);
    expect(harness.assistantController.error, isNull);
    final failed =
        harness.assistantController.currentConversation!.messages.last;
    expect(failed.isError, isTrue);
    expect(failed.compactError, isTrue);
    expect(failed.content, isNot(contains('network_request_failed')));
    expect(
      failed.activities.map((item) => item.label).join('\n'),
      contains('network_request_failed · network'),
    );
    expect(failed.activities.last.failed, isTrue);
    expect(failed.canRetry, isTrue);
  });

  test('business failures are not retried', () async {
    final harness = _ControllerHarness(
      service: _FakeAssistantService(
        businessError: const AiAssistantException('配额或请求错误'),
      ),
    );
    addTearDown(harness.dispose);

    await harness.assistantController.initialize();
    await harness.assistantController.send('你好');

    expect(harness.service.chatCalls, 1);
    expect(harness.assistantController.error, isNull);
    expect(
      harness.assistantController.currentConversation?.messages.last.content,
      contains('配额或请求错误'),
    );
  });

  test('agent recovery exhaustion reports its bounded reason', () async {
    final harness = _ControllerHarness(
      service: _FakeAssistantService(
        businessError: const AiAssistantAgentRecoveryExhaustedException(
          '小U网络恢复已达到 3 分钟安全时限。',
        ),
      ),
    );
    addTearDown(harness.dispose);

    await harness.assistantController.initialize();
    await harness.assistantController.send('复杂问题');

    final failed =
        harness.assistantController.currentConversation!.messages.last;
    expect(failed.compactError, isTrue);
    expect(
      failed.activities.map((item) => item.label).join('\n'),
      contains('agent_network_recovery_exhausted · network'),
    );
    expect(failed.activities.last.label, contains('已保留这轮问题'));
  });

  test(
    'enrollment network failures are not retried as chat requests',
    () async {
      final harness = _ControllerHarness(
        service: _FakeAssistantService(
          businessError: const AiAssistantNetworkException('登记响应丢失'),
        ),
      );
      addTearDown(harness.dispose);

      await harness.assistantController.initialize();
      await harness.assistantController.send('你好');

      expect(harness.service.chatCalls, 1);
      expect(harness.assistantController.error, isNull);
      expect(
        harness
            .assistantController
            .currentConversation
            ?.messages
            .last
            .compactError,
        isTrue,
      );
    },
  );

  test(
    'typed 502 is stored inline with diagnostics and can be retried',
    () async {
      final service = _FakeAssistantService(
        businessError: const AiAssistantRemoteStatusException(
          '请求小U失败（HTTP 502）。',
          statusCode: 502,
          code: 'provider_connection_timeout',
          stage: 'provider_connect',
          retryPolicy: 'new_request',
        ),
      );
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);

      await harness.assistantController.initialize();
      await harness.assistantController.send('普通问题');

      final failed =
          harness.assistantController.currentConversation!.messages.last;
      expect(failed.isError, isTrue);
      expect(failed.compactError, isTrue);
      expect(failed.content, isNot(contains('HTTP 状态：`502`')));
      expect(
        failed.activities.map((item) => item.label).join('\n'),
        contains('provider_connection_timeout · provider_connect'),
      );

      service.businessError = null;
      await harness.assistantController.retryFailedMessage(failed);

      expect(service.chatCalls, 2);
      final messages =
          harness.assistantController.currentConversation?.messages ?? const [];
      expect(messages, hasLength(2));
      expect(messages.map((item) => item.role), ['user', 'assistant']);
      expect(messages.where((item) => item.isUser), hasLength(1));
      expect(messages.last.content, '完成。');
    },
  );

  test(
    'do_not_retry failure is inline without an unsafe retry action',
    () async {
      final harness = _ControllerHarness(
        service: _FakeAssistantService(
          businessError: const AiAssistantRemoteStatusException(
            '本次请求结果无法确认。',
            statusCode: 409,
            code: 'provider_outcome_ambiguous',
            stage: 'provider_request',
            retryPolicy: 'do_not_retry',
          ),
        ),
      );
      addTearDown(harness.dispose);

      await harness.assistantController.initialize();
      await harness.assistantController.send('普通问题');

      final failed =
          harness.assistantController.currentConversation!.messages.last;
      expect(failed.isError, isTrue);
      expect(failed.canRetry, isFalse);
      expect(failed.content, contains('请不要直接重复提交'));
    },
  );

  test('disabling during initialization cannot re-enable assistant', () async {
    final enabledResult = Completer<bool>();
    final service = _FakeAssistantService(isEnabledCompleter: enabledResult);
    final harness = _ControllerHarness(service: service);
    addTearDown(harness.dispose);

    final initialization = harness.assistantController.initialize();
    await service.isEnabledStarted.future;
    final disabling = harness.assistantController.disableAssistant();

    expect(harness.assistantController.loading, isFalse);
    expect(harness.assistantController.enabled, isFalse);

    enabledResult.complete(false);
    await Future.wait([initialization, disabling]);

    expect(service.setEnabledValues, [false]);
    expect(harness.assistantController.loading, isFalse);
    expect(harness.assistantController.enabled, isFalse);
  });

  test('late replies cannot cross account generations', () async {
    final response = Completer<AssistantChatResult>();
    final service = _FakeAssistantService(chatCompleter: response);
    final harness = _ControllerHarness(service: service);
    addTearDown(harness.dispose);

    await harness.assistantController.initialize();
    final sendFuture = harness.assistantController.send('后台继续回答');
    await service.chatStarted.future;

    harness.sessionController.switchOwner('student02');
    response.complete(_result('旧账号的晚到回复'));
    await sendFuture;

    expect(harness.assistantController.conversations, isEmpty);
    expect(harness.assistantController.pendingTurn, isNull);
    await harness.assistantController.initialize();
    expect(harness.assistantController.currentConversation?.messages, isEmpty);
  });

  test('different conversations can reply at the same time', () async {
    final firstReply = Completer<AssistantChatResult>();
    final secondReply = Completer<AssistantChatResult>();
    final service = _FakeAssistantService(
      chatCompleters: {'第一段对话': firstReply, '第二段对话': secondReply},
    );
    final harness = _ControllerHarness(service: service);
    addTearDown(harness.dispose);

    await harness.assistantController.initialize();
    final firstConversationId =
        harness.assistantController.currentConversationId!;
    final firstSend = harness.assistantController.send('第一段对话');
    await pumpEventQueue(times: 2);

    await harness.assistantController.startNewConversation();
    final secondConversationId =
        harness.assistantController.currentConversationId!;
    final secondSend = harness.assistantController.send('第二段对话');
    await pumpEventQueue(times: 2);

    expect(
      harness.assistantController.isConversationSending(firstConversationId),
      isTrue,
    );
    expect(
      harness.assistantController.isConversationSending(secondConversationId),
      isTrue,
    );

    secondReply.complete(_result('第二段完成'));
    await secondSend;
    expect(
      harness.assistantController.isConversationSending(secondConversationId),
      isFalse,
    );
    expect(
      harness.assistantController.conversations
          .singleWhere((item) => item.id == secondConversationId)
          .messages
          .last
          .content,
      '第二段完成',
    );

    firstReply.complete(_result('第一段完成'));
    await firstSend;
    expect(
      harness.assistantController.conversations
          .singleWhere((item) => item.id == firstConversationId)
          .messages
          .last
          .content,
      '第一段完成',
    );
    expect(harness.assistantController.sending, isFalse);
  });

  test(
    'repeated blank conversations stay as one transient placeholder',
    () async {
      final historyStore = _SerialHistoryStore();
      final harness = _ControllerHarness(historyStore: historyStore);
      addTearDown(harness.dispose);
      await harness.assistantController.initialize();

      await Future.wait([
        harness.assistantController.startNewConversation(),
        harness.assistantController.startNewConversation(),
        harness.assistantController.startNewConversation(),
      ]);

      expect(harness.assistantController.conversations, hasLength(1));
      expect(harness.assistantController.conversationHistory, isEmpty);
      expect(historyStore.saved, isEmpty);
    },
  );

  test(
    'schedule intent loads timetable before building chat context',
    () async {
      final session = _ScheduleSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        now: () => DateTime(2026, 7, 20, 8),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('我今天有什么课？');

      expect(session.ensureTimetableCalls, 1);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.schedule),
      );
      expect(service.lastContext?.schedule, hasLength(1));
      expect(
        service.lastContext?.schedule.single.courseName,
        'Software Engineering',
      );
    },
  );

  test(
    'legacy TA-only schedule waits for cold-start TA data before validation',
    () async {
      final readStarted = Completer<void>();
      final releaseRead = Completer<String?>();
      final store = _DeferredTaCourseStore(
        targetKey: TaCourseRepository.storageKeyForUsername('student01'),
        readStarted: readStarted,
        releaseRead: releaseRead,
      );
      final session = _TaOnlySessionController();
      final taCourses = TaCourseController(
        sessionController: session,
        repository: TaCourseRepository(store: store),
      );
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        taCourseController: taCourses,
        now: () => DateTime.utc(2026, 8, 9, 1),
      );
      addTearDown(() {
        if (!releaseRead.isCompleted) {
          releaseRead.complete(null);
        }
        controller.dispose();
        coordinator.dispose();
        taCourses.dispose();
        session.dispose();
      });
      await controller.initialize();
      await readStarted.future;

      final send = controller.send('我明天有什么安排？');
      await pumpEventQueue(times: 5);
      expect(service.chatCalls, 0);

      releaseRead.complete(
        jsonEncode({
          'version': 1,
          'revision': 1,
          'entries': [
            const TaCourseEntry(
              id: 'acceptance-ta',
              title: 'Acceptance TA',
              location: 'Acceptance Room',
              weekday: DateTime.monday,
              startMinutes: 10 * 60,
              endMinutes: 11 * 60,
              repeatType: TaCourseRepeatType.weekly,
              revision: 1,
            ).toJson(),
          ],
        }),
      );
      await send;

      expect(session.ensureTimetableCalls, 1);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.schedule),
      );
      expect(service.lastContext?.schedule, hasLength(1));
      expect(
        service.lastContext?.schedule.single.courseId,
        'schedule:acceptance-ta',
      );
      expect(
        service.lastContext?.schedule.single.courseName,
        '日程：Acceptance TA',
      );
      expect(service.lastContext?.schedule.single.room, 'Acceptance Room');
    },
  );

  test(
    'provider planning selects lazy schedule context before final chat',
    () async {
      final session = _ScheduleSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _PlanningAssistantService(
        plannedSources: const {AssistantContextSource.schedule},
      );
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        now: () => DateTime(2026, 7, 20, 8),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('帮我看看接下来怎么处理');

      expect(service.planCalls, 1);
      expect(service.chatCalls, 1);
      expect(session.ensureTimetableCalls, 1);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.schedule),
      );
      expect(service.lastContext?.schedule, hasLength(1));
    },
  );

  test(
    'agent can read recent mail bodies without opening the mail page',
    () async {
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _MailBodyAgentAssistantService();
      final mailReader = _FakeAssistantMailContentReader();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        mailContentReader: mailReader,
        now: () => DateTime.parse('2026-09-04T12:00:00+08:00'),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('帮我看看这两天老师回复的邮件内容');

      expect(mailReader.findCalls, 1);
      expect(service.agentCalls, 2);
      expect(service.receivedContext?.version, '5');
      expect(
        service
            .receivedContext
            ?.mailToolResults
            .single
            .messages
            .single
            .bodyText,
        'Please send the proposal before Friday.',
      );
      expect(
        controller.currentConversation?.messages.last.content,
        contains('Friday'),
      );
    },
  );

  test(
    'explicit mail reference reads the verified body, persists its typed identity, and never uploads a file',
    () async {
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final historyStore = _MemoryHistoryStore();
      final service = _SelectedMailReferenceAssistantService();
      final mailReader = _SelectedMailReferenceReader();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: historyStore,
        mailContentReader: mailReader,
        now: () => DateTime.parse('2026-09-07T20:00:00+08:00'),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();
      await controller.startFreshConversation();

      final reference = AssistantMailReference.message(
        folder: MailFolder.inbox.name,
        uid: 86,
        mailboxUidValidity: 1234,
        sender: 'teacher@bnbu.edu.cn',
        subject: 'Project feedback',
        receivedAt: DateTime.parse('2026-09-07T19:00:00+08:00'),
      );
      await controller.send(
        '请总结附件邮件。',
        attachments: [AssistantInputAttachment.mailReference(reference)],
      );

      expect(controller.error, isNull);
      expect(service.chatCalls, 1);
      expect(mailReader.readCalls, 1);
      expect(mailReader.lastIdentities, hasLength(1));
      expect(mailReader.lastIdentities.single.uid, 86);
      expect(
        service.lastContext?.mailToolResults.single.messages.single.bodyText,
        '这是一封经当前邮箱账号校验后读取的正文。',
      );
      final userMessage = controller.currentConversation!.messages.first;
      expect(userMessage.mailReferences, hasLength(1));
      expect(userMessage.mailReferences.single.uid, reference.uid);
      expect(
        userMessage.mailReferences.single.mailboxUidValidity,
        reference.mailboxUidValidity,
      );
      final persisted = await historyStore.load('student01');
      expect(persisted.single.messages.first.mailReferences, hasLength(1));
      expect(persisted.single.messages.first.mailReferences.single.uid, 86);
    },
  );

  test(
    'attachment-only user turns keep clean content and bounded metadata',
    () async {
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final historyStore = _MemoryHistoryStore();
      final service = _SelectedMailReferenceAssistantService();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: historyStore,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();
      final attachment = AssistantInputAttachment(
        name: 'campus.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await controller.send('', attachments: [attachment]);

      final userMessage = controller.currentConversation!.messages.first;
      expect(userMessage.content, isEmpty);
      expect(userMessage.attachmentReferences.single.name, 'campus.png');
      expect(
        userMessage.attachmentReferences.single.kind,
        AssistantAttachmentReferenceKind.image,
      );
      expect(userMessage.runtimeAttachments.single.bytes, [1, 2, 3]);
      expect(service.attachmentCalls.single.name, 'campus.png');
      final persisted = (await historyStore.load(
        'student01',
      )).single.messages.first;
      expect(persisted.content, isEmpty);
      expect(persisted.attachmentReferences.single.name, 'campus.png');
    },
  );

  test(
    'continued mail conversations bound re-read identities to the newest eight references',
    () async {
      final historyStore = _MemoryHistoryStore();
      final sentAt = DateTime.parse('2026-09-07T20:00:00+08:00');
      await historyStore.save('student01', [
        AssistantConversation(
          id: 'mail-reference-history',
          title: '邮件续问',
          createdAt: sentAt,
          updatedAt: sentAt,
          messages: List.generate(
            9,
            (index) => AssistantStoredMessage(
              role: 'user',
              content: '第 ${index + 1} 封邮件',
              createdAt: sentAt.add(Duration(minutes: index)),
              mailReferences: [
                AssistantMailReference.message(
                  folder: MailFolder.inbox.name,
                  uid: index + 1,
                  mailboxUidValidity: 1234,
                  sender: 'teacher@bnbu.edu.cn',
                  subject: 'Mail ${index + 1}',
                  receivedAt: sentAt.add(Duration(minutes: index)),
                ),
              ],
            ),
          ),
        ),
      ]);
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _SelectedMailReferenceAssistantService();
      final mailReader = _SelectedMailReferenceReader();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: historyStore,
        mailContentReader: mailReader,
        now: () => sentAt,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      controller.selectConversation('mail-reference-history');
      await controller.send('继续比较这些邮件。');

      expect(mailReader.readCalls, 1);
      expect(mailReader.lastIdentities, hasLength(8));
      expect(mailReader.lastIdentities.map((item) => item.uid), [
        9,
        8,
        7,
        6,
        5,
        4,
        3,
        2,
      ]);
      expect(
        service.lastContext?.mailToolResults.single.messages,
        hasLength(8),
      );
    },
  );

  test(
    'a long explicit compose draft uses a text payload alongside a verified received-mail context',
    () async {
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _SelectedMailReferenceAssistantService();
      final mailReader = _SelectedMailReferenceReader();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        mailContentReader: mailReader,
        now: () => DateTime.parse('2026-09-07T20:00:00+08:00'),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();
      await controller.startFreshConversation();
      final longBody = List<String>.filled(5000, '草').join();

      await controller.send(
        '请检查这封草稿是否适合回复附件邮件。',
        attachments: [
          AssistantInputAttachment.mailReference(
            AssistantMailReference.message(
              folder: MailFolder.inbox.name,
              uid: 87,
              mailboxUidValidity: 1234,
              sender: 'teacher@bnbu.edu.cn',
              subject: 'Project feedback',
              receivedAt: DateTime.parse('2026-09-07T19:00:00+08:00'),
            ),
          ),
          AssistantInputAttachment.mailReference(
            AssistantMailReference.draft(
              recipients: 'teacher@bnbu.edu.cn',
              subject: 'Re: Project feedback',
              body: longBody,
            ),
          ),
        ],
      );

      expect(controller.error, isNull);
      expect(mailReader.lastIdentities.single.uid, 87);
      expect(service.lastContext?.mailToolResults, hasLength(1));
      expect(service.attachmentCalls, hasLength(1));
      expect(service.attachmentCalls.single.mimeType, 'text/markdown');
      expect(
        utf8.decode(service.attachmentCalls.single.bytes),
        contains(longBody),
      );
      expect(service.attachmentCalls.single.bytes.length, greaterThan(5000));
      expect(
        controller.currentConversation!.messages.first.mailReferences,
        hasLength(2),
      );
    },
  );

  test(
    'selected received mail fails closed when the runtime lacks mail body capability',
    () async {
      final harness = _ControllerHarness();
      addTearDown(harness.dispose);
      await harness.assistantController.initialize();
      await harness.assistantController.startFreshConversation();

      await harness.assistantController.send(
        '请查看附件邮件。',
        attachments: [
          AssistantInputAttachment.mailReference(
            AssistantMailReference.message(
              folder: MailFolder.inbox.name,
              uid: 1,
              mailboxUidValidity: 2,
              sender: 'teacher@bnbu.edu.cn',
              subject: 'Capability check',
              receivedAt: DateTime.parse('2026-09-07T20:00:00+08:00'),
            ),
          ),
        ],
      );

      expect(harness.service.chatCalls, 0);
      expect(harness.assistantController.error, '当前小U服务暂不支持读取附加邮件。');
      expect(
        harness.assistantController.currentConversation?.messages,
        isEmpty,
      );
    },
  );

  test('fixed local navigation never calls planning or chat', () async {
    final session = _ScheduleSessionController();
    final coordinator = AssistantContextCoordinator();
    final service = _PlanningAssistantService(
      plannedSources: const {},
      plannedNavigation: const AssistantPlanNavigation(targetId: 'schedule'),
    );
    final controller = AiAssistantController(
      sessionController: session,
      service: service,
      coordinator: coordinator,
      historyStore: _MemoryHistoryStore(),
    );
    addTearDown(() {
      controller.dispose();
      coordinator.dispose();
      session.dispose();
    });
    await controller.initialize();

    await controller.send('打开课表。');

    expect(service.planCalls, 0);
    expect(service.chatCalls, 0);
    expect(session.ensureTimetableCalls, 0);
    final reply = controller.currentConversation!.messages.last;
    expect(reply.isError, isFalse);
    expect(reply.content, '已为你准备好打开课表。');
    expect(reply.actions.single.type, AssistantActionType.openAppTab);
    expect(reply.actions.single.targetId, 'schedule');
  });

  test(
    'provider-planned safe navigation skips data loading and chat',
    () async {
      final session = _ScheduleSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _PlanningAssistantService(
        plannedSources: const {},
        plannedNavigation: const AssistantPlanNavigation(targetId: 'schedule'),
      );
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('帮我切换到课表页面。');

      expect(service.planCalls, 1);
      expect(service.chatCalls, 0);
      expect(session.ensureTimetableCalls, 0);
      final reply = controller.currentConversation!.messages.last;
      expect(reply.isError, isFalse);
      expect(reply.content, '已为你准备好打开课表。');
      expect(reply.actions.single.type, AssistantActionType.openAppTab);
      expect(reply.actions.single.targetId, 'schedule');
    },
  );

  test(
    'transient AI planning failure never falls back to keyword tool selection',
    () async {
      final session = _ScheduleSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _PlanningAssistantService(
        plannedSources: const {},
        planningError: const AiAssistantRemoteStatusException(
          'provider DNS timeout',
          code: 'provider_destination_timeout',
          stage: 'provider_preflight',
          retryPolicy: 'new_request',
        ),
      );
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('我今天有什么课？');

      expect(service.planCalls, 1);
      expect(service.chatCalls, 0);
      expect(session.ensureTimetableCalls, 0);
      final failed = controller.currentConversation!.messages.last;
      expect(failed.isError, isTrue);
      expect(failed.compactError, isTrue);
      expect(
        failed.activities.map((item) => item.label).join('\n'),
        contains('provider_destination_timeout · provider_preflight'),
      );
      expect(failed.canRetry, isTrue);
    },
  );

  test(
    'provider cannot request location without explicit user location intent',
    () async {
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _PlanningAssistantService(
        plannedSources: const {AssistantContextSource.currentLocation},
      );
      final locationService = _RecordingLocationService();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        locationService: locationService,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('你好');

      expect(service.planCalls, 1);
      expect(locationService.calls, 0);
      expect(
        service.lastContext?.sources,
        isNot(contains(AssistantContextSource.currentLocation)),
      );
      expect(service.lastContext?.currentLocation, isNull);
    },
  );

  test(
    'provider planning lazily loads bounded iSpace course metadata',
    () async {
      final session = _CatalogSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _PlanningAssistantService(
        plannedSources: const {AssistantContextSource.ispaceCourseCatalog},
      );
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('C Language 的老师和课件有哪些？');

      final catalog = service.lastContext?.ispaceCourseCatalog;
      expect(catalog?.courses.single.courseId, '42');
      expect(catalog?.courses.single.teachers, ['Teacher Chen']);
      expect(session.contentLoads, 1);
      expect(session.teacherLoads, 1);
    },
  );

  test(
    'course actions stay bound to IDs sent in the request context',
    () async {
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService(
        resultActions: const [
          AssistantAction(
            actionId: 'pack-valid',
            type: AssistantActionType.prepareCoursePack,
            title: '准备课程资料',
            requiresConfirmation: true,
            targetId: '42',
            url: '',
            recipient: '',
            subject: '',
            body: '',
            placeQuery: '',
          ),
          AssistantAction(
            actionId: 'pack-guessed',
            type: AssistantActionType.prepareCoursePack,
            title: '错误课程资料',
            requiresConfirmation: true,
            targetId: 'C Language',
            url: '',
            recipient: '',
            subject: '',
            body: '',
            placeQuery: '',
          ),
        ],
      );
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();

      await controller.send('准备 C Language 的课程资料');

      expect(service.lastContext?.courses.single.courseId, '42');
      expect(
        controller.currentConversation?.messages.last.actions.map(
          (action) => action.actionId,
        ),
        ['pack-valid'],
      );
    },
  );

  test(
    'agent loop executes requested client tools before final answer',
    () async {
      final service = _AgentAssistantService();
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('我有哪些课程？');

      expect(service.agentCalls, 2);
      expect(service.chatCalls, 0);
      expect(service.receivedToolResults, hasLength(1));
      expect(
        service.receivedToolResults.single.context.courses.single.courseId,
        '42',
      );
      expect(
        controller.currentConversation?.messages.last.content,
        '你当前有 C Language。',
      );
    },
  );

  test(
    'pure catalog aggregates skip agent tool selection and finalize once',
    () async {
      final service = _PlanningAgentAssistantService(
        plannedSources: const {
          AssistantContextSource.ispaceCourseCatalog,
          AssistantContextSource.ispaceToolResults,
        },
        capabilitySources: const {
          'ispace_course_catalog',
          'ispace_tool_results',
        },
      );
      final session = _AssignmentSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('只依据当前目录聚合回答：Assignment 类型一共有多少个？');

      expect(service.agentCalls, 0);
      expect(service.chatCalls, 1);
      final catalog = service.lastContext?.ispaceCourseCatalog;
      expect(catalog, isNotNull);
      expect(catalog!.courses.single.sections, isEmpty);
      expect(catalog.courses.single.moduleTypeCounts, {'assignment': 1});
      expect(
        controller.lastIspaceCatalogDiagnostics?.detailLevel,
        AssistantIspaceCatalogDetailLevel.aggregates,
      );
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'natural manual completion inventory finalizes without agent selection',
    () async {
      final service = _PlanningAgentAssistantService(
        plannedSources: const {
          AssistantContextSource.ispaceCourseCatalog,
          AssistantContextSource.ispaceToolResults,
        },
        capabilitySources: const {
          'ispace_course_catalog',
          'ispace_tool_results',
        },
      );
      final session = _ManualCompletionSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('哪些东西需要我自己点完成？按课程列一下。');

      expect(service.planCalls, 1);
      expect(service.agentCalls, 0);
      expect(service.chatCalls, 1);
      final catalog = service.lastContext?.ispaceCourseCatalog;
      expect(catalog, isNotNull);
      expect(catalog!.courses.single.sections.single.modules, hasLength(1));
      expect(
        catalog.courses.single.sections.single.modules.single.canManualComplete,
        isTrue,
      );
      expect(
        controller.lastIspaceCatalogDiagnostics?.detailLevel,
        AssistantIspaceCatalogDetailLevel.modules,
      );
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'controller routes capability-negotiated v3 through the agent loop',
    () async {
      final service = _AgentAssistantService(
        agentProtocolVersion: 3,
        completeImmediately: true,
      );
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('今天有哪些课程？');

      expect(service.agentCalls, 1);
      expect(service.chatCalls, 0);
      expect(service.receivedProtocolVersions, [3]);
    },
  );

  test('agent receives only sources selected for the current intent', () async {
    final service = _AgentAssistantService(
      completeImmediately: true,
      capabilitySources: AssistantContextSource.values
          .map((source) => source.wireValue)
          .toSet(),
    );
    final session = _ScheduleDeadlineSessionController();
    final coordinator = AssistantContextCoordinator();
    final controller = AiAssistantController(
      sessionController: session,
      service: service,
      coordinator: coordinator,
      historyStore: _MemoryHistoryStore(),
    );
    addTearDown(() {
      controller.dispose();
      coordinator.dispose();
      session.dispose();
    });

    await controller.initialize();
    await controller.send('安排我今天的课程和 DDL');

    expect(service.initialAvailableSources, {
      AssistantContextSource.schedule,
      AssistantContextSource.deadlines,
      AssistantContextSource.academicCalendar,
      AssistantContextSource.examTimetable,
    });
    expect(service.agentCalls, 1);
  });

  test(
    'agent uses provider preflight sources without local keyword union',
    () async {
      final service = _PlanningAgentAssistantService(
        plannedSources: const {AssistantContextSource.ispaceCourseCatalog},
        plannedServerTools: const [
          AssistantPlannedServerTool(
            name: AssistantServerTool.officialDirectory,
            query: 'Teacher Example',
          ),
        ],
        capabilitySources: const {
          'courses',
          'term_courses',
          'ispace_course_catalog',
          'ispace_tool_results',
        },
      );
      final session = _CatalogSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('请概括课程“Data Analysis Workshop”的章节、模块和进度。');

      expect(service.planCalls, 1);
      expect(service.initialAvailableSources, {
        AssistantContextSource.ispaceCourseCatalog,
      });
      expect(
        service.initialPlannedServerTools?.single.name,
        AssistantServerTool.officialDirectory,
      );
      expect(service.agentCalls, 1);
    },
  );

  test(
    'high thinking effort persists and is used for every agent continuation',
    () async {
      final service = _AgentAssistantService(
        expectedThinkingMode: AssistantThinkingMode.high,
      );
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final thinkingModeStore = _MemoryThinkingModeStore();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        thinkingModeStore: thinkingModeStore,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.setThinkingMode(AssistantThinkingMode.high);
      await controller.send('我有哪些课程？');

      expect(controller.thinkingMode, AssistantThinkingMode.high);
      expect(thinkingModeStore.mode, AssistantThinkingMode.high);
      expect(service.receivedThinkingModes, [
        AssistantThinkingMode.high,
        AssistantThinkingMode.high,
      ]);
      expect(service.receivedMaxOutputTokens, [4096, 4096]);
    },
  );

  test('legacy v1 high effort negotiates the old 2000 token ceiling', () async {
    final service = _AgentAssistantService(
      expectedThinkingMode: AssistantThinkingMode.high,
      agentProtocolVersion: 1,
      agentMaxOutputTokens: 2000,
    );
    final session = _CourseSessionController();
    final coordinator = AssistantContextCoordinator();
    final controller = AiAssistantController(
      sessionController: session,
      service: service,
      coordinator: coordinator,
      historyStore: _MemoryHistoryStore(),
      thinkingModeStore: _MemoryThinkingModeStore(),
    );
    addTearDown(() {
      controller.dispose();
      coordinator.dispose();
      session.dispose();
    });

    await controller.initialize();
    await controller.setThinkingMode(AssistantThinkingMode.high);
    await controller.send('我有哪些课程？');

    expect(service.receivedMaxOutputTokens, [2000, 2000]);
  });

  test('high effort agent has no forced client round cap', () async {
    final service = _AgentAssistantService(
      expectedThinkingMode: AssistantThinkingMode.high,
      requiredRounds: 40,
    );
    final session = _CourseSessionController();
    final coordinator = AssistantContextCoordinator();
    final controller = AiAssistantController(
      sessionController: session,
      service: service,
      coordinator: coordinator,
      historyStore: _MemoryHistoryStore(),
      thinkingModeStore: _MemoryThinkingModeStore(),
    );
    addTearDown(() {
      controller.dispose();
      coordinator.dispose();
      session.dispose();
    });

    await controller.initialize();
    await controller.setThinkingMode(AssistantThinkingMode.high);
    await controller.send('我有哪些课程？');

    expect(service.agentCalls, 40);
    final answer = controller.currentConversation!.messages.last;
    expect(answer.isError, isFalse);
    expect(answer.activities, isNotEmpty);
    expect(
      answer.activities.map((item) => item.label).join(),
      isNot(contains('第')),
    );
    expect(
      answer.activities,
      contains(
        predicate<AssistantActivity>((item) {
          return item.label.contains('调用「课程概览」技能');
        }),
      ),
    );
  });

  test(
    'legacy step limit finalizes through chat with academic profile context',
    () async {
      final service = _AgentAssistantService(
        capabilitySources: const {'academic_profile'},
        agentError: const AiAssistantRemoteStatusException(
          'legacy limit',
          statusCode: 502,
          code: 'agent_step_limit',
          stage: 'agent_loop',
          retryPolicy: 'new_request',
        ),
      );
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('结合我的专业，哪个导师更适合我？');

      expect(service.agentCalls, 1);
      expect(service.chatCalls, 1);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.academicProfile),
      );
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'invalid provider output after a client tool finalizes from loaded evidence',
    () async {
      final service = _AgentAssistantService(
        agentError: const AiAssistantRemoteStatusException(
          'invalid provider output',
          statusCode: 502,
          code: 'provider_invalid_output',
          stage: 'provider_parse',
          retryPolicy: 'new_request',
        ),
        agentErrorCall: 2,
      );
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('我有哪些课程？');

      expect(service.agentCalls, 2);
      expect(service.chatCalls, 1);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.courses),
      );
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'invalid provider output before any client tool stays fail closed',
    () async {
      final service = _AgentAssistantService(
        agentError: const AiAssistantRemoteStatusException(
          'invalid provider output',
          statusCode: 502,
          code: 'provider_invalid_output',
          stage: 'provider_parse',
          retryPolicy: 'new_request',
        ),
      );
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('我有哪些课程？');

      expect(service.agentCalls, 1);
      expect(service.chatCalls, 0);
      expect(controller.currentConversation?.messages.last.isError, isTrue);
    },
  );

  test(
    'required-context error after the only course tool uses loaded evidence',
    () async {
      final service = _AgentAssistantService(
        agentError: const AiAssistantRemoteStatusException(
          'required context mismatch',
          statusCode: 502,
          code: 'agent_required_context_missing',
          stage: 'agent_loop',
          retryPolicy: 'new_request',
        ),
        agentErrorCall: 2,
      );
      final session = _CourseSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('我有哪些课程？');

      expect(service.agentCalls, 2);
      expect(service.chatCalls, 1);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.courses),
      );
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'required-context error loads every AI-planned no-argument source',
    () async {
      final service = _AgentAssistantService(
        capabilitySources: const {'schedule', 'deadlines'},
        agentError: const AiAssistantRemoteStatusException(
          'required context mismatch',
          statusCode: 502,
          code: 'agent_required_context_missing',
          stage: 'agent_loop',
          retryPolicy: 'new_request',
        ),
      );
      final session = _ScheduleDeadlineSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('今天明天要不要交东西？');

      expect(service.agentCalls, 1);
      expect(service.chatCalls, 1);
      expect(service.lastContext?.sources, {
        AssistantContextSource.schedule,
        AssistantContextSource.deadlines,
      });
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'required runtime error loads the unique assignment module before fallback',
    () async {
      final service = _AssignmentFallbackService();
      final session = _AssignmentSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('Project 1 是否是团队作业？检查 submission state 和是否仍可编辑。');

      expect(service.agentCalls, 2);
      expect(service.chatCalls, 1);
      expect(
        service.lastContext?.sources,
        contains(AssistantContextSource.ispaceToolResults),
      );
      final activity =
          service.lastContext?.ispaceToolResults.singleOrNull?.activity;
      expect(activity?.submissionStatus, 'new');
      expect(activity?.canEditSubmission, isTrue);
      expect(activity?.submissionsEnabled, isTrue);
      expect(activity?.submissionLocked, isFalse);
      expect(activity?.preventSubmissionNotInGroup, isTrue);
      expect(activity?.timeLimitSeconds, 0);
      expect(activity?.toJson()['max_submission_size_scope'], 'per_file');
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'required runtime error binds a quoted short manual completion module',
    () async {
      final service = _ManualCompletionFallbackService();
      final session = _ManualCompletionSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('请准备把“C Language”里的“Q1”标记为完成；先展示对象并等待确认。');

      expect(service.agentCalls, 2);
      expect(service.planCalls, 1);
      expect(service.chatCalls, 1);
      final module = service.lastContext?.ispaceToolResults.singleOrNull;
      expect(module?.name, 'Q1');
      expect(module?.moduleType, 'page');
      expect(module?.capabilities, contains('completion_manual_write'));
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'required catalog error loads locally planned catalog after deadlines',
    () async {
      final service = _AssignmentFallbackService(requestDeadlineFirst: true);
      final session = _AssignmentSessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();
      await controller.send('把当前事项分成必须尽快、可以稍后、只有资料没有 DDL 三组。');

      expect(service.agentCalls, 2);
      expect(service.chatCalls, 1);
      expect(service.lastContext?.sources, {
        AssistantContextSource.deadlines,
        AssistantContextSource.ispaceCourseCatalog,
      });
      expect(controller.currentConversation?.messages.last.isError, isFalse);
    },
  );

  test(
    'editing and regenerating create switchable conversation branches',
    () async {
      final fixedNow = DateTime.utc(2026, 8, 31, 12);
      final harness = _ControllerHarness(now: () => fixedNow);
      addTearDown(harness.dispose);
      await harness.assistantController.initialize();
      await harness.assistantController.send('原问题');

      final original = harness.assistantController.currentConversation!;
      await harness.assistantController.editUserMessage(
        original.messages.first,
        '改写后的问题',
      );

      expect(
        harness.assistantController.currentConversationBranches,
        hasLength(2),
      );
      expect(
        harness.assistantController.currentConversation!.messages.first.content,
        '改写后的问题',
      );
      harness.assistantController.selectBranch(0);
      expect(harness.assistantController.currentConversation?.id, original.id);

      final originalAssistant = original.messages.last;
      await harness.assistantController.regenerateAssistantMessage(
        originalAssistant,
      );

      expect(
        harness.assistantController.currentConversationBranches,
        hasLength(3),
      );
      expect(harness.service.chatCalls, 3);
      expect(
        harness.assistantController.currentConversation!.messages.first.content,
        '原问题',
      );
    },
  );

  test('assistant feedback is persisted and can be cleared', () async {
    final historyStore = _MemoryHistoryStore();
    final harness = _ControllerHarness(historyStore: historyStore);
    addTearDown(harness.dispose);
    await harness.assistantController.initialize();
    await harness.assistantController.send('需要反馈的回答');
    var assistant =
        harness.assistantController.currentConversation!.messages.last;

    await harness.assistantController.setMessageFeedback(
      assistant,
      AssistantMessageFeedback.up,
    );

    assistant = harness.assistantController.currentConversation!.messages.last;
    expect(assistant.feedback, AssistantMessageFeedback.up);
    expect(
      (await historyStore.load('student01')).first.messages.last.feedback,
      AssistantMessageFeedback.up,
    );

    await harness.assistantController.setMessageFeedback(assistant, null);
    expect(
      harness.assistantController.currentConversation!.messages.last.feedback,
      isNull,
    );
  });

  AssistantConversation syncedConversation(String id) {
    final now = DateTime.utc(2026, 9, 10);
    return AssistantConversation(
      id: id,
      title: id,
      createdAt: now,
      updatedAt: now,
      messages: [
        AssistantStoredMessage(role: 'user', content: id, createdAt: now),
      ],
    );
  }

  test(
    'sending from a cold draft respects the 36 conversation snapshot limit',
    () async {
      final service = _SyncAssistantService(
        List.generate(36, (i) => syncedConversation('remote-$i')),
      );
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);
      final controller = harness.assistantController;
      await controller.initialize();
      await pumpEventQueue();
      final draft = controller.currentConversationId;
      expect(controller.conversationHistory, hasLength(36));
      await controller.send('New local conversation');
      await pumpEventQueue();
      expect(controller.currentConversationId, draft);
      expect(controller.conversationHistory, hasLength(36));
      expect(service.remoteConversations, hasLength(36));
      expect(service.remoteConversations.map((c) => c.id), contains(draft));
    },
  );

  test(
    'slow history pull does not block initialization or select remote chat',
    () async {
      final gate = Completer<void>();
      final service = _SyncAssistantService([syncedConversation('remote')])
        ..loadGate = gate;
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);
      var initialized = false;
      final initialization = harness.assistantController.initialize().then(
        (_) => initialized = true,
      );
      await pumpEventQueue();
      expect(initialized, isTrue);
      final draft = harness.assistantController.currentConversationId;
      gate.complete();
      await initialization;
      await pumpEventQueue();
      expect(
        harness.assistantController.conversationHistory.single.id,
        'remote',
      );
      expect(harness.assistantController.currentConversationId, draft);
    },
  );

  test(
    'background polling works without opening assistant and respects lifecycle and disable',
    () async {
      final service = _SyncAssistantService([syncedConversation('remote')])
        ..enabled = true;
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);
      final controller = harness.assistantController;
      controller.startBackgroundSync(
        interval: const Duration(milliseconds: 20),
      );
      await pumpEventQueue();
      expect(controller.conversationHistory.single.id, 'remote');
      final draft = controller.currentConversationId;
      service.remoteConversations.add(syncedConversation('later'));
      service.version++;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await pumpEventQueue();
      expect(controller.conversationById('later'), isNotNull);
      expect(controller.currentConversationId, draft);
      controller.setForeground(false);
      final pausedCalls = service.loadCalls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.loadCalls, pausedCalls);
      controller.setForeground(true);
      await pumpEventQueue();
      expect(service.loadCalls, greaterThan(pausedCalls));
      await controller.disableAssistant();
      await pumpEventQueue();
      final disabledCalls = service.loadCalls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.loadCalls, disabledCalls);
      expect(service.enabled, isFalse);
    },
  );

  test(
    'pull merges live writes and keeps a newly selected empty draft',
    () async {
      final service = _SyncAssistantService([])..enabled = true;
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);
      final controller = harness.assistantController;
      await controller.initialize();
      await pumpEventQueue();
      service.remoteConversations = [syncedConversation('other-device')];
      service.version++;
      final gate = Completer<void>();
      service.loadGate = gate;
      await controller.refreshHistoryInBackground();
      await pumpEventQueue();
      await controller.send('Local message during pull');
      final local = controller.currentConversationId;
      await controller.startFreshConversation();
      final draft = controller.currentConversationId;
      gate.complete();
      await pumpEventQueue();
      expect(controller.currentConversationId, draft);
      expect(controller.currentConversation!.messages, isEmpty);
      expect(controller.conversationById(local!), isNotNull);
      expect(controller.conversationById('other-device'), isNotNull);
      expect(
        service.remoteConversations.map((c) => c.id),
        containsAll([local, 'other-device']),
      );
    },
  );

  test(
    'late pull cannot restore a conversation deleted while it was loading',
    () async {
      final service = _SyncAssistantService([syncedConversation('delete-me')])
        ..enabled = true;
      final harness = _ControllerHarness(service: service);
      addTearDown(harness.dispose);
      final controller = harness.assistantController;
      await controller.initialize();
      await pumpEventQueue();
      final gate = Completer<void>();
      service.loadGate = gate;
      await controller.refreshHistoryInBackground();
      await pumpEventQueue();
      await controller.deleteConversation('delete-me');
      gate.complete();
      await pumpEventQueue();
      expect(controller.conversationById('delete-me'), isNull);
      expect(service.remoteConversations, isEmpty);
    },
  );

  test('late history pull is isolated after account change', () async {
    final gate = Completer<void>();
    final service = _SyncAssistantService([syncedConversation('old-account')])
      ..loadGate = gate;
    final harness = _ControllerHarness(service: service);
    addTearDown(harness.dispose);
    final controller = harness.assistantController;
    await controller.initialize();
    harness.sessionController.switchOwner('student02');
    service.loadGate = null;
    service.remoteConversations = [syncedConversation('new-account')];
    await controller.initialize();
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();
    expect(controller.conversationById('old-account'), isNull);
    expect(controller.conversationHistory.single.id, 'new-account');
  });

  test('remote history appears only in the sidebar on cold start', () async {
    final now = DateTime.utc(2026, 9, 10);
    final service = _SyncAssistantService([
      AssistantConversation(
        id: 'remote-only',
        title: 'Other device',
        createdAt: now,
        updatedAt: now,
        messages: [
          AssistantStoredMessage(
            role: 'user',
            content: 'Other device',
            createdAt: now,
          ),
        ],
      ),
    ]);
    final harness = _ControllerHarness(service: service);
    addTearDown(harness.dispose);
    await harness.assistantController.initialize();
    await pumpEventQueue();
    expect(
      harness.assistantController.conversationHistory.single.id,
      'remote-only',
    );
    expect(harness.assistantController.currentConversation!.messages, isEmpty);
    expect(
      harness.assistantController.currentConversationId,
      isNot('remote-only'),
    );
  });

  test(
    'initial cross-device sync merges local and remote conversations',
    () async {
      final now = DateTime.utc(2026, 8, 2, 8);
      AssistantConversation conversation(String id, String content) =>
          AssistantConversation(
            id: id,
            title: content,
            createdAt: now,
            updatedAt: now,
            messages: [
              AssistantStoredMessage(
                role: 'user',
                content: content,
                createdAt: now,
              ),
            ],
          );
      final historyStore = _MemoryHistoryStore();
      await historyStore.save('student01', [conversation('local', '本机对话')]);
      final service = _SyncAssistantService([
        conversation('remote', '另一台设备的对话'),
      ]);
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: historyStore,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });

      await controller.initialize();

      await pumpEventQueue();
      expect(controller.conversationHistory.map((item) => item.id).toSet(), {
        'local',
        'remote',
      });
      expect(controller.currentConversation!.messages, isEmpty);
      expect(service.remoteConversations, hasLength(2));
      expect(service.version, 2);
    },
  );

  test(
    'remote history save does not block local chat and keeps latest snapshot',
    () async {
      final historyStore = _MemoryHistoryStore();
      final service = _SyncAssistantService(const []);
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: historyStore,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();
      final saveGate = Completer<void>();
      service.saveGate = saveGate;

      await controller.send('这条消息先保存在本机');

      expect(
        (await historyStore.load('student01')).single.messages.last.content,
        '完成。',
      );
      expect(service.saveCalls, greaterThanOrEqualTo(1));
      saveGate.complete();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
        if (service.remoteConversations.singleOrNull?.messages.last.content ==
            '完成。') {
          break;
        }
      }
      expect(service.remoteConversations.single.messages.last.content, '完成。');
    },
  );

  test(
    'history conflict cannot discard a newer pending conversation',
    () async {
      final pendingReply = Completer<AssistantChatResult>();
      final historyStore = _MemoryHistoryStore();
      final service = _SyncAssistantService(
        const [],
        chatCompleters: {'第二段并发对话': pendingReply},
      );
      final session = _SessionController();
      final coordinator = AssistantContextCoordinator();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: historyStore,
      );
      addTearDown(() {
        if (!pendingReply.isCompleted) {
          pendingReply.complete(_result('第二段完成'));
        }
        controller.dispose();
        coordinator.dispose();
        session.dispose();
      });
      await controller.initialize();
      final saveGate = Completer<void>();
      service.saveGate = saveGate;

      await controller.send('第一段已完成对话');
      while (service.saveCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.startNewConversation();
      final pendingConversationId = controller.currentConversationId!;
      final pendingTurn = controller.send(
        '第二段并发对话',
        conversationId: pendingConversationId,
      );
      while (!controller.isConversationSending(pendingConversationId)) {
        await Future<void>.delayed(Duration.zero);
      }

      service.version += 1;
      service.remoteConversations = [
        AssistantConversation(
          id: 'other-device',
          title: '另一台设备',
          createdAt: DateTime.utc(2026, 9, 4),
          updatedAt: DateTime.utc(2026, 9, 4),
          messages: [
            AssistantStoredMessage(
              role: 'user',
              content: '另一台设备的消息',
              createdAt: DateTime.utc(2026, 9, 4),
            ),
          ],
        ),
      ];
      saveGate.complete();
      for (var attempt = 0; attempt < 40; attempt++) {
        await Future<void>.delayed(Duration.zero);
        if (controller.conversationById('other-device') != null) break;
      }

      expect(controller.conversationById('other-device'), isNotNull);
      expect(controller.conversationById(pendingConversationId), isNotNull);
      expect(controller.isConversationSending(pendingConversationId), isTrue);

      pendingReply.complete(_result('第二段完成'));
      await pendingTurn;
      expect(
        controller
            .conversationById(pendingConversationId)
            ?.messages
            .last
            .content,
        '第二段完成',
      );
      expect(controller.isConversationSending(pendingConversationId), isFalse);
    },
  );

  test('divergent device replies are preserved as branches', () async {
    final startedAt = DateTime.utc(2026, 8, 2, 8);
    final user = AssistantStoredMessage(
      role: 'user',
      content: '同一个问题',
      createdAt: startedAt,
    );
    AssistantConversation conversation(String answer, DateTime updatedAt) =>
        AssistantConversation(
          id: 'shared-conversation',
          title: '同一个问题',
          createdAt: startedAt,
          updatedAt: updatedAt,
          messages: [
            user,
            AssistantStoredMessage(
              role: 'assistant',
              content: answer,
              createdAt: updatedAt,
            ),
          ],
        );
    final historyStore = _MemoryHistoryStore();
    await historyStore.save('student01', [
      conversation('本机回答', startedAt.add(const Duration(minutes: 2))),
    ]);
    final service = _SyncAssistantService([
      conversation('远端回答', startedAt.add(const Duration(minutes: 1))),
    ]);
    final session = _SessionController();
    final coordinator = AssistantContextCoordinator();
    final controller = AiAssistantController(
      sessionController: session,
      service: service,
      coordinator: coordinator,
      historyStore: historyStore,
    );
    addTearDown(() {
      controller.dispose();
      coordinator.dispose();
      session.dispose();
    });

    await controller.initialize();

    await pumpEventQueue();
    controller.selectConversation('shared-conversation');
    final answers = controller.conversationHistory
        .map((item) => item.messages.last.content)
        .toSet();
    expect(answers, {'本机回答', '远端回答'});
    expect(controller.currentConversationBranches, hasLength(2));
  });
}

class _ControllerHarness {
  _ControllerHarness({
    _FakeAssistantService? service,
    AssistantHistoryStore? historyStore,
    DateTime Function()? now,
  }) : sessionController = _SessionController(),
       coordinator = AssistantContextCoordinator(),
       service = service ?? _FakeAssistantService() {
    assistantController = AiAssistantController(
      sessionController: sessionController,
      service: this.service,
      coordinator: coordinator,
      historyStore: historyStore ?? _MemoryHistoryStore(),
      now: now,
    );
  }

  final _SessionController sessionController;
  final AssistantContextCoordinator coordinator;
  final _FakeAssistantService service;
  late final AiAssistantController assistantController;

  void dispose() {
    assistantController.dispose();
    coordinator.dispose();
    sessionController.dispose();
  }
}

class _SessionController extends AppSessionController {
  String? _owner = 'student01';
  bool _authenticated = true;

  @override
  bool get isLoggedIn => _authenticated && _owner != null;

  @override
  String? get username => _owner;

  void switchOwner(String? value) {
    _owner = value;
    notifyListeners();
  }

  void setAuthenticated(bool value) {
    _authenticated = value;
    notifyListeners();
  }
}

class _CourseSessionController extends AppSessionController {
  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  MoodleRuntimeProfile get moodleRuntimeProfile => _testRuntimeProfile();

  @override
  List<CourseSummary> get courses => [
    CourseSummary(
      id: 42,
      fullName: 'C Language',
      shortName: 'COMP1001',
      categoryName: 'Computing',
      progress: 50,
    ),
  ];

  @override
  TimetableData? get timetable => TimetableData(
    profile: TimetableProfile(
      studentId: 'student01',
      name: 'Test Student',
      programme: 'Test Programme',
      year: '2026',
    ),
    semesters: const [],
    selectedSemesterId: '2026-summer',
    selectedSemesterName: 'Summer 2026',
    courses: [
      TimetableCourse(
        section: '1',
        category: 'Lecture',
        code: 'COMP1001',
        name: 'C Language',
        teacher: 'Test Teacher',
        meetings: [
          TimetableMeeting(
            weekday: DateTime.monday,
            dayLabel: 'Mon',
            startLabel: '09:00',
            endLabel: '09:50',
            startMinutes: 9 * 60,
            endMinutes: 9 * 60 + 50,
            room: 'T2-101',
          ),
        ],
        rooms: const ['T2-101'],
        units: '3',
        remark: '',
      ),
    ],
  );

  @override
  Future<void> ensureTimetableLoaded() async {}

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    return const [];
  }

  @override
  Future<List<String>> loadCourseTeacherNames(int courseId) async {
    return const [];
  }
}

class _CatalogSessionController extends _CourseSessionController {
  int contentLoads = 0;
  int teacherLoads = 0;

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    contentLoads++;
    return [
      CourseContentSection(
        id: 1,
        sectionNum: 1,
        name: 'Week 1',
        summary: '',
        modules: const [],
      ),
    ];
  }

  @override
  Future<List<String>> loadCourseTeacherNames(int courseId) async {
    teacherLoads++;
    return const ['Teacher Chen'];
  }
}

class _ManualCompletionSessionController extends _CourseSessionController {
  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async => [
    CourseContentSection(
      id: 1,
      sectionNum: 1,
      name: 'Activities',
      summary: '',
      modules: [
        CourseModule(
          id: 101,
          instance: 201,
          name: 'Q1',
          modName: 'page',
          url: 'https://ispace.example/mod/page/view.php?id=101',
          iconUrl: '',
          descriptionHtml: '',
          contents: const [],
          dates: const [],
          completionTracking: 1,
          completionData: const CourseModuleCompletionData(
            state: 0,
            timeCompletedEpoch: 0,
            overrideBy: 0,
            valueUsed: false,
            hasCompletion: true,
            isAutomatic: false,
            isTrackedUser: true,
            userVisible: true,
          ),
        ),
      ],
    ),
  ];
}

class _AssignmentSessionController extends _CourseSessionController {
  @override
  List<CourseSummary> get courses => [
    CourseSummary(
      id: 84,
      fullName: 'Database Management Systems',
      shortName: 'COMP3013 26F',
      categoryName: 'Computing',
      progress: 0,
    ),
  ];

  @override
  List<TimelineItem> get timelineItems => [
    TimelineItem(
      id: 501,
      title: 'Project 1',
      activityState: 'Due',
      activityType: 'assign',
      moduleName: 'assign',
      description: '',
      courseName: 'Database Management Systems',
      courseId: 84,
      instanceId: 201,
      url: 'https://ispace.example/mod/assign/view.php?id=101',
      sortTime: DateTime.utc(2026, 8, 9, 16),
      formattedTime: '',
      isOverdue: false,
    ),
  ];

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async => [
    CourseContentSection(
      id: 1,
      sectionNum: 1,
      name: 'Assignments',
      summary: '',
      modules: [
        CourseModule(
          id: 101,
          instance: 201,
          name: 'Project 1',
          modName: 'assign',
          url: 'https://ispace.example/mod/assign/view.php?id=101',
          iconUrl: '',
          descriptionHtml: '',
          contents: const [],
          dates: const [],
        ),
      ],
    ),
  ];

  @override
  Future<TimelineDetailData> loadTimelineDetail(TimelineItem item) async =>
      TimelineDetailData(
        item: item,
        type: TimelineDetailType.assignment,
        assignmentId: 201,
        assignmentName: 'Project 1',
        submissionStatus: 'new',
        canEditSubmission: true,
        supportsFileSubmission: true,
        maxFileSubmissions: 1,
        maxSubmissionSizeBytes: 1048576,
        submissionDrafts: true,
        requiresSubmissionStatement: true,
        preventSubmissionNotInGroup: true,
        timeLimitSeconds: 0,
        submissionsEnabled: true,
        submissionLocked: false,
        canFinalizeSubmission: true,
      );
}

class _ScheduleDeadlineSessionController extends _CourseSessionController {
  @override
  List<TimelineItem> get timelineItems => [
    TimelineItem(
      id: 89055,
      title: 'Step 4: Post-tutorial Quiz',
      activityState: 'Due',
      activityType: 'quiz',
      moduleName: 'quiz',
      description: '',
      courseName: 'Academic Integrity Online Tutorial',
      courseId: 42,
      instanceId: 90210,
      url: 'https://ispace.example/mod/quiz/view.php?id=270762',
      sortTime: DateTime.utc(2026, 8, 31, 9),
      formattedTime: '',
      isOverdue: false,
    ),
  ];
}

class _ScheduleSessionController extends AppSessionController {
  TimetableData? _loadedTimetable;
  int ensureTimetableCalls = 0;

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  TimetableData? get timetable => _loadedTimetable;

  @override
  Future<void> ensureTimetableLoaded() async {
    ensureTimetableCalls++;
    _loadedTimetable = TimetableData(
      profile: TimetableProfile(
        studentId: 'student01',
        name: 'Test Student',
        programme: 'Test Programme',
        year: '2026',
      ),
      semesters: const [],
      selectedSemesterId: '2026-summer',
      selectedSemesterName: 'Summer 2026',
      courses: [
        TimetableCourse(
          section: '1',
          category: 'Lecture',
          code: 'COMP1001',
          name: 'Software Engineering',
          teacher: 'Test Teacher',
          meetings: [
            TimetableMeeting(
              weekday: DateTime.monday,
              dayLabel: 'Mon',
              startLabel: '09:00',
              endLabel: '09:50',
              startMinutes: 9 * 60,
              endMinutes: 9 * 60 + 50,
              room: 'T2-101',
            ),
          ],
          rooms: const ['T2-101'],
          units: '3',
          remark: '',
        ),
      ],
    );
  }
}

class _TaOnlySessionController extends AppSessionController {
  int ensureTimetableCalls = 0;

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  TimetableData? get timetable => null;

  @override
  Future<void> ensureTimetableLoaded() async {
    ensureTimetableCalls += 1;
  }
}

class _DeferredTaCourseStore implements TaCoursePreferencesStore {
  _DeferredTaCourseStore({
    required this.targetKey,
    required this.readStarted,
    required this.releaseRead,
  });

  final String targetKey;
  final Completer<void> readStarted;
  final Completer<String?> releaseRead;

  @override
  Future<String?> getString(String key) {
    if (key == targetKey) {
      if (!readStarted.isCompleted) {
        readStarted.complete();
      }
      return releaseRead.future;
    }
    return Future.value(null);
  }

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<bool> setString(String key, String value) async => true;
}

class _FakeAssistantService implements AiAssistantService {
  _FakeAssistantService({
    this.networkFailuresBeforeSuccess = 0,
    this.businessError,
    this.chatCompleter,
    this.chatCompleters = const {},
    this.resultActions = const [],
    this.resultMemorySuggestions = const [],
    this.isEnabledCompleter,
  });

  final int networkFailuresBeforeSuccess;
  AiAssistantException? businessError;
  final Completer<AssistantChatResult>? chatCompleter;
  final Map<String, Completer<AssistantChatResult>> chatCompleters;
  final List<AssistantAction> resultActions;
  final List<AssistantMemorySuggestion> resultMemorySuggestions;
  final Completer<bool>? isEnabledCompleter;
  final Completer<void> chatStarted = Completer<void>();
  final Completer<void> isEnabledStarted = Completer<void>();
  final List<bool> setEnabledValues = [];
  bool enabled = true;
  int chatCalls = 0;
  final List<String> clientRequestIds = [];
  AssistantContextPayload? lastContext;
  String? lastChatMessage;

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
    chatCalls++;
    lastChatMessage = message;
    clientRequestIds.add(clientRequestId ?? '');
    lastContext = context;
    if (!chatStarted.isCompleted) chatStarted.complete();
    if (businessError != null) throw businessError!;
    while (chatCalls <= networkFailuresBeforeSuccess) {
      onProgress?.call(
        AiAssistantRemoteProgress(
          code: 'network_recovery',
          stage: 'status_reconciliation',
          retryPolicy: 'check_status',
          networkRecoveryAttempt: chatCalls.clamp(1, 10),
          maxNetworkRecoveries: 10,
        ),
      );
      if (chatCalls >= 11) {
        throw const AiAssistantChatNetworkException('test network failure');
      }
      chatCalls++;
      clientRequestIds.add(clientRequestId ?? '');
    }
    final conversationReply = chatCompleters[message];
    if (conversationReply != null) return conversationReply.future;
    if (chatCompleter != null) return chatCompleter!.future;
    return _result(
      '完成。',
      actions: resultActions,
      memorySuggestions: resultMemorySuggestions,
    );
  }

  @override
  void dispose() {}

  @override
  Future<bool> isEnabled(String username) async {
    if (!isEnabledStarted.isCompleted) {
      isEnabledStarted.complete();
    }
    return isEnabledCompleter?.future ?? enabled;
  }

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    return const AssistantCapabilities(
      available: true,
      model: 'test-model',
      contextSources: {
        'courses',
        'term_courses',
        'ispace_course_catalog',
        'deadlines',
        'schedule',
        'mail_summaries',
        'selected_mail',
        'school_activities',
        'current_page',
        'current_location',
      },
      actions: {
        'compose_email',
        'submit_assignment',
        'open_page',
        'open_assignment',
        'open_course',
        'open_mail',
        'prepare_course_pack',
        'open_app_tab',
      },
      storesConversationContent: false,
      purchaseApiAvailable: false,
    );
  }

  @override
  Future<AssistantQuota> loadQuota(String username) async => _quota();

  @override
  Future<void> setEnabled(String username, bool enabled) async {
    setEnabledValues.add(enabled);
    this.enabled = enabled;
  }
}

class _SyncAssistantService extends _FakeAssistantService
    implements AiAssistantHistorySyncService {
  _SyncAssistantService(
    List<AssistantConversation> conversations, {
    super.chatCompleters = const {},
  }) : remoteConversations = List.of(conversations);

  int version = 1;
  List<AssistantConversation> remoteConversations;
  Completer<void>? saveGate;
  int saveCalls = 0;
  int loadCalls = 0;
  Completer<void>? loadGate;

  @override
  Future<AssistantHistorySnapshot> loadHistory(String username) async {
    loadCalls++;
    final snapshot = AssistantHistorySnapshot(
      version: version,
      conversations: List.of(remoteConversations),
      updatedAt: DateTime.utc(2026, 8, 2),
    );
    await loadGate?.future;
    return snapshot;
  }

  @override
  Future<AssistantHistorySnapshot> saveHistory(
    String username, {
    required int expectedVersion,
    required List<AssistantConversation> conversations,
  }) async {
    saveCalls++;
    await saveGate?.future;
    if (expectedVersion != version) {
      throw AiAssistantHistoryConflictException(currentVersion: version);
    }
    version++;
    remoteConversations = List.of(conversations);
    return AssistantHistorySnapshot(
      version: version,
      conversations: List.of(remoteConversations),
      updatedAt: DateTime.utc(2026, 8, 2),
    );
  }
}

class _PlanningAssistantService extends _FakeAssistantService
    implements AiAssistantPlanningService {
  _PlanningAssistantService({
    required this.plannedSources,
    this.plannedNavigation,
    this.planningError,
  });

  final Set<AssistantContextSource> plannedSources;
  final AssistantPlanNavigation? plannedNavigation;
  final Object? planningError;
  int planCalls = 0;

  @override
  Future<AssistantContextPlan> planContext({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required Set<AssistantContextSource> availableSources,
    required Set<AssistantActionType> availableActions,
    String? clientRequestId,
    bool Function()? isOperationActive,
  }) async {
    planCalls++;
    if (planningError case final error?) {
      throw error;
    }
    expect(plannedSources.difference(availableSources), isEmpty);
    return AssistantContextPlan(
      requestId: 'planning-request-id',
      sources: plannedSources,
      navigation: plannedNavigation,
      usage: const AssistantTokenUsage(
        inputTokens: 10,
        outputTokens: 2,
        totalTokens: 12,
      ),
      quota: _quota(remaining: 9988),
    );
  }
}

class _MailBodyAgentAssistantService extends _FakeAssistantService
    implements AiAssistantPlanningService, AiAssistantAgentService {
  int agentCalls = 0;
  AssistantContextPayload? receivedContext;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    return const AssistantCapabilities(
      available: true,
      model: 'mail-test-model',
      contextVersion: '5',
      supportedContextVersions: {'5'},
      agentProtocolVersion: 3,
      agentPlanningRequired: false,
      contextSources: {'mail_tool_results'},
      actions: {},
      storesConversationContent: false,
      purchaseApiAvailable: false,
    );
  }

  @override
  Future<AssistantContextPlan> planContext({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required Set<AssistantContextSource> availableSources,
    required Set<AssistantActionType> availableActions,
    String? clientRequestId,
    bool Function()? isOperationActive,
  }) async {
    throw StateError('context v5 must skip the standalone planning request');
  }

  @override
  Future<AssistantAgentTurnResult> runAgentTurn({
    required String username,
    required String conversationId,
    required String clientRequestId,
    String message = '',
    List<AssistantConversationMessage> history = const [],
    Set<AssistantContextSource> availableSources = const {},
    Set<AssistantActionType> availableActions = const {},
    List<AssistantPlannedServerTool> plannedServerTools = const [],
    String continuationToken = '',
    List<AssistantAgentToolResult> toolResults = const [],
    AssistantThinkingMode thinkingMode = AssistantThinkingMode.medium,
    int agentProtocolVersion = 2,
    bool sourcesPreplanned = true,
    int maxOutputTokens = 1800,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    agentCalls++;
    if (agentCalls == 1) {
      expect(
        availableSources,
        contains(AssistantContextSource.mailToolResults),
      );
      expect(sourcesPreplanned, isFalse);
      return AssistantAgentTurnResult(
        requestId: clientRequestId,
        conversationId: conversationId,
        round: 1,
        toolCalls: const [
          AssistantAgentToolCall(
            callId: 'mail-search',
            name: 'find_mail_messages',
            arguments: {
              'query': '',
              'sender': '',
              'folders': ['inbox'],
              'lookback_days': 2,
              'official_senders_only': true,
              'limit': 4,
              'include_body': true,
            },
          ),
        ],
        continuationToken: 'mail-continuation',
        chatResult: null,
        usage: const AssistantTokenUsage(
          inputTokens: 2,
          outputTokens: 1,
          totalTokens: 3,
        ),
        quota: _quota(remaining: 9997),
      );
    }
    receivedContext = toolResults.single.context;
    return AssistantAgentTurnResult(
      requestId: clientRequestId,
      conversationId: conversationId,
      round: 2,
      toolCalls: const [],
      continuationToken: '',
      chatResult: _result('老师请你在 Friday 前发送 proposal。'),
      usage: const AssistantTokenUsage(
        inputTokens: 5,
        outputTokens: 3,
        totalTokens: 8,
      ),
      quota: _quota(remaining: 9989),
    );
  }
}

class _FakeAssistantMailContentReader extends AssistantMailContentReader {
  _FakeAssistantMailContentReader()
    : super(
        credentialsLoader: () async => null,
        mailService: createMailService(),
        now: () => DateTime.parse('2026-09-04T12:00:00+08:00'),
      );

  int findCalls = 0;

  @override
  Future<AssistantMailToolResultContext> findMessages(
    AssistantMailSearchRequest request, {
    int protocolVersion = 2,
  }) async {
    findCalls++;
    expect(request.lookbackDays, 2);
    expect(request.officialSendersOnly, isTrue);
    expect(request.includeBody, isTrue);
    return AssistantMailToolResultContext(
      resultKey: 'mail-search:${'a' * 64}',
      kind: 'mail_search',
      observedAt: DateTime.parse('2026-09-04T12:00:00+08:00'),
      completeness: 'complete',
      messages: [
        AssistantMailMessageContext(
          uid: 17,
          folder: MailFolder.inbox.name,
          mailboxUidValidity: 9001,
          senderName: 'Teacher',
          senderEmail: 'teacher@bnbu.edu.cn',
          recipients: 'student@mail.bnbu.edu.cn',
          cc: '',
          subject: 'Research reply',
          receivedAt: DateTime.parse('2026-09-04T10:00:00+08:00'),
          bodyText: 'Please send the proposal before Friday.',
          contentState: 'complete',
        ),
      ],
    );
  }
}

class _SelectedMailReferenceAssistantService extends _FakeAssistantService
    implements AiAssistantAttachmentService {
  List<AssistantInputAttachment> attachmentCalls = const [];

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    return const AssistantCapabilities(
      available: true,
      model: 'selected-mail-reference-test',
      contextSources: {'mail_tool_results'},
      actions: {},
      storesConversationContent: false,
      purchaseApiAvailable: false,
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
  }) {
    attachmentCalls = List.unmodifiable(attachments);
    return chat(
      username: username,
      message: message,
      history: history,
      context: context,
      clientRequestId: clientRequestId,
      isOperationActive: isOperationActive,
      onProgress: onProgress,
    );
  }
}

class _SelectedMailReferenceReader extends AssistantMailContentReader {
  _SelectedMailReferenceReader()
    : super(
        credentialsLoader: () async => null,
        mailService: createMailService(),
        now: () => DateTime.parse('2026-09-07T20:00:00+08:00'),
      );

  int readCalls = 0;
  List<MailMessageIdentity> lastIdentities = const [];

  @override
  Future<AssistantMailToolResultContext> readMessages(
    List<MailMessageIdentity> identities, {
    int bodyOffset = 0,
    int protocolVersion = 2,
  }) async {
    readCalls += 1;
    lastIdentities = List.unmodifiable(identities);
    return AssistantMailToolResultContext(
      resultKey: 'selected-mail-reference',
      kind: 'mail_messages',
      observedAt: DateTime.parse('2026-09-07T20:00:00+08:00'),
      completeness: 'complete',
      messages: identities
          .map(
            (identity) => AssistantMailMessageContext(
              uid: identity.uid,
              folder: identity.folder.name,
              mailboxUidValidity: identity.mailboxUidValidity,
              senderName: 'Teacher',
              senderEmail: 'teacher@bnbu.edu.cn',
              recipients: 'student@mail.bnbu.edu.cn',
              cc: '',
              subject: 'Project feedback',
              receivedAt: DateTime.parse('2026-09-07T19:00:00+08:00'),
              bodyText: '这是一封经当前邮箱账号校验后读取的正文。',
              contentState: 'complete',
            ),
          )
          .toList(growable: false),
    );
  }
}

class _FocusSessionController extends _ManualCompletionSessionController {
  String _currentOwner = 'student01';
  @override
  String? get username => _currentOwner;
  void switchOwner(String owner) {
    _currentOwner = owner;
    notifyListeners();
  }
}

class _FocusAgentService extends _AgentAssistantService {
  final messages = <String>[];
  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async =>
      const AssistantCapabilities(
        available: true,
        model: 'synthetic',
        contextVersion: '5',
        supportedContextVersions: {'5'},
        agentProtocolVersion: 2,
        agentPlanningRequired: false,
        contextSources: {
          'ispace_course_catalog',
          'ispace_tool_results',
          'mail_tool_results',
        },
        actions: {},
        storesConversationContent: false,
        purchaseApiAvailable: false,
      );

  @override
  Future<AssistantAgentTurnResult> runAgentTurn({
    required String username,
    required String conversationId,
    required String clientRequestId,
    String message = '',
    List<AssistantConversationMessage> history = const [],
    Set<AssistantContextSource> availableSources = const {},
    Set<AssistantActionType> availableActions = const {},
    List<AssistantPlannedServerTool> plannedServerTools = const [],
    String continuationToken = '',
    List<AssistantAgentToolResult> toolResults = const [],
    AssistantThinkingMode thinkingMode = AssistantThinkingMode.medium,
    int agentProtocolVersion = 2,
    bool sourcesPreplanned = true,
    int maxOutputTokens = 1800,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    if (continuationToken.isEmpty) messages.add(message);
    return AssistantAgentTurnResult(
      requestId: clientRequestId,
      conversationId: conversationId,
      round: continuationToken.isEmpty ? 1 : 2,
      toolCalls: continuationToken.isEmpty
          ? [
              AssistantAgentToolCall(
                callId: 'focus-${messages.length}',
                name: 'get_ispace_module',
                arguments: const {'module_ref': 'm1:42:101:201:page'},
              ),
            ]
          : const [],
      continuationToken: continuationToken.isEmpty ? 'synthetic-focus' : '',
      chatResult: continuationToken.isEmpty
          ? null
          : _result('Read Q1 in C Language.'),
      usage: const AssistantTokenUsage(
        inputTokens: 1,
        outputTokens: 1,
        totalTokens: 2,
      ),
      quota: _quota(),
    );
  }
}

class _AgentAssistantService extends _FakeAssistantService
    implements AiAssistantAgentService {
  _AgentAssistantService({
    this.expectedThinkingMode = AssistantThinkingMode.low,
    this.requiredRounds = 2,
    this.completeImmediately = false,
    this.capabilitySources = const {'courses'},
    this.agentError,
    this.agentErrorCall = 1,
    this.agentProtocolVersion = 2,
    this.agentMaxOutputTokens = 4096,
  });

  final AssistantThinkingMode expectedThinkingMode;
  final int requiredRounds;
  final bool completeImmediately;
  final Set<String> capabilitySources;
  final AiAssistantRemoteStatusException? agentError;
  final int agentErrorCall;
  final int agentProtocolVersion;
  final int agentMaxOutputTokens;
  int agentCalls = 0;
  List<AssistantAgentToolResult> receivedToolResults = const [];
  final List<AssistantThinkingMode> receivedThinkingModes = [];
  final List<int> receivedMaxOutputTokens = [];
  final List<int> receivedProtocolVersions = [];
  Set<AssistantContextSource>? initialAvailableSources;
  List<AssistantPlannedServerTool>? initialPlannedServerTools;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    return AssistantCapabilities(
      available: true,
      model: 'test-agent-model',
      agentProtocolVersion: agentProtocolVersion,
      agentMaxOutputTokens: agentMaxOutputTokens,
      agentExecutionBudgetSeconds: 480,
      agentTotalTokenBudget: 120000,
      contextSources: capabilitySources,
      actions: const {'open_course'},
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
  Future<AssistantAgentTurnResult> runAgentTurn({
    required String username,
    required String conversationId,
    required String clientRequestId,
    String message = '',
    List<AssistantConversationMessage> history = const [],
    Set<AssistantContextSource> availableSources = const {},
    Set<AssistantActionType> availableActions = const {},
    List<AssistantPlannedServerTool> plannedServerTools = const [],
    String continuationToken = '',
    List<AssistantAgentToolResult> toolResults = const [],
    AssistantThinkingMode thinkingMode = AssistantThinkingMode.low,
    int agentProtocolVersion = 2,
    bool sourcesPreplanned = true,
    int maxOutputTokens = 1800,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    agentCalls++;
    final configuredAgentError = agentError;
    if (agentCalls == agentErrorCall && configuredAgentError != null) {
      throw configuredAgentError;
    }
    receivedThinkingModes.add(thinkingMode);
    receivedMaxOutputTokens.add(maxOutputTokens);
    receivedProtocolVersions.add(agentProtocolVersion);
    if (agentCalls == 1) {
      initialAvailableSources = availableSources;
      initialPlannedServerTools = plannedServerTools;
      if (completeImmediately) {
        return AssistantAgentTurnResult(
          requestId: clientRequestId,
          conversationId: conversationId,
          round: 1,
          toolCalls: const [],
          continuationToken: '',
          chatResult: _result('已整理今天的课程和 DDL。'),
          usage: const AssistantTokenUsage(
            inputTokens: 10,
            outputTokens: 2,
            totalTokens: 12,
          ),
          quota: _quota(remaining: 9988),
        );
      }
      expect(message, '我有哪些课程？');
      expect(availableSources, contains(AssistantContextSource.courses));
      expect(thinkingMode, expectedThinkingMode);
      return AssistantAgentTurnResult(
        requestId: clientRequestId,
        conversationId: conversationId,
        round: 1,
        toolCalls: const [
          AssistantAgentToolCall(
            callId: 'call_courses_1',
            name: 'get_courses',
            arguments: {},
          ),
        ],
        continuationToken: 'continuation',
        chatResult: null,
        usage: const AssistantTokenUsage(
          inputTokens: 10,
          outputTokens: 2,
          totalTokens: 12,
        ),
        quota: _quota(remaining: 9988),
      );
    }
    expect(continuationToken, 'continuation');
    expect(thinkingMode, expectedThinkingMode);
    receivedToolResults = toolResults;
    if (agentCalls < requiredRounds) {
      return AssistantAgentTurnResult(
        requestId: clientRequestId,
        conversationId: conversationId,
        round: agentCalls,
        toolCalls: [
          AssistantAgentToolCall(
            callId: 'call_courses_$agentCalls',
            name: 'get_courses',
            arguments: const {},
          ),
        ],
        continuationToken: 'continuation',
        chatResult: null,
        usage: const AssistantTokenUsage(
          inputTokens: 10,
          outputTokens: 2,
          totalTokens: 12,
        ),
        quota: _quota(remaining: 9988),
      );
    }
    return AssistantAgentTurnResult(
      requestId: clientRequestId,
      conversationId: conversationId,
      round: agentCalls,
      toolCalls: const [],
      continuationToken: '',
      chatResult: _result('你当前有 C Language。'),
      usage: const AssistantTokenUsage(
        inputTokens: 20,
        outputTokens: 5,
        totalTokens: 25,
      ),
      quota: _quota(remaining: 9963),
    );
  }
}

class _PlanningAgentAssistantService extends _AgentAssistantService
    implements AiAssistantPlanningService {
  _PlanningAgentAssistantService({
    required this.plannedSources,
    required super.capabilitySources,
    this.plannedServerTools = const [],
  }) : super(completeImmediately: true);

  final Set<AssistantContextSource> plannedSources;
  final List<AssistantPlannedServerTool> plannedServerTools;
  int planCalls = 0;

  @override
  Future<AssistantContextPlan> planContext({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required Set<AssistantContextSource> availableSources,
    required Set<AssistantActionType> availableActions,
    String? clientRequestId,
    bool Function()? isOperationActive,
  }) async {
    planCalls++;
    expect(plannedSources.difference(availableSources), isEmpty);
    return AssistantContextPlan(
      requestId: clientRequestId ?? 'planning-agent-request-id',
      sources: plannedSources,
      serverTools: plannedServerTools,
      usage: const AssistantTokenUsage(
        inputTokens: 10,
        outputTokens: 2,
        totalTokens: 12,
      ),
      quota: _quota(remaining: 9988),
    );
  }
}

class _AssignmentFallbackService extends _FakeAssistantService
    implements AiAssistantAgentService {
  _AssignmentFallbackService({this.requestDeadlineFirst = false});

  final bool requestDeadlineFirst;
  int agentCalls = 0;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    return const AssistantCapabilities(
      available: true,
      model: 'test-agent-model',
      contextVersion: '4',
      supportedContextVersions: {'4'},
      agentProtocolVersion: 3,
      agentMaxOutputTokens: 4096,
      agentExecutionBudgetSeconds: 480,
      agentTotalTokenBudget: 120000,
      contextSources: {
        'ispace_course_catalog',
        'ispace_tool_results',
        'deadlines',
      },
      actions: {},
      thinkingModes: {
        AssistantThinkingMode.low,
        AssistantThinkingMode.medium,
        AssistantThinkingMode.high,
      },
      storesConversationContent: false,
      purchaseApiAvailable: false,
    );
  }

  @override
  Future<AssistantAgentTurnResult> runAgentTurn({
    required String username,
    required String conversationId,
    required String clientRequestId,
    String message = '',
    List<AssistantConversationMessage> history = const [],
    Set<AssistantContextSource> availableSources = const {},
    Set<AssistantActionType> availableActions = const {},
    List<AssistantPlannedServerTool> plannedServerTools = const [],
    String continuationToken = '',
    List<AssistantAgentToolResult> toolResults = const [],
    AssistantThinkingMode thinkingMode = AssistantThinkingMode.medium,
    int agentProtocolVersion = 2,
    bool sourcesPreplanned = true,
    int maxOutputTokens = 1800,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    agentCalls++;
    if (agentCalls == 1) {
      expect(
        availableSources,
        contains(AssistantContextSource.ispaceCourseCatalog),
      );
      expect(
        availableSources,
        contains(AssistantContextSource.ispaceToolResults),
      );
      return AssistantAgentTurnResult(
        requestId: clientRequestId,
        conversationId: conversationId,
        round: 1,
        toolCalls: [
          AssistantAgentToolCall(
            callId: requestDeadlineFirst ? 'deadlines-first' : 'catalog-lab1',
            name: requestDeadlineFirst
                ? 'get_deadlines'
                : 'search_ispace_course_catalog',
            arguments: requestDeadlineFirst
                ? const {}
                : {'query': message, 'include_details': true},
          ),
        ],
        continuationToken: 'assignment-continuation',
        chatResult: null,
        usage: const AssistantTokenUsage(
          inputTokens: 10,
          outputTokens: 2,
          totalTokens: 12,
        ),
        quota: _quota(remaining: 9988),
      );
    }
    throw const AiAssistantRemoteStatusException(
      'required runtime context missing',
      statusCode: 502,
      code: 'agent_required_context_missing',
      stage: 'agent_loop',
      retryPolicy: 'new_request',
    );
  }
}

class _ManualCompletionFallbackService extends _AssignmentFallbackService
    implements AiAssistantPlanningService {
  int planCalls = 0;

  @override
  Future<AssistantContextPlan> planContext({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required Set<AssistantContextSource> availableSources,
    required Set<AssistantActionType> availableActions,
    String? clientRequestId,
    bool Function()? isOperationActive,
  }) async {
    planCalls++;
    const selected = {
      AssistantContextSource.ispaceCourseCatalog,
      AssistantContextSource.ispaceToolResults,
    };
    expect(selected.difference(availableSources), isEmpty);
    return AssistantContextPlan(
      requestId: clientRequestId ?? 'manual-completion-plan',
      sources: selected,
      usage: const AssistantTokenUsage(
        inputTokens: 4,
        outputTokens: 2,
        totalTokens: 6,
      ),
      quota: _quota(remaining: 9994),
    );
  }
}

class _RecordingLocationService implements AssistantLocationService {
  int calls = 0;

  @override
  Future<AssistantCurrentLocationContext> currentLocation() async {
    calls++;
    return AssistantCurrentLocationContext(
      latitude: 22.35,
      longitude: 113.54,
      accuracyMeters: 10,
      observedAt: DateTime.utc(2026, 7, 20, 8),
    );
  }
}

class _MemoryHistoryStore implements AssistantHistoryStore {
  final Map<String, List<AssistantConversation>> _values = {};

  @override
  Future<List<AssistantConversation>> load(String username) async {
    return List.of(_values[username] ?? const []);
  }

  @override
  Future<void> save(
    String username,
    List<AssistantConversation> conversations,
  ) async {
    _values[username] = List.of(conversations);
  }
}

class _MemoryThinkingModeStore implements AssistantThinkingModeStore {
  AssistantThinkingMode mode = AssistantThinkingMode.low;

  @override
  Future<AssistantThinkingMode> load(String username) async => mode;

  @override
  Future<void> save(String username, AssistantThinkingMode mode) async {
    this.mode = mode;
  }
}

class _SerialHistoryStore implements AssistantHistoryStore {
  int activeSaves = 0;
  int maxActiveSaves = 0;
  final List<List<AssistantConversation>> saved = [];

  @override
  Future<List<AssistantConversation>> load(String username) async => const [];

  @override
  Future<void> save(
    String username,
    List<AssistantConversation> conversations,
  ) async {
    activeSaves++;
    if (activeSaves > maxActiveSaves) maxActiveSaves = activeSaves;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    saved.add(List.of(conversations));
    activeSaves--;
  }
}

AssistantChatResult _result(
  String answer, {
  List<AssistantAction> actions = const [],
  List<AssistantMemorySuggestion> memorySuggestions = const [],
}) {
  return AssistantChatResult(
    requestId: 'request-id',
    answer: answer,
    actions: actions,
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

class _MemoryAssistantService extends _FakeAssistantService
    implements AiAssistantMemorySyncService {
  _MemoryAssistantService({super.resultMemorySuggestions});

  int version = 0;
  List<AssistantMemoryEntry> entries = const [];

  @override
  Future<AssistantMemorySnapshot> loadMemories(String username) async {
    return AssistantMemorySnapshot(version: version, entries: entries);
  }

  @override
  Future<AssistantMemorySnapshot> saveMemories(
    String username, {
    required int expectedVersion,
    required List<AssistantMemoryEntry> entries,
  }) async {
    if (expectedVersion != version) {
      throw AiAssistantMemoryConflictException(currentVersion: version);
    }
    version++;
    this.entries = List.unmodifiable(entries);
    return AssistantMemorySnapshot(version: version, entries: this.entries);
  }
}

class _DelayedMemoryAssistantService extends _FakeAssistantService
    implements AiAssistantMemorySyncService {
  final loaded = Completer<AssistantMemorySnapshot>();

  @override
  Future<AssistantMemorySnapshot> loadMemories(String username) =>
      loaded.future;

  @override
  Future<AssistantMemorySnapshot> saveMemories(
    String username, {
    required int expectedVersion,
    required List<AssistantMemoryEntry> entries,
  }) async {
    return AssistantMemorySnapshot(
      version: expectedVersion + 1,
      entries: entries,
    );
  }
}

MoodleRuntimeProfile _testRuntimeProfile() => MoodleRuntimeProfile(
  release: 'test',
  version: 'test',
  functionVersions: {
    for (final function in const [
      'core_enrol_get_users_courses',
      'core_course_get_contents',
      'core_course_get_course_module',
      'core_files_get_files',
      'core_files_get_unused_draft_itemid',
      'core_completion_get_activities_completion_status',
      'core_completion_update_activity_completion_status_manually',
      'mod_assign_get_assignments',
      'mod_assign_get_submission_status',
      'mod_assign_save_submission',
      'mod_assign_submit_for_grading',
      'mod_quiz_get_quizzes_by_courses',
      'mod_quiz_get_user_attempts',
      'mod_quiz_get_quiz_access_information',
      'mod_quiz_get_attempt_access_information',
      'mod_quiz_get_attempt_data',
    ])
      function: 'test',
  },
  downloadFiles: true,
  uploadFiles: true,
  advancedFeatures: const {'enablecompletion': 1},
  userMaxUploadFileSize: 1048576,
);

class _TitleService extends _FakeAssistantService
    implements AiAssistantTitleService {
  final title = Completer<String?>();
  int calls = 0;
  @override
  Future<String?> summarizeConversationTitle({
    required String username,
    required String firstMessage,
    required String requestId,
    required bool Function() isOperationActive,
  }) {
    calls++;
    expect(RegExp(r'^[a-f0-9-]{36}$').hasMatch(requestId), isTrue);
    return title.future;
  }
}
