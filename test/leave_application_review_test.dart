import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/leave_application_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const form = LeaveApplicationForm(
    fields: {},
    completion: LeaveFormCompletion(
      canSubmit: true,
      token: 'synthetic',
      notices: ['Synthetic school note'],
      declaration: 'Synthetic certification text',
      acknowledgement: 'Synthetic acknowledgement',
      files: [LeaveSchoolAttachment('one', 'test-only.txt')],
    ),
  );
  testWidgets('review starts unchecked and cancellation does not accept', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const LeaveApplicationReview(form: form),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('leave-confirm-submit')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(result, false);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final ack = find.byKey(const ValueKey('leave-acknowledgement'));
    await tester.ensureVisible(ack);
    await tester.tap(ack);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交给学校'));
    await tester.pumpAndSettle();
    expect(result, true);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
  });

  testWidgets(
    'review is bounded and scrollable on phones tablets and desktop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [
        const Size(320, 568),
        const Size(844, 390),
        const Size(834, 1194),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(1.6),
                ),
                child: const Scaffold(body: LeaveApplicationReview(form: form)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .getSize(
                  find.descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Material &&
                          widget.type == MaterialType.card,
                    ),
                  ),
                )
                .width,
            lessThanOrEqualTo(680),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
