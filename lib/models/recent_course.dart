class RecentCourse {
  RecentCourse({
    required this.id,
    required this.fullName,
    required this.shortName,
    required this.viewUrl,
    required this.courseImage,
    required this.userAccessedEpoch,
    required this.progress,
  });

  final int id;
  final String fullName;
  final String shortName;
  final String viewUrl;
  final String courseImage;
  final int userAccessedEpoch;
  final int? progress;

  DateTime? get userAccessedAt {
    if (userAccessedEpoch <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      userAccessedEpoch * 1000,
      isUtc: true,
    );
  }

  factory RecentCourse.fromJson(Map<String, dynamic> json) {
    return RecentCourse(
      id: _toInt(json['id']),
      fullName: _pickString(json, const ['fullname', 'displayname'], '未命名课程'),
      shortName: _pickString(json, const ['shortname']),
      viewUrl: _pickString(json, const ['viewurl']),
      courseImage: _pickString(json, const ['courseimage']),
      userAccessedEpoch: _toInt(json['useraccessed']),
      progress: _toNullableInt(json['progress']),
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
    return _toInt(value);
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
