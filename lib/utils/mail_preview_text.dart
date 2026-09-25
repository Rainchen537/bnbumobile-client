import 'package:html/parser.dart' as html_parser;

final _entity = RegExp(
  r'&(?:#[0-9]{1,10}|#[xX][0-9a-fA-F]{1,8}|[A-Za-z][A-Za-z0-9]{1,32});',
);
final _bareNbsp = RegExp(r'&nbsp(?=\s|$)');
final _previewWhitespace = RegExp(r'[\s\u00a0\u2007\u202f]+');

/// Human-readable, single-line mail preview; never an HTML rendering surface.
///
/// Decode only matched references, not the surrounding prose or markup. An
/// attribute parsing context preserves unknown names instead of interpreting
/// a valid entity prefix in an ordinary word (for example &notables;).
String normalizeMailPreviewText(String input) {
  var value = input;
  for (var pass = 0; pass < 4 && value.contains('&'); pass++) {
    final next = value.replaceAll(_bareNbsp, '&nbsp;').replaceAllMapped(
      _entity,
      (match) {
        final encoded = match.group(0)!;
        final fragment = html_parser.parseFragment(
          '<span title="$encoded"></span>',
        );
        return fragment.children.single.attributes['title'] ?? encoded;
      },
    );
    if (next == value) break;
    value = next;
  }
  return value.replaceAll(_previewWhitespace, ' ').trim();
}
