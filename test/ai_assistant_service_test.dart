import 'package:bnbu_me/services/me_identity_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/mail_radar_store.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'background activation distinguishes first use from explicit opt-out',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesAiAssistantConsentStore();
      const email = 'fixture@example.test';
      expect(await store.canSyncInBackground(email), isTrue);
      await store.setEnabled(email, false);
      expect(await store.canSyncInBackground(email), isFalse);
      await store.setEnabled(email, true);
      expect(await store.canSyncInBackground(email), isTrue);
    },
  );

  test('邮件雷达等待时限覆盖服务端完整处理窗口', () {
    expect(
      RemoteAiAssistantService.defaultMailRadarRequestTimeout,
      const Duration(seconds: 58),
    );
  });

  test('小U规划等待时限覆盖服务端排队和 Provider 处理窗口', () {
    expect(
      RemoteAiAssistantService.defaultPlanningRequestTimeout,
      const Duration(seconds: 180),
    );
  });

  test('unlimited quota accepts null limits and remaining tokens', () {
    final quota = AssistantQuota.fromJson({
      'period_start': '2026-07-01T00:00:00Z',
      'period_end': '2026-08-01T00:00:00Z',
      'monthly_quota_tokens': null,
      'credit_balance_tokens': 0,
      'used_tokens': 1234,
      'reserved_tokens': 0,
      'remaining_tokens': null,
      'unlimited': true,
    });

    expect(quota.unlimited, isTrue);
    expect(quota.monthlyQuotaTokens, isNull);
    expect(quota.remainingTokens, isNull);
  });

  test('unbound assistant cannot enroll or send metadata', () async {
    var requests = 0;
    final store = _MemoryUsageSyncStore();
    final consent = _MemoryConsentStore();
    final service = RemoteAiAssistantService(
      usageStore: store,
      consentStore: consent,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    await expectLater(
      service.setEnabled('student01', true),
      throwsA(isA<MeBindingRequired>()),
    );
    expect(requests, 0);
    expect(consent.enabled, isFalse);
    expect(store.record, isNull);
    service.dispose();
  });

  test(
    'chat sends device token only in header and selected strict context',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      late String requestUrl;
      late String? authorizationHeader;
      late String requestBody;
      final client = MockClient((request) async {
        requestUrl = request.url.toString();
        authorizationHeader =
            request.headers['Authorization'] ??
            request.headers['authorization'];
        requestBody = request.body;
        return http.Response(
          jsonEncode({
            'request_id': '00000000-0000-0000-0000-000000000003',
            'answer': '已整理今天的课程。',
            'actions': [],
            'suggestions': [
              {'label': '查看下一节', 'message': '请告诉我下一节课程的信息。', 'kind': 'submit'},
              {'label': '其他', 'message': '', 'kind': 'other'},
            ],
            'usage': {
              'input_tokens': 20,
              'output_tokens': 10,
              'total_tokens': 30,
            },
            'quota': _quotaJson(remaining: 9970, used: 30),
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );
      final context = AssistantContextPayload(
        sources: const {AssistantContextSource.courses},
        courses: const [
          AssistantCourseContext(
            courseId: '42',
            name: 'C Language',
            teachers: ['Teacher Chen'],
          ),
        ],
      );

      final result = await service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: context,
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
      );

      expect(result.answer, '已整理今天的课程。');
      expect(result.suggestions, hasLength(2));
      expect(result.suggestions.first.label, '查看下一节');
      expect(result.suggestions.last.isOther, isTrue);
      expect(result.quota.remainingTokens, 9970);
      expect(requestUrl, 'https://sync.example/v1/assistant/chat');
      expect(authorizationHeader, 'Bearer dev_existing-token');
      final requestPayload = jsonDecode(requestBody) as Map<String, dynamic>;
      expect(requestPayload['message'], '整理课程');
      expect(
        requestPayload['client_request_id'],
        '123e4567-e89b-42d3-a456-426614174000',
      );
      final sentContext = requestPayload['context'] as Map<String, dynamic>;
      expect(sentContext['sources'], ['courses']);
      expect(
        (sentContext['courses'] as List).single,
        containsPair('teachers', ['Teacher Chen']),
      );
      final serialized = jsonEncode(requestPayload);
      expect(serialized, isNot(contains('dev_existing-token')));
      expect(serialized.toLowerCase(), isNot(contains('password')));
    },
  );

  test(
    'mail radar uses dedicated endpoint and parses tool and memory evidence',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      late Map<String, dynamic> requestBody;
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://sync.example/v1/assistant/mail-radar/analyze',
          );
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'request_id': '00000000-0000-0000-0000-000000000003',
            'result': {
              'summary_zh': '老师请用户下课后到办公室。',
              'content_language': 'other',
              'needs_translation': true,
              'translation_zh': '下课后请到我的办公室。',
              'priority': 'normal',
              'category': 'action',
              'is_direct_correspondence': true,
              'sender_role': 'teacher',
              'is_recall_notice': false,
              'action_zh': '下课后前往老师办公室',
              'action_links': [],
              'deadline_text': '',
              'related_thread_key': 'office',
              'attachment_notes': [],
              'memory_suggestions': [],
            },
            'tool_uses': [
              {
                'name': 'official_directory',
                'status': 'used',
                'query': 'chen@bnbu.edu.cn',
              },
              {'name': 'approved_memory', 'status': 'used', 'query': '当前邮件'},
            ],
            'memory_suggestions': [
              {
                'content': '用户长期计划从事软件开发。',
                'memory_type': 'persona',
                'source_id': '',
              },
            ],
            'usage': {
              'input_tokens': 20,
              'output_tokens': 10,
              'total_tokens': 30,
            },
            'quota': _quotaJson(remaining: 9970, used: 30),
          }, 200);
        }),
        usageStore: usageStore,
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );

      final result = await service.analyzeMailRadar(
        username: 'student01',
        request: MailRadarRemoteRequest(
          clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
          uid: 12,
          mailboxUidValidity: 77,
          senderName: 'Dr Chen',
          senderEmail: 'chen@bnbu.edu.cn',
          subject: 'Office',
          receivedAt: DateTime.parse('2026-08-14T09:00:00+08:00'),
          bodyExcerpt: 'Please come to my office after class.',
          recipients: 'student01@mail.bnbu.edu.cn',
          cc: '',
          listId: '',
          precedence: '',
          replyHeaders: '',
          attachmentContext: '无',
          sourceLinks: const [],
          attachments: const [],
          targetLanguageTag: 'en',
        ),
      );

      expect(
        requestBody['client_request_id'],
        '123e4567-e89b-42d3-a456-426614174000',
      );
      expect(requestBody['sender_email'], 'chen@bnbu.edu.cn');
      expect(requestBody['target_language'], 'en');
      expect(requestBody.keys, isNot(contains('password')));
      expect(result.clientRequestId, '123e4567-e89b-42d3-a456-426614174000');
      expect(result.toolUses.map((item) => item.name), [
        'official_directory',
        'approved_memory',
      ]);
      expect(result.memorySuggestions.single.content, '用户长期计划从事软件开发。');
    },
  );

  test(
    'mail radar replaces one received-stage conflicting request id and returns it',
    () async {
      final requestIds = <String>[];
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requestIds.add(body['client_request_id'] as String);
          if (requestIds.length == 1) {
            return _jsonResponse({
              'detail': {
                'code': 'client_request_id_conflict',
                'stage': 'received',
                'retry_policy': 'do_not_retry',
              },
            }, 409);
          }
          return _jsonResponse({
            'request_id': '00000000-0000-0000-0000-000000000003',
            'result': <String, dynamic>{},
            'tool_uses': <Object>[],
            'memory_suggestions': <Object>[],
          }, 200);
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );

      final result = await service.analyzeMailRadar(
        username: 'student01',
        request: MailRadarRemoteRequest(
          clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
          uid: 12,
          mailboxUidValidity: 77,
          senderName: 'Sender',
          senderEmail: 'sender@bnbu.edu.cn',
          subject: 'Notice',
          receivedAt: DateTime.parse('2026-08-14T09:00:00+08:00'),
          bodyExcerpt: 'Campus notice.',
          recipients: 'student01@mail.bnbu.edu.cn',
          cc: '',
          listId: '',
          precedence: '',
          replyHeaders: '',
          attachmentContext: '',
          sourceLinks: const [],
          attachments: const [],
        ),
      );

      expect(requestIds, hasLength(2));
      expect(requestIds.first, '123e4567-e89b-42d3-a456-426614174000');
      expect(requestIds.last, isNot(requestIds.first));
      expect(
        requestIds.last,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(result.clientRequestId, requestIds.last);
    },
  );

  test(
    'mail radar never loops when the replacement id also conflicts',
    () async {
      var calls = 0;
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          calls++;
          return _jsonResponse({
            'detail': {
              'code': 'client_request_id_conflict',
              'stage': 'received',
              'retry_policy': 'do_not_retry',
            },
          }, 409);
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );

      await expectLater(
        service.analyzeMailRadar(
          username: 'student01',
          request: MailRadarRemoteRequest(
            clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
            uid: 12,
            mailboxUidValidity: 77,
            senderName: 'Sender',
            senderEmail: 'sender@bnbu.edu.cn',
            subject: 'Notice',
            receivedAt: DateTime.parse('2026-08-14T09:00:00+08:00'),
            bodyExcerpt: 'Campus notice.',
            recipients: 'student01@mail.bnbu.edu.cn',
            cc: '',
            listId: '',
            precedence: '',
            replyHeaders: '',
            attachmentContext: '',
            sourceLinks: const [],
            attachments: const [],
          ),
        ),
        throwsA(
          isA<AiAssistantRemoteStatusException>().having(
            (error) => error.code,
            'code',
            'client_request_id_conflict',
          ),
        ),
      );
      expect(calls, 2);
    },
  );

  test(
    'mail radar uses the authenticated account-level snapshot API',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final rawItem = <String, dynamic>{
        'key': '77_12',
        'uid': 12,
        'mailbox_uid_validity': 77,
        'subject': 'Office',
        'sender': 'Dr Chen',
        'received_at': '2026-08-14T09:00:00+08:00',
        'summary_zh': '老师请用户下课后到办公室。',
        'translation_zh': '',
        'priority': 'normal',
        'category': 'action',
        'sender_role': 'teacher',
        'action_zh': '下课后前往老师办公室',
        'action_links': <Object>[],
        'deadline_text': '',
        'related_thread_key': 'office',
        'attachment_notes': <Object>[],
        'analyzed_at': '2026-08-14T09:01:00+08:00',
        'updated_at': '2026-08-14T09:01:00+08:00',
        'analysis_pending': false,
        'analysis_request_id': '123e4567-e89b-42d3-a456-426614174000',
        'tool_uses': <Object>[],
        'memory_suggestions': <Object>[],
      };
      final requests = <http.Request>[];
      var remoteItem = rawItem;
      final client = MockClient((request) async {
        requests.add(request);
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer dev_existing-token',
        );
        if (request.method == 'GET') {
          return _jsonResponse({
            'version': 1,
            'items': [remoteItem],
            'updated_at': '2026-08-14T09:02:00Z',
          }, 200);
        }
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.method, 'PATCH');
        if (payload['expected_version'] == 2) {
          expect(payload['items'], isEmpty);
          return _jsonResponse({
            'version': 3,
            'items': [remoteItem],
          }, 200);
        }
        expect(payload['expected_version'], 1);
        expect(
          ((payload['items'] as List).single as Map<String, dynamic>)['key'],
          '77_12',
        );
        remoteItem = (payload['items'] as List).single as Map<String, dynamic>;
        return _jsonResponse({
          'version': 2,
          'items': payload['items'],
          'updated_at': '2026-08-14T09:03:00Z',
        }, 200);
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );

      final loaded = await service.loadMailRadar('student01');
      final changedItems = [loaded.items.single.copyWith(completed: true)];
      final saved = await service.saveMailRadar(
        'student01',
        expectedVersion: loaded.version,
        items: changedItems,
      );

      expect(loaded.items.single.summaryZh, '老师请用户下课后到办公室。');
      expect(saved.version, 2);
      final unchanged = await service.saveMailRadar(
        'student01',
        expectedVersion: saved.version,
        items: changedItems,
      );
      expect(unchanged.version, 3);
      expect(unchanged.items.single.key, '77_12');
      expect(requests.length, 3);
      // A later remote read replaces the comparison baseline. Restoring a
      // locally newer field must be uploaded even if it matched an older sync.
      remoteItem = rawItem;
      final refreshed = await service.loadMailRadar('student01');
      await service.saveMailRadar(
        'student01',
        expectedVersion: refreshed.version,
        items: changedItems,
      );
      expect(remoteItem['completed'], isTrue);
      expect(
        requests.map((request) => request.url.path),
        everyElement('/v1/assistant/mail-radar/snapshot'),
      );
    },
  );

  test('mail radar access denial is a hidden-feature signal', () async {
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async => http.Response('not found', 404)),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
    );

    await expectLater(
      service.loadMailRadar('student01'),
      throwsA(isA<AiAssistantMailRadarUnavailableException>()),
    );
  });

  test(
    'mail radar analysis maps a revoked entitlement to hidden feature',
    () async {
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async => http.Response('forbidden', 403)),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );

      await expectLater(
        service.analyzeMailRadar(
          username: 'student01',
          request: MailRadarRemoteRequest(
            clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
            uid: 12,
            mailboxUidValidity: 77,
            senderName: 'Sender',
            senderEmail: 'sender@bnbu.edu.cn',
            subject: 'Notice',
            receivedAt: DateTime.parse('2026-08-14T09:00:00+08:00'),
            bodyExcerpt: 'Campus notice.',
            recipients: 'student01@mail.bnbu.edu.cn',
            cc: '',
            listId: '',
            precedence: '',
            replyHeaders: '',
            attachmentContext: '',
            sourceLinks: const [],
            attachments: const [],
          ),
        ),
        throwsA(isA<AiAssistantMailRadarUnavailableException>()),
      );
    },
  );

  test(
    'assistant history uses the authenticated cross-device snapshot API',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      final requests = <http.Request>[];
      final now = DateTime.utc(2026, 7, 28, 8);
      final conversation = AssistantConversation(
        id: 'local-123456',
        title: '同步验证',
        createdAt: now,
        updatedAt: now,
        messages: [
          AssistantStoredMessage(
            role: 'user',
            content: '请跨设备同步',
            createdAt: now,
          ),
        ],
      );
      final client = MockClient((request) async {
        requests.add(request);
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer dev_existing-token',
        );
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'version': 1,
              'conversations': [conversation.toJson()],
              'updated_at': '2026-07-28T08:01:00Z',
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload, isNot(contains('protocol_version')));
        expect(payload['expected_version'], 1);
        expect(
          ((payload['conversations'] as List).single
              as Map<String, dynamic>)['title'],
          '同步验证',
        );
        return http.Response(
          jsonEncode({
            'version': 2,
            'conversations': [conversation.toJson()],
            'updated_at': '2026-07-28T08:02:00Z',
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );

      final loaded = await service.loadHistory('student01');
      final saved = await service.saveHistory(
        'student01',
        expectedVersion: loaded.version,
        conversations: loaded.conversations,
      );

      expect(loaded.conversations.single.messages.single.content, '请跨设备同步');
      expect(saved.version, 2);
      expect(
        requests.map((request) => request.url.path),
        everyElement('/v1/assistant/history'),
      );
    },
  );

  test(
    'history retries without presentation fields for a legacy strict schema',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      final now = DateTime.utc(2026, 8, 7, 9);
      final conversation = AssistantConversation(
        id: 'legacy-history-sync',
        title: '网络恢复测试',
        createdAt: now,
        updatedAt: now,
        messages: [
          AssistantStoredMessage(
            role: 'assistant',
            content: '网络暂时没有恢复，这轮问题已经保留。',
            createdAt: now,
            isError: true,
            compactError: true,
            retryMessage: '继续检查今天安排',
            activities: const [
              AssistantActivity(label: '网络连接暂未恢复，已保留这轮问题', failed: true),
            ],
          ),
        ],
      );
      final payloads = <Map<String, dynamic>>[];
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        payloads.add(payload);
        final message =
            ((((payload['conversations'] as List).single
                            as Map<String, dynamic>)['messages']
                        as List)
                    .single
                as Map<String, dynamic>);
        final activity =
            ((message['activities'] as List).single as Map<String, dynamic>);
        if (attempts == 1) {
          expect(message['compact_error'], isTrue);
          expect(activity['failed'], isTrue);
          return _jsonResponse({
            'detail': [
              {
                'type': 'extra_forbidden',
                'loc': ['body', 'compact_error'],
              },
            ],
          }, 422);
        }
        expect(message, isNot(contains('compact_error')));
        expect(activity, isNot(contains('failed')));
        return _jsonResponse({
          'version': 4,
          'conversations': payload['conversations'],
          'updated_at': '2026-08-07T09:01:00Z',
        }, 200);
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );

      final saved = await service.saveHistory(
        'student01',
        expectedVersion: 3,
        conversations: [conversation],
      );

      expect(attempts, 2);
      expect(payloads.map((payload) => payload['expected_version']).toSet(), {
        3,
      });
      expect(saved.version, 4);

      final savedAgain = await service.saveHistory(
        'student01',
        expectedVersion: 4,
        conversations: [conversation],
      );

      expect(attempts, 3);
      final thirdMessage =
          (((((payloads.last['conversations'] as List).single
                          as Map<String, dynamic>)['messages']
                      as List)
                  .single
              as Map<String, dynamic>));
      expect(thirdMessage, isNot(contains('compact_error')));
      expect(savedAgain.version, 4);
    },
  );

  test('history does not retry an unrelated validation error', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final consentStore = _MemoryConsentStore(enabled: true);
    var attempts = 0;
    final client = MockClient((request) async {
      attempts++;
      return _jsonResponse({
        'detail': [
          {
            'type': 'greater_than_equal',
            'loc': ['body', 'expected_version'],
          },
        ],
      }, 422);
    });
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: usageStore,
      consentStore: consentStore,
      baseUrl: 'https://sync.example',
    );
    final now = DateTime.utc(2026, 9, 8);
    final conversation = AssistantConversation(
      id: 'validation-no-retry',
      title: '校验失败',
      createdAt: now,
      updatedAt: now,
      messages: [
        AssistantStoredMessage(
          role: 'assistant',
          content: '网络暂时没有恢复，这轮问题已经保留。',
          createdAt: now,
          isError: true,
          compactError: true,
        ),
      ],
    );

    await expectLater(
      service.saveHistory(
        'student01',
        expectedVersion: 0,
        conversations: [conversation],
      ),
      throwsA(
        isA<AiAssistantException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 422'),
        ),
      ),
    );
    expect(attempts, 1);
  });

  test(
    'attachment-only history does not retry an invalid legacy shape',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return _jsonResponse({
          'detail': [
            {
              'type': 'extra_forbidden',
              'loc': [
                'body',
                'conversations',
                0,
                'messages',
                0,
                'attachment_references',
              ],
            },
          ],
        }, 422);
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );
      final now = DateTime.utc(2026, 9, 8);
      final conversation = AssistantConversation(
        id: 'attachment-legacy-no-retry',
        title: 'synthetic.png',
        createdAt: now,
        updatedAt: now,
        messages: [
          AssistantStoredMessage(
            role: 'user',
            content: '',
            createdAt: now,
            attachmentReferences: const [
              AssistantAttachmentReference(
                kind: AssistantAttachmentReferenceKind.image,
                name: 'synthetic.png',
              ),
            ],
          ),
        ],
      );

      await expectLater(
        service.saveHistory(
          'student01',
          expectedVersion: 0,
          conversations: [conversation],
        ),
        throwsA(isA<AiAssistantException>()),
      );
      expect(attempts, 1);
    },
  );

  test(
    'plan asks the provider to choose from bounded client skills before chat',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      late Map<String, dynamic> requestPayload;
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://sync.example/v1/assistant/plan',
        );
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer dev_existing-token',
        );
        requestPayload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'request_id': '00000000-0000-4000-8000-000000000004',
            'sources': ['schedule', 'deadlines'],
            'server_tools': [
              {'name': 'official_directory', 'query': 'Teacher Example'},
            ],
            'navigation': {'type': 'open_app_tab', 'target_id': 'schedule'},
            'usage': {
              'input_tokens': 12,
              'output_tokens': 4,
              'total_tokens': 16,
            },
            'quota': _quotaJson(remaining: 9984, used: 16),
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );

      final plan = await service.planContext(
        username: 'student01',
        message: '帮我安排一下',
        history: const [],
        availableSources: const {
          AssistantContextSource.schedule,
          AssistantContextSource.deadlines,
        },
        availableActions: const {
          AssistantActionType.openAppTab,
          AssistantActionType.openAssignment,
        },
        clientRequestId: '123e4567-e89b-42d3-a456-426614174001',
      );

      expect(plan.sources, {
        AssistantContextSource.schedule,
        AssistantContextSource.deadlines,
      });
      expect(
        plan.serverTools.single.name,
        AssistantServerTool.officialDirectory,
      );
      expect(plan.serverTools.single.query, 'Teacher Example');
      expect(plan.navigation?.targetId, 'schedule');
      expect(plan.quota.remainingTokens, 9984);
      expect(
        requestPayload['client_request_id'],
        '123e4567-e89b-42d3-a456-426614174001',
      );
      expect(requestPayload['available_context_sources'], [
        'deadlines',
        'schedule',
      ]);
      expect(requestPayload['available_actions'], [
        'open_app_tab',
        'open_assignment',
      ]);
      expect(requestPayload, isNot(contains('context')));
    },
  );

  test('plan reattaches once after an untyped gateway timeout', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final consentStore = _MemoryConsentStore(enabled: true);
    final payloads = <Map<String, dynamic>>[];
    final delays = <Duration>[];
    var attempts = 0;
    final client = MockClient((request) async {
      attempts += 1;
      payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (attempts == 1) {
        return http.Response('gateway timeout', 504);
      }
      return _jsonResponse({
        'request_id': '00000000-0000-4000-8000-000000000004',
        'sources': ['schedule'],
        'server_tools': const [],
        'navigation': null,
        'usage': const {
          'input_tokens': 12,
          'output_tokens': 4,
          'total_tokens': 16,
        },
        'quota': _quotaJson(remaining: 9984, used: 16),
      }, 200);
    });
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: usageStore,
      consentStore: consentStore,
      retryDelay: (delay) async => delays.add(delay),
      baseUrl: 'https://sync.example',
    );

    final plan = await service.planContext(
      username: 'student01',
      message: 'What should I study next?',
      history: const [],
      availableSources: const {AssistantContextSource.schedule},
      availableActions: const {},
      clientRequestId: '123e4567-e89b-42d3-a456-426614174001',
    );

    expect(plan.sources, {AssistantContextSource.schedule});
    expect(attempts, 2);
    expect(delays, [const Duration(milliseconds: 250)]);
    expect(payloads.map((payload) => payload['client_request_id']).toSet(), {
      '123e4567-e89b-42d3-a456-426614174001',
    });
    expect(payloads[0], payloads[1]);
  });

  test('plan retries one typed transient provider timeout', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final consentStore = _MemoryConsentStore(enabled: true);
    var attempts = 0;
    final client = MockClient((request) async {
      attempts += 1;
      if (attempts == 1) {
        return _jsonResponse({
          'detail': const {
            'code': 'provider_timeout',
            'stage': 'provider_request',
            'retry_policy': 'new_request',
          },
        }, 504);
      }
      return _jsonResponse({
        'request_id': '00000000-0000-4000-8000-000000000004',
        'sources': const [],
        'server_tools': const [],
        'navigation': null,
        'usage': const {
          'input_tokens': 12,
          'output_tokens': 4,
          'total_tokens': 16,
        },
        'quota': _quotaJson(remaining: 9984, used: 16),
      }, 200);
    });
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: usageStore,
      consentStore: consentStore,
      retryDelay: (_) async {},
      baseUrl: 'https://sync.example',
    );

    await service.planContext(
      username: 'student01',
      message: '帮我找一个方向合适的老师。',
      history: const [],
      availableSources: const {},
      availableActions: const {},
      clientRequestId: '123e4567-e89b-42d3-a456-426614174001',
    );

    expect(attempts, 2);
  });

  test('agent turn pauses for a typed client tool and resumes', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final consentStore = _MemoryConsentStore(enabled: true);
    final payloads = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://sync.example/v1/assistant/agent/turn',
      );
      payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (payloads.length == 1) {
        return _jsonResponse({
          'request_id': '00000000-0000-4000-8000-000000000010',
          'conversation_id': '123e4567-e89b-42d3-a456-426614174010',
          'status': 'requires_tools',
          'round': 1,
          'tool_calls': [
            {
              'call_id': 'call_schedule',
              'name': 'get_schedule',
              'arguments': <String, dynamic>{},
            },
          ],
          'continuation_token': 'encrypted-continuation',
          'answer': '',
          'actions': [],
          'suggestions': [],
          'usage': {'input_tokens': 20, 'output_tokens': 5, 'total_tokens': 25},
          'quota': _quotaJson(remaining: 9975, used: 25),
        }, 200);
      }
      return _jsonResponse({
        'request_id': '00000000-0000-4000-8000-000000000011',
        'conversation_id': '123e4567-e89b-42d3-a456-426614174010',
        'status': 'completed',
        'round': 2,
        'tool_calls': [],
        'continuation_token': '',
        'answer': '下一节课是 C Language。',
        'actions': [],
        'suggestions': [],
        'usage': {'input_tokens': 30, 'output_tokens': 8, 'total_tokens': 38},
        'quota': _quotaJson(remaining: 9937, used: 63),
      }, 200);
    });
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: usageStore,
      consentStore: consentStore,
      baseUrl: 'https://sync.example',
    );

    final first = await service.runAgentTurn(
      username: 'student01',
      conversationId: '123e4567-e89b-42d3-a456-426614174010',
      clientRequestId: '123e4567-e89b-42d3-a456-426614174011',
      message: '下一节课是什么？',
      history: const [],
      availableSources: const {AssistantContextSource.schedule},
      availableActions: const {AssistantActionType.openCourse},
      plannedServerTools: const [
        AssistantPlannedServerTool(
          name: AssistantServerTool.officialDirectory,
          query: 'Teacher Example',
        ),
      ],
      agentProtocolVersion: 2,
    );
    expect(first.requiresTools, isTrue);
    expect(first.toolCalls.single.name, 'get_schedule');

    final second = await service.runAgentTurn(
      username: 'student01',
      conversationId: '123e4567-e89b-42d3-a456-426614174010',
      clientRequestId: '123e4567-e89b-42d3-a456-426614174012',
      continuationToken: first.continuationToken,
      toolResults: [
        AssistantAgentToolResult(
          callId: first.toolCalls.single.callId,
          context: AssistantContextPayload(
            sources: const {AssistantContextSource.schedule},
            schedule: [
              AssistantScheduleContext(
                courseId: '42',
                courseName: 'C Language',
                room: 'T4-101',
                startsAt: DateTime.parse('2026-07-24T01:00:00Z'),
                endsAt: DateTime.parse('2026-07-24T02:00:00Z'),
              ),
            ],
          ),
        ),
      ],
      agentProtocolVersion: 2,
    );

    expect(second.chatResult?.answer, '下一节课是 C Language。');
    expect(payloads.first['message'], '下一节课是什么？');
    expect(payloads.first['available_context_sources'], ['schedule']);
    expect(payloads.first['planned_server_tools'], [
      {'name': 'official_directory', 'query': 'Teacher Example'},
    ]);
    expect(payloads.first['thinking_mode'], 'low');
    expect(payloads.first['max_output_tokens'], 1800);
    expect(payloads.first['sources_preplanned'], isTrue);
    expect(payloads.first, isNot(contains('continuation_token')));
    expect(payloads.last['continuation_token'], 'encrypted-continuation');
    expect(payloads.last['thinking_mode'], 'low');
    expect(payloads.last['sources_preplanned'], isTrue);
    expect(payloads.last, isNot(contains('message')));
    expect(payloads.last, isNot(contains('planned_server_tools')));
    final sentResults = payloads.last['tool_results'] as List<dynamic>;
    expect(
      ((sentResults.single as Map<String, dynamic>)['context']
          as Map<String, dynamic>)['sources'],
      ['schedule'],
    );
  });

  test(
    'v3 agent turn negotiates SSE and accepts a heartbeating result',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      late http.Request sent;
      const clientRequestId = '123e4567-e89b-42d3-a456-426614174061';
      final client = MockClient((request) async {
        sent = request;
        return http.Response(
          _agentSse([
            (
              'ready',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000060',
                'client_request_id': clientRequestId,
                'heartbeat_interval_ms': 10000,
                'execution_budget_seconds': 480,
              },
            ),
            (
              'heartbeat',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000060',
                'client_request_id': clientRequestId,
                'sequence': 1,
              },
            ),
            (
              'x-metric',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000060',
                'client_request_id': clientRequestId,
                'optional': true,
                'elapsed_ms': 12,
              },
            ),
            (
              'result',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000060',
                'client_request_id': clientRequestId,
                'response': _agentCompletedJson(
                  requestId: '00000000-0000-4000-8000-000000000060',
                  conversationId: '123e4567-e89b-42d3-a456-426614174060',
                  answer: 'SSE 已完成。',
                ),
              },
            ),
          ]),
          200,
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );

      final result = await service.runAgentTurn(
        username: 'student01',
        conversationId: '123e4567-e89b-42d3-a456-426614174060',
        clientRequestId: clientRequestId,
        message: '用 SSE 回答。',
        agentProtocolVersion: 3,
      );

      expect(result.chatResult?.answer, 'SSE 已完成。');
      expect(sent.method, 'POST');
      expect(
        sent.url.toString(),
        'https://sync.example/v1/assistant/agent/turn/stream',
      );
      expect(sent.headers['accept'], 'text/event-stream');
      expect(
        (jsonDecode(sent.body) as Map<String, dynamic>)['client_request_id'],
        clientRequestId,
      );
    },
  );

  test(
    'v3 agent reconnects a broken stream through the stable request URL',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      const clientRequestId = '123e4567-e89b-42d3-a456-426614174071';
      final methods = <String>[];
      final urls = <String>[];
      var elapsedReads = 0;
      final client = MockClient((request) async {
        methods.add(request.method);
        urls.add(request.url.toString());
        if (methods.length == 1) {
          return http.Response(
            _agentSse([
              (
                'ready',
                {
                  'version': 1,
                  'request_id': '00000000-0000-4000-8000-000000000070',
                  'client_request_id': clientRequestId,
                  'heartbeat_interval_ms': 10000,
                  'execution_budget_seconds': 480,
                },
              ),
              (
                'heartbeat',
                {
                  'version': 1,
                  'request_id': '00000000-0000-4000-8000-000000000070',
                  'client_request_id': clientRequestId,
                  'sequence': 1,
                },
              ),
            ]),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }
        return http.Response(
          _agentSse([
            (
              'ready',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000070',
                'client_request_id': clientRequestId,
                'heartbeat_interval_ms': 10000,
                'execution_budget_seconds': 480,
              },
            ),
            (
              'result',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000070',
                'client_request_id': clientRequestId,
                'response': _agentCompletedJson(
                  requestId: '00000000-0000-4000-8000-000000000070',
                  conversationId: '123e4567-e89b-42d3-a456-426614174070',
                  answer: '已从断流恢复。',
                ),
              },
            ),
          ]),
          200,
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
        agentRecoveryElapsed: () =>
            elapsedReads++ == 0 ? Duration.zero : const Duration(minutes: 4),
      );

      final result = await service.runAgentTurn(
        username: 'student01',
        conversationId: '123e4567-e89b-42d3-a456-426614174070',
        clientRequestId: clientRequestId,
        message: '断流后继续。',
        agentProtocolVersion: 3,
      );

      expect(result.chatResult?.answer, '已从断流恢复。');
      expect(methods, ['POST', 'GET']);
      expect(urls.last, endsWith('/stream/$clientRequestId'));
    },
  );

  test('v3 agent stream preserves a typed terminal error', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final consentStore = _MemoryConsentStore(enabled: true);
    const clientRequestId = '123e4567-e89b-42d3-a456-426614174081';
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        _agentSse([
          (
            'ready',
            {
              'version': 1,
              'request_id': '00000000-0000-4000-8000-000000000080',
              'client_request_id': clientRequestId,
              'heartbeat_interval_ms': 10000,
              'execution_budget_seconds': 480,
            },
          ),
          (
            'error',
            {
              'version': 1,
              'request_id': '00000000-0000-4000-8000-000000000080',
              'client_request_id': clientRequestId,
              'status_code': 502,
              'detail': {
                'code': 'provider_timeout',
                'stage': 'provider',
                'retry_policy': 'new_request',
              },
            },
          ),
        ]),
        200,
        headers: const {'content-type': 'text/event-stream; charset=utf-8'},
      );
    });
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: usageStore,
      consentStore: consentStore,
      baseUrl: 'https://sync.example',
    );

    await expectLater(
      service.runAgentTurn(
        username: 'student01',
        conversationId: '123e4567-e89b-42d3-a456-426614174080',
        clientRequestId: clientRequestId,
        message: '冲突测试。',
        agentProtocolVersion: 3,
      ),
      throwsA(
        isA<AiAssistantRemoteStatusException>().having(
          (error) => error.code,
          'code',
          'provider_timeout',
        ),
      ),
    );
    expect(requests, 1);
  });

  test('v3 SSE accepts CRLF events split across UTF-8 chunks', () async {
    const clientRequestId = '123e4567-e89b-42d3-a456-426614174091';
    final sse = _agentSse([
      (
        'ready',
        {
          'version': 1,
          'request_id': '00000000-0000-4000-8000-000000000090',
          'client_request_id': clientRequestId,
          'heartbeat_interval_ms': 10000,
          'execution_budget_seconds': 480,
        },
      ),
      (
        'result',
        {
          'version': 1,
          'request_id': '00000000-0000-4000-8000-000000000090',
          'client_request_id': clientRequestId,
          'response': _agentCompletedJson(
            requestId: '00000000-0000-4000-8000-000000000090',
            conversationId: '123e4567-e89b-42d3-a456-426614174090',
            answer: '分块完成。',
          ),
        },
      ),
    ]);
    final bytes = utf8.encode(sse);
    final client = _StreamClient(
      (request) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          bytes.sublist(0, 19),
          bytes.sublist(19, 111),
          bytes.sublist(111),
        ]),
        200,
        headers: const {'content-type': 'text/event-stream'},
      ),
    );
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
    );

    final result = await service.runAgentTurn(
      username: 'student01',
      conversationId: '123e4567-e89b-42d3-a456-426614174090',
      clientRequestId: clientRequestId,
      message: '分块测试。',
      agentProtocolVersion: 3,
    );

    expect(result.chatResult?.answer, '分块完成。');
  });

  test('v3 SSE rejects an event envelope with a mismatched event name', () async {
    const clientRequestId = '123e4567-e89b-42d3-a456-426614174101';
    final client = MockClient(
      (request) async => http.Response(
        'event: ready\ndata: ${jsonEncode({'event': 'heartbeat', 'version': 1, 'request_id': '00000000-0000-4000-8000-000000000100', 'client_request_id': clientRequestId, 'heartbeat_interval_ms': 10000, 'execution_budget_seconds': 480})}\n\n',
        200,
        headers: const {'content-type': 'text/event-stream'},
      ),
    );
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
    );

    await expectLater(
      service.runAgentTurn(
        username: 'student01',
        conversationId: '123e4567-e89b-42d3-a456-426614174100',
        clientRequestId: clientRequestId,
        message: '校验事件。',
        agentProtocolVersion: 3,
      ),
      throwsA(isA<AiAssistantException>()),
    );
  });

  test(
    'v3 SSE rejects unknown events and mismatched client identities',
    () async {
      const clientRequestId = '123e4567-e89b-42d3-a456-426614174111';
      RemoteAiAssistantService serviceFor(String sse) =>
          RemoteAiAssistantService(
            syncAllowed: (_) => true,
            client: MockClient(
              (request) async => http.Response(
                sse,
                200,
                headers: const {'content-type': 'text/event-stream'},
              ),
            ),
            usageStore: _MemoryUsageSyncStore(
              record: const UsageSyncDeviceRecord(
                installationId: 'installation-id-000000000000000001',
                deviceToken: 'dev_existing-token',
              ),
            ),
            consentStore: _MemoryConsentStore(enabled: true),
            baseUrl: 'https://sync.example',
          );
      Future<void> expectRejected(RemoteAiAssistantService service) =>
          expectLater(
            service.runAgentTurn(
              username: 'student01',
              conversationId: '123e4567-e89b-42d3-a456-426614174110',
              clientRequestId: clientRequestId,
              message: '校验身份。',
              agentProtocolVersion: 3,
            ),
            throwsA(isA<AiAssistantException>()),
          );

      await expectRejected(
        serviceFor(
          _agentSse([
            (
              'unexpected',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000110',
                'client_request_id': clientRequestId,
              },
            ),
          ]),
        ),
      );
      await expectRejected(
        serviceFor(
          _agentSse([
            (
              'ready',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000110',
                'client_request_id': '123e4567-e89b-42d3-a456-426614174112',
                'heartbeat_interval_ms': 10000,
                'execution_budget_seconds': 480,
              },
            ),
          ]),
        ),
      );
      await expectRejected(
        serviceFor(
          _agentSse([
            (
              'ready',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000110',
                'client_request_id': clientRequestId,
                'heartbeat_interval_ms': 10000,
                'execution_budget_seconds': 480,
              },
            ),
            (
              'result',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000110',
                'client_request_id': clientRequestId,
                'response': _agentCompletedJson(
                  requestId: '00000000-0000-4000-8000-000000000119',
                  conversationId: '123e4567-e89b-42d3-a456-426614174110',
                  answer: 'wrong request id',
                ),
              },
            ),
          ]),
        ),
      );
      await expectRejected(
        serviceFor(
          _agentSse([
            (
              'ready',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000110',
                'client_request_id': clientRequestId,
                'heartbeat_interval_ms': 10000,
                'execution_budget_seconds': 480,
              },
            ),
            (
              'result',
              {
                'version': 1,
                'request_id': '00000000-0000-4000-8000-000000000110',
                'client_request_id': clientRequestId,
                'response': _agentCompletedJson(
                  requestId: '00000000-0000-4000-8000-000000000110',
                  conversationId: '123e4567-e89b-42d3-a456-426614174119',
                  answer: 'wrong conversation id',
                ),
              },
            ),
          ]),
        ),
      );
    },
  );

  test('v3 SSE only accepts the bounded heartbeat and event limits', () async {
    const clientRequestId = '123e4567-e89b-42d3-a456-426614174121';
    const requestId = '00000000-0000-4000-8000-000000000120';
    const conversationId = '123e4567-e89b-42d3-a456-426614174120';
    RemoteAiAssistantService serviceFor(
      List<(String, Map<String, dynamic>)> events,
    ) => RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(_agentSse(events)),
          200,
          headers: const {'content-type': 'text/event-stream'},
        ),
      ),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
    );
    List<(String, Map<String, dynamic>)> streamWith(
      int heartbeatInterval,
      int heartbeatCount,
    ) => [
      (
        'ready',
        {
          'version': 1,
          'request_id': requestId,
          'client_request_id': clientRequestId,
          'heartbeat_interval_ms': heartbeatInterval,
          'execution_budget_seconds': 540,
        },
      ),
      ...List.generate(
        heartbeatCount,
        (index) => (
          'heartbeat',
          {
            'version': 1,
            'request_id': requestId,
            'client_request_id': clientRequestId,
            'sequence': index + 1,
          },
        ),
      ),
      (
        'result',
        {
          'version': 1,
          'request_id': requestId,
          'client_request_id': clientRequestId,
          'response': _agentCompletedJson(
            requestId: requestId,
            conversationId: conversationId,
            answer: 'bounded',
          ),
        },
      ),
    ];
    Future<AssistantAgentTurnResult> run(RemoteAiAssistantService service) =>
        service.runAgentTurn(
          username: 'student01',
          conversationId: conversationId,
          clientRequestId: clientRequestId,
          message: '边界测试。',
          agentProtocolVersion: 3,
        );

    expect(
      (await run(serviceFor(streamWith(5000, 126)))).chatResult?.answer,
      'bounded',
    );
    expect(
      (await run(serviceFor(streamWith(30000, 0)))).chatResult?.answer,
      'bounded',
    );
    await expectLater(
      run(serviceFor(streamWith(4999, 0))),
      throwsA(isA<AiAssistantException>()),
    );
    await expectLater(
      run(serviceFor(streamWith(30001, 0))),
      throwsA(isA<AiAssistantException>()),
    );
    await expectLater(
      run(serviceFor(streamWith(5000, 127))),
      throwsA(isA<AiAssistantException>()),
    );
  });

  test('high agent turn uses native effort without reducing output', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final consentStore = _MemoryConsentStore(enabled: true);
    late Map<String, dynamic> payload;
    final client = MockClient((request) async {
      payload = jsonDecode(request.body) as Map<String, dynamic>;
      return _jsonResponse({
        'request_id': '00000000-0000-4000-8000-000000000040',
        'conversation_id': '123e4567-e89b-42d3-a456-426614174040',
        'status': 'completed',
        'round': 1,
        'tool_calls': [],
        'continuation_token': '',
        'answer': '已深度核对。',
        'actions': [],
        'suggestions': [],
        'usage': {'input_tokens': 12, 'output_tokens': 7, 'total_tokens': 19},
        'quota': _quotaJson(remaining: 9981, used: 19),
      }, 200);
    });
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: usageStore,
      consentStore: consentStore,
      baseUrl: 'https://sync.example',
    );

    final result = await service.runAgentTurn(
      username: 'student01',
      conversationId: '123e4567-e89b-42d3-a456-426614174040',
      clientRequestId: '123e4567-e89b-42d3-a456-426614174041',
      message: '把 OOP 的演示课件打包',
      thinkingMode: AssistantThinkingMode.high,
      maxOutputTokens: 4096,
    );

    expect(result.chatResult?.answer, '已深度核对。');
    expect(payload['thinking_mode'], 'high');
    expect(payload['max_output_tokens'], 4096);

    await service.runAgentTurn(
      username: 'student01',
      conversationId: '123e4567-e89b-42d3-a456-426614174040',
      clientRequestId: '123e4567-e89b-42d3-a456-426614174042',
      message: '旧协议兼容请求',
      thinkingMode: AssistantThinkingMode.high,
      agentProtocolVersion: 1,
      maxOutputTokens: 2000,
    );
    expect(payload['thinking_mode'], 'deep');
    expect(payload['max_output_tokens'], 2000);
  });

  test(
    'agent turn retries the same idempotent request after network loss',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      final requestBodies = <String>[];
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        requestBodies.add(request.body);
        if (attempts == 1) {
          throw http.ClientException('response lost', request.url);
        }
        return _jsonResponse({
          'request_id': '00000000-0000-4000-8000-000000000020',
          'conversation_id': '123e4567-e89b-42d3-a456-426614174020',
          'status': 'completed',
          'round': 1,
          'tool_calls': [],
          'continuation_token': '',
          'answer': '已恢复 Agent 请求。',
          'actions': [],
          'suggestions': [],
          'usage': {'input_tokens': 10, 'output_tokens': 6, 'total_tokens': 16},
          'quota': _quotaJson(remaining: 9984, used: 16),
        }, 200);
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      final result = await service.runAgentTurn(
        username: 'student01',
        conversationId: '123e4567-e89b-42d3-a456-426614174020',
        clientRequestId: '123e4567-e89b-42d3-a456-426614174021',
        message: '继续',
        availableSources: const {AssistantContextSource.currentPage},
      );

      expect(result.chatResult?.answer, '已恢复 Agent 请求。');
      expect(attempts, 2);
      expect(requestBodies[1], requestBodies[0]);
    },
  );

  test(
    'agent turn recovers four transient failures with one request body',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      final requestBodies = <String>[];
      final delays = <Duration>[];
      final progress = <AiAssistantRemoteProgress>[];
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        requestBodies.add(request.body);
        if (attempts == 1) {
          return _jsonResponse({
            'detail': {
              'code': 'provider_rate_limited',
              'stage': 'provider_response',
              'retry_policy': 'retry_after',
              'retry_after_ms': 1500,
            },
          }, 503);
        }
        if (attempts == 2) {
          return _jsonResponse({
            'detail': {
              'code': 'provider_agent_error',
              'stage': 'provider_request',
              'retry_policy': 'new_request',
            },
          }, 502);
        }
        if (attempts == 3) {
          return _jsonResponse({
            'detail': {
              'code': 'provider_server_error',
              'stage': 'provider_response',
              'retry_policy': 'new_request',
            },
          }, 502);
        }
        if (attempts == 4) {
          return http.Response('upstream gateway unavailable', 504);
        }
        return _jsonResponse({
          'request_id': '00000000-0000-4000-8000-000000000030',
          'conversation_id': '123e4567-e89b-42d3-a456-426614174030',
          'status': 'completed',
          'round': 1,
          'tool_calls': [],
          'continuation_token': '',
          'answer': 'Provider 已恢复。',
          'actions': [],
          'suggestions': [],
          'usage': {'input_tokens': 10, 'output_tokens': 6, 'total_tokens': 16},
          'quota': _quotaJson(remaining: 9984, used: 16),
        }, 200);
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
        retryDelay: (delay) async => delays.add(delay),
      );

      final result = await service.runAgentTurn(
        username: 'student01',
        conversationId: '123e4567-e89b-42d3-a456-426614174030',
        clientRequestId: '123e4567-e89b-42d3-a456-426614174031',
        message: '测试恢复',
        onProgress: progress.add,
      );

      expect(result.chatResult?.answer, 'Provider 已恢复。');
      expect(attempts, 5);
      expect(requestBodies.toSet(), hasLength(1));
      expect(delays, hasLength(4));
      expect(delays.first, const Duration(milliseconds: 1500));
      expect(progress.map((item) => item.networkRecoveryAttempt), [1, 2, 3, 4]);
      expect(progress.map((item) => item.maxNetworkRecoveries).toSet(), {4});
    },
  );

  test(
    'agent turn reports recovery exhaustion after the final transient failure',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      final requestBodies = <String>[];
      final progress = <AiAssistantRemoteProgress>[];
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        requestBodies.add(request.body);
        return _jsonResponse({
          'detail': {
            'code': 'provider_timeout',
            'stage': 'provider_request',
            'retry_policy': 'new_request',
          },
        }, 502);
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      await expectLater(
        service.runAgentTurn(
          username: 'student01',
          conversationId: '123e4567-e89b-42d3-a456-426614174040',
          clientRequestId: '123e4567-e89b-42d3-a456-426614174041',
          message: '测试恢复耗尽',
          onProgress: progress.add,
        ),
        throwsA(
          isA<AiAssistantAgentRecoveryExhaustedException>().having(
            (error) => error.message,
            'message',
            contains('安全上限'),
          ),
        ),
      );

      expect(attempts, 5);
      expect(requestBodies.toSet(), hasLength(1));
      expect(progress.map((item) => item.networkRecoveryAttempt), [1, 2, 3, 4]);
    },
  );

  test(
    'agent turn does not disguise a deterministic agent error as network',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return _jsonResponse({
          'detail': {
            'code': 'agent_step_limit',
            'stage': 'agent_loop',
            'retry_policy': 'new_request',
          },
        }, 502);
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      await expectLater(
        service.runAgentTurn(
          username: 'student01',
          conversationId: '123e4567-e89b-42d3-a456-426614174050',
          clientRequestId: '123e4567-e89b-42d3-a456-426614174051',
          message: '测试逻辑错误',
        ),
        throwsA(
          isA<AiAssistantRemoteStatusException>().having(
            (error) => error.code,
            'code',
            'agent_step_limit',
          ),
        ),
      );
      expect(attempts, 1);
    },
  );

  test('chat serializes explicitly selected attachments', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final consentStore = _MemoryConsentStore(enabled: true);
    late Map<String, dynamic> requestPayload;
    final client = MockClient((request) async {
      requestPayload = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'request_id': '00000000-0000-4000-8000-000000000005',
          'answer': '我看到了附件。',
          'actions': [],
          'usage': {
            'input_tokens': 20,
            'output_tokens': 10,
            'total_tokens': 30,
          },
          'quota': _quotaJson(remaining: 9970, used: 30),
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: client,
      usageStore: usageStore,
      consentStore: consentStore,
      baseUrl: 'https://sync.example',
    );

    await service.chatWithAttachments(
      username: 'student01',
      message: '看看图片',
      history: const [],
      context: const AssistantContextPayload(sources: {}),
      attachments: [
        AssistantInputAttachment(
          name: 'campus.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
        ),
      ],
      clientRequestId: '123e4567-e89b-42d3-a456-426614174001',
    );

    final attachments = requestPayload['attachments'] as List<dynamic>;
    expect(attachments, hasLength(1));
    expect(attachments.single, containsPair('data_base64', 'iVBORw=='));
    expect(attachments.single, containsPair('mime_type', 'image/png'));
    expect(requestPayload, isNot(contains('password')));
  });

  for (final mimeType in ['image/png', 'text/plain']) {
    test(
      'chat accepts a 50 MB $mimeType through the real serializer',
      () async {
        final usageStore = _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        );
        final consentStore = _MemoryConsentStore(enabled: true);
        late Map<String, dynamic> requestPayload;
        final client = MockClient((request) async {
          requestPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'request_id': '00000000-0000-4000-8000-000000000005',
              'answer': '我看到了附件。',
              'actions': [],
              'usage': {
                'input_tokens': 20,
                'output_tokens': 10,
                'total_tokens': 30,
              },
              'quota': _quotaJson(remaining: 9970, used: 30),
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final service = RemoteAiAssistantService(
          syncAllowed: (_) => true,
          client: client,
          usageStore: usageStore,
          consentStore: consentStore,
          baseUrl: 'https://sync.example',
        );

        await service.chatWithAttachments(
          username: 'student01',
          message: '看看图片',
          history: const [],
          context: const AssistantContextPayload(sources: {}),
          attachments: [
            AssistantInputAttachment(
              name: 'campus.png',
              mimeType: mimeType,
              bytes: Uint8List(50 * 1024 * 1024),
            ),
          ],
          clientRequestId: '123e4567-e89b-42d3-a456-426614174001',
        );

        final attachments = requestPayload['attachments'] as List<dynamic>;
        expect(attachments, hasLength(1));
        expect(
          base64Decode(
            (attachments.single as Map)['data_base64'] as String,
          ).length,
          50 * 1024 * 1024,
        );
        expect(attachments.single, containsPair('mime_type', mimeType));
        expect(requestPayload, isNot(contains('password')));
      },
    );
  }

  test(
    'study mode uses its dedicated protocol and synchronized file copy',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      final pdfBytes = Uint8List.fromList('%PDF-1.7\npage'.codeUnits);
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') return http.Response('', 204);
        if (request.method == 'GET') {
          return http.Response.bytes(
            pdfBytes,
            200,
            headers: const {'content-type': 'application/pdf'},
          );
        }
        return http.Response(
          jsonEncode({
            'request_id': '00000000-0000-0000-0000-000000000003',
            'answer': '已按本页内容整理。',
            'actions': [],
            'suggestions': [],
            'usage': {
              'input_tokens': 20,
              'output_tokens': 10,
              'total_tokens': 30,
            },
            'quota': _quotaJson(remaining: 9970, used: 30),
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );
      final documentKey = List.filled(64, 'a').join();

      await service.uploadStudyDocument(
        username: 'student01',
        documentKey: documentKey,
        title: 'Lecture 01.pdf',
        mimeType: 'application/pdf',
        bytes: pdfBytes,
      );
      final copy = await service.downloadStudyDocument(
        username: 'student01',
        documentKey: documentKey,
      );
      final result = await service.studyChat(
        username: 'student01',
        message: '整理本页',
        history: const [],
        attachments: const [],
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
      );

      expect(copy?.bytes, pdfBytes);
      expect(copy?.mimeType, 'application/pdf');
      expect(result.answer, '已按本页内容整理。');
      expect(requests.map((item) => item.method), ['PUT', 'GET', 'POST']);
      expect(
        requests.first.url.path,
        '/v1/assistant/study/documents/$documentKey',
      );
      expect(requests.first.bodyBytes, pdfBytes);
      expect(requests.first.headers['X-Study-Document-Title'], isNotEmpty);
      final chatPayload =
          jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(chatPayload['mode'], 'study');
      expect((chatPayload['context'] as Map)['sources'], isEmpty);
    },
  );

  test('plan refuses to send content while assistant is disabled', () async {
    var requests = 0;
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 500);
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(),
      baseUrl: 'https://sync.example',
    );

    await expectLater(
      service.planContext(
        username: 'student01',
        message: '帮我安排一下',
        history: const [],
        availableSources: const {AssistantContextSource.schedule},
        availableActions: const {AssistantActionType.openAppTab},
      ),
      throwsA(isA<AiAssistantConsentRequiredException>()),
    );
    expect(requests, 0);
  });

  test(
    'rejected device token is cleared without email-only enrollment',
    () async {
      var requests = 0;
      final store = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_rejected',
        ),
      );
      final service = RemoteAiAssistantService(
        usageStore: store,
        consentStore: _MemoryConsentStore(enabled: true),
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, '/v1/assistant/quota');
          return http.Response('{}', 401);
        }),
      );
      await expectLater(
        service.loadQuota('student01'),
        throwsA(isA<MeBindingRequired>()),
      );
      expect(requests, 1);
      expect(store.record?.deviceToken, isNull);
      service.dispose();
    },
  );

  test(
    'late chat 401 cannot re-enroll after the operation is disabled',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_expired-token',
        ),
      );
      final consentStore = _MemoryConsentStore(enabled: true);
      final chatStarted = Completer<void>();
      final chatResponse = Completer<http.Response>();
      var chatRequests = 0;
      var enrollments = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/assistant/chat') {
          chatRequests++;
          if (!chatStarted.isCompleted) {
            chatStarted.complete();
          }
          return chatResponse.future;
        }
        if (request.url.path == '/v1/enrollment') {
          enrollments++;
          return http.Response('{}', 500);
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: consentStore,
        baseUrl: 'https://sync.example',
      );
      var isOperationActive = true;

      final result = service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
        isOperationActive: () => isOperationActive,
      );
      await chatStarted.future;
      consentStore.enabled = false;
      isOperationActive = false;
      chatResponse.complete(http.Response('{}', 401));

      await expectLater(
        result,
        throwsA(isA<AiAssistantOperationCancelledException>()),
      );
      expect(chatRequests, 1);
      expect(enrollments, 0);
      expect(usageStore.record?.deviceToken, 'dev_expired-token');
    },
  );

  test('missing ME identity is not a retryable chat transport error', () async {
    var requests = 0;
    final service = RemoteAiAssistantService(
      usageStore: _MemoryUsageSyncStore(),
      consentStore: _MemoryConsentStore(enabled: true),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    await expectLater(
      service.loadQuota('student01'),
      throwsA(isA<MeBindingRequired>()),
    );
    expect(requests, 0);
    service.dispose();
  });

  test(
    'credential-looking user message is rejected before network access',
    () async {
      final usageStore = _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      );
      final client = MockClient((request) async {
        fail('Network must not be called for credential-looking messages.');
      });
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: client,
        usageStore: usageStore,
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );

      await expectLater(
        service.chat(
          username: 'student01',
          message: 'Cookie: secret',
          history: const [],
          context: const AssistantContextPayload(sources: {}),
        ),
        throwsA(isA<AiAssistantException>()),
      );
    },
  );

  test(
    'network transport failures use the retryable exception subtype',
    () async {
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          throw http.ClientException('test transport failure', request.url);
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      await expectLater(
        service.chat(
          username: 'student01',
          message: '整理课程',
          history: const [],
          context: const AssistantContextPayload(sources: {}),
          clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsA(isA<AiAssistantChatNetworkException>()),
      );
    },
  );

  test(
    'HTTP stream failures are classified as retryable network errors',
    () async {
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          throw const HttpException('response stream closed');
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      await expectLater(
        service.chat(
          username: 'student01',
          message: '整理课程',
          history: const [],
          context: const AssistantContextPayload(sources: {}),
          clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsA(isA<AiAssistantChatNetworkException>()),
      );
    },
  );

  test(
    'HTTP business failures are not marked as retryable network errors',
    () async {
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async => http.Response('{}', 503)),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );

      await expectLater(
        service.chat(
          username: 'student01',
          message: '整理课程',
          history: const [],
          context: const AssistantContextPayload(sources: {}),
          clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsA(
          isA<AiAssistantException>().having(
            (error) => error is AiAssistantNetworkException,
            'is network error',
            isFalse,
          ),
        ),
      );
    },
  );

  test(
    'lost POST response is reconciled with status GET before replaying',
    () async {
      const requestId = '123e4567-e89b-42d3-a456-426614174000';
      final requests = <http.Request>[];
      final progress = <AiAssistantRemoteProgress>[];
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v1/assistant/chat') {
            throw http.ClientException('lost chat response', request.url);
          }
          expect(request.url.path, '/v1/assistant/requests/$requestId');
          return _jsonResponse(
            _statusJson(result: _chatResponseJson(answer: '状态恢复完成。')),
            200,
          );
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      final result = await service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: requestId,
        onProgress: progress.add,
      );

      expect(result.answer, '状态恢复完成。');
      expect(
        requests
            .map((request) => '${request.method} ${request.url.path}')
            .toList(),
        ['POST /v1/assistant/chat', 'GET /v1/assistant/requests/$requestId'],
      );
      expect(progress.map((item) => item.status), contains('completed'));
    },
  );

  test(
    'non JSON edge 502 polls status using retry_after before replaying',
    () async {
      const requestId = '123e4567-e89b-42d3-a456-426614174000';
      final requests = <http.Request>[];
      final delays = <Duration>[];
      var statusCalls = 0;
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v1/assistant/chat') {
            return http.Response('<html>Bad Gateway</html>', 502);
          }
          statusCalls++;
          if (statusCalls == 1) {
            return _jsonResponse(
              _statusJson(
                status: 'provider_pending',
                code: 'provider_pending',
                stage: 'provider_request',
                retryPolicy: 'poll_status',
                retryAfterMs: 75,
              ),
              202,
            );
          }
          return _jsonResponse(
            _statusJson(result: _chatResponseJson(answer: '轮询恢复完成。')),
            200,
          );
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
        retryDelay: (delay) async {
          delays.add(delay);
        },
      );

      final result = await service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: requestId,
      );

      expect(result.answer, '轮询恢复完成。');
      expect(
        requests
            .map((request) => '${request.method} ${request.url.path}')
            .toList(),
        [
          'POST /v1/assistant/chat',
          'GET /v1/assistant/requests/$requestId',
          'GET /v1/assistant/requests/$requestId',
        ],
      );
      expect(delays, [const Duration(milliseconds: 75)]);
    },
  );

  test(
    'missing durable status replays POST with the same client request ID',
    () async {
      const requestId = '123e4567-e89b-42d3-a456-426614174000';
      final requests = <http.Request>[];
      final postPayloads = <Map<String, dynamic>>[];
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v1/assistant/chat') {
            postPayloads.add(jsonDecode(request.body) as Map<String, dynamic>);
            if (postPayloads.length == 1) {
              throw http.ClientException('lost chat response', request.url);
            }
            return _jsonResponse(_chatResponseJson(), 200);
          }
          expect(request.url.path, '/v1/assistant/requests/$requestId');
          return http.Response('not found', 404);
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      await service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: requestId,
      );

      expect(
        requests
            .map((request) => '${request.method} ${request.url.path}')
            .toList(),
        [
          'POST /v1/assistant/chat',
          'GET /v1/assistant/requests/$requestId',
          'POST /v1/assistant/chat',
        ],
      );
      expect(
        postPayloads.map((payload) => payload['client_request_id']).toSet(),
        {requestId},
      );
    },
  );

  test('ambiguous status stops without replaying provider request', () async {
    const requestId = '123e4567-e89b-42d3-a456-426614174000';
    final requests = <http.Request>[];
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/v1/assistant/chat') {
          return http.Response('<html>Bad Gateway</html>', 502);
        }
        return http.Response(
          jsonEncode(
            _statusJson(
              status: 'ambiguous',
              code: 'provider_outcome_ambiguous',
              stage: 'provider_request',
              retryPolicy: 'do_not_retry',
            ),
          ),
          409,
        );
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {},
    );

    await expectLater(
      service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: requestId,
      ),
      throwsA(
        isA<AiAssistantRemoteStatusException>()
            .having((error) => error.code, 'code', 'provider_outcome_ambiguous')
            .having(
              (error) => error.retryPolicy,
              'retryPolicy',
              'do_not_retry',
            ),
      ),
    );
    expect(
      requests
          .map((request) => '${request.method} ${request.url.path}')
          .toList(),
      ['POST /v1/assistant/chat', 'GET /v1/assistant/requests/$requestId'],
    );
  });

  test(
    'completed but not replayable status stops without changing request ID',
    () async {
      const requestId = '123e4567-e89b-42d3-a456-426614174000';
      final requests = <http.Request>[];
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v1/assistant/chat') {
            throw http.ClientException('lost chat response', request.url);
          }
          return http.Response(
            jsonEncode(
              _statusJson(
                status: 'completed',
                code: 'result_not_replayable',
                stage: 'result_replay',
                retryPolicy: 'new_request',
              ),
            ),
            410,
          );
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
        retryDelay: (_) async {},
      );

      await expectLater(
        service.chat(
          username: 'student01',
          message: '整理课程',
          history: const [],
          context: const AssistantContextPayload(sources: {}),
          clientRequestId: requestId,
        ),
        throwsA(
          isA<AiAssistantRemoteStatusException>().having(
            (error) => error.code,
            'code',
            'result_not_replayable',
          ),
        ),
      );
      expect(
        requests
            .map((request) => '${request.method} ${request.url.path}')
            .toList(),
        ['POST /v1/assistant/chat', 'GET /v1/assistant/requests/$requestId'],
      );
    },
  );

  test('typed 503 stops without status polling or replay', () async {
    final requests = <http.Request>[];
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'provider_not_configured',
              'stage': 'configuration',
              'retry_policy': 'contact_admin',
            },
          }),
          503,
        );
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {},
    );

    await expectLater(
      service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsA(
        isA<AiAssistantRemoteStatusException>().having(
          (error) => error.code,
          'code',
          'provider_not_configured',
        ),
      ),
    );
    expect(
      requests
          .map((request) => '${request.method} ${request.url.path}')
          .toList(),
      ['POST /v1/assistant/chat'],
    );
  });

  test('typed 429 maps to quota exception without status polling', () async {
    final requests = <http.Request>[];
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'quota_exceeded',
              'stage': 'reservation',
              'retry_policy': 'retry_after',
              'retry_after_ms': 60000,
            },
          }),
          429,
        );
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {},
    );

    await expectLater(
      service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsA(isA<AiAssistantQuotaExceededException>()),
    );
    expect(
      requests
          .map((request) => '${request.method} ${request.url.path}')
          .toList(),
      ['POST /v1/assistant/chat'],
    );
  });

  test('typed 409 conflict preserves server code without replay', () async {
    final requests = <http.Request>[];
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'client_request_id_conflict',
              'stage': 'received',
              'retry_policy': 'do_not_retry',
            },
          }),
          409,
        );
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {},
    );

    await expectLater(
      service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsA(
        isA<AiAssistantRemoteStatusException>()
            .having((error) => error.code, 'code', 'client_request_id_conflict')
            .having((error) => error.stage, 'stage', 'received')
            .having(
              (error) => error.retryPolicy,
              'retryPolicy',
              'do_not_retry',
            ),
      ),
    );
    expect(
      requests
          .map((request) => '${request.method} ${request.url.path}')
          .toList(),
      ['POST /v1/assistant/chat'],
    );
  });

  test('typed safe 502 retries ten times with a fresh request id', () async {
    final requests = <http.Request>[];
    final progress = <AiAssistantRemoteProgress>[];
    var failures = 0;
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        if (failures++ == 10) {
          return _jsonResponse(_chatResponseJson(), 200);
        }
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'provider_connection_timeout',
              'stage': 'provider_connect',
              'retry_policy': 'new_request',
            },
          }),
          502,
        );
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {},
    );

    final result = await service.chat(
      username: 'student01',
      message: '整理课程',
      history: const [],
      context: const AssistantContextPayload(sources: {}),
      clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
      onProgress: progress.add,
    );
    expect(result.answer, '完成。');
    expect(requests, hasLength(11));
    final requestIds = requests
        .map(
          (request) =>
              (jsonDecode(request.body)
                      as Map<String, dynamic>)['client_request_id']
                  as String,
        )
        .toList();
    expect(requestIds.toSet(), hasLength(11));
    expect(requestIds.first, '123e4567-e89b-42d3-a456-426614174000');
    expect(
      progress
          .map((item) => item.networkRecoveryAttempt)
          .whereType<int>()
          .toList(),
      List<int>.generate(10, (index) => index + 1),
    );
  });

  test('typed 502 marked do_not_retry is never replayed', () async {
    final requests = <http.Request>[];
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'detail': {
              'code': 'provider_outcome_ambiguous',
              'stage': 'provider_request',
              'retry_policy': 'do_not_retry',
            },
          }),
          502,
        );
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {},
    );

    await expectLater(
      service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsA(
        isA<AiAssistantRemoteStatusException>().having(
          (error) => error.retryPolicy,
          'retryPolicy',
          'do_not_retry',
        ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('operation cancellation stops status polling', () async {
    const requestId = '123e4567-e89b-42d3-a456-426614174000';
    final requests = <http.Request>[];
    var active = true;
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/v1/assistant/chat') {
          return http.Response('<html>Bad Gateway</html>', 502);
        }
        return http.Response(
          jsonEncode(
            _statusJson(
              status: 'provider_pending',
              code: 'provider_pending',
              stage: 'provider_request',
              retryPolicy: 'poll_status',
              retryAfterMs: 10,
            ),
          ),
          202,
        );
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {
        active = false;
      },
    );

    await expectLater(
      service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: requestId,
        isOperationActive: () => active,
      ),
      throwsA(isA<AiAssistantOperationCancelledException>()),
    );
    expect(
      requests
          .map((request) => '${request.method} ${request.url.path}')
          .toList(),
      ['POST /v1/assistant/chat', 'GET /v1/assistant/requests/$requestId'],
    );
  });

  test('chat uses at most ten network recoveries', () async {
    const requestId = '123e4567-e89b-42d3-a456-426614174000';
    final requests = <http.Request>[];
    final progress = <AiAssistantRemoteProgress>[];
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/v1/assistant/chat') {
          return http.Response('<html>Bad Gateway</html>', 502);
        }
        return http.Response('not found', 404);
      }),
      usageStore: _MemoryUsageSyncStore(
        record: const UsageSyncDeviceRecord(
          installationId: 'installation-id-000000000000000001',
          deviceToken: 'dev_existing-token',
        ),
      ),
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
      retryDelay: (_) async {},
    );

    await expectLater(
      service.chat(
        username: 'student01',
        message: '整理课程',
        history: const [],
        context: const AssistantContextPayload(sources: {}),
        clientRequestId: requestId,
        onProgress: progress.add,
      ),
      throwsA(isA<AiAssistantChatRecoveryExhaustedException>()),
    );
    expect(
      requests.where((request) => request.url.path == '/v1/assistant/chat'),
      hasLength(11),
    );
    expect(
      requests.where(
        (request) => request.url.path == '/v1/assistant/requests/$requestId',
      ),
      hasLength(10),
    );
    expect(
      progress
          .map((item) => item.networkRecoveryAttempt)
          .whereType<int>()
          .toList(),
      List<int>.generate(10, (index) => index + 1),
    );
  });

  test(
    'radar preferences use account settings with CAS and consent revision',
    () async {
      var missing = true;
      var conflict = false;
      final service = RemoteAiAssistantService(
        syncAllowed: (_) => true,
        client: MockClient((request) async {
          expect(request.url.path, '/v1/settings/mail_radar.v1');
          expect(request.headers['authorization'], 'Bearer dev_existing-token');
          if (conflict) {
            return _jsonResponse({
              'detail': {'current_version': 3},
            }, 409);
          }
          if (request.method == 'GET' && missing) {
            return _jsonResponse({'detail': 'settings not found'}, 404);
          }
          if (request.method == 'PUT') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['expected_version'], 0);
            expect(body['value'], {
              'schema_version': 1,
              'enabled': true,
              'lookback_days': 7,
              'consent_version': mailRadarConsentVersion,
            });
            missing = false;
          }
          return _jsonResponse({
            'namespace': 'mail_radar.v1',
            'version': 1,
            'value': {
              'schema_version': 1,
              'enabled': true,
              'lookback_days': 7,
              'consent_version': mailRadarConsentVersion,
            },
          }, 200);
        }),
        usageStore: _MemoryUsageSyncStore(
          record: const UsageSyncDeviceRecord(
            installationId: 'installation-id-000000000000000001',
            deviceToken: 'dev_existing-token',
          ),
        ),
        consentStore: _MemoryConsentStore(enabled: true),
        baseUrl: 'https://sync.example',
      );
      expect(await service.loadRadarPreferences('student01'), isNull);
      final saved = await service.saveRadarPreferences(
        'student01',
        0,
        const MailRadarPreferences(
          hasConsent: true,
          enabled: true,
          lookbackDays: 7,
        ),
      );
      expect(saved.version, 1);
      expect(
        (await service.loadRadarPreferences(
          'student01',
        ))!.preferences.lookbackDays,
        7,
      );
      conflict = true;
      await expectLater(
        service.saveRadarPreferences('student01', 0, saved.preferences),
        throwsA(isA<MailRadarPreferenceConflict>()),
      );
      service.dispose();
    },
  );

  test('disabling assistant preserves shared device identity', () async {
    final usageStore = _MemoryUsageSyncStore(
      record: const UsageSyncDeviceRecord(
        installationId: 'installation-id-000000000000000001',
        deviceToken: 'dev_existing-token',
      ),
    );
    final service = RemoteAiAssistantService(
      syncAllowed: (_) => true,
      client: MockClient((request) async {
        fail('Disabling AI must not delete an always-on activity device.');
      }),
      usageStore: usageStore,
      consentStore: _MemoryConsentStore(enabled: true),
      baseUrl: 'https://sync.example',
    );

    await service.setEnabled('student01', false);

    expect(usageStore.record?.deviceToken, 'dev_existing-token');
  });
}

