const teacherReviewConsentVersion = 'teacher-reviews.2026-08-24';

class TeacherReviewCourseEvidence {
  const TeacherReviewCourseEvidence({
    required this.courseCode,
    required this.courseName,
    required this.semesterId,
    required this.semesterName,
  });

  factory TeacherReviewCourseEvidence.fromJson(Map<String, dynamic> json) {
    return TeacherReviewCourseEvidence(
      courseCode: _string(json['course_code']),
      courseName: _string(json['course_name']),
      semesterId: _string(json['semester_id']),
      semesterName: _string(json['semester_name']),
    );
  }

  final String courseCode;
  final String courseName;
  final String semesterId;
  final String semesterName;

  Map<String, Object?> toJson() => {
    'course_code': courseCode,
    'course_name': courseName,
    'semester_id': semesterId,
    'semester_name': semesterName,
  };

  String get displayLabel => [
    courseCode,
    courseName,
    semesterName,
  ].where((item) => item.isNotEmpty).join(' · ');
}

enum TeacherStyleDimension {
  requirements('课堂要求', ['灵活自主', '两者兼有', '规范细致']),
  rapport('交流风格', ['沉稳克制', '两者兼有', '热情亲和']),
  teaching('授课方式', ['系统讲授', '讲授与讨论', '互动讨论']),
  pace('课程节奏', ['循序渐进', '节奏适中', '紧凑推进']),
  workload('作业投入', ['较少', '适中', '较多']);

  const TeacherStyleDimension(this.label, this.choices);
  final String label;
  final List<String> choices;
  String choice(int value) =>
      value >= 1 && value <= 3 ? choices[value - 1] : '未选择';
}

enum TeacherReviewModerationStatus { visible, hidden }

