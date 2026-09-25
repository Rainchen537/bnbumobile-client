import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';
import 'package:bnbu_me/widgets/fixed_schedule_editor.dart';
import 'package:bnbu_me/widgets/leave_application_editor.dart';

void main() {
  for (final width in [320.0, 390.0, 900.0]) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('form values reach the right edge $width $locale $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1200);
          addTearDown(tester.view.reset);
          final l10n = BnbuLocalizations(locale);
          Future<void> mount(Widget child) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light,
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
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(body: child),
              ),
            );
            await tester.pumpAndSettle();
          }

          // Shared rows also place the DDL settings' trailing check/delete
          // controls. Their edge must not depend on the label's length.
          await mount(
            const BnbuCreationGroup(
              children: [
                BnbuCreationRow(
                  label: '学期',
                  value: Icon(Icons.check, key: ValueKey('trailing-check')),
                ),
              ],
            ),
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('trailing-check'))).right,
            closeTo(
              tester.getRect(find.byType(BnbuCreationRow)).right - 16,
              .1,
            ),
          );

          await mount(
            FixedScheduleEditor(
              initialEntry: TaCourseEntry(
                id: 'alignment-fixture',
                title: 'Synthetic schedule',
                location: '',
                weekday: 1,
                startMinutes: 540,
                endMinutes: 600,
                repeatType: TaCourseRepeatType.weekly,
                activeWeekStarts: List.generate(
                  12,
                  (i) => DateTime(2026, 9, 7).add(Duration(days: i * 7)),
                ),
              ),
            ),
          );
          for (final field in [
            ('重复', 'fixed-schedule-repeat'),
            ('适用周', 'fixed-schedule-weeks'),
            ('星期', 'fixed-schedule-weekday'),
          ]) {
            final control = find.byKey(ValueKey(field.$2));
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            final row = find
                .ancestor(
                  of: find.text(l10n.text(field.$1)),
                  matching: find.byType(Row),
                )
                .first;
            final arrow = find
                .descendant(of: control, matching: find.byType(Icon))
                .last;
            expect(
              tester.getRect(arrow).right,
              closeTo(tester.getRect(row).right, .1),
              reason: field.$1,
            );
          }
          expect(tester.takeException(), isNull);

          await mount(
            LeaveApplicationEditor(
              form: LeaveApplicationForm(
                fields: const {
                  'semester': LeaveApplicationField(display: '2026 S1'),
                  'beginTime': LeaveApplicationField(value: '09:00'),
                  'endTime': LeaveApplicationField(value: '10:00'),
                },
                reasons: const [],
                courses: const [],
              ),
              busy: false,
              onOpenSchool: (_, _) async {},
            ),
          );
          for (final label in ['学期', '开始日期', '开始时间', '结束日期', '结束时间']) {
            final row = find.byWidgetPredicate(
              (widget) =>
                  widget is BnbuCreationRow &&
                  (widget.label == label || widget.label == l10n.text(label)),
            );
            await tester.scrollUntilVisible(
              row,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            final arrows = find.descendant(
              of: row,
              matching: find.byType(Icon),
            );
            final value = arrows.evaluate().isNotEmpty
                ? arrows.last
                : find.byWidget(tester.widget<BnbuCreationRow>(row).value);
            expect(
              tester.getRect(value).right,
              closeTo(tester.getRect(row).right - 16, .1),
              reason: label,
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
