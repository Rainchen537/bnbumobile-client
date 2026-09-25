import 'mail_html_sanitizer.dart';
import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as ast;
import 'package:flutter/painting.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Rewrites a display copy. The original mail and its cache remain untouched.
String buildMailHtml(
  String source, {
  required bool dark,
  bool original = false,
}) {
  final document = html.parse(source);
  removeUnsafeMailElements(document);
  document.head!.nodes.insert(
    0,
    Element.tag('meta')
      ..attributes.addAll({
        'http-equiv': 'Content-Security-Policy',
        'content': mailContentSecurityPolicy,
      }),
  );
  document.querySelector('#hands-bnbu-mail-theme')?.remove();
  if (document.querySelector('meta[charset]') == null) {
    document.head!.append(Element.html('<meta charset="utf-8">'));
  }
  if (document.querySelector('meta[name="viewport"]') == null) {
    document.head!.append(
      Element.html(
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
      ),
    );
  }
  if (dark && !original) {
    for (final node in document.querySelectorAll('style')) {
      node.text = _adaptCss(node.text);
    }
    for (final node in document.querySelectorAll(
      '[style], [bgcolor], font[color]',
    )) {
      if (node.localName == 'svg' || _insideSvg(node)) continue;
      final inline = node.attributes['style'];
      if (inline != null) {
        final adapted = _adaptCss('x{$inline}');
        node.attributes['style'] = adapted.substring(2, adapted.length - 1);
      }
      for (final attribute in ['bgcolor', 'color']) {
        final value = node.attributes[attribute];
        if (value != null) {
          node.attributes[attribute] = _adaptColors(
            value,
            background: attribute == 'bgcolor',
          );
        }
      }
    }
  }
  final useDark = dark && !original;
  final background = useDark ? '#18191B' : '#FFFFFF';
  final foreground = useDark ? '#F2F3F5' : '#17191B';
  document.head!.append(
    Element.html('''<style id="hands-bnbu-mail-theme">
@font-face { font-family:"BnbuMailCJK"; src:local("PingFangSC-Regular"),local("PingFang SC"); font-weight:400; unicode-range:U+2E80-303F,U+31C0-31EF,U+3400-9FFF,U+F900-FAFF,U+FE30-FE4F,U+FF00-FFEF,U+20000-2FA1F; }
@font-face { font-family:"BnbuMailCJK"; src:local("PingFangSC-Semibold"); font-weight:700; unicode-range:U+2E80-303F,U+31C0-31EF,U+3400-9FFF,U+F900-FAFF,U+FE30-FE4F,U+FF00-FFEF,U+20000-2FA1F; }
:root { color-scheme: ${useDark ? 'dark' : 'light'}; }
html, body { margin:0 !important; min-height:100% !important; background:$background; color:$foreground; }
body { box-sizing:border-box !important; padding:18px 8px 32px !important;
-webkit-text-size-adjust:100%; text-size-adjust:100%;
font-family:"BnbuMailCJK",-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Helvetica Neue",Arial,sans-serif;
font-size:14px; font-weight:400; line-height:1.6;
overflow-wrap:anywhere !important; word-break:break-word !important; }
a { color:${useDark ? '#78B6F5' : '#0879C9'}; }
blockquote { border-left-color:${useDark ? '#34373B' : '#DDE3EA'}; }
img, video, table { max-width:100% !important; }
</style>'''),
  );
  return document.outerHtml;
}

String _adaptCss(String source) {
  try {
    final visitor = _ColorDeclarations(source);
    css.parse(source).visit(visitor);
    var output = source;
    for (final edit in visitor.edits.reversed) {
      output = output.replaceRange(edit.$1, edit.$2, edit.$3);
    }
    return output;
  } catch (_) {
    // Malformed/unknown CSS remains available in the original-style view.
    return source;
  }
}

class _ColorDeclarations extends ast.Visitor {
  _ColorDeclarations(this.source);
  final String source;
  final edits = <(int, int, String)>[];
  @override
  void visitDeclaration(ast.Declaration node) {
    final property = node.property.toLowerCase();
    final foreground =
        property == 'color' || property == '-webkit-text-fill-color';
    final background =
        property == 'background' ||
        property == 'background-color' ||
        property == 'background-image';
    final border =
        property.startsWith('border') &&
        (property.endsWith('color') || property == 'border');
    if (!foreground && !background && !border) return;
    final span = node.span;
    final colon = span.text.indexOf(':');
    if (colon < 0) return;
    final start = span.start.offset + colon + 1;
    final value = source.substring(start, span.end.offset);
    final adapted = _adaptColors(value, background: background || border);
    if (adapted != value) edits.add((start, span.end.offset, adapted));
  }
}

