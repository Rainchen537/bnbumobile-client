import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_memory.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/assistant_memory_store.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'package:bnbu_me/services/small_u_acceptance_bridge.dart';
import 'package:bnbu_me/state/ai_assistant_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';

void main() {
  test('acceptance burst ceiling represents eighty independent clients', () {
    expect(smallUAcceptanceMaxConcurrentTurns, 80);
  });

  test('bridge config requires a test gate and a safe absolute path', () {
    final argumentDiscoveryPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}bridge.json';
    final environmentDiscoveryPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'from-environment.json';
    expect(
      SmallUAcceptanceBridgeConfig.fromArguments([
        '--small-u-acceptance-bridge=$argumentDiscoveryPath',
      ]),
      isNull,
    );
    expect(
      SmallUAcceptanceBridgeConfig.fromArguments([
        '--small-u-acceptance-bridge=relative.json',
      ], enabled: true),
      isNull,
    );
    final config = SmallUAcceptanceBridgeConfig.fromArguments(
      ['--small-u-acceptance-bridge=$argumentDiscoveryPath'],
      enabled: true,
      environment: const {},
    );
    expect(config?.discoveryFile.path, argumentDiscoveryPath);
    final environmentConfig = SmallUAcceptanceBridgeConfig.fromArguments(
      const [],
      enabled: true,
      environment: {
        'SMALL_U_ACCEPTANCE_DISCOVERY_FILE': environmentDiscoveryPath,
      },
    );
    expect(environmentConfig?.discoveryFile.path, environmentDiscoveryPath);
    final defaultConfig = SmallUAcceptanceBridgeConfig.fromArguments(
      const [],
      enabled: true,
      environment: const {},
    );
    expect(
      defaultConfig?.discoveryFile.path,
      '${Directory.systemTemp.path}${Platform.pathSeparator}bnbu-small-u-acceptance.json',
    );
    final runtimeGatedConfig = SmallUAcceptanceBridgeConfig.fromArguments(
      const [],
      environment: const {'SMALL_U_ACCEPTANCE_BRIDGE_ENABLED': '1'},
    );
    expect(
      runtimeGatedConfig?.discoveryFile.path,
      '${Directory.systemTemp.path}${Platform.pathSeparator}bnbu-small-u-acceptance.json',
    );
  });

  test(
    'loopback bridge requires its token and deletes discovery on close',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'small_u_acceptance_bridge_test.',
      );
      final discovery = File('${directory.path}/bridge.json');
      final prompts = <String>[];
      final bridge = SmallUAcceptanceBridge(
        config: SmallUAcceptanceBridgeConfig(discoveryFile: discovery),
        statusHandler: () => {'logged_in': true},
        auditHandler: () async => {'schema_version': 1, 'courses': const []},
        turnHandler: (request) async {
          prompts.add(request.prompt);
          return {
            'answer': '完成：${request.prompt}',
            'conversation_id': 'conversation-1',
          };
        },
      );
      addTearDown(() async {
        await bridge.close();
        if (await discovery.exists()) await discovery.delete();
        if (await directory.exists()) await directory.delete();
      });

      await bridge.start();
      expect(await discovery.exists(), isTrue);
      if (Platform.isLinux || Platform.isMacOS) {
        final directoryStat = await directory.stat();
        expect(directoryStat.mode & 0x1FF, 0x1C0);
      }
      final metadata = jsonDecode(await discovery.readAsString()) as Map;
      final baseUrl = Uri.parse(metadata['base_url'] as String);
      final token = metadata['token'] as String;

      final unauthorized = await _request(baseUrl.resolve('/v1/status'));
      expect(unauthorized.statusCode, HttpStatus.unauthorized);

      final status = await _request(
        baseUrl.resolve('/v1/status'),
        token: token,
      );
      expect(status.statusCode, HttpStatus.ok);
      expect(status.json['logged_in'], isTrue);

      final audit = await _request(
        baseUrl.resolve('/v1/audit-snapshot'),
        token: token,
      );
      expect(audit.statusCode, HttpStatus.ok);
      expect(audit.json['schema_version'], 1);
      expect(audit.json['courses'], isEmpty);

      final turn = await _request(
        baseUrl.resolve('/v1/turns'),
        method: 'POST',
        token: token,
        body: {
          'prompt': '真实页面问题',
          'new_conversation': true,
          'open_ui': true,
          'thinking_mode': 'high',
        },
      );
      expect(turn.statusCode, HttpStatus.ok);
      expect(turn.json['answer'], '完成：真实页面问题');
      expect(prompts, ['真实页面问题']);

      await bridge.close();
      expect(await discovery.exists(), isFalse);
    },
  );

  test(
    'bridge runs independent turns concurrently and keeps audit exclusive',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'small_u_acceptance_bridge_concurrent_test.',
      );
      final discovery = File('${directory.path}/bridge.json');
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final release = Completer<void>();
      final bridge = SmallUAcceptanceBridge(
        config: SmallUAcceptanceBridgeConfig(discoveryFile: discovery),
        statusHandler: () => {'logged_in': true},
        auditHandler: () async => {'schema_version': 1, 'courses': const []},
        turnHandler: (request) async {
          if (request.prompt == 'first') {
            firstStarted.complete();
          } else if (request.prompt == 'second') {
            secondStarted.complete();
          }
          await release.future;
          return {
            'answer': '完成：${request.prompt}',
            'conversation_id': request.prompt,
          };
        },
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await bridge.close();
        if (await discovery.exists()) await discovery.delete();
        if (await directory.exists()) await directory.delete();
      });

      await bridge.start();
      final metadata = jsonDecode(await discovery.readAsString()) as Map;
      final baseUrl = Uri.parse(metadata['base_url'] as String);
      final token = metadata['token'] as String;
      final first = _request(
        baseUrl.resolve('/v1/turns'),
        method: 'POST',
        token: token,
        body: {
          'prompt': 'first',
          'new_conversation': true,
          'open_ui': false,
          'thinking_mode': 'high',
        },
      );
      final second = _request(
        baseUrl.resolve('/v1/turns'),
        method: 'POST',
        token: token,
        body: {
          'prompt': 'second',
          'new_conversation': true,
          'open_ui': false,
          'thinking_mode': 'low',
        },
      );
      await Future.wait([firstStarted.future, secondStarted.future]);

      final status = await _request(
        baseUrl.resolve('/v1/status'),
        token: token,
      );
      expect(status.json['active_turns'], 2);
      final audit = await _request(
        baseUrl.resolve('/v1/audit-snapshot'),
        token: token,
      );
      expect(audit.statusCode, HttpStatus.conflict);
      expect(audit.json['error'], 'turn_in_progress');

      release.complete();
      final responses = await Future.wait([first, second]);
      expect(
        responses.map((item) => item.statusCode),
        everyElement(HttpStatus.ok),
      );
      expect(responses.map((item) => item.json['conversation_id']).toSet(), {
        'first',
        'second',
      });
    },
  );

  test(
    'runtime sends through the real controller and returns its stored answer',
    () async {
      final session = _LoggedInSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService();
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        memoryStore: _MemoryStore(),
        thinkingModeStore: _ThinkingModeStore(),
      );
      var openCalls = 0;
      final runtime = SmallUAcceptanceRuntime(
        assistantController: controller,
        sessionController: session,
        openAssistant: () async {
          openCalls += 1;
        },
        isAssistantPresented: () => false,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        service.dispose();
        session.dispose();
      });

      final result = await runtime.runTurn(
        const SmallUAcceptanceTurnRequest(
          prompt: '从真实控制器回答',
          newConversation: true,
          openUi: true,
          thinkingMode: 'high',
        ),
      );

      expect(openCalls, 1);
      expect(service.messages, ['从真实控制器回答']);
      expect(result['answer'], '真实链路完成。');
      expect(result['thinking_mode'], 'high');
      expect(
        controller.currentConversation?.messages.map((item) => item.content),
        ['从真实控制器回答', '真实链路完成。'],
      );

      final audit = await runtime.auditSnapshot();
      expect((audit['profile'] as Map)['function_count'], 2);
      expect((audit['courses'] as List), hasLength(1));
      expect(
        (((audit['courses'] as List).single as Map)['sections'] as List),
        hasLength(1),
      );
      expect((audit['timeline'] as List), hasLength(1));
      expect(audit.toString(), isNot(contains('student01')));
      expect(audit.toString(), isNot(contains('Private')));
      expect(audit.toString(), isNot(contains('example.invalid')));
    },
  );

  test(
    'runtime isolates concurrent conversations and thinking modes',
    () async {
      final session = _LoggedInSessionController();
      final coordinator = AssistantContextCoordinator();
      final highReply = Completer<AssistantChatResult>();
      final lowReply = Completer<AssistantChatResult>();
      final service = _FakeAssistantService(
        chatCompleters: {'high question': highReply, 'low question': lowReply},
      );
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        memoryStore: _MemoryStore(),
        thinkingModeStore: _ThinkingModeStore(),
      );
      final runtime = SmallUAcceptanceRuntime(
        assistantController: controller,
        sessionController: session,
        openAssistant: () async {},
        isAssistantPresented: () => true,
      );
      addTearDown(() {
        if (!highReply.isCompleted) highReply.complete(_result('high answer'));
        if (!lowReply.isCompleted) lowReply.complete(_result('low answer'));
        controller.dispose();
        coordinator.dispose();
        service.dispose();
        session.dispose();
      });

      final highTurn = runtime.runTurn(
        const SmallUAcceptanceTurnRequest(
          prompt: 'high question',
          newConversation: true,
          openUi: false,
          thinkingMode: 'high',
        ),
      );
      final lowTurn = runtime.runTurn(
        const SmallUAcceptanceTurnRequest(
          prompt: 'low question',
          newConversation: true,
          openUi: false,
          thinkingMode: 'low',
        ),
      );
      while (service.messages.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.sending, isTrue);

      lowReply.complete(_result('low answer'));
      highReply.complete(_result('high answer'));
      final results = await Future.wait([highTurn, lowTurn]);
      expect(results[0]['thinking_mode'], 'high');
      expect(results[0]['answer'], 'high answer');
      expect(results[1]['thinking_mode'], 'low');
      expect(results[1]['answer'], 'low answer');
      expect(
        results[0]['conversation_id'],
        isNot(results[1]['conversation_id']),
      );
      expect(controller.sending, isFalse);
    },
  );

  test(
    'runtime returns de-identified iSpace catalog timing diagnostics',
    () async {
      final session = _LoggedInSessionController();
      final coordinator = AssistantContextCoordinator();
      final service = _FakeAssistantService(
        contextSources: const {'ispace_course_catalog'},
      );
      final controller = AiAssistantController(
        sessionController: session,
        service: service,
        coordinator: coordinator,
        historyStore: _MemoryHistoryStore(),
        memoryStore: _MemoryStore(),
        thinkingModeStore: _ThinkingModeStore(),
      );
      final runtime = SmallUAcceptanceRuntime(
        assistantController: controller,
        sessionController: session,
        openAssistant: () async {},
        isAssistantPresented: () => true,
      );
      addTearDown(() {
        controller.dispose();
        coordinator.dispose();
        service.dispose();
        session.dispose();
      });

      final result = await runtime.runTurn(
        const SmallUAcceptanceTurnRequest(
          prompt: '统计全部 iSpace 模块类型分布',
          newConversation: true,
          openUi: false,
          thinkingMode: 'low',
        ),
      );

      final diagnostics = (result['ispace_catalog_diagnostics'] as Map)
          .cast<String, dynamic>();
      expect(diagnostics['detail_level'], 'aggregates');
      expect(diagnostics['selected_course_count'], 1);
      expect(diagnostics['content_network_loads'], 1);
      expect(diagnostics['teacher_network_loads'], 0);
      expect(diagnostics['serialized_bytes'], greaterThan(0));
      expect(diagnostics.toString(), isNot(contains('Example Course')));
      expect(diagnostics.toString(), isNot(contains('Lecture Notes')));
    },
  );
}

