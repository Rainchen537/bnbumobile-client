import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/services/leave_application_bridge.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/leave_application_editor.dart';
import 'package:bnbu_me/widgets/leave_time_picker.dart';
import 'package:bnbu_me/widgets/leave_course_picker.dart';
import 'package:bnbu_me/widgets/leave_application_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

LeaveApplicationForm fixture({String name = 'Example Student A'}) =>
    LeaveApplicationForm(
      fields: {
        'englishName': LeaveApplicationField(value: name, display: name),
        'studentNo': const LeaveApplicationField(display: 'SYNTHETIC-STUDENT'),
        'semester': const LeaveApplicationField(display: 'Synthetic semester'),
        'days': const LeaveApplicationField(display: 'School result'),
        for (final key in [
          'mobile',
          'familyPhone',
          'details',
          'beginDate',
          'beginTime',
          'endDate',
          'endTime',
          'reason',
        ])
          key: const LeaveApplicationField(editable: true, required: true),
      },
      reasons: const [
        LeaveApplicationOption('0', 'Health Problem'),
        LeaveApplicationOption('8', 'School option'),
      ],
      courses: const [
        {
          'index': '4',
          'token': 'synthetic:4',
          'code': 'DEMO1001',
          'title': 'Synthetic Course',
          'teacher': 'Example Teacher',
          'time': 'School time',
        },
      ],
    );

