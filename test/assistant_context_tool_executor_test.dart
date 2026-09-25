import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/services/assistant_context_builder.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/assistant_context_tool_executor.dart';
import 'package:bnbu_me/services/assistant_location_service.dart';
import 'package:bnbu_me/services/ta_course_repository.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final toolName in const ['get_ta_courses', 'get_schedule']) {
    test('$toolName waits for the cold-start TA load', () async {
      final fixture = _ToolFixture(toolName: toolName);
      addTearDown(fixture.dispose);
      await fixture.readStarted.future;

      var completed = false;
      final pending = fixture.execute().whenComplete(() => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      fixture.releaseRead.complete(fixture.storedPayload);
      final result = await pending;

      expect(fixture.store.targetReadCount, 1);
      if (toolName == 'get_ta_courses') {
        expect(result.context.taCourses, hasLength(1));
        expect(result.context.taCourses.single.title, 'Acceptance TA');
        expect(result.context.taCourseCollectionRevision, 1);
      } else {
        expect(result.context.schedule, hasLength(1));
        expect(
          result.context.schedule.single.courseId,
          'schedule:acceptance-ta',
        );
        expect(result.context.schedule.single.courseName, '日程：Acceptance TA');
        expect(result.context.schedule.single.room, 'Acceptance Room');
        expect(
          result.context.schedule.single.startsAt,
          DateTime.utc(2026, 8, 10, 2),
        );
      }
    });

    test('$toolName surfaces a cold-start TA load failure', () async {
      final fixture = _ToolFixture(toolName: toolName);
      addTearDown(fixture.dispose);
      await fixture.readStarted.future;

      final pending = fixture.execute();
      fixture.releaseRead.completeError(
        const TaCourseStorageException('无法读取 TA 课配置。'),
      );

      await expectLater(
        pending,
        throwsA(
          isA<AiAssistantToolExecutionException>().having(
            (error) => error.message,
            'message',
            contains('暂时无法读取'),
          ),
        ),
      );
    });
  }

  test(
    'original detail request overrides a metadata-only catalog call',
    () async {
      final session = _CatalogSessionController();
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });
      final contextBuilder = AssistantContextBuilder(
        controller: session,
        coordinator: coordinator,
      );
      expect(
        contextBuilder.needsIspaceCourseDetails('为了制定计划，目前 iSpace 证据还缺哪些信息？'),
        isTrue,
      );
      expect(
        contextBuilder.needsIspaceModuleRuntimeDetails(
          'Check Project 1 submission status.',
        ),
        isTrue,
      );
      expect(
        contextBuilder.needsIspaceModuleRuntimeDetails(
          'Is Project 1 a team assignment?',
        ),
        isTrue,
      );
      final executor = AssistantContextToolExecutor(
        contextBuilder: contextBuilder,
        sessionController: session,
        locationService: const _UnusedLocationService(),
      );

      final result = await executor.execute(
        const AssistantAgentToolCall(
          callId: 'catalog-details',
          name: 'search_ispace_course_catalog',
          arguments: {
            'query': 'provider omitted the named course',
            'include_details': false,
          },
        ),
        allowCurrentLocation: false,
        requestMessage:
            'How many Moodle modules are in my current iSpace catalog, '
            'and how many are visible?',
      );

      expect(session.contentLoadCount, 1);
      final course = result.context.ispaceCourseCatalog!.courses.single;
      expect(course.sections, isEmpty);
      expect(course.moduleCount, 2);
      expect(course.moduleTypeCounts, {'resource': 1, 'assignment': 1});
      expect(course.completionTrackingCounts, {'none': 2});
      expect(
        contextBuilder.lastIspaceCatalogDiagnostics?.detailLevel,
        AssistantIspaceCatalogDetailLevel.aggregates,
      );
    },
  );

  test(
    'provider-selected aggregate level overrides vague local wording',
    () async {
      final session = _CatalogSessionController();
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });
      final contextBuilder = AssistantContextBuilder(
        controller: session,
        coordinator: coordinator,
      );
      final executor = AssistantContextToolExecutor(
        contextBuilder: contextBuilder,
        sessionController: session,
        locationService: const _UnusedLocationService(),
      );

      final result = await executor.execute(
        const AssistantAgentToolCall(
          callId: 'catalog-ai-aggregates',
          name: 'search_ispace_course_catalog',
          arguments: {
            'query': '这些东西都是什么类型，各有几个？',
            'include_details': false,
            'detail_level': 'aggregates',
          },
        ),
        allowCurrentLocation: false,
        requestMessage: '这些东西都是什么类型，各有几个？',
      );

      expect(session.contentLoadCount, 1);
      final course = result.context.ispaceCourseCatalog!.courses.single;
      expect(course.sections, isEmpty);
      expect(course.moduleCount, 2);
      expect(course.moduleTypeCounts, {'resource': 1, 'assignment': 1});
      expect(
        contextBuilder.lastIspaceCatalogDiagnostics?.detailLevel,
        AssistantIspaceCatalogDetailLevel.aggregates,
      );
    },
  );

  test(
    'named module enforces module evidence over an AI summary level',
    () async {
      final session = _CatalogSessionController();
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });
      final contextBuilder = AssistantContextBuilder(
        controller: session,
        coordinator: coordinator,
      );
      final executor = AssistantContextToolExecutor(
        contextBuilder: contextBuilder,
        sessionController: session,
        locationService: const _UnusedLocationService(),
      );

      final result = await executor.execute(
        const AssistantAgentToolCall(
          callId: 'named-module-minimum',
          name: 'search_ispace_course_catalog',
          arguments: {
            'query': '“Bounded Catalog”里的“Lab Assignment”是什么类型？',
            'detail_level': 'summary',
          },
        ),
        allowCurrentLocation: false,
        requestMessage: '“Bounded Catalog”里的“Lab Assignment”是什么类型？',
      );

      expect(session.contentLoadCount, 1);
      final course = result.context.ispaceCourseCatalog!.courses.single;
      expect(
        course.sections.single.modules.map((module) => module.name),
        contains('Lab Assignment'),
      );
      expect(
        contextBuilder.lastIspaceCatalogDiagnostics?.detailLevel,
        AssistantIspaceCatalogDetailLevel.modules,
      );
    },
  );
}