http.Response _jsonResponse(Map<String, dynamic> body, int statusCode) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

String _agentSse(List<(String, Map<String, dynamic>)> events) => events
    .map(
      (item) =>
          'event: ${item.$1}\r\ndata: ${jsonEncode({...item.$2, 'event': item.$1})}\r\n\r\n',
    )
    .join();

Map<String, dynamic> _agentCompletedJson({
  required String requestId,
  required String conversationId,
  required String answer,
}) => {
  'request_id': requestId,
  'conversation_id': conversationId,
  'status': 'completed',
  'round': 1,
  'tool_calls': [],
  'continuation_token': '',
  'answer': answer,
  'actions': [],
  'suggestions': [],
  'usage': {'input_tokens': 20, 'output_tokens': 8, 'total_tokens': 28},
  'quota': _quotaJson(remaining: 9972, used: 28),
};

Map<String, dynamic> _quotaJson({int remaining = 10000, int used = 0}) {
  return {
    'period_start': '2026-07-01T00:00:00Z',
    'period_end': '2026-08-01T00:00:00Z',
    'monthly_quota_tokens': 10000,
    'credit_balance_tokens': 0,
    'used_tokens': used,
    'reserved_tokens': 0,
    'remaining_tokens': remaining,
  };
}

Map<String, dynamic> _chatResponseJson({String answer = '完成。'}) {
  return {
    'request_id': '00000000-0000-0000-0000-000000000003',
    'answer': answer,
    'actions': [],
    'usage': {'input_tokens': 20, 'output_tokens': 10, 'total_tokens': 30},
    'quota': _quotaJson(remaining: 9970, used: 30),
  };
}

