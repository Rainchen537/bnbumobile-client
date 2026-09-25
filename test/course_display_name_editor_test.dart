import 'dart:async';

import 'package:bnbu_me/models/course_display_preferences.dart';
import 'package:bnbu_me/state/course_display_preferences_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/course_display_editor.dart';
import 'package:bnbu_me/widgets/course_display_name_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_display_preferences_test.dart'
    show MemoryCourseStore, fixtureCourse;

const _field = ValueKey('course-display-name');
const _done = ValueKey('course-display-name-done');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(CourseDisplayPreferencesController, MemoryCourseStore)> open(
    WidgetTester tester, {
    double width = 390,
    Locale locale = const Locale('en'),
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryCourseStore();
    final controller = CourseDisplayPreferencesController(store: store);
    await controller.bind('fixture');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        locale: locale,
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCourseDisplayEditor(
                context,
                controller: controller,
                courses: [fixtureCourse(1), fixtureCourse(2)],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename for me'));
    await tester.pumpAndSettle();
    return (controller, store);
  }

  for (final close in ['done', 'back', 'escape', 'backdrop']) {
    testWidgets('immediate $close flushes latest name without outer Save', (
      tester,
    ) async {
      final (controller, store) = await open(tester);
      await tester.enterText(find.byKey(_field), 'Before closing');
      switch (close) {
        case 'done':
          await tester.tap(find.byKey(_done));
        case 'back':
          await tester.binding.handlePopRoute();
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'backdrop':
          await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(find.byType(CourseDisplayNameEditor), findsNothing);
      expect(controller.value.names, {1: 'Before closing'});
      expect(
        CourseDisplayPreferences.fromJson(
          store.local['fixture']!['value'],
        ).names,
        {1: 'Before closing'},
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(controller.value.names, {1: 'Before closing'});
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('name autosave does not commit hide or order drafts', (
    tester,
  ) async {
    final (controller, _) = await open(tester);
    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();
    for (final action in ['Hide course', 'Move down']) {
      await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename for me'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_field), 'Independent name');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(controller.value.names, {1: 'Independent name'});
    expect(controller.value.hidden, isEmpty);
    expect(controller.value.order, isEmpty);
    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(controller.value.names, {1: 'Independent name'});
    expect(controller.value.hidden, isEmpty);
    expect(controller.value.order, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed local write stays open and same-value retry persists', (
    tester,
  ) async {
    final (controller, store) = await open(tester);
    store.failLocal = true;
    await tester.enterText(find.byKey(_field), 'Retry name');
    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();
    expect(find.byType(CourseDisplayNameEditor), findsOneWidget);
    expect(find.text('Saved on this device'), findsNothing);
    expect(store.local, isEmpty);
    expect(controller.localSaveFailed, isTrue);
    store.failLocal = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(controller.localSaveFailed, isFalse);
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(
      CourseDisplayPreferences.fromJson(store.local['fixture']!['value']).names,
      {1: 'Retry name'},
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restore failure exposes retry even after alias leaves memory', (
    tester,
  ) async {
    final (controller, store) = await open(tester);
    await tester.enterText(find.byKey(_field), 'Alias');
    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();
    store.failLocal = true;
    await tester.tap(find.byKey(const ValueKey('course-display-actions-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore original name'));
    await tester.pumpAndSettle();
    expect(controller.localSaveFailed, isTrue);
    expect(find.text('Retry'), findsOneWidget);
    store.failLocal = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(controller.localSaveFailed, isFalse);
    expect(
      CourseDisplayPreferences.fromJson(store.local['fixture']!['value']).names,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing during slow disk write drains latest value in order', (
    tester,
  ) async {
    final (controller, store) = await open(tester);
    final gate = Completer<void>();
    store.localGate = gate;
    await tester.enterText(find.byKey(_field), 'First');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byKey(_field), 'Second');
    await tester.enterText(find.byKey(_field), 'Latest');
    await tester.pump(const Duration(milliseconds: 450));
    expect(store.local, isEmpty);
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.value.names, {1: 'Latest'});
    expect(
      CourseDisplayPreferences.fromJson(store.local['fixture']!['value']).names,
      {1: 'Latest'},
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('IME composition is not persisted until committed', (
    tester,
  ) async {
    final (controller, _) = await open(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '课程',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.value.names, isEmpty);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '课程',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(controller.value.names, {1: '课程'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'logout/login same account invalidates pending rename generation',
    (tester) async {
      final (controller, store) = await open(tester);
      final generation = controller.bindingGeneration;
      await tester.enterText(find.byKey(_field), 'Stale name');
      await controller.bind(null);
      await controller.bind('fixture');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CourseDisplayEditor), findsNothing);
      expect(controller.value.names, isEmpty);
      expect(store.local, isEmpty);
      await expectLater(
        controller.saveName(1, 'Late', expectedGeneration: generation),
        throwsStateError,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    testWidgets(
      '150 code points accepted, 151 rejected without truncation at $width',
      (tester) async {
        final (controller, _) = await open(
          tester,
          width: width,
          dark: width == 900,
        );
        for (final character in ['a', '课', '😀']) {
          await tester.enterText(find.byKey(_field), character * 150);
          await tester.pump(const Duration(milliseconds: 450));
          await tester.pumpAndSettle();
          expect(controller.value.names[1], character * 150);
          await tester.enterText(find.byKey(_field), character * 151);
          await tester.tap(find.byKey(_done));
          await tester.pumpAndSettle();
          expect(find.byType(CourseDisplayNameEditor), findsOneWidget);
          expect(controller.value.names[1], character * 150);
          expect(find.text('151/150'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
