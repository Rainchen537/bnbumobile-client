import 'dart:async';

import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/services/leave_application_bridge.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/leave_application_editor.dart';
import 'package:bnbu_me/widgets/leave_course_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'leave_application_editor_test.dart' show fixture;

LeaveCoursePickerSnapshot courseFixture({int page = 1}) =>
    LeaveCoursePickerSnapshot.fromJson({
      'token': 'synthetic-session:$page',
      'rowIndex': '4',
      'page': 'Page $page / 2',
      'hasPrevious': page > 1,
      'hasNext': page < 2,
      'candidates': [
        for (var i = 0; i < 8; i++)
          {
            'key': '$i',
            'code': 'DEMO$page$i',
            'teacher': 'Example Teacher $i',
            'units': '3',
            'type': 'Lecture',
            'time': 'Mon ${9 + i}:00-${9 + i}:50',
          },
      ],
    });

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<void> showPicker(
    WidgetTester tester, {
    Future<LeaveBridgeResult> Function(LeaveCoursePickerSnapshot, bool)? onPage,
    ValueChanged<LeaveCourseChoice?>? onResult,
    ThemeData? theme,
    Locale locale = const Locale('zh'),
    double scale = 1,
    Future<LeaveBridgeResult> Function()? onRetry,
    List<Map<String, String>> selectedCourses = const [],
    LeaveCoursePickerSnapshot? initial,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: const [
          Locale('zh'),
          Locale('en'),
          Locale('zh', 'TW'),
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  leaveCoursePickerRoute(
                    context: context,
                    builder: (_) => LeaveCoursePicker(
                      initial: initial ?? courseFixture(),
                      selectedCourses: selectedCourses,
                      onRetry: onRetry,
                      onPage:
                          onPage ??
                          (_, next) async => LeaveBridgeResult(
                            'course_ready',
                            null,
                            courseFixture(page: next ? 2 : 1),
                          ),
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selected rows stay grey and disabled without changing school handles',
    (tester) async {
      final snapshot = courseFixture();
      LeaveCourseChoice? result;
      await showPicker(
        tester,
        initial: snapshot,
        selectedCourses: [snapshot.candidates.first],
        onResult: (value) => result = value,
      );
      expect(find.text('DEMO10'), findsOneWidget);
      expect(find.text('已选'), findsOneWidget);
      await tester.tap(find.text('DEMO10'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('DEMO11'), findsOneWidget);
      await tester.tap(find.text('DEMO11'));
      await tester.pumpAndSettle();
      expect(identical(result!.snapshot, snapshot), isTrue);
      expect(identical(result!.candidate, snapshot.candidates[1]), isTrue);
      expect(result!.candidate['key'], '1');
      expect(snapshot.candidates, hasLength(8));
    },
  );

  testWidgets(
    'strict matching retains different classes and incomplete school fields',
    (tester) async {
      final first = courseFixture().candidates.first;
      for (final field in ['code', 'teacher', 'type', 'time']) {
        for (final value in ['different', '', '   ']) {
          LeaveCourseChoice? choice;
          await showPicker(
            tester,
            onResult: (result) => choice = result,
            selectedCourses: [
              {...first, field: value},
            ],
          );
          expect(find.text(first['code']!), findsOneWidget);
          expect(find.text('已选'), findsNothing);
          await tester.tap(find.text(first['code']!));
          await tester.pumpAndSettle();
          expect(choice?.candidate['key'], first['key']);
        }
      }
      await showPicker(
        tester,
        selectedCourses: [
          for (final row in courseFixture().candidates)
            {
              for (final field in ['code', 'teacher', 'type', 'time'])
                field: '  ${row[field]}  ',
            },
        ],
      );
      expect(find.text('已选'), findsNWidgets(8));
      expect(find.text('暂无数据'), findsNothing);
    },
  );

  testWidgets(
    'fully selected page retains paging and filters each school snapshot',
    (tester) async {
      final one = courseFixture(), two = courseFixture(page: 2);
      final requests = <LeaveCoursePickerSnapshot>[];
      await showPicker(
        tester,
        initial: one,
        selectedCourses: [...one.candidates, two.candidates.first],
        onPage: (snapshot, next) async {
          requests.add(snapshot);
          return LeaveBridgeResult('course_ready', null, next ? two : one);
        },
      );
      expect(find.text('已选'), findsNWidgets(8));
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('DEMO20'), findsOneWidget);
      expect(find.text('已选'), findsOneWidget);
      expect(find.text('DEMO21'), findsOneWidget);
      await tester.tap(find.byTooltip('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('已选'), findsNWidgets(8));
      expect(identical(requests[0], one), isTrue);
      expect(identical(requests[1], two), isTrue);
    },
  );

  testWidgets(
    'retry filters the returned page and does not repeat navigation',
    (tester) async {
      final two = courseFixture(page: 2);
      var pages = 0;
      await showPicker(
        tester,
        selectedCourses: two.candidates,
        onPage: (_, _) async {
          pages++;
          return const LeaveBridgeResult('unavailable');
        },
        onRetry: () async => LeaveBridgeResult('course_ready', null, two),
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新读取课程'));
      await tester.pumpAndSettle();
      expect(find.text('已选'), findsNWidgets(8));
      expect(pages, 1);
    },
  );

  testWidgets(
    'empty school data is distinct from selected-only in all languages',
    (tester) async {
      final empty = LeaveCoursePickerSnapshot.fromJson({
        'token': 'empty',
        'rowIndex': '4',
        'page': 'Page 1 / 1',
        'candidates': <Map<String, String>>[],
      });
      for (final entry in {
        const Locale('zh'): ['已选', '暂无数据'],
        const Locale('zh', 'TW'): ['已選', '暫無數據'],
        const Locale('en'): ['Selected', 'No data'],
      }.entries) {
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          await showPicker(
            tester,
            selectedCourses: courseFixture().candidates,
            locale: entry.key,
            theme: theme,
          );
          expect(find.text(entry.value[0]), findsNWidgets(8));
          await tester.tap(find.byType(IconButton).first);
          await tester.pumpAndSettle();
          await showPicker(
            tester,
            initial: empty,
            locale: entry.key,
            theme: theme,
          );
          expect(find.text(entry.value[1]), findsOneWidget);
          await tester.tap(find.byType(IconButton).first);
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'native selection returns exact ephemeral candidate; cancel returns none',
    (tester) async {
      LeaveCourseChoice? selected;
      await showPicker(tester, onResult: (value) => selected = value);
      expect(
        find.byTooltip('DEMO10\nExample Teacher 0\nLecture\nMon 9:00-9:50'),
        findsOneWidget,
      );
      await tester.tap(find.text('DEMO10'));
      await tester.pumpAndSettle();
      expect(selected!.snapshot.rowIndex, '4');
      expect(selected!.candidate['key'], '0');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    },
  );

  testWidgets(
    'failed page reload reads current candidates without repeating pagination',
    (tester) async {
      var pages = 0, reads = 0;
      await showPicker(
        tester,
        onPage: (_, _) async {
          pages++;
          return const LeaveBridgeResult('unavailable');
        },
        onRetry: () async {
          reads++;
          return LeaveBridgeResult(
            'course_ready',
            null,
            courseFixture(page: 2),
          );
        },
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('DEMO10'), findsOneWidget);
      expect(
        tester.widget<AbsorbPointer>(find.byType(AbsorbPointer).last).absorbing,
        isTrue,
      );
      await tester.tap(find.text('重新读取课程'));
      await tester.pumpAndSettle();
      expect(find.text('DEMO20'), findsOneWidget);
      expect(pages, 1);
      expect(reads, 1);
    },
  );

  testWidgets(
    'page action locks candidates until new school snapshot; failed page cannot select stale data',
    (tester) async {
      var pending = Completer<LeaveBridgeResult>();
      var requests = 0;
      await showPicker(
        tester,
        onPage: (snapshot, next) {
          requests++;
          expect(
            snapshot.token,
            requests == 1 ? 'synthetic-session:1' : 'synthetic-session:2',
          );
          return pending.future;
        },
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();
      expect(find.text('DEMO10'), findsOneWidget);
      expect(
        tester.widget<AbsorbPointer>(find.byType(AbsorbPointer).last).absorbing,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '取消',
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete(
        LeaveBridgeResult('course_ready', null, courseFixture(page: 2)),
      );
      await tester.pumpAndSettle();
      expect(find.text('DEMO20'), findsOneWidget);
      pending = Completer<LeaveBridgeResult>();
      await tester.tap(find.byTooltip('上一页'));
      await tester.pump();
      pending.complete(const LeaveBridgeResult('unsupported'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '上一页',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      expect(requests, 2);
    },
  );

  testWidgets(
    'course picker remains bounded and scrollable in narrow, landscape and large text layouts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [
        const Size(320, 568),
        const Size(844, 390),
        const Size(768, 1024),
        const Size(834, 1194),
        const Size(1194, 834),
        const Size(900, 1000),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          for (final locale in [
            const Locale('zh'),
            const Locale('zh', 'TW'),
            const Locale('en'),
          ]) {
            await showPicker(
              tester,
              theme: theme,
              locale: locale,
              scale: 1.6,
              selectedCourses: [courseFixture().candidates.first],
            );
            final rect = tester.getRect(
              find.byKey(const ValueKey('leave-course-picker-content')),
            );
            final inset = size.width <= 900 ? 0 : (size.width - 900) / 2;
            expect(rect.left, greaterThanOrEqualTo(inset));
            expect(rect.right, lessThanOrEqualTo(size.width - inset));
            expect(rect.top, greaterThanOrEqualTo(size.height * .09));
            expect(rect.bottom, closeTo(size.height, 1));
            expect(find.byType(Dialog), findsNothing);
            final route =
                ModalRoute.of(tester.element(find.byType(LeaveCoursePicker)))!
                    as ModalBottomSheetRoute;
            expect(route.enableDrag, isFalse);
            expect(route.isDismissible, isFalse);
            final list = find.byKey(const ValueKey('leave-week-vertical'));
            await tester.drag(list, const Offset(0, -500));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      }
    },
  );

  testWidgets(
    'editor uses native selection callback with real row index and preserves phone draft',
    (tester) async {
      final selections = <String?>[];
      final drafts = <Map<String, String>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveApplicationEditor(
              busy: false,
              form: LeaveApplicationForm(
                fields: fixture().fields,
                courses: [
                  {...fixture().courses.single, 'index': '4'},
                ],
              ),
              onOpenSchool: (_, _) async =>
                  fail('must use native course callback'),
              onSelectCourse: (index, changes) async {
                selections.add(index);
                drafts.add(changes);
              },
            ),
          ),
        ),
      );
      final phone = find.byKey(const ValueKey('leave-mobile'));
      await tester.ensureVisible(phone);
      await tester.enterText(phone, '12345');
      await tester.scrollUntilVisible(
        find.text('DEMO1001 · Synthetic Course'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEMO1001 · Synthetic Course'));
      await tester.ensureVisible(find.text('选择课程与教师'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择课程与教师'));
      expect(selections, ['4', null]);
      expect(drafts, [
        {'mobile': '12345'},
        {'mobile': '12345'},
      ]);
    },
  );
}
