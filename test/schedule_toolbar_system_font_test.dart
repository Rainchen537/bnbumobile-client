import 'dart:io';

import 'package:bnbu_me/pages/schedule_page.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/home_navigation_fixtures.dart';

/// Local Apple font measurement supplements the platform-independent Ahem
/// accessibility and overflow coverage in schedule_page_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final systemFont = File('/System/Library/Fonts/SFNS.ttf');
  setUpAll(() async {
    if (!systemFont.existsSync()) return;
    final bytes = ByteData.sublistView(await systemFont.readAsBytes());
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });

  for (final width in [375.0, 390.0, 402.0, 430.0]) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      const Locale('en'),
    ]) {
      testWidgets(
        'system font keeps all phone controls visible: $width $locale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 874);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          for (final start in [
            DateTime(2026, 9, 7),
            DateTime(2026, 10, 19),
            DateTime(2026, 10, 26),
            DateTime(2026, 12, 21),
            DateTime(2026, 12, 28),
          ]) {
            final session = HomeNavigationFixture();
            final ta = TaCourseController(sessionController: session);
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
                locale: locale,
                supportedLocales: BnbuLocalizations.supportedLocales,
                localizationsDelegates: const [
                  BnbuLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: SchedulePage(
                  controller: session,
                  taCourseController: ta,
                  now: start,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final toolbar = tester.getRect(
              find.byKey(const ValueKey('schedule-toolbar')),
            );
            expect(toolbar.height, 44);
            final scroll = tester.state<ScrollableState>(
              find.descendant(
                of: find.byKey(const ValueKey('schedule-phone-toolbar-scroll')),
                matching: find.byType(Scrollable),
              ),
            );
            expect(
              scroll.position.maxScrollExtent,
              0,
              reason: '$width $locale $start 常规字号下所有操作必须直接可见',
            );
            for (final action in [
              'view-toggle',
              'locate-action',
              'previous-week',
              'week-picker',
              'next-week',
              'deadline-toggle',
              'ta-action',
            ]) {
              final target = tester.getRect(
                find.byKey(ValueKey('schedule-$action')),
              );
              expect(target.left, greaterThanOrEqualTo(12));
              expect(target.right, lessThanOrEqualTo(width - 12));
              expect(target.width, greaterThanOrEqualTo(44));
              expect(target.height, greaterThanOrEqualTo(44));
              expect(target.center.dy, closeTo(toolbar.center.dy, 0.01));
            }
            final date = find.byKey(
              const ValueKey('schedule-week-range-label'),
            );
            final calendar = find.descendant(
              of: find.byKey(const ValueKey('schedule-week-picker')),
              matching: find.byIcon(LucideIcons.calendarRange300),
            );
            expect(calendar, findsNothing, reason: '全部周次的日期都不再显示日历');
            expect(
              tester.getRect(date).center.dx,
              closeTo(toolbar.center.dx, .01),
            );
            final fontSize = tester.widget<Text>(date).style!.fontSize!;
            expect(fontSize, inInclusiveRange(13, 15.4));
            if (start == DateTime(2026, 9, 7) || width == 430) {
              expect(fontSize, 15.4, reason: '空间足够时保持原日期字号');
            } else if (start == DateTime(2026, 10, 19) && width == 375) {
              expect(fontSize, lessThanOrEqualTo(15.4), reason: '长日期只适当缩小数字');
            }
            final end = start.add(const Duration(days: 6));
            expect(
              tester.widget<Text>(date).data,
              '${start.month}/${start.day}–${end.month}/${end.day}',
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: date, matching: find.byType(RichText)),
            );
            expect(paragraph.didExceedMaxLines, isFalse);
            if (start == DateTime(2026, 10, 19)) {
              final pickerBefore = tester.getRect(
                find.byKey(const ValueKey('schedule-week-picker')),
              );
              final dateBefore = tester.getRect(date);
              await tester.tap(
                find.byKey(const ValueKey('schedule-view-toggle')),
              );
              await tester.pumpAndSettle();
              expect(calendar, findsNothing);
              expect(tester.getRect(date), dateBefore);
              expect(tester.widget<Text>(date).style!.fontSize, fontSize);
              final picker = find.byKey(const ValueKey('schedule-week-picker'));
              expect(
                tester.getRect(picker),
                pickerBefore,
                reason: '横、竖表共用相同日期及图标布局',
              );
              await tester.tap(picker);
              await tester.pumpAndSettle();
              final weeks = find.byWidgetPredicate(
                (widget) =>
                    widget is InkWell &&
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'fixed-schedule-week-',
                    ),
              );
              expect(weeks, findsNWidgets(6));
              Navigator.of(tester.element(weeks.first)).pop();
              await tester.pumpAndSettle();
              expect(calendar, findsNothing);
              if (width == 402 && locale.languageCode == 'en') {
                for (var week = 0; week < 6; week++) {
                  await tester.tap(
                    find.byKey(const ValueKey('schedule-previous-week')),
                  );
                  await tester.pumpAndSettle();
                }
                expect(tester.widget<Text>(date).data, '9/7–9/13');
                expect(
                  tester.widget<Text>(date).style!.fontSize,
                  15.4,
                  reason: '同一页面切回短日期必须恢复原字号',
                );
                expect(calendar, findsNothing);
              }
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            ta.dispose();
            session.dispose();
          }
        },
        skip: !systemFont.existsSync(),
      );
    }
  }
}
