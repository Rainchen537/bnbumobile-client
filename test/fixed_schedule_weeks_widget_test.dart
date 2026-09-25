import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';
import 'package:bnbu_me/widgets/fixed_schedule_editor.dart';
import 'fixed_schedule_weeks_test.dart' show calendarTimetable, weeklyEntry;

void main() {
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets(
      'teaching defaults, holiday and external week persist at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        TaCourseEntry? saved;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    saved = await showBnbuCreationModal<TaCourseEntry>(
                      context: context,
                      builder: (context, presentation) =>
                          FixedScheduleEditor(timetable: calendarTimetable()),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('fixed-schedule-weeks')));
        await tester.pumpAndSettle();
        final originalPanel = tester.getRect(
          find.byKey(const ValueKey('fixed-weeks-panel')),
        );
        final holiday = find.byKey(const ValueKey('fixed-weeks-2026-10-26'));
        await tester.scrollUntilVisible(
          holiday,
          240,
          scrollable: _weekScroll(),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(holiday).value, isFalse);
        await tester.tap(holiday);
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(holiday).value, isTrue);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('fixed-weeks-add')),
          -240,
          scrollable: _weekScroll(),
        );
        await tester.tap(find.byKey(const ValueKey('fixed-weeks-add')));
        await tester.pumpAndSettle();
        // Defaults start in September. Move beyond the term and into a new year.
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byTooltip('下个月'));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(const ValueKey('fixed-schedule-week-2027-1-4')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('fixed-weeks-panel'))),
          originalPanel,
        );
        await tester.tap(find.byKey(const ValueKey('fixed-weeks-save')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('fixed-schedule-title')),
          'Study',
        );
        await tester.tap(find.byKey(const ValueKey('ta-course-editor-save')));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        expect(saved!.appliesToWeek(DateTime(2026, 10, 26)), isTrue);
        expect(saved!.appliesToWeek(DateTime(2027, 1, 4)), isTrue);
        expect(saved!.appliesToWeek(DateTime(2027, 1, 11)), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('cancelling week edits preserves existing selected weeks', (
    tester,
  ) async {
    final original = weeklyEntry(weeks: [DateTime(2026, 10, 26)]);
    TaCourseEntry? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showBnbuCreationModal<TaCourseEntry>(
                  context: context,
                  builder: (context, presentation) => FixedScheduleEditor(
                    initialEntry: original,
                    timetable: calendarTimetable(),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('fixed-schedule-weeks')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixed-schedule-weeks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixed-weeks-default')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixed-weeks-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ta-course-editor-save')));
    await tester.pumpAndSettle();
    expect(saved!.hasSameCourseFields(original), isTrue);
  });
  testWidgets(
    'English dark large text picker keeps confirm and external weeks accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
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
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBnbuCreationModal<void>(
                  context: context,
                  builder: (context, presentation) =>
                      FixedScheduleEditor(timetable: calendarTimetable()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fixed-schedule-weeks')));
      await tester.pumpAndSettle();
      expect(find.text('Add other weeks'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fixed-weeks-save')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _weekScroll() => find.descendant(
  of: find.byKey(const ValueKey('fixed-weeks-list')),
  matching: find.byType(Scrollable),
);
