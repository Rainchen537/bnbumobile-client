import '../models/assistant_content_page.dart';
import 'assistant/assistant_content_reader.dart';
import 'assistant/assistant_document_cache.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../models/assistant_models.dart';
import '../models/academic_calendar.dart';
import '../models/campus_time.dart';
import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/moodle_runtime_profile.dart';
import '../models/moodle_module_access.dart';
import '../models/quiz_attempt_data.dart';
import '../models/ta_course_entry.dart';
import '../models/timetable_data.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../state/app_session_controller.dart';
import '../state/ta_course_controller.dart';
import 'assistant_context_coordinator.dart';
import 'academic_calendar_service.dart';

enum AssistantIspaceCatalogDetailLevel {
  summary,
  aggregates,
  modules,
  files,
  teachers,
  full;

  bool get loadsContents => switch (this) {
    summary || teachers => false,
    aggregates || modules || files || full => true,
  };

  bool get loadsTeachers => this == teachers || this == full;

  bool get includesModules => this == modules || this == files || this == full;

  bool get includesFiles => this == files || this == full;

  int get maxCourses => 24;
}

class AssistantIspaceCatalogDiagnostics {
  const AssistantIspaceCatalogDiagnostics({
    required this.detailLevel,
    required this.selectedCourseCount,
    required this.contentNetworkLoads,
    required this.teacherNetworkLoads,
    required this.contentCacheHits,
    required this.teacherCacheHits,
    required this.failedCourseCount,
    required this.omittedCourseCount,
    required this.serializedBytes,
    required this.elapsedMilliseconds,
  });

  final AssistantIspaceCatalogDetailLevel detailLevel;
  final int selectedCourseCount;
  final int contentNetworkLoads;
  final int teacherNetworkLoads;
  final int contentCacheHits;
  final int teacherCacheHits;
  final int failedCourseCount;
  final int omittedCourseCount;
  final int serializedBytes;
  final int elapsedMilliseconds;

  Map<String, Object> toJson() => {
    'detail_level': detailLevel.name,
    'selected_course_count': selectedCourseCount,
    'content_network_loads': contentNetworkLoads,
    'teacher_network_loads': teacherNetworkLoads,
    'content_cache_hits': contentCacheHits,
    'teacher_cache_hits': teacherCacheHits,
    'failed_course_count': failedCourseCount,
    'omitted_course_count': omittedCourseCount,
    'serialized_bytes': serializedBytes,
    'elapsed_ms': elapsedMilliseconds,
  };
}

class AssistantContextBuilder {
  AssistantContextBuilder({
    this.mailRadarAvailable = false,
    required AppSessionController controller,
    required AssistantContextCoordinator coordinator,
    TaCourseController? taCourseController,
    AcademicCalendarBundleLoader? calendarBundleLoader,
    OfficialAcademicCalendarRepository? calendarDocumentRepository,
    AssistantDocumentTextCache? calendarTextCache,
    DateTime Function()? now,
    Duration ispaceCatalogCacheTtl = const Duration(minutes: 2),
    int ispaceCatalogMaxConcurrentRequests = 6,
  }) : _controller = controller,
       _coordinator = coordinator,
       _taCourseController = taCourseController,
       _calendarBundleLoader = calendarBundleLoader,
       _calendarDocumentRepository =
           calendarDocumentRepository ??
           OfficialAcademicCalendarRepository(
             cacheTtl: const Duration(minutes: 10),
             semester: () => controller.timetable == null
                 ? BnbuAcademicCalendar.current
                 : BnbuAcademicCalendar.semesterFor(controller.timetable!) ??
                       BnbuAcademicCalendar.current,
           ),
       _calendarTextCache = calendarTextCache ?? AssistantDocumentTextCache(),
       _now = now ?? DateTime.now,
       _ispaceCatalogCacheTtl = ispaceCatalogCacheTtl,
       _ispaceRequestLimiter = _AsyncLimiter(
         ispaceCatalogMaxConcurrentRequests,
       ) {
    if (ispaceCatalogCacheTtl.isNegative) {
      throw ArgumentError.value(
        ispaceCatalogCacheTtl,
        'ispaceCatalogCacheTtl',
        'must not be negative',
      );
    }
    if (ispaceCatalogMaxConcurrentRequests < 1 ||
        ispaceCatalogMaxConcurrentRequests > 6) {
      throw RangeError.range(
        ispaceCatalogMaxConcurrentRequests,
        1,
        6,
        'ispaceCatalogMaxConcurrentRequests',
      );
    }
  }

  final bool mailRadarAvailable;
  final AppSessionController _controller;
  final AssistantContextCoordinator _coordinator;
  final TaCourseController? _taCourseController;
  bool fixedScheduleEnabled = false;
  final AcademicCalendarBundleLoader? _calendarBundleLoader;
  final OfficialAcademicCalendarRepository _calendarDocumentRepository;
  final AssistantDocumentTextCache _calendarTextCache;
  final DateTime Function() _now;
  final Duration _ispaceCatalogCacheTtl;
  final _AsyncLimiter _ispaceRequestLimiter;
  final Map<int, _TimedCacheEntry<List<CourseContentSection>>>
  _courseContentsCache = {};
  final Map<int, _TimedCacheEntry<List<String>>> _courseTeachersCache = {};
  final Map<int, Future<List<CourseContentSection>>> _courseContentsInFlight =
      {};
  final Map<int, Future<List<String>>> _courseTeachersInFlight = {};
  Object? _catalogCacheSession;
  String _catalogCacheOwner = '';
  int _catalogCacheRevision = -1;
  int _catalogCacheEpoch = 0;
  bool _catalogCacheInitialized = false;
  AssistantIspaceCatalogDiagnostics? _lastIspaceCatalogDiagnostics;
  final Map<String, (DateTime, String)> _documentTextCache = {};

  static const int _maxIspaceToolResultBytes = 22 * 1024;

  AssistantIspaceCatalogDiagnostics? get lastIspaceCatalogDiagnostics =>
      _lastIspaceCatalogDiagnostics;

  void clearLastIspaceCatalogDiagnostics() {
    _lastIspaceCatalogDiagnostics = null;
  }

  void invalidateIspaceCatalogCache() {
    _catalogCacheEpoch++;
    _documentTextCache.clear();
    _courseContentsCache.clear();
    _courseTeachersCache.clear();
    _courseContentsInFlight.clear();
    _courseTeachersInFlight.clear();
    _catalogCacheInitialized = false;
  }

  Set<AssistantContextSource> availableSources() {
    final snapshot = _coordinator.snapshot();
    final runtimeProfile = _controller.moodleRuntimeProfile;
    final canReadCatalog =
        runtimeProfile?.supports(
          MoodleNormalizedCapability.courseCatalogRead,
        ) ??
        false;
    final canReadQuiz =
        runtimeProfile?.supports(MoodleNormalizedCapability.quizRead) ?? false;
    return {
      if (_academicProfile() != null) AssistantContextSource.academicProfile,
      if (_controller.courses.isNotEmpty ||
          (_controller.timetable?.courses.isNotEmpty ?? false))
        AssistantContextSource.courses,
      if (_controller.timetable?.courses.isNotEmpty ?? false)
        AssistantContextSource.termCourses,
      if (_controller.courses.isNotEmpty && canReadCatalog)
        AssistantContextSource.ispaceCourseCatalog,
      if (_controller.courses.isNotEmpty && canReadCatalog)
        AssistantContextSource.ispaceToolResults,
      if (_controller.timelineItems.isNotEmpty && canReadCatalog)
        AssistantContextSource.ispaceActivity,
      if (_controller.timelineItems.isNotEmpty && canReadQuiz)
        AssistantContextSource.ispaceQuizAttempt,
      if (_controller.timelineItems.any((item) => item.sortTime != null))
        AssistantContextSource.deadlines,
      if ((_controller.timetable?.courses.any(
                (course) => course.meetings.isNotEmpty,
              ) ??
              false) ||
          (_taCourseController?.entries.isNotEmpty ?? false))
        AssistantContextSource.schedule,
      AssistantContextSource.academicCalendar,
      if (_controller.username?.trim().isNotEmpty ?? false)
        AssistantContextSource.examTimetable,
      if (snapshot.mailSummaries.isNotEmpty ||
          _coordinator.canLoadMailSummaries)
        AssistantContextSource.mailSummaries,
      if (snapshot.selectedMail != null) AssistantContextSource.selectedMail,
      if ((_controller.username?.trim().isNotEmpty ?? false) &&
          _controller.canOpenOfficialSchoolSession)
        AssistantContextSource.mailToolResults,
      if (snapshot.schoolActivities.isNotEmpty)
        AssistantContextSource.schoolActivities,
      if (_taCourseController != null) AssistantContextSource.taCourses,
      if (snapshot.currentPage != null) AssistantContextSource.currentPage,
    };
  }

  Set<AssistantContextSource> planningSources() {
    final hasSessionOwner = _controller.username?.trim().isNotEmpty ?? false;
    final runtimeProfile = _controller.moodleRuntimeProfile;
    final canReadCatalog =
        runtimeProfile?.supports(
          MoodleNormalizedCapability.courseCatalogRead,
        ) ??
        false;
    final canReadQuiz =
        runtimeProfile?.supports(MoodleNormalizedCapability.quizRead) ?? false;
    return {
      ...availableSources(),
      if (hasSessionOwner) AssistantContextSource.academicProfile,
      if (hasSessionOwner) AssistantContextSource.schedule,
      if (hasSessionOwner) AssistantContextSource.termCourses,
      if (hasSessionOwner && canReadCatalog)
        AssistantContextSource.ispaceCourseCatalog,
      if (hasSessionOwner && canReadCatalog)
        AssistantContextSource.ispaceToolResults,
      if (hasSessionOwner && canReadCatalog)
        AssistantContextSource.ispaceActivity,
      if (hasSessionOwner && canReadQuiz)
        AssistantContextSource.ispaceQuizAttempt,
      AssistantContextSource.academicCalendar,
      if (hasSessionOwner) AssistantContextSource.examTimetable,
      AssistantContextSource.currentLocation,
    };
  }

  Future<TaCourseMutationResult?> ensureTaCoursesLoaded() {
    return _taCourseController?.ensureLoaded() ?? Future.value(null);
  }

  AssistantContextPayload build(
    Set<AssistantContextSource> selectedSources, {
    String contextVersion = '3',
    AssistantCurrentLocationContext? currentLocation,
    AssistantIspaceCourseCatalogContext? ispaceCourseCatalog,
    AssistantIspaceActivityContext? ispaceActivity,
    AssistantIspaceQuizAttemptContext? ispaceQuizAttempt,
    List<AssistantIspaceToolResultContext> ispaceToolResults = const [],
    AssistantAcademicCalendarContext? academicCalendar,
    List<AssistantMailSummaryContext>? mailSummaries,
    List<AssistantMailToolResultContext> mailToolResults = const [],
  }) {
    final snapshot = _coordinator.snapshot();
    return AssistantContextPayload(
      sources: Set.unmodifiable(selectedSources),
      version: contextVersion,
      mailRadarAvailable: mailRadarAvailable,
      academicProfile:
          selectedSources.contains(AssistantContextSource.academicProfile)
          ? _academicProfile()
          : null,
      courses: selectedSources.contains(AssistantContextSource.courses)
          ? _courses()
          : const [],
      term: selectedSources.contains(AssistantContextSource.termCourses)
          ? _term()
          : null,
      termCourses: selectedSources.contains(AssistantContextSource.termCourses)
          ? _termCourses()
          : const [],
      ispaceCourseCatalog:
          selectedSources.contains(AssistantContextSource.ispaceCourseCatalog)
          ? ispaceCourseCatalog
          : null,
      ispaceActivity:
          selectedSources.contains(AssistantContextSource.ispaceActivity)
          ? ispaceActivity
          : null,
      ispaceQuizAttempt:
          selectedSources.contains(AssistantContextSource.ispaceQuizAttempt)
          ? ispaceQuizAttempt
          : null,
      ispaceToolResults:
          selectedSources.contains(AssistantContextSource.ispaceToolResults)
          ? List.unmodifiable(ispaceToolResults)
          : const [],
      deadlines: selectedSources.contains(AssistantContextSource.deadlines)
          ? _deadlines()
          : const [],
      schedule: selectedSources.contains(AssistantContextSource.schedule)
          ? _schedule()
          : const [],
      academicCalendar:
          selectedSources.contains(AssistantContextSource.academicCalendar)
          ? academicCalendar
          : null,
      examTimetable:
          selectedSources.contains(AssistantContextSource.examTimetable)
          ? _examTimetable()
          : null,
      mailSummaries:
          selectedSources.contains(AssistantContextSource.mailSummaries)
          ? (mailSummaries ?? snapshot.mailSummaries)
          : const [],
      selectedMail:
          selectedSources.contains(AssistantContextSource.selectedMail)
          ? snapshot.selectedMail
          : null,
      mailToolResults:
          selectedSources.contains(AssistantContextSource.mailToolResults)
          ? List.unmodifiable(mailToolResults)
          : const [],
      schoolActivities:
          selectedSources.contains(AssistantContextSource.schoolActivities)
          ? snapshot.schoolActivities
          : const [],
      fixedScheduleVersion:
          fixedScheduleEnabled &&
              selectedSources.contains(AssistantContextSource.taCourses)
          ? 2
          : 0,
      fixedScheduleCourses:
          fixedScheduleEnabled &&
              selectedSources.contains(AssistantContextSource.taCourses)
          ? _fixedScheduleCourses()
          : const [],
      taCourses: selectedSources.contains(AssistantContextSource.taCourses)
          ? _taCourses()
          : const [],
      taCourseCollectionRevision:
          selectedSources.contains(AssistantContextSource.taCourses)
          ? _taCourseController?.revision
          : null,
      currentPage: selectedSources.contains(AssistantContextSource.currentPage)
          ? snapshot.currentPage
          : null,
      currentLocation:
          selectedSources.contains(AssistantContextSource.currentLocation)
          ? currentLocation
          : null,
    );
  }

