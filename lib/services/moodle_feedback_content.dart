import 'package:html/parser.dart' as html_parser;

/// Converts the upstream Feedback item representation into readable evidence.
/// It contains question labels/options, never response fields or submission IDs.
String moodleFeedbackItemsText(List<dynamic> rawItems) {
  if (rawItems.any((item) => item is! Map)) {
    throw const FormatException('问卷题目格式无效。');
  }
  final items =
      rawItems.map((item) => Map<String, dynamic>.from(item as Map)).toList()
        ..sort(
          (a, b) => _number(a['position']).compareTo(_number(b['position'])),
        );
  String text(Object? value) =>
      (html_parser.parseFragment(value?.toString() ?? '').text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  final questionNumbers = <int, int>{
    for (final item in items)
      _number(item['id']): _number(item['itemnumber'] ?? item['position']),
  };
  return items
      .map((item) {
        final type = item['typ']?.toString() ?? '';
        final name = text(item['name']);
        final presentation = item['presentation']?.toString() ?? '';
        if (type == 'pagebreak') return '--- Next questionnaire page ---';
        if (type == 'label') return 'Instruction: ${text(presentation)}';
        final number = _number(item['itemnumber'] ?? item['position']);
        final lines = <String>[
          '$number. $name',
          'Required: ${item['required'] == true || item['required'] == 1 ? 'yes' : 'no'}',
        ];
        if (type == 'multichoice') {
          // Moodle 4.1: subtype >>>>> option|option <<<<< layout.
          final parts = presentation.split('>>>>>');
          if (parts.length != 2 ||
              !const {'r', 'c', 'd'}.contains(parts.first)) {
            throw const FormatException('问卷选项格式无效。');
          }
          lines.add(
            'Answer type: ${parts.first == 'c' ? 'multiple choice' : 'single choice'}',
          );
          final choices = parts.last.split('<<<<<').first.split('|');
          for (var i = 0; i < choices.length; i++) {
            lines.add('${i + 1}) ${text(choices[i])}');
          }
        } else if (type == 'textarea' || type == 'textfield') {
          lines.add('Answer type: free text');
        } else {
          lines.add('Answer type: ${text(type)}');
          if (presentation.isNotEmpty) {
            lines.add('Details: ${text(presentation)}');
          }
        }
        final dependency = _number(item['dependitem']);
        if (dependency > 0) {
          final number = questionNumbers[dependency];
          lines.add(
            number == null
                ? 'Conditional question: its prerequisite is unavailable.'
                : 'Shown when question $number has answer: ${text(item['dependvalue'])}',
          );
        }
        if (item['itemfiles'] is List &&
            (item['itemfiles'] as List).isNotEmpty) {
          lines.add(
            'Embedded files are present; their content is not included here.',
          );
        }
        return lines.join('\n');
      })
      .join('\n\n');
}

int _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
