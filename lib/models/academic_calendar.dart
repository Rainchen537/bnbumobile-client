import 'package:flutter/foundation.dart';

import 'timetable_data.dart';

const String bnbuAy202627Semester1Title = 'Semester 1 of AY2026-27';

enum BnbuCalendarEventKind {
  term('term'),
  registration('registration'),
  teaching('teaching'),
  makeUpClass('make_up_class'),
  holiday('holiday'),
  readingWeek('reading_week'),
  exam('exam'),
  administrative('administrative');

  const BnbuCalendarEventKind(this.wireValue);
  final String wireValue;
}

class BnbuCalendarEvent {
  const BnbuCalendarEvent({
    required this.kind,
    required this.name,
    required this.startsOn,
    required this.endsOn,
    this.reason = '',
    this.sourceWeekday,
    this.notice = '',
  });

  final BnbuCalendarEventKind kind;
  final String name;
  final DateTime startsOn;
  final DateTime endsOn;
  final String reason;
  final int? sourceWeekday;
  final String notice;
}

class BnbuAcademicCalendarContext {
  const BnbuAcademicCalendarContext({
    required this.semesterTitle,
    required this.timezone,
    required this.appliesToSelectedSemester,
    required this.semesterStartsOn,
    required this.lastClassDay,
    required this.events,
  });

  final String semesterTitle;
  final String timezone;
  final bool appliesToSelectedSemester;
  final DateTime semesterStartsOn;
  final DateTime lastClassDay;
  final List<BnbuCalendarEvent> events;
}

class BnbuClassDay {
  const BnbuClassDay({
    required this.date,
    required this.sourceWeekday,
    this.notice,
  });

  final DateTime date;
  final int? sourceWeekday;
  final String? notice;

  bool get hasClasses => sourceWeekday != null;
  bool get isMakeUpDay =>
      sourceWeekday != null && sourceWeekday != date.weekday;
}

/// Senate-approved academic calendar entries for Semester 1 of AY2026-27.
///
/// This is the single source for the bounded Small U calendar context and
/// class-day exceptions.  Only the teaching-related entries are used by
/// [classDayFor], so later administrative events cannot affect MIS recurrence.
class BnbuAcademicCalendar {
  const BnbuAcademicCalendar._();

