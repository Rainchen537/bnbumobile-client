import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_presentation.dart';

void main() {
  test('calendar week, yesterday and Shanghai midnight are distinct', () {
    final now = DateTime.parse('2026-09-10T04:00:00Z');
    expect(
      formatMailListDate(DateTime.parse('2026-09-09T16:01:00Z'), now: now),
      '00:01',
    );
    expect(
      formatMailListDate(DateTime.parse('2026-09-09T02:00:00Z'), now: now),
      '昨天',
    );
    expect(
      formatMailListDate(DateTime.parse('2026-09-07T02:00:00Z'), now: now),
      '星期一',
    );
    expect(
      formatMailListDate(DateTime.parse('2026-09-06T02:00:00Z'), now: now),
      '9/6',
    );
    expect(
      formatMailListDate(DateTime.parse('2026-08-30T02:00:00Z'), now: now),
      '8/30',
    );
  });
  test(
    'same subject stays separate while explicit references join across boxes',
    () {
      MailMessageSummary message(
        int uid,
        MailFolder folder,
        String id,
        String refs,
      ) => MailMessageSummary(
        uid: uid,
        subject: 'Weekly update',
        sender: 'Teacher',
        preview: '',
        hasHtmlBody: false,
        date: DateTime.utc(2026, 9, uid),
        isSeen: false,
        folder: folder,
        mailboxUidValidity: 1,
        messageId: id,
        references: refs,
      );
      final first = message(1, MailFolder.inbox, '<one@example.test>', '');
      final reply = message(
        1,
        MailFolder.sent,
        '<two@example.test>',
        '<one@example.test>',
      );
      final unrelated = message(
        3,
        MailFolder.inbox,
        '<three@example.test>',
        '',
      );
      final groups = groupMailConversations([first, reply, unrelated]);
      expect(groups.map((group) => group.length), [1, 2]);
      expect(first.identityKey, isNot(reply.identityKey));
    },
  );
  test('sent rows display recipients while preserving the original sender', () {
    final summary = MailMessageSummary(
      uid: 1,
      subject: 'Hello',
      sender: 'Self <self@example.test>',
      recipients: 'Teacher <teacher@bnbu.edu.cn>',
      preview: '',
      hasHtmlBody: false,
      date: null,
      isSeen: true,
      folder: MailFolder.sent,
    );
    expect(summary.correspondent, 'Teacher <teacher@bnbu.edu.cn>');
    expect(summary.sender, 'Self <self@example.test>');
    expect(
      summary.copyWith(folder: MailFolder.inbox).correspondent,
      summary.sender,
    );
  });
}
