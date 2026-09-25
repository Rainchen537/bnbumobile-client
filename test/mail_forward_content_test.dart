import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_forward_content.dart';

void main() {
  const detail = MailMessageDetail(
    uid: 9,
    subject: '课程 <更新>',
    sender: 'Teacher <teacher@bnbu.edu.cn>',
    recipients: 'student@mail.bnbu.edu.cn',
    cc: null,
    date: null,
    body: '原始纯文本',
    htmlBody:
        '<table><tbody><tr><th>课程</th><td>数据结构</td></tr></tbody></table>'
        '<img src="https://tracker.example/pixel"><script>alert(1)</script>',
    isSeen: true,
  );

  test(
    'forward helper preserves allowed table while escaping prepared text',
    () {
      final html = MailForwardContent.html(
        detail,
        '2026年9月7日 10:00',
        leadingText: '请转发 <这段草稿>',
      );
      final plain = MailForwardContent.plainText(
        detail,
        '2026年9月7日 10:00',
        leadingText: '请转发 <这段草稿>',
      );

      expect(plain, startsWith('请转发 <这段草稿>'));
      expect(plain, contains('---------- 转发的邮件 ----------'));
      expect(html, contains('&lt;这段草稿&gt;'));
      expect(html, contains('<table>'));
      expect(html, contains('<th>课程</th>'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('tracker.example')));
    },
  );
}
