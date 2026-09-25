class CourseSummary {
  CourseSummary({
    required this.id,
    required this.fullName,
    required this.shortName,
    required this.categoryName,
    required this.progress,
    this.startAt,
    this.endAt,
    this.visible = true,
    this.hidden = false,
    this.enableCompletion = false,
    this.completionUserTracked = false,
    this.completed = false,
    this.showGrades = false,
    this.showActivityDates = false,
    this.showCompletionConditions = false,
  });

  final int id;
  final String fullName;
  final String shortName;
  final String categoryName;
  final int? progress;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool visible;
  final bool hidden;
  final bool enableCompletion;
  final bool completionUserTracked;
  final bool completed;
  final bool showGrades;
  final bool showActivityDates;
  final bool showCompletionConditions;

  factory CourseSummary.fromJson(Map<String, dynamic> json) {
    return CourseSummary(
      id: _toInt(json['id']),
      fullName: _pickString(json, const ['fullname', 'displayname'], '未命名课程'),
      shortName: _pickString(json, const ['shortname']),
      categoryName: _pickString(json, const ['categoryname', 'category']),
      progress: _toNullableInt(json['progress']),
      startAt: _toDateTime(json['startdate']),
      endAt: _toDateTime(json['enddate']),
      visible: _toBool(json['visible']),
      hidden: _toBool(json['hidden']),
      enableCompletion: _toBool(json['enablecompletion']),
      completionUserTracked: _toBool(json['completionusertracked']),
      completed: _toBool(json['completed']),
      showGrades: _toBool(json['showgrades']),
      showActivityDates: _toBool(json['showactivitydates']),
      showCompletionConditions: _toBool(json['showcompletionconditions']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    final parsed = _toInt(value);
    return parsed;
  }

  static DateTime? _toDateTime(dynamic value) {
    final seconds = _toInt(value);
    if (seconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static bool _toBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }

  static String _pickString(
    Map<String, dynamic> json,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }
}
