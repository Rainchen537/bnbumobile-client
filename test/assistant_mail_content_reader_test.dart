import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/assistant/assistant_mail_content_reader.dart';
import 'package:bnbu_me/services/mail_service.dart';

void main() {
  const credentials = MailAccessCredentials(
    userId: 'student',
    emailAddress: 'student@mail.bnbu.edu.cn',
    password: 'test-password',
  );
  final now = DateTime.parse('2026-09-04T12:00:00+08:00');

  test(
    'search resumes beyond 200 envelopes without a false empty result',
    () async {
      final service = _ReaderMailService(
        summaries: List.generate(
          230,
          (i) => _summary(
            uid: 230 - i,
            sender: i == 220
                ? 'Target <target@bnbu.edu.cn>'
                : 'Other <other@bnbu.edu.cn>',
            date: now,
          ),
        ),
      );
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => credentials,
        mailService: service,
        now: () => now,
      );
      final first = await reader.findMessages(
        const AssistantMailSearchRequest(
          query: 'Target',
          searchScope: 'metadata',
          includeBody: false,
        ),
      );
      expect(first.messages, isEmpty);
      expect(first.completeness, 'truncated');
      expect(first.nextCursor, isNotEmpty);
      final next = await reader.findMessages(
        AssistantMailSearchRequest(
          query: 'Target',
          searchScope: 'metadata',
          includeBody: false,
          cursor: first.nextCursor,
        ),
      );
      expect(next.messages.single.uid, 10);
      expect(next.scanComplete, isTrue);
    },
  );

  test('body-only terms are searchable without marking mail read', () async {
    final service = _ReaderMailService(
      summaries: [
        _summary(uid: 11, sender: 'Teacher <one@bnbu.edu.cn>', date: now),
      ],
      details: {
        11: _detail(
          uid: 11,
          sender: 'Teacher <one@bnbu.edu.cn>',
          body: 'The hidden deadline is Friday',
        ),
      },
    );
    final reader = AssistantMailContentReader(
      credentialsLoader: () async => credentials,
      mailService: service,
      now: () => now,
    );
    final result = await reader.findMessages(
      const AssistantMailSearchRequest(
        query: 'hidden deadline',
        searchScope: 'body',
      ),
    );
    expect(result.messages.single.uid, 11);
    expect(service.lastMarkAsSeen, isFalse);
  });

  test(
    'long multilingual bodies can be reassembled with byte-safe pages',
    () async {
      final body = '文😀' * 9000;
      final service = _ReaderMailService(
        details: {
          31: _detail(uid: 31, sender: 'Teacher <one@bnbu.edu.cn>', body: body),
        },
      );
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => credentials,
        mailService: service,
        now: () => now,
      );
      const identity = MailMessageIdentity(
        folder: MailFolder.inbox,
        uid: 31,
        mailboxUidValidity: 9001,
      );
      var offset = 0;
      final parts = <String>[];
      do {
        final result = await reader.readMessages([
          identity,
        ], bodyOffset: offset);
        expect(
          utf8.encode(jsonEncode(result.toJson())).length,
          lessThan(64 * 1024),
        );
        final message = result.messages.single;
        parts.add(message.bodyText);
        if (message.nextBodyOffset == null) break;
        expect(message.nextBodyOffset, greaterThan(offset));
        offset = message.nextBodyOffset!;
      } while (true);
      expect(parts.join(), body);
    },
  );

  test(
    'findMessages reads recent official mail bodies in one unseen batch',
    () async {
      final service = _ReaderMailService(
        summaries: [
          _summary(
            uid: 11,
            sender: 'Teacher One <one@bnbu.edu.cn>',
            date: now.subtract(const Duration(hours: 2)),
          ),
          _summary(
            uid: 12,
            sender: 'Teacher Two <two@bnbu.edu.cn>',
            date: now.subtract(const Duration(hours: 8)),
          ),
          _summary(
            uid: 13,
            sender: 'Student <student2@mail.bnbu.edu.cn>',
            date: now.subtract(const Duration(hours: 1)),
          ),
          _summary(
            uid: 14,
            sender: 'Old Teacher <old@bnbu.edu.cn>',
            date: now.subtract(const Duration(days: 4)),
          ),
        ],
        details: {
          11: _detail(
            uid: 11,
            sender: 'Teacher One <one@bnbu.edu.cn>',
            body: 'First reply',
          ),
          12: _detail(
            uid: 12,
            sender: 'Teacher Two <two@bnbu.edu.cn>',
            body: 'Second reply',
          ),
        },
      );
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => credentials,
        mailService: service,
        now: () => now,
      );

      final result = await reader.findMessages(
        const AssistantMailSearchRequest(
          lookbackDays: 2,
          officialSendersOnly: true,
          includeBody: true,
        ),
      );

      expect(result.kind, 'mail_search');
      expect(result.completeness, 'complete');
      expect(result.resultKey, matches(RegExp(r'^mail-search:[0-9a-f]{64}$')));
      expect(result.messages.map((message) => message.uid), [11, 12]);
      expect(result.messages.map((message) => message.bodyText), [
        'First reply',
        'Second reply',
      ]);
      expect(service.batchReadCalls, 1);
      expect(service.lastMarkAsSeen, isFalse);
    },
  );

  test(
    'findMessages reports metadata without pretending it read bodies',
    () async {
      final service = _ReaderMailService(
        summaries: [
          _summary(uid: 21, sender: 'Teacher <teacher@bnbu.edu.cn>', date: now),
        ],
      );
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => credentials,
        mailService: service,
        now: () => now,
      );

      final result = await reader.findMessages(
        const AssistantMailSearchRequest(includeBody: false),
      );

      expect(result.messages.single.contentState, 'metadata_only');
      expect(result.messages.single.bodyText, isEmpty);
      expect(service.batchReadCalls, 0);
    },
  );

  test(
    'readMessages keeps stable identity and bounds oversized bodies',
    () async {
      final service = _ReaderMailService(
        details: {
          31: _detail(
            uid: 31,
            sender: 'Teacher <teacher@bnbu.edu.cn>',
            body: 'x' * (20 * 1024),
          ),
        },
      );
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => credentials,
        mailService: service,
        now: () => now,
      );

      final result = await reader.readMessages(const [
        MailMessageIdentity(
          folder: MailFolder.inbox,
          uid: 31,
          mailboxUidValidity: 9001,
        ),
      ]);

      expect(result.kind, 'mail_messages');
      expect(result.messages.single.stableIdentity, 'inbox:9001:31');
      expect(result.messages.single.contentState, 'truncated');
      expect(result.messages.single.bodyText.length, 12 * 1024);
      expect(service.lastMarkAsSeen, isFalse);
    },
  );

  test(
    'reader reports unavailable instead of inventing body content',
    () async {
      final service = _ReaderMailService(
        summaries: [
          _summary(uid: 41, sender: 'Teacher <teacher@bnbu.edu.cn>', date: now),
        ],
        failBatchRead: true,
      );
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => credentials,
        mailService: service,
        now: () => now,
      );

      final search = await reader.findMessages(
        const AssistantMailSearchRequest(includeBody: true),
      );
      expect(search.messages.single.contentState, 'unavailable');
      expect(search.messages.single.bodyText, isEmpty);

      final read = await reader.readMessages(const [
        MailMessageIdentity(
          folder: MailFolder.inbox,
          uid: 41,
          mailboxUidValidity: 9001,
        ),
      ]);
      expect(read.completeness, 'unavailable');
      expect(read.messages, isEmpty);
    },
  );

  test(
    'reader distinguishes an unparseable HTML body from an empty mail',
    () async {
      final service = _ReaderMailService(
        details: {
          42: _detail(
            uid: 42,
            sender: 'Teacher <teacher@bnbu.edu.cn>',
            body: '',
            htmlBody: '<div></div>',
          ),
        },
      );
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => credentials,
        mailService: service,
        now: () => now,
      );

      final result = await reader.readMessages(const [
        MailMessageIdentity(
          folder: MailFolder.inbox,
          uid: 42,
          mailboxUidValidity: 9001,
        ),
      ]);

      expect(result.messages.single.contentState, 'parse_failed');
      expect(result.messages.single.bodyText, isEmpty);
    },
  );

  test(
    'reader rejects mail access without the app session credentials',
    () async {
      final reader = AssistantMailContentReader(
        credentialsLoader: () async => null,
        mailService: _ReaderMailService(),
        now: () => now,
      );

      await expectLater(
        reader.findMessages(const AssistantMailSearchRequest()),
        throwsA(
          isA<AssistantMailContentException>().having(
            (error) => error.message,
            'message',
            contains('登录'),
          ),
        ),
      );
    },
  );
}

