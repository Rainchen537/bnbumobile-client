import 'dart:convert';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/mail_radar_analyzer.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/services/mail_source_service.dart';
import 'package:bnbu_me/services/sync/account_sync_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const credentials = MailAccessCredentials(
  userId: 'fixture',
  emailAddress: 'fixture@example.org',
  password: 'fixture-only',
);
MailMessageDetail mail(String body) => MailMessageDetail(
  uid: 7,
  mailboxUidValidity: 99,
  subject: 'Campus concert',
  sender: 'campus@example.org',
  recipients: 'all_students@example.org',
  cc: null,
  date: DateTime.now().subtract(const Duration(days: 45)),
  body: body,
  htmlBody: null,
  isSeen: false,
);
MailMessageSummary summary(MailMessageDetail detail) => MailMessageSummary(
  uid: detail.uid,
  mailboxUidValidity: detail.mailboxUidValidity,
  subject: detail.subject,
  sender: detail.sender,
  preview: '',
  date: detail.date,
  isSeen: false,
  hasAttachments: false,
  hasHtmlBody: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Unicode excerpts remain valid at emoji boundaries', () {
    final original = '${'a' * 41999}🎉${'b' * 61000}尾';
    final excerpt = mailSourceExcerpt(original, 60000);
    expect(utf8.decode(utf8.encode(excerpt)), excerpt);
    expect(excerpt, endsWith('尾'));
    expect(mailSourceLimit('🎉abc', 1), '');
    expect(mailSourceLimit('🎉abc', 2), '🎉');
    final legacy = 'a' * 80000;
    expect(
      mailSourceExcerpt(legacy, 60000),
      '${legacy.substring(0, 42000)}\n...[中间省略]...\n${legacy.substring(62018)}',
    );
    final damaged = String.fromCharCode(0xd83c);
    for (final text in [
      mailSourceLimit(damaged, 5),
      mailSourceExcerpt(damaged, 50),
      mailSourceBoundedText(damaged, 500),
    ]) {
      expect(utf8.decode(utf8.encode(text)), text);
    }
  });
  test(
    'classification version invalidates not-selected without reupload',
    () async {
      final remote = SourceFixture()..notSelected = true;
      final mailbox = MailboxFixture(mail('Campus concert'));
      final analyzer = MailSourceRadarAnalyzer(
        assistantService: AssistantFixture(),
        radarService: AssistantFixture(),
        source: remote,
        storage: MemoryStorage(),
      );
      await analyzer.collect(
        username: 'fixture',
        credentials: credentials,
        mailService: mailbox,
        active: () => true,
      );
      Future<MailRadarItem> acquire() => analyzer.analyze(
        clientRequestId: 'fixture',
        username: 'fixture',
        credentials: credentials,
        summary: summary(mailbox.detail),
        detail: mailbox.detail,
        mailService: mailbox,
      );
      await expectLater(acquire(), throwsA(isA<MailSourceSkipped>()));
      final key = mailRadarMessageKey(MailFolder.inbox, 99, 7);
      expect(analyzer.isNotSelected(key), true);
      remote.version++;
      remote.notSelected = false;
      await analyzer.policy('fixture');
      expect(analyzer.isNotSelected(key), false);
      expect((await acquire()).category, MailRadarCategory.event);
      expect(remote.requests.where((r) => r.$1 == 'observations').length, 1);
      expect(remote.requests.where((r) => r.$1 == 'acquire').length, 2);
    },
  );
  test('invalid material is retained as a bounded failure receipt', () async {
    final remote = SourceFixture()..invalidUpload = true;
    final mailbox = MailboxFixture(mail('Ordinary mail'));
    final storage = MemoryStorage();
    final analyzer = MailSourceRadarAnalyzer(
      assistantService: AssistantFixture(),
      radarService: AssistantFixture(),
      source: remote,
      storage: storage,
    );
    await analyzer.collect(
      username: 'fixture',
      credentials: credentials,
      mailService: mailbox,
      active: () => true,
    );
    expect(analyzer.collectionError, 'invalid_request');
    expect(storage.value!.values.single['status'], 'invalid_input');
    expect(storage.value.toString(), isNot(contains('Ordinary mail')));
    await analyzer.collect(
      username: 'fixture',
      credentials: credentials,
      mailService: mailbox,
      active: () => true,
    );
    expect(remote.requests.where((r) => r.$1 == 'observations').length, 1);
  });
  test('conditional actions retain the audience and condition', () {
    final text = mailSourceActionText({
      'action_items': [
        {
          'action': 'Pay the fee',
          'obligation': 'conditional_required',
          'applies_to': 'Registered participants',
          'condition': 'Only if payment is outstanding',
          'deadline_text': '',
        },
      ],
    }, 'en');
    expect(text, contains('Required if applicable'));
    expect(text, contains('Only if payment is outstanding'));
    expect(text, contains('Registered participants'));
  });
  test(
    'CJK body and attachment budgets retain evidence tails without exceeding server bytes',
    () {
      final original = '${'校园活动' * 25000}报名截止';
      final bounded = mailSourceBoundedText(original, 128 * 1024);
      expect(utf8.encode(bounded).length, lessThanOrEqualTo(128 * 1024));
      expect(bounded, endsWith('报名截止'));
      expect(bounded, contains('[content omitted]'));
    },
  );
  test(
    '90 day collection, actual mailbox observation, header-only preflight and manual mode',
    () async {
      final remote = SourceFixture(),
          mailbox = MailboxFixture(mail('Campus concert'));
      final analyzer = MailSourceRadarAnalyzer(
        assistantService: AssistantFixture(),
        radarService: AssistantFixture(),
        source: remote,
        storage: MemoryStorage(),
      );
      expect(analyzer.hasSourceConsent, false);
      await analyzer.collect(
        username: 'fixture',
        credentials: credentials,
        mailService: mailbox,
        active: () => true,
      );
      expect(analyzer.hasSourceConsent, true);
      expect(remote.requests.map((r) => r.$1), [
        'policy',
        'preflight',
        'observations',
      ]);
      final preflight = remote.requests[1].$2!;
      expect(preflight.containsKey('body'), false);
      expect(preflight['headers']['recipients'], contains('all_students'));
      expect(preflight['headers']['uid_validity'], 99);
      expect(mailbox.markedSeen, false);
      final item = await analyzer.analyze(
        clientRequestId: 'fixture',
        username: 'fixture',
        credentials: credentials,
        summary: summary(mailbox.detail),
        detail: mailbox.detail,
        mailService: mailbox,
        manual: true,
      );
      expect(remote.requests.last.$2!['mode'], 'manual');
      expect(remote.requests.last.$2!['observation_id'], 'actual-observation');
      expect(item.summaryZh, '校园音乐会');
      final pending = item.copyWith(analysisPending: true);
      final sourceItems = [pending, item];
      expect(analyzer.publishableSnapshot(sourceItems), [item]);
      expect(
        sourceItems.length,
        2,
      ); // Privacy projection must not delete local intent.
      final sensitive = MailRadarItem.fromJson({
        ...item.toJson(),
        'subject': '验证码：123456',
      });
      expect(analyzer.publishableSnapshot([sensitive]), isEmpty);
      expect(remote.requests.where((r) => r.$1 == 'observations').length, 1);
    },
  );
  test('missing consent and configuration never upload mail', () async {
    final source = SourceFixture()..ready = false;
    final mailbox = MailboxFixture(mail('Campus concert'));
    final analyzer = MailSourceRadarAnalyzer(
      assistantService: AssistantFixture(),
      radarService: AssistantFixture(),
      source: source,
      storage: MemoryStorage(),
    );
    await expectLater(
      analyzer.collect(
        username: 'fixture',
        credentials: credentials,
        mailService: mailbox,
        active: () => true,
      ),
      throwsA(isA<MailSourceException>()),
    );
    expect(source.requests.map((r) => r.$1), ['policy']);
    expect(mailbox.reads, 0);
  });
  test(
    'secrets stay on the device, ordinary personal mail is allowed',
    () async {
      for (final body in [
        '验证码：123456',
        'Your verification code is 987654',
        'access_token: secret123456',
      ]) {
        expect(mailSourceContainsSecret(body), true);
      }
      for (final body in [
        '验证码安全讲座',
        'verification code examples and lecture',
        'Dear Alice, meet after class?',
      ]) {
        expect(mailSourceContainsSecret(body), false);
      }
      final source = SourceFixture(),
          mailbox = MailboxFixture(mail('验证码：123456'));
      final analyzer = MailSourceRadarAnalyzer(
        assistantService: AssistantFixture(),
        radarService: AssistantFixture(),
        source: source,
        storage: MemoryStorage(),
      );
      await analyzer.collect(
        username: 'fixture',
        credentials: credentials,
        mailService: mailbox,
        active: () => true,
      );
      expect(source.requests.map((r) => r.$1), ['policy']);
      expect(analyzer.isNotSelected('99_7'), true);
    },
  );
}