Map<String, dynamic> _statusJson({
  String status = 'completed',
  String code = 'completed',
  String stage = 'completed',
  String retryPolicy = 'none',
  int? retryAfterMs,
  Map<String, dynamic>? result,
}) {
  return {
    'request_id': '00000000-0000-0000-0000-000000000003',
    'client_request_id': '123e4567-e89b-42d3-a456-426614174000',
    'status': status,
    'code': code,
    'stage': stage,
    'retry_policy': retryPolicy,
    'retry_after_ms': retryAfterMs,
    'result_replayable': result != null,
    'replay_expires_at': result == null ? null : '2026-07-01T00:05:00Z',
    'usage': result == null
        ? null
        : {'input_tokens': 20, 'output_tokens': 10, 'total_tokens': 30},
    'result': result,
  };
}

class _MemoryConsentStore implements AiAssistantConsentStore {
  _MemoryConsentStore({this.enabled = false});

  bool enabled;

  @override
  Future<bool> canSyncInBackground(String email) async => enabled;

  @override
  Future<bool> isEnabled(String email) async => enabled;

  @override
  Future<void> setEnabled(String email, bool enabled) async {
    this.enabled = enabled;
  }
}

class _MemoryUsageSyncStore implements UsageSyncStore {
  _MemoryUsageSyncStore({this.record});

  UsageSyncDeviceRecord? record;

  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async => record;

  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async {
    this.record = record;
  }
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