MailMessageSummary _summary({
  required int uid,
  required String sender,
  required DateTime date,
}) {
  return MailMessageSummary(
    uid: uid,
    subject: 'Reply $uid',
    sender: sender,
    preview: '',
    hasHtmlBody: false,
    date: date,
    isSeen: false,
    folder: MailFolder.inbox,
    mailboxUidValidity: 9001,
  );
}

MailMessageDetail _detail({
  required int uid,
  required String sender,
  required String body,
  String? htmlBody,
}) {
  return MailMessageDetail(
    uid: uid,
    subject: 'Reply $uid',
    sender: sender,
    recipients: 'student@mail.bnbu.edu.cn',
    cc: null,
    date: DateTime.parse('2026-09-04T10:00:00+08:00'),
    body: body,
    htmlBody: htmlBody,
    isSeen: false,
    mailboxUidValidity: 9001,
    folder: MailFolder.inbox,
  );
}

class _ReaderMailService extends MailService {
  _ReaderMailService({
    this.summaries = const [],
    this.details = const {},
    this.failBatchRead = false,
  });

  final List<MailMessageSummary> summaries;
  final Map<int, MailMessageDetail> details;
  final bool failBatchRead;
  int batchReadCalls = 0;
  bool? lastMarkAsSeen;

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    return MailFolderSnapshot(
      emailAddress: credentials.emailAddress,
      incomingServer: 'imap.example.test',
      outgoingServer: 'smtp.example.test',
      messages: summaries.skip((page - 1) * pageSize).take(pageSize).toList(),
      fetchedAt: DateTime.parse('2026-09-04T12:00:00+08:00'),
      folder: folder,
      totalMessages: summaries.length,
      currentPage: page,
      pageSize: pageSize,
      mailboxUidValidity: 9001,
    );
  }

  @override
  Future<List<MailMessageDetail>> readMessages({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    bool markAsSeen = true,
  }) async {
    batchReadCalls++;
    lastMarkAsSeen = markAsSeen;
    if (failBatchRead) {
      throw const MailServiceException('mailbox unavailable');
    }
    return messages.map((identity) => details[identity.uid]!).toList();
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async => details[uid]!;

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) async => summaries;

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {}

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) async => const [];

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {}

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) async => null;

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {}

  @override
  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  }) async {}

  @override
  Future<void> close() async {}
}
