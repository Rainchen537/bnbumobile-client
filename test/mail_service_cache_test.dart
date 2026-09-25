import 'dart:io';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail/src/private/util/client_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_local_cache.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/services/mail_service_io.dart';

class _Imap extends ImapClient {
  _Imap({this.supportsSort = false}) : super(isLogEnabled: false);
  final bool supportsSort;
  late final ImapServerInfo _fixtureServerInfo = ImapServerInfo(
    ConnectionInfo('imap.example.test', 993, isSecure: true),
  )..capabilities = supportsSort ? const [Capability('SORT')] : const [];

  @override
  ImapServerInfo get serverInfo => _fixtureServerInfo;
  final uids = [10, 11];
  final seen = <int>{};
  final headerRequests = <List<int>>[];
  int validity = 77;
  bool singlePart = false;
  String plainPreviewText = 'Reusable body';
  int textSize = 40;
  int structures = 0;
  final definitions = <String>[];
  final sequenceRequests = <String>[];
  final sortCriteria = <String>[];
  final headerDates = <int, String>{};
  BodyPart structure() {
    BodyPart part(
      String mime,
      int size, {
      String? cid,
      bool attachment = false,
    }) => BodyPart()
      ..contentType = ContentTypeHeader(mime)
      ..size = size
      ..encoding = '8bit'
      ..cid = cid
      ..contentDisposition = attachment
          ? ContentDispositionHeader.attachment(filename: 'file.txt')
          : null;
    if (singlePart) return part('text/plain; charset=utf-8', textSize);
    final root = part('multipart/mixed', 800);
    root.addPart(part('text/plain; charset=utf-8', textSize));
    root.addPart(part('text/html; charset=utf-8', textSize));
    root.addPart(part('image/png', 80, cid: '<logo>'));
    root.addPart(part('text/plain', 100, attachment: true));
    return root;
  }

  Mailbox get box => Mailbox(
    encodedName: 'INBOX',
    encodedPath: 'INBOX',
    flags: [MailboxFlag.inbox],
    pathSeparator: '/',
    uidValidity: validity,
    messagesExists: uids.length,
    messagesUnseen: uids.length - seen.length,
  );

  MimeMessage message(int uid, {bool headers = false}) =>
      (headers
            ? MimeMessage.parseFromText(
                'Subject: Notice $uid\r\n'
                'From: Teacher <teacher@example.test>\r\n'
                'To: Student <student@example.test>\r\n'
                'Date: ${headerDates[uid] ?? 'Mon, 07 Sep 2026 10:30:00 +0800'}\r\n\r\n',
              )
            : MimeMessage())
        ..uid = uid
        ..size = uid * 1000
        ..flags = [if (seen.contains(uid)) MessageFlags.seen];

  @override
  Future<SortImapResult> uidSortMessages(
    String criteria, [
    String searchCriteria = 'ALL',
    String charset = 'UTF-8',
    List<ReturnOption>? returnOptions,
  ]) async {
    sortCriteria.add('$criteria:$searchCriteria');
    return SortImapResult()
      ..matchingSequence = MessageSequence.fromIds(uids, isUid: true);
  }

  @override
  Future<Mailbox> statusMailbox(
    Mailbox mailbox,
    List<StatusFlags> flags,
  ) async => box;
  @override
  Future<FetchImapResult> fetchMessagesByCriteria(
    String criteria, {
    Duration? responseTimeout,
  }) async {
    expect(criteria, endsWith('(UID FLAGS)'));
    sequenceRequests.add(criteria);
    final range = RegExp(r'^(\d+):(\d+) ').firstMatch(criteria)!;
    final first = int.parse(range[1]!);
    final last = int.parse(range[2]!);
    return FetchImapResult(
      uids.skip(first - 1).take(last - first + 1).map(message).toList(),
      null,
    );
  }

