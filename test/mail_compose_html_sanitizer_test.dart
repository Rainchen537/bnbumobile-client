import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/mail_compose_html_sanitizer.dart';

void main() {
  test(
    'outgoing rich HTML keeps document formatting but removes executable paste',
    () {
      final safe = MailComposeHtmlSanitizer.sanitize('''
<script>alert('x')</script>
<p onclick="steal()" style="margin-left:12em">正文 <strong>加粗</strong></p>
<p style="margin-left:14em">过深缩进</p>
<a href="javascript:alert(1)">bad</a>
<a href="mailto:test@bnbu.edu.cn">mail</a>
<img src="https://tracker.example/pixel.png" onerror="steal()">
<img src="data:image/png;base64,AA==" onload="steal()">
<table style="color:#123; width:100%; background-image:url(https://tracker.example/x)">
  <tr><td colspan="2" colwidth="120,120">单元格</td></tr>
</table>
''');

      expect(safe, isNot(contains('<script')));
      expect(safe, isNot(contains('onclick')));
      expect(safe, isNot(contains('onerror')));
      expect(safe, isNot(contains('onload')));
      expect(safe, isNot(contains('javascript:')));
      expect(safe, isNot(contains('tracker.example')));
      expect(safe, contains('mailto:test@bnbu.edu.cn'));
      expect(safe, contains('data:image/png;base64,AA=='));
      expect(safe, contains('<table'));
      expect(safe, contains('colspan="2"'));
      expect(safe, contains('colwidth="120,120"'));
      expect(safe, contains('color:#123'));
      expect(safe, contains('width:100%'));
      expect(safe, contains('margin-left:12em'));
      expect(safe, isNot(contains('margin-left:14em')));
    },
  );
}