void main() {
  testWidgets('live language changes preserve the native leave draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final form = fixture();
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('en'),
      const Locale('zh', 'TW'),
    ]) {
      final l10n = BnbuLocalizations(locale);
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
          home: Scaffold(
            body: LeaveApplicationEditor(
              form: form,
              busy: false,
              onOpenSchool: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text(l10n.text('学期')), findsOneWidget);
      expect(find.text(l10n.text('学号')), findsOneWidget);
      expect(find.text('Synthetic semester'), findsOneWidget);
      final mobile = find.byKey(const ValueKey('leave-mobile'));
      await tester.ensureVisible(mobile);
      if (locale.countryCode == 'CN') {
        await tester.enterText(mobile, '+00 123456');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
      }
      expect(tester.widget<TextField>(mobile).controller!.text, '+00 123456');
      for (final label in ['开始日期', '结束日期']) {
        final target = find.text('${l10n.text(label)} *');
        await tester.scrollUntilVisible(
          target,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(target, findsOneWidget);
      }
      final details = find.byKey(const ValueKey('leave-details'));
      await tester.scrollUntilVisible(
        details,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      if (locale.countryCode == 'CN') {
        await tester.enterText(details, 'Synthetic draft remains unchanged');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<TextField>(details).controller!.text,
        'Synthetic draft remains unchanged',
      );
      expect(form.reasons.first.label, 'Health Problem');
      expect(form.courses.first['title'], 'Synthetic Course');
    }
  });

  test('leave labels have English and Traditional translations', () {
    const english = BnbuLocalizations(Locale('en'));
    const traditional = BnbuLocalizations(Locale('zh', 'TW'));
    for (final label in [
      '学期',
      '学号',
      '开始日期',
      '结束日期',
      '选择',
      '放弃',
      '学校页面加载失败',
      '学校页面加载失败，请检查网络后重试。',
    ]) {
      expect(english.text(label), isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
    }
    expect(traditional.text('学号'), '學號');
    expect(traditional.text('开始日期'), '開始日期');
    expect(traditional.text('结束日期'), '結束日期');
  });

  const renderFont = String.fromEnvironment('BNBU_LEAVE_RENDER_FONT');
  if (renderFont.isNotEmpty) {
    testWidgets('optional local synthetic rendering evidence', (tester) async {
      await tester.runAsync(() async {
        final data = ByteData.sublistView(await File(renderFont).readAsBytes());
        for (final family in [
          'Roboto',
          'Roboto-Medium',
          'Roboto-Bold',
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          await (FontLoader(family)..addFont(Future.value(data))).load();
        }
        final manifest =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final family in manifest.cast<Map<String, dynamic>>()) {
          final name = family['family'] as String;
          if (!name.contains('lucide') && name != 'MaterialIcons') continue;
          final loader = FontLoader(family['family'] as String);
          for (final font
              in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        tester.view.physicalSize = const Size(390, 844);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                appBar: AppBar(title: const Text('请假申请')),
                body: LeaveApplicationEditor(
                  key: ValueKey(dark),
                  form: LeaveApplicationForm(
                    fields: {
                      ...fixture().fields,
                      'chineseName': const LeaveApplicationField(
                        display: '示例同学',
                      ),
                      'faculty': const LeaveApplicationField(
                        display: 'Example Faculty',
                      ),
                      'programme': const LeaveApplicationField(
                        display: 'Computer Science and Technology',
                      ),
                      'mobile': const LeaveApplicationField(
                        value: '+00 123 456',
                        editable: true,
                      ),
                      'familyPhone': const LeaveApplicationField(
                        value: '+00 456 789',
                        editable: true,
                      ),
                    },
                  ),
                  busy: false,
                  onOpenSchool: (_, _) async {},
                  onSelectCourse: (_, _) async {},
                  onRemoveCourse: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final section in [
          'top',
          'bottom',
          'time',
          'courses',
          'courses-wide',
          'courses-overlap',
          'courses-overlap-options',
          'wide',
          'review',
        ]) {
          if (section == 'wide' || section == 'review') {
            tester.view.physicalSize = section == 'wide'
                ? const Size(1000, 900)
                : const Size(390, 844);
            final synthetic = LeaveApplicationForm(
              fields: {
                ...fixture().fields,
                'chineseName': const LeaveApplicationField(display: '示例同学'),
                'faculty': const LeaveApplicationField(
                  display: 'Example Faculty',
                ),
                'programme': const LeaveApplicationField(
                  display: 'Example Programme',
                ),
              },
              completion: const LeaveFormCompletion(
                canSubmit: true,
                notices: ['Synthetic school note for UI testing.'],
                declaration:
                    'Synthetic declaration. This is not a real application.',
                acknowledgement: '已了解示例申请须知（仅测试）',
              ),
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    appBar: AppBar(title: const Text('请假申请')),
                    body: section == 'wide'
                        ? LeaveApplicationEditor(
                            form: synthetic,
                            busy: false,
                            onOpenSchool: (_, _) async {},
                          )
                        : LeaveApplicationReview(form: synthetic),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          if (section == 'bottom') {
            await tester.drag(find.byType(ListView), const Offset(0, -1700));
            await tester.pumpAndSettle();
          }
          if (section == 'time') {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: RepaintBoundary(
                  key: boundary,
                  child: const Scaffold(
                    body: LeaveTimePicker(
                      title: '开始时间',
                      initialTime: TimeOfDay(hour: 9, minute: 17),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          if (section.startsWith('courses')) {
            tester.view.physicalSize = section == 'courses-wide'
                ? const Size(1200, 900)
                : const Size(390, 844);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    body: LeaveCoursePicker(
                      key: ValueKey('preview-$section-$dark'),
                      selectedCourses: [
                        {
                          'code': 'Database Systems (1003)',
                          'teacher': 'Example Teacher 1',
                          'type': 'Lecture',
                          'time': section.contains('overlap')
                              ? 'Mon 09:30–10:50'
                              : 'Tue 10:00–11:50',
                        },
                      ],
                      initial: LeaveCoursePickerSnapshot.fromJson({
                        'token': 'synthetic:1',
                        'rowIndex': '4',
                        'page': 'Page 1 / 1',
                        'hasPrevious': false,
                        'hasNext': false,
                        'candidates': [
                          for (var i = 0; i < 6; i++)
                            {
                              'key': '$i',
                              'code': const [
                                'Computer Organisation (1001)',
                                'Database Systems (1003)',
                                'Data Structures (1002)',
                                'Linear Algebra (1001)',
                                'Probability and Statistics (1002)',
                                'Environmental Awareness (1012)',
                              ][i],
                              'teacher': 'Example Teacher $i',
                              'units': '3',
                              'type': 'Lecture',
                              'time': section.contains('overlap') && i == 1
                                  ? 'Mon 09:30–10:50'
                                  : const [
                                      'Mon 09:00–10:50',
                                      'Tue 10:00–11:50',
                                      'Wed 11:00–11:50',
                                      'Thu 09:00–09:50',
                                      'Fri 14:00–15:50',
                                      'Mon 14:00–15:50',
                                    ][i],
                            },
                        ],
                      }),
                      onPage: (_, _) async =>
                          const LeaveBridgeResult('unsupported'),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          if (section == 'courses-overlap-options') {
            await tester.tap(find.byKey(const ValueKey('leave-overlap-1-540')));
            await tester.pumpAndSettle();
          }
          // Widget tests disable system fallback for unqualified text. Use
          // the local font only there, preserving dedicated icon fonts.
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
                  ),
                );
              }
            }
          }
          await tester.pump();
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final directory = Directory('build/leave-native-preview');
            await directory.create(recursive: true);
            await File(
              '${directory.path}/${dark ? 'dark' : 'light'}-$section.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    });
  }
  testWidgets(
    'native form wraps at phone/tablet/desktop widths in all languages and themes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final width in [
        320.0,
        390.0,
        768.0,
        834.0,
        1024.0,
        1194.0,
        1440.0,
      ]) {
        tester.view.physicalSize = Size(width, 844);
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          for (final locale in [
            const Locale('en'),
            const Locale('zh', 'CN'),
            const Locale('zh', 'TW'),
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                locale: locale,
                supportedLocales: BnbuLocalizations.supportedLocales,
                localizationsDelegates: const [
                  BnbuLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Scaffold(
                  body: LeaveApplicationEditor(
                    key: ValueKey('$width-$theme-$locale'),
                    form: fixture(name: 'Example Student With A Long Name'),
                    busy: false,
                    onOpenSchool: (_, _) async {},
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text('Example Student With A Long Name'),
              findsOneWidget,
            );
            await tester.drag(find.byType(ListView), const Offset(0, -1600));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final editorRect = tester.getRect(find.byType(ListView));
            expect(editorRect.width, lessThanOrEqualTo(760));
          }
        }
      }
    },
  );

  testWidgets(
    'typing uses Flutter controls and only explicit user action hands off changes',
    (tester) async {
      final calls = <Map<String, String>>[];
      final sections = <LeaveSchoolSection>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveApplicationEditor(
              form: fixture(),
              busy: false,
              onOpenSchool: (section, changes) async {
                sections.add(section);
                calls.add(changes);
              },
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('leave-mobile'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '123456');
      expect(calls, isEmpty);
      final button = find.text('核对并提交');
      await tester.scrollUntilVisible(
        button,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pump();
      expect(sections, [LeaveSchoolSection.review]);
      expect(calls.single, {'mobile': '123456'});
    },
  );

  for (final dispose in [false, true]) {
    testWidgets(
      'course removal rejects stale confirmation (dispose=$dispose)',
      (tester) async {
        var removals = 0;
        Widget host(LeaveApplicationForm? form) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: form == null
                ? const Text('Signed out')
                : LeaveApplicationEditor(
                    form: form,
                    busy: false,
                    onOpenSchool: (_, _) async {},
                    onRemoveCourse: (_) async {
                      removals++;
                    },
                  ),
          ),
        );
        await tester.pumpWidget(host(fixture()));
        await tester.scrollUntilVisible(
          find.byTooltip('移除课程'),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('移除课程'));
        await tester.pumpAndSettle();
        expect(find.text('移除此课程？'), findsOneWidget);
        await tester.pumpWidget(
          host(dispose ? null : fixture(name: 'Updated school snapshot')),
        );
        await tester.pumpAndSettle();
        if (dispose) {
          expect(find.text('移除此课程？'), findsNothing);
        } else {
          await tester.tap(find.text('移除'));
          await tester.pumpAndSettle();
        }
        expect(removals, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'school acknowledgement updates draft; another account widget has no old data',
    (tester) async {
      Future<void> show(String owner) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LeaveApplicationEditor(
              key: ValueKey(owner),
              form: fixture(name: owner),
              busy: false,
              onOpenSchool: (_, _) async {},
            ),
          ),
        ),
      );
      await show('Synthetic A');
      final mobile = find.byKey(const ValueKey('leave-mobile'));
      await tester.ensureVisible(mobile);
      await tester.enterText(mobile, '11111');
      await show('Synthetic B');
      expect(find.text('Synthetic A'), findsNothing);
      expect(find.text('Synthetic B'), findsOneWidget);
      await tester.ensureVisible(mobile);
      expect(tester.widget<TextField>(mobile).controller!.text, isEmpty);
    },
  );
}
