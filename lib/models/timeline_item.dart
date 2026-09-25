import 'package:intl/intl.dart';

class TimelineItem {
  TimelineItem({
    required this.id,
    required this.title,
    required this.activityState,
    required this.activityType,
    required this.moduleName,
    required this.description,
    required this.courseName,
    required this.courseId,
    required this.instanceId,
    required this.url,
    this.iconUrl = '',
    required this.sortTime,
    required this.formattedTime,
    required this.isOverdue,
  });

  final int id;
  final String title;
  final String activityState;
  final String activityType;
  final String moduleName;
  final String description;
  final String courseName;
  final int courseId;
  final int instanceId;
  final String url;
  final String iconUrl;
  final DateTime? sortTime;
  final String formattedTime;
  final bool isOverdue;

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    final course = json['course'];
    final courseId = _toInt(
      json['courseid'] ??
          (course is Map<String, dynamic> ? course['id'] : null),
    );
    return TimelineItem(
      id: _toInt(json['id']),
      title: _pickString(json, const [
        'activityname',
        'name',
        'eventname',
        'title',
      ], '未命名事件'),
      activityState: _pickString(json, const [
        'activitystr',
        'normalisedeventtypetext',
        'eventtype',
      ]),
      activityType: _pickString(json, const [
        'modulename',
        'eventtype',
        'activitytype',
        'activityname',
      ]),
      moduleName: _pickString(json, const ['modulename', 'eventtype']),
      description: _stripHtml(
        _pickString(json, const ['description', 'formatteddescription']),
      ),
      courseName: _courseName(course),
      courseId: courseId,
      instanceId: _toInt(json['instance'] ?? json['activityinstance']),
      url: _extractUrl(json),
      iconUrl: _extractIconUrl(json),
      sortTime: _toDateTime(
        json['timesort'] ??
            json['timedue'] ??
            json['timestart'] ??
            json['timecreated'],
      ),
      formattedTime: _pickString(json, const ['formattedtime']),
      isOverdue: _toBool(json['overdue']),
    );
  }

  String displayTime(DateFormat formatter) {
    if (sortTime != null) {
      return formatter.format(sortTime!.toLocal());
    }
    if (formattedTime.isNotEmpty) {
      return formattedTime;
    }
    return '无时间信息';
  }

  static String _courseName(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _pickString(value, const ['fullname', 'displayname', 'shortname']);
    }
    if (value is String) {
      return value;
    }
    return '';
  }

  static String _extractUrl(Map<String, dynamic> json) {
    final action = json['action'];
    if (action is Map<String, dynamic>) {
      final actionUrl = action['url'];
      if (actionUrl is String) {
        return actionUrl;
      }
    }
    return _pickString(json, const ['viewurl', 'url']);
  }

  static String _extractIconUrl(Map<String, dynamic> json) {
    final icon = json['icon'];
    if (icon is Map<String, dynamic>) {
      final iconUrl = _pickString(icon, const ['iconurl', 'url']);
      if (iconUrl.isNotEmpty) {
        return iconUrl;
      }
    } else if (icon is Map) {
      final casted = icon.cast<String, dynamic>();
      final iconUrl = _pickString(casted, const ['iconurl', 'url']);
      if (iconUrl.isNotEmpty) {
        return iconUrl;
      }
    }
    return _pickString(json, const ['iconurl', 'modicon']);
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

  static DateTime? _toDateTime(dynamic value) {
    final timestamp = _toInt(value);
    if (timestamp <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
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

  static bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  static String _stripHtml(String input) {
    if (input.isEmpty) {
      return '';
    }
    return input
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
