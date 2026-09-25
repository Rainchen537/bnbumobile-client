class CourseGradeSnapshot {
  const CourseGradeSnapshot({required this.courseId, required this.items});

  final int courseId;
  final List<CourseGradeItem> items;

  factory CourseGradeSnapshot.fromJson(
    Map<String, dynamic> json, {
    required int courseId,
    required int userId,
  }) {
    final userGrades = json['usergrades'];
    if (userGrades is! List) {
      return CourseGradeSnapshot(courseId: courseId, items: const []);
    }
    final matches = userGrades.whereType<Map>().where(
      (grade) => _toInt(grade['userid']) == userId,
    );
    if (matches.length != 1) {
      return CourseGradeSnapshot(courseId: courseId, items: const []);
    }
    final gradeReport = matches.single.cast<String, dynamic>();
    final rawItems = gradeReport['gradeitems'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    CourseGradeItem.fromJson(item.cast<String, dynamic>()),
              )
              .where((item) => item.id > 0 && item.name.isNotEmpty)
              .toList(growable: false)
        : const <CourseGradeItem>[];
    return CourseGradeSnapshot(courseId: courseId, items: items);
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class CourseGradeItem {
  const CourseGradeItem({
    required this.id,
    required this.name,
    required this.moduleType,
    required this.courseModuleId,
    required this.gradeFormatted,
    required this.rangeFormatted,
    required this.percentageFormatted,
    required this.feedbackHtml,
    required this.hidden,
    required this.locked,
    required this.submittedEpoch,
    required this.gradedEpoch,
  });

  final int id;
  final String name;
  final String moduleType;
  final int courseModuleId;
  final String gradeFormatted;
  final String rangeFormatted;
  final String percentageFormatted;
  final String feedbackHtml;
  final bool hidden;
  final bool locked;
  final int submittedEpoch;
  final int gradedEpoch;

  DateTime? get submittedAt => _dateTime(submittedEpoch);
  DateTime? get gradedAt => _dateTime(gradedEpoch);

  factory CourseGradeItem.fromJson(Map<String, dynamic> json) {
    return CourseGradeItem(
      id: _toInt(json['id']),
      name: _string(json['itemname']),
      moduleType: _string(json['itemmodule']),
      courseModuleId: _toInt(json['cmid']),
      gradeFormatted: _string(json['gradeformatted']),
      rangeFormatted: _string(json['rangeformatted']),
      percentageFormatted: _string(json['percentageformatted']),
      feedbackHtml: _string(json['feedback']),
      hidden:
          _toBool(json['gradeishidden']) || _toBool(json['gradehiddenbydate']),
      locked: _toBool(json['gradeislocked']) || _toBool(json['locked']),
      submittedEpoch: _toInt(json['gradedatesubmitted']),
      gradedEpoch: _toInt(json['gradedategraded']),
    );
  }

  static DateTime? _dateTime(int epoch) {
    if (epoch <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';
}
