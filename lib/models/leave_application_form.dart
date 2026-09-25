/// Device-memory-only school form values. Never persist or send to BNBU.ME/AI.
class LeaveApplicationField {
  const LeaveApplicationField({
    this.value = '',
    this.display = '',
    this.editable = false,
    this.required = false,
    this.maxLength = 4000,
  });
  final String value;
  final String display;
  final bool editable;
  final bool required;
  final int maxLength;

  factory LeaveApplicationField.fromJson(Map<String, dynamic> json) =>
      LeaveApplicationField(
        value: json['value'] as String? ?? '',
        display: json['display'] as String? ?? '',
        editable: json['editable'] == true,
        required: json['required'] == true,
        maxLength: (json['maxLength'] as num? ?? 4000).toInt().clamp(1, 4000),
      );
}

class LeaveApplicationOption {
  const LeaveApplicationOption(this.value, this.label);
  final String value;
  final String label;
}

class LeaveApplicationForm {
  const LeaveApplicationForm({
    required this.fields,
    this.reasons = const [],
    this.courses = const [],
    this.attachmentSummary = '',
    this.completion = const LeaveFormCompletion(),
  });
  final Map<String, LeaveApplicationField> fields;
  final List<LeaveApplicationOption> reasons;
  final List<Map<String, String>> courses;
  final String attachmentSummary;
  final LeaveFormCompletion completion;

  LeaveApplicationField field(String key) =>
      fields[key] ?? const LeaveApplicationField();

  /// Use the school's current requirements and the still-local draft. This
  /// check does not write partially completed fields or accept declarations.
  List<String> missingRequired([Map<String, String> draft = const {}]) {
    const labels = {
      'mobile': '手机号码',
      'familyPhone': '家人联系电话',
      'beginDate': '开始日期',
      'beginTime': '开始时间',
      'endDate': '结束日期',
      'endTime': '结束时间',
      'reason': '请假类型',
      'details': '请假原因（英文）',
    };
    return [
      for (final entry in labels.entries)
        if (field(entry.key).required &&
            (draft[entry.key] ?? field(entry.key).value).trim().isEmpty)
          entry.value,
      if (completion.missingCourses) '涉及课程与教师',
      if (completion.attachmentRequired &&
          (!completion.filesKnown || completion.files.isEmpty))
        '证明材料',
    ];
  }

  factory LeaveApplicationForm.fromJson(Map<String, dynamic> json) =>
      LeaveApplicationForm(
        fields: Map.unmodifiable(
          (json['fields'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
              key,
              LeaveApplicationField.fromJson(value as Map<String, dynamic>),
            ),
          ),
        ),
        reasons: List.unmodifiable(
          (json['reasons'] as List).map(
            (o) => LeaveApplicationOption(
              o['value'] as String,
              o['label'] as String,
            ),
          ),
        ),
        courses: List.unmodifiable(
          (json['courses'] as List).map(
            (row) => Map<String, String>.unmodifiable(
              Map<String, String>.from(row as Map),
            ),
          ),
        ),
        attachmentSummary: json['attachmentSummary'] as String? ?? '',
        completion: LeaveFormCompletion.fromJson(
          json['completion'] as Map<String, dynamic>? ?? const {},
        ),
      );
}

/// Only display data and short-lived handles, never school upload URLs/tokens.
class LeaveFormCompletion {
  const LeaveFormCompletion({
    this.token = '',
    this.notices = const [],
    this.declaration = '',
    this.acknowledgement = '',
    this.canSubmit = false,
    this.canUpload = false,
    this.attachmentRequired = false,
    this.filesKnown = false,
    this.coursesRequired = false,
    this.missingCourses = false,
    this.maxBytes = 0,
    this.files = const [],
  });
  final String token, declaration, acknowledgement;
  final List<String> notices;
  final bool canSubmit, canUpload;
  final bool attachmentRequired, filesKnown, coursesRequired, missingCourses;
  final int maxBytes;
  final List<LeaveSchoolAttachment> files;

  factory LeaveFormCompletion.fromJson(Map<String, dynamic> json) =>
      LeaveFormCompletion(
        token: json['token'] as String? ?? '',
        notices: List<String>.from(json['notices'] as List? ?? const []),
        declaration: json['declaration'] as String? ?? '',
        acknowledgement: json['acknowledgement'] as String? ?? '',
        canSubmit: json['canSubmit'] == true,
        canUpload: json['canUpload'] == true,
        attachmentRequired: json['attachmentRequired'] == true,
        filesKnown: json['filesKnown'] == true,
        coursesRequired: json['coursesRequired'] == true,
        missingCourses: json['missingCourses'] == true,
        maxBytes: (json['maxBytes'] as num? ?? 0).toInt(),
        files: [
          for (final file in json['files'] as List? ?? const [])
            LeaveSchoolAttachment(
              file['key'] as String,
              file['name'] as String,
            ),
        ],
      );
}

class LeaveSchoolAttachment {
  const LeaveSchoolAttachment(this.key, this.name);
  final String key, name;
}

/// Ephemeral handles scoped to one verified school dialog and page revision.
class LeaveCoursePickerSnapshot {
  LeaveCoursePickerSnapshot.fromJson(Map<String, dynamic> json)
    : token = json['token'] as String,
      rowIndex = json['rowIndex'] as String,
      page = json['page'] as String,
      hasPrevious = json['hasPrevious'] == true,
      hasNext = json['hasNext'] == true,
      candidates = List.unmodifiable(
        (json['candidates'] as List).map(
          (c) => Map<String, String>.unmodifiable(
            Map<String, String>.from(c as Map),
          ),
        ),
      );

  final String token, rowIndex, page;
  final bool hasPrevious, hasNext;
  final List<Map<String, String>> candidates;
}

class LeaveCourseChoice {
  const LeaveCourseChoice(this.snapshot, this.candidate);
  final LeaveCoursePickerSnapshot snapshot;
  final Map<String, String> candidate;
}
