import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';

enum ExamTimetableAvailability { available, empty, unavailable }

class ExamTimetableData {
  const ExamTimetableData({
    required this.availability,
    this.entries = const <ExamTimetableEntry>[],
  });

  const ExamTimetableData.unavailable()
    : availability = ExamTimetableAvailability.unavailable,
      entries = const <ExamTimetableEntry>[];

  final ExamTimetableAvailability availability;
  final List<ExamTimetableEntry> entries;

  factory ExamTimetableData.fromHtml(String source) {
    final document = html_parser.parse(source);
    final parsedEntries = <ExamTimetableEntry>[];
    for (final table in document.querySelectorAll('table')) {
      parsedEntries.addAll(_entriesFromTable(table));
    }
    final entries = deduplicateEntries(parsedEntries);
    return ExamTimetableData(
      availability: entries.isEmpty
          ? ExamTimetableAvailability.empty
          : ExamTimetableAvailability.available,
      entries: entries,
    );
  }

  static List<ExamTimetableEntry> deduplicateEntries(
    Iterable<ExamTimetableEntry> source,
  ) {
    final entriesByIdentity = <String, ExamTimetableEntry>{};
    for (final entry in source) {
      final existing = entriesByIdentity[entry.identityKey];
      if (existing == null ||
          (existing.remark.isEmpty && entry.remark.isNotEmpty)) {
        entriesByIdentity[entry.identityKey] = entry;
      }
    }
    final entries = entriesByIdentity.values.toList(growable: false)
      ..sort((left, right) => left.startsAt.compareTo(right.startsAt));
    return entries;
  }

