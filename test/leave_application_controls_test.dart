import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/services/leave_application_bridge.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/leave_application_editor.dart';
import 'package:bnbu_me/widgets/leave_time_picker.dart';
import 'package:bnbu_me/widgets/bnbu_menu.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'leave_application_editor_test.dart' show fixture;

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
  Future<void> showEditor(
    WidgetTester tester, {
    bool busy = false,
    Map<String, LeaveApplicationField> fields = const {},
    Future<void> Function(LeaveSchoolSection, Map<String, String>)? onOpen,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: LeaveApplicationEditor(
          form: LeaveApplicationForm(
            fields: {...fixture().fields, ...fields},
            reasons: fixture().reasons,
          ),
          busy: busy,
          onOpenSchool: onOpen ?? (_, _) async {},
        ),
      ),
    ),
  );

  Future<void> tapRow(WidgetTester tester, String label) async {
    final rowLabel = find.textContaining(
      RegExp('^${RegExp.escape(label)}(?: \\*)?\$'),
    );
    await tester.scrollUntilVisible(
      rowLabel,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(rowLabel);
    await tester.pumpAndSettle();
  }

  Future<void> wheelTo(WidgetTester tester, String id, int item) async {
    final picker = tester.widget<CupertinoPicker>(find.byKey(ValueKey(id)));
    picker.scrollController!.jumpToItem(item);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reason menu preserves school values and only changes the draft',
    (tester) async {
      final calls = <Map<String, String>>[];
      await showEditor(
        tester,
        onOpen: (_, changes) async => calls.add(changes),
      );
      final menu = find.byKey(const ValueKey('leave-reason'));
      await tester.scrollUntilVisible(
        menu,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('School option'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('School option'), findsOneWidget);
      await tapRow(tester, '核对并提交');
      expect(calls.single, {'reason': '8'});
    },
  );

  testWidgets('compact applicant uses aligned label and value columns', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await showEditor(tester);
      await tester.pumpAndSettle();
      final left = tester.getTopLeft(find.text('申请人资料')).dx;
      final valueLeft = tester.getTopLeft(find.text('Example Student A')).dx;
      expect(
        tester.widget<Text>(find.text('Example Student A')).textAlign,
        TextAlign.end,
      );
      for (final label in [
        '中文姓名',
        '英文姓名',
        '学号',
        '学院',
        '专业',
        '手机号码 *',
        '家人联系电话 *',
      ]) {
        expect(tester.getTopLeft(find.text(label)).dx, closeTo(left, 1));
      }
      expect(valueLeft, greaterThan(left + 40));
      expect(
        tester.getTopLeft(find.text('SYNTHETIC-STUDENT')).dx,
        closeTo(valueLeft, 1),
      );
      expect(
        tester.getCenter(find.text('英文姓名')).dy,
        closeTo(tester.getCenter(find.text('Example Student A')).dy, 1),
      );
      for (final id in ['mobile', 'familyPhone']) {
        expect(
          tester.getTopLeft(find.byKey(ValueKey('leave-$id'))).dx,
          closeTo(valueLeft, 1),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'wide applicant has four rows with right-aligned values and paired phones',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final width in [768.0, 834.0, 1024.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await showEditor(tester);
        await tester.pumpAndSettle();
        Rect box(String id) =>
            tester.getRect(find.byKey(ValueKey('leave-identity-$id')));
        expect(box('chineseName').top, box('englishName').top);
        expect(box('chineseName').right, closeTo(box('englishName').left, 1));
        expect(
          box('studentNo').width,
          closeTo(box('chineseName').width * 2, 1),
        );
        expect(box('faculty').top, box('programme').top);
        expect(box('faculty').left, box('chineseName').left);
        expect(
          tester.getTopRight(find.text('Example Student A')).dx,
          closeTo(box('englishName').right - 16, 1),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('leave-mobile'))).dy,
          tester.getTopLeft(find.byKey(const ValueKey('leave-familyPhone'))).dy,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('compact applicant columns survive long data and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ]) {
      for (final width in [320.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1800);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: BnbuLocalizations.supportedLocales,
            localizationsDelegates: const [
              BnbuLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: LeaveApplicationEditor(
                key: ValueKey('$locale-$width'),
                form: LeaveApplicationForm(
                  fields: {
                    ...fixture().fields,
                    'chineseName': const LeaveApplicationField(display: '示例同学'),
                    'englishName': const LeaveApplicationField(
                      display: 'Example Student With A Very Long Name',
                    ),
                    'faculty': const LeaveApplicationField(
                      display: 'Example Faculty',
                    ),
                    'programme': const LeaveApplicationField(
                      display: 'Computer Science and Technology',
                    ),
                  },
                ),
                busy: false,
                onOpenSchool: (_, _) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final left = tester.getTopLeft(find.text('示例同学')).dx;
        for (final text in [
          'Example Student With A Very Long Name',
          'SYNTHETIC-STUDENT',
          'Example Faculty',
          'Computer Science and Technology',
        ]) {
          final rect = tester.getRect(find.text(text));
          expect(rect.left, closeTo(left, 1));
          expect(rect.right, lessThanOrEqualTo(width - 32));
        }
        final mobile = find.byKey(const ValueKey('leave-mobile'));
        await tester.ensureVisible(mobile);
        expect(tester.getTopLeft(mobile).dx, closeTo(left, 1));
        await tester.enterText(mobile, '+00 123-456');
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'own phone is editable, draft only and outside collapsed identity',
    (tester) async {
      final calls = <Map<String, String>>[];
      await showEditor(
        tester,
        onOpen: (_, changes) async => calls.add(changes),
      );
      await tapRow(tester, '申请人资料');
      final mobile = find.byKey(const ValueKey('leave-mobile'));
      await tester.ensureVisible(mobile);
      expect(tester.widget<TextField>(mobile).readOnly, isFalse);
      expect(tester.widget<TextField>(mobile).textAlign, TextAlign.end);
      expect(tester.widget<TextField>(mobile).decoration!.suffixIcon, isNull);
      await tester.enterText(mobile, '+00 123-456');
      expect(calls, isEmpty);
      await tapRow(tester, '核对并提交');
      expect(calls.single, {'mobile': '+00 123-456'});
    },
  );

  for (final busy in [false, true]) {
    testWidgets('phone and time respect school readonly or busy ($busy)', (
      tester,
    ) async {
      await showEditor(
        tester,
        busy: busy,
        fields: {
          'mobile': LeaveApplicationField(editable: busy),
          'beginTime': LeaveApplicationField(editable: busy),
        },
      );
      final mobile = find.byKey(const ValueKey('leave-mobile'));
      await tester.ensureVisible(mobile);
      expect(tester.widget<TextField>(mobile).readOnly, isTrue);
      await tapRow(tester, '开始时间');
      expect(find.byType(LeaveTimePicker), findsNothing);
    });
  }

  testWidgets('safety locks never masquerade as running work or enable edits', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [320.0, 900.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final locale in BnbuLocalizations.supportedLocales) {
          for (final state in ['working', 'blocked', 'submitting', 'locked']) {
            await tester.pumpWidget(
              MaterialApp(
                key: ValueKey('$width-$theme-$locale-$state'),
                theme: theme,
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
                  ).copyWith(textScaler: TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: Scaffold(
                  body: LeaveApplicationEditor(
                    form: LeaveApplicationForm(
                      fields: fixture().fields,
                      reasons: fixture().reasons,
                      courses: fixture().courses,
                      completion: const LeaveFormCompletion(
                        files: [LeaveSchoolAttachment('fake', 'example.pdf')],
                      ),
                    ),
                    busy: state == 'working' || state == 'submitting',
                    writeBlocked: state != 'working',
                    submissionLocked:
                        state == 'locked' || state == 'submitting',
                    onOpenSchool: (_, _) async => fail('must not dispatch'),
                    onSelectCourse: (_, _) async => fail('must not select'),
                    onRemoveCourse: (_) async => fail('must not remove'),
                    onAddAttachment: () async => fail('must not upload'),
                    onRemoveAttachment: (_) async =>
                        fail('must not remove attachment'),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final editor = find.byType(LeaveApplicationEditor);
            final l10n = BnbuLocalizations.of(tester.element(editor));
            final label = l10n.text(switch (state) {
              'working' => '正在同步学校表单',
              'submitting' => '正在提交至学校',
              'blocked' => '请先核对学校表单',
              _ => '提交结果待确认',
            });
            await tester.scrollUntilVisible(
              find.text(label),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, label),
                  )
                  .onPressed,
              isNull,
            );
            if (state != 'working') {
              expect(find.text(l10n.text('正在同步学校表单')), findsNothing);
            }
            expect(find.byType(ListTile), findsWidgets);
            for (final button in tester.widgetList<IconButton>(
              find.byType(IconButton),
            )) {
              expect(button.onPressed, isNull);
            }
            for (final row in tester.widgetList<ListTile>(
              find.byType(ListTile),
            )) {
              expect(row.onTap, isNull);
            }
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('leave-mobile')),
              -300,
              scrollable: find.byType(Scrollable).first,
            );
            for (final id in ['mobile', 'familyPhone']) {
              expect(
                tester
                    .widget<TextField>(find.byKey(ValueKey('leave-$id')))
                    .readOnly,
                isTrue,
              );
            }
            await tapRow(tester, l10n.text('开始日期'));
            expect(find.byType(DatePickerDialog), findsNothing);
            await tapRow(tester, l10n.text('开始时间'));
            expect(find.byType(LeaveTimePicker), findsNothing);
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('leave-reason')),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              tester
                  .widget<BnbuMenuButton<String>>(
                    find.byKey(const ValueKey('leave-reason')),
                  )
                  .enabled,
              isFalse,
            );
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('leave-details')),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('leave-details')),
                  )
                  .readOnly,
              isTrue,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });

  testWidgets(
    'time wheels preserve exact minutes; cancel never changes draft',
    (tester) async {
      final calls = <Map<String, String>>[];
      await showEditor(
        tester,
        fields: {
          'beginTime': const LeaveApplicationField(
            value: '09:17',
            editable: true,
          ),
          'endTime': const LeaveApplicationField(
            value: '10:47',
            editable: true,
          ),
        },
        onOpen: (_, values) async => calls.add(values),
      );
      await tapRow(tester, '开始时间');
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
      expect(
        tester
            .widget<CupertinoPicker>(
              find.byKey(const ValueKey('leave-time-minute')),
            )
            .scrollController!
            .selectedItem,
        17,
      );
      await wheelTo(tester, 'leave-time-hour', 23);
      await wheelTo(tester, 'leave-time-minute', 59);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('09:17'), findsOneWidget);
      await tapRow(tester, '开始时间');
      await wheelTo(tester, 'leave-time-hour', 0);
      await wheelTo(tester, 'leave-time-minute', 0);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('00:00'), findsOneWidget);
      expect(calls, isEmpty);
      await tapRow(tester, '结束时间');
      await wheelTo(tester, 'leave-time-hour', 23);
      await wheelTo(tester, 'leave-time-minute', 59);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tapRow(tester, '核对并提交');
      expect(calls.single, {'beginTime': '00:00', 'endTime': '23:59'});
    },
  );

  testWidgets('removing the editor removes its open time dialog', (
    tester,
  ) async {
    await showEditor(tester);
    await tapRow(tester, '开始时间');
    expect(find.byType(LeaveTimePicker), findsOneWidget);
    // Keep the navigator alive to model session expiry replacing the editor.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Text('Signed out')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LeaveTimePicker), findsNothing);
    expect(find.text('Signed out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wheel dialog is bounded and usable across sizes, themes and locales',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [
        const Size(320, 568),
        const Size(844, 390),
        const Size(900, 1000),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          for (final locale in BnbuLocalizations.supportedLocales) {
            await tester.pumpWidget(
              MaterialApp(
                key: ValueKey('$size-$theme-$locale'),
                theme: theme,
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
                  ).copyWith(textScaler: TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: LeaveTimePicker(
                    title: '开始时间',
                    initialTime: TimeOfDay(hour: 23, minute: 59),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final surface = tester.getRect(find.byType(SingleChildScrollView));
            expect(surface.width, lessThanOrEqualTo(360));
            expect(surface.left, greaterThanOrEqualTo(20));
            expect(surface.right, lessThanOrEqualTo(size.width - 20));
            expect(surface.bottom, lessThanOrEqualTo(size.height - 24));
          }
        }
      }
    },
  );
}