  static final List<BnbuCalendarEvent> _builtInEvents = List.unmodifiable([
    _event(
      BnbuCalendarEventKind.term,
      'Summer Term Ends (AY2025/26) / 2025/26 夏季学期结束',
      2026,
      8,
      18,
    ),
    _event(
      BnbuCalendarEventKind.registration,
      'Registration of Year 1 Students / 一年级学生注册',
      2026,
      8,
      23,
      endDay: 24,
    ),
    _event(
      BnbuCalendarEventKind.registration,
      'New Student Orientation & English Enhancement Programme / 新生迎新及英语强化课程',
      2026,
      8,
      25,
      endDay: 31,
    ),
    _event(
      BnbuCalendarEventKind.term,
      'Semester I Begins / First Day of Classes / 第一学期开始及首个上课日',
      2026,
      9,
      1,
    ),
    _event(
      BnbuCalendarEventKind.registration,
      'Course Add/Drop / 选退课期',
      2026,
      9,
      1,
      endDay: 14,
    ),
    _event(
      BnbuCalendarEventKind.makeUpClass,
      'Make-up for Friday’s class / All Staff on Duty / 周五课程补课及全体教职员上班',
      2026,
      9,
      20,
      reason: '按周五课表补课；全体教职员上班',
      sourceWeekday: DateTime.friday,
    ),
    _event(
      BnbuCalendarEventKind.holiday,
      'Mid-Autumn Festival / 中秋节假期',
      2026,
      9,
      25,
      endDay: 27,
    ),
    _event(
      BnbuCalendarEventKind.holiday,
      'National Day holidays / 国庆节假期',
      2026,
      10,
      1,
      endDay: 7,
    ),
    _event(
      BnbuCalendarEventKind.makeUpClass,
      'Make-up for Monday’s class / All Staff on Duty / 周一课程补课及全体教职员上班',
      2026,
      10,
      10,
      reason: '按周一课表补课；全体教职员上班',
      sourceWeekday: DateTime.monday,
    ),
    _event(
      BnbuCalendarEventKind.readingWeek,
      'Reading Week / 阅读周',
      2026,
      10,
      25,
      endDay: 31,
    ),
    _event(
      BnbuCalendarEventKind.teaching,
      'Semester I Last Day of Classes / 第一学期最后上课日',
      2026,
      12,
      11,
    ),
    _event(
      BnbuCalendarEventKind.exam,
      'Reserved for CET / 大学英语四、六级考试预留',
      2026,
      12,
      12,
    ),
    _event(
      BnbuCalendarEventKind.exam,
      'Revision for Final Examinations / 期末考试复习期',
      2026,
      12,
      13,
      endDay: 15,
    ),
    _event(
      BnbuCalendarEventKind.exam,
      'Semester I Final Examinations / 第一学期期末考试',
      2026,
      12,
      16,
      endDay: 27,
    ),
    _event(
      BnbuCalendarEventKind.term,
      'Military Training for Year 1 Students / 一年级学生军训',
      2026,
      12,
      28,
      endDay: 31,
    ),
    _event(
      BnbuCalendarEventKind.holiday,
      'New Year holiday / 元旦假期',
      2027,
      1,
      1,
    ),
    _event(
      BnbuCalendarEventKind.term,
      'Military Training for Year 1 Students / 一年级学生军训',
      2027,
      1,
      2,
      endDay: 11,
    ),
    _event(
      BnbuCalendarEventKind.administrative,
      'Faculty Board Meetings / 学院委员会会议',
      2027,
      1,
      6,
    ),
    _event(
      BnbuCalendarEventKind.administrative,
      'Senate Meeting / 校务委员会会议',
      2027,
      1,
      8,
    ),
    _event(
      BnbuCalendarEventKind.term,
      'Release of Grade Reports / Semester I Ends / 成绩报告发布及第一学期结束',
      2027,
      1,
      11,
    ),
    _event(
      BnbuCalendarEventKind.holiday,
      'Chinese New Year holidays (University closed) / 春节假期（大学关闭）',
      2027,
      1,
      24,
      endDay: 31,
    ),
  ]);

  static final revision = ValueNotifier<int>(0);
  static BnbuCalendarCatalog? _catalog;
  static BnbuCalendarCatalog? get catalog => _catalog;
  static final builtIn = BnbuCalendarSemester(
    id: '2026-27-s1',
    academicYearStart: 2026,
    semester: 1,
    semesterTitle: bnbuAy202627Semester1Title,
    semesterIds: const [],
    semesterStartsOn: DateTime(2026, 9, 1),
    lastClassDay: DateTime(2026, 12, 11),
    events: _builtInEvents,
    documents: const {},
  );
  static BnbuCalendarSemester get current => _catalog?.current ?? builtIn;
  static List<BnbuCalendarEvent> get events => current.events;
  static DateTime get semesterStarts => current.semesterStartsOn;
  static DateTime get lastClassDay => current.lastClassDay;

  /// Atomically publish one validated snapshot. Consumers keep the original API.
  static void install(BnbuCalendarCatalog? value) {
    _catalog = value;
    revision.value++;
  }

  static BnbuCalendarSemester? semesterFor(TimetableData timetable) {
    for (final term in _catalog?.semesters ?? <BnbuCalendarSemester>[]) {
      if (term.matches(timetable)) return term;
    }
    if (builtIn.matches(timetable) &&
        !(_catalog?.semesters.any((s) => s.id == builtIn.id) ?? false)) {
      return builtIn;
    }
    return null;
  }

  static BnbuAcademicCalendarContext contextFor(TimetableData? timetable) {
    final term = timetable == null
        ? current
        : semesterFor(timetable) ?? current;
    return BnbuAcademicCalendarContext(
      semesterTitle: term.semesterTitle,
      timezone: 'Asia/Shanghai',
      appliesToSelectedSemester: timetable != null && term.matches(timetable),
      semesterStartsOn: term.semesterStartsOn,
      lastClassDay: term.lastClassDay,
      events: term.events,
    );
  }