  static List<ExamTimetableEntry> _entriesFromTable(Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.length < 2) return const <ExamTimetableEntry>[];
    for (var headerIndex = 0; headerIndex < rows.length - 1; headerIndex++) {
      final headerCells = rows[headerIndex].querySelectorAll('th, td');
      final headers = headerCells.map((cell) => _normalize(cell.text)).toList();
      final columns = _ExamColumns.fromHeaders(headers);
      if (!columns.isExamTable) continue;
      final entries = <ExamTimetableEntry>[];
      for (final row in rows.skip(headerIndex + 1)) {
        final cells = row.querySelectorAll('th, td');
        if (cells.length < headers.length) continue;
        final values = cells.map((cell) => _normalize(cell.text)).toList();
        final entry = ExamTimetableEntry._tryParse(values, columns);
        if (entry != null) entries.add(entry);
      }
      return entries;
    }
    return const <ExamTimetableEntry>[];
  }

  static String _normalize(String value) =>
      value.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class ExamTimetableEntry {
  const ExamTimetableEntry({
    required this.courseCode,
    required this.courseName,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.room,
    required this.seat,
    required this.remark,
  });

  final String courseCode;
  final String courseName;
  final DateTime date;
  final int startMinutes;
  final int endMinutes;
  final String room;
  final String seat;
  final String remark;

  DateTime get startsAt => DateTime(
    date.year,
    date.month,
    date.day,
  ).add(Duration(minutes: startMinutes));
  DateTime get endsAt => DateTime(
    date.year,
    date.month,
    date.day,
  ).add(Duration(minutes: endMinutes));
  String get timeLabel =>
      '${_formatMinutes(startMinutes)}-${_formatMinutes(endMinutes)}';
  String get displayName => courseName.isNotEmpty ? courseName : courseCode;
  String get identityKey => <String>[
    courseCode.trim().toLowerCase(),
    courseName.trim().toLowerCase(),
    DateFormat('yyyy-MM-dd').format(date),
    startMinutes.toString(),
    endMinutes.toString(),
    room.trim().toLowerCase(),
    seat.trim().toLowerCase(),
  ].join('\u001f');
  String get widgetKey => identityKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'courseCode': courseCode,
    'courseName': courseName,
    'date': DateFormat('yyyy-MM-dd').format(date),
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'room': room,
    'seat': seat,
    'remark': remark,
  };

  factory ExamTimetableEntry.fromJson(Map<String, dynamic> json) {
    final date = _parseDate(
      json['date'] is String ? json['date'] as String : '',
    );
    final startMinutes = json['startMinutes'];
    final endMinutes = json['endMinutes'];
    if (date == null || startMinutes is! num || endMinutes is! num) {
      throw const FormatException('Invalid exam timetable cache entry.');
    }
    return ExamTimetableEntry(
      courseCode: json['courseCode'] is String
          ? json['courseCode'] as String
          : '',
      courseName: json['courseName'] is String
          ? json['courseName'] as String
          : '',
      date: date,
      startMinutes: startMinutes.toInt(),
      endMinutes: endMinutes.toInt(),
      room: json['room'] is String ? json['room'] as String : '',
      seat: json['seat'] is String ? json['seat'] as String : '',
      remark: json['remark'] is String ? json['remark'] as String : '',
    );
  }

  static ExamTimetableEntry? _tryParse(
    List<String> values,
    _ExamColumns columns,
  ) {
    final date = _parseDate(columns.value(values, columns.date));
    final timeRange = _parseTimeRange(columns.value(values, columns.time));
    if (date == null || timeRange == null) return null;
    final courseCode = columns.value(values, columns.courseCode);
    final courseName = columns.value(values, columns.courseName);
    if (courseCode.isEmpty && courseName.isEmpty) return null;
    return ExamTimetableEntry(
      courseCode: courseCode,
      courseName: courseName,
      date: date,
      startMinutes: timeRange.$1,
      endMinutes: timeRange.$2,
      room: columns.value(values, columns.room),
      seat: columns.value(values, columns.seat),
      remark: columns.value(values, columns.remark),
    );
  }

  static DateTime? _parseDate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    for (final format in <String>[
      'yyyy-MM-dd',
      'yyyy/MM/dd',
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'd MMM yyyy',
      'MMM d, yyyy',
    ]) {
      try {
        final parsed = DateFormat(format, 'en_US').parseStrict(normalized);
        return DateTime(parsed.year, parsed.month, parsed.day);
      } on FormatException {
        // Try the next official date style.
      }
    }
    return null;
  }

  static (int, int)? _parseTimeRange(String value) {
    final match = RegExp(
      r'^(\d{1,2}:\d{2}\s*(?:AM|PM)?)\s*(?:-|–|—|to)\s*(\d{1,2}:\d{2}\s*(?:AM|PM)?)$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    final start = _parseMinutes(match.group(1)!);
    final end = _parseMinutes(match.group(2)!);
    if (start == null || end == null || end <= start) return null;
    return (start, end);
  }

  static int? _parseMinutes(String value) {
    final normalized = value.trim().toUpperCase();
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    var hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || minute > 59) return null;
    final period = match.group(3);
    if (period == null) {
      if (hour > 23) return null;
    } else {
      if (hour < 1 || hour > 12) return null;
      if (period == 'AM' && hour == 12) hour = 0;
      if (period == 'PM' && hour != 12) hour += 12;
    }
    return hour * 60 + minute;
  }

  static String _formatMinutes(int value) {
    final hour = (value ~/ 60).toString().padLeft(2, '0');
    final minute = (value % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ExamColumns {
  const _ExamColumns({
    required this.courseCode,
    required this.courseName,
    required this.date,
    required this.time,
    required this.room,
    required this.seat,
    required this.remark,
  });

  final int? courseCode;
  final int? courseName;
  final int? date;
  final int? time;
  final int? room;
  final int? seat;
  final int? remark;

  bool get isExamTable =>
      date != null &&
      time != null &&
      (courseCode != null || courseName != null);
  String value(List<String> values, int? index) =>
      index != null && index >= 0 && index < values.length ? values[index] : '';

  factory _ExamColumns.fromHeaders(List<String> headers) {
    int? find(List<RegExp> patterns) {
      for (var index = 0; index < headers.length; index++) {
        final header = headers[index].toLowerCase();
        if (patterns.any((pattern) => pattern.hasMatch(header))) return index;
      }
      return null;
    }

    return _ExamColumns(
      courseCode: find(<RegExp>[
        RegExp(r'course\s*code'),
        RegExp(r'module\s*code'),
        RegExp(r'课程代码'),
      ]),
      courseName: find(<RegExp>[
        RegExp(r'course\s*(?:name|title)'),
        RegExp(r'module\s*(?:name|title)'),
        RegExp(r'课程名称'),
      ]),
      date: find(<RegExp>[
        RegExp(r'exam\s*date'),
        RegExp(r'^date$'),
        RegExp(r'考试日期'),
      ]),
      time: find(<RegExp>[
        RegExp(r'exam\s*time'),
        RegExp(r'^time$'),
        RegExp(r'考试时间'),
      ]),
      room: find(<RegExp>[RegExp(r'venue'), RegExp(r'room'), RegExp(r'考场')]),
      seat: find(<RegExp>[RegExp(r'seat'), RegExp(r'座位')]),
      remark: find(<RegExp>[RegExp(r'remark'), RegExp(r'note'), RegExp(r'备注')]),
    );
  }
}