class _ToolFixture {
  _ToolFixture({required this.toolName}) {
    final storageKey = TaCourseRepository.storageKeyForUsername('student01');
    store = _DeferredTaCourseStore(
      targetKey: storageKey,
      readStarted: readStarted,
      releaseRead: releaseRead,
    );
    session = _LoggedInSessionController();
    taCourses = TaCourseController(
      sessionController: session,
      repository: TaCourseRepository(store: store),
    );
    coordinator = AssistantContextCoordinator();
    executor = AssistantContextToolExecutor(
      contextBuilder: AssistantContextBuilder(
        controller: session,
        coordinator: coordinator,
        taCourseController: taCourses,
        now: () => DateTime.utc(2026, 8, 9, 1),
      ),
      sessionController: session,
      locationService: const _UnusedLocationService(),
    );
  }

  final String toolName;
  final Completer<void> readStarted = Completer<void>();
  final Completer<String?> releaseRead = Completer<String?>();
  late final _DeferredTaCourseStore store;
  late final _LoggedInSessionController session;
  late final TaCourseController taCourses;
  late final AssistantContextCoordinator coordinator;
  late final AssistantContextToolExecutor executor;

  String get storedPayload => jsonEncode({
    'version': 1,
    'revision': 1,
    'entries': [
      const TaCourseEntry(
        id: 'acceptance-ta',
        title: 'Acceptance TA',
        location: 'Acceptance Room',
        weekday: DateTime.monday,
        startMinutes: 10 * 60,
        endMinutes: 11 * 60,
        repeatType: TaCourseRepeatType.weekly,
        revision: 1,
      ).toJson(),
    ],
  });

  Future<AssistantAgentToolResult> execute() {
    return executor.execute(
      AssistantAgentToolCall(
        callId: 'cold-start-$toolName',
        name: toolName,
        arguments: const {},
      ),
      allowCurrentLocation: false,
    );
  }

  void dispose() {
    if (!releaseRead.isCompleted) {
      releaseRead.complete(null);
    }
    taCourses.dispose();
    coordinator.dispose();
    session.dispose();
  }
}

class _LoggedInSessionController extends AppSessionController {
  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  TimetableData? get timetable => null;

  @override
  Future<void> ensureTimetableLoaded() async {}
}

class _CatalogSessionController extends AppSessionController {
  int contentLoadCount = 0;

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  List<CourseSummary> get courses => [
    CourseSummary(
      id: 81,
      fullName: 'Bounded Catalog',
      shortName: 'BOUND81',
      categoryName: 'Computing',
      progress: null,
    ),
  ];

  @override
  MoodleRuntimeProfile get moodleRuntimeProfile => MoodleRuntimeProfile(
    release: 'test',
    version: 'test',
    functionVersions: const {
      'core_enrol_get_users_courses': 'test',
      'core_course_get_contents': 'test',
    },
    downloadFiles: true,
    uploadFiles: true,
    advancedFeatures: const {},
    userMaxUploadFileSize: 1048576,
  );

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    contentLoadCount++;
    return [
      CourseContentSection(
        id: 1,
        sectionNum: 1,
        name: 'Resources',
        summary: '',
        modules: [
          CourseModule(
            id: 101,
            instance: 201,
            name: 'Lecture Resource',
            modName: 'resource',
            url: '',
            iconUrl: '',
            descriptionHtml: '',
            contents: const [],
            dates: const [],
          ),
          CourseModule(
            id: 102,
            instance: 202,
            name: 'Lab Assignment',
            modName: 'assign',
            url: '',
            iconUrl: '',
            descriptionHtml: '',
            contents: const [],
            dates: const [],
          ),
        ],
      ),
    ];
  }

  @override
  Future<List<String>> loadCourseTeacherNames(int courseId) async => const [];
}

class _DeferredTaCourseStore implements TaCoursePreferencesStore {
  _DeferredTaCourseStore({
    required this.targetKey,
    required this.readStarted,
    required this.releaseRead,
  });

  final String targetKey;
  final Completer<void> readStarted;
  final Completer<String?> releaseRead;
  int targetReadCount = 0;

  @override
  Future<String?> getString(String key) {
    if (key == targetKey) {
      targetReadCount += 1;
      if (!readStarted.isCompleted) {
        readStarted.complete();
      }
      return releaseRead.future;
    }
    return Future.value(null);
  }

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<bool> setString(String key, String value) async => true;
}

class _UnusedLocationService implements AssistantLocationService {
  const _UnusedLocationService();

  @override
  Future<AssistantCurrentLocationContext> currentLocation() {
    throw StateError('Location should not be requested by these tools.');
  }
}