  @override
  Future<FetchImapResult> uidFetchMessages(
    MessageSequence sequence,
    String? definition, {
    int? changedSinceModSequence,
    Duration? responseTimeout,
  }) async {
    final ids = sequence.toList().where(uids.contains).toList();
    definitions.add(definition!);
    final headers = definition.contains('HEADER.FIELDS');
    if (headers) headerRequests.add(ids);
    return FetchImapResult(
      ids.map((id) {
        final result = message(id, headers: headers);
        for (final match in RegExp(
          r'BODY\.PEEK\[([0-9.]+)\]',
        ).allMatches(definition)) {
          final partId = match.group(1)!;
          final raw = partId == '2'
              ? '<p>Reusable body</p><img src="cid:logo">'
              : partId == '3'
              ? 'small-image'
              : plainPreviewText;
          result.setPart(
            partId,
            MimePart()..mimeData = TextMimeData(raw, containsHeader: false),
          );
        }
        return result;
      }).toList(),
      null,
    );
  }
}

class _Client extends MailClient {
  _Client(this.imap)
    : super(
        MailAccount.fromManualSettings(
          name: 'Synthetic',
          email: 'synthetic@example.test',
          userName: 'synthetic',
          password: 'fixture',
          incomingHost: 'imap.example.test',
          outgoingHost: 'smtp.example.test',
        ),
      );
  final _Imap imap;
  @override
  bool get isConnected => true;
  @override
  ImapClient get lowLevelIncomingMailClient => imap;
  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<Mailbox>> listMailboxes({List<MailboxFlag>? order}) async => [
    imap.box,
  ];
  @override
  Future<List<MimeMessage>> fetchMessageSequence(
    MessageSequence sequence, {
    Mailbox? mailbox,
    FetchPreference fetchPreference = FetchPreference.fullWhenWithinSize,
    bool markAsSeen = false,
  }) async {
    expect(markAsSeen, isFalse);
    if (fetchPreference == FetchPreference.bodystructure) imap.structures++;
    return [
      for (final uid in sequence.toList())
        imap.message(uid, headers: true)..body = imap.structure(),
    ];
  }

  @override
  Future<Mailbox> selectMailboxByPath(
    String path, {
    bool enableCondStore = false,
    QResyncParameters? qresync,
  }) async => imap.box;
}

