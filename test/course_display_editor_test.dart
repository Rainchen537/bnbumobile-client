import 'package:bnbu_me/models/course_display_preferences.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/course_display_preferences_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/course_display_editor.dart';
import 'package:bnbu_me/widgets/bnbu_component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_display_preferences_test.dart' show MemoryCourseStore;

final _courses = List.generate(
  12,
  (i) => CourseSummary(
    id: i + 1,
    fullName: 'Course ${i + 1} — Computer Science and Technology',
    shortName: 'Course ${i + 1}',
    categoryName: '',
    progress: null,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('name edits persist without either confirmation or outer Save', (
    tester,
  ) async {
    final store = MemoryCourseStore();
    final controller = CourseDisplayPreferencesController(store: store);
    await controller.bind('fixture');
    await tester.pumpWidget(_host(controller, 390));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _openRename(tester);
    await tester.enterText(
      find.byKey(const ValueKey('course-display-name')),
      'Auto saved name',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(controller.value.names, {1: 'Auto saved name'});
    expect(
      CourseDisplayPreferences.fromJson(store.local['fixture']!['value']).names,
      {1: 'Auto saved name'},
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    testWidgets('bounded editor rename, reorder, hide, restore at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryCourseStore();
      final controller = CourseDisplayPreferencesController(store: store);
      await controller.bind('fixture');
      await tester.pumpWidget(_host(controller, width));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(CourseDisplayEditor)).height,
        lessThanOrEqualTo(620),
      );
      expect(
        tester.getSize(find.byType(CourseDisplayEditor)).width,
        lessThanOrEqualTo(620),
      );
      expect(
        tester.widget(find.byKey(const ValueKey('course-display-actions-1'))),
        isA<BnbuMenuButton<String>>(),
      );
      expect(find.text(_courses.first.shortName), findsOneWidget);
      expect(find.text(_courses.first.fullName), findsNothing);
      await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename for me'));
      await tester.pumpAndSettle();
      expect(_renameValue(tester), _courses.first.shortName);
      await tester.enterText(
        find.byKey(const ValueKey('course-display-name')),
        'My math',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('My math'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('course-display-editor-2')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('course-display-editor-1')))
              .dy,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide course'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-display-save')));
      await tester.pumpAndSettle();
      expect(controller.value.names, {1: 'My math'});
      expect(controller.value.hidden, {1});
      expect(controller.value.order.take(2), [2, 1]);
      expect(_courses.first.fullName, contains('Computer Science'));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show course'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('course-display-save')));
      await tester.pumpAndSettle();
      expect(controller.value.hidden, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('unchanged list name does not create a personal alias', (
    tester,
  ) async {
    final controller = CourseDisplayPreferencesController(
      store: MemoryCourseStore(),
    );
    await controller.bind('fixture');
    await tester.pumpWidget(_host(controller, 390));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _openRename(tester);
    expect(_renameValue(tester), _courses.first.shortName);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('course-display-save')));
    await tester.pumpAndSettle();
    expect(controller.value.names, isEmpty);
    expect(controller.hasPending, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('missing short name falls back to school full name', (
    tester,
  ) async {
    final controller = CourseDisplayPreferencesController(
      store: MemoryCourseStore(),
    );
    await controller.bind('fixture');
    final course = CourseSummary(
      id: 1,
      fullName: 'School full name',
      shortName: '',
      categoryName: '',
      progress: null,
    );
    await tester.pumpWidget(_host(controller, 390, courses: [course]));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text(course.fullName), findsOneWidget);
    await _openRename(tester);
    expect(_renameValue(tester), course.fullName);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('course-display-save')));
    await tester.pumpAndSettle();
    expect(controller.value.names, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final width in [390.0, 768.0, 1200.0]) {
    for (final restoreByClearing in [false, true]) {
      testWidgets(
        'list rename updates navigation only at $width, clear=$restoreByClearing',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final store = MemoryCourseStore();
          final display = CourseDisplayPreferencesController(store: store);
          await display.bind('fixture');
          final session = _CourseSession();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              locale: const Locale('en'),
              supportedLocales: BnbuLocalizations.supportedLocales,
              localizationsDelegates: const [
                BnbuLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: IspacePage(
                controller: session,
                courseDisplayPreferences: display,
                onGoToUserTab: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> navigation() async {
            if (width < 880) {
              await tester.tap(
                find.byKey(const ValueKey('ispace-top-bar-navigation-button')),
              );
              await tester.pumpAndSettle();
            }
          }

          Future<void> manage() async {
            await navigation();
            await tester.tap(
              find.byKey(const ValueKey('ispace-manage-courses')),
            );
            await tester.pumpAndSettle();
          }

          final row = find.byKey(const ValueKey('ispace-navigation-course-1'));
          await navigation();
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(find.text(_courses.first.fullName), findsOneWidget);

          await manage();
          await _openRename(tester);
          expect(_renameValue(tester), _courses.first.shortName);
          await tester.enterText(
            find.byKey(const ValueKey('course-display-name')),
            'My list name',
          );
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(display.value.names, {
            1: 'My list name',
          }); // Names save without committing the order/visibility draft.
          await tester.tap(find.byKey(const ValueKey('course-display-save')));
          await tester.pumpAndSettle();
          expect(find.text(_courses.first.fullName), findsOneWidget);
          await navigation();
          expect(
            find.descendant(of: row, matching: find.text('My list name')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('ispace-manage-courses')));
          await tester.pumpAndSettle();
          await _openRename(tester);
          expect(_renameValue(tester), 'My list name');
          await tester.enterText(
            find.byKey(const ValueKey('course-display-name')),
            'Automatically saved name',
          );
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(display.value.names, {1: 'Automatically saved name'});
          if (restoreByClearing) {
            await _openRename(tester);
            await tester.enterText(
              find.byKey(const ValueKey('course-display-name')),
              '',
            );
            await tester.tap(find.text('Done'));
          } else {
            await tester.tap(
              find.byKey(const ValueKey('course-display-actions-1')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Restore original name'));
          }
          await tester.pumpAndSettle();
          final editorRow = find.byKey(
            const ValueKey('course-display-editor-1'),
          );
          expect(
            find.descendant(
              of: editorRow,
              matching: find.text(_courses.first.shortName),
            ),
            findsOneWidget,
          );
          // Restoring then simply confirming the original name must keep the removal.
          await _openRename(tester);
          expect(_renameValue(tester), _courses.first.shortName);
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('course-display-save')));
          await tester.pumpAndSettle();
          expect(display.value.names, isEmpty);
          expect(find.text(_courses.first.fullName), findsOneWidget);
          await navigation();
          expect(
            find.descendant(
              of: row,
              matching: find.text(_courses.first.shortName),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(session.courses.first, same(_courses.first));
          await tester.pumpWidget(const SizedBox());
          session.dispose();
          display.dispose();
          final restored = CourseDisplayPreferencesController(store: store);
          await restored.bind('fixture');
          expect(restored.value.names, isEmpty);
          restored.dispose();
        },
      );
    }
  }

  testWidgets(
    'production drawer uses ABAB surfaces and synced aliases/order/hidden',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryCourseStore()..offline = true;
      final display = CourseDisplayPreferencesController(store: store);
      await display.bind('fixture');
      await display.saveDraft(
        CourseDisplayPreferences(
          names: {2: 'My alias'},
          hidden: {1},
          order: [3, 2],
        ),
        display.value,
      );
      final session = _CourseSession();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IspacePage(
            controller: session,
            courseDisplayPreferences: display,
            onGoToUserTab: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final a = find.byKey(const ValueKey('ispace-navigation-course-3'));
      final b = find.byKey(const ValueKey('ispace-navigation-course-2'));
      final c = find.byKey(const ValueKey('ispace-navigation-course-4'));
      expect(
        find.byKey(const ValueKey('ispace-navigation-course-1')),
        findsNothing,
      );
      expect(find.text('My alias'), findsOneWidget);
      expect(tester.getTopLeft(a).dy, lessThan(tester.getTopLeft(b).dy));
      expect(
        tester.widget<Material>(a).color,
        isNot(tester.widget<Material>(b).color),
      );
      expect(
        tester.widget<Material>(a).color,
        tester.widget<Material>(c).color,
      );
      expect(
        find.byKey(const ValueKey('ispace-manage-courses')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      display.dispose();
    },
  );

  testWidgets('closing editor discards edits and logout dismisses it', (
    tester,
  ) async {
    final store = MemoryCourseStore();
    final controller = CourseDisplayPreferencesController(store: store);
    await controller.bind('fixture');
    await tester.pumpWidget(_host(controller, 390));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide course'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(controller.value.hidden, isEmpty);
    expect(store.writes, 0);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await controller.bind(null);
    await tester.pumpAndSettle();
    expect(find.byType(CourseDisplayEditor), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

String _renameValue(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('course-display-name')),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

Future<void> _openRename(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rename for me'));
  await tester.pumpAndSettle();
}

Widget _host(
  CourseDisplayPreferencesController controller,
  double width, {
  List<CourseSummary>? courses,
}) => MaterialApp(
  theme: width == 900 ? AppTheme.dark : AppTheme.light,
  locale: const Locale('en'),
  supportedLocales: BnbuLocalizations.supportedLocales,
  localizationsDelegates: const [
    BnbuLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.5 : 1)),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCourseDisplayEditor(
            context,
            controller: controller,
            courses: courses ?? _courses,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

class _CourseSession extends AppSessionController {
  @override
  bool get isLoggedIn => true;
  @override
  String get username => 'fixture';
  @override
  List<CourseSummary> get courses => _courses;
  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async =>
      [];
}
