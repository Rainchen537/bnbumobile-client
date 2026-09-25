import 'dart:io';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_local_cache.dart';

void main() {
  late Directory root;
  late MailLocalCache cache;
  const account = 'synthetic@example.test';
  const id = MailMessageIdentity(
    folder: MailFolder.inbox,
    uid: 12,
    mailboxUidValidity: 77,
  );
  final key = SecretKey(List.generate(32, (i) => i));
  MailLocalCache reopened() =>
      MailLocalCache(directory: () async => root, key: () async => key);
  final summary = MailMessageSummary(
    uid: 12,
    subject: '课程通知',
    sender: 'Teacher',
    preview: 'A cached preview',
    hasHtmlBody: true,
    date: DateTime.utc(2026, 9, 7),
    isSeen: false,
    previewLoaded: true,
    mailboxUidValidity: 77,
    recipients: 'Student',
    messageId: '<notice@example.test>',
    references: '<original@example.test>',
    messageSizeBytes: 263168,
  );
  const detail = MailMessageDetail(
    uid: 12,
    subject: '课程通知',
    sender: 'Teacher',
    recipients: 'Student',
    cc: null,
    date: null,
    body: 'Offline content sentinel',
    htmlBody: '<p>Offline HTML sentinel</p>',
    isSeen: false,
    mailboxUidValidity: 77,
    messageSizeBytes: 263168,
    attachments: [
      MailAttachment(
        name: 'document.pdf',
        size: 120,
        mimeType: 'application/pdf',
        partId: '2',
      ),
    ],
  );
  MailFolderSnapshot page({
    int number = 1,
    List<MailMessageSummary>? messages,
  }) => MailFolderSnapshot(
    emailAddress: account,
    incomingServer: 'imap.example.test',
    outgoingServer: 'smtp.example.test',
    messages: messages ?? [summary],
    fetchedAt: DateTime.utc(2026, 9, 7),
    folder: MailFolder.inbox,
    totalMessages: 26,
    currentPage: number,
    pageSize: 25,
    mailboxUidValidity: 77,
    mailboxUnreadCount: 4,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bnbu-synthetic-mail-cache-');
    cache = reopened();
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'legacy cached preview decodes entities without changing body or flags',
    () async {
      await cache.savePage(
        account,
        page(
          messages: [
            summary.copyWith(preview: '各位同学： &nbsp; A&amp;B &#160; &#x1F600;'),
          ],
        ),
      );
      await cache.saveDetail(account, detail);
      final restored = reopened();
      final cached = (await restored.loadPage(
        account,
        MailFolder.inbox,
      ))!.messages.single;
      expect(cached.preview, '各位同学： A&B 😀');
      expect(cached.previewLoaded, isTrue);
      expect(cached.isSeen, isFalse);
      expect(cached.mailboxUidValidity, 77);
      expect(
        (await restored.loadDetail(account, id))!.htmlBody,
        detail.htmlBody,
      );
    },
  );

  test(
    'recreated cache restores list, preview, body, HTML and attachment identity',
    () async {
      await cache.savePage(account, page());
      await cache.saveDetail(account, detail);
      final restored = reopened();
      final list = await restored.loadPage(account, MailFolder.inbox);
      expect(list!.messages.single.subject, '课程通知');
      expect(list.messages.single.preview, 'A cached preview');
      expect(list.messages.single.previewLoaded, isTrue);
      expect(list.messages.single.messageSizeBytes, 263168);
      expect(list.totalMessages, 26);
      final body = await restored.loadDetail(account, id);
      expect(body!.body, detail.body);
      expect(body.messageSizeBytes, 263168);
      expect(body.htmlBody, detail.htmlBody);
      expect(body.attachments.single.partId, '2');
      for (final file
          in await root
              .list(recursive: true)
              .where((e) => e is File)
              .cast<File>()
              .toList()) {
        final bytes = await file.readAsBytes();
        final raw = String.fromCharCodes(bytes);
        expect(raw, isNot(contains(detail.body)));
        expect(raw, isNot(contains(summary.preview)));
        expect(file.path, isNot(contains(account)));
      }
    },
  );

  test(
    'ordered pages do not collide and default newest pages still load',
    () async {
      final newest = page(messages: [summary]);
      final oldestSummary = summary.copyWith(
        uid: 1,
        date: DateTime.utc(2020),
        subject: '',
      );
      final oldest = page(messages: [oldestSummary]);
      await cache.savePage(account, newest);
      await cache.savePage(
        account,
        oldest,
        sortOrder: MailSortOrder.oldestFirst,
      );

      expect(
        (await reopened().loadPage(
          account,
          MailFolder.inbox,
        ))!.messages.single.uid,
        12,
      );
      final restoredOldest = await reopened().loadPage(
        account,
        MailFolder.inbox,
        sortOrder: MailSortOrder.oldestFirst,
      );
      expect(restoredOldest!.messages.single.uid, 1);
      expect(restoredOldest.messages.single.subject, isEmpty);
    },
  );

  test('account, folder and UIDVALIDITY isolate identical UIDs', () async {
    await cache.savePage(account, page());
    await cache.saveDetail(account, detail);
    expect(await cache.loadDetail('different@example.test', id), isNull);
    expect(
      await cache.loadDetail(
        account,
        const MailMessageIdentity(
          folder: MailFolder.sent,
          uid: 12,
          mailboxUidValidity: 77,
        ),
      ),
      isNull,
    );
    await cache.validateMailbox(account, MailFolder.inbox, 78);
    expect(await cache.loadPage(account, MailFolder.inbox), isNull);
    expect(await cache.loadDetail(account, id), isNull);
    // A late result from the previous mailbox cannot repopulate its old body.
    await cache.saveDetail(account, detail);
    expect(await cache.loadDetail(account, id), isNull);
  });

  test('fresh flags do not discard cached preview or body', () async {
    await cache.savePage(account, page());
    await cache.saveDetail(account, detail);
    await cache.savePage(
      account,
      page(
        messages: [
          summary.copyWith(
            preview: '',
            previewLoaded: false,
            isSeen: true,
            isFlagged: true,
          ),
        ],
      ),
    );
    final restored = (await cache.loadPage(
      account,
      MailFolder.inbox,
    ))!.messages.single;
    expect(restored.preview, summary.preview);
    expect(restored.isSeen, isTrue);
    expect(restored.isFlagged, isTrue);
    expect((await cache.loadDetail(account, id))!.body, detail.body);
    expect((await cache.loadDetail(account, id))!.isSeen, isTrue);
  });

  test(
    'first page changes invalidate positional pages but retain message content',
    () async {
      await cache.savePage(account, page());
      await cache.savePage(
        account,
        page(number: 2, messages: [summary.copyWith(uid: 11)]),
      );
      expect(
        await reopened().loadPage(account, MailFolder.inbox, page: 2),
        isNotNull,
      );
      await cache.savePage(
        account,
        page(messages: [summary.copyWith(uid: 13)]),
      );
      expect(await cache.loadPage(account, MailFolder.inbox, page: 2), isNull);
      expect((await cache.loadSummary(account, id))!.subject, summary.subject);
    },
  );

  test(
    'flag changes invalidate filtered pages and update stored read state',
    () async {
      await cache.savePage(account, page());
      await cache.savePage(account, page(), unreadOnly: true);
      await cache.saveDetail(account, detail);
      await cache.updateFlags(account, [id], seen: true, flagged: true);
      expect(
        await cache.loadPage(account, MailFolder.inbox, unreadOnly: true),
        isNull,
      );
      expect((await cache.loadDetail(account, id))!.isSeen, isTrue);
      expect((await cache.loadSummary(account, id))!.isFlagged, isTrue);
    },
  );

  test(
    'delete or move removes body and invalidates positional pages',
    () async {
      await cache.savePage(account, page());
      await cache.saveDetail(account, detail);
      await cache.remove(account, [id]);
      expect(await reopened().loadPage(account, MailFolder.inbox), isNull);
      expect(await reopened().loadDetail(account, id), isNull);
    },
  );

  test(
    'corrupt data and a different encryption key become cache misses',
    () async {
      await cache.savePage(account, page());
      final wrong = MailLocalCache(
        directory: () async => root,
        key: () async => SecretKey(List.filled(32, 100)),
      );
      expect(await wrong.loadPage(account, MailFolder.inbox), isNull);
      final entry =
          (await root
                      .list(recursive: true)
                      .where(
                        (e) => e is File && e.uri.pathSegments.last == '12.bin',
                      )
                      .toList())
                  .single
              as File;
      await entry.writeAsBytes([1, 2, 3]);
      expect(await cache.loadSummary(account, id), isNull);
      expect(await cache.loadPage(account, MailFolder.inbox), isNull);
    },
  );

  test('concurrent preview and detail writes preserve both results', () async {
    await cache.savePage(account, page());
    await Future.wait([
      cache.saveDetail(account, detail),
      cache.saveSummaries(account, [
        summary.copyWith(preview: 'updated preview'),
      ]),
    ]);
    expect(
      (await reopened().loadSummary(account, id))!.preview,
      'updated preview',
    );
    expect((await reopened().loadDetail(account, id))!.body, detail.body);
  });

  test(
    'flag refresh does not rewrite bodies and disk eviction remains bounded',
    () async {
      await cache.savePage(account, page());
      await cache.saveDetail(account, detail);
      final bodyFile =
          (await root
                      .list(recursive: true)
                      .where((e) => e is File && e.path.endsWith('.body.bin'))
                      .toList())
                  .single
              as File;
      final encryptedBody = await bodyFile.readAsBytes();
      await cache.updateFlags(account, [id], seen: true);
      expect(await bodyFile.readAsBytes(), encryptedBody);
      final bounded = MailLocalCache(
        directory: () async => root,
        key: () async => key,
        maxEntries: 4,
        maxBytes: 4096,
      );
      await bounded.savePage(
        account,
        page(
          messages: List.generate(30, (i) => summary.copyWith(uid: 100 + i)),
        ),
      );
      final files = await root
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      expect(files.length, lessThanOrEqualTo(4));
      var bytes = 0;
      for (final file in files) {
        bytes += await file.length();
      }
      expect(bytes, lessThanOrEqualTo(4096));
    },
  );

  test(
    'unavailable secure storage never falls back to a plaintext cache',
    () async {
      final unavailable = MailLocalCache(
        directory: () async => root,
        key: () async =>
            throw const FileSystemException('synthetic unavailable key'),
      );
      await unavailable.savePage(account, page());
      expect(await unavailable.loadPage(account, MailFolder.inbox), isNull);
      expect(await root.list(recursive: true).toList(), isEmpty);
    },
  );
}