class TeacherReviewEntry {
  const TeacherReviewEntry({
    required this.id,
    this.reviewFormat = 'stars_v1',
    this.styleDimensions = const {},
    required this.teacherKey,
    required this.teacherName,
    required this.teacherNameEn,
    required this.overallRating,
    required this.teachingEngagement,
    required this.gradingGenerosity,
    required this.attendanceFrequency,
    required this.feedbackQuality,
    required this.courseWorkload,
    required this.comment,
    required this.courseLinked,
    required this.courseEvidence,
    required this.moderationStatus,
    required this.hiddenReason,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TeacherReviewEntry.fromJson(Map<String, dynamic> json) {
    return TeacherReviewEntry(
      id: _string(json['id']),
      reviewFormat: _string(json['review_format']),
      styleDimensions: _styles(json['style_dimensions']),
      teacherKey: _string(json['teacher_key']),
      teacherName: _string(json['teacher_name']),
      teacherNameEn: _string(json['teacher_name_en']),
      overallRating: _integer(json['overall_rating']),
      teachingEngagement: _integer(json['teaching_engagement']),
      gradingGenerosity: _integer(json['grading_generosity']),
      attendanceFrequency: _integer(json['attendance_frequency']),
      feedbackQuality: _nullableInteger(json['feedback_quality']),
      courseWorkload: _nullableInteger(json['course_workload']),
      comment: _string(json['comment']),
      courseLinked: json['course_linked'] == true,
      courseEvidence: _objects(
        json['course_evidence'],
        TeacherReviewCourseEvidence.fromJson,
      ),
      moderationStatus: _string(json['moderation_status']) == 'hidden'
          ? TeacherReviewModerationStatus.hidden
          : TeacherReviewModerationStatus.visible,
      hiddenReason: _string(json['hidden_reason']),
      version: _integer(json['version']),
      createdAt: _dateTime(json['created_at']),
      updatedAt: _dateTime(json['updated_at']),
    );
  }

  final String reviewFormat;
  final Map<String, int> styleDimensions;
  final String id;
  final String teacherKey;
  final String teacherName;
  final String teacherNameEn;
  final int overallRating;
  final int teachingEngagement;
  final int gradingGenerosity;
  final int attendanceFrequency;
  final int? feedbackQuality;
  final int? courseWorkload;
  final String comment;
  final bool courseLinked;
  final List<TeacherReviewCourseEvidence> courseEvidence;
  final TeacherReviewModerationStatus moderationStatus;
  final String hiddenReason;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TeacherReviewSummary {
  const TeacherReviewSummary({
    required this.count,
    required this.courseLinkedCount,
    required this.overallAverage,
    required this.teachingEngagementAverage,
    required this.gradingGenerosityAverage,
    required this.attendanceFrequencyAverage,
    required this.feedbackQualityAverage,
    required this.courseWorkloadAverage,
    this.styleCount = 0,
    this.styleDistribution = const {},
    this.overallRatingCounts = const [0, 0, 0, 0, 0],
  });

  factory TeacherReviewSummary.fromJson(Map<String, dynamic> json) {
    return TeacherReviewSummary(
      styleCount: _integer(json['style_count']),
      styleDistribution: _styleDistribution(json['style_distribution']),
      count: _integer(json['count']),
      courseLinkedCount: _integer(json['course_linked_count']),
      overallAverage: _nullableDouble(json['overall_average']),
      teachingEngagementAverage: _nullableDouble(
        json['teaching_engagement_average'],
      ),
      gradingGenerosityAverage: _nullableDouble(
        json['grading_generosity_average'],
      ),
      attendanceFrequencyAverage: _nullableDouble(
        json['attendance_frequency_average'],
      ),
      feedbackQualityAverage: _nullableDouble(json['feedback_quality_average']),
      courseWorkloadAverage: _nullableDouble(json['course_workload_average']),
      overallRatingCounts: _ratingCounts(json['overall_rating_counts']),
    );
  }

  final int styleCount;
  final Map<String, List<int>> styleDistribution;
  final int count;
  final int courseLinkedCount;
  final double? overallAverage;
  final double? teachingEngagementAverage;
  final double? gradingGenerosityAverage;
  final double? attendanceFrequencyAverage;
  final double? feedbackQualityAverage;
  final double? courseWorkloadAverage;
  final List<int> overallRatingCounts;
}

class TeacherReviewPageData {
  const TeacherReviewPageData({
    required this.summary,
    required this.total,
    required this.offset,
    required this.limit,
    required this.items,
  });

  factory TeacherReviewPageData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    return TeacherReviewPageData(
      summary: TeacherReviewSummary.fromJson(
        summary is Map ? summary.cast<String, dynamic>() : const {},
      ),
      total: _integer(json['total']),
      offset: _integer(json['offset']),
      limit: _integer(json['limit']),
      items: _objects(json['items'], TeacherReviewEntry.fromJson),
    );
  }

  final TeacherReviewSummary summary;
  final int total;
  final int offset;
  final int limit;
  final List<TeacherReviewEntry> items;
}

class TeacherReviewMineState {
  const TeacherReviewMineState({
    required this.review,
    required this.suspendedUntil,
    required this.canReview,
  });

  factory TeacherReviewMineState.fromJson(Map<String, dynamic> json) {
    final review = json['review'];
    return TeacherReviewMineState(
      review: review is Map
          ? TeacherReviewEntry.fromJson(review.cast<String, dynamic>())
          : null,
      suspendedUntil: _nullableDateTime(json['suspended_until']),
      canReview: json['can_review'] == true,
    );
  }

  final TeacherReviewEntry? review;
  final DateTime? suspendedUntil;
  final bool canReview;
}

class TeacherReviewDraft {
  const TeacherReviewDraft({
    required this.expectedVersion,
    this.styleDimensions,
    this.overallRating = 0,
    this.teachingEngagement = 0,
    this.gradingGenerosity = 0,
    this.attendanceFrequency = 0,
    this.courseWorkload,
    required this.comment,
    required this.courseEvidence,
  });

  final Map<String, int>? styleDimensions;
  final int expectedVersion;
  final int overallRating;
  final int teachingEngagement;
  final int gradingGenerosity;
  final int attendanceFrequency;
  final int? courseWorkload;
  final String comment;
  final List<TeacherReviewCourseEvidence> courseEvidence;

  Map<String, Object?> toJson() => {
    'consent_version': teacherReviewConsentVersion,
    'expected_version': expectedVersion,
    if (styleDimensions != null) ...{
      'review_format': 'style_v1',
      'style_dimensions': styleDimensions,
    } else ...{
      'overall_rating': overallRating,
      'teaching_engagement': teachingEngagement,
      'grading_generosity': gradingGenerosity,
      'attendance_frequency': attendanceFrequency,
      'course_workload': courseWorkload,
    },
    'comment': comment,
    'course_evidence': courseEvidence.map((item) => item.toJson()).toList(),
  };
}

String _string(Object? value) => value is String ? value.trim() : '';

int _integer(Object? value) => value is num ? value.toInt() : 0;

int? _nullableInteger(Object? value) => value is num ? value.toInt() : null;

double? _nullableDouble(Object? value) =>
    value is num ? value.toDouble() : null;

DateTime _dateTime(Object? value) =>
    DateTime.tryParse(_string(value)) ?? DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _nullableDateTime(Object? value) => DateTime.tryParse(_string(value));

List<T> _objects<T>(
  Object? value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => fromJson(item.cast<String, dynamic>()))
      .toList(growable: false);
}

List<int> _ratingCounts(Object? value) {
  if (value is! List || value.length != 5) {
    return const [0, 0, 0, 0, 0];
  }
  return List<int>.unmodifiable(
    value.map(
      (item) => item is num ? item.toInt().clamp(0, 1 << 31).toInt() : 0,
    ),
  );
}

Map<String, int> _styles(Object? value) {
  if (value is! Map) return const {};
  return Map.unmodifiable({
    for (final dimension in TeacherStyleDimension.values)
      if (value[dimension.name] is int &&
          (value[dimension.name] as int) >= 1 &&
          (value[dimension.name] as int) <= 3)
        dimension.name: value[dimension.name] as int,
  });
}

Map<String, List<int>> _styleDistribution(Object? value) {
  if (value is! Map) return const {};
  return Map.unmodifiable({
    for (final dimension in TeacherStyleDimension.values)
      if (value[dimension.name] is List &&
          (value[dimension.name] as List).length == 3)
        dimension.name: List<int>.unmodifiable(
          (value[dimension.name] as List).map(
            (v) => v is int && v >= 0 ? v : 0,
          ),
        ),
  });
}
