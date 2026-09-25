import '../models/mail_models.dart';
import 'mail_compose_html_sanitizer.dart';

/// Builds the editable message body used by every mail-forward entry point.
///
/// The source HTML is sanitized for the compose editor and SMTP while retaining
/// its allowed formatting. A prepared Small U draft is always escaped as text
/// above the standard forward header, so it cannot reinterpret user text as
/// outgoing HTML.
class MailForwardContent {
  const MailForwardContent._();

  static String plainText(
    MailMessageDetail detail,
    String timeLabel, {
    String leadingText = '',
  }) {
    final forwarded =
        '\n\n---------- 转发的邮件 ----------\n'
        '发件人：${detail.sender}\n'
        '收件人：${detail.recipients}\n'
        '时间：$timeLabel\n'
        '主题：${detail.subject}\n\n'
        '${detail.body}';
    final leading = leadingText.trimRight();
    return leading.isEmpty ? forwarded : '$leading$forwarded';
  }

  static String html(
    MailMessageDetail detail,
    String timeLabel, {
    String leadingText = '',
  }) {
    final originalHtml = detail.htmlBody?.trim() ?? '';
    final safeOriginal = originalHtml.isEmpty
        ? '<p>${_escapeHtml(detail.body).replaceAll('\n', '<br>')}</p>'
        : MailComposeHtmlSanitizer.sanitize(originalHtml);
    final leading = leadingText.trim();
    final safeLeading = leading.isEmpty
        ? ''
        : '<p>${_escapeHtml(leading).replaceAll('\n', '<br>')}</p>';
    return MailComposeHtmlSanitizer.sanitize('''
$safeLeading
<div>
  <p>---------- 转发的邮件 ----------</p>
  <p>发件人：${_escapeHtml(detail.sender)}<br>
  收件人：${_escapeHtml(detail.recipients)}<br>
  时间：${_escapeHtml(timeLabel)}<br>
  主题：${_escapeHtml(detail.subject)}</p>
  <hr>
  $safeOriginal
</div>''');
  }

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