  AssistantAcademicProfileContext? _academicProfile() {
    final timetableProfile = _controller.timetable?.profile;
    final programmeCode = timetableProfile?.programme.trim() ?? '';
    final programmeName = _controller.portalProfile?.majorName.trim() ?? '';
    final year = timetableProfile?.year.trim() ?? '';
    if (programmeCode.isEmpty && programmeName.isEmpty) {
      return null;
    }
    return AssistantAcademicProfileContext(
      programmeCode: _limit(programmeCode, 80),
      programmeName: _limit(programmeName, 160),
      year: _limit(year, 40),
    );
  }

  Future<List<AssistantMailSummaryContext>> loadMailSummaries() =>
      _coordinator.loadMailSummaries();

  Future<AssistantAcademicCalendarContext> loadAcademicCalendar() async {
    final timetable = _controller.timetable;
    final bundle = await (_calendarBundleLoader ?? _calendarDocumentRepository)
        .loadBundle();
    final context = BnbuAcademicCalendar.contextFor(timetable);
    return AssistantAcademicCalendarContext(
      semesterTitle: _limit(bundle.semesterTitle, 160),
      timezone: context.timezone,
      appliesToSelectedSemester: context.appliesToSelectedSemester,
      semesterStartsOn: context.semesterStartsOn,
      lastClassDay: context.lastClassDay,
      events: context.events
          .take(200)
          .map(
            (event) => AssistantAcademicCalendarEventContext(
              kind: event.kind.wireValue,
              name: _limit(event.name, 80),
              startsOn: event.startsOn,
              endsOn: event.endsOn,
              reason: _limit(event.reason, 160),
              sourceWeekday: event.sourceWeekday,
            ),
          )
          .toList(growable: false),
      documents: [
        AssistantAcademicCalendarDocumentContext(
          kind: 'academic_calendar',
          title: _limit(bundle.academicCalendar.title, 240),
          url: bundle.academicCalendar.uri.toString(),
        ),
        AssistantAcademicCalendarDocumentContext(
          kind: 'class_schedule',
          title: _limit(bundle.classSchedule.title, 240),
          url: bundle.classSchedule.uri.toString(),
        ),
      ],
    );
  }

  Future<AssistantAcademicCalendarContext> readAcademicCalendarDocument(
    String kind,
    int offset,
  ) async {
    final documentKind = kind == 'academic_calendar'
        ? AcademicCalendarDocumentKind.academicCalendar
        : AcademicCalendarDocumentKind.classSchedule;
    final bytes = await _calendarDocumentRepository.loadDocument(documentKind);
    final text = await _calendarTextCache.read('$kind.pdf', bytes);
    final metadata = await loadAcademicCalendar();
    return AssistantAcademicCalendarContext(
      semesterTitle: metadata.semesterTitle,
      timezone: metadata.timezone,
      appliesToSelectedSemester: metadata.appliesToSelectedSemester,
      semesterStartsOn: metadata.semesterStartsOn,
      lastClassDay: metadata.lastClassDay,
      events: metadata.events,
      documents: metadata.documents,
      documentPages: [
        {
          'kind': kind,
          'content': AssistantContentPage.slice(text, offset).toJson(),
        },
      ],
    );
  }