  static bool appliesTo(TimetableData timetable) =>
      semesterFor(timetable) != null;

  static BnbuClassDay classDayFor(
    TimetableData timetable,
    DateTime campusDate,
  ) {
    final date = _dateOnly(campusDate);
    final term = semesterFor(timetable);
    if (term == null) {
      return BnbuClassDay(date: date, sourceWeekday: date.weekday);
    }
    if (date.isBefore(term.semesterStartsOn) ||
        date.isAfter(term.lastClassDay)) {
      return BnbuClassDay(date: date, sourceWeekday: null);
    }
    for (final event in term.events) {
      if (!_isWithin(date, event.startsOn, event.endsOn)) continue;
      if (event.kind == BnbuCalendarEventKind.holiday ||
          event.kind == BnbuCalendarEventKind.readingWeek) {
        return BnbuClassDay(
          date: date,
          sourceWeekday: null,
          notice: _notice(event),
        );
      }
      if (event.kind == BnbuCalendarEventKind.makeUpClass) {
        return BnbuClassDay(
          date: date,
          sourceWeekday: event.sourceWeekday,
          notice: _notice(event),
        );
      }
    }
    return BnbuClassDay(date: date, sourceWeekday: date.weekday);
  }

  static String _notice(BnbuCalendarEvent event) {
    if (event.notice.isNotEmpty) return event.notice;
    // Preserve the bundled calendar's existing display strings.
    if (event.kind == BnbuCalendarEventKind.readingWeek) {
      return 'Reading Week 假期';
    }
    if (event.name == 'Mid-Autumn Festival / 中秋节假期') return '中秋假期';
    if (event.name == 'National Day holidays / 国庆节假期') return '国庆假期';
    if (event.kind == BnbuCalendarEventKind.makeUpClass) {
      return '补周${const ['一', '二', '三', '四', '五', '六', '日'][event.sourceWeekday! - 1]}课程';
    }
    return event.name;
  }

  static DateTime? nextMeetingDate({
    required TimetableData timetable,
    required TimetableMeeting meeting,
    required DateTime fromCampusDate,
    int searchDays = 370,
  }) {
    final start = _dateOnly(fromCampusDate);
    for (var offset = 0; offset <= searchDays; offset++) {
      final date = _addDays(start, offset);
      if (classDayFor(timetable, date).sourceWeekday == meeting.weekday) {
        return date;
      }
    }
    return null;
  }

  static String? noticeForWeek(TimetableData timetable, DateTime weekStart) {
    final term = semesterFor(timetable);
    if (term == null) return null;
    final end = _addDays(weekStart, 6);
    for (final event in term.events) {
      if (event.kind == BnbuCalendarEventKind.readingWeek &&
          !event.startsOn.isAfter(end) &&
          !event.endsOn.isBefore(weekStart)) {
        return _notice(event);
      }
    }
    return null;
  }

  static BnbuCalendarEvent _event(
    BnbuCalendarEventKind kind,
    String name,
    int year,
    int month,
    int day, {
    int? endDay,
    String reason = '',
    int? sourceWeekday,
  }) => BnbuCalendarEvent(
    kind: kind,
    name: name,
    startsOn: DateTime(year, month, day),
    endsOn: DateTime(year, month, endDay ?? day),
    reason: reason,
    sourceWeekday: sourceWeekday,
  );

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static DateTime _addDays(DateTime value, int days) =>
      DateTime(value.year, value.month, value.day + days);
  static bool _isWithin(DateTime value, DateTime start, DateTime end) =>
      !value.isBefore(start) && !value.isAfter(end);
}

