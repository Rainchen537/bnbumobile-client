import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/moodle_module_access.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/services/assistant_context_builder.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final prompt in [
    'Read Workshop Reflection 2026 in Practice Hub and list its questions.',
    '请读取Practice Hub中的Workshop Reflection 2026，列出全部题目。',
    '读取Practice Hub中的workshop reflection2026，列出全部题目。',
  ]) {
    test('unquoted late module remains discoverable: $prompt', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final result = await fixture.builder.loadIspaceCourseCatalog(
        prompt,
        detailLevelOverride: AssistantIspaceCatalogDetailLevel.modules,
      );
      final course = result.courses.single;
      expect(course.sectionCount, 14);
      expect(course.sections.first.modules.first.name, _targetName);
      expect(course.sections.first.modules.first.moduleRef, _targetRef);
      expect(course.truncated, isTrue);
    });
  }

  test('an exact DDL title locates its course beyond catalog limits', () async {
    final fixture = _Fixture(addEarlierCourses: true);
    addTearDown(fixture.dispose);
    final result = await fixture.builder.loadIspaceCourseCatalog(
      'Read workshop reflection2026 and list its questions.',
      detailLevelOverride: AssistantIspaceCatalogDetailLevel.modules,
    );
    expect(result.courses.map((course) => course.courseId), ['999']);
    expect(
      result.courses.single.sections.first.modules.first.moduleRef,
      _targetRef,
    );
  });

  test('Feedback module details include actual question content', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final result = await fixture.builder.loadIspaceModule(_targetRef);
    expect(fixture.controller.textReads, 1);
    expect(result.content?.text, _questions);
    expect(result.content?.state, 'complete');
    expect(result.capabilities, contains('feedback_read'));
    expect(result.capabilities, isNot(contains('feedback_write')));
  });

  test('legacy module callers retain their metadata-only contract', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final result = await fixture.builder.loadIspaceModule(
      _targetRef,
      includeContent: false,
    );
    expect(result.content, isNull);
    expect(fixture.controller.textReads, 0);
    expect(result.capabilities, contains('feedback_read'));
  });

  test(
    'long Feedback content keeps a valid cursor within the result budget',
    () async {
      final fixture = _Fixture(text: List.filled(12000, '"问😀').join());
      addTearDown(fixture.dispose);
      final result = await fixture.builder.loadIspaceModule(_targetRef);
      expect(result.content, isNotNull);
      expect(result.content!.nextOffset, result.content!.text.length);
      expect(result.content!.totalCharacters, fixture.controller.text.length);
      expect(result.content!.state, 'truncated');
      expect(result.truncated, isTrue);
      expect(
        utf8.encode(jsonEncode(result.toJson())).length,
        lessThanOrEqualTo(22 * 1024),
      );
    },
  );

  test('a hidden parent section cannot authorize module content', () async {
    final fixture = _Fixture(sectionVisible: false);
    addTearDown(fixture.dispose);
    await expectLater(
      fixture.builder.loadIspaceModule(_targetRef),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      fixture.builder.readIspaceContent(_targetRef),
      throwsA(isA<StateError>()),
    );
    expect(fixture.controller.textReads, 0);
  });

  test('large metadata still leaves a progressing content cursor', () async {
    final fixture = _Fixture(
      text: List.filled(12000, '问😀').join(),
      accessMessage: List.filled(4000, String.fromCharCode(1)).join(),
    );
    addTearDown(fixture.dispose);
    final result = await fixture.builder.loadIspaceModule(_targetRef);
    expect(result.content!.text, isNotEmpty);
    expect(result.content!.nextOffset, greaterThan(0));
    expect(
      utf8.encode(jsonEncode(result.toJson())).length,
      lessThanOrEqualTo(22 * 1024),
    );
  });
}

const _targetName = 'Workshop Reflection 2026';
const _targetRef = 'm1:999:9001:8001:feedback';
const _questions =
    '1. How useful was the workshop?\n'
    'Required: yes\nOptions: Very useful | Somewhat useful | Not useful\n\n'
    '2. What would you improve?\nRequired: no\nAnswer: free text';

