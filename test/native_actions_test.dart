import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/native_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/native_actions');
  const actions = NativeActions(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('requests the attachment cache directory', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getMailAttachmentCacheDir');
      return '/tmp/mail_attachments';
    });

    expect(
      await actions.getMailAttachmentCacheDirectory(),
      '/tmp/mail_attachments',
    );
  });

  test('opens a file with path and MIME type', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    await actions.openFile(
      path: '/tmp/mail_attachments/report.pdf',
      mimeType: 'application/pdf',
    );

    expect(received?.method, 'openFile');
    expect(received?.arguments, {
      'path': '/tmp/mail_attachments/report.pdf',
      'mimeType': 'application/pdf',
    });
  });

  test('clears the native web session', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    await actions.clearWebSession();

    expect(received?.method, 'clearWebSession');
    expect(received?.arguments, isNull);
  });

  test('opens only credential-free HTTP(S) external links', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    await actions.openExternalUrl('https://bnbu.edu.cn/path');
    expect(received?.method, 'openExternalUrl');

    for (final rejected in <String>[
      'javascript:alert(1)',
      'file:///tmp/private.txt',
      'https://user:password@bnbu.edu.cn/path',
      'https://bnbu.edu.cn\nmalformed',
    ]) {
      expect(
        () => actions.openExternalUrl(rejected),
        throwsA(isA<FormatException>()),
        reason: rejected,
      );
    }
  });

  group('downloadedFileDisplayName', () {
    test('uses the native path basename when available', () {
      expect(
        downloadedFileDisplayName(
          '/Documents/report-1234.pdf',
          fallback: 'report.pdf',
        ),
        'report-1234.pdf',
      );
    });

    test('keeps the fallback for content URIs and queued downloads', () {
      expect(
        downloadedFileDisplayName(
          'content://media/external/downloads/42',
          fallback: 'report.pdf',
        ),
        'report.pdf',
      );
      expect(
        downloadedFileDisplayName(42, fallback: 'report.pdf'),
        'report.pdf',
      );
    });
  });

  group('safeAttachmentFileName', () {
    test('removes path traversal components', () {
      expect(safeAttachmentFileName('../../secret.txt'), 'secret.txt');
      expect(safeAttachmentFileName(r'..\secret.txt'), 'secret.txt');
    });

    test('replaces invalid file name characters', () {
      expect(safeAttachmentFileName('report:final?.pdf'), 'report_final_.pdf');
    });

    test('uses a fallback for unusable names', () {
      expect(safeAttachmentFileName('..'), 'attachment.bin');
      expect(safeAttachmentFileName(''), 'attachment.bin');
    });
  });

  group('mailAttachmentCacheFileName', () {
    String buildName({
      String accountId = 'student@mail.example.edu',
      String mailbox = 'inbox',
      int messageUid = 42,
      String partId = '2.1',
      String originalName = 'report.pdf',
      String? messageId = '<message@example.edu>',
      int? mailboxUidValidity = 1234,
    }) {
      return mailAttachmentCacheFileName(
        accountId: accountId,
        mailbox: mailbox,
        messageId: messageId,
        mailboxUidValidity: mailboxUidValidity,
        messageUid: messageUid,
        partId: partId,
        originalName: originalName,
      );
    }

    test('keeps the display name without exposing account identity', () {
      final fileName = buildName();

      expect(fileName, endsWith('_report.pdf'));
      expect(fileName, isNot(contains('student')));
      expect(fileName, isNot(contains('example.edu')));
    });

    test('scopes identical UIDs by account, mailbox, message, and part', () {
      final original = buildName();

      expect(buildName(accountId: 'other@mail.example.edu'), isNot(original));
      expect(buildName(mailbox: 'sent'), isNot(original));
      expect(buildName(mailboxUidValidity: 5678), isNot(original));
      expect(buildName(messageId: '<other@example.edu>'), isNot(original));
      expect(buildName(partId: '2.2'), isNot(original));
    });

    test('keeps sanitization collisions in separate cache files', () {
      final first = buildName(originalName: 'report?.pdf');
      final second = buildName(partId: '2.2', originalName: 'report*.pdf');

      expect(first, isNot(second));
      expect(first, endsWith('report_.pdf'));
      expect(second, endsWith('report_.pdf'));
    });

    test('limits the complete UTF-8 file name length', () {
      final fileName = buildName(
        originalName: '${List.filled(80, '课程资料').join()}.pdf',
      );

      expect(utf8.encode(fileName).length, lessThanOrEqualTo(240));
      expect(fileName, endsWith('.pdf'));
    });
  });

  group('urlsHaveSameOrigin', () {
    test('accepts equivalent default HTTPS ports', () {
      expect(
        urlsHaveSameOrigin(
          'https://ispace.example.edu/file',
          'https://ispace.example.edu:443',
        ),
        isTrue,
      );
    });

    test('rejects different hosts, schemes, and ports', () {
      expect(
        urlsHaveSameOrigin(
          'https://attacker.example/file',
          'https://ispace.example.edu',
        ),
        isFalse,
      );
      expect(
        urlsHaveSameOrigin(
          'http://ispace.example.edu/file',
          'https://ispace.example.edu',
        ),
        isFalse,
      );
      expect(
        urlsHaveSameOrigin(
          'https://ispace.example.edu:444/file',
          'https://ispace.example.edu',
        ),
        isFalse,
      );
    });
  });
}
