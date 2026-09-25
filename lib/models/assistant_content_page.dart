import 'dart:convert';

/// Full source text stays on the device. Only the requested page enters a tool result.
class AssistantContentPage {
  const AssistantContentPage({
    required this.text,
    required this.offset,
    required this.totalCharacters,
    required this.state,
    this.nextOffset,
    this.nextSourcePage,
    this.sourceComplete = true,
  });
  final String text;
  final int offset;
  final int totalCharacters;
  final String state;
  final int? nextOffset;
  final int? nextSourcePage;
  final bool sourceComplete;
  Map<String, dynamic> toJson() => {
    'text': text,
    'offset': offset,
    'total_characters': totalCharacters,
    'state': state,
    if (!sourceComplete) 'source_complete': false,
    if (nextSourcePage != null) 'next_source_page': nextSourcePage,
    if (nextOffset != null) 'next_offset': nextOffset,
  };

  factory AssistantContentPage.slice(
    String source,
    int offset, {
    int byteBudget = 16000,
  }) {
    if (offset < 0 ||
        offset > source.length ||
        (offset < source.length &&
            offset > 0 &&
            source.codeUnitAt(offset) >= 0xdc00 &&
            source.codeUnitAt(offset) <= 0xdfff)) {
      throw const FormatException('正文续读位置无效');
    }
    final out = StringBuffer();
    var bytes = 0;
    for (final rune in source.substring(offset).runes) {
      final value = String.fromCharCode(rune);
      final size = utf8.encode(value).length;
      if (bytes + size > byteBudget) break;
      bytes += size;
      out.write(value);
    }
    final end = offset + out.length;
    return AssistantContentPage(
      text: out.toString(),
      offset: offset,
      totalCharacters: source.length,
      nextOffset: end < source.length ? end : null,
      state: source.isEmpty
          ? 'empty'
          : offset > 0 || end < source.length
          ? 'truncated'
          : 'complete',
    );
  }
}