class _Response {
  const _Response(this.statusCode, this.json);

  final int statusCode;
  final Map<String, dynamic> json;
}

Future<_Response> _request(
  Uri uri, {
  String method = 'GET',
  String? token,
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final decoded = jsonDecode(await utf8.decoder.bind(response).join());
    return _Response(
      response.statusCode,
      (decoded as Map).cast<String, dynamic>(),
    );
  } finally {
    client.close(force: true);
  }
}

class _LoggedInSessionController extends AppSessionController {
  _LoggedInSessionController()
    : super(deadlineReminderService: _FakeDeadlineReminderService());

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  MoodleRuntimeProfile? get moodleRuntimeProfile => MoodleRuntimeProfile(
    release: '4.1.3+',
    version: '2022112803.06',
    functionVersions: const {
      'core_enrol_get_users_courses': '2022112800',
      'core_course_get_contents': '2022112800',
    },
    downloadFiles: true,
    uploadFiles: true,
    advancedFeatures: const {'enablecompletion': 1},
    userMaxUploadFileSize: 1024,
  );

  @override
  List<CourseSummary> get courses => [
    CourseSummary(
      id: 101,
      fullName: 'Example Course',
      shortName: 'EX101',
      categoryName: 'Current',
      progress: 25,
      enableCompletion: true,
      completionUserTracked: true,
      showGrades: true,
    ),
  ];

