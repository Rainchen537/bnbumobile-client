import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/models/teacher_review.dart';
import 'package:bnbu_me/models/teacher_review_reference.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/services/teacher_review_service.dart';
import 'package:bnbu_me/services/teacher_review_reference_repository.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/teacher_reviews_section.dart';

void main() {
  testWidgets(
    'teacher reviews pin mine, show moderation, filter, and attach timetable course',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeTeacherReviewService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeacherReviewsSection(
                teacher: _teacher(),
                username: 'v12345678',
                timetable: _timetable(),
                reviewService: service,
                referenceRepository: _EmptyReferenceRepository(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('teacher-review-summary')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('teacher-review-mine')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('teacher-review-mine')),
          matching: find.byKey(
            const ValueKey('teacher-review-mine-edit-action'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('teacher-review-edit-action')),
        findsNothing,
      );
      final editRect = tester.getRect(
        find.byKey(const ValueKey('teacher-review-mine-edit-action')),
      );
      expect(editRect.width, greaterThanOrEqualTo(44));
      expect(editRect.height, greaterThanOrEqualTo(44));
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('反馈 5/5'), findsNothing);
      expect(find.text('管理员已隐藏'), findsOneWidget);
      expect(find.text('社区治理'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('teacher-review-00000000-0000-4000-8000-000000000001'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('teacher-review-00000000-0000-4000-8000-000000000002'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('teacher-review-course-filter')),
      );
      await tester.pumpAndSettle();
      expect(service.courseLinkedOnly, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('teacher-review-mine-edit-action')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('teacher-review-editor-modal')),
        findsOneWidget,
      );
      expect(find.textContaining('COMP1001'), findsWidgets);
      expect(find.text('课表匹配'), findsWidgets);
      expect(find.text('反馈质量'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('teacher-style-rapport-3')));
      await tester.tap(find.byKey(const ValueKey('teacher-review-save')));
      await tester.pumpAndSettle();
      expect(service.savedDraft?.courseEvidence.single.courseCode, 'COMP1001');
      expect(service.savedDraft?.expectedVersion, 3);
    },
  );

  testWidgets('teacher review editor is centered and readable in dark mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeTeacherReviewService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view).copyWith(
          textScaler: const TextScaler.linear(1.4),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: TeacherReviewsSection(
                teacher: _teacher(),
                username: 'v12345678',
                timetable: _timetable(),
                reviewService: service,
                referenceRepository: _EmptyReferenceRepository(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('teacher-review-mine-edit-action')),
    );
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('bnbu-adaptive-modal-dialog'));
    expect(dialog, findsOneWidget);
    expect(tester.getRect(dialog).width, lessThanOrEqualTo(680));
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty reviews hide zero score and validate the rating form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _EmptyTeacherReviewService();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherReviewsSection(
              teacher: _teacher(),
              username: 'v12345678',
              timetable: _timetable(),
              reviewService: service,
              referenceRepository: _EmptyReferenceRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('teacher-review-summary')), findsNothing);
    expect(find.text('暂无同学评价'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('teacher-review-empty-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('teacher-review-save')));
    await tester.pumpAndSettle();

    expect(find.text('请选择至少一项课堂体验'), findsOneWidget);
    expect(service.savedDraft, isNull);
  });

  testWidgets(
    'historical reference stays separate from community rating totals',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _EmptyTeacherReviewService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeacherReviewsSection(
                teacher: _teacher(),
                username: 'v12345678',
                timetable: _timetable(),
                reviewService: service,
                referenceRepository: _FakeReferenceRepository(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('历史选课参考'), findsOneWidget);
      expect(find.text('Computing Fundamentals'), findsOneWidget);
      expect(find.textContaining('不计入同学评价评分与数量'), findsOneWidget);
      expect(find.text('课堂练习与期末内容关联较强。'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('teacher-review-summary')),
        findsNothing,
      );
      expect(find.text('暂无同学评价'), findsOneWidget);
    },
  );

  testWidgets('review dossier reflows across compact medium and expanded', (
    tester,
  ) async {
    final service = _FakeTeacherReviewService();
    addTearDown(service.dispose);
    addTearDown(tester.view.reset);

    for (final size in const [
      Size(375, 1000),
      Size(390, 1000),
      Size(768, 1024),
      Size(844, 390),
      Size(1024, 768),
      Size(1440, 1000),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: TeacherReviewsSection(
                teacher: _teacher(),
                username: 'v12345678',
                timetable: _timetable(),
                reviewService: service,
                referenceRepository: _EmptyReferenceRepository(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('teacher-review-summary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'size=$size');
    }
  });

  testWidgets(
    'review dossier derives distribution from a complete legacy page',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeTeacherReviewService(includeRatingCounts: false);
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeacherReviewsSection(
                teacher: _teacher(),
                username: 'v12345678',
                timetable: _timetable(),
                reviewService: service,
                referenceRepository: _EmptyReferenceRepository(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('teacher-review-rating-distribution')),
        findsNothing,
      );
    },
  );
}

OfficialTeacherProfile _teacher() => const OfficialTeacherProfile(
  name: '陈老师',
  nameEn: 'Teacher Chen',
  email: 'teacher.chen@bnbu.edu.cn',
  title: '副教授',
  titleEn: 'Associate Professor',
  position: '',
  office: '',
  telephone: '',
  academicCn: '',
  academicEn: '',
  educationCn: '',
  educationEn: '',
  unitNames: ['理工科技学院'],
  photoUrl: '',
  profileUrl: 'https://staff.bnbu.edu.cn/teacher-chen/en',
  sourceUpdatedAt: null,
);

TimetableData _timetable() => TimetableData(
  profile: TimetableProfile(
    studentId: 'V12345678',
    name: '测试同学',
    programme: 'COMP',
    year: '2',
  ),
  semesters: [
    TimetableSemester(
      id: '2026-S1',
      name: 'Semester 1 of AY2026-27',
      isSelected: true,
    ),
  ],
  selectedSemesterId: '2026-S1',
  selectedSemesterName: 'Semester 1 of AY2026-27',
  courses: [
    TimetableCourse(
      section: '1',
      category: 'Lecture',
      code: 'COMP1001',
      name: 'Computing Fundamentals',
      teacher: '陈老师',
      meetings: const [],
      rooms: const [],
      units: '3',
      remark: '',
    ),
  ],
);

TeacherReviewEntry _review({
  required String id,
  TeacherReviewModerationStatus status = TeacherReviewModerationStatus.visible,
  String hiddenReason = '',
  int version = 1,
}) => TeacherReviewEntry(
  id: id,
  teacherKey: _teacher().reviewKey,
  teacherName: '陈老师',
  teacherNameEn: 'Teacher Chen',
  overallRating: 5,
  teachingEngagement: 5,
  gradingGenerosity: 4,
  attendanceFrequency: 2,
  feedbackQuality: 5,
  courseWorkload: 3,
  comment: '讲解清楚',
  courseLinked: true,
  courseEvidence: const [
    TeacherReviewCourseEvidence(
      courseCode: 'COMP1001',
      courseName: 'Computing Fundamentals',
      semesterId: '2026-S1',
      semesterName: 'Semester 1 of AY2026-27',
    ),
  ],
  moderationStatus: status,
  hiddenReason: hiddenReason,
  version: version,
  createdAt: DateTime(2026, 8, 20),
  updatedAt: DateTime(2026, 8, 24),
);

class _FakeTeacherReviewService implements TeacherReviewService {
  _FakeTeacherReviewService({this.includeRatingCounts = true});

  final bool includeRatingCounts;
  bool courseLinkedOnly = false;
  TeacherReviewDraft? savedDraft;

  @override
  Future<TeacherReviewPageData> loadReviews(
    String teacherKey, {
    bool courseLinkedOnly = false,
    int offset = 0,
    int limit = 50,
  }) async {
    this.courseLinkedOnly = courseLinkedOnly;
    return TeacherReviewPageData(
      summary: TeacherReviewSummary(
        count: 2,
        courseLinkedCount: 2,
        overallRatingCounts: includeRatingCounts
            ? const [0, 0, 0, 1, 1]
            : const [0, 0, 0, 0, 0],
        overallAverage: 4.5,
        teachingEngagementAverage: 4.5,
        gradingGenerosityAverage: 4,
        attendanceFrequencyAverage: 2.5,
        feedbackQualityAverage: 4.5,
        courseWorkloadAverage: 3,
      ),
      total: 2,
      offset: 0,
      limit: 50,
      items: [
        _review(
          id: '00000000-0000-4000-8000-000000000001',
          status: TeacherReviewModerationStatus.hidden,
          hiddenReason: '社区治理',
          version: 3,
        ),
        _review(id: '00000000-0000-4000-8000-000000000002'),
      ],
    );
  }

  @override
  Future<TeacherReviewMineState> loadMine(
    String username,
    String teacherKey,
  ) async => TeacherReviewMineState(
    review: _review(
      id: '00000000-0000-4000-8000-000000000001',
      status: TeacherReviewModerationStatus.hidden,
      hiddenReason: '社区治理',
      version: 3,
    ),
    suspendedUntil: null,
    canReview: true,
  );

  @override
  Future<TeacherReviewMineState> saveReview(
    String username,
    String teacherKey,
    TeacherReviewDraft draft,
  ) async {
    savedDraft = draft;
    return TeacherReviewMineState(
      review: _review(id: '00000000-0000-4000-8000-000000000001', version: 4),
      suspendedUntil: null,
      canReview: true,
    );
  }

  @override
  void dispose() {}
}

class _EmptyTeacherReviewService implements TeacherReviewService {
  TeacherReviewDraft? savedDraft;

  @override
  Future<TeacherReviewPageData> loadReviews(
    String teacherKey, {
    bool courseLinkedOnly = false,
    int offset = 0,
    int limit = 50,
  }) async => const TeacherReviewPageData(
    summary: TeacherReviewSummary(
      count: 0,
      courseLinkedCount: 0,
      overallAverage: null,
      teachingEngagementAverage: null,
      gradingGenerosityAverage: null,
      attendanceFrequencyAverage: null,
      feedbackQualityAverage: null,
      courseWorkloadAverage: null,
    ),
    total: 0,
    offset: 0,
    limit: 50,
    items: [],
  );

  @override
  Future<TeacherReviewMineState> loadMine(
    String username,
    String teacherKey,
  ) async => const TeacherReviewMineState(
    review: null,
    suspendedUntil: null,
    canReview: true,
  );

  @override
  Future<TeacherReviewMineState> saveReview(
    String username,
    String teacherKey,
    TeacherReviewDraft draft,
  ) async {
    savedDraft = draft;
    return const TeacherReviewMineState(
      review: null,
      suspendedUntil: null,
      canReview: true,
    );
  }

  @override
  void dispose() {}
}

class _FakeReferenceRepository implements TeacherReviewReferenceRepository {
  @override
  Future<List<TeacherReviewReference>> loadFor({
    required String teacherKey,
    required Iterable<TeacherReviewCourseEvidence> courseEvidence,
  }) async => [
    TeacherReviewReference(
      id: 'history_test',
      scope: TeacherReviewReferenceScope.teacher,
      teacherKeys: [teacherKey],
      courseCodes: const [],
      courseNames: const ['Computing Fundamentals'],
      sourceLabel: '校园墙历史匿名留言整理',
      sourceUrl: '',
      summary: '整体倾向：正向，样本较少',
      highlights: const ['课堂练习与期末内容关联较强。'],
      curatedAt: DateTime(2026, 8, 29),
    ),
  ];
}

class _EmptyReferenceRepository implements TeacherReviewReferenceRepository {
  @override
  Future<List<TeacherReviewReference>> loadFor({
    required String teacherKey,
    required Iterable<TeacherReviewCourseEvidence> courseEvidence,
  }) async => const [];
}
