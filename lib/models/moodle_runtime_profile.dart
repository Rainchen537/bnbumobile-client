enum MoodleNormalizedCapability {
  courseCatalogRead,
  moduleMetadataRead,
  fileDownload,
  fileUpload,
  completionRead,
  completionManualWrite,
  gradesRead,
  assignmentRead,
  assignmentDraftWrite,
  assignmentFinalize,
  quizRead,
  quizStart,
  quizSave,
  quizFinish,
  quizReview,
  forumRead,
  forumWrite,
  choiceRead,
  choiceWrite,
  feedbackRead,
  feedbackWrite,
  lessonRead,
  lessonWrite,
}

class MoodleRuntimeProfile {
  MoodleRuntimeProfile({
    required this.release,
    required this.version,
    required Map<String, String> functionVersions,
    required this.downloadFiles,
    required this.uploadFiles,
    required Map<String, int> advancedFeatures,
    required this.userMaxUploadFileSize,
  }) : functionVersions = Map.unmodifiable(functionVersions),
       advancedFeatures = Map.unmodifiable(advancedFeatures);

  final String release;
  final String version;
  final Map<String, String> functionVersions;
  final bool downloadFiles;
  final bool uploadFiles;
  final Map<String, int> advancedFeatures;
  final int userMaxUploadFileSize;

  factory MoodleRuntimeProfile.fromSiteInfo(Map<String, dynamic> json) {
    final functions = <String, String>{};
    final rawFunctions = json['functions'];
    if (rawFunctions is List) {
      for (final raw in rawFunctions.whereType<Map>()) {
        final name = raw['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        functions[name] = raw['version']?.toString().trim() ?? '';
      }
    }

    final features = <String, int>{};
    final rawFeatures = json['advancedfeatures'];
    if (rawFeatures is List) {
      for (final raw in rawFeatures.whereType<Map>()) {
        final name = raw['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        features[name] = _toInt(raw['value']);
      }
    }

    return MoodleRuntimeProfile(
      release: json['release']?.toString().trim() ?? '',
      version: json['version']?.toString().trim() ?? '',
      functionVersions: functions,
      downloadFiles: _toBool(json['downloadfiles']),
      uploadFiles: _toBool(json['uploadfiles']),
      advancedFeatures: features,
      userMaxUploadFileSize: _toInt(json['usermaxuploadfilesize']),
    );
  }

  bool supportsFunction(String functionName) =>
      functionVersions.containsKey(functionName);

  bool supportsFunctions(Iterable<String> functionNames) =>
      functionNames.every(supportsFunction);

  bool advancedFeatureEnabled(String name) =>
      (advancedFeatures[name] ?? 0) != 0;

  bool supports(MoodleNormalizedCapability capability) {
    return switch (capability) {
      MoodleNormalizedCapability.courseCatalogRead => supportsFunctions(const [
        'core_enrol_get_users_courses',
        'core_course_get_contents',
      ]),
      MoodleNormalizedCapability.moduleMetadataRead =>
        supportsFunction('core_course_get_course_module') ||
            supportsFunction('core_course_get_course_module_by_instance'),
      MoodleNormalizedCapability.fileDownload =>
        downloadFiles &&
            supportsFunction('core_course_get_contents') &&
            supportsFunction('core_files_get_files'),
      MoodleNormalizedCapability.fileUpload =>
        uploadFiles && supportsFunction('core_files_get_unused_draft_itemid'),
      MoodleNormalizedCapability.completionRead =>
        advancedFeatureEnabled('enablecompletion') &&
            supportsFunction(
              'core_completion_get_activities_completion_status',
            ),
      MoodleNormalizedCapability.completionManualWrite =>
        supports(MoodleNormalizedCapability.completionRead) &&
            supportsFunction(
              'core_completion_update_activity_completion_status_manually',
            ),
      MoodleNormalizedCapability.gradesRead => supportsFunction(
        'gradereport_user_get_grade_items',
      ),
      MoodleNormalizedCapability.assignmentRead => supportsFunctions(const [
        'mod_assign_get_assignments',
        'mod_assign_get_submission_status',
      ]),
      MoodleNormalizedCapability.assignmentDraftWrite =>
        supports(MoodleNormalizedCapability.assignmentRead) &&
            supportsFunction('mod_assign_save_submission'),
      MoodleNormalizedCapability.assignmentFinalize =>
        supports(MoodleNormalizedCapability.assignmentDraftWrite) &&
            supportsFunction('mod_assign_submit_for_grading'),
      MoodleNormalizedCapability.quizRead => supportsFunctions(const [
        'mod_quiz_get_user_attempts',
        'mod_quiz_get_quiz_access_information',
        'mod_quiz_get_attempt_access_information',
        'mod_quiz_get_attempt_data',
      ]),
      MoodleNormalizedCapability.quizStart =>
        supports(MoodleNormalizedCapability.quizRead) &&
            supportsFunction('mod_quiz_start_attempt'),
      MoodleNormalizedCapability.quizSave =>
        supports(MoodleNormalizedCapability.quizRead) &&
            supportsFunction('mod_quiz_save_attempt'),
      MoodleNormalizedCapability.quizFinish =>
        supports(MoodleNormalizedCapability.quizRead) &&
            supportsFunction('mod_quiz_process_attempt'),
      MoodleNormalizedCapability.quizReview => supportsFunctions(const [
        'mod_quiz_get_attempt_review',
        'mod_quiz_get_combined_review_options',
      ]),
      MoodleNormalizedCapability.forumRead =>
        supportsFunctions(const [
              'mod_forum_get_forum_access_information',
              'mod_forum_get_discussion_posts',
            ]) &&
            (supportsFunction('mod_forum_get_forum_discussions_paginated') ||
                supportsFunction('mod_forum_get_forum_discussions')),
      MoodleNormalizedCapability.forumWrite =>
        supports(MoodleNormalizedCapability.forumRead) &&
            supportsFunctions(const [
              'mod_forum_add_discussion',
              'mod_forum_add_discussion_post',
            ]),
      MoodleNormalizedCapability.choiceRead => supportsFunctions(const [
        'mod_choice_get_choices_by_courses',
        'mod_choice_get_choice_options',
      ]),
      MoodleNormalizedCapability.choiceWrite =>
        supports(MoodleNormalizedCapability.choiceRead) &&
            supportsFunction('mod_choice_submit_choice_response'),
      MoodleNormalizedCapability.feedbackRead => supportsFunction(
        'mod_feedback_get_feedback_access_information',
      ),
      MoodleNormalizedCapability.feedbackWrite =>
        supports(MoodleNormalizedCapability.feedbackRead) &&
            supportsFunctions(const [
              'mod_feedback_launch_feedback',
              'mod_feedback_process_page',
            ]),
      MoodleNormalizedCapability.lessonRead => supportsFunction(
        'mod_lesson_get_lesson_access_information',
      ),
      MoodleNormalizedCapability.lessonWrite =>
        supports(MoodleNormalizedCapability.lessonRead) &&
            supportsFunctions(const [
              'mod_lesson_launch_attempt',
              'mod_lesson_process_page',
              'mod_lesson_finish_attempt',
            ]),
    };
  }

  Set<MoodleNormalizedCapability> get normalizedCapabilities =>
      Set.unmodifiable(MoodleNormalizedCapability.values.where(supports));

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is bool) return value ? 1 : 0;
    return 0;
  }

  static bool _toBool(dynamic value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes') return true;
      if (normalized == 'false' || normalized == 'no') return false;
    }
    return _toInt(value) != 0;
  }
}
