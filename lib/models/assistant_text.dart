/// Repairs double-escaped Markdown paragraph/list separators in provider prose.
/// Code, formulas and ordinary backslash sequences (including paths) are literal.
String normalizeAssistantProse(String source) {
  final protected = RegExp(
    r'(`+)[\s\S]*?\1|\$\$[\s\S]*?\$\$|\$[^\n$]*\$|\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)',
  );
  String prose(String value) => value
      .replaceAll(r'\r\n\r\n', '\n\n')
      .replaceAll(r'\n\n', '\n\n')
      .replaceAllMapped(
        RegExp(r'\\(?:r\\)?n(?=[ \t]*(?:[-*+] |[0-9]+[.)] |#{1,6} ))'),
        (_) => '\n',
      );
  final result = StringBuffer();
  var offset = 0;
  for (final match in protected.allMatches(source)) {
    result.write(prose(source.substring(offset, match.start)));
    result.write(match.group(0));
    offset = match.end;
  }
  result.write(prose(source.substring(offset)));
  return result.toString();
}
