import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/assistant_models.dart';
import '../models/assistant_text.dart';
import '../theme/app_theme.dart';

class SafeAssistantMarkdown extends StatelessWidget {
  const SafeAssistantMarkdown({
    super.key,
    required this.data,
    required this.actions,
    required this.onAction,
    this.fontScale = 1,
  }) : assert(fontScale > 0);

  final String data;
  final List<AssistantAction> actions;
  final ValueChanged<AssistantAction> onAction;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final actionCounts = <String, int>{};
    for (final action in actions) {
      final id = action.actionId.trim();
      if (id.isNotEmpty) {
        actionCounts[id] = (actionCounts[id] ?? 0) + 1;
      }
    }
    final actionsById = <String, AssistantAction>{
      for (final action in actions)
        if (action.actionId.trim().isNotEmpty &&
            actionCounts[action.actionId.trim()] == 1)
          action.actionId.trim(): action,
    };
    final blocks = _parseBlocks(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const SizedBox(height: 9),
          _buildBlock(context, blocks[index], actionsById),
        ],
      ],
    );
  }

  Widget _buildBlock(
    BuildContext context,
    _MarkdownBlock block,
    Map<String, AssistantAction> actionsById,
  ) {
    final tokens = context.bnbuTheme;
    final baseStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(height: 1.55, fontSize: 15 * fontScale);
    switch (block.type) {
      case _MarkdownBlockType.heading:
        final size = switch (block.level) {
          1 => 22.0 * fontScale,
          2 => 19.0 * fontScale,
          3 => 17.0 * fontScale,
          4 => 16.0 * fontScale,
          5 => 15.0 * fontScale,
          _ => 14.0 * fontScale,
        };
        return _inlineText(
          context,
          block.text,
          actionsById,
          baseStyle.copyWith(fontSize: size, fontWeight: FontWeight.w700),
        );
      case _MarkdownBlockType.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < block.items.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  left: block.items[index].depth * 18,
                  bottom: index == block.items.length - 1 ? 0 : 5,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: _buildListMarker(
                        context,
                        block.items[index],
                        baseStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _inlineText(
                        context,
                        block.items[index].text,
                        actionsById,
                        baseStyle,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case _MarkdownBlockType.quote:
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: tokens.border, width: 3)),
            color: tokens.surfaceMuted,
          ),
          child: _inlineText(
            context,
            block.text,
            actionsById,
            baseStyle.copyWith(color: tokens.textSecondary),
          ),
        );
      case _MarkdownBlockType.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.surfaceMuted,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              block.text,
              style: TextStyle(
                color: tokens.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13 * fontScale,
                height: 1.45,
              ),
            ),
          ),
        );
      case _MarkdownBlockType.table:
        return _buildTable(context, block.table!, actionsById, baseStyle);
      case _MarkdownBlockType.math:
        return _buildMathBlock(context, block.text, baseStyle);
      case _MarkdownBlockType.thematicBreak:
        return Divider(height: 1, color: tokens.border);
      case _MarkdownBlockType.paragraph:
        return _inlineText(context, block.text, actionsById, baseStyle);
    }
  }

  Widget _buildListMarker(
    BuildContext context,
    _MarkdownListItem item,
    TextStyle style,
  ) {
    if (item.checked case final checked?) {
      return Semantics(
        checked: checked,
        child: ExcludeSemantics(
          child: Align(
            alignment: Alignment.topRight,
            child: Icon(
              checked ? LucideIcons.squareCheckBig300 : LucideIcons.square300,
              key: ValueKey(
                checked
                    ? 'assistant-markdown-task-checked'
                    : 'assistant-markdown-task-unchecked',
              ),
              size: 18 * fontScale,
              color: checked
                  ? Theme.of(context).colorScheme.primary
                  : context.bnbuTheme.textSecondary,
            ),
          ),
        ),
      );
    }
    return BnbuText(
      item.number == null ? '•' : '${item.number}.',
      textAlign: TextAlign.right,
      style: style.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildTable(
    BuildContext context,
    _MarkdownTable table,
    Map<String, AssistantAction> actionsById,
    TextStyle baseStyle,
  ) {
    final tokens = context.bnbuTheme;
    final rows = <TableRow>[
      _buildTableRow(
        context,
        table.headers,
        table.alignments,
        actionsById,
        baseStyle.copyWith(fontWeight: FontWeight.w700),
        isHeader: true,
      ),
      for (final row in table.rows)
        _buildTableRow(context, row, table.alignments, actionsById, baseStyle),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 0.0;
        final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
            .clamp(1.0, 2.0);
        final minimumColumnWidth = 104 * fontScale * textScale;
        final maximumColumnWidth = 320 * fontScale * textScale;
        final availableColumnWidth = availableWidth > 0
            ? availableWidth / table.headers.length
            : 180 * fontScale * textScale;
        final preferredColumnWidth = availableColumnWidth.clamp(
          minimumColumnWidth,
          maximumColumnWidth,
        );
        final contentWidth = preferredColumnWidth * table.headers.length;
        final tableWidth = contentWidth > availableWidth
            ? contentWidth
            : availableWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Table(
                defaultColumnWidth: FixedColumnWidth(
                  tableWidth / table.headers.length,
                ),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(
                  top: BorderSide(color: tokens.border),
                  right: BorderSide(color: tokens.border),
                  bottom: BorderSide(color: tokens.border),
                  left: BorderSide(color: tokens.border),
                  horizontalInside: BorderSide(color: tokens.border),
                  verticalInside: BorderSide(color: tokens.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                children: rows,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMathBlock(
    BuildContext context,
    String formula,
    TextStyle baseStyle,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 0.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minimumWidth),
              child: Center(
                child: _mathWidget(
                  context,
                  formula,
                  baseStyle.copyWith(fontSize: 17 * fontScale),
                  mathStyle: MathStyle.display,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _mathWidget(
    BuildContext context,
    String formula,
    TextStyle style, {
    required MathStyle mathStyle,
  }) {
    final effectiveStyle = style.copyWith(color: context.bnbuTheme.textPrimary);
    Widget fallback() {
      return SelectableText(
        formula,
        style: effectiveStyle.copyWith(fontFamily: 'monospace'),
      );
    }

    if (formula.isEmpty || formula.length > _maximumFormulaLength) {
      return fallback();
    }
    return Semantics(
      label: formula,
      child: ExcludeSemantics(
        child: Math.tex(
          formula,
          mathStyle: mathStyle,
          textStyle: effectiveStyle,
          settings: const TexParserSettings(
            maxExpand: _maximumFormulaExpansionDepth,
            strict: Strict.ignore,
          ),
          onErrorFallback: (_) => fallback(),
        ),
      ),
    );
  }

  TableRow _buildTableRow(
    BuildContext context,
    List<String> cells,
    List<_MarkdownTableAlignment> alignments,
    Map<String, AssistantAction> actionsById,
    TextStyle style, {
    bool isHeader = false,
  }) {
    return TableRow(
      decoration: isHeader
          ? BoxDecoration(color: context.bnbuTheme.surfaceMuted)
          : null,
      children: [
        for (var index = 0; index < cells.length; index++)
          Semantics(
            header: isHeader,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              alignment: switch (alignments[index]) {
                _MarkdownTableAlignment.left => Alignment.centerLeft,
                _MarkdownTableAlignment.center => Alignment.center,
                _MarkdownTableAlignment.right => Alignment.centerRight,
              },
              child: _inlineText(
                context,
                cells[index],
                actionsById,
                style,
                textAlign: switch (alignments[index]) {
                  _MarkdownTableAlignment.left => TextAlign.left,
                  _MarkdownTableAlignment.center => TextAlign.center,
                  _MarkdownTableAlignment.right => TextAlign.right,
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _inlineText(
    BuildContext context,
    String source,
    Map<String, AssistantAction> actionsById,
    TextStyle style, {
    TextAlign? textAlign,
  }) {
    return Text.rich(
      TextSpan(
        style: style,
        children: _inlineSpans(context, source, actionsById, style),
      ),
      textAlign: textAlign,
    );
  }

  List<InlineSpan> _inlineSpans(
    BuildContext context,
    String source,
    Map<String, AssistantAction> actionsById,
    TextStyle style, {
    int depth = 0,
  }) {
    if (source.isEmpty || depth >= 8) {
      return [TextSpan(text: _unescapeMarkdown(source))];
    }
    final tokens = context.bnbuTheme;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _inlineTokenPattern.allMatches(source)) {
      if (match.start < cursor) continue;
      if (_isEscaped(source, match.start)) {
        final prefixEnd = match.start > cursor ? match.start - 1 : match.start;
        if (prefixEnd > cursor) {
          spans.add(
            TextSpan(
              text: _unescapeMarkdown(source.substring(cursor, prefixEnd)),
            ),
          );
        }
        spans.add(TextSpan(text: _unescapeMarkdown(match.group(0)!)));
        cursor = match.end;
        continue;
      }
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: _unescapeMarkdown(source.substring(cursor, match.start)),
          ),
        );
      }
      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: style.copyWith(
              color: tokens.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13 * fontScale,
              backgroundColor: tokens.surfaceMuted,
            ),
          ),
        );
      } else if (token.startsWith(r'\(') || token.startsWith(r'$')) {
        final formula = token.startsWith(r'\(')
            ? token.substring(2, token.length - 2)
            : token.substring(1, token.length - 1);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _mathWidget(
                context,
                formula,
                style.copyWith(fontSize: 15 * fontScale),
                mathStyle: MathStyle.text,
              ),
            ),
          ),
        );
      } else if (token.startsWith('![')) {
        final separator = token.indexOf('](');
        spans.add(
          TextSpan(
            text: _unescapeMarkdown(token.substring(2, separator)),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else if (token.startsWith('[')) {
        final separator = token.indexOf('](');
        final label = _unescapeMarkdown(token.substring(1, separator));
        final target = token.substring(separator + 2, token.length - 1);
        const prefix = 'assistant-action:';
        final action = target.startsWith(prefix)
            ? actionsById[target.substring(prefix.length)]
            : null;
        if (action == null) {
          spans.add(TextSpan(text: label));
        } else {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Semantics(
                button: true,
                label: label,
                child: InkWell(
                  onTap: () => onAction(action),
                  borderRadius: BorderRadius.circular(4),
                  child: BnbuText(
                    label,
                    style: style.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      } else {
        final markerLength = token.startsWith('***') || token.startsWith('___')
            ? 3
            : token.startsWith('**') ||
                  token.startsWith('__') ||
                  token.startsWith('~~')
            ? 2
            : 1;
        final inner = token.substring(
          markerLength,
          token.length - markerLength,
        );
        final tokenStyle = switch (token.substring(0, markerLength)) {
          '***' || '___' => style.copyWith(
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
          '**' || '__' => style.copyWith(fontWeight: FontWeight.w700),
          '~~' => style.copyWith(decoration: TextDecoration.lineThrough),
          _ => style.copyWith(fontStyle: FontStyle.italic),
        };
        if (_inlineTokenPattern.hasMatch(inner)) {
          spans.add(
            TextSpan(
              style: tokenStyle,
              children: _inlineSpans(
                context,
                inner,
                actionsById,
                tokenStyle,
                depth: depth + 1,
              ),
            ),
          );
        } else {
          spans.add(
            TextSpan(text: _unescapeMarkdown(inner), style: tokenStyle),
          );
        }
      }
      cursor = match.end;
    }
    if (cursor < source.length) {
      spans.add(TextSpan(text: _unescapeMarkdown(source.substring(cursor))));
    }
    return spans;
  }
}

final RegExp _inlineTokenPattern = RegExp(
  r'(`[^`\n]+`|(?<!\\)\$(?!\$|\s)[^$\n]*?\S(?<!\\)\$(?!\$)|(?<!\\)\\\([^\n]+?\\\)|!\[[^\]\n]*\]\([^\)\n]+\)|\[[^\]\n]+\]\([^\)\n]+\)|\*\*\*[^*\n]+\*\*\*|___[^_\n]+___|\*\*[^*\n]+\*\*|__[^_\n]+__|~~[^~\n]+~~|\*[^*\n]+\*|_[^_\n]+_)',
);

const int _maximumFormulaLength = 4096;
const int _maximumFormulaExpansionDepth = 100;

bool _isEscaped(String source, int index) {
  var slashCount = 0;
  for (
    var cursor = index - 1;
    cursor >= 0 && source[cursor] == r'\';
    cursor--
  ) {
    slashCount++;
  }
  return slashCount.isOdd;
}

String _unescapeMarkdown(String source) {
  return source.replaceAllMapped(
    RegExp(r'\\([\\`*_\$\[\]{}()#+\-.!|>~])'),
    (match) => match.group(1)!,
  );
}

enum _MarkdownBlockType {
  paragraph,
  heading,
  list,
  quote,
  code,
  table,
  math,
  thematicBreak,
}

class _MarkdownBlock {
  const _MarkdownBlock({
    required this.type,
    this.text = '',
    this.items = const [],
    this.level = 0,
    this.table,
  });

  final _MarkdownBlockType type;
  final String text;
  final List<_MarkdownListItem> items;
  final int level;
  final _MarkdownTable? table;
}

class _MarkdownListItem {
  const _MarkdownListItem({
    required this.text,
    required this.depth,
    this.number,
    this.checked,
  });

  final String text;
  final int depth;
  final int? number;
  final bool? checked;

  _MarkdownListItem append(String continuation) {
    return _MarkdownListItem(
      text: '$text ${continuation.trim()}',
      depth: depth,
      number: number,
      checked: checked,
    );
  }
}

enum _MarkdownTableAlignment { left, center, right }

class _MarkdownTable {
  const _MarkdownTable({
    required this.headers,
    required this.alignments,
    required this.rows,
  });

  final List<String> headers;
  final List<_MarkdownTableAlignment> alignments;
  final List<List<String>> rows;
}

class _ParsedMathBlock {
  const _ParsedMathBlock({required this.formula, required this.lineCount});

  final String formula;
  final int lineCount;
}

final RegExp _listLinePattern = RegExp(r'^(\s*)([-+*]|\d+[.)])\s+(.+)$');
final RegExp _thematicBreakPattern = RegExp(
  r'^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$',
);
final RegExp _tableSeparatorCellPattern = RegExp(r'^:?-{3,}:?$');

List<_MarkdownBlock> _parseBlocks(String source) {
  final lines = normalizeAssistantProse(
    source,
  ).replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <_MarkdownBlock>[];
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      index++;
      continue;
    }

    final fence = RegExp(r'^\s*(```+|~~~+)').firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      index++;
      final code = <String>[];
      while (index < lines.length &&
          !RegExp(
            '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}'
            r'\s*$',
          ).hasMatch(lines[index])) {
        code.add(lines[index]);
        index++;
      }
      if (index < lines.length) index++;
      blocks.add(
        _MarkdownBlock(type: _MarkdownBlockType.code, text: code.join('\n')),
      );
      continue;
    }

    final mathBlock = _parseMathBlock(lines, index);
    if (mathBlock != null) {
      blocks.add(
        _MarkdownBlock(type: _MarkdownBlockType.math, text: mathBlock.formula),
      );
      index += mathBlock.lineCount;
      continue;
    }

    final table = _parseTable(lines, index);
    if (table != null) {
      blocks.add(_MarkdownBlock(type: _MarkdownBlockType.table, table: table));
      index += table.rows.length + 2;
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(line.trim());
    if (heading != null) {
      final headingText = heading
          .group(2)!
          .replaceFirst(RegExp(r'\s+#+\s*$'), '');
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.heading,
          text: headingText,
          level: heading.group(1)!.length,
        ),
      );
      index++;
      continue;
    }

    final setextLevel = _setextLevel(lines, index);
    if (setextLevel != null) {
      blocks.add(
        _MarkdownBlock(
          type: _MarkdownBlockType.heading,
          text: line.trim(),
          level: setextLevel,
        ),
      );
      index += 2;
      continue;
    }

    if (_thematicBreakPattern.hasMatch(line)) {
      blocks.add(const _MarkdownBlock(type: _MarkdownBlockType.thematicBreak));
      index++;
      continue;
    }

    if (_listLinePattern.hasMatch(line)) {
      final items = <_MarkdownListItem>[];
      while (index < lines.length) {
        final match = _listLinePattern.firstMatch(lines[index]);
        if (match != null) {
          final marker = match.group(2)!;
          var text = match.group(3)!;
          bool? checked;
          final task = RegExp(r'^\[([ xX])\]\s+(.+)$').firstMatch(text);
          if (task != null) {
            checked = task.group(1)!.toLowerCase() == 'x';
            text = task.group(2)!;
          }
          items.add(
            _MarkdownListItem(
              text: text,
              depth: (_indentWidth(match.group(1)!) ~/ 2).clamp(0, 6),
              number: RegExp(r'^\d').hasMatch(marker)
                  ? int.tryParse(marker.replaceAll(RegExp(r'\D'), ''))
                  : null,
              checked: checked,
            ),
          );
          index++;
          continue;
        }
        if (items.isNotEmpty &&
            lines[index].trim().isNotEmpty &&
            _indentWidth(lines[index]) > items.last.depth * 2 &&
            !_startsBlockAt(lines, index)) {
          items[items.length - 1] = items.last.append(lines[index]);
          index++;
          continue;
        }
        break;
      }
      blocks.add(_MarkdownBlock(type: _MarkdownBlockType.list, items: items));
      continue;
    }

    if (line.trimLeft().startsWith('>')) {
      final quote = <String>[];
      while (index < lines.length && lines[index].trimLeft().startsWith('>')) {
        quote.add(lines[index].trimLeft().substring(1).trimLeft());
        index++;
      }
      blocks.add(
        _MarkdownBlock(type: _MarkdownBlockType.quote, text: quote.join('\n')),
      );
      continue;
    }

    final paragraph = <String>[line.trimLeft()];
    index++;
    while (index < lines.length &&
        lines[index].trim().isNotEmpty &&
        !_startsBlockAt(lines, index)) {
      paragraph.add(lines[index].trimLeft());
      index++;
    }
    blocks.add(
      _MarkdownBlock(
        type: _MarkdownBlockType.paragraph,
        text: _joinParagraphLines(paragraph),
      ),
    );
  }
  if (blocks.isEmpty) {
    return const [_MarkdownBlock(type: _MarkdownBlockType.paragraph, text: '')];
  }
  return blocks;
}

int _indentWidth(String source) {
  var width = 0;
  for (final unit in source.codeUnits) {
    if (unit == 0x20) {
      width++;
    } else if (unit == 0x09) {
      width += 2;
    } else {
      break;
    }
  }
  return width;
}

String _joinParagraphLines(List<String> lines) {
  final buffer = StringBuffer();
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index];
    final hardBreak = line.endsWith('  ') || line.endsWith(r'\');
    if (hardBreak) {
      line = line.endsWith(r'\')
          ? line.substring(0, line.length - 1)
          : line.trimRight();
    }
    buffer.write(line);
    if (index < lines.length - 1) buffer.write(hardBreak ? '\n' : ' ');
  }
  return buffer.toString();
}

int? _setextLevel(List<String> lines, int index) {
  if (index + 1 >= lines.length || lines[index].trim().isEmpty) return null;
  final underline = lines[index + 1].trim();
  if (RegExp(r'^=+$').hasMatch(underline)) return 1;
  if (RegExp(r'^-+$').hasMatch(underline)) return 2;
  return null;
}

_ParsedMathBlock? _parseMathBlock(List<String> lines, int index) {
  if (index >= lines.length) return null;
  final trimmed = lines[index].trim();
  for (final delimiters in const <(String, String)>[
    (r'$$', r'$$'),
    (r'\[', r'\]'),
  ]) {
    final opening = delimiters.$1;
    final closing = delimiters.$2;
    if (!trimmed.startsWith(opening)) continue;
    if (trimmed.length > opening.length + closing.length &&
        trimmed.endsWith(closing)) {
      return _ParsedMathBlock(
        formula: trimmed
            .substring(opening.length, trimmed.length - closing.length)
            .trim(),
        lineCount: 1,
      );
    }
    if (trimmed != opening) return null;
    final formulaLines = <String>[];
    var lineIndex = index + 1;
    while (lineIndex < lines.length && lines[lineIndex].trim() != closing) {
      formulaLines.add(lines[lineIndex]);
      lineIndex++;
    }
    if (lineIndex >= lines.length) return null;
    return _ParsedMathBlock(
      formula: formulaLines.join('\n').trim(),
      lineCount: lineIndex - index + 1,
    );
  }
  return null;
}

_MarkdownTable? _parseTable(List<String> lines, int index) {
  if (index + 1 >= lines.length) return null;
  final headers = _splitTableRow(lines[index]);
  final separators = _splitTableRow(lines[index + 1]);
  if (headers == null ||
      separators == null ||
      headers.length < 2 ||
      separators.length != headers.length ||
      !separators.every(
        (cell) => _tableSeparatorCellPattern.hasMatch(cell.trim()),
      )) {
    return null;
  }
  final alignments = separators
      .map((cell) {
        final trimmed = cell.trim();
        if (trimmed.startsWith(':') && trimmed.endsWith(':')) {
          return _MarkdownTableAlignment.center;
        }
        if (trimmed.endsWith(':')) return _MarkdownTableAlignment.right;
        return _MarkdownTableAlignment.left;
      })
      .toList(growable: false);
  final rows = <List<String>>[];
  var rowIndex = index + 2;
  while (rowIndex < lines.length && lines[rowIndex].trim().isNotEmpty) {
    final cells = _splitTableRow(lines[rowIndex]);
    if (cells == null) break;
    rows.add(
      List<String>.generate(
        headers.length,
        (column) => column < cells.length ? cells[column] : '',
        growable: false,
      ),
    );
    rowIndex++;
  }
  return _MarkdownTable(headers: headers, alignments: alignments, rows: rows);
}

List<String>? _splitTableRow(String source) {
  var line = source.trim();
  if (!line.contains('|')) return null;
  if (line.startsWith('|')) line = line.substring(1);
  if (line.endsWith('|') && !_isEscaped(line, line.length - 1)) {
    line = line.substring(0, line.length - 1);
  }
  final cells = <String>[];
  final buffer = StringBuffer();
  var inCode = false;
  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (character == '`' && !_isEscaped(line, index)) {
      inCode = !inCode;
      buffer.write(character);
      continue;
    }
    if (character == '|' && !inCode && !_isEscaped(line, index)) {
      cells.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(character);
  }
  cells.add(buffer.toString().trim());
  return cells;
}

bool _startsBlockAt(List<String> lines, int index) {
  if (index >= lines.length) return false;
  final trimmed = lines[index].trimLeft();
  return RegExp(r'^(```+|~~~+)').hasMatch(trimmed) ||
      _parseMathBlock(lines, index) != null ||
      RegExp(r'^#{1,6}\s+').hasMatch(trimmed) ||
      _listLinePattern.hasMatch(lines[index]) ||
      _thematicBreakPattern.hasMatch(lines[index]) ||
      trimmed.startsWith('>') ||
      _setextLevel(lines, index) != null ||
      _parseTable(lines, index) != null;
}
