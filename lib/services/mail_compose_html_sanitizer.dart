import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Sanitizes HTML generated for outgoing mail or restored from an IMAP draft.
/// It preserves the local editor's formatting schema while removing executable
/// content and network-backed image sources.
class MailComposeHtmlSanitizer {
  static final RegExp _safeLink = RegExp(
    r'^(https?:|mailto:|tel:)',
    caseSensitive: false,
  );
  static final RegExp _safeImage = RegExp(
    r'^data:image/(png|jpe?g|gif|webp);base64,',
    caseSensitive: false,
  );
  static const _allowedStyleNames = <String>{
    'background-color',
    'color',
    'font-family',
    'font-size',
    'font-style',
    'font-weight',
    'height',
    'line-height',
    'margin-left',
    'min-width',
    'text-align',
    'text-decoration',
    'width',
  };

  static String sanitize(String source) {
    final document = html_parser.parseFragment(source);
    for (final element in document.querySelectorAll(
      'base,embed,form,iframe,link,meta,object,script,style,svg',
    )) {
      element.remove();
    }
    for (final element in document.querySelectorAll('*')) {
      _sanitizeAttributes(element);
    }
    return document.outerHtml;
  }

  static void _sanitizeAttributes(dom.Element element) {
    final attributes = Map<String, String>.from(element.attributes);
    for (final entry in attributes.entries) {
      final name = entry.key.toLowerCase();
      final value = entry.value.trim();
      if (name.startsWith('on')) {
        element.attributes.remove(entry.key);
      } else if (name == 'src') {
        if (element.localName != 'img' || !_safeImage.hasMatch(value)) {
          element.attributes.remove(entry.key);
        }
      } else if (name == 'href') {
        if (!_safeLink.hasMatch(value)) element.attributes.remove(entry.key);
      } else if (name == 'style') {
        final styles = value
            .split(';')
            .map((part) => part.split(':'))
            .where((parts) => parts.length >= 2)
            .map(
              (parts) => (
                parts.first.trim().toLowerCase(),
                parts.sublist(1).join(':').trim(),
              ),
            )
            .where(
              (style) =>
                  _allowedStyleNames.contains(style.$1) &&
                  !RegExp(
                    r'expression|url\s*\(',
                    caseSensitive: false,
                  ).hasMatch(style.$2) &&
                  _validStyleValue(style.$1, style.$2),
            )
            .map((style) => '${style.$1}:${style.$2}')
            .join(';');
        if (styles.isEmpty) {
          element.attributes.remove(entry.key);
        } else {
          element.attributes[entry.key] = styles;
        }
      } else if ((name == 'colwidth' || name == 'data-colwidth') &&
          RegExp(r'^[0-9, ]+$').hasMatch(value)) {
        continue;
      } else if (!const {'align', 'colspan', 'rowspan'}.contains(name)) {
        element.attributes.remove(entry.key);
      }
    }
  }

  static bool _validStyleValue(String name, String value) {
    if (const {'width', 'min-width', 'height'}.contains(name)) {
      return RegExp(r'^\d+(?:\.\d+)?(?:px|%|em|rem)?$').hasMatch(value);
    }
    if (name == 'margin-left') {
      final match = RegExp(r'^(\d+(?:\.\d+)?)(?:px|em|rem)$').firstMatch(value);
      return match != null && double.parse(match.group(1)!) <= 12;
    }
    return true;
  }
}