  @override
  List<TimelineItem> get timelineItems => [
    TimelineItem(
      id: 501,
      title: 'Example Assignment',
      activityState: 'Due',
      activityType: 'assign',
      moduleName: 'assign',
      description: 'Private description must not enter the audit snapshot.',
      courseName: 'Example Course',
      courseId: 101,
      instanceId: 601,
      url: 'https://example.invalid/private',
      sortTime: DateTime.utc(2026, 9, 4),
      formattedTime: 'Tomorrow',
      isOverdue: false,
    ),
  ];

  @override
  Future<void> refreshCourses() async {}

  @override
  Future<void> refreshTimeline() async {}

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async => [
    CourseContentSection(
      id: 201,
      sectionNum: 1,
      name: 'Week 1',
      summary: 'Private summary must not enter the audit snapshot.',
      modules: [
        CourseModule(
          id: 301,
          instance: 401,
          name: 'Lecture Notes',
          modName: 'resource',
          url: 'https://example.invalid/private-resource',
          iconUrl: 'https://example.invalid/icon',
          descriptionHtml: '<p>Private module description</p>',
          contents: [
            CourseModuleContent(
              type: 'file',
              fileName: 'notes.pdf',
              filePath: '/private/',
              fileUrl: 'https://example.invalid/private-file',
              fileSize: 256,
              mimeType: 'application/pdf',
              timeModifiedEpoch: 1788436800,
              sortOrder: 1,
              author: 'Private Author',
              license: 'allrightsreserved',
            ),
          ],
          dates: [
            CourseModuleDate(
              label: 'Due',
              timestamp: 1788436800,
              dataId: 'due',
            ),
          ],
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
          downloadContent: true,
        ),
      ],
    ),
  ];
}

