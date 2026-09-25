import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_service_io.dart';

void main() {
  const credentials = MailAccessCredentials(
    userId: 'student',
    emailAddress: 'student@mail.bnbu.edu.cn',
    password: 'test-only',
  );

  test(
    'multiple recipients and carbon copies remain separate SMTP addresses',
    () {
      final message = buildOutgoingMailMimeMessage(
        credentials: credentials,
        composeData: const MailComposeData(
          to: '"Student, One" <one@example.test>, two@example.test',
          cc: 'three@example.test, four@example.test',
          subject: 'Group reply',
          body: 'Hello',
        ),
      );
      expect(message.to!.map((a) => a.email), [
        'one@example.test',
        'two@example.test',
      ]);
      expect(message.cc!.map((a) => a.email), [
        'three@example.test',
        'four@example.test',
      ]);
    },
  );

  test('HTML body stays alternative while attachments use multipart mixed', () {
    final message = buildOutgoingMailMimeMessage(
      credentials: credentials,
      composeData: MailComposeData(
        to: 'teacher@bnbu.edu.cn',
        subject: 'Reply with attachment',
        body: 'Plain body',
        htmlBody: '<p>HTML body</p>',
        attachments: [
          MailComposeAttachment(
            name: '../report?.pdf',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      ),
    );
    final rendered = message.renderMessage();

    expect(rendered, contains('Content-Type: multipart/mixed'));
    expect(rendered, contains('Content-Type: multipart/alternative'));
    expect(rendered, contains('Content-Type: text/plain'));
    expect(rendered, contains('Content-Type: text/html'));
    expect(rendered, contains('Content-Disposition: attachment'));
    expect(rendered, contains('report_.pdf'));
    expect(rendered, isNot(contains('../report?.pdf')));
  });

  test('HTML without attachments keeps an alternative root', () {
    final message = buildOutgoingMailMimeMessage(
      credentials: credentials,
      composeData: const MailComposeData(
        to: 'teacher@bnbu.edu.cn',
        subject: 'HTML only',
        body: 'Plain body',
        htmlBody: '<p>HTML body</p>',
      ),
    );
    final rendered = message.renderMessage();

    expect(rendered, contains('Content-Type: multipart/alternative'));
    expect(rendered, isNot(contains('Content-Type: multipart/mixed')));
  });
}