void main() {
  const credentials = MailAccessCredentials(
    userId: 'synthetic',
    emailAddress: 'synthetic@example.test',
    password: 'fixture',
  );
  late Directory root;
  late _Imap imap;
  final key = SecretKey(List.filled(32, 21));
  MailLocalCache store() =>
      MailLocalCache(directory: () async => root, key: () async => key);
  MailService service() => createPlatformMailService(
    cache: store(),
    clientFactory: (_) => _Client(imap),
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'bnbu-mail-transport-fixture-',
    );
    imap = _Imap();
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'startup and radar sequence reads remain one bounded newest page',
    () async {
      imap.uids
        ..clear()
        ..addAll(List.generate(450, (index) => index + 10));
      final mail = service();
      final page = await mail.fetchFolder(
        credentials: credentials,
        pageSize: 25,
      );
      expect(page.messages, hasLength(25));
      expect(page.totalMessages, 450);
      expect(imap.sequenceRequests, ['426:450 (UID FLAGS)']);
      expect(imap.headerRequests.expand((uids) => uids).length, 25);
      expect(imap.sortCriteria, isEmpty);
      expect(imap.structures, 0);
      await mail.close();
    },
  );

  test(
    'plain MIME preview decodes entities while cached full body stays original',
    () async {
      imap.plainPreviewText = '各位同学： &nbsp; A&amp;B &#x1F600;';
      final mail = service();
      final folder = await mail.fetchFolder(credentials: credentials);
      final previews = await (mail as MailOrganizationService).loadPreviews(
        credentials: credentials,
        messages: [folder.messages.first],
      );
      expect(previews.single.preview, '各位同学： A&B 😀');
      final detail = await mail.readMessage(
        credentials: credentials,
        folder: MailFolder.inbox,
        uid: previews.single.uid,
        expectedMailboxUidValidity: 77,
        markAsSeen: false,
      );
      expect(detail.body, imap.plainPreviewText);
      expect(detail.htmlBody, contains('Reusable body'));
      await mail.close();
    },
  );

  test(
    'preview length never splits a supplementary Unicode character',
    () async {
      imap.plainPreviewText = '${List.filled(87, 'a').join()}😀tail';
      final mail = service();
      final folder = await mail.fetchFolder(credentials: credentials);
      final previews = await (mail as MailOrganizationService).loadPreviews(
        credentials: credentials,
        messages: [folder.messages.first],
      );
      expect(previews.single.preview, '${List.filled(87, 'a').join()}😀...');
      await mail.close();
    },
  );

  test(
    'preview saves complete text, excludes attachments and images, then reopens offline',
    () async {
      final mail = service();
      final folder = await mail.fetchFolder(credentials: credentials);
      final previews = await (mail as MailOrganizationService).loadPreviews(
        credentials: credentials,
        messages: [folder.messages.first],
      );
      expect(previews.single.preview, contains('Reusable body'));
      final fetched = imap.definitions
          .where((d) => d.contains('BODY.PEEK[1]'))
          .toList();
      expect(fetched, hasLength(1));
      expect(fetched.single, contains('BODY.PEEK[2]'));
      expect(fetched.single, isNot(contains('BODY.PEEK[3]')));
      expect(fetched.single, isNot(contains('BODY.PEEK[4]')));
      await mail.close();
      final reopened = service();
      final detail = await reopened.readMessage(
        credentials: credentials,
        folder: MailFolder.inbox,
        uid: 11,
        expectedMailboxUidValidity: 77,
        markAsSeen: false,
      );
      expect(detail.body, 'Reusable body');
      expect(detail.htmlBody, contains('Reusable body'));
      expect(detail.inlineImagesLoaded, isFalse);
      expect(detail.attachments.single.partId, '4');
      final enriched = await (reopened as MailInlineImageLoader)
          .loadInlineImages(credentials: credentials, detail: detail);
      expect(enriched.body, 'Reusable body');
      expect(enriched.htmlBody, contains('data:image/png;base64,'));
      expect(enriched.inlineImagesLoaded, isTrue);
      expect(
        imap.definitions.where((d) => d.contains('BODY.PEEK[1]')),
        hasLength(1),
      );
      await reopened.close();
    },
  );

  test(
    'server DATE sort pages the complete result and preserves RFC822 size',
    () async {
      imap = _Imap(supportsSort: true);
      final mail = service() as MailSortedFolderReader;

      final oldest = await mail.fetchSortedFolder(
        credentials: credentials,
        folder: MailFolder.inbox,
        sortOrder: MailSortOrder.oldestFirst,
        pageSize: 1,
      );
      final newest = await mail.fetchSortedFolder(
        credentials: credentials,
        folder: MailFolder.inbox,
        sortOrder: MailSortOrder.newestFirst,
        pageSize: 1,
      );

      expect(oldest.messages.single.uid, 10);
      expect(oldest.messages.single.messageSizeBytes, 10000);
      expect(newest.messages.single.uid, 11);
      expect(imap.sortCriteria, everyElement('DATE:ALL'));
      expect(
        imap.definitions.any(
          (definition) => definition.contains('RFC822.SIZE'),
        ),
        isTrue,
      );
    },
  );

  test(
    'metadata fallback sorts the complete result without downloading bodies',
    () async {
      imap.headerDates
        ..[10] = 'Tue, 08 Sep 2026 10:30:00 +0800'
        ..[11] = 'Mon, 07 Sep 2026 10:30:00 +0800';
      final mail = service() as MailSortedFolderReader;

      final oldest = await mail.fetchSortedFolder(
        credentials: credentials,
        folder: MailFolder.inbox,
        sortOrder: MailSortOrder.oldestFirst,
        pageSize: 1,
      );
      final newest = await mail.fetchSortedFolder(
        credentials: credentials,
        folder: MailFolder.inbox,
        sortOrder: MailSortOrder.newestFirst,
        pageSize: 1,
      );

      expect(oldest.messages.single.uid, 11);
      expect(newest.messages.single.uid, 10);
      expect(imap.headerRequests.first.toSet(), {10, 11});
      expect(
        imap.definitions.any(
          (definition) => RegExp(r'BODY\.PEEK\[\d').hasMatch(definition),
        ),
        isFalse,
      );
    },
  );

  test(
    'single-part body retains MIME type and is cached from preview',
    () async {
      imap.singlePart = true;
      final mail = service();
      final folder = await mail.fetchFolder(credentials: credentials);
      await (mail as MailOrganizationService).loadPreviews(
        credentials: credentials,
        messages: folder.messages,
      );
      final detail = await (mail as MailCacheReader).readCachedMessage(
        credentials: credentials,
        identity: folder.messages.first.identity!,
      );
      expect(detail?.body, 'Reusable body');
      expect(detail?.inlineImagesLoaded, isTrue);
      await mail.close();
    },
  );

  test(
    'oversized preview never records a partial message as complete detail',
    () async {
      imap.singlePart = true;
      imap.textSize = 512 * 1024;
      final mail = service();
      final folder = await mail.fetchFolder(credentials: credentials);
      await (mail as MailOrganizationService).loadPreviews(
        credentials: credentials,
        messages: [folder.messages.first],
      );
      final detail = await (mail as MailCacheReader).readCachedMessage(
        credentials: credentials,
        identity: folder.messages.first.identity!,
      );
      expect(detail, isNull);
      expect(imap.definitions.any((d) => d.contains('BODY.PEEK[1]')), isFalse);
      final complete = await mail.readMessage(
        credentials: credentials,
        folder: MailFolder.inbox,
        uid: 11,
        expectedMailboxUidValidity: 77,
        markAsSeen: false,
      );
      expect(complete.body, 'Reusable body');
      await mail.close();
    },
  );

  test(
    'reopened service only fetches headers of newly arrived messages',
    () async {
      var mail = service();
      final first = await mail.fetchFolder(credentials: credentials);
      expect(first.messages.map((m) => m.subject), ['Notice 11', 'Notice 10']);
      expect(imap.headerRequests.single.toSet(), {10, 11});
      await mail.close();
      imap.uids.add(12);
      imap.seen.add(11);
      mail = service();
      final refreshed = await mail.fetchFolder(credentials: credentials);
      expect(imap.headerRequests.last, [12]);
      expect(refreshed.messages.map((m) => m.subject), [
        'Notice 12',
        'Notice 11',
        'Notice 10',
      ]);
      expect(refreshed.messages.firstWhere((m) => m.uid == 11).isSeen, isTrue);
      await mail.close();
    },
  );

  test(
    'validity reset refetches headers instead of reusing old UID content',
    () async {
      final mail = service();
      await mail.fetchFolder(credentials: credentials);
      imap.validity = 78;
      await mail.fetchFolder(credentials: credentials);
      expect(imap.headerRequests, hasLength(2));
      expect(imap.headerRequests.last.toSet(), {10, 11});
      expect(
        await store().loadSummary(
          credentials.emailAddress,
          const MailMessageIdentity(
            folder: MailFolder.inbox,
            uid: 10,
            mailboxUidValidity: 77,
          ),
        ),
        isNull,
      );
      await mail.close();
    },
  );

  test(
    'cached body survives service recreation without another content fetch',
    () async {
      final mail = service();
      await mail.fetchFolder(credentials: credentials);
      await store().saveDetail(
        credentials.emailAddress,
        const MailMessageDetail(
          uid: 10,
          subject: 'Notice 10',
          sender: 'Teacher',
          recipients: 'Student',
          cc: null,
          date: null,
          body: 'Saved body',
          htmlBody: null,
          isSeen: false,
          mailboxUidValidity: 77,
        ),
      );
      await mail.close();
      final reopened = service();
      final body = await reopened.readMessage(
        credentials: credentials,
        folder: MailFolder.inbox,
        uid: 10,
        expectedMailboxUidValidity: 77,
        markAsSeen: false,
      );
      expect(body.body, 'Saved body');
      expect(imap.headerRequests, hasLength(1));
      expect(body.isSeen, isFalse);
      await reopened.close();
    },
  );
}
