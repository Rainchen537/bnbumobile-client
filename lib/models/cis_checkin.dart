import 'campus_time.dart';

/// School-owned data. These objects never contain credentials or a CIS token.
class CisCheckinProject {
  const CisCheckinProject({
    required this.id,
    required this.name,
    required this.requiredCount,
    required this.checkedCount,
    required this.completed,
    this.opensAt,
    this.closesAt,
  });

  final String id;
  final String name;
  final int requiredCount;
  final int checkedCount;
  final bool completed;
  final DateTime? opensAt;
  final DateTime? closesAt;

  factory CisCheckinProject.fromJson(Map<String, dynamic> json) {
    final project = cisObject(json['project']);
    final range = cisOptionalObject(json['timeRang'] ?? project['timeRang']);
    return CisCheckinProject(
      id: cisId(project['id']),
      name: cisTitle(project),
      requiredCount: cisCount(json['minCheckinTimes']),
      checkedCount: cisCount(json['studentCheckinTimes']),
      completed: cisBool(json['studentFinishCheckin']),
      opensAt: cisDate(range?['begin']),
      closesAt: cisDate(range?['end']),
    );
  }
}

class CisCheckinSession {
  const CisCheckinSession({
    this.beginsAt,
    this.endsAt,
    this.checkinAt,
    this.checkoutAt,
    required this.checkedIn,
    required this.checkedOut,
  });
  final DateTime? beginsAt;
  final DateTime? endsAt;
  final DateTime? checkinAt;
  final DateTime? checkoutAt;
  final bool? checkedIn;
  final bool? checkedOut;
}

class CisCheckinRecord {
  const CisCheckinRecord({
    required this.id,
    required this.name,
    required this.completed,
    required this.checkedIn,
    required this.checkedOut,
    required this.sessions,
    this.nameCn = '',
    this.speaker = '',
    this.location = '',
  });
  final String id;
  final String name;
  final String nameCn;
  final String speaker;
  final String location;
  final bool completed;
  final bool checkedIn;
  final bool checkedOut;
  final List<CisCheckinSession> sessions;

  /// Unknown status is not proof of completed statistics. The school's
  /// separate counting-list endpoint is deliberately never requested.
  static bool isSettled(Map<String, dynamic> json) {
    final item = cisObject(json['projectItem']);
    return item['counting'] == false || item['counting'] == 0;
  }

  static bool hasKnownStatistics(Map<String, dynamic> json) {
    final status = cisObject(json['projectItem'])['counting'];
    return status is bool || status == 0 || status == 1;
  }

  factory CisCheckinRecord.fromJson(Map<String, dynamic> json) {
    if (!isSettled(json)) throw const FormatException('Unsettled CIS record');
    final item = cisObject(json['projectItem']);
    final range = cisOptionalObject(item['timeRang']);
    final sessions = <CisCheckinSession>[
      CisCheckinSession(
        beginsAt: cisDate(range?['begin']),
        endsAt: cisDate(range?['end']),
        checkinAt: cisDate(json['checkinTime']),
        checkoutAt: cisDate(json['checkoutTime']),
        checkedIn: cisOptionalBool(json['checkinFinish']),
        checkedOut: cisOptionalBool(json['checkoutFinish']),
      ),
    ];
    final plusCount = item['plusCount'] == null
        ? (item['plus'] == true ? 1 : 0)
        : cisCount(item['plusCount']);
    if (plusCount > 3) throw const FormatException('Unsupported CIS sessions');
    for (var i = 1; i <= plusCount; i++) {
      final suffix = i == 1 ? 'Plus' : 'Plus$i';
      if (json['checkinTime$suffix'] == null &&
          json['checkoutTime$suffix'] == null) {
        continue;
      }
      sessions.add(
        CisCheckinSession(
          beginsAt: cisDate(item['begin$suffix']),
          endsAt: cisDate(item['end$suffix']),
          checkinAt: cisDate(json['checkinTime$suffix']),
          checkoutAt: cisDate(json['checkoutTime$suffix']),
          checkedIn: cisOptionalBool(json['checkinFinish$suffix']),
          checkedOut: cisOptionalBool(json['checkoutFinish$suffix']),
        ),
      );
    }
    return CisCheckinRecord(
      id: cisId(json['id']),
      name: cisTitle(item),
      nameCn: cisText(item['nameCn']),
      speaker: cisText(item['speaker']),
      location: cisText(item['location']),
      completed: cisBool(json['finish']),
      checkedIn: cisBool(json['mainCheckinFinish']),
      checkedOut: cisBool(json['mainCheckoutFinish']),
      sessions: List.unmodifiable(sessions),
    );
  }
}

class CisCheckinPageData<T> {
  const CisCheckinPageData({
    required this.items,
    required this.page,
    required this.hasMore,
    this.hasUnknownStatistics = false,
  });
  final List<T> items;
  final int page;
  // Based on the unfiltered server page, not the settled subset's length.
  final bool hasMore;
  final bool hasUnknownStatistics;
}

Map<String, dynamic> cisObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid CIS object');
  }
  return value;
}

Map<String, dynamic>? cisOptionalObject(Object? value) =>
    value == null ? null : cisObject(value);

String cisText(Object? value) {
  if (value == null) return '';
  if (value is! String || value.length > 8192) {
    throw const FormatException('Invalid CIS text');
  }
  return value.trim();
}

String cisTitle(Map<String, dynamic> value) {
  final name = cisText(value['nameEn']);
  final fallback = name.isEmpty ? cisText(value['nameCn']) : name;
  if (fallback.isEmpty) throw const FormatException('Missing CIS title');
  return fallback;
}

String cisId(Object? value) {
  final id = value is int && value >= 0 ? '$value' : cisText(value);
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
    throw const FormatException('Invalid CIS identifier');
  }
  return id;
}

int cisCount(Object? value) {
  if (value is! int || value < 0 || value > 10000000) {
    throw const FormatException('Invalid CIS count');
  }
  return value;
}

bool cisBool(Object? value) {
  if (value == true || value == 1) return true;
  if (value == false || value == 0) return false;
  throw const FormatException('Unknown CIS status');
}

bool? cisOptionalBool(Object? value) => value == null ? null : cisBool(value);

DateTime? cisDate(Object? value) {
  if (value == null || value == '') return null;
  if (value is int && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is! String || value.length > 80) {
    throw const FormatException('Invalid CIS date');
  }
  var text = value.replaceAll('/', '-').replaceFirst(' ', 'T');
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) text = '${text}T00:00:00';
  final hasZone = RegExp(
    r'(Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(text);
  final parsed = DateTime.tryParse(hasZone ? text : '$text+08:00');
  if (parsed == null) throw const FormatException('Invalid CIS date');
  return parsed.toUtc();
}

DateTime cisCampusDate(DateTime value) => toBnbuCampusClock(value);