/// Public wire envelope; never contains a school identity or session.
class BnbuCalendarCatalog {
  BnbuCalendarCatalog({
    required this.version,
    required this.defaultSemesterId,
    required this.semesters,
  });
  final int version;
  final String defaultSemesterId;
  final List<BnbuCalendarSemester> semesters;
  BnbuCalendarSemester? get current => semesters.isEmpty
      ? null
      : semesters.firstWhere((s) => s.id == defaultSemesterId);

  factory BnbuCalendarCatalog.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 ||
        json['version'] is! int ||
        (json['version'] as int) < 0) {
      throw const FormatException('Calendar version');
    }
    final data = json['catalog'] as Map<String, dynamic>;
    final raw = data['semesters'] as List;
    if (raw.length > 60) throw const FormatException('Calendar size');
    final semesters = raw
        .map((s) => BnbuCalendarSemester.fromJson(s as Map<String, dynamic>))
        .toList();
    final ids = <String>{}, terms = <String>{}, aliases = <String>{};
    for (final term in semesters) {
      if (!ids.add(term.id) ||
          !terms.add('${term.academicYearStart}-${term.semester}')) {
        throw const FormatException('Duplicate semester');
      }
      for (final alias in term.semesterIds) {
        if (!aliases.add(alias.trim().toLowerCase())) {
          throw const FormatException('Duplicate semester alias');
        }
      }
    }
    final selected = data['default_semester_id'] as String;
    if (semesters.isEmpty ? selected.isNotEmpty : !ids.contains(selected)) {
      throw const FormatException('Default semester');
    }
    return BnbuCalendarCatalog(
      version: json['version'] as int,
      defaultSemesterId: selected,
      semesters: List.unmodifiable(semesters),
    );
  }
}

class BnbuCalendarSemester {
  const BnbuCalendarSemester({
    required this.id,
    required this.academicYearStart,
    required this.semester,
    required this.semesterTitle,
    required this.semesterIds,
    required this.semesterStartsOn,
    required this.lastClassDay,
    required this.events,
    required this.documents,
  });
  final String id, semesterTitle;
  final int academicYearStart, semester;
  final List<String> semesterIds;
  final DateTime semesterStartsOn, lastClassDay;
  final List<BnbuCalendarEvent> events;
  final Map<String, ({String title, Uri uri})> documents;

  bool matches(TimetableData timetable) {
    if (semesterIds.any(
      (id) =>
          id.trim().toLowerCase() ==
          timetable.selectedSemesterId.trim().toLowerCase(),
    )) {
      return true;
    }
    final value =
        '${timetable.selectedSemesterId} ${timetable.selectedSemesterName}'
            .toLowerCase();
    final years = RegExp(
      r'(?:ay\s*)?(20\d{2})\s*[-/]\s*(\d{2}|20\d{2})\b',
    ).allMatches(value).toList();
    final yearMatches = years.isEmpty
        ? RegExp('(?:^|\\D)$academicYearStart(?:\$|\\D)').hasMatch(value)
        : years.any((m) {
            final start = int.parse(m[1]!);
            final rawEnd = int.parse(m[2]!);
            final end = rawEnd < 100 ? (start ~/ 100) * 100 + rawEnd : rawEnd;
            return start == academicYearStart && end == start + 1;
          });
    // Winter's wire value is not an official MIS "Semester 4" identifier.
    // Match its explicit alias or year-qualified name without guessing one.
    if (semester == 4) {
      return yearMatches &&
          RegExp(
            r'\bwinter\b|\bmilitary\s+training\b|冬季|军训|軍訓',
          ).hasMatch(value);
    }
    final roman = const ['i', 'ii', 'iii'][semester - 1];
    final chinese = const ['一', '二', '三'][semester - 1];
    return yearMatches &&
        (RegExp(
              '(?:^|[^a-z0-9])(?:semester|sem|s)\\s*(?:$semester|$roman)(?:\$|[^a-z0-9])',
            ).hasMatch(value) ||
            RegExp('第\\s*(?:$semester|$chinese)\\s*学期').hasMatch(value) ||
            (semester == 3 && RegExp(r'\bsummer\b|夏季').hasMatch(value)));
  }

