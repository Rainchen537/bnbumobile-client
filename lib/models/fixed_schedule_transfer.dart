import 'dart:convert';
import 'ta_course_entry.dart';

/// Version 3 intentionally changes the envelope key: older readers must reject
/// this file instead of importing selected weeks as unrestricted weekly events.
abstract final class FixedScheduleTransfer {
  static String encode(Iterable<TaCourseEntry> entries) => jsonEncode({
    'version': 3,
    'fixedSchedules': entries.map((entry) => entry.toJson()).toList(),
  });

  static List<TaCourseEntry> decode(String raw) {
    final decoded = jsonDecode(raw);
    final Object? entries;
    if (decoded is Map<String, dynamic>) {
      final version = decoded['version'] ?? 1;
      if (![1, 2, 3].contains(version)) throw const FormatException('不支持的日程版本');
      entries = decoded[version == 3 ? 'fixedSchedules' : 'entries'];
    } else {
      entries = decoded;
    }
    if (entries is! List) throw const FormatException('导入文件格式不正确');
    return entries
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('日程格式不正确');
          }
          return TaCourseEntry.fromJson(item);
        })
        .toList(growable: false);
  }
}
