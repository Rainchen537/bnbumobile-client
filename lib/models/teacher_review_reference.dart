import 'teacher_review.dart';

enum TeacherReviewReferenceScope { teacher, course }

class TeacherReviewReference {
  const TeacherReviewReference({
    required this.id,
    required this.scope,
    required this.teacherKeys,
    required this.courseCodes,
    required this.courseNames,
    required this.sourceLabel,
    required this.sourceUrl,
    required this.summary,
    required this.highlights,
    required this.curatedAt,
  });

  factory TeacherReviewReference.fromJson(Map<String, dynamic> json) {
    final scope = switch (_string(json['scope'])) {
      'teacher' => TeacherReviewReferenceScope.teacher,
      'course' => TeacherReviewReferenceScope.course,
      _ => throw const FormatException('选课参考范围无效。'),
    };
    final reference = TeacherReviewReference(
      id: _string(json['id']),
      scope: scope,
      teacherKeys: _strings(json['teacher_keys']),
      courseCodes: _strings(json['course_codes']),
      courseNames: _strings(json['course_names']),
      sourceLabel: _string(json['source_label']),
      sourceUrl: _string(json['source_url']),
      summary: _string(json['summary']),
      highlights: _strings(json['highlights']),
      curatedAt: DateTime.tryParse(_string(json['curated_at'])),
    );
    reference._validate();
    return reference;
  }

  final String id;
  final TeacherReviewReferenceScope scope;
  final List<String> teacherKeys;
  final List<String> courseCodes;
  final List<String> courseNames;
  final String sourceLabel;
  final String sourceUrl;
  final String summary;
  final List<String> highlights;
  final DateTime? curatedAt;

  bool matchesTeacher(String teacherKey) =>
      teacherKeys.contains(teacherKey.trim());

  bool matchesCourseEvidence(Iterable<TeacherReviewCourseEvidence> evidence) {
    final normalizedCodes = courseCodes
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final normalizedNames = courseNames
        .map(_normalizeCourseName)
        .where((value) => value.isNotEmpty)
        .toSet();
    return evidence.any((course) {
      final code = course.courseCode.trim().toUpperCase();
      if (code.isNotEmpty && normalizedCodes.contains(code)) return true;
      return normalizedNames.contains(_normalizeCourseName(course.courseName));
    });
  }

  void _validate() {
    if (id.isEmpty ||
        sourceLabel.isEmpty ||
        summary.isEmpty ||
        courseNames.isEmpty) {
      throw const FormatException('选课参考缺少必要字段。');
    }
    if (scope == TeacherReviewReferenceScope.teacher && teacherKeys.isEmpty) {
      throw const FormatException('教师选课参考缺少正式教师标识。');
    }
    if (scope == TeacherReviewReferenceScope.course && teacherKeys.isNotEmpty) {
      throw const FormatException('课程选课参考不能绑定未经核对的教师。');
    }
  }
}

String _string(Object? value) => value is String ? value.trim() : '';

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return List<String>.unmodifiable(
    value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty),
  );
}

String _normalizeCourseName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff]+'), '');
