import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Remove active, embedded and navigation-capable elements.
/// Strip noscript as a whole because its parsing depends on scripting mode.
const mailUnsafeElementSelectors =
    'script,noscript,iframe,frame,frameset,object,embed,applet,base,form,meta,link';

const mailContentSecurityPolicy =
    "default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'; font-src data:; connect-src 'none'; media-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'";

/// Mutates a display document only; raw mail and cached source stay unchanged.
void removeUnsafeMailElements(Document document) {
  for (final element in document.querySelectorAll(mailUnsafeElementSelectors)) {
    element.remove();
  }
  for (final element in document.querySelectorAll('*')) {
    element.attributes.removeWhere(
      (name, _) => name.toString().toLowerCase().startsWith('on'),
    );
  }
}

/// Parses raw mail HTML, strips active and navigation-capable elements plus
/// inline event handlers, and wraps the remaining content in a self-contained
/// document locked down with a restrictive Content-Security-Policy (no scripts,
/// no remote content, no forms, no frames, no base override).
///
/// Returns an empty string for empty input. This only produces a display copy;
/// the original mail and its cache are never modified.
String buildRenderableMailHtml(String htmlText) {
  if (htmlText.trim().isEmpty) {
    return '';
  }
  final parsed = html.parse(htmlText);
  removeUnsafeMailElements(parsed);
  final headInnerHtml = parsed.head?.innerHtml.trim() ?? '';
  final bodyInnerHtml = parsed.body?.innerHtml.trim().isNotEmpty == true
      ? parsed.body!.innerHtml
      : (parsed.documentElement?.innerHtml ?? '');
  final renderedBody = Element.tag('body')..innerHtml = bodyInnerHtml;
  if (parsed.body != null) {
    renderedBody.attributes.addAll(parsed.body!.attributes);
    renderedBody.attributes.removeWhere(
      (name, _) => name.toString().toLowerCase().startsWith('on'),
    );
  }
  return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="$mailContentSecurityPolicy">
    $headInnerHtml
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: #ffffff;
      }
      body {
        padding: 12px 14px 18px;
        color: #111827;
        font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        line-height: 1.55;
        overflow-wrap: break-word;
        word-break: break-word;
      }
      img, video, iframe, table {
        max-width: 100% !important;
      }
      img {
        height: auto !important;
      }
      table {
        width: auto !important;
      }
      pre {
        white-space: pre-wrap;
        word-break: break-word;
      }
      blockquote {
        margin: 0 0 0 12px;
        padding-left: 12px;
        border-left: 3px solid #E5E7EB;
      }
    </style>
  </head>
  ${renderedBody.outerHtml}
</html>
''';
}
