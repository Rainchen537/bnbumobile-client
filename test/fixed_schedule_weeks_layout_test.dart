import 'dart:io';
import 'dart:ui' as ui;

import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';
import 'package:bnbu_me/widgets/fixed_schedule_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixed_schedule_weeks_test.dart' show calendarTimetable, weeklyEntry;

const _preview = bool.fromEnvironment('FIXED_WEEKS_PREVIEWS');
const _panel = ValueKey('fixed-weeks-panel');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!_preview) return;
    final bytes = ByteData.sublistView(
      await File('/System/Library/Fonts/SFNS.ttf').readAsBytes(),
    );
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('WeeksPreviewCJK')..addFont(
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
  });

  Future<double> open(
    WidgetTester tester, {
    Size size = const Size(402, 874),
    double scale = 1,
    Locale locale = const Locale('zh', 'CN'),
    bool dark = false,
    bool glass = false,
    bool unknown = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    SharedPreferences.setMockInitialValues({
      AppThemeModeController.liquidGlassPreferenceKey: glass,
    });
    final appearance = AppThemeModeController(
      liquidGlassSupportLoader: () async => true,
    );
    await appearance.restore();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
      tester.view.reset();
    });
    final base = dark ? AppTheme.dark : AppTheme.light;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          platform: size.width < 1200
              ? TargetPlatform.iOS
              : TargetPlatform.macOS,
          textTheme: _preview
              ? base.textTheme.apply(
                  fontFamilyFallback: const ['WeeksPreviewCJK'],
                )
              : null,
        ),
        locale: locale,
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('weeks-preview'),
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: BnbuLiquidGlassScope(controller: appearance, child: child!),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const BnbuText('固定日程')),
            body: TextButton(
              onPressed: () => showBnbuCreationModal<void>(
                context: context,
                builder: (context, presentation) => FixedScheduleEditor(
                  timetable: calendarTimetable(
                    name: unknown ? 'unknown' : null,
                  ),
                  initialEntry: unknown
                      ? weeklyEntry(weeks: [DateTime(2026, 12, 28)])
                      : null,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final editorHeight = tester.getSize(find.byType(BnbuCreationForm)).height;
    await tester.ensureVisible(
      find.byKey(const ValueKey('fixed-schedule-weeks')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fixed-schedule-weeks')));
    await tester.pumpAndSettle();
    return editorHeight;
  }

  for (final size in [
    const Size(402, 874),
    const Size(820, 1180),
    const Size(1180, 820),
    const Size(1440, 960),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('bounded solid week panel matches editor $size dark=$dark', (
        tester,
      ) async {
        final editorHeight = await open(
          tester,
          size: size,
          dark: dark,
          glass: true,
        );
        final panel = tester.getRect(find.byKey(_panel));
        expect(
          panel.height,
          closeTo(
            editorHeight.clamp(0.0, (size.height * .7).clamp(0.0, 720.0)),
            1,
          ),
        );
        expect(panel.height, lessThanOrEqualTo(size.height * .7));
        expect(
          panel.width,
          lessThanOrEqualTo(size.width < 700 ? size.width : 560),
        );
        final surface = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byKey(_panel),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        final context = tester.element(find.byKey(_panel));
        expect(surface.color, context.bnbuTheme.canvas);
        expect(surface.color.a, 1);
        expect(find.text('第 1 周 · 教学开始周'), findsOneWidget);
        if (_preview && size.width == 402) {
          await savePreview(tester, '402-start-${dark ? 'dark' : 'light'}');
        }
        final saveRect = tester.getRect(
          find.byKey(const ValueKey('fixed-weeks-save')),
        );
        await reveal(tester, 'fixed-weeks-2026-09-21');
        expect(find.textContaining('9/25–9/27 中秋节假期'), findsOneWidget);
        if (_preview) {
          await savePreview(
            tester,
            '${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
        }
        await reveal(tester, 'fixed-weeks-2026-09-28');
        expect(find.textContaining('10/1–10/4 国庆节假期'), findsOneWidget);
        await reveal(tester, 'fixed-weeks-2026-10-19');
        expect(find.textContaining('10/25 Reading Week'), findsOneWidget);
        await reveal(tester, 'fixed-weeks-2026-10-26');
        expect(find.textContaining('10/26–10/31 Reading Week'), findsOneWidget);
        if (_preview && size.width == 402) {
          await savePreview(tester, '402-reading-${dark ? 'dark' : 'light'}');
        }
        await reveal(tester, 'fixed-weeks-2026-12-07');
        expect(find.text('第 15 周 · 教学结束周'), findsOneWidget);
        expect(tester.getRect(find.byKey(_panel)), panel);
        expect(
          tester.getRect(find.byKey(const ValueKey('fixed-weeks-save'))),
          saveRect,
        );
        expect(
          find.byKey(const ValueKey('fixed-weeks-save')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('fixed-weeks-cancel')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final locale in [
    const Locale('en'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets(
      'small large-type panel scrolls labels without clipping $locale',
      (tester) async {
        await open(
          tester,
          size: const Size(320, 700),
          scale: 1.8,
          locale: locale,
          dark: true,
        );
        await reveal(tester, 'fixed-weeks-2026-09-21');
        expect(
          find.textContaining(
            locale.languageCode == 'en' ? 'Mid-Autumn Festival' : '中秋節假期',
          ),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(_panel)).height,
          lessThanOrEqualTo(490),
        );
        expect(
          find.byKey(const ValueKey('fixed-weeks-save')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('fixed-weeks-cancel')).hitTestable(),
          findsOneWidget,
        );
        if (_preview) {
          await savePreview(tester, '320-large-${locale.toLanguageTag()}');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unknown semester keeps cross-year dates without invented labels',
    (tester) async {
      await open(tester, unknown: true);
      expect(find.text('2026 · 12/28–2027/1/3'), findsOneWidget);
      expect(find.textContaining('教学开始周'), findsNothing);
      expect(find.textContaining('第 1 周'), findsNothing);
      expect(find.text('当前学期校历不可用，请手动选择周'), findsOneWidget);
      expect(find.byKey(const ValueKey('fixed-weeks-default')), findsNothing);
      expect(
        find.byKey(const ValueKey('fixed-weeks-add')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> reveal(WidgetTester tester, String key) async {
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('fixed-weeks-list')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    150,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}

Future<void> savePreview(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('weeks-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/fixed-weeks-previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