  Future<AssistantIspaceCourseCatalogContext> loadIspaceCourseCatalog(
    String message, {
    String? entityQuery,
    bool? includeDetails,
    AssistantIspaceCatalogDetailLevel? detailLevelOverride,
    void Function(AssistantIspaceCatalogDiagnostics diagnostics)? onDiagnostics,
  }) async {
    final clock = Stopwatch()..start();
    final runtimeProfile = _controller.moodleRuntimeProfile;
    if (runtimeProfile == null ||
        !runtimeProfile.supports(
          MoodleNormalizedCapability.courseCatalogRead,
        )) {
      throw StateError('学校当前未开放 iSpace 课程目录能力。');
    }
    final catalogLease = _controller.captureSessionLease();
    final eligible = _selectIspaceCourses(message);
    final entityText = '$message\n${entityQuery ?? ''}';
    final explicitEntityNames = _quotedIspaceEntityNames(entityText);
    final detailLevel =
        detailLevelOverride ??
        ispaceCatalogDetailLevel(message, includeDetails: includeDetails);
    final manualCompletionProjection =
        detailLevel == AssistantIspaceCatalogDetailLevel.modules &&
        isReadOnlyVisibleManualCompletionList(message);
    final selected = eligible
        .take(detailLevel.maxCourses)
        .toList(growable: false);
    var contentNetworkLoads = 0;
    var teacherNetworkLoads = 0;
    var contentCacheHits = 0;
    var teacherCacheHits = 0;

    void recordDiagnostics(AssistantIspaceCourseCatalogContext catalog) {
      clock.stop();
      final diagnostics = AssistantIspaceCatalogDiagnostics(
        detailLevel: detailLevel,
        selectedCourseCount: selected.length,
        contentNetworkLoads: contentNetworkLoads,
        teacherNetworkLoads: teacherNetworkLoads,
        contentCacheHits: contentCacheHits,
        teacherCacheHits: teacherCacheHits,
        failedCourseCount: catalog.failedCourseCount,
        omittedCourseCount: catalog.omittedCourseCount,
        serializedBytes: _serializedBytes(catalog.toJson()),
        elapsedMilliseconds: clock.elapsedMilliseconds,
      );
      _lastIspaceCatalogDiagnostics = diagnostics;
      onDiagnostics?.call(diagnostics);
    }

    if (detailLevel == AssistantIspaceCatalogDetailLevel.summary) {
      final courses = selected
          .map(
            (course) => AssistantIspaceCourseContext(
              courseId: course.id.toString(),
              name: _limit(course.fullName, 240),
              shortName: _limit(course.shortName, 120),
              category: _limit(course.categoryName, 160),
              startAt: course.startAt,
              endAt: course.endAt,
              teachers: const [],
              sections: const [],
              truncated: false,
              progress: course.progress,
              completionEnabled: course.enableCompletion,
              completionUserTracked: course.completionUserTracked,
              completed: course.completed,
              showGrades: course.showGrades,
            ),
          )
          .toList(growable: false);
      final omitted = eligible.length - selected.length;
      final catalog = AssistantIspaceCourseCatalogContext(
        courses: courses,
        complete: omitted == 0,
        omittedCourseCount: omitted.clamp(0, 1000),
        failedCourseCount: 0,
        truncated: omitted > 0,
      );
      recordDiagnostics(catalog);
      return catalog;
    }
    _prepareIspaceCatalogCache();
    final loaded = <AssistantIspaceCourseContext>[];
    var failed = 0;
    var globalModules = 0;
    var globalFiles = 0;
    final results = <_LoadedIspaceCourse?>[];
    for (var offset = 0; offset < selected.length; offset += 4) {
      results.addAll(
        await Future.wait(
          selected.skip(offset).take(4).map((course) async {
            try {
              final contentFuture = detailLevel.loadsContents
                  ? _loadCachedCourseContents(
                      course.id,
                      onSource: (cacheHit) {
                        if (cacheHit) {
                          contentCacheHits++;
                        } else {
                          contentNetworkLoads++;
                        }
                      },
                    )
                  : Future<List<CourseContentSection>>.value(const []);
              final teacherFuture = detailLevel.loadsTeachers
                  ? _loadCachedCourseTeachers(
                      course.id,
                      onSource: (cacheHit) {
                        if (cacheHit) {
                          teacherCacheHits++;
                        } else {
                          teacherNetworkLoads++;
                        }
                      },
                    )
                  : Future<List<String>>.value(const []);
              final values = await Future.wait<Object>([
                contentFuture,
                teacherFuture,
              ]);
              return _LoadedIspaceCourse(
                course: course,
                sections: values[0] as List<CourseContentSection>,
                teachers: values[1] as List<String>,
              );
            } catch (error) {
              if (_isSessionFailure(error)) {
                rethrow;
              }
              return null;
            }
          }),
        ),
      );
    }
    if (catalogLease != null && !catalogLease.isActive) {
      throw StateError('登录状态已变化，请重试。');
    }
    for (final result in results) {
      if (result == null) {
        failed++;
        continue;
      }
      final course = result.course;
      final sourceSections = result.sections;
      final sectionCount = sourceSections.length;
      final visibleSectionCount = sourceSections
          .where((section) => section.userVisible)
          .length;
      final moduleTypeCounts = <String, int>{};
      final visibleModuleTypeCounts = <String, int>{};
      final completionTrackingCounts = <String, int>{};
      final visibleCompletionTrackingCounts = <String, int>{};
      var moduleCount = 0;
      var visibleModuleCount = 0;
      if (detailLevel.loadsContents) {
        for (final section in sourceSections) {
          for (final module in section.modules) {
            final moduleType = _normalizedIspaceModuleType(module.modName);
            moduleCount++;
            moduleTypeCounts.update(
              moduleType,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            final completionTracking = _normalizedCompletionTracking(
              module.completionTracking,
            );
            completionTrackingCounts.update(
              completionTracking,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            if (section.userVisible && module.userVisible) {
              visibleModuleCount++;
              visibleModuleTypeCounts.update(
                moduleType,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
              visibleCompletionTrackingCounts.update(
                completionTracking,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
          }
        }
      }
      var courseTruncated = false;
      final sections = <AssistantIspaceSectionContext>[];
      var courseModules = 0;
      var courseFiles = 0;
      bool canManuallyComplete(
        CourseContentSection section,
        CourseModule module,
      ) =>
          runtimeProfile.supports(
            MoodleNormalizedCapability.completionManualWrite,
          ) &&
          section.userVisible &&
          module.userVisible &&
          module.completionTracking == 1 &&
          module.completionData?.isTrackedUser == true &&
          module.completionData?.userVisible == true;
      if (detailLevel.includesModules) {
        if (manualCompletionProjection) {
          final matchingModules = <CourseModule>[];
          for (final section in sourceSections) {
            for (final module in section.modules) {
              if (canManuallyComplete(section, module)) {
                matchingModules.add(module);
              }
            }
          }
          final remainingGlobalModules = 120 - globalModules;
          final projectionLimit = remainingGlobalModules < 32
              ? remainingGlobalModules
              : 32;
          courseTruncated = matchingModules.length > projectionLimit;
          final modules = <AssistantIspaceModuleContext>[];
          for (final module in matchingModules.take(projectionLimit)) {
            courseModules++;
            globalModules++;
            modules.add(
              AssistantIspaceModuleContext(
                moduleId: 'manual-$courseModules',
                name: _limit(module.name, 240),
                moduleType: _limit(module.modName, 80),
                files: const [],
                moduleRef: '',
                instanceId: '',
                userVisible: true,
                completionTracking: 1,
                completionState: (module.completionData?.state ?? 0).clamp(
                  0,
                  3,
                ),
                completedAt: module.completionData?.timeCompletedAt,
                canManualComplete: true,
                canDownloadFiles: false,
                dates: const [],
              ),
            );
          }
          if (modules.isNotEmpty) {
            sections.add(
              AssistantIspaceSectionContext(
                sectionId: 'manual-completion',
                name: 'Manual completion',
                modules: List.unmodifiable(modules),
                userVisible: true,
              ),
            );
          }
        } else {
          // Match against actual returned names before applying output limits.
          // This resolves an already-selected source; it does not select tools.
          final requestedNames = <String>{
            ...explicitEntityNames,
            for (final section in sourceSections)
              for (final module in section.modules)
                if (_mentionsIspaceEntity(entityText, module.name))
                  _normalizeCourseSearchText(module.name),
          };
          final orderedSections = _prioritizeIspaceSections(
            sourceSections,
            requestedNames,
          );
          courseTruncated = sourceSections.length > 10;
          for (final section in orderedSections.take(10)) {
            final modules = <AssistantIspaceModuleContext>[];
            final orderedModules = _prioritizeIspaceModules(
              section.modules,
              requestedNames,
            );
            for (final module in orderedModules) {
              if (courseModules >= 32 || globalModules >= 120) {
                courseTruncated = true;
                break;
              }
              final userVisible = section.userVisible && module.userVisible;
              final files = <AssistantIspaceFileContext>[];
              if (detailLevel.includesFiles) {
                for (final file
                    in userVisible
                        ? module.contents
                        : const <CourseModuleContent>[]) {
                  if (courseFiles >= 48 ||
                      globalFiles >= 240 ||
                      files.length >= 8) {
                    courseTruncated = true;
                    break;
                  }
                  files.add(
                    AssistantIspaceFileContext(
                      name: _limit(file.fileName, 255),
                      mimeType: _limit(file.mimeType, 120),
                      sizeBytes: file.fileSize.clamp(0, 2147483647),
                      modifiedAt: file.timeModifiedAt,
                      author: _limit(file.author, 160),
                    ),
                  );
                  courseFiles++;
                  globalFiles++;
                }
              }
              modules.add(
                AssistantIspaceModuleContext(
                  moduleId: module.id.toString(),
                  name: _limit(module.name, 240),
                  moduleType: _limit(module.modName, 80),
                  files: List.unmodifiable(files),
                  moduleRef: userVisible ? _moduleRef(course.id, module) : '',
                  instanceId: module.instance.toString(),
                  userVisible: userVisible,
                  availabilityInfo: _limit(
                    _htmlText(module.availabilityInfo),
                    500,
                  ),
                  completionTracking: module.completionTracking.clamp(0, 2),
                  completionState: (module.completionData?.state ?? 0).clamp(
                    0,
                    3,
                  ),
                  completedAt: module.completionData?.timeCompletedAt,
                  canManualComplete: canManuallyComplete(section, module),
                  canDownloadFiles:
                      runtimeProfile.supports(
                        MoodleNormalizedCapability.fileDownload,
                      ) &&
                      userVisible &&
                      module.downloadContent &&
                      files.isNotEmpty,
                  dates: module.dates
                      .take(8)
                      .map(
                        (date) => AssistantIspaceModuleDateContext(
                          label: _limit(date.label, 120),
                          dataId: _limit(date.dataId, 80),
                          at: date.dateTime,
                        ),
                      )
                      .toList(growable: false),
                ),
              );
              courseModules++;
              globalModules++;
            }
            sections.add(
              AssistantIspaceSectionContext(
                sectionId: section.id.toString(),
                name: _limit(section.name, 160),
                modules: List.unmodifiable(modules),
                userVisible: section.userVisible,
              ),
            );
          }
        }
      }
      loaded.add(
        AssistantIspaceCourseContext(
          courseId: course.id.toString(),
          name: _limit(course.fullName, 240),
          shortName: _limit(course.shortName, 120),
          category: _limit(course.categoryName, 160),
          startAt: course.startAt,
          endAt: course.endAt,
          teachers: result.teachers
              .map((name) => _limit(name, 160))
              .take(8)
              .toList(),
          sections: List.unmodifiable(sections),
          truncated: courseTruncated,
          progress: course.progress,
          completionEnabled: course.enableCompletion,
          completionUserTracked: course.completionUserTracked,
          completed: course.completed,
          showGrades: course.showGrades,
          sectionCount: detailLevel.loadsContents ? sectionCount : null,
          visibleSectionCount: detailLevel.loadsContents
              ? visibleSectionCount
              : null,
          moduleCount: detailLevel.loadsContents ? moduleCount : null,
          visibleModuleCount: detailLevel.loadsContents
              ? visibleModuleCount
              : null,
          moduleTypeCounts: Map.unmodifiable(moduleTypeCounts),
          visibleModuleTypeCounts: Map.unmodifiable(visibleModuleTypeCounts),
          completionTrackingCounts: Map.unmodifiable(completionTrackingCounts),
          visibleCompletionTrackingCounts: Map.unmodifiable(
            visibleCompletionTrackingCounts,
          ),
        ),
      );
    }
    var omitted = eligible.length - selected.length;
    var truncated = omitted > 0 || loaded.any((course) => course.truncated);
    while (loaded.isNotEmpty &&
        utf8.encode(jsonEncode(_catalogJson(loaded))).length > 96 * 1024) {
      loaded.removeLast();
      omitted++;
      truncated = true;
    }
    final catalog = AssistantIspaceCourseCatalogContext(
      courses: List.unmodifiable(loaded),
      complete: failed == 0 && !truncated,
      omittedCourseCount: omitted.clamp(0, 1000),
      failedCourseCount: failed.clamp(0, 1000),
      truncated: truncated,
    );
    recordDiagnostics(catalog);
    return catalog;
  }

  Future<AssistantIspaceActivityContext> loadIspaceActivity(
    String itemId,
  ) async {
    final normalized = itemId.trim();
    final matches = _controller.timelineItems.where(
      (item) => item.id.toString() == normalized,
    );
    if (matches.length != 1) {
      throw StateError('iSpace 活动稳定标识已失效。');
    }
    final item = matches.single;
    final detail = await _controller.loadTimelineDetail(item);
    CourseModule? indexedModule;
    if (item.courseId > 0) {
      try {
        final sections = await _loadCachedCourseContents(
          item.courseId,
          onSource: (_) {},
        );
        final modules = sections.expand((section) => section.modules).toList();
        final courseModuleId = int.tryParse(_courseModuleId(item.url)) ?? 0;
        final moduleMatches = modules.where(
          (module) =>
              (courseModuleId > 0 && module.id == courseModuleId) ||
              (item.instanceId > 0 && module.instance == item.instanceId),
        );
        if (moduleMatches.length == 1) {
          indexedModule = moduleMatches.single;
        } else if (courseModuleId > 0) {
          final exact = modules.where((module) => module.id == courseModuleId);
          if (exact.length == 1) indexedModule = exact.single;
        }
      } catch (_) {
        // Timeline detail remains usable when the course index is temporarily
        // unavailable; no failed lookup is persisted as a missing activity.
      }
    }
    final fileMetadata = detail.assignmentIntroFiles.isNotEmpty
        ? detail.assignmentIntroFiles.map(
            (file) => AssistantIspaceFileContext(
              name: _limit(file.fileName, 255),
              mimeType: _limit(file.mimeType, 120),
              sizeBytes: file.fileSize.clamp(0, 2147483647),
              modifiedAt: file.modifiedAt,
              author: '',
            ),
          )
        : (indexedModule?.contents ?? const <CourseModuleContent>[]).map(
            (file) => AssistantIspaceFileContext(
              name: _limit(file.fileName, 255),
              mimeType: _limit(file.mimeType, 120),
              sizeBytes: file.fileSize.clamp(0, 2147483647),
              modifiedAt: file.timeModifiedAt,
              author: _limit(file.author, 160),
            ),
          );
    final introFiles = fileMetadata
        .take(8)
        .map((file) => file)
        .toList(growable: false);
    final submissionFiles = detail.submissionFiles
        .take(6)
        .map(
          (file) => AssistantIspaceFileContext(
            name: _limit(file.fileName, 255),
            mimeType: _limit(file.mimeType, 120),
            sizeBytes: file.fileSize.clamp(0, 2147483647),
            modifiedAt: file.modifiedAt,
            author: '',
          ),
        )
        .toList(growable: false);
    final forumDiscussions = detail.forumDiscussions
        .take(24)
        .map(
          (discussion) => AssistantIspaceForumDiscussionContext(
            discussionId: discussion.id.toString(),
            subject: _limit(discussion.subject, 300),
            messagePreview: _limit(_htmlText(discussion.messagePreview), 1000),
            author: _limit(discussion.author, 160),
            modifiedAt: discussion.timeModifiedAt,
            replyCount: discussion.replyCount.clamp(0, 1000000),
            pinned: discussion.pinned,
            locked: discussion.locked,
          ),
        )
        .toList(growable: false);
    final moduleSummary = _htmlText(indexedModule?.descriptionHtml ?? '');
    final summary = detail.assignmentIntro.trim().isNotEmpty
        ? detail.assignmentIntro
        : moduleSummary.isNotEmpty
        ? moduleSummary
        : item.description;
    final moduleOpenAt = _moduleDate(indexedModule, const ['open', 'start']);
    final moduleDueAt = _moduleDate(indexedModule, const ['due']);
    final moduleCloseAt = _moduleDate(indexedModule, const ['close', 'end']);
    return AssistantIspaceActivityContext(
      itemId: normalized,
      courseId: item.courseId > 0 ? item.courseId.toString() : '',
      courseModuleId: indexedModule?.id.toString() ?? _courseModuleId(item.url),
      instanceId:
          indexedModule?.instance.toString() ??
          (item.instanceId > 0 ? item.instanceId.toString() : ''),
      activityType:
          indexedModule?.modName.trim().toLowerCase().isNotEmpty == true
          ? _limit(indexedModule!.modName.trim().toLowerCase(), 80)
          : _activityType(item),
      title: _limit(
        detail.assignmentName.trim().isNotEmpty
            ? detail.assignmentName
            : indexedModule?.name.trim().isNotEmpty == true
            ? indexedModule!.name
            : item.title,
        300,
      ),
      courseName: _limit(item.courseName, 240),
      summary: _limit(summary.replaceAll(RegExp(r'\s+'), ' ').trim(), 4000),
      openAt: detail.openDate ?? moduleOpenAt,
      dueAt: detail.dueDate ?? moduleDueAt ?? item.sortTime,
      closeAt: detail.cutoffDate ?? moduleCloseAt,
      submissionStatus: _limit(detail.submissionStatus, 80),
      canEditSubmission: detail.canEditSubmission,
      supportsFileSubmission: detail.supportsFileSubmission,
      supportsOnlineTextSubmission: detail.supportsOnlineTextSubmission,
      maxFileSubmissions: detail.maxFileSubmissions.clamp(0, 100),
      maxSubmissionSizeBytes: detail.maxSubmissionSizeBytes.clamp(
        0,
        2147483647,
      ),
      files: List.unmodifiable(introFiles),
      gradingStatus: _limit(detail.gradingStatus, 80),
      feedbackSummary: _limit(_htmlText(detail.feedbackSummary), 2000),
      submissionFiles: List.unmodifiable(submissionFiles),
      forumId: detail.forumId > 0 ? detail.forumId.toString() : '',
      forumDiscussions: List.unmodifiable(forumDiscussions),
      canStartDiscussion: detail.forumId > 0 && detail.canStartDiscussion,
      submissionDrafts: detail.submissionDrafts,
      requiresSubmissionStatement: detail.requiresSubmissionStatement,
      teamSubmission: detail.teamSubmission,
      requireAllTeamMembersSubmit: detail.requireAllTeamMembersSubmit,
      preventSubmissionNotInGroup: detail.preventSubmissionNotInGroup,
      timeLimitSeconds: detail.timeLimitSeconds.clamp(0, 2147483647),
      submissionsEnabled: detail.submissionsEnabled,
      submissionLocked: detail.submissionLocked,
      canFinalizeSubmission: detail.canFinalizeSubmission,
    );
  }

  Future<AssistantIspaceQuizAttemptContext> loadIspaceQuizAttempt(
    String itemId,
  ) async {
    final normalized = itemId.trim();
    final matches = _controller.timelineItems.where(
      (item) => item.id.toString() == normalized,
    );
    if (matches.length != 1) {
      throw StateError('iSpace 测验稳定标识已失效。');
    }
    final item = matches.single;
    final activityType = '${item.activityType} ${item.moduleName} ${item.url}'
        .toLowerCase();
    if (!activityType.contains('quiz')) {
      throw StateError('该 iSpace 活动不是 Quiz。');
    }
    final snapshot = await _controller.loadQuizAttempt(item);
    var remainingFields = 200;
    var remainingOptions = 400;
    final questions = snapshot.questions.take(40).map((question) {
      final fields = question.fields
          .take(remainingFields.clamp(0, 20))
          .map((field) {
            remainingFields--;
            final options = field.options
                .take(remainingOptions.clamp(0, 40))
                .map((option) {
                  remainingOptions--;
                  return AssistantQuizAnswerOptionContext(
                    value: _limit(option.value, 500),
                    label: _limit(option.label, 500),
                  );
                })
                .toList(growable: false);
            return AssistantQuizAnswerFieldContext(
              name: _limit(field.name, 160),
              kind: switch (field.kind) {
                QuizAnswerFieldKind.choice => 'choice',
                QuizAnswerFieldKind.text => 'text',
                QuizAnswerFieldKind.select => 'select',
              },
              label: _limit(field.label, 500),
              currentValues: field.currentValues
                  .map((value) => _limit(value, 4000))
                  .take(20)
                  .toList(growable: false),
              options: options,
              maxLength: field.maxLength.clamp(1, 4000),
              multiple: field.multiple,
            );
          })
          .toList(growable: false);
      return AssistantQuizQuestionContext(
        slot: question.slot,
        number: _limit(question.number, 40),
        type: _limit(question.type, 80),
        prompt: _limit(question.prompt, 4000),
        status: _limit(question.status, 120),
        fields: fields,
      );
    }).toList();
    while (questions.isNotEmpty &&
        utf8
                .encode(
                  jsonEncode({
                    'questions': questions
                        .map((question) => question.toJson())
                        .toList(),
                  }),
                )
                .length >
            96 * 1024) {
      questions.removeLast();
    }
    return AssistantIspaceQuizAttemptContext(
      itemId: snapshot.itemId,
      quizId: snapshot.quizId,
      attemptId: snapshot.attemptId,
      state: _limit(snapshot.state, 80),
      canStart: snapshot.canStart,
      canSave: snapshot.canSave,
      canFinish: snapshot.canFinish,
      accessMessage: _limit(snapshot.accessMessage, 1000),
      questions: List.unmodifiable(questions),
      truncated:
          snapshot.truncated || questions.length < snapshot.questions.length,
    );
  }

  Future<AssistantIspaceToolResultContext> readIspaceContent(
    String moduleRef, {
    String kind = 'description',
    int offset = 0,
    int itemId = 0,
    int page = 0,
  }) async {
    final lease = _controller.captureSessionLease();
    final identity = _parseModuleRef(moduleRef);
    final course = _controller.courses.singleWhere(
      (c) => c.id == identity.$1 && c.visible && !c.hidden,
    );
    final sections = await _loadCachedCourseContents(
      course.id,
      onSource: (_) {},
    );
    final module = sections
        .where((section) => section.userVisible)
        .expand((s) => s.modules)
        .singleWhere(
          (m) =>
              m.id == identity.$2 &&
              m.instance == identity.$3 &&
              m.modName == identity.$4 &&
              m.userVisible,
        );
    if ((kind == 'quiz' && module.modName != 'quiz') ||
        (kind == 'discussion' && module.modName != 'forum')) {
      throw StateError('正文类型与模块不匹配。');
    }
    final filesForReading = [...module.contents];
    if (module.modName == 'assign' && (kind == 'files' || kind == 'file')) {
      final assignment = await _controller.resolveAssistantModuleTimelineItem(
        moduleRef,
      );
      final detail = await _controller.loadTimelineDetail(assignment);
      final knownUrls = filesForReading.map((f) => f.fileUrl).toSet();
      for (final file in [
        ...detail.assignmentIntroFiles,
        ...detail.submissionFiles,
      ]) {
        if (!knownUrls.add(file.fileUrl)) continue;
        final submitted = detail.submissionFiles.contains(file);
        filesForReading.add(
          CourseModuleContent(
            type: 'file',
            fileName: '${submitted ? '已提交' : '要求附件'}/${file.fileName}',
            filePath: '',
            fileUrl: file.fileUrl,
            fileSize: file.fileSize,
            mimeType: file.mimeType,
            timeModifiedEpoch: file.modifiedEpoch,
            sortOrder: filesForReading.length,
            author: '',
            license: '',
          ),
        );
      }
    }
    var source = '';
    int? nextSourcePage;
    if (kind == 'files') {
      source = filesForReading
          .asMap()
          .entries
          .map(
            (e) =>
                '${e.key}: ${e.value.fileName} (${e.value.mimeType}, ${e.value.fileSize})',
          )
          .join('\n');
    } else if (kind == 'file') {
      if (!module.downloadContent) throw StateError('该模块当前不允许读取文件。');
      if (itemId < 0 || itemId >= filesForReading.length) {
        throw StateError('课程文件引用已失效。');
      }
      final file = filesForReading[itemId];
      final key =
          '$moduleRef:$itemId:${file.timeModifiedEpoch}:${file.fileSize}';
      final cached = _documentTextCache[key];
      if (cached != null && _isFresh(cached.$1)) {
        source = cached.$2;
      } else {
        final bytes = await _controller.readAssistantCourseFile(file.fileUrl);
        source = await const AssistantDocumentReader().extract(
          file.fileName,
          bytes,
        );
        if (lease != null && !lease.isActive) throw StateError('登录状态已变化。');
        if (_documentTextCache.length >= 4) {
          _documentTextCache.remove(_documentTextCache.keys.first);
        }
        _documentTextCache[key] = (_now().toUtc(), source);
      }
    } else if (kind == 'quiz' && module.modName == 'quiz') {
      final item = await _controller.resolveAssistantModuleTimelineItem(
        moduleRef,
      );
      final snapshot = await _controller.readAssistantQuizPage(item, itemId);
      source = snapshot.questions
          .map(
            (q) =>
                '${q.number}: ${q.prompt}\n${q.fields.map((f) => '${f.name}: ${f.label}\n${f.options.map((o) => '${o.value}: ${o.label}').join('\n')}').join('\n')}',
          )
          .join('\n\n');
      nextSourcePage = snapshot.nextPage;
      source +=
          '\nnext_page: ${snapshot.nextPage ?? -1}\n${snapshot.accessMessage}';
    } else if (module.modName == 'assign' || module.modName == 'forum') {
      final item = await _controller.resolveAssistantModuleTimelineItem(
        moduleRef,
      );
      final detail = await _controller.loadTimelineDetail(item);
      if (module.modName == 'assign') {
        source = _htmlText(detail.assignmentIntro);
      } else if (itemId == 0) {
        final discussions = await _controller.readAssistantForumPage(
          module.instance,
          page,
        );
        nextSourcePage = discussions.length == 10 ? page + 1 : null;
        source = discussions
            .map((d) => '${d.id}: ${d.subject}\n${_htmlText(d.messagePreview)}')
            .join('\n\n');
      } else {
        final discussions = await _controller.readAssistantForumPage(
          module.instance,
          page,
        );
        if (!discussions.any((d) => d.id == itemId)) {
          throw StateError('讨论不在当前论坛可见列表中。');
        }
        final posts = await _controller.loadForumDiscussionPosts(itemId);
        source = posts
            .map((p) => '${p.author}\n${p.subject}\n${p.message}')
            .join('\n\n');
      }
    } else if (const {'page', 'feedback', 'lesson'}.contains(module.modName)) {
      if (module.modName != 'page') {
        final access = await _controller.loadModuleAccess(
          moduleType: module.modName,
          instanceId: module.instance,
          courseId: course.id,
        );
        if (!access.canRead) throw StateError('学校当前未允许读取该模块内容。');
      }
      source = await _controller.readAssistantModuleText(
        courseId: course.id,
        instanceId: module.instance,
        moduleType: module.modName,
        pageId: itemId,
      );
    } else {
      source = _htmlText(module.descriptionHtml);
    }
    if (lease != null && !lease.isActive) throw StateError('登录状态已变化。');
    final fragment = AssistantContentPage.slice(source, offset);
    final content = AssistantContentPage(
      text: fragment.text,
      offset: fragment.offset,
      totalCharacters: fragment.totalCharacters,
      nextOffset: fragment.nextOffset,
      nextSourcePage: nextSourcePage,
      sourceComplete: nextSourcePage == null,
      state: nextSourcePage != null ? 'truncated' : fragment.state,
    );
    return AssistantIspaceToolResultContext(
      resultKey: 'content:$moduleRef:$kind:$itemId:$page:$offset',
      kind: 'module',
      observedAt: _now().toUtc(),
      courseId: course.id.toString(),
      moduleRef: moduleRef,
      moduleId: module.id.toString(),
      instanceId: module.instance.toString(),
      moduleType: module.modName,
      name: module.name,
      courseName: course.fullName,
      capabilities: const ['module_read'],
      content: content,
      truncated: content.state == 'truncated',
    );
  }

  Future<AssistantIspaceToolResultContext> loadIspaceModule(
    String moduleRef, {
    bool includeContent = true,
  }) async {
    final lease = _controller.captureSessionLease();
    final runtimeProfile = _controller.moodleRuntimeProfile;
    if (runtimeProfile == null ||
        !runtimeProfile.supports(
          MoodleNormalizedCapability.courseCatalogRead,
        )) {
      throw StateError('学校当前未开放 iSpace 课程目录能力。');
    }
    final identity = _parseModuleRef(moduleRef);
    final courseMatches = _controller.courses.where(
      (course) => course.id == identity.$1 && course.visible && !course.hidden,
    );
    if (courseMatches.length != 1) {
      throw StateError('iSpace 课程模块引用已失效。');
    }
    final course = courseMatches.single;
    final sections = await _loadCachedCourseContents(
      course.id,
      onSource: (_) {},
    );
    final moduleMatches = sections
        .expand((section) => section.modules)
        .where(
          (module) =>
              module.id == identity.$2 &&
              module.instance == identity.$3 &&
              module.modName.trim().toLowerCase() == identity.$4,
        )
        .toList(growable: false);
    if (moduleMatches.length != 1) {
      throw StateError('iSpace 课程模块引用已失效。');
    }
    final module = moduleMatches.single;
    if (!module.userVisible ||
        !sections.any(
          (section) => section.userVisible && section.modules.contains(module),
        )) {
      throw StateError('该 iSpace 课程模块当前不可见。');
    }

    final files = module.contents
        .take(8)
        .map(
          (file) => AssistantIspaceFileContext(
            name: _limit(file.fileName, 255),
            mimeType: _limit(file.mimeType, 120),
            sizeBytes: file.fileSize.clamp(0, 2147483647),
            modifiedAt: file.timeModifiedAt,
            author: _limit(file.author, 160),
          ),
        )
        .toList(growable: false);
    var payloadTruncated = module.contents.length > files.length;
    final normalizedRef = _moduleRef(course.id, module);
    if (normalizedRef != moduleRef) {
      throw StateError('iSpace 课程模块引用已变化。');
    }
    final pseudoItem = TimelineItem(
      id: module.id,
      title: module.name,
      activityState: '',
      activityType: module.modName,
      moduleName: module.modName,
      description: _htmlText(module.descriptionHtml),
      courseName: course.fullName,
      courseId: course.id,
      instanceId: module.instance,
      url: module.url,
      sortTime: _moduleDate(module, const ['due', 'close', 'end']),
      formattedTime: '',
      isOverdue: false,
    );

    AssistantIspaceActivityContext? activity;
    AssistantIspaceQuizAttemptContext? quizAttempt;
    MoodleModuleAccessSnapshot? moduleAccess;
    AssistantContentPage? content;
    String? fullContent;
    var accessMessage = '';
    final moduleType = module.modName.trim().toLowerCase();
    if (moduleType == 'assign' &&
        runtimeProfile.supports(MoodleNormalizedCapability.assignmentRead)) {
      try {
        final detail = await _controller.loadTimelineDetail(pseudoItem);
        if (detail.type != TimelineDetailType.assignment ||
            detail.assignmentId <= 0) {
          throw StateError('assignment detail is unavailable');
        }
        payloadTruncated =
            payloadTruncated || detail.submissionFiles.length > 6;
        activity = _moduleActivityContext(
          moduleRef: normalizedRef,
          course: course,
          module: module,
          item: pseudoItem,
          detail: detail,
          files: const [],
        );
      } catch (error) {
        if (_isSessionFailure(error)) rethrow;
        accessMessage = '该作业当前无法通过 iSpace Mobile Service 读取。';
      }
    } else if (moduleType == 'forum' &&
        runtimeProfile.supports(MoodleNormalizedCapability.forumRead)) {
      try {
        final detail = await _controller.loadTimelineDetail(pseudoItem);
        if (detail.type != TimelineDetailType.forum || detail.forumId <= 0) {
          throw StateError('forum detail is unavailable');
        }
        payloadTruncated =
            payloadTruncated ||
            detail.submissionFiles.length > 6 ||
            detail.forumDiscussions.length > 6;
        activity = _moduleActivityContext(
          moduleRef: normalizedRef,
          course: course,
          module: module,
          item: pseudoItem,
          detail: detail,
          files: const [],
        );
      } catch (error) {
        if (_isSessionFailure(error)) rethrow;
        accessMessage = '该论坛当前无法通过 iSpace Mobile Service 读取。';
      }
    } else if (moduleType == 'quiz' &&
        runtimeProfile.supports(MoodleNormalizedCapability.quizRead)) {
      try {
        final snapshot = await _controller.loadQuizAttempt(pseudoItem);
        quizAttempt = _moduleQuizContext(normalizedRef, snapshot);
        accessMessage = quizAttempt.accessMessage;
      } catch (error) {
        if (_isSessionFailure(error)) rethrow;
        accessMessage = '该测验当前无法通过 iSpace Mobile Service 读取。';
      }
    } else if (moduleType == 'choice' &&
        runtimeProfile.supports(MoodleNormalizedCapability.choiceRead)) {
      try {
        moduleAccess = await _controller.loadModuleAccess(
          moduleType: moduleType,
          instanceId: module.instance,
          courseId: course.id,
        );
      } catch (error) {
        if (_isSessionFailure(error)) rethrow;
        accessMessage = '该 Choice 当前无法通过 iSpace Mobile Service 读取。';
      }
    } else if (moduleType == 'feedback' &&
        runtimeProfile.supports(MoodleNormalizedCapability.feedbackRead)) {
      try {
        moduleAccess = await _controller.loadModuleAccess(
          moduleType: moduleType,
          instanceId: module.instance,
          courseId: course.id,
        );
      } catch (error) {
        if (_isSessionFailure(error)) rethrow;
        accessMessage = '该 Feedback 当前无法通过 iSpace Mobile Service 读取。';
      }
    } else if (moduleType == 'lesson' &&
        runtimeProfile.supports(MoodleNormalizedCapability.lessonRead)) {
      try {
        moduleAccess = await _controller.loadModuleAccess(
          moduleType: moduleType,
          instanceId: module.instance,
          courseId: course.id,
        );
      } catch (error) {
        if (_isSessionFailure(error)) rethrow;
        accessMessage = '该 Lesson 当前无法通过 iSpace Mobile Service 读取。';
      }
    }

    // A Feedback module is a questionnaire. Its access flags alone cannot
    // answer a request to read or help answer it, so include its first bounded
    // page alongside the live module state, just as Quiz includes questions.
    if (includeContent &&
        moduleType == 'feedback' &&
        moduleAccess?.canRead == true) {
      try {
        if (!runtimeProfile.supportsFunction('mod_feedback_get_items')) {
          throw StateError('问卷题目读取能力不可用。');
        }
        fullContent = await _controller.readAssistantModuleText(
          courseId: course.id,
          instanceId: module.instance,
          moduleType: moduleType,
        );
        content = AssistantContentPage.slice(fullContent, 0);
      } catch (error) {
        if (_isSessionFailure(error)) rethrow;
        content = const AssistantContentPage(
          text: '',
          offset: 0,
          totalCharacters: 0,
          state: 'unavailable',
          sourceComplete: false,
        );
      }
    }

    final capabilities = <String>{'module_read'};
    if (files.isNotEmpty &&
        module.downloadContent &&
        runtimeProfile.supports(MoodleNormalizedCapability.fileDownload)) {
      capabilities.add('file_download');
    }
    if (module.completionTracking == 1 &&
        module.completionData?.isTrackedUser == true &&
        module.completionData?.userVisible == true &&
        runtimeProfile.supports(
          MoodleNormalizedCapability.completionManualWrite,
        )) {
      capabilities.add('completion_manual_write');
    }
    if (activity != null && moduleType == 'assign') {
      capabilities.add('assignment_read');
      if (activity.canEditSubmission &&
          runtimeProfile.supports(
            MoodleNormalizedCapability.assignmentDraftWrite,
          )) {
        capabilities.add('assignment_draft_write');
      }
      if (activity.canFinalizeSubmission &&
          runtimeProfile.supports(
            MoodleNormalizedCapability.assignmentFinalize,
          )) {
        capabilities.add('assignment_finalize');
      }
    }
    if (activity != null && moduleType == 'forum') {
      capabilities.add('forum_read');
      if (activity.canStartDiscussion &&
          runtimeProfile.supports(MoodleNormalizedCapability.forumWrite)) {
        capabilities.add('forum_write');
      }
    }
    if (quizAttempt != null) {
      capabilities.add('quiz_read');
      if (quizAttempt.canStart &&
          runtimeProfile.supports(MoodleNormalizedCapability.quizStart)) {
        capabilities.add('quiz_start');
      }
      if (quizAttempt.canSave &&
          runtimeProfile.supports(MoodleNormalizedCapability.quizSave)) {
        capabilities.add('quiz_save');
      }
      if (quizAttempt.canFinish &&
          runtimeProfile.supports(MoodleNormalizedCapability.quizFinish)) {
        capabilities.add('quiz_finish');
      }
    }
    if (moduleAccess?.canRead == true) {
      capabilities.add('${moduleType}_read');
      final runtimeWriteEnabled = switch (moduleType) {
        'choice' => runtimeProfile.supports(
          MoodleNormalizedCapability.choiceWrite,
        ),
        'feedback' => runtimeProfile.supports(
          MoodleNormalizedCapability.feedbackWrite,
        ),
        'lesson' => runtimeProfile.supports(
          MoodleNormalizedCapability.lessonWrite,
        ),
        _ => false,
      };
      if (moduleAccess!.canWrite && runtimeWriteEnabled) {
        capabilities.add('${moduleType}_write');
      }
    }

    final description = _htmlText(module.descriptionHtml);
    var summary = activity != null
        ? ''
        : moduleAccess?.statusMessage.trim().isNotEmpty == true
        ? moduleAccess!.statusMessage
        : accessMessage.isNotEmpty
        ? accessMessage
        : description;
    var boundedFiles = files.toList(growable: true);
    var boundedActivity = activity;
    var boundedQuizAttempt = quizAttempt;
    var availabilityInfo = _limit(_htmlText(module.availabilityInfo), 1000);
    var boundedChoiceOptions =
        moduleAccess?.choiceOptions
            .map(
              (option) => AssistantIspaceChoiceOptionContext(
                optionId: option.id.toString(),
                label: _limit(option.label, 500),
                selected: option.selected,
                disabled: option.disabled,
                maxAnswers: option.maxAnswers.clamp(0, 1000000),
              ),
            )
            .toList(growable: true) ??
        <AssistantIspaceChoiceOptionContext>[];
    payloadTruncated =
        payloadTruncated || (moduleAccess?.choiceOptionsTruncated ?? false);

    AssistantIspaceToolResultContext buildResult() =>
        AssistantIspaceToolResultContext(
          resultKey: 'module:$normalizedRef',
          kind: 'module',
          observedAt: _now().toUtc(),
          courseId: course.id.toString(),
          moduleRef: normalizedRef,
          moduleId: module.id.toString(),
          instanceId: module.instance.toString(),
          moduleType: _limit(moduleType, 80),
          name: _limit(module.name, 300),
          courseName: _limit(course.fullName, 240),
          summary: _limit(summary, 4000),
          userVisible: module.userVisible,
          availabilityInfo: availabilityInfo,
          completionTracking: module.completionTracking.clamp(0, 2),
          completionState: (module.completionData?.state ?? 0).clamp(0, 3),
          completedAt: module.completionData?.timeCompletedAt,
          capabilities: capabilities.toList()..sort(),
          files: List.unmodifiable(boundedFiles),
          activity: boundedActivity,
          quizAttempt: boundedQuizAttempt,
          content: content,
          choiceOptions: List.unmodifiable(boundedChoiceOptions),
          choiceAllowMultiple: moduleAccess?.choiceAllowMultiple ?? false,
          choiceAllowUpdate: moduleAccess?.choiceAllowUpdate ?? false,
          truncated:
              payloadTruncated ||
              (boundedQuizAttempt?.truncated ?? false) ||
              content?.state == 'truncated',
        );

    var result = buildResult();
    while (_serializedBytes(result.toJson()) > _maxIspaceToolResultBytes) {
      payloadTruncated = true;
      if (boundedFiles.isNotEmpty) {
        boundedFiles.removeLast();
      } else if (boundedActivity?.forumDiscussions.isNotEmpty == true) {
        final currentActivity = boundedActivity!;
        boundedActivity = _copyIspaceActivity(
          currentActivity,
          forumDiscussions: currentActivity.forumDiscussions
              .take(currentActivity.forumDiscussions.length - 1)
              .toList(growable: false),
        );
      } else if (boundedActivity?.submissionFiles.isNotEmpty == true) {
        final currentActivity = boundedActivity!;
        boundedActivity = _copyIspaceActivity(
          currentActivity,
          submissionFiles: currentActivity.submissionFiles
              .take(currentActivity.submissionFiles.length - 1)
              .toList(growable: false),
        );
      } else if (boundedActivity?.feedbackSummary.isNotEmpty == true) {
        boundedActivity = _copyIspaceActivity(
          boundedActivity!,
          feedbackSummary: '',
        );
      } else if (boundedActivity?.summary.isNotEmpty == true) {
        final currentActivity = boundedActivity!;
        boundedActivity = _copyIspaceActivity(
          currentActivity,
          summary: _shorten(currentActivity.summary),
        );
      } else if (boundedQuizAttempt?.questions.isNotEmpty == true) {
        final currentQuizAttempt = boundedQuizAttempt!;
        boundedQuizAttempt = _copyQuizAttempt(
          currentQuizAttempt,
          questions: currentQuizAttempt.questions
              .take(currentQuizAttempt.questions.length - 1)
              .toList(growable: false),
          truncated: true,
        );
      } else if (boundedChoiceOptions.isNotEmpty) {
        boundedChoiceOptions.removeLast();
      } else if (fullContent != null &&
          content != null &&
          utf8.encode(content.text).length > 4) {
        content = AssistantContentPage.slice(
          fullContent,
          0,
          byteBudget: (utf8.encode(content.text).length ~/ 2).clamp(4, 16000),
        );
      } else if (summary.isNotEmpty) {
        summary = _shorten(summary);
      } else if (availabilityInfo.isNotEmpty) {
        availabilityInfo = _shorten(availabilityInfo);
      } else {
        throw StateError('iSpace 模块结果超过安全上下文大小。');
      }
      result = buildResult();
    }
    if (lease != null && !lease.isActive) throw StateError('登录状态已变化。');
    return result;
  }

  Future<AssistantIspaceToolResultContext> loadIspaceCourseGrades(
    String courseId,
  ) async {
    final runtimeProfile = _controller.moodleRuntimeProfile;
    if (runtimeProfile == null ||
        !runtimeProfile.supports(MoodleNormalizedCapability.gradesRead)) {
      throw StateError('学校当前未开放 iSpace 成绩读取能力。');
    }
    final parsedCourseId = int.tryParse(courseId.trim()) ?? 0;
    final matches = _controller.courses.where(
      (course) =>
          course.id == parsedCourseId && course.visible && !course.hidden,
    );
    if (parsedCourseId <= 0 || matches.length != 1) {
      throw StateError('iSpace 课程标识已失效。');
    }
    final course = matches.single;
    if (!course.showGrades) {
      throw StateError('该课程当前未向学生显示成绩。');
    }
    final snapshot = await _controller.loadCourseGrades(course.id);
    final items = snapshot.items
        .take(64)
        .map((item) {
          final hidden = item.hidden;
          return AssistantIspaceGradeItemContext(
            itemId: item.id.toString(),
            name: _limit(item.name, 300),
            moduleType: _limit(item.moduleType, 80),
            courseModuleId: item.courseModuleId > 0
                ? item.courseModuleId.toString()
                : '',
            grade: hidden ? '' : _limit(item.gradeFormatted, 160),
            range: hidden ? '' : _limit(item.rangeFormatted, 160),
            percentage: hidden ? '' : _limit(item.percentageFormatted, 160),
            feedback: hidden ? '' : _limit(_htmlText(item.feedbackHtml), 2000),
            hidden: hidden,
            locked: item.locked,
            submittedAt: item.submittedAt,
            gradedAt: item.gradedAt,
          );
        })
        .toList(growable: true);
    var truncated = snapshot.items.length > items.length;
    AssistantIspaceToolResultContext buildResult() =>
        AssistantIspaceToolResultContext(
          resultKey: 'course_grades:${course.id}',
          kind: 'course_grades',
          observedAt: _now().toUtc(),
          courseId: course.id.toString(),
          capabilities: const ['grades_read'],
          courseGrades: AssistantIspaceCourseGradesContext(
            courseId: course.id.toString(),
            items: List.unmodifiable(items),
            truncated: truncated,
          ),
          truncated: truncated,
        );
    var result = buildResult();
    while (_serializedBytes(result.toJson()) > _maxIspaceToolResultBytes &&
        items.isNotEmpty) {
      items.removeLast();
      truncated = true;
      result = buildResult();
    }
    if (_serializedBytes(result.toJson()) > _maxIspaceToolResultBytes) {
      throw StateError('iSpace 成绩结果超过安全上下文大小。');
    }
    return result;
  }

  AssistantIspaceActivityContext _moduleActivityContext({
    required String moduleRef,
    required CourseSummary course,
    required CourseModule module,
    required TimelineItem item,
    required TimelineDetailData detail,
    required List<AssistantIspaceFileContext> files,
  }) {
    final submissionFiles = detail.submissionFiles
        .take(8)
        .map(
          (file) => AssistantIspaceFileContext(
            name: _limit(file.fileName, 255),
            mimeType: _limit(file.mimeType, 120),
            sizeBytes: file.fileSize.clamp(0, 2147483647),
            modifiedAt: file.modifiedAt,
            author: '',
          ),
        )
        .toList(growable: false);
    final discussions = detail.forumDiscussions
        .take(6)
        .map(
          (discussion) => AssistantIspaceForumDiscussionContext(
            discussionId: discussion.id.toString(),
            subject: _limit(discussion.subject, 160),
            messagePreview: _limit(_htmlText(discussion.messagePreview), 240),
            author: _limit(discussion.author, 120),
            modifiedAt: discussion.timeModifiedAt,
            replyCount: discussion.replyCount.clamp(0, 1000000),
            pinned: discussion.pinned,
            locked: discussion.locked,
          ),
        )
        .toList(growable: false);
    final description = _htmlText(module.descriptionHtml);
    final summary = detail.assignmentIntro.trim().isNotEmpty
        ? detail.assignmentIntro
        : description.isNotEmpty
        ? description
        : item.description;
    return AssistantIspaceActivityContext(
      itemId: moduleRef,
      courseId: course.id.toString(),
      courseModuleId: module.id.toString(),
      instanceId: module.instance.toString(),
      activityType: _limit(module.modName.trim().toLowerCase(), 80),
      title: _limit(
        detail.assignmentName.trim().isNotEmpty
            ? detail.assignmentName
            : module.name,
        300,
      ),
      courseName: _limit(course.fullName, 240),
      summary: _limit(summary, 2000),
      openAt: detail.openDate ?? _moduleDate(module, const ['open', 'start']),
      dueAt:
          detail.dueDate ?? _moduleDate(module, const ['due']) ?? item.sortTime,
      closeAt: detail.cutoffDate ?? _moduleDate(module, const ['close', 'end']),
      submissionStatus: _limit(detail.submissionStatus, 80),
      canEditSubmission: detail.canEditSubmission,
      supportsFileSubmission: detail.supportsFileSubmission,
      supportsOnlineTextSubmission: detail.supportsOnlineTextSubmission,
      maxFileSubmissions: detail.maxFileSubmissions.clamp(0, 100),
      maxSubmissionSizeBytes: detail.maxSubmissionSizeBytes.clamp(
        0,
        2147483647,
      ),
      files: List.unmodifiable(files),
      gradingStatus: _limit(detail.gradingStatus, 80),
      feedbackSummary: _limit(_htmlText(detail.feedbackSummary), 1000),
      submissionFiles: List.unmodifiable(submissionFiles),
      forumId: detail.forumId > 0 ? detail.forumId.toString() : '',
      forumDiscussions: List.unmodifiable(discussions),
      canStartDiscussion: detail.forumId > 0 && detail.canStartDiscussion,
      submissionDrafts: detail.submissionDrafts,
      requiresSubmissionStatement: detail.requiresSubmissionStatement,
      teamSubmission: detail.teamSubmission,
      requireAllTeamMembersSubmit: detail.requireAllTeamMembersSubmit,
      preventSubmissionNotInGroup: detail.preventSubmissionNotInGroup,
      timeLimitSeconds: detail.timeLimitSeconds.clamp(0, 2147483647),
      submissionsEnabled: detail.submissionsEnabled,
      submissionLocked: detail.submissionLocked,
      canFinalizeSubmission: detail.canFinalizeSubmission,
    );
  }

  AssistantIspaceQuizAttemptContext _moduleQuizContext(
    String moduleRef,
    QuizAttemptSnapshot snapshot,
  ) {
    var remainingFields = 200;
    var remainingOptions = 400;
    final questions = snapshot.questions
        .take(40)
        .map((question) {
          final fields = question.fields
              .take(remainingFields.clamp(0, 20))
              .map((field) {
                remainingFields--;
                final options = field.options
                    .take(remainingOptions.clamp(0, 40))
                    .map((option) {
                      remainingOptions--;
                      return AssistantQuizAnswerOptionContext(
                        value: _limit(option.value, 500),
                        label: _limit(option.label, 500),
                      );
                    })
                    .toList(growable: false);
                return AssistantQuizAnswerFieldContext(
                  name: _limit(field.name, 160),
                  kind: switch (field.kind) {
                    QuizAnswerFieldKind.choice => 'choice',
                    QuizAnswerFieldKind.text => 'text',
                    QuizAnswerFieldKind.select => 'select',
                  },
                  label: _limit(field.label, 500),
                  currentValues: field.currentValues
                      .map((value) => _limit(value, 4000))
                      .take(20)
                      .toList(growable: false),
                  options: options,
                  maxLength: field.maxLength.clamp(1, 4000),
                  multiple: field.multiple,
                );
              })
              .toList(growable: false);
          return AssistantQuizQuestionContext(
            slot: question.slot,
            number: _limit(question.number, 40),
            type: _limit(question.type, 80),
            prompt: _limit(question.prompt, 4000),
            status: _limit(question.status, 120),
            fields: fields,
          );
        })
        .toList(growable: false);
    return AssistantIspaceQuizAttemptContext(
      itemId: moduleRef,
      quizId: snapshot.quizId,
      attemptId: snapshot.attemptId,
      state: _limit(snapshot.state, 80),
      canStart: snapshot.canStart,
      canSave: snapshot.canSave,
      canFinish: snapshot.canFinish,
      accessMessage: _limit(snapshot.accessMessage, 1000),
      questions: List.unmodifiable(questions),
      truncated:
          snapshot.truncated || questions.length < snapshot.questions.length,
    );
  }

  AssistantIspaceActivityContext _copyIspaceActivity(
    AssistantIspaceActivityContext source, {
    String? summary,
    String? feedbackSummary,
    List<AssistantIspaceFileContext>? submissionFiles,
    List<AssistantIspaceForumDiscussionContext>? forumDiscussions,
  }) {
    return AssistantIspaceActivityContext(
      itemId: source.itemId,
      courseId: source.courseId,
      courseModuleId: source.courseModuleId,
      instanceId: source.instanceId,
      activityType: source.activityType,
      title: source.title,
      courseName: source.courseName,
      summary: summary ?? source.summary,
      openAt: source.openAt,
      dueAt: source.dueAt,
      closeAt: source.closeAt,
      submissionStatus: source.submissionStatus,
      canEditSubmission: source.canEditSubmission,
      supportsFileSubmission: source.supportsFileSubmission,
      supportsOnlineTextSubmission: source.supportsOnlineTextSubmission,
      maxFileSubmissions: source.maxFileSubmissions,
      maxSubmissionSizeBytes: source.maxSubmissionSizeBytes,
      files: source.files,
      gradingStatus: source.gradingStatus,
      feedbackSummary: feedbackSummary ?? source.feedbackSummary,
      submissionFiles: submissionFiles ?? source.submissionFiles,
      forumId: source.forumId,
      forumDiscussions: forumDiscussions ?? source.forumDiscussions,
      canStartDiscussion: source.canStartDiscussion,
      submissionDrafts: source.submissionDrafts,
      requiresSubmissionStatement: source.requiresSubmissionStatement,
      teamSubmission: source.teamSubmission,
      canFinalizeSubmission: source.canFinalizeSubmission,
    );
  }

  AssistantIspaceQuizAttemptContext _copyQuizAttempt(
    AssistantIspaceQuizAttemptContext source, {
    required List<AssistantQuizQuestionContext> questions,
    required bool truncated,
  }) {
    return AssistantIspaceQuizAttemptContext(
      itemId: source.itemId,
      quizId: source.quizId,
      attemptId: source.attemptId,
      state: source.state,
      canStart: source.canStart,
      canSave: source.canSave,
      canFinish: source.canFinish,
      accessMessage: source.accessMessage,
      questions: questions,
      truncated: truncated,
    );
  }

  int _serializedBytes(Map<String, dynamic> value) =>
      utf8.encode(jsonEncode(value)).length;

  String _shorten(String value) {
    if (value.length <= 1) return '';
    return value.substring(0, value.length ~/ 2).trimRight();
  }

  (int, int, int, String) _parseModuleRef(String value) {
    final match = RegExp(
      r'^m1:([1-9][0-9]{0,19}):([1-9][0-9]{0,19}):'
      r'([1-9][0-9]{0,19}):([a-z][a-z0-9_]{0,79})$',
    ).firstMatch(value.trim());
    if (match == null) {
      throw StateError('iSpace 课程模块引用无效。');
    }
    final courseId = int.tryParse(match.group(1)!) ?? 0;
    final moduleId = int.tryParse(match.group(2)!) ?? 0;
    final instanceId = int.tryParse(match.group(3)!) ?? 0;
    if (courseId <= 0 || moduleId <= 0 || instanceId <= 0) {
      throw StateError('iSpace 课程模块引用无效。');
    }
    return (courseId, moduleId, instanceId, match.group(4)!);
  }

  List<CourseSummary> _selectIspaceCourses(String message) {
    final courses = _visibleIspaceCourses();
    final normalized = message.toLowerCase();
    final explicit = _explicitIspaceCourses(message, courses);
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final deadlineCourseIds = _matchingIspaceDeadlines(
      message,
    ).map((item) => item.courseId).toSet();
    if (deadlineCourseIds.isNotEmpty) {
      return courses
          .where((course) => deadlineCourseIds.contains(course.id))
          .toList();
    }
    final requestedYear = _requestedCalendarYear(normalized);
    if (requestedYear != null && _requestsHistoricalCourseScope(normalized)) {
      final yearStart = DateTime.utc(requestedYear);
      final nextYearStart = DateTime.utc(requestedYear + 1);
      final datedMatches = courses.where((course) {
        final start = course.startAt;
        final end = course.endAt;
        if (start == null && end == null) {
          return false;
        }
        final effectiveStart = start ?? end!;
        final effectiveEnd = end ?? start!;
        return effectiveStart.isBefore(nextYearStart) &&
            !effectiveEnd.isBefore(yearStart);
      }).toList();
      final yearTextMatches = courses.where((course) {
        if (course.startAt != null || course.endAt != null) {
          return false;
        }
        final text =
            '${course.fullName} ${course.shortName} ${course.categoryName}';
        return text.contains(requestedYear.toString()) ||
            text.contains('${requestedYear - 1}-$requestedYear') ||
            text.contains('$requestedYear-${requestedYear + 1}');
      }).toList();
      final matches = [...datedMatches, ...yearTextMatches];
      matches.sort(_compareCoursesChronologically);
      return matches;
    }
    if (normalized.contains('上学期') ||
        normalized.contains('上一学期') ||
        normalized.contains('last semester') ||
        normalized.contains('previous term')) {
      final ended =
          courses
              .where((course) => course.endAt?.isBefore(_now()) ?? false)
              .toList()
            ..sort((a, b) => b.endAt!.compareTo(a.endAt!));
      if (ended.isNotEmpty) {
        final cutoff = ended.first.endAt!.subtract(const Duration(days: 180));
        final previousTerm = ended
            .where((course) => course.endAt!.isAfter(cutoff))
            .toList();
        final unknownDates = courses
            .where((course) => course.endAt == null)
            .toList(growable: false);
        return [...previousTerm, ...unknownDates];
      }
    }
    return courses;
  }

  bool hasExplicitIspaceCourseMatch(String message) =>
      _explicitIspaceCourses(message, _visibleIspaceCourses()).isNotEmpty ||
      _matchingIspaceDeadlines(message).isNotEmpty;

  bool hasExplicitIspaceModuleCandidate(String message) {
    if (_matchingIspaceDeadlines(message).isNotEmpty) return true;
    final quotedNames = _quotedIspaceEntityNames(message);
    if (quotedNames.length < 2) return false;
    final courseNames = <String>{};
    for (final course in _visibleIspaceCourses()) {
      courseNames.add(_normalizeCourseSearchText(course.fullName));
      courseNames.add(_normalizeCourseSearchText(course.shortName));
      courseNames.addAll(_courseSearchAliases(course));
    }
    return quotedNames.any(courseNames.contains) &&
        quotedNames.any((name) => !courseNames.contains(name));
  }

  List<CourseSummary> _visibleIspaceCourses() => _controller.courses
      .where((course) => course.id > 0 && course.visible && !course.hidden)
      .take(80)
      .toList();

  List<CourseSummary> _explicitIspaceCourses(
    String message,
    List<CourseSummary> courses,
  ) {
    final normalized = message.toLowerCase();
    final normalizedSearchText = _normalizeCourseSearchText(message);
    final paddedSearchText = ' $normalizedSearchText ';
    final quotedNames = _quotedIspaceEntityNames(message);
    final quotedFullNameMatches = courses.where((course) {
      final full = _normalizeCourseSearchText(course.fullName);
      return full.length >= 3 && quotedNames.contains(full);
    }).toList();
    if (quotedFullNameMatches.isNotEmpty) return quotedFullNameMatches;

    final quotedShortNameMatches = courses.where((course) {
      final short = _normalizeCourseSearchText(course.shortName);
      return short.length >= 3 && quotedNames.contains(short);
    }).toList();
    if (quotedShortNameMatches.isNotEmpty) return quotedShortNameMatches;

    final fullNameMatches = courses.where((course) {
      final full = course.fullName.toLowerCase();
      return full.length >= 3 && normalized.contains(full);
    }).toList();
    if (fullNameMatches.isNotEmpty) return fullNameMatches;

    final shortNameMatches = courses.where((course) {
      final short = course.shortName.toLowerCase();
      return short.length >= 3 && normalized.contains(short);
    }).toList();
    if (shortNameMatches.isNotEmpty) return shortNameMatches;

    final aliasMatches = courses
        .where(
          (course) => _courseSearchAliases(
            course,
          ).any((alias) => paddedSearchText.contains(' $alias ')),
        )
        .toList();
    if (aliasMatches.isNotEmpty) return aliasMatches;

    return courses.where((course) {
      final initialisms = {
        _courseInitialism(course.fullName),
        _courseInitialism(course.shortName),
      }.where((value) => value.length >= 2);
      return initialisms.any((value) => paddedSearchText.contains(' $value '));
    }).toList();
  }

  int? _requestedCalendarYear(String normalized) {
    if (normalized.contains('去年') || normalized.contains('last year')) {
      return _now().year - 1;
    }
    final match = RegExp(r'(?<!\d)(20\d{2})(?!\d)').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    final value = int.tryParse(match.group(1)!);
    if (value == null || value < 2000 || value > _now().year + 1) {
      return null;
    }
    return value;
  }

  bool _requestsHistoricalCourseScope(String normalized) {
    if ([
      '去年',
      '往年',
      '历史课程',
      '以前的课程',
      'last year',
      'past course',
      'historical course',
    ].any(normalized.contains)) {
      return true;
    }
    return RegExp(r'20\d{2}\s*年(?:的)?(?:课程|课件|课程列表)').hasMatch(normalized) ||
        RegExp(
          r'(?:courses?|courseware)\s+(?:in|from)\s+20\d{2}',
        ).hasMatch(normalized);
  }

  int _compareCoursesChronologically(CourseSummary left, CourseSummary right) {
    final leftDate = left.startAt ?? left.endAt;
    final rightDate = right.startAt ?? right.endAt;
    if (leftDate == null && rightDate == null) {
      return left.fullName.compareTo(right.fullName);
    }
    if (leftDate == null) return 1;
    if (rightDate == null) return -1;
    final dateOrder = leftDate.compareTo(rightDate);
    return dateOrder != 0 ? dateOrder : left.fullName.compareTo(right.fullName);
  }

  String _courseInitialism(String value) {
    final words = RegExp(r'[a-z]+')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .where((word) => word.isNotEmpty);
    return words.map((word) => word[0]).join();
  }

  Set<String> _courseSearchAliases(CourseSummary course) {
    final aliases = <String>{};
    void add(String value) {
      final normalized = _normalizeCourseSearchText(value);
      if (normalized.length >= 3) aliases.add(normalized);
    }

    add(course.fullName);
    add(course.shortName);
    for (final value in [course.fullName, course.shortName]) {
      for (final match in RegExp(
        r'\b[A-Za-z]{2,8}\s*-?\s*\d{3,5}[A-Za-z]?\b',
      ).allMatches(value)) {
        add(match.group(0) ?? '');
      }
    }
    var core = course.fullName.replaceFirst(RegExp(r'\s*\[[^\]]*\]\s*$'), '');
    core = core.replaceAll(
      RegExp(
        r'\s*\((?:dr|prof(?:essor)?|mr|mrs|ms)\.?\s+[^)]*\)',
        caseSensitive: false,
      ),
      '',
    );
    add(core);
    var withoutTrailingClass = core;
    while (RegExp(r'\s*\([0-9]+\)\s*$').hasMatch(withoutTrailingClass)) {
      withoutTrailingClass = withoutTrailingClass.replaceFirst(
        RegExp(r'\s*\([0-9]+\)\s*$'),
        '',
      );
      add(withoutTrailingClass);
    }
    return aliases;
  }

  String _normalizeCourseSearchText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _mentionsIspaceEntity(String message, String name) {
    String normalize(String value) => _normalizeCourseSearchText(value)
        .replaceAllMapped(
          RegExp(r'([a-z])([0-9])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([0-9])([a-z])'),
          (match) => '${match[1]} ${match[2]}',
        );
    final normalizedName = normalize(name);
    if (normalizedName.length < 3) return false;
    return RegExp(
      '(^|[^a-z0-9])${RegExp.escape(normalizedName)}(\$|[^a-z0-9])',
    ).hasMatch(normalize(message));
  }

  Iterable<TimelineItem> _matchingIspaceDeadlines(String message) =>
      _controller.timelineItems.where(
        (item) =>
            item.courseId > 0 && _mentionsIspaceEntity(message, item.title),
      );

  Set<String> _quotedIspaceEntityNames(String message) {
    final names = <String>{};
    for (final pattern in <RegExp>[
      RegExp(r'“([^”\n]{1,500})”'),
      RegExp(r'"([^"\n]{1,500})"'),
      RegExp(r'「([^」\n]{1,500})」'),
      RegExp(r'『([^』\n]{1,500})』'),
    ]) {
      for (final match in pattern.allMatches(message)) {
        final normalized = _normalizeCourseSearchText(match.group(1) ?? '');
        if (normalized.isNotEmpty) names.add(normalized);
      }
    }
    return names;
  }

  List<CourseContentSection> _prioritizeIspaceSections(
    List<CourseContentSection> sections,
    Set<String> explicitEntityNames,
  ) {
    if (explicitEntityNames.isEmpty) return sections;
    bool containsExplicitModule(CourseContentSection section) =>
        section.modules.any(
          (module) => explicitEntityNames.contains(
            _normalizeCourseSearchText(module.name),
          ),
        );
    return [
      ...sections.where(containsExplicitModule),
      ...sections.where((section) => !containsExplicitModule(section)),
    ];
  }

  List<CourseModule> _prioritizeIspaceModules(
    List<CourseModule> modules,
    Set<String> explicitEntityNames,
  ) {
    if (explicitEntityNames.isEmpty) return modules;
    bool isExplicit(CourseModule module) =>
        explicitEntityNames.contains(_normalizeCourseSearchText(module.name));
    return [
      ...modules.where(isExplicit),
      ...modules.where((module) => !isExplicit(module)),
    ];
  }

  bool needsIspaceCourseDetails(String message) =>
      _needsIspaceCourseDetails(message);

  bool isReadOnlyVisibleManualCompletionList(String message) {
    final normalized = message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final implicitManualCompletion = RegExp(
      r'(?:(?:需要|得|要).{0,8}(?:我|自己).{0,6}(?:点|手动).{0,4}完成|自己点完成)',
    ).hasMatch(normalized);
    final hasManualCompletion =
        normalized.contains('手动完成') ||
        implicitManualCompletion ||
        [
          'manual completion',
          'manually completed',
          'manually completable',
        ].any(normalized.contains);
    final hasVisibleScope =
        normalized.contains('可见') ||
        normalized.contains('visible') ||
        implicitManualCompletion;
    final hasNameList = [
      '列出',
      '名称',
      '名字',
      '清单',
      '哪些',
      'list',
      'names',
      'which',
    ].any(normalized.contains);
    final activeMutation = RegExp(
      r'(?:标记(?:为|成)?(?:已)?完成|设为(?:已)?完成|取消完成|'
      r'mark.{0,12}(?:complete|done)|set.{0,12}(?:complete|done)|'
      r'change.{0,12}completion)',
      caseSensitive: false,
    ).hasMatch(normalized);
    final explicitlyReadOnly = RegExp(
      r'(?:(?:不要|请勿|不实际|无需).{0,16}(?:修改|标记|设置|完成状态)|'
      r"(?:do not|don't|without).{0,24}(?:change|mark|set|modify))",
      caseSensitive: false,
    ).hasMatch(normalized);
    return hasManualCompletion &&
        hasVisibleScope &&
        hasNameList &&
        (!activeMutation || explicitlyReadOnly);
  }

  AssistantIspaceCatalogDetailLevel ispaceCatalogDetailLevel(
    String message, {
    bool? includeDetails,
  }) {
    if (includeDetails == false) {
      return AssistantIspaceCatalogDetailLevel.summary;
    }
    if (isReadOnlyVisibleManualCompletionList(message)) {
      return AssistantIspaceCatalogDetailLevel.modules;
    }
    final normalized = message.toLowerCase();
    final hasAggregateLanguage =
        [
          '多少',
          '数量',
          '计数',
          '统计',
          '总数',
          '分布',
          '占比',
          '比例',
          '聚合',
          '各有几',
          '分别有几',
          '几种类型',
        ].any(normalized.contains) ||
        RegExp(
          r'\b(?:how many|count|counts|number of|distribution|breakdown|total|percentage|ratio|aggregate|aggregation)\b',
        ).hasMatch(normalized);
    final hasCatalogAggregateScope = [
      '模块',
      '活动',
      '资源',
      '内容',
      '内容类型',
      '完成追踪',
      '手动完成',
      '自动完成',
      '可见模块',
      '隐藏模块',
      'module',
      'activity',
      'resource',
      'completion tracking',
      'manual completion',
      'automatic completion',
    ].any(normalized.contains);
    if (includeDetails != true &&
        !_needsIspaceCourseDetails(message) &&
        !(hasAggregateLanguage && hasCatalogAggregateScope)) {
      return AssistantIspaceCatalogDetailLevel.summary;
    }

    final asksForTeachers = [
      '老师',
      '教师',
      '教授',
      '导师',
      'teacher',
      'professor',
      'instructor',
      'lecturer',
    ].any(normalized.contains);
    final asksForFiles =
        [
          '文件',
          '文件名',
          '文件列表',
          '哪些文件',
          '所有文件',
          '课件',
          '讲义',
          '幻灯片',
          '附件',
          '下载',
          '打包',
          'ppt',
          'pdf',
          'zip',
          'file name',
          'file list',
          'which files',
          'all files',
          'courseware',
          'slides',
          'presentation',
          'attachment',
          'download',
          'package',
        ].any(normalized.contains) ||
        RegExp(r'\bfiles?\b').hasMatch(normalized);
    final asksForModuleRowProperties = [
      '章节',
      '完成跟踪',
      '可见性',
      '是否可见',
      '开放日期',
      '截止日期',
      '开放时间',
      '关闭时间',
      '关闭日期',
      'section',
      'completion tracking',
      'visibility',
      'is visible',
      'open date',
      'close date',
      'opening time',
      'closing time',
    ].any(normalized.contains);
    final asksOnlyForTypes =
        !asksForModuleRowProperties &&
        (RegExp(r'(?:哪些|什么|哪几种).{0,10}(?:模块|活动|资料)?类型').hasMatch(normalized) ||
            RegExp(r'(?:模块|活动).{0,4}类型分布').hasMatch(normalized) ||
            RegExp(
              r'(?:每种|各类).{0,8}类型.{0,8}(?:数量|多少|计数)',
            ).hasMatch(normalized) ||
            (normalized.contains('模块类型') &&
                ['最多', '最少', '排名'].any(normalized.contains)) ||
            RegExp(
              r'\b(?:what|which)\b.{0,24}\b(?:module|activity|resource) types?\b',
            ).hasMatch(normalized) ||
            RegExp(
              r'\b(?:module|activity)[ -]?types? distribution\b',
            ).hasMatch(normalized) ||
            RegExp(
              r'\b(?:each|every)\b.{0,16}\btypes?\b.{0,16}\b(?:count|number)\b',
            ).hasMatch(normalized) ||
            (RegExp(r'\bmodule types?\b').hasMatch(normalized) &&
                RegExp(r'\b(?:most|least|ranking)\b').hasMatch(normalized)));
    final asksForAggregates = asksOnlyForTypes || hasAggregateLanguage;
    final mentionsSpecificModuleRows = [
      '章节',
      '模块',
      '活动',
      '隐藏项',
      '不可见项',
      'section',
      'module',
      'activity',
      'hidden item',
      'inaccessible item',
    ].any(normalized.contains);
    final mentionsModuleRows =
        mentionsSpecificModuleRows ||
        ['目录', 'catalog'].any(normalized.contains);
    final asksForNamedRows =
        !asksOnlyForTypes &&
        mentionsModuleRows &&
        [
          '列出',
          '清单',
          '明细',
          '逐个',
          '每一个',
          '分别是什么',
          '叫什么',
          '哪些模块',
          '哪些活动',
          '隐藏模块有哪些',
          '不可见模块有哪些',
          '名称',
          '名字',
          '例子',
          '示例',
          '举例',
          'list ',
          'which module',
          'which activit',
          'each module',
          'every module',
          'module names',
          'activity names',
          'example',
          'details',
        ].any(normalized.contains);
    final asksForModuleRuntime = needsIspaceModuleRuntimeDetails(message);
    final asksForModules =
        asksForNamedRows ||
        asksForModuleRuntime ||
        mentionsModuleRows ||
        [
          '开放日期',
          '截止日期',
          '开放时间',
          '关闭时间',
          '关闭日期',
          '隐藏模块',
          '不可见模块',
          'open date',
          'close date',
          'opening time',
          'closing time',
          'hidden module',
          'inaccessible module',
        ].any(normalized.contains);

    if (asksForTeachers &&
        (asksForFiles || asksForModuleRuntime || mentionsSpecificModuleRows)) {
      return AssistantIspaceCatalogDetailLevel.full;
    }
    if (asksForTeachers) {
      return AssistantIspaceCatalogDetailLevel.teachers;
    }
    if (asksForFiles) {
      return AssistantIspaceCatalogDetailLevel.files;
    }
    if (asksForAggregates && !asksForNamedRows && !asksForModuleRuntime) {
      return AssistantIspaceCatalogDetailLevel.aggregates;
    }
    if (asksForModules) {
      return AssistantIspaceCatalogDetailLevel.modules;
    }
    return includeDetails == true
        ? AssistantIspaceCatalogDetailLevel.full
        : AssistantIspaceCatalogDetailLevel.modules;
  }

  void _prepareIspaceCatalogCache() {
    final session = _controller.session;
    final owner = _controller.username?.trim().toLowerCase() ?? '';
    final revision = _controller.moodleCatalogRevision;
    if (_catalogCacheInitialized &&
        identical(_catalogCacheSession, session) &&
        _catalogCacheOwner == owner &&
        _catalogCacheRevision == revision) {
      return;
    }
    _catalogCacheEpoch++;
    _courseContentsCache.clear();
    _courseTeachersCache.clear();
    _courseContentsInFlight.clear();
    _courseTeachersInFlight.clear();
    _catalogCacheSession = session;
    _catalogCacheOwner = owner;
    _catalogCacheRevision = revision;
    _catalogCacheInitialized = true;
  }

  bool _isFresh(DateTime storedAt) {
    final age = _now().toUtc().difference(storedAt);
    return !age.isNegative && age <= _ispaceCatalogCacheTtl;
  }

  Future<List<CourseContentSection>> _loadCachedCourseContents(
    int courseId, {
    required void Function(bool cacheHit) onSource,
  }) {
    final lease = _controller.captureSessionLease();
    if (lease != null && !lease.isActive) {
      throw StateError('登录状态已变化，请重试。');
    }
    _prepareIspaceCatalogCache();
    final cached = _courseContentsCache[courseId];
    if (cached != null && _isFresh(cached.storedAt)) {
      onSource(true);
      return Future.value(cached.value);
    }
    _courseContentsCache.remove(courseId);
    final active = _courseContentsInFlight[courseId];
    if (active != null) {
      onSource(true);
      return active;
    }
    onSource(false);
    final epoch = _catalogCacheEpoch;
    late final Future<List<CourseContentSection>> pending;
    pending = _ispaceRequestLimiter
        .run(() {
          if (lease != null && !lease.isActive) {
            throw StateError('登录状态已变化，请重试。');
          }
          return _controller
              .loadCourseContents(courseId)
              .timeout(const Duration(seconds: 10));
        })
        .then((value) {
          final immutable = List<CourseContentSection>.unmodifiable(value);
          if (epoch == _catalogCacheEpoch) {
            _courseContentsCache[courseId] = _TimedCacheEntry(
              value: immutable,
              storedAt: _now().toUtc(),
            );
          }
          return immutable;
        })
        .whenComplete(() {
          if (identical(_courseContentsInFlight[courseId], pending)) {
            _courseContentsInFlight.remove(courseId);
          }
        });
    _courseContentsInFlight[courseId] = pending;
    return pending;
  }

  Future<List<String>> _loadCachedCourseTeachers(
    int courseId, {
    required void Function(bool cacheHit) onSource,
  }) {
    final lease = _controller.captureSessionLease();
    if (lease != null && !lease.isActive) {
      throw StateError('登录状态已变化，请重试。');
    }
    _prepareIspaceCatalogCache();
    final cached = _courseTeachersCache[courseId];
    if (cached != null && _isFresh(cached.storedAt)) {
      onSource(true);
      return Future.value(cached.value);
    }
    _courseTeachersCache.remove(courseId);
    final active = _courseTeachersInFlight[courseId];
    if (active != null) {
      onSource(true);
      return active;
    }
    onSource(false);
    final epoch = _catalogCacheEpoch;
    late final Future<List<String>> pending;
    pending = _ispaceRequestLimiter
        .run(() {
          if (lease != null && !lease.isActive) {
            throw StateError('登录状态已变化，请重试。');
          }
          return _controller
              .loadCourseTeacherNames(courseId)
              .timeout(const Duration(seconds: 10));
        })
        .then((value) {
          final immutable = List<String>.unmodifiable(value);
          if (epoch == _catalogCacheEpoch) {
            _courseTeachersCache[courseId] = _TimedCacheEntry(
              value: immutable,
              storedAt: _now().toUtc(),
            );
          }
          return immutable;
        })
        .whenComplete(() {
          if (identical(_courseTeachersInFlight[courseId], pending)) {
            _courseTeachersInFlight.remove(courseId);
          }
        });
    _courseTeachersInFlight[courseId] = pending;
    return pending;
  }

  bool needsIspaceModuleRuntimeDetails(String message) {
    final normalized = message.toLowerCase();
    final hasAssignmentSignal =
        RegExp(r'\blab\s*\d+\b').hasMatch(normalized) ||
        [
          '作业',
          '提交状态',
          '已提交',
          '草稿',
          '最终提交',
          '迟交',
          'assignment',
          'submission',
          'submitted',
          'draft',
          'finalize',
          'finalise',
          'late submission',
        ].any(normalized.contains);
    return hasAssignmentSignal &&
        [
          '提交状态',
          '已提交',
          '仍可编辑',
          '草稿',
          '最终提交',
          'submission statement',
          '团队作业',
          '作业要求',
          '提交开关',
          '提交锁',
          '分组限制',
          '分组',
          '时间限制',
          '迟交',
          '本机文件',
          '文件预选',
          '打开',
          '入口',
          '标记',
          '题目内容',
          '预计耗时',
          'submission state',
          'submission status',
          'submitted',
          'editable',
          'draft',
          'finalize',
          'finalise',
          'team submission',
          'team assignment',
          'assignment instructions',
          'assignment requirements',
          'submissions enabled',
          'submission locked',
          'group',
          'time limit',
          'late submission',
          'local file',
          'file submission',
          'file limit',
          'maximum files',
          'max files',
          'per-file',
          'open',
          'entry',
          'mark complete',
          'task content',
          'duration',
        ].any(normalized.contains);
  }

  bool needsIspaceCompletionRuntimeDetails(String message) {
    if (isReadOnlyVisibleManualCompletionList(message)) return false;
    return RegExp(
      r'(?:标记(?:为|成)?(?:已)?完成|设为(?:已)?完成|取消完成|'
      r'mark.{0,16}(?:complete|done)|set.{0,16}(?:complete|done)|'
      r'change.{0,16}completion)',
      caseSensitive: false,
    ).hasMatch(message);
  }

  bool _needsIspaceCourseDetails(String message) {
    final normalized = message.toLowerCase();
    if (RegExp(r'\blab\s*\d+\b').hasMatch(normalized)) return true;
    return [
      '老师',
      '教师',
      '教授',
      '导师',
      '课件',
      '讲义',
      '资料',
      '文件',
      '章节',
      '目录',
      '模块',
      '活动',
      '打包',
      '下载',
      'ppt',
      'pptx',
      'pdf',
      '幻灯片',
      'zip',
      'teacher',
      'professor',
      'courseware',
      'course catalog',
      'slides',
      'presentation',
      'material',
      'file',
      'section',
      'module',
      'download',
      '开放日期',
      '截止日期',
      '开放时间',
      '关闭时间',
      '关闭日期',
      '隐藏模块',
      '不可见模块',
      '完成追踪',
      '手动完成',
      '自动完成',
      '证据还缺',
      '证据缺失',
      '缺哪些信息',
      'open date',
      'close date',
      'opening time',
      'closing time',
      'hidden module',
      'inaccessible module',
      'completion tracking',
      'manual completion',
      'automatic completion',
      'missing evidence',
      'evidence gaps',
      'what is missing',
      'assignment',
      'assign',
      'booking',
      'choice',
      'feedback',
      'folder',
      'forum',
      'label',
      'mediasite',
      'page',
      'quiz',
      'resource',
      'url',
    ].any(normalized.contains);
  }

  String _normalizedIspaceModuleType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'assign') return 'assignment';
    if (RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(normalized)) {
      return normalized;
    }
    return 'unknown';
  }

  String _normalizedCompletionTracking(int value) => switch (value) {
    0 => 'none',
    1 => 'manual',
    2 => 'automatic',
    _ => 'unknown',
  };

  bool _isSessionFailure(Object error) {
    final text = error.toString();
    return text.contains('请先登录') || text.contains('登录状态已变化');
  }

  Map<String, Object> _catalogJson(
    List<AssistantIspaceCourseContext> courses,
  ) => {'courses': courses.map((course) => course.toJson()).toList()};

  String _moduleRef(int courseId, CourseModule module) {
    final moduleType = module.modName.trim().toLowerCase();
    if (courseId <= 0 ||
        module.id <= 0 ||
        module.instance <= 0 ||
        !RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(moduleType)) {
      return '';
    }
    return 'm1:$courseId:${module.id}:${module.instance}:$moduleType';
  }

  List<AssistantCourseContext> _courses() {
    final timetableCourses = _controller.timetable?.courses ?? const [];
    if (_controller.courses.isEmpty) {
      return timetableCourses
          .take(24)
          .map(
            (course) => AssistantCourseContext(
              courseId: '',
              name: _limit(
                course.name.isNotEmpty ? course.name : course.code,
                240,
              ),
              teachers: _teacherNames(course.teacher),
            ),
          )
          .where((course) => course.name.isNotEmpty)
          .toList(growable: false);
    }

    return _controller.courses
        .take(24)
        .map(
          (course) => AssistantCourseContext(
            courseId: course.id.toString(),
            name: _limit(course.fullName, 240),
            teachers: const [],
          ),
        )
        .toList(growable: false);
  }

  AssistantTermContext? _term() {
    final timetable = _controller.timetable;
    if (timetable == null || timetable.courses.isEmpty) {
      return null;
    }
    return AssistantTermContext(
      label: _limit(timetable.selectedSemesterName, 160),
      asOf: _now(),
    );
  }

  List<AssistantTermCourseContext> _termCourses() {
    final timetable = _controller.timetable;
    final timetableCourses = timetable?.courses ?? const [];
    final now = _now();
    return timetableCourses
        .take(24)
        .map((course) {
          DateTime? nextStartsAt;
          var nextRoom = '';
          for (final meeting in course.meetings) {
            if (timetable == null) continue;
            final candidate = _nextOccurrence(timetable, now, meeting);
            if (candidate == null) continue;
            if (nextStartsAt == null || candidate.isBefore(nextStartsAt)) {
              nextStartsAt = candidate;
              nextRoom = meeting.room;
            }
          }
          return AssistantTermCourseContext(
            courseId: _moodleCourseIdFor(course),
            name: _limit(
              course.name.isNotEmpty ? course.name : course.code,
              240,
            ),
            teachers: _teacherNames(course.teacher),
            nextStartsAt: nextStartsAt,
            nextRoom: _limit(nextRoom, 80),
          );
        })
        .where((course) => course.name.isNotEmpty)
        .toList(growable: false);
  }

  List<AssistantDeadlineContext> _deadlines() {
    final threshold = _now().subtract(const Duration(hours: 1));
    final items =
        _controller.timelineItems
            .where(
              (item) =>
                  item.sortTime != null && !item.sortTime!.isBefore(threshold),
            )
            .toList(growable: false)
          ..sort((left, right) => left.sortTime!.compareTo(right.sortTime!));
    return items
        .take(40)
        .map(
          (item) => AssistantDeadlineContext(
            itemId: item.id.toString(),
            title: _limit(item.title, 300),
            courseName: _limit(item.courseName, 240),
            activityType: _limit(item.activityType, 80),
            dueAt: item.sortTime!,
            courseId: item.courseId > 0 ? item.courseId.toString() : '',
            courseModuleId: _courseModuleId(item.url),
            instanceId: item.instanceId > 0 ? item.instanceId.toString() : '',
          ),
        )
        .toList(growable: false);
  }

  String _courseModuleId(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    final value = uri?.queryParameters['id']?.trim() ?? '';
    return int.tryParse(value) != null ? value : '';
  }

  String _activityType(TimelineItem item) {
    final module = item.moduleName.trim().toLowerCase();
    if (module.isNotEmpty) return _limit(module, 80);
    final activity = item.activityType.trim().toLowerCase();
    if (activity.isNotEmpty) return _limit(activity, 80);
    final match = RegExp(r'/mod/([^/]+)/').firstMatch(item.url);
    return _limit(match?.group(1) ?? 'unknown', 80);
  }

  String _htmlText(String value) {
    if (value.trim().isEmpty) return '';
    return (html_parser.parseFragment(value).text ?? '').trim();
  }

  DateTime? _moduleDate(CourseModule? module, List<String> terms) {
    if (module == null) return null;
    for (final date in module.dates) {
      final key = '${date.dataId} ${date.label}'.toLowerCase();
      if (terms.any(key.contains) && date.dateTime != null) {
        return date.dateTime;
      }
    }
    return null;
  }

  List<AssistantScheduleContext> _schedule() {
    final now = _now().toUtc();
    final end = now.add(const Duration(days: 7));
    final timetable = _controller.timetable;
    final timetableCourses = timetable?.courses ?? const [];
    final occurrences = <AssistantScheduleContext>[];

    for (final course in timetableCourses) {
      for (final meeting in course.meetings) {
        if (timetable == null) continue;
        final start = _nextOccurrence(timetable, now, meeting);
        if (start == null) continue;
        final finish = start.add(
          Duration(minutes: meeting.endMinutes - meeting.startMinutes),
        );
        if (!finish.isAfter(now) || !start.isBefore(end)) {
          continue;
        }
        occurrences.add(
          AssistantScheduleContext(
            courseId: _moodleCourseIdFor(course),
            courseName: _limit(
              course.name.isNotEmpty ? course.name : course.code,
              240,
            ),
            room: _limit(meeting.room, 80),
            startsAt: start,
            endsAt: finish,
          ),
        );
      }
    }
    final campusNow = toBnbuCampusClock(now);
    final firstCampusDay = DateTime(
      campusNow.year,
      campusNow.month,
      campusNow.day,
    );
    for (final entry
        in _taCourseController?.entries ?? const <TaCourseEntry>[]) {
      if (!entry.isVisibleIn(timetable)) continue;
      for (var offset = 0; offset < 8; offset++) {
        final date = DateTime(
          firstCampusDay.year,
          firstCampusDay.month,
          firstCampusDay.day + offset,
        );
        if (date.weekday != entry.weekday ||
            !entry.appliesToWeek(TaCourseEntry.normalizeWeekStart(date))) {
          continue;
        }
        final start = bnbuCampusClockToUtc(
          date.add(Duration(minutes: entry.startMinutes)),
        );
        final finish = bnbuCampusClockToUtc(
          date.add(Duration(minutes: entry.endMinutes)),
        );
        if (!finish.isAfter(now) || !start.isBefore(end)) continue;
        occurrences.add(
          AssistantScheduleContext(
            courseId: '${entry.isTa ? 'ta' : 'schedule'}:${entry.id}',
            courseName:
                '${entry.kindLabel}：${_limit(entry.resolveCourse(timetable)?.name ?? entry.displayTitle, 220)}',
            room: _limit(entry.displayLocation, 80),
            startsAt: start,
            endsAt: finish,
          ),
        );
      }
    }
    occurrences.sort((left, right) => left.startsAt.compareTo(right.startsAt));
    return occurrences.take(40).toList(growable: false);
  }

  AssistantExamTimetableContext _examTimetable() {
    final timetable = _controller.timetable;
    if (timetable == null) {
      return const AssistantExamTimetableContext(
        semesterId: '',
        semesterName: '',
        availability: 'unavailable',
        entries: [],
      );
    }
    return AssistantExamTimetableContext(
      semesterId: _limit(timetable.selectedSemesterId, 120),
      semesterName: _limit(timetable.selectedSemesterName, 160),
      availability: timetable.examAvailability.name,
      entries: timetable.exams
          .take(40)
          .map(
            (entry) => AssistantExamTimetableEntryContext(
              courseCode: _limit(entry.courseCode, 80),
              courseName: _limit(entry.courseName, 240),
              startsAt: bnbuCampusClockToUtc(entry.startsAt),
              endsAt: bnbuCampusClockToUtc(entry.endsAt),
              room: _limit(entry.room, 80),
              seat: _limit(entry.seat, 80),
              remark: _limit(entry.remark, 240),
            ),
          )
          .toList(growable: false),
    );
  }

  List<Map<String, String>> _fixedScheduleCourses() {
    final timetable = _controller.timetable;
    if (timetable == null) return const [];
    return timetable.courses
        .take(80)
        .map(
          (course) => {
            'key': TaCourseEntry.bindingKey(timetable, course),
            'name': _limit(course.name, 160),
            'code': _limit(course.code, 80),
            'semester_id': _limit(timetable.selectedSemesterId, 120),
          },
        )
        .toList();
  }

  List<AssistantTaCourseContext> _taCourses() {
    final controller = _taCourseController;
    if (controller == null) {
      return const [];
    }
    // The v2 strict server schema cannot represent finite weekly recurrence.
    // Do not present these entries to the agent as unrestricted weekly events.
    // The upcoming-schedule tool uses appliesToWeek and remains available.
    if (controller.entries.any((entry) => entry.activeWeekStarts != null)) {
      throw StateError('按周固定日程请从近期日程查询；修改适用周请打开固定日程管理。');
    }
    final collectionRevision = controller.revision;
    return controller.entries
        .take(24)
        .map(
          (entry) => AssistantTaCourseContext(
            kind: fixedScheduleEnabled ? entry.kind.name : '',
            courseKey: fixedScheduleEnabled ? entry.courseKey : '',
            id: _limit(entry.id, 120),
            title: _limit(entry.title, 160),
            location: _limit(entry.location, 160),
            weekday: entry.weekday,
            startMinutes: entry.startMinutes,
            endMinutes: entry.endMinutes,
            repeatType: entry.repeatType.name,
            weekStart: entry.weekStart == null
                ? null
                : TaCourseEntry.normalizeWeekStart(entry.weekStart!),
            entryRevision: entry.revision,
            collectionRevision: collectionRevision,
          ),
        )
        .toList(growable: false);
  }

  DateTime? _nextOccurrence(
    TimetableData timetable,
    DateTime now,
    TimetableMeeting meeting,
  ) {
    final campusNow = toBnbuCampusClock(now);
    final today = DateTime(campusNow.year, campusNow.month, campusNow.day);
    var day = BnbuAcademicCalendar.nextMeetingDate(
      timetable: timetable,
      meeting: meeting,
      fromCampusDate: today,
    );
    if (day == null) return null;
    var start = bnbuCampusClockToUtc(
      day.add(Duration(minutes: meeting.startMinutes)),
    );
    final finish = bnbuCampusClockToUtc(
      day.add(Duration(minutes: meeting.endMinutes)),
    );
    if (!finish.isAfter(now)) {
      day = BnbuAcademicCalendar.nextMeetingDate(
        timetable: timetable,
        meeting: meeting,
        fromCampusDate: DateTime(day.year, day.month, day.day + 1),
      );
      if (day == null) return null;
      start = bnbuCampusClockToUtc(
        day.add(Duration(minutes: meeting.startMinutes)),
      );
    }
    return start;
  }

  String _moodleCourseIdFor(TimetableCourse timetableCourse) {
    for (final course in _controller.courses) {
      if (_courseMatches(
        fullName: course.fullName,
        shortName: course.shortName,
        candidate: timetableCourse,
      )) {
        return course.id.toString();
      }
    }
    return '';
  }

  bool _courseMatches({
    required String fullName,
    required String shortName,
    required TimetableCourse candidate,
  }) {
    final normalizedFullName = _normalize(fullName);
    final haystack = _normalize('$fullName $shortName');
    final code = _normalize(candidate.code);
    final name = _normalize(candidate.name);
    return (code.isNotEmpty && haystack.contains(code)) ||
        (name.isNotEmpty &&
            (haystack.contains(name) ||
                (normalizedFullName.isNotEmpty &&
                    name.contains(normalizedFullName))));
  }

  List<String> _teacherNames(String source) {
    return source
        .split(RegExp(r'[;/；、\n]+'))
        .map((item) => _limit(item.trim().split(RegExp(r'\s+')).join(' '), 160))
        .where((item) => item.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9㐀-鿿]+'), '');
  }

  String _limit(String value, int maxLength) {
    final normalized = value.trim().split(RegExp(r'\s+')).join(' ');
    return normalized.length <= maxLength
        ? normalized
        : normalized.substring(0, maxLength);
  }
}

class _LoadedIspaceCourse {
  const _LoadedIspaceCourse({
    required this.course,
    required this.sections,
    required this.teachers,
  });

  final CourseSummary course;
  final List<CourseContentSection> sections;
  final List<String> teachers;
}

class _TimedCacheEntry<T> {
  const _TimedCacheEntry({required this.value, required this.storedAt});

  final T value;
  final DateTime storedAt;
}

class _AsyncLimiter {
  _AsyncLimiter(this.maxConcurrent);

  final int maxConcurrent;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() operation) async {
    await _acquire();
    try {
      return await operation();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
