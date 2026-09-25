class CourseContentSection {
  CourseContentSection({
    required this.id,
    required this.sectionNum,
    required this.name,
    required this.summary,
    required this.modules,
    this.visible = true,
    this.userVisible = true,
  });

  final int id;
  final int sectionNum;
  final String name;
  final String summary;
  final List<CourseModule> modules;
  final bool visible;
  final bool userVisible;

  factory CourseContentSection.fromJson(Map<String, dynamic> json) {
    final modulesRaw = json['modules'];
    final modules = modulesRaw is List
        ? modulesRaw
              .whereType<Map>()
              .map(
                (item) => CourseModule.fromJson(item.cast<String, dynamic>()),
              )
              .toList()
        : const <CourseModule>[];

    return CourseContentSection(
      id: _toInt(json['id']),
      sectionNum: _toInt(json['section']),
      name: _pickString(json, const ['name'], '未命名章节'),
      summary: _pickString(json, const ['summary']),
      modules: modules,
      visible: _toBool(json['visible'], fallback: true),
      userVisible: _toBool(json['uservisible'], fallback: false),
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

  static bool _toBool(dynamic value, {required bool fallback}) {
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

class CourseModule {
  CourseModule({
    required this.id,
    required this.instance,
    required this.name,
    required this.modName,
    required this.url,
    required this.iconUrl,
    required this.descriptionHtml,
    required this.contents,
    required this.dates,
    this.visible = true,
    this.userVisible = true,
    this.availabilityInfo = '',
    this.completionTracking = 0,
    this.completionData,
    this.downloadContent = false,
  });

  final int id;
  final int instance;
  final String name;
  final String modName;
  final String url;
  final String iconUrl;
  final String descriptionHtml;
  final List<CourseModuleContent> contents;
  final List<CourseModuleDate> dates;
  final bool visible;
  final bool userVisible;
  final String availabilityInfo;
  final int completionTracking;
  final CourseModuleCompletionData? completionData;
  final bool downloadContent;

  bool get isAssignment => modName.toLowerCase().contains('assign');

  factory CourseModule.fromJson(Map<String, dynamic> json) {
    final contentsRaw = json['contents'];
    final contents = contentsRaw is List
        ? contentsRaw
              .whereType<Map>()
              .map(
                (item) =>
                    CourseModuleContent.fromJson(item.cast<String, dynamic>()),
              )
              .toList()
        : const <CourseModuleContent>[];

    final datesRaw = json['dates'];
    final dates = datesRaw is List
        ? datesRaw
              .whereType<Map>()
              .map(
                (item) =>
                    CourseModuleDate.fromJson(item.cast<String, dynamic>()),
              )
              .toList()
        : const <CourseModuleDate>[];

    return CourseModule(
      id: _toInt(json['id']),
      instance: _toInt(json['instance']),
      name: _pickString(json, const ['name'], '未命名活动'),
      modName: _pickString(json, const ['modname']),
      url: _pickString(json, const ['url']),
      iconUrl: _pickString(json, const ['modicon']),
      descriptionHtml: _pickString(json, const ['description']),
      contents: contents,
      dates: dates,
      visible: _toBool(json['visible'], fallback: true),
      userVisible: _toBool(json['uservisible'], fallback: false),
      availabilityInfo: _pickString(json, const ['availabilityinfo']),
      completionTracking: _toInt(json['completion']),
      completionData: json['completiondata'] is Map
          ? CourseModuleCompletionData.fromJson(
              (json['completiondata'] as Map).cast<String, dynamic>(),
            )
          : null,
      downloadContent: _toBool(json['downloadcontent'], fallback: false),
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

  static bool _toBool(dynamic value, {required bool fallback}) {
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

class CourseModuleCompletionData {
  const CourseModuleCompletionData({
    required this.state,
    required this.timeCompletedEpoch,
    required this.overrideBy,
    required this.valueUsed,
    required this.hasCompletion,
    required this.isAutomatic,
    required this.isTrackedUser,
    required this.userVisible,
  });

  final int state;
  final int timeCompletedEpoch;
  final int overrideBy;
  final bool valueUsed;
  final bool hasCompletion;
  final bool isAutomatic;
  final bool isTrackedUser;
  final bool userVisible;

  DateTime? get timeCompletedAt {
    if (timeCompletedEpoch <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      timeCompletedEpoch * 1000,
      isUtc: true,
    );
  }

  factory CourseModuleCompletionData.fromJson(Map<String, dynamic> json) {
    return CourseModuleCompletionData(
      state: _toInt(json['state']),
      timeCompletedEpoch: _toInt(json['timecompleted']),
      overrideBy: _toInt(json['overrideby']),
      valueUsed: _toBool(json['valueused']),
      hasCompletion: _toBool(json['hascompletion']),
      isAutomatic: _toBool(json['isautomatic']),
      isTrackedUser: _toBool(json['istrackeduser']),
      userVisible: _toBool(json['uservisible'], fallback: false),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
}

class CourseModuleContent {
  CourseModuleContent({
    required this.type,
    required this.fileName,
    required this.filePath,
    required this.fileUrl,
    required this.fileSize,
    required this.mimeType,
    required this.timeModifiedEpoch,
    required this.sortOrder,
    required this.author,
    required this.license,
  });

  final String type;
  final String fileName;
  final String filePath;
  final String fileUrl;
  final int fileSize;
  final String mimeType;
  final int timeModifiedEpoch;
  final int sortOrder;
  final String author;
  final String license;

  DateTime? get timeModifiedAt {
    if (timeModifiedEpoch <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      timeModifiedEpoch * 1000,
      isUtc: true,
    );
  }

  factory CourseModuleContent.fromJson(Map<String, dynamic> json) {
    return CourseModuleContent(
      type: _pickString(json, const ['type']),
      fileName: _pickString(json, const ['filename', 'name'], '未命名文件'),
      filePath: _pickString(json, const ['filepath']),
      fileUrl: _pickString(json, const ['fileurl', 'url']),
      fileSize: _toInt(json['filesize'] ?? json['size']),
      mimeType: _pickString(json, const ['mimetype']),
      timeModifiedEpoch: _toInt(json['timemodified'] ?? json['datemodified']),
      sortOrder: _toInt(json['sortorder']),
      author: _pickString(json, const ['author']),
      license: _pickString(json, const ['license']),
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

class CourseModuleDate {
  CourseModuleDate({
    required this.label,
    required this.timestamp,
    required this.dataId,
  });

  final String label;
  final int timestamp;
  final String dataId;

  DateTime? get dateTime {
    if (timestamp <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
  }

  factory CourseModuleDate.fromJson(Map<String, dynamic> json) {
    return CourseModuleDate(
      label: _pickString(json, const ['label']),
      timestamp: _toInt(json['timestamp']),
      dataId: _pickString(json, const ['dataid']),
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
