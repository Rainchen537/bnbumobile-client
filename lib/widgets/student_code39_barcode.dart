import 'package:flutter/material.dart';

/// A small, dependency-free Code 39 renderer for the student eCard.
///
/// The payload is supplied by the caller so the barcode remains a
/// session-local rendering of the current student's ID.
class StudentCode39Barcode extends StatelessWidget {
  const StudentCode39Barcode({
    super.key,
    required this.payload,
    this.semanticsLabel = '学号 Code 39 条码',
  });

  final String payload;
  final String semanticsLabel;

  static String payloadForStudentId(String studentId) => 'U0$studentId';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: CustomPaint(
        painter: _Code39BarcodePainter(payload),
        size: const Size(double.infinity, 82),
      ),
    );
  }
}

class _Code39BarcodePainter extends CustomPainter {
  _Code39BarcodePainter(this.payload);

  final String payload;

  // Each symbol contains nine alternating bars/spaces. 1 is a narrow
  // element and 2 is a wide element. The first and last '*' are Code 39
  // start/stop symbols and are not part of the decoded payload.
  static const Map<String, String> _patterns = <String, String>{
    '0': '112122111',
    '1': '211112112',
    '2': '211112211',
    '3': '111112212',
    '4': '211122111',
    '5': '111122112',
    '6': '111122211',
    '7': '212112111',
    '8': '112112112',
    '9': '112112211',
    'A': '211211112',
    'B': '211211211',
    'C': '111211212',
    'D': '211221111',
    'E': '111221112',
    'F': '111221211',
    'G': '212211111',
    'H': '112211112',
    'I': '112211211',
    'J': '112221111',
    'K': '221111112',
    'L': '221111211',
    'M': '121111212',
    'N': '221121111',
    'O': '121121112',
    'P': '121121211',
    'Q': '222111111',
    'R': '122111112',
    'S': '122111211',
    'T': '122121111',
    'U': '211111122',
    'V': '211111221',
    'W': '111111222',
    'X': '211121121',
    'Y': '111121122',
    'Z': '111121221',
    '-': '212111121',
    '.': '112111122',
    ' ': '112111221',
    r'$': '111212121',
    '/': '121112121',
    '+': '121211121',
    '%': '121212111',
    '*': '112121121',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final symbols = <String>['*', ...payload.split(''), '*'];
    if (size.width <= 0 ||
        size.height <= 0 ||
        symbols.any((symbol) => !_patterns.containsKey(symbol))) {
      return;
    }

    const quietZoneModules = 10;
    var totalModules = quietZoneModules * 2;
    for (var index = 0; index < symbols.length; index++) {
      final pattern = _patterns[symbols[index]]!;
      totalModules += pattern.runes
          .map((rune) => rune - 48)
          .reduce((left, right) => left + right);
      if (index < symbols.length - 1) totalModules++;
    }

    final moduleWidth = size.width / totalModules;
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    var cursor = quietZoneModules * moduleWidth;

    for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
      // Paint the reference widths in scan order. Painting the table order
      // directly makes barcode readers return the payload backwards.
      final pattern = _patterns[symbols[symbolIndex]]!
          .split('')
          .reversed
          .join();
      for (
        var elementIndex = 0;
        elementIndex < pattern.length;
        elementIndex++
      ) {
        final width = (pattern.codeUnitAt(elementIndex) - 48) * moduleWidth;
        if (elementIndex.isEven) {
          canvas.drawRect(Rect.fromLTWH(cursor, 0, width, size.height), paint);
        }
        cursor += width;
      }
      if (symbolIndex < symbols.length - 1) cursor += moduleWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _Code39BarcodePainter oldDelegate) {
    return oldDelegate.payload != payload;
  }
}
