import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/course_grade_data.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/exam_timetable.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/models/moodle_module_access.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/models/timeline_detail_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/services/assistant_context_builder.dart';
import 'package:bnbu_me/services/assistant_context_tool_executor.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/academic_calendar_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'module discovery includes the thirteenth course within bounded concurrency',
    () async {
      final controller = _ContextController(
        courses: [
          for (var i = 1; i <= 13; i++)
            CourseSummary(
              id: i,
              fullName: 'Course $i',
              shortName: 'COMP$i',
              categoryName: 'Computing',
              progress: 0,
            ),
        ],
        timelineItems: const [],
        timetable: null,
        contentLoadDelay: const Duration(milliseconds: 1),
        contentsByCourse: {
          13: [
            CourseContentSection(
              id: 1,
              sectionNum: 1,
              name: 'Week 1',
              summary: '',
              modules: [
                CourseModule(
                  id: 130,
                  instance: 131,
                  name: 'Lab 01',
                  modName: 'assign',
                  descriptionHtml: '',
                  url: '',
                  iconUrl: '',
                  contents: const [],
                  dates: const [],
                ),
              ],
            ),
          ],
        },
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(controller.dispose);
      addTearDown(coordinator.dispose);
      final catalog =
          await AssistantContextBuilder(
            controller: controller,
            coordinator: coordinator,
          ).loadIspaceCourseCatalog(
            '',
            detailLevelOverride: AssistantIspaceCatalogDetailLevel.modules,
          );
      expect(catalog.courses.length, 13);
      expect(catalog.omittedCourseCount, 0);
      expect(
        catalog.courses.last.sections.single.modules.single.moduleRef,
        'm1:13:130:131:assign',
      );
      expect(controller.maxConcurrentSchoolLoads, lessThanOrEqualTo(4));
    },
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'fixed schedules negotiate typed metadata and preserve it through tool merge',
    () async {
      final timetable = TimetableData(
        profile: TimetableProfile(
          studentId: '',
          name: '',
          programme: '',
          year: '',
        ),
        semesters: [],
        selectedSemesterId: 'semester-1',
        selectedSemesterName: 'Semester 1',
        courses: [
          TimetableCourse(
            section: '1',
            category: '',
            code: 'COMP1',
            name: 'Computer Organisation',
            teacher: '',
            meetings: [],
            rooms: [],
            units: '',
            remark: '',
          ),
        ],
      );
      final controller = _ContextController(
        courses: [],
        timelineItems: [],
        timetable: timetable,
      );
      final taCourses = TaCourseController(sessionController: controller);
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        taCourses.dispose();
        coordinator.dispose();
        controller.dispose();
      });
      await taCourses.ensureLoaded();
      final course = timetable.courses.single;
      final entry = TaCourseEntry(
        id: 'bound-ta',
        title: course.name,
        location: 'T1',
        weekday: 2,
        startMinutes: 600,
        endMinutes: 650,
        repeatType: TaCourseRepeatType.weekly,
        kind: FixedScheduleKind.ta,
        courseKey: TaCourseEntry.bindingKey(timetable, course),
        courseCode: course.code,
        semesterId: timetable.selectedSemesterId,
      );
      expect(
        (await taCourses.addEntry(
          entry,
          expectedRevision: taCourses.revision,
        )).isSuccess,
        isTrue,
      );
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        taCourseController: taCourses,
      );
      final legacy = builder.build({AssistantContextSource.taCourses}).toJson();
      expect(legacy.containsKey('fixed_schedule_version'), isFalse);
      builder.fixedScheduleEnabled = true;
      final context = builder.build({AssistantContextSource.taCourses});
      expect(context.fixedScheduleVersion, 2);
      expect(context.fixedScheduleCourses.single['key'], entry.courseKey);
      expect(context.taCourses.single.kind, 'ta');
      final merged = AssistantContextToolExecutor.merge([
        context,
        builder.build({}),
      ]);
      expect(merged.fixedScheduleCourses, context.fixedScheduleCourses);
      expect(merged.toJson()['fixed_schedule_version'], 2);
    },
  );

  test('builder includes only explicitly selected bounded sources', () {
    final now = DateTime.utc(2026, 7, 20);
    final controller = _ContextController(
      courses: [
        CourseSummary(
          id: 42,
          fullName: 'C Language',
          shortName: 'COMP1001',
          categoryName: 'Computing',
          progress: null,
        ),
      ],
      timelineItems: [
        TimelineItem(
          id: 7,
          title: 'Lab assignment',
          activityState: '',
          activityType: 'assign',
          moduleName: 'assign',
          description: '',
          courseName: 'C Language',
          courseId: 42,
          instanceId: 70,
          url: '',
          sortTime: now.add(const Duration(days: 1)),
          formattedTime: '',
          isOverdue: false,
        ),
      ],
      timetable: TimetableData(
        profile: TimetableProfile(
          studentId: '',
          name: '',
          programme: 'CST-S',
          year: '2',
        ),
        semesters: const [],
        selectedSemesterId: 'semester',
        selectedSemesterName: 'Semester',
        courses: [
          TimetableCourse(
            section: '1',
            category: '',
            code: 'COMP1001',
            name: 'C Language',
            teacher: 'Teacher Chen',
            meetings: [
              TimetableMeeting(
                weekday: now.weekday,
                dayLabel: 'Mon',
                startLabel: '09:00',
                endLabel: '10:00',
                startMinutes: 9 * 60,
                endMinutes: 10 * 60,
                room: 'T3-101',
              ),
            ],
            rooms: const ['T3-101'],
            units: '3',
            remark: '',
          ),
        ],
      ),
    );
    final coordinator = AssistantContextCoordinator();
    final registration = coordinator.register(
      AssistantContextContribution(
        currentPage: () => const AssistantCurrentPageContext(
          pageType: 'course',
          title: 'C Language',
          selectedItemId: '42',
        ),
      ),
    );
    addTearDown(() {
      registration.dispose();
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
      now: () => now,
    );

    final payload = builder.build({
      AssistantContextSource.academicProfile,
      AssistantContextSource.courses,
      AssistantContextSource.termCourses,
      AssistantContextSource.schedule,
      AssistantContextSource.currentPage,
    });

    expect(payload.sources, isNot(contains(AssistantContextSource.deadlines)));
    expect(payload.academicProfile?.programmeCode, 'CST-S');
    expect(payload.academicProfile?.year, '2');
    expect(
      payload.toJson()['academic_profile'],
      containsPair('programme_code', 'CST-S'),
    );
    expect(payload.deadlines, isEmpty);
    expect(payload.courses.single.teachers, isEmpty);
    expect(payload.term?.label, 'Semester');
    expect(payload.termCourses.single.teachers, ['Teacher Chen']);
    expect(payload.termCourses.single.courseId, '42');
    expect(payload.termCourses.single.nextRoom, 'T3-101');
    expect(payload.schedule.single.room, 'T3-101');
    expect(payload.schedule.single.courseId, '42');
    expect(payload.schedule.single.startsAt, DateTime.utc(2026, 7, 20, 1));
    expect(payload.schedule.single.endsAt, DateTime.utc(2026, 7, 20, 2));
    expect(payload.currentPage?.selectedItemId, '42');
    expect(
      payload.toJson()['schedule'],
      everyElement(
        allOf(
          containsPair('starts_at', contains('Z')),
          containsPair('ends_at', contains('Z')),
        ),
      ),
    );
  });

  test('timetable-only courses keep text without inventing Moodle IDs', () {
    final now = DateTime.utc(2026, 7, 20);
    final controller = _ContextController(
      courses: const [],
      timelineItems: const [],
      timetable: TimetableData(
        profile: TimetableProfile(
          studentId: '',
          name: '',
          programme: '',
          year: '',
        ),
        semesters: const [],
        selectedSemesterId: 'semester',
        selectedSemesterName: 'Semester',
        courses: [
          TimetableCourse(
            section: '1',
            category: '',
            code: 'UNMATCHED1001',
            name: 'Timetable Only Course',
            teacher: 'Teacher Example',
            meetings: [
              TimetableMeeting(
                weekday: now.weekday,
                dayLabel: 'Mon',
                startLabel: '09:00',
                endLabel: '10:00',
                startMinutes: 9 * 60,
                endMinutes: 10 * 60,
                room: 'T3-101',
              ),
            ],
            rooms: const ['T3-101'],
            units: '3',
            remark: '',
          ),
        ],
      ),
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
      now: () => now,
    );

    final payload = builder.build({
      AssistantContextSource.courses,
      AssistantContextSource.termCourses,
      AssistantContextSource.schedule,
    });

    expect(payload.courses.single.name, 'Timetable Only Course');
    expect(payload.courses.single.courseId, isEmpty);
    expect(payload.termCourses.single.courseId, isEmpty);
    expect(payload.schedule.single.courseName, 'Timetable Only Course');
    expect(payload.schedule.single.courseId, isEmpty);
  });

  test('schedule context follows the academic calendar make-up day', () {
    final now = DateTime.utc(2026, 10, 9, 16);
    final controller = _ContextController(
      courses: const [],
      timelineItems: const [],
      timetable: TimetableData(
        profile: TimetableProfile(
          studentId: '',
          name: '',
          programme: '',
          year: '',
        ),
        semesters: const [],
        selectedSemesterId: '2026-27-s1',
        selectedSemesterName: 'Semester 1 of AY2026-27',
        courses: [
          TimetableCourse(
            section: '1',
            category: '',
            code: 'COMP1001',
            name: 'Monday Course',
            teacher: '',
            meetings: [
              TimetableMeeting(
                weekday: DateTime.monday,
                dayLabel: 'Mon',
                startLabel: '09:00',
                endLabel: '10:00',
                startMinutes: 9 * 60,
                endMinutes: 10 * 60,
                room: 'T3-101',
              ),
            ],
            rooms: const ['T3-101'],
            units: '3',
            remark: '',
          ),
        ],
      ),
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
      now: () => now,
    );

    final payload = builder.build({AssistantContextSource.schedule});

    expect(payload.schedule, hasLength(1));
    expect(payload.schedule.single.courseName, 'Monday Course');
    expect(payload.schedule.single.startsAt, DateTime.utc(2026, 10, 10, 1));
    expect(payload.schedule.single.endsAt, DateTime.utc(2026, 10, 10, 2));
  });

  test(
    'calendar and exam contexts preserve official metadata and availability',
    () async {
      final now = DateTime.utc(2026, 10, 9, 16);
      final controller = _ContextController(
        courses: const [],
        timelineItems: const [],
        timetable: TimetableData(
          profile: TimetableProfile(
            studentId: '',
            name: '',
            programme: '',
            year: '',
          ),
          semesters: const [],
          selectedSemesterId: '2026-27-s1',
          selectedSemesterName: 'Semester 1 of AY2026-27',
          courses: const [],
          examAvailability: ExamTimetableAvailability.empty,
        ),
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        now: () => now,
        calendarBundleLoader: _BundleLoader(),
      );

      final calendar = await builder.loadAcademicCalendar();

      final payload = builder.build({
        AssistantContextSource.academicCalendar,
        AssistantContextSource.examTimetable,
      }, academicCalendar: calendar);

      expect(payload.academicCalendar?.timezone, 'Asia/Shanghai');
      expect(payload.academicCalendar?.events, hasLength(21));
      expect(payload.academicCalendar?.documents, hasLength(2));
      expect(payload.examTimetable?.availability, 'empty');
      expect(payload.examTimetable?.entries, isEmpty);
    },
  );

  test(
    'schedule includes TA occurrences even without an MIS timetable',
    () async {
      final now = DateTime.utc(2026, 8, 9, 1);
      final controller = _ContextController(
        courses: const [],
        timelineItems: const [],
        timetable: null,
      );
      final taCourses = TaCourseController(sessionController: controller);
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        taCourses.dispose();
        coordinator.dispose();
        controller.dispose();
      });
      await taCourses.reload();
      await taCourses.addEntry(
        const TaCourseEntry(
          id: 'ta-weekly',
          title: 'Acceptance TA',
          location: 'Acceptance Room',
          weekday: DateTime.monday,
          startMinutes: 10 * 60,
          endMinutes: 11 * 60,
          repeatType: TaCourseRepeatType.weekly,
        ),
        expectedRevision: 0,
      );
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        taCourseController: taCourses,
        now: () => now,
      );

      expect(
        builder.availableSources(),
        contains(AssistantContextSource.schedule),
      );
      final payload = builder.build({AssistantContextSource.schedule});
      expect(payload.schedule, hasLength(1));
      expect(payload.schedule.single.courseId, 'schedule:ta-weekly');
      expect(payload.schedule.single.courseName, '日程：Acceptance TA');
      expect(payload.schedule.single.room, 'Acceptance Room');
      expect(payload.schedule.single.startsAt, DateTime.utc(2026, 8, 10, 2));
    },
  );

  test(
    'TA occurrences stay on their own weekday across MIS make-up days',
    () async {
      final now = DateTime.utc(2026, 10, 9, 16);
      final controller = _ContextController(
        courses: const [],
        timelineItems: const [],
        timetable: TimetableData(
          profile: TimetableProfile(
            studentId: '',
            name: '',
            programme: '',
            year: '',
          ),
          semesters: const [],
          selectedSemesterId: '2026-27-s1',
          selectedSemesterName: 'Semester 1 of AY2026-27',
          courses: [
            TimetableCourse(
              section: '1',
              category: '',
              code: 'COMP1001',
              name: 'MIS Monday Course',
              teacher: '',
              meetings: [
                TimetableMeeting(
                  weekday: DateTime.monday,
                  dayLabel: 'Mon',
                  startLabel: '09:00',
                  endLabel: '10:00',
                  startMinutes: 9 * 60,
                  endMinutes: 10 * 60,
                  room: 'T3-101',
                ),
              ],
              rooms: const ['T3-101'],
              units: '3',
              remark: '',
            ),
          ],
        ),
      );
      final taCourses = TaCourseController(sessionController: controller);
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        taCourses.dispose();
        coordinator.dispose();
        controller.dispose();
      });
      await taCourses.reload();
      await taCourses.addEntry(
        const TaCourseEntry(
          id: 'ta-monday',
          title: 'TA Monday Course',
          location: 'B201',
          weekday: DateTime.monday,
          startMinutes: 10 * 60,
          endMinutes: 11 * 60,
          repeatType: TaCourseRepeatType.weekly,
        ),
        expectedRevision: 0,
      );
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        taCourseController: taCourses,
        now: () => now,
      );

      final schedule = builder.build({
        AssistantContextSource.schedule,
      }).schedule;

      expect(
        schedule
            .singleWhere((entry) => entry.courseName == 'MIS Monday Course')
            .startsAt,
        DateTime.utc(2026, 10, 10, 1),
      );
      expect(
        schedule
            .singleWhere((entry) => entry.courseId == 'schedule:ta-monday')
            .startsAt,
        DateTime.utc(2026, 10, 12, 2),
      );
    },
  );

  test(
    'exam context remains unavailable when timetable loading has no data',
    () {
      final controller = _ContextController(
        courses: const [],
        timelineItems: const [],
        timetable: null,
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final payload = builder.build({AssistantContextSource.examTimetable});

      expect(payload.examTimetable?.availability, 'unavailable');
      expect(payload.examTimetable?.entries, isEmpty);
    },
  );

  test(
    'available MIS exams serialize exact campus times and bounded fields',
    () {
      final controller = _ContextController(
        courses: const [],
        timelineItems: const [],
        timetable: TimetableData(
          profile: TimetableProfile(
            studentId: '',
            name: '',
            programme: '',
            year: '',
          ),
          semesters: const [],
          selectedSemesterId: '2026-27-s1',
          selectedSemesterName: 'Semester 1 of AY2026-27',
          courses: const [],
          examAvailability: ExamTimetableAvailability.available,
          exams: [
            ExamTimetableEntry(
              courseCode: 'COMP1001',
              courseName: 'Programming',
              date: DateTime(2026, 12, 20),
              startMinutes: 9 * 60,
              endMinutes: 11 * 60,
              room: 'T3-101',
              seat: '18',
              remark: '携带学生证',
            ),
          ],
        ),
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final payload = builder.build({AssistantContextSource.examTimetable});
      final exam = payload.examTimetable!.entries.single;
      final json = payload.toJson();

      expect(payload.examTimetable?.availability, 'available');
      expect(exam.startsAt, DateTime.utc(2026, 12, 20, 1));
      expect(exam.endsAt, DateTime.utc(2026, 12, 20, 3));
      expect(exam.room, 'T3-101');
      expect(exam.seat, '18');
      expect(exam.remark, '携带学生证');
      expect(
        ((json['exam_timetable'] as Map<String, dynamic>)['entries'] as List)
            .single,
        containsPair('starts_at', '2026-12-20T01:00:00.000Z'),
      );
    },
  );

  test(
    'TA schedule keeps an in-progress single week session and excludes stale ones',
    () async {
      final now = DateTime.utc(2026, 7, 20, 2, 30);
      final controller = _ContextController(
        courses: const [],
        timelineItems: const [],
        timetable: null,
      );
      final taCourses = TaCourseController(sessionController: controller);
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        taCourses.dispose();
        coordinator.dispose();
        controller.dispose();
      });
      await taCourses.reload();
      var revision = 0;
      for (final entry in <TaCourseEntry>[
        TaCourseEntry(
          id: 'in-progress',
          title: 'In progress',
          location: 'B201',
          weekday: DateTime.monday,
          startMinutes: 10 * 60,
          endMinutes: 11 * 60,
          repeatType: TaCourseRepeatType.singleWeek,
          weekStart: DateTime(2026, 7, 20),
        ),
        TaCourseEntry(
          id: 'ended',
          title: 'Ended',
          location: 'B202',
          weekday: DateTime.monday,
          startMinutes: 8 * 60,
          endMinutes: 9 * 60,
          repeatType: TaCourseRepeatType.singleWeek,
          weekStart: DateTime(2026, 7, 20),
        ),
        TaCourseEntry(
          id: 'other-week',
          title: 'Other week',
          location: 'B203',
          weekday: DateTime.monday,
          startMinutes: 10 * 60,
          endMinutes: 11 * 60,
          repeatType: TaCourseRepeatType.singleWeek,
          weekStart: DateTime(2026, 7, 13),
        ),
      ]) {
        final result = await taCourses.addEntry(
          entry,
          expectedRevision: revision,
        );
        expect(result.isSuccess, isTrue);
        revision++;
      }
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        taCourseController: taCourses,
        now: () => now,
      );

      final schedule = builder.build({
        AssistantContextSource.schedule,
      }).schedule;

      expect(schedule, hasLength(1));
      expect(schedule.single.courseId, 'schedule:in-progress');
      expect(schedule.single.startsAt, DateTime.utc(2026, 7, 20, 2));
      expect(schedule.single.endsAt, DateTime.utc(2026, 7, 20, 3));
    },
  );

  test('builder exposes bounded TA courses with optimistic revisions', () async {
    final controller = _ContextController(
      courses: const [],
      timelineItems: const [],
      timetable: null,
    );
    final taCourses = TaCourseController(sessionController: controller);
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      taCourses.dispose();
      coordinator.dispose();
      controller.dispose();
    });
    await taCourses.reload();
    final added = await taCourses.addEntry(
      const TaCourseEntry(
        id: 'ta-1',
        title: 'Programming TA',
        location: 'B201',
        weekday: DateTime.tuesday,
        startMinutes: 10 * 60,
        endMinutes: 10 * 60 + 50,
        repeatType: TaCourseRepeatType.weekly,
      ),
      expectedRevision: 0,
    );
    expect(added.isSuccess, isTrue);

    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
      taCourseController: taCourses,
    );

    expect(
      builder.availableSources(),
      contains(AssistantContextSource.taCourses),
    );
    final payload = builder.build({AssistantContextSource.taCourses});
    expect(payload.taCourseCollectionRevision, taCourses.revision);
    expect(payload.taCourses, hasLength(1));
    expect(payload.taCourses.single.id, 'ta-1');
    expect(
      payload.taCourses.single.entryRevision,
      taCourses.entries.single.revision,
    );
    expect(payload.taCourses.single.collectionRevision, taCourses.revision);
    expect(
      payload.toJson(),
      containsPair('ta_course_collection_revision', taCourses.revision),
    );
    await taCourses.updateEntry(
      taCourses.entries.single.copyWith(
        activeWeekStarts: [DateTime(2026, 10, 26)],
      ),
      expectedRevision: taCourses.entries.single.revision,
    );
    expect(
      () => builder.build({AssistantContextSource.taCourses}),
      throwsStateError,
      reason:
          'The strict v2 schema must not describe selected weeks as unlimited recurrence',
    );
  });

  test('loads bounded last-semester teacher and courseware metadata', () async {
    final now = DateTime.utc(2026, 7, 23);
    final controller = _ContextController(
      courses: [
        CourseSummary(
          id: 42,
          fullName: 'C Language',
          shortName: 'COMP1001',
          categoryName: 'Computing',
          progress: 100,
          enableCompletion: true,
          completionUserTracked: true,
          completed: true,
          showGrades: true,
          startAt: DateTime.utc(2026, 1, 10),
          endAt: DateTime.utc(2026, 5, 30),
        ),
        CourseSummary(
          id: 43,
          fullName: 'Current Course',
          shortName: 'COMP2001',
          categoryName: 'Computing',
          progress: 10,
          startAt: DateTime.utc(2026, 7, 1),
          endAt: DateTime.utc(2026, 12, 1),
        ),
      ],
      timelineItems: const [],
      timetable: null,
      teachersByCourse: const {
        42: ['Teacher Chen'],
      },
      contentsByCourse: {
        42: [
          CourseContentSection(
            id: 5,
            sectionNum: 1,
            name: 'Week 1',
            summary: 'not forwarded',
            modules: [
              CourseModule(
                id: 9,
                instance: 10,
                name: 'Lecture slides',
                modName: 'resource',
                url: 'https://ispace.example/course/resource',
                iconUrl: 'https://ispace.example/icon',
                descriptionHtml: '<p>not forwarded</p>',
                contents: [
                  CourseModuleContent(
                    type: 'file',
                    fileName: '01-introduction.pdf',
                    filePath: '/',
                    fileUrl: 'https://ispace.example/pluginfile/secret',
                    fileSize: 2048,
                    mimeType: 'application/pdf',
                    timeModifiedEpoch: 1760000000,
                    sortOrder: 1,
                    author: 'Teacher Chen',
                    license: 'allrightsreserved',
                  ),
                ],
                dates: const [],
                completionTracking: 1,
                completionData: const CourseModuleCompletionData(
                  state: 1,
                  timeCompletedEpoch: 1760000000,
                  overrideBy: 0,
                  valueUsed: true,
                  hasCompletion: true,
                  isAutomatic: false,
                  isTrackedUser: true,
                  userVisible: true,
                ),
                downloadContent: true,
              ),
            ],
          ),
        ],
      },
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
      now: () => now,
    );

    final catalog = await builder.loadIspaceCourseCatalog('列出我上学期课程的老师和课件');
    final payload = builder.build({
      AssistantContextSource.ispaceCourseCatalog,
    }, ispaceCourseCatalog: catalog);
    final encoded = payload.toJson().toString();
    final fullCatalogBytes =
        builder.lastIspaceCatalogDiagnostics!.serializedBytes;

    expect(catalog.courses, hasLength(1));
    expect(catalog.courses.single.courseId, '42');
    expect(catalog.courses.single.progress, 100);
    expect(catalog.courses.single.completionEnabled, isTrue);
    expect(catalog.courses.single.completed, isTrue);
    expect(catalog.courses.single.showGrades, isTrue);
    expect(catalog.courses.single.teachers, ['Teacher Chen']);
    expect(
      catalog.courses.single.sections.single.modules.single.files.single.name,
      '01-introduction.pdf',
    );
    final module = catalog.courses.single.sections.single.modules.single;
    expect(module.moduleRef, 'm1:42:9:10:resource');
    expect(module.instanceId, '10');
    expect(module.completionTracking, 1);
    expect(module.completionState, 1);
    expect(module.canManualComplete, isTrue);
    expect(module.canDownloadFiles, isTrue);

    final moduleResult = await builder.loadIspaceModule(module.moduleRef);
    final modulePayload = builder.build(
      {AssistantContextSource.ispaceToolResults},
      contextVersion: '4',
      ispaceToolResults: [moduleResult],
    );
    expect(moduleResult.resultKey, 'module:m1:42:9:10:resource');
    expect(moduleResult.capabilities, contains('module_read'));
    expect(moduleResult.capabilities, contains('file_download'));
    expect(moduleResult.capabilities, contains('completion_manual_write'));
    expect(modulePayload.toJson()['version'], '4');
    expect(encoded, isNot(contains('pluginfile')));
    expect(encoded, isNot(contains('not forwarded')));
    expect(encoded, isNot(contains('https://')));

    final explicitCatalog = await builder.loadIspaceCourseCatalog(
      'C Language 课程目录里有哪些模块类型？',
    );
    expect(explicitCatalog.courses, hasLength(1));
    expect(explicitCatalog.courses.single.sections, isEmpty);
    expect(explicitCatalog.courses.single.moduleTypeCounts, {'resource': 1});
    expect(controller.contentLoadCount, 1);
    expect(
      builder.lastIspaceCatalogDiagnostics?.detailLevel,
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
    expect(builder.lastIspaceCatalogDiagnostics?.contentCacheHits, 1);
    expect(
      builder.lastIspaceCatalogDiagnostics!.serializedBytes,
      lessThan(fullCatalogBytes),
    );
  });

  test('course grade tool masks hidden values and keeps typed dates', () async {
    final controller = _ContextController(
      courses: [
        CourseSummary(
          id: 42,
          fullName: 'C Language',
          shortName: 'COMP1001',
          categoryName: 'Computing',
          progress: 80,
          showGrades: true,
        ),
      ],
      timelineItems: const [],
      timetable: null,
      gradesByCourse: {
        42: CourseGradeSnapshot(
          courseId: 42,
          items: const [
            CourseGradeItem(
              id: 1,
              name: 'Visible quiz',
              moduleType: 'quiz',
              courseModuleId: 101,
              gradeFormatted: '8.00',
              rangeFormatted: '0–10',
              percentageFormatted: '80%',
              feedbackHtml: '<p>Good work</p>',
              hidden: false,
              locked: true,
              submittedEpoch: 1760000000,
              gradedEpoch: 1760003600,
            ),
            CourseGradeItem(
              id: 2,
              name: 'Hidden assignment',
              moduleType: 'assign',
              courseModuleId: 102,
              gradeFormatted: '99.00',
              rangeFormatted: '0–100',
              percentageFormatted: '99%',
              feedbackHtml: '<p>Secret feedback</p>',
              hidden: true,
              locked: false,
              submittedEpoch: 1760000000,
              gradedEpoch: 1760003600,
            ),
          ],
        ),
      },
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
      now: () => DateTime.utc(2026, 9, 2),
    );

    final result = await builder.loadIspaceCourseGrades('42');

    expect(result.kind, 'course_grades');
    expect(result.courseGrades?.items, hasLength(2));
    expect(result.courseGrades?.items.first.grade, '8.00');
    expect(result.courseGrades?.items.first.feedback, 'Good work');
    expect(result.courseGrades?.items.first.gradedAt, isNotNull);
    expect(result.courseGrades?.items.last.hidden, isTrue);
    expect(result.courseGrades?.items.last.grade, isEmpty);
    expect(result.courseGrades?.items.last.percentage, isEmpty);
    expect(result.courseGrades?.items.last.feedback, isEmpty);
  });

  test(
    'course grade tool rejects a hidden course before reading grades',
    () async {
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 42,
            fullName: 'Hidden course',
            shortName: 'HIDDEN',
            categoryName: 'Current',
            progress: null,
            hidden: true,
            showGrades: true,
          ),
        ],
        timelineItems: const [],
        timetable: null,
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      await expectLater(
        builder.loadIspaceCourseGrades('42'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('v4 grade result truncates before the server 32 KiB boundary', () async {
    final controller = _ContextController(
      courses: [
        CourseSummary(
          id: 42,
          fullName: 'Large grade course',
          shortName: 'LARGE',
          categoryName: 'Current',
          progress: 50,
          showGrades: true,
        ),
      ],
      timelineItems: const [],
      timetable: null,
      gradesByCourse: {
        42: CourseGradeSnapshot(
          courseId: 42,
          items: List.generate(
            64,
            (index) => CourseGradeItem(
              id: index + 1,
              name: 'Assessment ${index + 1}',
              moduleType: 'assign',
              courseModuleId: 100 + index,
              gradeFormatted: '88.00',
              rangeFormatted: '0–100',
              percentageFormatted: '88%',
              feedbackHtml: '<p>${List.filled(1000, '反馈').join()}</p>',
              hidden: false,
              locked: false,
              submittedEpoch: 1760000000,
              gradedEpoch: 1760003600,
            ),
          ),
        ),
      },
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
      now: () => DateTime.utc(2026, 9, 2),
    );

    final result = await builder.loadIspaceCourseGrades('42');
    final encodedBytes = utf8.encode(jsonEncode(result.toJson())).length;

    expect(result.truncated, isTrue);
    expect(result.courseGrades?.truncated, isTrue);
    expect(result.courseGrades!.items.length, lessThan(64));
    expect(encodedBytes, lessThanOrEqualTo(22 * 1024));
  });

  test(
    'choice module result keeps stable option ids and access capability',
    () async {
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 42,
            fullName: 'Course',
            shortName: 'COURSE',
            categoryName: 'Current',
            progress: null,
          ),
        ],
        timelineItems: const [],
        timetable: null,
        contentsByCourse: {
          42: [
            CourseContentSection(
              id: 1,
              sectionNum: 1,
              name: 'Activities',
              summary: '',
              modules: [
                CourseModule(
                  id: 101,
                  instance: 88,
                  name: 'Choose a session',
                  modName: 'choice',
                  url: '',
                  iconUrl: '',
                  descriptionHtml: '',
                  contents: const [],
                  dates: const [],
                ),
              ],
            ),
          ],
        },
        moduleAccessByType: const {
          'choice': MoodleModuleAccessSnapshot(
            moduleType: 'choice',
            canRead: true,
            canWrite: true,
            statusMessage: '',
            choiceAllowMultiple: true,
            choiceAllowUpdate: true,
            choiceOptions: [
              MoodleChoiceOption(
                id: 7,
                label: 'Tuesday',
                selected: false,
                disabled: false,
                maxAnswers: 20,
              ),
            ],
          ),
        },
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final result = await builder.loadIspaceModule('m1:42:101:88:choice');

      expect(result.capabilities, containsAll(['choice_read', 'choice_write']));
      expect(result.choiceOptions.single.optionId, '7');
      expect(result.choiceOptions.single.label, 'Tuesday');
      expect(result.choiceAllowMultiple, isTrue);
      expect(result.choiceAllowUpdate, isTrue);
    },
  );

  test(
    'last-year course list uses historical dates without loading current term',
    () async {
      final now = DateTime.utc(2026, 7, 23);
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 21,
            fullName: 'Academic English',
            shortName: 'ENG1001',
            categoryName: '2025',
            progress: 100,
            startAt: DateTime.utc(2025, 2, 1),
            endAt: DateTime.utc(2025, 6, 30),
          ),
          CourseSummary(
            id: 22,
            fullName: 'C Programming',
            shortName: 'COMP1001',
            categoryName: '2025',
            progress: 100,
            startAt: DateTime.utc(2025, 9, 1),
            endAt: DateTime.utc(2026, 1, 10),
          ),
          CourseSummary(
            id: 23,
            fullName: 'Current Course',
            shortName: 'COMP2001',
            categoryName: '2026',
            progress: 10,
            startAt: DateTime.utc(2026, 2, 1),
            endAt: DateTime.utc(2026, 6, 30),
          ),
        ],
        timelineItems: const [],
        timetable: null,
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        now: () => now,
      );

      final catalog = await builder.loadIspaceCourseCatalog('帮我整理一下去年的课程列表');

      expect(catalog.courses.map((course) => course.courseId), ['21', '22']);
      expect(
        catalog.courses.every((course) => course.sections.isEmpty),
        isTrue,
      );
      expect(catalog.complete, isTrue);
      expect(controller.contentLoadCount, 0);
      expect(controller.teacherLoadCount, 0);
    },
  );

  test(
    'course acronym selects only the matching historical iSpace course',
    () async {
      final now = DateTime.utc(2026, 7, 23);
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 51,
            fullName: 'Object-Oriented Programming',
            shortName: 'COMP2002',
            categoryName: '2025',
            progress: 100,
            startAt: DateTime.utc(2025, 2, 1),
            endAt: DateTime.utc(2025, 6, 30),
          ),
          CourseSummary(
            id: 52,
            fullName: 'Discrete Mathematics',
            shortName: 'MATH2001',
            categoryName: '2025',
            progress: 100,
            startAt: DateTime.utc(2025, 2, 1),
            endAt: DateTime.utc(2025, 6, 30),
          ),
        ],
        timelineItems: const [],
        timetable: null,
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        now: () => now,
      );

      final metadataOnly = await builder.loadIspaceCourseCatalog(
        '好的，帮我把去年 OOP 的课程课件打包',
        includeDetails: false,
      );
      expect(metadataOnly.courses.single.sections, isEmpty);
      expect(controller.contentLoadCount, 0);
      expect(controller.teacherLoadCount, 0);

      final catalog = await builder.loadIspaceCourseCatalog(
        '好的，帮我把去年 OOP 的课程课件打包',
      );

      expect(catalog.courses.map((course) => course.courseId), ['51']);
      expect(controller.contentLoadCount, 1);
      expect(controller.teacherLoadCount, 0);
    },
  );

  test('exact full course name outranks another course initialism', () async {
    final controller = _ContextController(
      courses: [
        CourseSummary(
          id: 61,
          fullName: 'Cost Management',
          shortName: 'BUS3001',
          categoryName: '2026',
          progress: 20,
        ),
        CourseSummary(
          id: 62,
          fullName: 'Operating Systems',
          shortName: 'COMP3002',
          categoryName: '2026',
          progress: 30,
        ),
      ],
      timelineItems: const [],
      timetable: null,
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
    );

    final catalog = await builder.loadIspaceCourseCatalog(
      '“Cost Management”这门课现在是什么结构？',
      includeDetails: false,
    );

    expect(catalog.courses.map((course) => course.courseId), ['61']);
  });

  test('quoted full course name excludes another nested full name', () async {
    final controller = _ContextController(
      courses: [
        CourseSummary(
          id: 63,
          fullName: 'Introduction to Modern Social Theories',
          shortName: 'SOC1006',
          categoryName: '2026',
          progress: 0,
        ),
        CourseSummary(
          id: 64,
          fullName: 'Modern Social Theories',
          shortName: 'SOC2006',
          categoryName: '2026',
          progress: 0,
        ),
      ],
      timelineItems: const [],
      timetable: null,
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
    );

    final catalog = await builder.loadIspaceCourseCatalog(
      '“Introduction to Modern Social Theories”下面有什么？',
      includeDetails: false,
    );

    expect(catalog.courses.map((course) => course.courseId), ['63']);
  });

  test(
    'explicit module is retained ahead of section and module bounds',
    () async {
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 63,
            fullName: 'Late Bound Course',
            shortName: 'LATE63',
            categoryName: '2026',
            progress: 40,
          ),
        ],
        timelineItems: const [],
        timetable: null,
        contentsByCourse: {
          63: List.generate(
            11,
            (sectionIndex) => CourseContentSection(
              id: sectionIndex + 1,
              sectionNum: sectionIndex + 1,
              name: 'Section ${sectionIndex + 1}',
              summary: '',
              modules: List.generate(
                4,
                (moduleIndex) => CourseModule(
                  id: 1000 + sectionIndex * 10 + moduleIndex,
                  instance: 2000 + sectionIndex * 10 + moduleIndex,
                  name: sectionIndex == 10 && moduleIndex == 3
                      ? 'Critical Module'
                      : 'Item $sectionIndex-$moduleIndex',
                  modName: 'page',
                  url: '',
                  iconUrl: '',
                  descriptionHtml: '',
                  contents: const [],
                  dates: const [],
                ),
              ),
            ),
          ),
        },
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final catalog = await builder.loadIspaceCourseCatalog(
        '“Late Bound Course”里的“Critical Module”是什么类型，放在哪段？',
        detailLevelOverride: AssistantIspaceCatalogDetailLevel.modules,
      );

      final course = catalog.courses.single;
      expect(course.sections.first.name, 'Section 11');
      expect(course.sections.first.modules.first.name, 'Critical Module');
      expect(course.moduleCount, 44);
      expect(course.truncated, isTrue);
    },
  );

  test(
    'partial practical course names select both targets and keep inaccessible date evidence',
    () async {
      final closesAt = DateTime.utc(2026, 9, 3, 9);
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 61,
            fullName:
                'Data Structures and Algorithms (1002) (Dr. Example) '
                '[Semester 1 of 2026-2027]',
            shortName: 'COMP2003-1002',
            categoryName: 'Computing',
            progress: 0,
          ),
          CourseSummary(
            id: 62,
            fullName:
                'Data Structures and Algorithm Analysis '
                '[Semester 1 of 2026-2027]',
            shortName: 'COMP2004',
            categoryName: 'Computing',
            progress: 0,
          ),
          CourseSummary(
            id: 63,
            fullName: 'Unrelated Course [Semester 1 of 2026-2027]',
            shortName: 'UNRELATED',
            categoryName: 'Other',
            progress: null,
          ),
        ],
        timelineItems: const [],
        timetable: null,
        contentsByCourse: {
          61: [
            CourseContentSection(
              id: 1,
              sectionNum: 1,
              name: 'Quiz evidence',
              summary: '',
              modules: [
                CourseModule(
                  id: 101,
                  instance: 201,
                  name: 'Post-tutorial Quiz',
                  modName: 'quiz',
                  url: 'https://ispace.example/hidden',
                  iconUrl: '',
                  descriptionHtml: 'must not be forwarded',
                  contents: const [],
                  dates: [
                    CourseModuleDate(
                      label: 'Closes',
                      timestamp: closesAt.millisecondsSinceEpoch ~/ 1000,
                      dataId: 'close',
                    ),
                  ],
                  userVisible: false,
                  availabilityInfo: '<p>Not available to students</p>',
                ),
              ],
            ),
          ],
          62: [
            CourseContentSection(
              id: 2,
              sectionNum: 1,
              name: 'Resources',
              summary: '',
              modules: [
                CourseModule(
                  id: 102,
                  instance: 202,
                  name: 'Lecture folder',
                  modName: 'folder',
                  url: '',
                  iconUrl: '',
                  descriptionHtml: '',
                  contents: const [],
                  dates: const [],
                ),
              ],
            ),
          ],
        },
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final catalog = await builder.loadIspaceCourseCatalog(
        '比较 Data Structures and Algorithms (1002) 与 '
        'Data Structures and Algorithm Analysis 的课程目录和资料类型',
      );

      expect(catalog.courses.map((course) => course.courseId), ['61', '62']);
      expect(controller.contentLoadCount, 2);
      expect(controller.teacherLoadCount, 0);
      final hidden = catalog.courses.first.sections.single.modules.single;
      expect(catalog.courses.first.moduleCount, 1);
      expect(catalog.courses.first.visibleModuleCount, 0);
      expect(catalog.courses.first.moduleTypeCounts, {'quiz': 1});
      expect(catalog.courses.first.visibleModuleTypeCounts, isEmpty);
      expect(catalog.courses.first.completionTrackingCounts, {'none': 1});
      expect(catalog.courses.first.visibleCompletionTrackingCounts, isEmpty);
      expect(catalog.courses.last.moduleCount, 1);
      expect(catalog.courses.last.visibleModuleCount, 1);
      expect(catalog.courses.last.moduleTypeCounts, {'folder': 1});
      expect(catalog.courses.last.visibleModuleTypeCounts, {'folder': 1});
      expect(catalog.courses.last.completionTrackingCounts, {'none': 1});
      expect(catalog.courses.last.visibleCompletionTrackingCounts, {'none': 1});
      expect(hidden.userVisible, isFalse);
      expect(hidden.moduleRef, isEmpty);
      expect(hidden.files, isEmpty);
      expect(hidden.dates.single.label, 'Closes');
      expect(hidden.dates.single.dataId, 'close');
      expect(hidden.dates.single.at, closesAt);
      expect(hidden.availabilityInfo, 'Not available to students');
    },
  );

  test(
    'bare course codes and full names select every comparison target',
    () async {
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 71,
            fullName:
                'COMP1003 Computer Organization [Semester 1 of 2026-2027]',
            shortName: 'COMP1003 26F',
            categoryName: 'Computing',
            progress: 0,
          ),
          CourseSummary(
            id: 72,
            fullName:
                'Data Structures and Algorithm Analysis '
                '[Semester 1 of 2026-2027]',
            shortName: 'COMP2004 26F',
            categoryName: 'Computing',
            progress: 0,
          ),
          CourseSummary(
            id: 73,
            fullName: 'Unrelated Course [Semester 1 of 2026-2027]',
            shortName: 'COMP9999 26F',
            categoryName: 'Other',
            progress: 0,
          ),
        ],
        timelineItems: const [],
        timetable: null,
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final catalog = await builder.loadIspaceCourseCatalog(
        '比较 COMP1003 和 Data Structures and Algorithm Analysis 的资料类型',
        includeDetails: false,
      );

      expect(catalog.courses.map((course) => course.courseId), ['71', '72']);
      expect(controller.contentLoadCount, 0);
      expect(controller.teacherLoadCount, 0);
    },
  );

  test(
    'module aggregates cover details omitted by the section bound',
    () async {
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 81,
            fullName: 'Bounded Catalog',
            shortName: 'BOUND81',
            categoryName: 'Computing',
            progress: null,
          ),
        ],
        timelineItems: const [],
        timetable: null,
        contentsByCourse: {
          81: List.generate(
            11,
            (index) => CourseContentSection(
              id: index + 1,
              sectionNum: index + 1,
              name: 'Section ${index + 1}',
              summary: '',
              userVisible: index != 10,
              modules: [
                CourseModule(
                  id: index + 101,
                  instance: index + 201,
                  name: 'Feedback ${index + 1}',
                  modName: 'feedback',
                  url: '',
                  iconUrl: '',
                  descriptionHtml: '',
                  contents: const [],
                  dates: const [],
                ),
              ],
            ),
          ),
        },
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final catalog = await builder.loadIspaceCourseCatalog(
        'Bounded Catalog 有多少 Feedback 模块？',
      );

      final course = catalog.courses.single;
      expect(course.sections, isEmpty);
      expect(course.truncated, isFalse);
      expect(course.sectionCount, 11);
      expect(course.visibleSectionCount, 10);
      expect(course.moduleCount, 11);
      expect(course.visibleModuleCount, 10);
      expect(course.moduleTypeCounts, {'feedback': 11});
      expect(course.visibleModuleTypeCounts, {'feedback': 10});
      expect(course.completionTrackingCounts, {'none': 11});
      expect(course.visibleCompletionTrackingCounts, {'none': 10});
      expect(
        builder.lastIspaceCatalogDiagnostics?.detailLevel,
        AssistantIspaceCatalogDetailLevel.aggregates,
      );
      expect(builder.lastIspaceCatalogDiagnostics?.teacherNetworkLoads, 0);
    },
  );

  test('catalog detail levels load only the evidence each question needs', () {
    final controller = _ContextController(
      courses: const [],
      timelineItems: const [],
      timetable: null,
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
    );

    expect(
      builder.ispaceCatalogDetailLevel('我现在有哪些课程？'),
      AssistantIspaceCatalogDetailLevel.summary,
    );
    expect(
      builder.ispaceCatalogDetailLevel('统计全部 iSpace 模块类型分布'),
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
    expect(
      builder.ispaceCatalogDetailLevel('统计全部 iSpace 模块的类型分布，按数量列出'),
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
    expect(
      builder.ispaceCatalogDetailLevel('把模块按 Moodle 活动类型统计，列出每种类型和数量。'),
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
    expect(
      builder.ispaceCatalogDetailLevel('按类型统计我的 iSpace 内容'),
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
    expect(
      builder.ispaceCatalogDetailLevel('当前模块类型里数量最多和最少的分别是什么？'),
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
    expect(
      builder.ispaceCatalogDetailLevel('只依据 Assignment 模块类型聚合回答'),
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
    expect(
      builder.ispaceCatalogDetailLevel('列出所有隐藏模块的名称和关闭日期'),
      AssistantIspaceCatalogDetailLevel.modules,
    );
    expect(
      builder.ispaceCatalogDetailLevel('列出 OOP 的 PDF 课件文件名'),
      AssistantIspaceCatalogDetailLevel.files,
    );
    expect(
      builder.ispaceCatalogDetailLevel('每门课分别是哪位老师？'),
      AssistantIspaceCatalogDetailLevel.teachers,
    );
    expect(
      builder.ispaceCatalogDetailLevel('列出每门课老师和 PDF 课件'),
      AssistantIspaceCatalogDetailLevel.full,
    );
    expect(
      builder.ispaceCatalogDetailLevel(
        '列出 OOP 的 PDF 课件文件名',
        includeDetails: false,
      ),
      AssistantIspaceCatalogDetailLevel.summary,
    );
    expect(
      builder.isReadOnlyVisibleManualCompletionList(
        '列出当前支持手动完成的可见模块名称，不要实际修改完成状态。',
      ),
      isTrue,
    );
    expect(
      builder.needsIspaceCompletionRuntimeDetails(
        '请准备把课程里的指定模块标记为完成，展示对象后等待确认。',
      ),
      isTrue,
    );
    expect(
      builder.isReadOnlyVisibleManualCompletionList(
        'List visible module names that support manual completion. Do not change the state.',
      ),
      isTrue,
    );
    expect(
      builder.isReadOnlyVisibleManualCompletionList('哪些东西需要我自己点完成？按课程列一下。'),
      isTrue,
    );
    expect(
      builder.ispaceCatalogDetailLevel('哪些东西需要我自己点完成？按课程列一下。'),
      AssistantIspaceCatalogDetailLevel.modules,
    );
    expect(
      builder.isReadOnlyVisibleManualCompletionList('列出可见的手动完成模块，然后全部标记完成。'),
      isFalse,
    );
  });

  test(
    'manual completion inventory filters before section and module bounds',
    () async {
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 42,
            fullName: 'Course',
            shortName: 'COURSE',
            categoryName: 'Test',
            progress: null,
          ),
        ],
        timelineItems: const [],
        timetable: null,
        contentsByCourse: {
          42: List.generate(
            13,
            (sectionIndex) => CourseContentSection(
              id: sectionIndex + 1,
              sectionNum: sectionIndex + 1,
              name: 'Section ${sectionIndex + 1}',
              summary: '',
              modules: [
                CourseModule(
                  id: 1000 + sectionIndex,
                  instance: 2000 + sectionIndex,
                  name: 'Manual ${sectionIndex + 1}',
                  modName: 'page',
                  url: '',
                  iconUrl: '',
                  descriptionHtml: '',
                  contents: const [],
                  dates: const [],
                  completionTracking: 1,
                  completionData: const CourseModuleCompletionData(
                    state: 0,
                    timeCompletedEpoch: 0,
                    overrideBy: 0,
                    valueUsed: false,
                    hasCompletion: true,
                    isAutomatic: false,
                    isTrackedUser: true,
                    userVisible: true,
                  ),
                ),
                CourseModule(
                  id: 3000 + sectionIndex,
                  instance: 4000 + sectionIndex,
                  name: 'Untracked ${sectionIndex + 1}',
                  modName: 'resource',
                  url: '',
                  iconUrl: '',
                  descriptionHtml: '',
                  contents: const [],
                  dates: const [],
                ),
              ],
            ),
          ),
        },
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final catalog = await builder.loadIspaceCourseCatalog(
        '列出当前支持手动完成的可见模块名称，不要实际修改完成状态。',
      );

      final course = catalog.courses.single;
      expect(course.sections, hasLength(1));
      expect(course.sections.single.sectionId, 'manual-completion');
      expect(course.sections.single.modules, hasLength(13));
      expect(
        course.sections.single.modules.every(
          (module) =>
              module.canManualComplete &&
              module.moduleRef.isEmpty &&
              module.instanceId.isEmpty,
        ),
        isTrue,
      );
      expect(course.truncated, isFalse);
      expect(catalog.complete, isTrue);
      expect(
        builder.lastIspaceCatalogDiagnostics?.detailLevel,
        AssistantIspaceCatalogDetailLevel.modules,
      );
    },
  );

  test('named activity type plus row properties keeps module evidence', () {
    final controller = _ContextController(
      courses: const [],
      timelineItems: const [],
      timetable: null,
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
    );

    expect(
      builder.ispaceCatalogDetailLevel(
        '“Course”里的“Q1”是什么 Moodle 活动类型？在哪个章节？完成跟踪怎么设置？',
        includeDetails: true,
      ),
      AssistantIspaceCatalogDetailLevel.modules,
    );
    expect(
      builder.ispaceCatalogDetailLevel('列出每种活动类型和数量。', includeDetails: true),
      AssistantIspaceCatalogDetailLevel.aggregates,
    );
  });

  test(
    'catalog uses six bounded requests and reuses only fresh revision-scoped results',
    () async {
      var now = DateTime.utc(2026, 9, 3, 8);
      final courses = List.generate(
        10,
        (index) => CourseSummary(
          id: index + 1,
          fullName: 'Course ${index + 1}',
          shortName: 'COURSE${index + 1}',
          categoryName: 'Computing',
          progress: index,
        ),
      );
      final controller = _ContextController(
        courses: courses,
        timelineItems: const [],
        timetable: null,
        contentLoadDelay: const Duration(milliseconds: 20),
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
        now: () => now,
      );

      final first = await builder.loadIspaceCourseCatalog('统计全部 iSpace 模块类型分布');
      expect(first.courses, hasLength(10));
      expect(controller.contentLoadCount, 10);
      expect(controller.teacherLoadCount, 0);
      expect(controller.maxConcurrentSchoolLoads, inInclusiveRange(2, 6));
      expect(builder.lastIspaceCatalogDiagnostics?.contentNetworkLoads, 10);
      expect(builder.lastIspaceCatalogDiagnostics?.contentCacheHits, 0);

      await builder.loadIspaceCourseCatalog('统计全部 iSpace 模块类型分布');
      expect(controller.contentLoadCount, 10);
      expect(builder.lastIspaceCatalogDiagnostics?.contentNetworkLoads, 0);
      expect(builder.lastIspaceCatalogDiagnostics?.contentCacheHits, 10);

      now = now.add(const Duration(minutes: 3));
      await builder.loadIspaceCourseCatalog('统计全部 iSpace 模块类型分布');
      expect(controller.contentLoadCount, 20);

      controller.catalogRevision++;
      await builder.loadIspaceCourseCatalog('统计全部 iSpace 模块类型分布');
      expect(controller.contentLoadCount, 30);
    },
  );

  test(
    'catalog coalesces in-flight loads and never caches a failure',
    () async {
      final course = CourseSummary(
        id: 90,
        fullName: 'Concurrent Catalog',
        shortName: 'CON90',
        categoryName: 'Computing',
        progress: null,
      );
      final controller = _ContextController(
        courses: [course],
        timelineItems: const [],
        timetable: null,
        contentLoadDelay: const Duration(milliseconds: 20),
        contentFailures: 1,
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final failed = await builder.loadIspaceCourseCatalog(
        '统计全部 iSpace 模块类型分布',
      );
      expect(failed.courses, isEmpty);
      expect(failed.failedCourseCount, 1);
      expect(controller.contentLoadCount, 1);

      final recovered = await builder.loadIspaceCourseCatalog(
        '统计全部 iSpace 模块类型分布',
      );
      expect(recovered.courses, hasLength(1));
      expect(recovered.failedCourseCount, 0);
      expect(controller.contentLoadCount, 2);

      builder.invalidateIspaceCatalogCache();
      final concurrent = await Future.wait([
        builder.loadIspaceCourseCatalog('统计全部 iSpace 模块类型分布'),
        builder.loadIspaceCourseCatalog('统计全部 iSpace 模块类型分布'),
      ]);
      expect(
        concurrent.every((catalog) => catalog.courses.length == 1),
        isTrue,
      );
      expect(controller.contentLoadCount, 3);
    },
  );

  test(
    'teacher-only catalog skips course contents and caches contacts',
    () async {
      final controller = _ContextController(
        courses: [
          CourseSummary(
            id: 91,
            fullName: 'Teacher Lookup',
            shortName: 'TEACH91',
            categoryName: 'Computing',
            progress: null,
          ),
        ],
        timelineItems: const [],
        timetable: null,
        teachersByCourse: const {
          91: ['Teacher Example'],
        },
        teacherLoadDelay: const Duration(milliseconds: 1),
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final first = await builder.loadIspaceCourseCatalog('每门课分别是哪位老师？');
      expect(first.courses.single.teachers, ['Teacher Example']);
      expect(first.courses.single.sections, isEmpty);
      expect(first.courses.single.moduleCount, isNull);
      expect(controller.contentLoadCount, 0);
      expect(controller.teacherLoadCount, 1);

      await builder.loadIspaceCourseCatalog('列出所有课程教师');
      expect(controller.teacherLoadCount, 1);
      expect(builder.lastIspaceCatalogDiagnostics?.teacherCacheHits, 1);
    },
  );

  test('a current-year start-date question keeps undated courses', () async {
    final controller = _ContextController(
      courses: [
        CourseSummary(
          id: 71,
          fullName: 'Dated Current Course',
          shortName: 'DATED',
          categoryName: '2026',
          progress: null,
          startAt: DateTime.utc(2026, 8, 27, 16),
        ),
        CourseSummary(
          id: 72,
          fullName: 'Undated Learning Hub',
          shortName: 'HUB',
          categoryName: 'General',
          progress: null,
        ),
      ],
      timelineItems: const [],
      timetable: null,
    );
    final coordinator = AssistantContextCoordinator();
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    final builder = AssistantContextBuilder(
      controller: controller,
      coordinator: coordinator,
    );

    final catalog = await builder.loadIspaceCourseCatalog(
      '按课程开始时间整理：哪些是 2026 年 8 月底新开的？',
      includeDetails: false,
    );

    expect(catalog.courses.map((course) => course.courseId), ['71', '72']);
    expect(catalog.courses.last.startAt, isNull);
  });

  test(
    'loads one exact iSpace activity with all stable ID namespaces',
    () async {
      final item = TimelineItem(
        id: 89055,
        title: 'Step 4: Post-tutorial Quiz',
        activityState: '',
        activityType: 'quiz',
        moduleName: 'quiz',
        description: 'Post-tutorial quiz',
        courseName: 'AIoT',
        courseId: 1531,
        instanceId: 90210,
        url: 'https://ispace.bnbu.edu.cn/mod/quiz/view.php?id=270762',
        sortTime: DateTime.utc(2026, 8, 8),
        formattedTime: '',
        isOverdue: false,
      );
      final controller = _ContextController(
        courses: const [],
        timelineItems: [item],
        timetable: null,
        detail: TimelineDetailData(
          item: item,
          type: TimelineDetailType.generic,
        ),
        contentsByCourse: {
          1531: [
            CourseContentSection(
              id: 1,
              sectionNum: 1,
              name: 'Tutorial',
              summary: '',
              modules: [
                CourseModule(
                  id: 270762,
                  instance: 90210,
                  name: 'Step 4: Post-tutorial Quiz',
                  modName: 'quiz',
                  url: 'https://ispace.bnbu.edu.cn/mod/quiz/view.php?id=270762',
                  iconUrl: '',
                  descriptionHtml: '<p>Complete the post-tutorial quiz.</p>',
                  contents: const [],
                  dates: [
                    CourseModuleDate(
                      label: 'Closes',
                      timestamp:
                          DateTime.utc(2026, 8, 8).millisecondsSinceEpoch ~/
                          1000,
                      dataId: 'close',
                    ),
                  ],
                ),
              ],
            ),
          ],
        },
      );
      final coordinator = AssistantContextCoordinator();
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      final builder = AssistantContextBuilder(
        controller: controller,
        coordinator: coordinator,
      );

      final activity = await builder.loadIspaceActivity('89055');

      expect(activity.itemId, '89055');
      expect(activity.courseId, '1531');
      expect(activity.courseModuleId, '270762');
      expect(activity.instanceId, '90210');
      expect(activity.activityType, 'quiz');
      expect(activity.summary, 'Complete the post-tutorial quiz.');
      expect(activity.closeAt, DateTime.utc(2026, 8, 8));
    },
  );
}

class _BundleLoader implements AcademicCalendarBundleLoader {
  @override
  Future<AcademicCalendarBundle> loadBundle() async =>
      fallbackAcademicCalendarBundle;
}

class _ContextController extends AppSessionController {
  _ContextController({
    required this.courses,
    required this.timelineItems,
    required this.timetable,
    this.teachersByCourse = const {},
    this.contentsByCourse = const {},
    this.gradesByCourse = const {},
    this.moduleAccessByType = const {},
    this.detail,
    this.contentLoadDelay = Duration.zero,
    this.teacherLoadDelay = Duration.zero,
    int contentFailures = 0,
  }) : contentFailuresRemaining = contentFailures;

  @override
  final List<CourseSummary> courses;

  @override
  final List<TimelineItem> timelineItems;

  @override
  final TimetableData? timetable;
  final Map<int, List<String>> teachersByCourse;
  final Map<int, List<CourseContentSection>> contentsByCourse;
  final Map<int, CourseGradeSnapshot> gradesByCourse;
  final Map<String, MoodleModuleAccessSnapshot> moduleAccessByType;
  final TimelineDetailData? detail;
  final Duration contentLoadDelay;
  final Duration teacherLoadDelay;
  int teacherLoadCount = 0;
  int contentLoadCount = 0;
  int activeSchoolLoads = 0;
  int maxConcurrentSchoolLoads = 0;
  int catalogRevision = 0;
  int contentFailuresRemaining;

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  MoodleRuntimeProfile get moodleRuntimeProfile => _testRuntimeProfile();

  @override
  int get moodleCatalogRevision => catalogRevision;

  @override
  Future<List<String>> loadCourseTeacherNames(int courseId) async {
    teacherLoadCount++;
    activeSchoolLoads++;
    if (activeSchoolLoads > maxConcurrentSchoolLoads) {
      maxConcurrentSchoolLoads = activeSchoolLoads;
    }
    try {
      if (teacherLoadDelay > Duration.zero) {
        await Future<void>.delayed(teacherLoadDelay);
      }
      return teachersByCourse[courseId] ?? const [];
    } finally {
      activeSchoolLoads--;
    }
  }

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    contentLoadCount++;
    activeSchoolLoads++;
    if (activeSchoolLoads > maxConcurrentSchoolLoads) {
      maxConcurrentSchoolLoads = activeSchoolLoads;
    }
    try {
      if (contentLoadDelay > Duration.zero) {
        await Future<void>.delayed(contentLoadDelay);
      }
      if (contentFailuresRemaining > 0) {
        contentFailuresRemaining--;
        throw StateError('transient course contents failure');
      }
      return contentsByCourse[courseId] ?? const [];
    } finally {
      activeSchoolLoads--;
    }
  }

  @override
  Future<CourseGradeSnapshot> loadCourseGrades(int courseId) async {
    return gradesByCourse[courseId] ??
        CourseGradeSnapshot(courseId: courseId, items: const []);
  }

  @override
  Future<MoodleModuleAccessSnapshot> loadModuleAccess({
    required String moduleType,
    required int instanceId,
    required int courseId,
  }) async {
    final access = moduleAccessByType[moduleType];
    if (access == null) throw StateError('missing module access fixture');
    return access;
  }

  @override
  Future<TimelineDetailData> loadTimelineDetail(TimelineItem item) async {
    return detail ??
        TimelineDetailData(item: item, type: TimelineDetailType.generic);
  }
}

MoodleRuntimeProfile _testRuntimeProfile() => MoodleRuntimeProfile(
  release: 'test',
  version: 'test',
  functionVersions: {
    for (final function in const [
      'core_enrol_get_users_courses',
      'core_course_get_contents',
      'core_course_get_course_module',
      'core_files_get_files',
      'core_files_get_unused_draft_itemid',
      'core_completion_get_activities_completion_status',
      'core_completion_update_activity_completion_status_manually',
      'gradereport_user_get_grade_items',
      'mod_choice_get_choices_by_courses',
      'mod_choice_get_choice_options',
      'mod_choice_submit_choice_response',
      'mod_quiz_get_quizzes_by_courses',
      'mod_quiz_get_user_attempts',
      'mod_quiz_get_quiz_access_information',
      'mod_quiz_get_attempt_access_information',
      'mod_quiz_get_attempt_data',
    ])
      function: 'test',
  },
  downloadFiles: true,
  uploadFiles: true,
  advancedFeatures: const {'enablecompletion': 1},
  userMaxUploadFileSize: 1048576,
);
