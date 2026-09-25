import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bnbu_me/pages/cis_checkin_page.dart';
import 'package:bnbu_me/models/cis_checkin.dart';
import 'package:bnbu_me/pages/home_page.dart';
import 'package:bnbu_me/services/cis_checkin_client.dart';
import 'package:bnbu_me/services/home_card_visibility_service.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/cis_checkin_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/cis_checkin_fixtures.dart';

const preview = bool.fromEnvironment('CIS_CHECKIN_PREVIEWS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (!preview) return;
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                await File('/System/Library/Fonts/SFNS.ttf').readAsBytes(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader('CheckinCJK')..addFont(
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
    // The framework's unstyled header fallback is Ahem in Widget tests.
    // Replace that test-only face so Chinese headers can be visually reviewed.
    await (FontLoader('Ahem')..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '/System/Library/Fonts/STHeiti Light.ttc',
              ).readAsBytes(),
            ),
          ),
        ))
        .load();
  });

  Future<void> pump(
    WidgetTester tester,
    CheckinFixtureController source, {
    double width = 390,
    Locale locale = const Locale('en'),
    bool dark = false,
    Widget? child,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = dark ? AppTheme.dark : AppTheme.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: preview
            ? theme.copyWith(
                appBarTheme: theme.appBarTheme.copyWith(
                  titleTextStyle: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'CheckinCJK',
                  ),
                ),
                textTheme: theme.textTheme.apply(
                  fontFamilyFallback: ['CheckinCJK'],
                ),
              )
            : theme,
        locale: locale,
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('checkin-preview'),
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.5 : 1)),
            child: child!,
          ),
        ),
        home: child ?? CisCheckinPage(controller: source),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 768.0, 900.0, 1440.0]) {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
    ]) {
      testWidgets(
        'native check-in list/detail $width ${locale.toLanguageTag()}',
        (tester) async {
          final source = CheckinFixtureController();
          addTearDown(source.dispose);
          await pump(
            tester,
            source,
            width: width,
            locale: locale,
            dark: width == 900,
          );
          expect(
            find.byKey(const ValueKey('cis-project-project-1')),
            findsOneWidget,
          );
          expect(
            find.text(BnbuLocalizations(locale).text('打卡记录')),
            findsNothing,
          );
          expect(
            find.text(BnbuLocalizations(locale).text('打卡项目')),
            findsNothing,
          );
          expect(find.textContaining('12 /'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('cis-project-project-3')),
            120,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('cis-project-list')),
              matching: find.byType(Scrollable),
            ),
          );
          expect(find.textContaining('0 /'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('cis-project-project-1')),
            -160,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('cis-project-list')),
              matching: find.byType(Scrollable),
            ),
          );
          if (preview && width == 390 && locale.countryCode == 'CN') {
            await screenshot(tester, 'mobile-projects');
          }
          await tester.tap(find.byKey(const ValueKey('cis-project-project-1')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('cis-record-project-1-1')),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('cis-record-project-1-incomplete')),
            140,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('cis-record-list')),
              matching: find.byType(Scrollable),
            ),
          );
          expect(
            find.byKey(const ValueKey('cis-record-project-1-incomplete')),
            findsOneWidget,
          );
          await tester.drag(
            find.byKey(const ValueKey('cis-record-list')),
            const Offset(0, 1000),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('cis-project-list')),
            width >= 880 ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
          if (preview &&
              locale.countryCode == 'CN' &&
              [390.0, 900.0, 1440.0].contains(width)) {
            await screenshot(tester, 'detail-${width.toInt()}');
          }
          if (width < 880) {
            await tester.tap(
              find.byTooltip(BnbuLocalizations(locale).text('返回')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('cis-project-list')),
              findsOneWidget,
            );
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'expanded records show school timestamps without further requests',
    (tester) async {
      final source = CheckinFixtureController();
      addTearDown(source.dispose);
      await pump(tester, source);
      await tester.tap(find.byKey(const ValueKey('cis-project-project-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Synthetic event').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic speaker'), findsOneWidget);
      expect(find.textContaining('13:55'), findsOneWidget);
      expect(find.textContaining('16:02'), findsOneWidget);
      expect(source.recordCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    for (final (checkedIn, checkedOut) in [
      (false, true),
      (true, false),
      (false, false),
      (true, true),
    ]) {
      testWidgets(
        'check-in $checkedIn / check-out $checkedOut uses red x or green check, dark=$dark',
        (tester) async {
          final source = CheckinFixtureController();
          addTearDown(source.dispose);
          final record = CisCheckinRecord.fromJson({
            ...checkinRecordJson(completed: checkedIn && checkedOut),
            'mainCheckinFinish': checkedIn,
            'mainCheckoutFinish': checkedOut,
          });
          await pump(
            tester,
            source,
            dark: dark,
            child: Scaffold(body: CisRecordCard(record: record)),
          );
          final failures = [
            checkedIn,
            checkedOut,
          ].where((value) => !value).length;
          expect(find.byIcon(LucideIcons.x300), findsNWidgets(failures));
          expect(
            find.byIcon(LucideIcons.check300),
            findsNWidgets(2 - failures),
          );
          expect(find.byIcon(LucideIcons.minus300), findsNothing);
          final background =
              (dark ? BnbuThemeExtension.dark : BnbuThemeExtension.light)
                  .surface
                  .computeLuminance();
          for (final element in find.byIcon(LucideIcons.x300).evaluate()) {
            final color = (element.widget as Icon).color!;
            expect(color.r, greaterThan(color.g));
            final foreground = color.computeLuminance();
            final contrast = foreground > background
                ? (foreground + .05) / (background + .05)
                : (background + .05) / (foreground + .05);
            expect(contrast, greaterThanOrEqualTo(3));
          }
          for (final element in find.byIcon(LucideIcons.check300).evaluate()) {
            final color = (element.widget as Icon).color!;
            expect(color.g, greaterThan(color.r));
          }
          final finalStatus = tester.widget<Text>(
            find.text(
              const BnbuLocalizations(
                Locale('en'),
              ).text(record.completed ? '已完成' : '未完成'),
            ),
          );
          final matchingIcon = tester.widget<Icon>(
            find
                .byIcon(
                  record.completed ? LucideIcons.check300 : LucideIcons.x300,
                )
                .first,
          );
          expect(
            finalStatus.style!.color,
            matchingIcon.color,
            reason:
                'The record final status uses green for completed and red for uncompleted',
          );
          final luminance = finalStatus.style!.color!.computeLuminance();
          final textContrast = luminance > background
              ? (luminance + .05) / (background + .05)
              : (background + .05) / (luminance + .05);
          expect(textContrast, greaterThanOrEqualTo(4.5));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'unknown statistics is not shown as a genuine empty school history',
    (tester) async {
      final source = CheckinFixtureController()..unknownRecordStatistics = true;
      addTearDown(source.dispose);
      await pump(tester, source);
      await tester.tap(find.byKey(const ValueKey('cis-project-project-1')));
      await tester.pumpAndSettle();
      expect(
        find.text('The school has not provided a verifiable statistics status'),
        findsOneWidget,
      );
      expect(find.text('No finalized check-in records'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('filter lives in the app bar without a refresh action', (
    tester,
  ) async {
    final source = CheckinFixtureController();
    addTearDown(source.dispose);
    await pump(tester, source);
    expect(find.byTooltip('Refresh'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const ValueKey('cis-project-filter')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('cis-project-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cis-project-project-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('cis-project-project-1')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'resizing preserves the selected record pane and expanded details',
    (tester) async {
      final source = CheckinFixtureController();
      addTearDown(source.dispose);
      await pump(tester, source, width: 900);
      await tester.tap(find.byKey(const ValueKey('cis-project-project-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Synthetic event').first);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpAndSettle();
      expect(source.recordCalls, 1);
      expect(find.textContaining('Synthetic speaker'), findsOneWidget);
      expect(find.byKey(const ValueKey('cis-project-filter')), findsNothing);
      tester.view.physicalSize = const Size(900, 900);
      await tester.pumpAndSettle();
      expect(source.recordCalls, 1);
      expect(find.byKey(const ValueKey('cis-project-filter')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('completed labels meet AA contrast on the dark card surface', (
    tester,
  ) async {
    final source = CheckinFixtureController();
    addTearDown(source.dispose);
    await pump(tester, source, width: 900, dark: true);
    final text = tester.widget<Text>(find.text('Completed').first);
    final foreground = text.style!.color!.computeLuminance();
    final background = BnbuThemeExtension.dark.surface.computeLuminance();
    expect((foreground + .05) / (background + .05), greaterThanOrEqualTo(4.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'empty filtered pages continue and retain Load more past bounded batch',
    (tester) async {
      final source = CheckinFixtureController()..blankRecordPages = 4;
      addTearDown(source.dispose);
      await pump(tester, source);
      await tester.tap(find.byKey(const ValueKey('cis-project-project-1')));
      await tester.pumpAndSettle();
      expect(source.recordCalls, 3);
      expect(find.text('No finalized check-in records'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(source.recordCalls, 5);
      expect(find.byType(CisRecordCard), findsNWidgets(2));
      expect(find.text('Load more'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'project switch discards late records and logout clears all visible data',
    (tester) async {
      final source = CheckinFixtureController();
      addTearDown(source.dispose);
      await pump(tester, source, width: 1440);
      final gate = Completer<void>();
      source.recordGate = gate;
      await tester.tap(find.byKey(const ValueKey('cis-project-project-1')));
      await tester.pump();
      source.recordGate = null;
      await tester.tap(find.byKey(const ValueKey('cis-project-project-2')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cis-record-project-2-1')),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cis-record-project-1-1')),
        findsNothing,
      );
      source.expire();
      await tester.pumpAndSettle();
      expect(find.byType(CisProjectCard), findsNothing);
      expect(find.byType(CisRecordCard), findsNothing);
      expect(find.textContaining('Your login has changed.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'refresh errors preserve previous result without exposing upstream text',
    (tester) async {
      final source = CheckinFixtureController();
      addTearDown(source.dispose);
      await pump(tester, source);
      source.projectFailure = StateError('synthetic-sensitive-upstream');
      await tester.drag(
        find.byKey(const ValueKey('cis-project-list')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CisProjectCard), findsNWidgets(3));
      expect(find.textContaining('synthetic-sensitive'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      source.projectFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reopened page keeps cached projects visible when revalidation fails',
    (tester) async {
      final source = CheckinFixtureController()
        ..hasCachedProjects = true
        ..projectFailure = const CisCheckinException(CisCheckinFailure.network);
      addTearDown(source.dispose);
      await pump(tester, source);
      expect(find.byType(CisProjectCard), findsNWidgets(3));
      expect(find.text('Retry'), findsOneWidget);
      source.expire();
      await tester.pumpAndSettle();
      expect(find.byType(CisProjectCard), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('permission denial is distinct from an empty project list', (
    tester,
  ) async {
    final source = CheckinFixtureController()
      ..projectFailure = const CisCheckinException(
        CisCheckinFailure.permission,
      );
    addTearDown(source.dispose);
    await pump(tester, source);
    expect(
      find.text('This account cannot access the school check-in system.'),
      findsOneWidget,
    );
    expect(find.text('No matching check-in projects'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'home adds a check-in entry without replacing leave and follows visibility',
    (tester) async {
      final source = _HomeCheckinFixture();
      addTearDown(source.dispose);
      await pump(
        tester,
        source,
        width: 1440,
        child: HomePage(
          controller: source,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
          homeCardVisibilityService: const DefaultHomeCardVisibilityService(),
        ),
      );
      expect(source.projectCalls, 1);
      source.notifyListeners();
      await tester.pumpAndSettle();
      expect(source.projectCalls, 1);
      expect(find.text('Leave Request'), findsOneWidget);
      await tester.ensureVisible(find.text('Check-in overview'));
      await tester.tap(find.text('Check-in overview'));
      await tester.pumpAndSettle();
      expect(find.byType(CisCheckinPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _HomeCheckinFixture extends CheckinFixtureController {
  @override
  Future<void> refreshTimetable() async {}
  @override
  Future<void> refreshTimeline() async {}
}

Future<void> screenshot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('checkin-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/checkin-previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