class AssistantFixture
    implements AiAssistantService, AiAssistantMailRadarService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SourceFixture implements MailSourceService {
  bool ready = true;
  final requests = <(String, Map<String, dynamic>?)>[];
  int version = 1;
  bool notSelected = false, invalidUpload = false;
  @override
  Future<Map<String, dynamic>> mailSourceRequest(
    String username,
    String endpoint, {
    Map<String, dynamic>? body,
    bool Function()? isOperationActive,
  }) async {
    requests.add((endpoint, body));
    if (endpoint == 'acquire' && notSelected) return {'status': 'not_selected'};
    if (endpoint == 'observations' && invalidUpload) {
      throw const MailSourceException('invalid_request');
    }
    return switch (endpoint) {
      'policy' => {
        'version': version,
        'source_days': 90,
        'readiness': ready ? 'ready' : 'provider_not_configured',
        'consent': {
          'enabled': true,
          'current': true,
          'approved': true,
          'epoch': 1,
        },
      },
      'preflight' => {'status': 'allowed', 'ticket': 'ticket'},
      'observations' => {
        'status': 'accepted',
        'observation_id': 'actual-observation',
      },
      'acquire' => {
        'status': 'completed',
        'result': {
          'radar': {
            'category': 'event',
            'priority': 'normal',
            'summaries': {
              'zh-Hans': '校园音乐会',
              'zh-Hant': '校園音樂會',
              'en': 'Concert',
            },
            'deadline_text': '',
            'deadline_evidence': '',
            'deadline_precision': 'none',
          },
          'events': [],
          'actions': [],
          'missing_fields': [],
          'complete': true,
        },
      },
      _ => throw StateError(endpoint),
    };
  }
}

class MemoryStorage extends AccountSyncStorage {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read(String owner, String domain) async =>
      value;
  @override
  Future<void> writeIfCurrent(
    String owner,
    String domain,
    Map<String, dynamic> data, {
    required bool Function() isCurrent,
  }) async {
    if (isCurrent()) value = Map.of(data);
  }
}

class MailboxFixture implements MailService {
  MailboxFixture(this.detail);
  final MailMessageDetail detail;
  bool markedSeen = false;
  int reads = 0;
  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async {
    markedSeen = markAsSeen;
    reads++;
    return detail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchFolder) {
      return Future.value(
        MailFolderSnapshot(
          emailAddress: 'fixture@example.org',
          incomingServer: 'fixture',
          outgoingServer: 'fixture',
          fetchedAt: DateTime.now(),
          currentPage: 1,
          pageSize: 50,
          folder: MailFolder.inbox,
          messages: [summary(detail)],
          totalMessages: 1,
          mailboxUidValidity: 99,
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}
