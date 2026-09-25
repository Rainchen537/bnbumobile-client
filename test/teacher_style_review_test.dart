import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/models/teacher_review.dart';
import 'package:bnbu_me/models/teacher_review_reference.dart';
import 'package:bnbu_me/services/teacher_review_service.dart';
import 'package:bnbu_me/services/teacher_review_reference_repository.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/teacher_reviews_section.dart';
import 'package:bnbu_me/widgets/student_review_components.dart';

const render = bool.fromEnvironment('TEACHER_STYLE_PREVIEWS');
const teacher = OfficialTeacherProfile(
  name: '陈老师',
  nameEn: 'Teacher Chen',
  email: 'example@bnbu.edu.cn',
  title: '副教授',
  titleEn: 'Associate Professor',
  position: '',
  office: '',
  telephone: '',
  academicCn: '',
  academicEn: '',
  educationCn: '',
  educationEn: '',
  unitNames: [],
  photoUrl: '',
  profileUrl: 'https://staff.bnbu.edu.cn/example/en',
  sourceUpdatedAt: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!render) return;
    for (final family in ['Ahem', 'Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                await File('/System/Library/Fonts/SFNS.ttf').readAsBytes(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader('StyleCJK')..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '/System/Library/Fonts/STHeiti Light.ttc',
              ).readAsBytes(),
            ),
          ),
        ))
        .load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
          rootBundle.load(
            'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
          ),
        ))
        .load();
  });
  for (final width in [390.0, 900.0, 1440.0, 320.0]) {
    testWidgets(
      'styles support selection clearing and unobserved dimensions at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final service = _Service();
        final english = width == 320;
        final dark = width == 900;
        final theme = dark ? AppTheme.dark : AppTheme.light;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('style-preview'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: Locale(english ? 'en' : 'zh'),
              supportedLocales: BnbuLocalizations.supportedLocales,
              localizationsDelegates: const [
                BnbuLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: render
                  ? theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        fontFamilyFallback: ['StyleCJK'],
                      ),
                    )
                  : theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(english ? 1.8 : 1)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TeacherReviewsSection(
                    teacher: teacher,
                    username: 'v12345678',
                    timetable: null,
                    reviewService: service,
                    referenceRepository: _References(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(StudentReviewRating), findsNothing);
        expect(
          find.byKey(const ValueKey('teacher-style-distribution-rapport')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('teacher-style-distribution-workload')),
          findsNothing,
        );
        if (render) await _save(tester, 'summary-${width.toInt()}');
        await tester.ensureVisible(
          find.byKey(const ValueKey('teacher-review-mine-edit-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('teacher-review-mine-edit-action')),
        );
        await tester.pumpAndSettle();
        if (width < 700) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
          final radius = (sheet.shape! as RoundedRectangleBorder).borderRadius
              .resolve(TextDirection.ltr);
          expect(radius.bottomLeft, Radius.zero);
          expect(radius.bottomRight, Radius.zero);
          expect(radius.topLeft, const Radius.circular(20));
          if (render) await _save(tester, 'keyboard-editor-${width.toInt()}');
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
        }
        final choice = find.byKey(
          const ValueKey('teacher-style-requirements-3'),
        );
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(tester.getRect(choice).height, greaterThanOrEqualTo(44));
        final clear = find.byKey(
          const ValueKey('teacher-style-requirements-clear'),
        );
        await tester.ensureVisible(clear);
        await tester.pumpAndSettle();
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('teacher-style-requirements-clear')),
          findsNothing,
        );
        await tester.tap(choice);
        await tester.pumpAndSettle();
        if (render) {
          await _save(tester, 'editor-${width.toInt()}');
        }
        await tester.tap(find.byKey(const ValueKey('teacher-review-save')));
        await tester.pumpAndSettle();
        expect(service.saved!.styleDimensions, {
          'rapport': 3,
          'requirements': 3,
        });
        expect(service.saved!.toJson().containsKey('overall_rating'), isFalse);
        expect(service.saved!.toJson().containsKey('course_workload'), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  // Widget tests disable platform fallback fonts. Use the loaded local fonts
  // for text spans that rely on the system default, without changing content.
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is RenderParagraph && paragraph.text is TextSpan) {
      final span = paragraph.text as TextSpan;
      if (span.style?.fontFamily == null) {
        paragraph.text = TextSpan(
          text: span.text,
          children: span.children,
          style: (span.style ?? const TextStyle()).copyWith(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['StyleCJK'],
          ),
        );
      }
    }
  }
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('style-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/teacher-style-previews');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _References implements TeacherReviewReferenceRepository {
  @override
  Future<List<TeacherReviewReference>> loadFor({
    required String teacherKey,
    required Iterable<TeacherReviewCourseEvidence> courseEvidence,
  }) async => [];
}

class _Service implements TeacherReviewService {
  TeacherReviewDraft? saved;
  TeacherReviewEntry get review => TeacherReviewEntry.fromJson({
    'id': 'synthetic-review',
    'teacher_key': teacher.reviewKey,
    'review_format': 'style_v1',
    'style_dimensions': {'rapport': 3},
    'comment': '课后交流很耐心，课堂讨论机会多。',
    'course_evidence': [],
    'moderation_status': 'visible',
    'version': 1,
    'updated_at': '2026-09-13T12:00:00Z',
  });
  @override
  Future<TeacherReviewPageData> loadReviews(
    String key, {
    bool courseLinkedOnly = false,
    int offset = 0,
    int limit = 50,
  }) async => TeacherReviewPageData.fromJson({
    'summary': {
      'count': 1,
      'course_linked_count': 0,
      'style_count': 1,
      'style_distribution': {
        'rapport': [0, 0, 1],
      },
    },
    'total': 1,
    'offset': 0,
    'limit': 50,
    'items': [],
  });
  @override
  Future<TeacherReviewMineState> loadMine(String username, String key) async =>
      TeacherReviewMineState(
        review: review,
        suspendedUntil: null,
        canReview: true,
      );
  @override
  Future<TeacherReviewMineState> saveReview(
    String username,
    String key,
    TeacherReviewDraft draft,
  ) async {
    saved = draft;
    return TeacherReviewMineState(
      review: review,
      suspendedUntil: null,
      canReview: true,
    );
  }

  @override
  void dispose() {}
}