class _FakeDeadlineReminderService extends DeadlineReminderService {
  @override
  Future<bool> loadEnabled() async => false;
}

class _FakeAssistantService implements AiAssistantService {
  _FakeAssistantService({
    this.contextSources = const {},
    this.chatCompleters = const {},
  });

  final Set<String> contextSources;
  final Map<String, Completer<AssistantChatResult>> chatCompleters;
  final messages = <String>[];

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
    final pending = chatCompleters[message];
    if (pending != null) return pending.future;
    return AssistantChatResult(
      requestId: clientRequestId ?? 'request-id',
      answer: '真实链路完成。',
      actions: const [],
      usage: const AssistantTokenUsage(
        inputTokens: 10,
        outputTokens: 5,
        totalTokens: 15,
      ),
      quota: _quota(),
    );
  }

  @override
  void dispose() {}

  @override
  Future<bool> isEnabled(String username) async => true;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async =>
      AssistantCapabilities(
        available: true,
        model: 'test-model',
        contextSources: contextSources,
        actions: const {},
        storesConversationContent: false,
        purchaseApiAvailable: false,
      );

  @override
  Future<AssistantQuota> loadQuota(String username) async => _quota();

  @override
  Future<void> setEnabled(String username, bool enabled) async {}
}

AssistantChatResult _result(String answer) => AssistantChatResult(
  requestId: 'request-id',
  answer: answer,
  actions: const [],
  usage: const AssistantTokenUsage(
    inputTokens: 10,
    outputTokens: 5,
    totalTokens: 15,
  ),
  quota: _quota(),
);

AssistantQuota _quota() => AssistantQuota(
  periodStart: DateTime.utc(2026, 8),
  periodEnd: DateTime.utc(2026, 9),
  monthlyQuotaTokens: 100000,
  creditBalanceTokens: 0,
  usedTokens: 0,
  reservedTokens: 0,
  remainingTokens: 100000,
);

class _MemoryHistoryStore implements AssistantHistoryStore {
  List<AssistantConversation> conversations = [];

  @override
  Future<List<AssistantConversation>> load(String username) async =>
      List.of(conversations);

  @override
  Future<void> save(
    String username,
    List<AssistantConversation> conversations,
  ) async {
    this.conversations = List.of(conversations);
  }
}

class _MemoryStore implements AssistantMemoryStore {
  List<AssistantMemoryEntry> entries = [];

  @override
  Future<List<AssistantMemoryEntry>> load(String owner) async =>
      List.of(entries);

  @override
  Future<void> save(String owner, List<AssistantMemoryEntry> entries) async {
    this.entries = List.of(entries);
  }
}

class _ThinkingModeStore implements AssistantThinkingModeStore {
  AssistantThinkingMode mode = AssistantThinkingMode.medium;

  @override
  Future<AssistantThinkingMode> load(String username) async => mode;

  @override
  Future<void> save(String username, AssistantThinkingMode mode) async {
    this.mode = mode;
  }
}
