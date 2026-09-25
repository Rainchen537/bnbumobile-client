class PortalAccountProfile {
  const PortalAccountProfile({
    required this.fullName,
    required this.identity,
    required this.organization,
    required this.department,
    required this.avatarPath,
    this.college = '',
    this.chineseName = '',
    this.englishName = '',
    this.studentLevel = '',
    this.gender = '',
    this.residence = '',
    this.portalUserId,
  });

  factory PortalAccountProfile.fromPortalJson(Map<String, dynamic> json) {
    return PortalAccountProfile(
      fullName: _stringOf(json['username']),
      chineseName: _firstStringOf(json, const [
        'chineseName',
        'chinesename',
        'name_cn',
        'chinese_name',
        'xm',
      ]),
      englishName: _firstStringOf(json, const [
        'englishName',
        'englishname',
        'name_en',
        'english_name',
      ]),
      identity: _stringOf(json['jobs']),
      organization: _stringOf(json['subcompanyname']),
      department: _stringOf(json['deptname']),
      avatarPath: _stringOf(json['icon']),
      college: _firstStringOf(json, const [
        'college',
        'collegename',
        'collegeName',
        'faculty',
        'facultyname',
        'facultyName',
        'school',
        'schoolname',
        'schoolName',
        'xy',
        'xymc',
      ]),
      studentLevel: _firstStringOf(json, const [
        'studentlevel',
        'studentLevel',
        'studenttype',
        'studentType',
        'studentcategory',
        'studentCategory',
        'educationlevel',
        'educationLevel',
        'pycc',
        'xslb',
      ]),
      gender: _firstStringOf(json, const ['sex', 'gender']),
      residence: _firstStringOf(json, const ['dormitory', 'dorm']),
      portalUserId: _intOf(json['userid']),
    );
  }

  PortalAccountProfile mergeResourceCardJson(Map<String, dynamic> json) {
    final resourceCollege = _resourceFieldValue(
      json,
      fieldNames: const <String>{
        'college',
        'collegename',
        'faculty',
        'facultyname',
        'school',
        'schoolname',
        'academy',
        'academyname',
        'xy',
        'xymc',
        'ssxy',
        'ssxymc',
      },
      fieldLabels: const <String>{
        '学院',
        '所属学院',
        '所在学院',
        '学部',
        'Faculty',
        'College',
        'School',
      },
    );
    final resourceGender = _resourceFieldValue(
      json,
      fieldNames: const <String>{
        'sex',
        'sexname',
        'gender',
        'gendername',
        'xb',
        'xbmc',
      },
      fieldLabels: const <String>{'性别'},
    );
    final resourceStudentLevel = _resourceFieldValue(
      json,
      fieldNames: const <String>{
        'studentlevel',
        'studenttype',
        'studentcategory',
        'educationlevel',
        'programmelevel',
        'degreelevel',
        'pycc',
        'xslb',
        'xslx',
      },
      fieldLabels: const <String>{
        '学生层次',
        '学生类别',
        '学生类型',
        '培养层次',
        '学历层次',
        'Student Level',
        'Student Type',
        'Student Category',
        'Programme Level',
      },
    );
    final resourceChineseName = _resourceFieldValue(
      json,
      fieldNames: const {
        'chinesename',
        'namecn',
        'chinesefullname',
        'xm',
        'lastname',
      },
      fieldLabels: const {'中文姓名', '中文名', '姓名', 'Chinese Name'},
    );
    final resourceEnglishName = _resourceFieldValue(
      json,
      fieldNames: const {'englishname', 'nameen', 'englishfullname'},
      fieldLabels: const {'英文姓名', '英文名', 'English Name'},
    );
    return PortalAccountProfile(
      fullName: fullName,
      chineseName: resourceChineseName.isNotEmpty
          ? resourceChineseName
          : chineseName,
      englishName: resourceEnglishName.isNotEmpty
          ? resourceEnglishName
          : englishName,
      identity: identity,
      organization: organization,
      department: department,
      avatarPath: avatarPath,
      college: resourceCollege.isNotEmpty ? resourceCollege : college,
      studentLevel: resourceStudentLevel.isNotEmpty
          ? resourceStudentLevel
          : studentLevel,
      gender: resourceGender.isNotEmpty ? resourceGender : gender,
      residence: residence,
      portalUserId: portalUserId,
    );
  }

  final String fullName;
  final String chineseName;
  final String englishName;
  final String identity;
  final String organization;
  final String department;
  final String avatarPath;
  final String college;
  final String studentLevel;
  final String gender;
  final String residence;
  final int? portalUserId;

  String get majorName => department.trim();

  bool get isEmpty =>
      fullName.isEmpty &&
      identity.isEmpty &&
      organization.isEmpty &&
      department.isEmpty &&
      college.isEmpty &&
      studentLevel.isEmpty &&
      gender.isEmpty &&
      residence.isEmpty;

  static String _firstStringOf(
    Map<String, dynamic> json,
    Iterable<String> keys,
  ) {
    for (final key in keys) {
      final value = _stringOf(json[key]);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static String _stringOf(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  static int? _intOf(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static String _resourceFieldValue(
    dynamic node, {
    required Set<String> fieldNames,
    required Set<String> fieldLabels,
  }) {
    if (node is List) {
      for (final value in node) {
        final found = _resourceFieldValue(
          value,
          fieldNames: fieldNames,
          fieldLabels: fieldLabels,
        );
        if (found.isNotEmpty) return found;
      }
      return '';
    }
    if (node is! Map) return '';

    final map = Map<dynamic, dynamic>.from(node);
    for (final entry in map.entries) {
      if (fieldNames.contains(_normalizedFieldName(entry.key))) {
        final found = _resourceDisplayValue(entry.value);
        if (found.isNotEmpty) return found;
      }
    }

    final identifiers = <dynamic>[
      map['name'],
      map['fieldname'],
      map['fieldName'],
      map['domkey'],
      map['domKey'],
      map['id'],
    ];
    final labels = <dynamic>[
      map['label'],
      map['title'],
      map['fieldlabel'],
      map['fieldLabel'],
    ];
    final isTargetField = identifiers.any(
      (value) => _fieldIdentifierMatches(value, fieldNames),
    );
    final isTargetLabel = labels.any(
      (value) => fieldLabels.contains(_stringOf(value)),
    );
    if (isTargetField || isTargetLabel) {
      for (final key in const <String>[
        'displayValue',
        'displayvalue',
        'showName',
        'showname',
        'valueSpan',
        'valuespan',
        'text',
        'value',
      ]) {
        final found = _resourceDisplayValue(map[key]);
        if (found.isNotEmpty) return found;
      }
    }

    for (final value in map.values) {
      final found = _resourceFieldValue(
        value,
        fieldNames: fieldNames,
        fieldLabels: fieldLabels,
      );
      if (found.isNotEmpty) return found;
    }
    return '';
  }

  static bool _fieldIdentifierMatches(dynamic value, Set<String> fieldNames) {
    if (value is List) {
      return value.any((item) => _fieldIdentifierMatches(item, fieldNames));
    }
    return fieldNames.contains(_normalizedFieldName(value));
  }

  static String _normalizedFieldName(dynamic value) {
    return _stringOf(
      value,
    ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
  }

  static String _resourceDisplayValue(dynamic value) {
    if (value is String || value is num) {
      return value.toString().trim();
    }
    if (value is Map) {
      for (final key in const <String>[
        'displayValue',
        'displayvalue',
        'showName',
        'showname',
        'text',
        'label',
        'name',
        'value',
      ]) {
        final found = _resourceDisplayValue(value[key]);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }
}