// URLs and quoted strings are matched first and kept verbatim, including hashes.
final _tokens = RegExp(
  r'''var\([^)]*\)|url\((?:[^()"']|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')*\)|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?:rgba?|hsla?)\([^)]*\)|#[0-9a-fA-F]{3,8}\b|\b[a-zA-Z]+\b''',
  caseSensitive: false,
);
String _adaptColors(
  String value, {
  required bool background,
}) => value.replaceAllMapped(_tokens, (match) {
  final raw = match[0]!;
  final color = parseMailCssColor(raw);
  if (color == null || color.a == 0) return raw;
  final hsl = HSLColor.fromColor(color);
  Color mapped;
  if (background) {
    mapped = hsl.saturation < .12 && hsl.lightness > .7
        ? const Color(0xFF18191B)
        : hsl.withLightness(hsl.lightness.clamp(0, .15)).toColor();
  } else {
    var lightness = hsl.lightness;
    mapped = hsl.saturation < .12 ? const Color(0xfff2f3f5) : color;
    while (mapped.computeLuminance() < .52 && lightness < 1) {
      lightness = (lightness + .025).clamp(0, 1);
      mapped = hsl.withLightness(lightness).toColor();
    }
  }
  return '#${mapped.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}${color.a < 1 ? (color.a * 255).round().toRadixString(16).padLeft(2, '0') : ''}';
});

Color? parseMailCssColor(String source) {
  final value = source.trim().toLowerCase();
  if (value == 'transparent') return const Color(0x00000000);
  if (value.startsWith('#')) {
    var hex = value.substring(1);
    if (hex.length == 3 || hex.length == 4) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return hex.length == 6
        ? Color(0xff000000 | parsed)
        : Color((parsed >> 8) | ((parsed & 255) << 24));
  }
  final functional = RegExp(r'^(rgba?|hsla?)\((.*)\)$').firstMatch(value);
  if (functional != null) {
    final parts = functional[2]!
        .split(RegExp(r'[,\s/]+'))
        .where((v) => v.isNotEmpty)
        .toList();
    if (parts.length < 3 || parts.length > 4) return null;
    double? number(String s, double percent) => s.endsWith('%')
        ? double.tryParse(
            s.substring(0, s.length - 1),
          ).mapValue((v) => v * percent / 100)
        : double.tryParse(s);
    final alpha = parts.length == 4 ? number(parts[3], 1) : 1.0;
    if (alpha == null || !alpha.isFinite) return null;
    if (functional[1]!.startsWith('hsl')) {
      final h = double.tryParse(parts[0].replaceAll('deg', ''));
      final s = number(parts[1], 1);
      final l = number(parts[2], 1);
      if (h == null ||
          s == null ||
          l == null ||
          !h.isFinite ||
          !s.isFinite ||
          !l.isFinite) {
        return null;
      }
      return HSLColor.fromAHSL(
        alpha.clamp(0, 1),
        h % 360,
        s.clamp(0, 1),
        l.clamp(0, 1),
      ).toColor();
    }
    final channels = parts.take(3).map((v) => number(v, 255)).toList();
    if (channels.any((v) => v == null || !v.isFinite)) return null;
    return Color.fromRGBO(
      channels[0]!.round().clamp(0, 255),
      channels[1]!.round().clamp(0, 255),
      channels[2]!.round().clamp(0, 255),
      alpha.clamp(0, 1),
    );
  }
  final named = css.TokenKind.matchColorName(value);
  return named == null
      ? null
      : Color(0xff000000 | css.TokenKind.colorValue(named));
}

extension on double? {
  double? mapValue(double Function(double) transform) =>
      this == null ? null : transform(this!);
}

bool _insideSvg(Element node) {
  Element? parent = node.parent;
  while (parent != null) {
    if (parent.localName == 'svg') return true;
    parent = parent.parent;
  }
  return false;
}
