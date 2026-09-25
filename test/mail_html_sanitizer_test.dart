import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:bnbu_me/services/mail_html_sanitizer.dart';

void main() {
  test('empty input yields an empty document', () {
    expect(buildRenderableMailHtml(''), '');
    expect(buildRenderableMailHtml('   \n\t '), '');
  });

  test('meta refresh hidden inside <noscript> cannot survive to the WebView', () {
    // package:html parses <noscript> content as raw text, so the meta is
    // invisible to child selectors but becomes live markup once a WebView
    // re-parses it with scripting disabled. The whole <noscript> must be gone.
    final raw =
        '<html><head><noscript>'
        '<meta http-equiv="refresh" content="0;url=https://attacker.example/phish">'
        '</noscript></head><body><p>Hello</p></body></html>';
    final output = buildRenderableMailHtml(raw);

    expect(output.toLowerCase(), isNot(contains('http-equiv="refresh"')));
    expect(output, isNot(contains('attacker.example')));
    final doc = html.parse(output);
    expect(doc.querySelectorAll('noscript'), isEmpty);
    expect(doc.querySelectorAll('meta[content*="attacker"]'), isEmpty);
    // The legitimate body still renders.
    expect(doc.body!.text, contains('Hello'));
  });

  test('directly placed navigation and active elements are stripped', () {
    final raw =
        '<html><head>'
        '<meta http-equiv="refresh" content="0;url=https://a.example/">'
        '<base href="https://a.example/">'
        '<link rel="preconnect" href="https://a.example">'
        '<link rel="dns-prefetch" href="https://b.example">'
        '</head><body>'
        '<script>document.location="https://a.example"</script>'
        '<iframe src="https://a.example/i"></iframe>'
        '<form action="https://a.example/f"><input name="p"></form>'
        '<object data="https://a.example/o"></object>'
        '<embed src="https://a.example/e">'
        '<p>Body text</p>'
        '</body></html>';
    final doc = html.parse(buildRenderableMailHtml(raw));

    expect(doc.querySelectorAll('script'), isEmpty);
    expect(doc.querySelectorAll('iframe'), isEmpty);
    expect(doc.querySelectorAll('form'), isEmpty);
    expect(doc.querySelectorAll('object'), isEmpty);
    expect(doc.querySelectorAll('embed'), isEmpty);
    expect(doc.querySelectorAll('base'), isEmpty);
    expect(doc.querySelectorAll('link'), isEmpty);
    // No refresh meta survives; only the template's own CSP meta remains.
    expect(doc.querySelectorAll('meta[http-equiv="refresh"]'), isEmpty);
    expect(doc.body!.text, contains('Body text'));
  });

  test('the isolated document declares its own locked-down CSP', () {
    final doc = html.parse(buildRenderableMailHtml('<p>x</p>'));
    final csp = doc.querySelector('meta[http-equiv="Content-Security-Policy"]');
    expect(csp, isNotNull);
    final content = csp!.attributes['content']!;
    expect(content, contains("default-src 'none'"));
    expect(content, contains("connect-src 'none'"));
    expect(content, contains("frame-src 'none'"));
    expect(content, contains("form-action 'none'"));
    expect(content, contains("base-uri 'none'"));
  });

  test('benign content, links and inline images are preserved', () {
    final raw =
        '<p>Hello <a href="https://example.edu/a">link</a></p>'
        '<img src="cid:image-1" alt="inline">';
    final doc = html.parse(buildRenderableMailHtml(raw));

    expect(doc.body!.text, contains('Hello'));
    expect(doc.querySelector('a')!.attributes['href'], 'https://example.edu/a');
    expect(doc.querySelector('img')!.attributes['src'], 'cid:image-1');
  });

  test('inline event handlers are removed from the body element', () {
    final raw = '<body onload="steal()"><p>x</p></body>';
    final doc = html.parse(buildRenderableMailHtml(raw));
    expect(doc.body!.attributes.keys, isNot(contains('onload')));
  });
}
