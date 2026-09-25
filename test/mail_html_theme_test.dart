import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:bnbu_me/services/mail_html_theme.dart';

void main() {
  test('cached mail is sanitized again in every presentation mode', () {
    const cached =
        '<html><head><style>p{color:red}</style><noscript><meta http-equiv="refresh" content="0;url=https://invalid.example/"></noscript><link rel="preconnect" href="https://invalid.example/"></head><body><p>Local copy</p></body></html>';
    for (final dark in [false, true]) {
      for (final original in [false, true]) {
        final rendered = buildMailHtml(cached, dark: dark, original: original);
        expect(rendered.toLowerCase(), isNot(contains('<noscript')));
        expect(rendered.toLowerCase(), isNot(contains('http-equiv="refresh"')));
        expect(rendered, isNot(contains('invalid.example')));
        expect(rendered, contains('Content-Security-Policy'));
        expect(rendered, contains('Local copy'));
        expect(
          rendered.indexOf('Content-Security-Policy'),
          lessThan(rendered.indexOf('<style')),
        );
      }
    }
    expect(cached, contains('<noscript>'));
  });

  test('HTML fragments receive trusted metadata and replace source viewport', () {
    final fragment = html.parse(buildMailHtml('<p>合成正文</p>', dark: true));
    expect(fragment.body!.text, '合成正文');
    expect(
      fragment.querySelector('meta[charset]')!.attributes['charset'],
      'utf-8',
    );
    expect(
      fragment.querySelector('meta[name="viewport"]')!.attributes['content'],
      'width=device-width, initial-scale=1',
    );
    final complete = html.parse(
      buildMailHtml(
        '<html><head><meta name="viewport" content="width=device-width, initial-scale=1.2"></head><body>body</body></html>',
        dark: true,
      ),
    );
    expect(complete.querySelectorAll('meta[name="viewport"]'), hasLength(1));
    expect(
      complete.querySelector('meta[name="viewport"]')!.attributes['content'],
      'width=device-width, initial-scale=1',
    );
  });

  test(
    'dark mail transforms white blocks and preserves red emphasis and highlights',
    () {
      final doc = html.parse(
        buildMailHtml(
          '''<div style="background-color: white;color:black"><span style="background:yellow;color:#000">Highlight</span><p style="color:red">Deadline</p></div>''',
          dark: true,
        ),
      );
      expect(
        doc.querySelector('div')!.attributes['style'],
        contains('#18191b'),
      );
      expect(
        doc.querySelector('span')!.attributes['style'],
        isNot(contains('yellow')),
      );
      final red = RegExp(
        r'color:(#[a-fA-F0-9]+)',
      ).firstMatch(doc.querySelector('p')!.attributes['style']!)![1]!;
      final color = parseMailCssColor(red)!;
      expect(color.r, greaterThan(color.g));
      expect(color.computeLuminance(), greaterThanOrEqualTo(.52));
      expect(doc.outerHtml, isNot(contains('color: inherit !important')));
    },
  );
  test(
    'style sheets, legacy attributes, gradients and nested selectors are adapted',
    () {
      final doc = html.parse(
        buildMailHtml(
          '<style>@media screen {td {background:#fff!important;color:rgb(0,0,0)}} .x{background-image:linear-gradient(white, yellow)}</style><table bgcolor="#ffffff"><tr><td><font color="black">body</font></td></tr></table>',
          dark: true,
        ),
      );
      expect(doc.querySelector('style')!.text, contains('!important'));
      expect(doc.querySelector('table')!.attributes['bgcolor'], '#18191b');
      expect(doc.querySelector('font')!.attributes['color'], isNot('black'));
      expect(
        doc.querySelector('style')!.text,
        isNot(contains('linear-gradient(white')),
      );
    },
  );
  test('light and original style preserve sender colors, images and text', () {
    const source =
        '<p style="color:red;background:yellow">hello</p><img src="cid:one"><style>.photo{background:url("https://example.test/white/#fff")}</style>';
    for (final content in [
      buildMailHtml(source, dark: false),
      buildMailHtml(source, dark: true, original: true),
    ]) {
      expect(content, contains('color:red;background:yellow'));
      expect(content, contains('cid:one'));
    }
    expect(
      buildMailHtml(source, dark: true),
      contains('https://example.test/white/#fff'),
    );
  });
  test('color parser supports named, alpha, rgb percentages and hsl', () {
    for (final s in [
      'red',
      '#f00',
      '#ff0000',
      'rgb(100%,0%,0%)',
      'hsl(0,100%,50%)',
    ]) {
      expect(parseMailCssColor(s)!.r, 1);
      expect(parseMailCssColor(s)!.g, 0);
    }
    expect(parseMailCssColor('transparent')!.a, 0);
    expect(parseMailCssColor('var(--color)'), isNull);
    expect(
      buildMailHtml('<p style="color:var(--red)">text</p>', dark: true),
      contains('var(--red)'),
    );
  });
}