  factory BnbuCalendarSemester.fromJson(Map<String, dynamic> data) {
    final id = _calendarText(data['id'], 64);
    if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id)) {
      throw const FormatException('Semester id');
    }
    final year = data['academic_year_start'] as int,
        semester = data['semester'] as int;
    if (year < 2000 || year > 2198 || semester < 1 || semester > 4) {
      throw const FormatException('Semester');
    }
    final starts = _calendarDate(data['semester_starts_on']),
        last = _calendarDate(data['last_class_day']);
    final lower = DateTime(year), upper = DateTime(year + 2);
    bool validRange(DateTime a, DateTime b) =>
        !a.isBefore(lower) && !b.isBefore(a) && b.isBefore(upper);
    if (!validRange(starts, last)) {
      throw const FormatException('Teaching range');
    }
    final rawEvents = data['events'] as List;
    if (rawEvents.length > 200) throw const FormatException('Events size');
    final events = <BnbuCalendarEvent>[], effects = <BnbuCalendarEvent>[];
    for (final raw in rawEvents) {
      final e = raw as Map<String, dynamic>;
      final kind = BnbuCalendarEventKind.values.firstWhere(
        (v) => v.wireValue == e['kind'],
      );
      final a = _calendarDate(e['starts_on']), b = _calendarDate(e['ends_on']);
      final weekday = e['source_weekday'] as int?;
      if (!validRange(a, b) ||
          (kind == BnbuCalendarEventKind.makeUpClass
              ? weekday == null ||
                    weekday < 1 ||
                    weekday > 7 ||
                    a != b ||
                    a.isBefore(starts) ||
                    a.isAfter(last)
              : weekday != null)) {
        throw const FormatException('Event range or weekday');
      }
      final event = BnbuCalendarEvent(
        kind: kind,
        name: _calendarText(e['name'], 240),
        startsOn: a,
        endsOn: b,
        reason: _calendarText(e['reason'] ?? '', 500, empty: true),
        sourceWeekday: weekday,
        notice: _calendarText(e['notice'] ?? '', 120, empty: true),
      );
      if ([
        BnbuCalendarEventKind.holiday,
        BnbuCalendarEventKind.readingWeek,
        BnbuCalendarEventKind.makeUpClass,
      ].contains(kind)) {
        if (effects.any(
          (other) => !a.isAfter(other.endsOn) && !b.isBefore(other.startsOn),
        )) {
          throw const FormatException('Overlapping class rules');
        }
        effects.add(event);
      }
      events.add(event);
    }
    final docs = <String, ({String title, Uri uri})>{};
    for (final key in ['academic_calendar', 'class_schedule']) {
      final raw = (data['documents'] as Map)[key] as Map;
      final uri = Uri.parse(_calendarText(raw['url'], 500));
      if (uri.scheme != 'https' ||
          uri.host != 'ar.bnbu.edu.cn' ||
          uri.port != 443 ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !uri.path.toLowerCase().endsWith('.pdf')) {
        throw const FormatException('Official PDF origin');
      }
      docs[key] = (title: _calendarText(raw['title'], 240), uri: uri);
    }
    final aliases = (data['semester_ids'] as List? ?? [])
        .map((v) => _calendarText(v, 160))
        .toList();
    if (aliases.length > 20) throw const FormatException('Aliases size');
    return BnbuCalendarSemester(
      id: id,
      academicYearStart: year,
      semester: semester,
      semesterTitle: _calendarText(data['semester_title'], 160),
      semesterIds: List.unmodifiable(aliases),
      semesterStartsOn: starts,
      lastClassDay: last,
      events: List.unmodifiable(events),
      documents: Map.unmodifiable(docs),
    );
  }
}

String _calendarText(dynamic value, int limit, {bool empty = false}) {
  if (value is! String ||
      value.length > limit ||
      (!empty && value.trim().isEmpty)) {
    throw const FormatException('Calendar text');
  }
  return value;
}

DateTime _calendarDate(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Date format');
  }
  final date = DateTime.parse(value);
  if (date.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Date value');
  }
  return date;
}
