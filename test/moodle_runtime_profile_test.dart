import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';

void main() {
  test('missing site-info fields fail closed', () {
    final profile = MoodleRuntimeProfile.fromSiteInfo(const {});

    expect(profile.release, isEmpty);
    expect(profile.version, isEmpty);
    expect(profile.functionVersions, isEmpty);
    expect(profile.downloadFiles, isFalse);
    expect(profile.uploadFiles, isFalse);
    expect(profile.normalizedCapabilities, isEmpty);
  });

  test('missing Moodle visibility fields fail closed', () {
    final course = CourseSummary.fromJson(const {
      'id': 42,
      'fullname': 'Course',
    });
    final section = CourseContentSection.fromJson(const {
      'id': 1,
      'section': 1,
      'name': 'Section',
    });
    final module = CourseModule.fromJson(const {
      'id': 2,
      'instance': 3,
      'name': 'Resource',
      'modname': 'resource',
    });

    expect(course.visible, isFalse);
    expect(section.userVisible, isFalse);
    expect(module.userVisible, isFalse);
  });

  test('parses only named functions and numeric feature flags', () {
    final profile = MoodleRuntimeProfile.fromSiteInfo({
      'release': '4.1.3+',
      'version': '2022112803.06',
      'downloadfiles': '1',
      'uploadfiles': true,
      'functions': const [
        {'name': 'core_course_get_contents', 'version': 'first'},
        {'name': '', 'version': 'ignored'},
        {'version': 'ignored'},
        {'name': 'core_course_get_contents', 'version': 'latest'},
      ],
      'advancedfeatures': const [
        {'name': 'enablecompletion', 'value': '1'},
        {'name': '', 'value': 1},
      ],
    });

    expect(profile.release, '4.1.3+');
    expect(profile.version, '2022112803.06');
    expect(profile.functionVersions, {'core_course_get_contents': 'latest'});
    expect(profile.downloadFiles, isTrue);
    expect(profile.uploadFiles, isTrue);
    expect(profile.advancedFeatureEnabled('enablecompletion'), isTrue);
    expect(
      () => profile.functionVersions['invented'] = 'value',
      throwsUnsupportedError,
    );
  });

  test('derives capabilities only when every required function is present', () {
    final profile = _profile(const {
      'core_enrol_get_users_courses',
      'core_course_get_contents',
      'core_course_get_course_module',
      'core_files_get_files',
      'core_files_get_unused_draft_itemid',
      'core_completion_get_activities_completion_status',
      'core_completion_update_activity_completion_status_manually',
      'gradereport_user_get_grade_items',
      'mod_assign_get_assignments',
      'mod_assign_get_submission_status',
      'mod_assign_save_submission',
      'mod_assign_submit_for_grading',
      'mod_quiz_get_user_attempts',
      'mod_quiz_get_quiz_access_information',
      'mod_quiz_get_attempt_access_information',
      'mod_quiz_get_attempt_data',
      'mod_quiz_start_attempt',
      'mod_quiz_save_attempt',
      'mod_quiz_process_attempt',
      'mod_quiz_get_attempt_review',
      'mod_quiz_get_combined_review_options',
      'mod_choice_get_choices_by_courses',
      'mod_choice_get_choice_options',
      'mod_choice_submit_choice_response',
    });

    expect(
      profile.supports(MoodleNormalizedCapability.courseCatalogRead),
      isTrue,
    );
    expect(
      profile.supports(MoodleNormalizedCapability.moduleMetadataRead),
      isTrue,
    );
    expect(profile.supports(MoodleNormalizedCapability.fileDownload), isTrue);
    expect(profile.supports(MoodleNormalizedCapability.fileUpload), isTrue);
    expect(profile.supports(MoodleNormalizedCapability.completionRead), isTrue);
    expect(
      profile.supports(MoodleNormalizedCapability.completionManualWrite),
      isTrue,
    );
    expect(profile.supports(MoodleNormalizedCapability.gradesRead), isTrue);
    expect(
      profile.supports(MoodleNormalizedCapability.assignmentFinalize),
      isTrue,
    );
    expect(profile.supports(MoodleNormalizedCapability.quizFinish), isTrue);
    expect(profile.supports(MoodleNormalizedCapability.quizReview), isTrue);
    expect(profile.supports(MoodleNormalizedCapability.choiceWrite), isTrue);
    expect(profile.supports(MoodleNormalizedCapability.forumRead), isFalse);
  });

  test('site switches remain mandatory even when functions exist', () {
    final disabled = _profile(
      const {
        'core_course_get_contents',
        'core_files_get_files',
        'core_files_get_unused_draft_itemid',
        'core_completion_get_activities_completion_status',
      },
      downloadFiles: false,
      uploadFiles: false,
      completionEnabled: false,
    );

    expect(disabled.supports(MoodleNormalizedCapability.fileDownload), isFalse);
    expect(disabled.supports(MoodleNormalizedCapability.fileUpload), isFalse);
    expect(
      disabled.supports(MoodleNormalizedCapability.completionRead),
      isFalse,
    );
  });
}

MoodleRuntimeProfile _profile(
  Set<String> functions, {
  bool downloadFiles = true,
  bool uploadFiles = true,
  bool completionEnabled = true,
}) => MoodleRuntimeProfile(
  release: 'test',
  version: 'test',
  functionVersions: {for (final function in functions) function: 'test'},
  downloadFiles: downloadFiles,
  uploadFiles: uploadFiles,
  advancedFeatures: {'enablecompletion': completionEnabled ? 1 : 0},
  userMaxUploadFileSize: 1048576,
);