class _Fixture {
  _Fixture({
    bool addEarlierCourses = false,
    bool sectionVisible = true,
    String text = _questions,
    String accessMessage = 'Anonymous feedback',
  }) {
    controller = _Controller(
      addEarlierCourses: addEarlierCourses,
      sectionVisible: sectionVisible,
      text: text,
      accessMessage: accessMessage,
    );
    coordinator = AssistantContextCoordinator();
    builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
    );
  }

  late final _Controller controller;
  late final AssistantContextCoordinator coordinator;
  late final AssistantContextBuilder builder;

  void dispose() {
    coordinator.dispose();
    controller.dispose();
  }
}

class _Controller extends AppSessionController {
  _Controller({
    required this.addEarlierCourses,
    required this.sectionVisible,
    required this.text,
    required this.accessMessage,
  });

  final bool addEarlierCourses;
  final bool sectionVisible;
  final String text;
  final String accessMessage;
  int textReads = 0;

  @override
  bool get isLoggedIn => true;
  @override
  String? get username => 'synthetic-reader';
  @override
  List<CourseSummary> get courses => [
    if (addEarlierCourses)
      for (var i = 1; i <= 30; i++)
        CourseSummary(
          id: i,
          fullName: 'Synthetic Course $i',
          shortName: 'SYN$i',
          categoryName: 'Test',
          progress: null,
        ),
    CourseSummary(
      id: 999,
      fullName: 'Practice Hub',
      shortName: 'PRACTICE',
      categoryName: 'Test',
      progress: null,
    ),
  ];

  @override
  List<TimelineItem> get timelineItems => [
    TimelineItem(
      id: 1234,
      title: _targetName,
      activityState: 'Feedback closes',
      activityType: 'feedback',
      moduleName: 'feedback',
      description: '',
      courseName: 'Practice Hub',
      courseId: 999,
      instanceId: 8001,
      url: 'https://school.example/mod/feedback/view.php?id=9001',
      sortTime: DateTime.utc(2026, 10, 1),
      formattedTime: '',
      isOverdue: false,
    ),
  ];

  @override
  MoodleRuntimeProfile get moodleRuntimeProfile => MoodleRuntimeProfile(
    release: 'synthetic',
    version: 'test',
    downloadFiles: false,
    uploadFiles: false,
    advancedFeatures: const {},
    userMaxUploadFileSize: 0,
    functionVersions: {
      for (final name in [
        'core_enrol_get_users_courses',
        'core_course_get_contents',
        'mod_feedback_get_feedback_access_information',
        'mod_feedback_get_items',
      ])
        name: 'test',
    },
  );

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async =>
      courseId != 999
      ? []
      : [
          for (var i = 0; i < 14; i++)
            CourseContentSection(
              id: i + 1,
              sectionNum: i,
              name: 'Section $i',
              summary: '',
              userVisible: i != 13 || sectionVisible,
              modules: [
                CourseModule(
                  id: i == 13 ? 9001 : 1000 + i,
                  instance: i == 13 ? 8001 : 2000 + i,
                  name: i == 13 ? _targetName : 'Synthetic Item $i',
                  modName: i == 13 ? 'feedback' : 'page',
                  url: '',
                  iconUrl: '',
                  descriptionHtml: '',
                  contents: const [],
                  dates: const [],
                ),
              ],
            ),
        ];

  @override
  Future<MoodleModuleAccessSnapshot> loadModuleAccess({
    required String moduleType,
    required int instanceId,
    required int courseId,
  }) async => MoodleModuleAccessSnapshot(
    moduleType: 'feedback',
    canRead: true,
    canWrite: false,
    statusMessage: accessMessage,
  );

  @override
  Future<String> readAssistantModuleText({
    required int courseId,
    required int instanceId,
    required String moduleType,
    int pageId = 0,
  }) async {
    textReads++;
    return text;
  }
}
