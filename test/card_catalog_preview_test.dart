import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tool/card_catalog_preview.dart';
import '../tool/card_catalog/catalog_data.dart';
import '../tool/card_catalog/card_samples.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final macFace = File('/System/Library/Fonts/STHeiti Light.ttc');
    // Flutter's cached test font avoids Ahem's square Latin glyphs on hosts
    // without the macOS face used by the local visual review captures.
    final sdkFont = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
      '${Platform.pathSeparator}material_fonts'
      '${Platform.pathSeparator}Roboto-Regular.ttf',
    );
    final face = macFace.existsSync() ? macFace : sdkFont;
    expect(
      face.existsSync(),
      isTrue,
      reason: 'The pinned Flutter SDK must include its cached Roboto font.',
    );
    if (face.existsSync()) {
      for (final name in [
        'Roboto',
        'Ahem',
        '.SF Pro Text',
        '.SF Pro Display',
      ]) {
        await (FontLoader(name)..addFont(
              Future.value(ByteData.sublistView(await face.readAsBytes())),
            ))
            .load();
      }
    }
    for (final family
        in jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List) {
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  Future<void> sample(
    WidgetTester tester,
    CatalogEntry entry, {
    double width = 358,
    double scale = 1,
    bool dark = false,
    bool english = false,
    CatalogTextCase textCase = CatalogTextCase.normal,
    bool proposed = true,
    bool missingFields = false,
    double bottomInset = 12,
    VoidCallback? onOpen,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width + 32, 1800);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        locale: english ? const Locale('en') : const Locale('zh', 'CN'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width + 32, 1800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: const ValueKey('sample-capture'),
                  child: CatalogCardSample(
                    entry: entry,
                    fixture: CatalogFixture(
                      english: english,
                      textCase: textCase,
                      missingFields: missingFields,
                    ),
                    proposed: proposed,
                    bottomInset: bottomInset,
                    onOpen: onOpen ?? () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'proposed samples preserve bounded layouts in phone and wide large type',
    (tester) async {
      addTearDown(tester.view.reset);
      for (final width in [288.0, 358.0, 600.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final dark in [false, true]) {
            for (final entry in catalogEntries) {
              await sample(
                tester,
                entry,
                width: width,
                scale: scale,
                dark: dark,
                english: dark,
                textCase: CatalogTextCase.extreme,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${entry.id} $width/$scale/$dark',
              );
            }
          }
        }
      }
    },
  );

  testWidgets('summary footers do not move with one versus two title lines', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final kind in [
      CatalogKind.homeCourse,
      CatalogKind.homeDeadline,
      CatalogKind.ispaceDeadline,
      CatalogKind.agendaDeadline,
    ]) {
      final entry = catalogEntries.firstWhere((e) => e.kind == kind);
      await sample(tester, entry, textCase: CatalogTextCase.short);
      final first = tester.getRect(
        find.byKey(ValueKey('proposed-footer-${entry.id}')),
      );
      await sample(tester, entry, textCase: CatalogTextCase.long);
      final second = tester.getRect(
        find.byKey(ValueKey('proposed-footer-${entry.id}')),
      );
      expect(first.top, closeTo(second.top, .1), reason: entry.id);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('course family preserves original field roles at fixed corners', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final width in [288.0, 358.0, 600.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final kind in [
          CatalogKind.agendaCourse,
          CatalogKind.courseDetail,
          CatalogKind.agendaTa,
          CatalogKind.agendaEvent,
        ]) {
          for (final textCase in [
            CatalogTextCase.short,
            CatalogTextCase.extreme,
          ]) {
            final entry = catalogEntries.firstWhere((e) => e.kind == kind);
            await sample(
              tester,
              entry,
              width: width,
              scale: scale,
              textCase: textCase,
            );
            final frame = tester.getRect(find.byType(BnbuSurfaceCard));
            final clock = tester.getRect(find.byIcon(LucideIcons.clock3300));
            final time = tester.getRect(find.text('14:00 - 15:50'));
            final location = tester.getRect(find.byIcon(LucideIcons.mapPin300));
            expect(clock.left, closeTo(frame.left + 21, .1), reason: entry.id);
            expect(clock.top, closeTo(frame.top + 12, .1), reason: entry.id);
            expect(time.left, closeTo(clock.right + 8, .1), reason: entry.id);
            expect(location.left, closeTo(clock.left, .1), reason: entry.id);
            expect(
              location.bottom,
              closeTo(frame.bottom - 12, .1),
              reason: entry.id,
            );
            if (kind != CatalogKind.courseDetail) {
              final arrow = tester.getRect(
                find.byIcon(LucideIcons.arrowRight300),
              );
              expect(
                arrow.right,
                closeTo(frame.right - 12, .1),
                reason: entry.id,
              );
              expect(arrow.top, closeTo(frame.top + 12, .1), reason: entry.id);
            } else {
              expect(find.byIcon(LucideIcons.arrowRight300), findsNothing);
            }
            if (kind == CatalogKind.agendaCourse ||
                kind == CatalogKind.courseDetail) {
              final teacher = tester.getRect(
                find.byIcon(LucideIcons.contactRound300),
              );
              expect(
                teacher.right,
                closeTo(frame.right - 12, .1),
                reason: entry.id,
              );
              expect(
                teacher.bottom,
                closeTo(frame.bottom - 12, .1),
                reason: entry.id,
              );
              final hit = find
                  .ancestor(
                    of: find.byIcon(LucideIcons.contactRound300),
                    matching: find.byType(InkWell),
                  )
                  .first;
              expect(tester.getSize(hit).height, greaterThanOrEqualTo(44));
            } else {
              expect(find.byIcon(LucideIcons.contactRound300), findsNothing);
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.id} $width $scale',
            );
          }
        }
      }
    }
  });

  testWidgets(
    'corner insets survive missing teacher and custom bottom spacing',
    (tester) async {
      addTearDown(tester.view.reset);
      for (final kind in [
        CatalogKind.agendaCourse,
        CatalogKind.courseDetail,
        CatalogKind.agendaTa,
        CatalogKind.agendaEvent,
      ]) {
        for (final missing in [false, true]) {
          for (final bottom in [8.0, 12.0, 20.0]) {
            var taps = 0;
            final entry = catalogEntries.firstWhere((e) => e.kind == kind);
            await sample(
              tester,
              entry,
              missingFields: missing,
              bottomInset: bottom,
              onOpen: () => taps++,
            );
            final frame = tester.getRect(find.byType(BnbuSurfaceCard));
            final pin = tester.getRect(find.byIcon(LucideIcons.mapPin300));
            expect(pin.bottom, closeTo(frame.bottom - bottom, .1));
            final teacher = find.byIcon(LucideIcons.contactRound300);
            if (missing ||
                kind == CatalogKind.agendaTa ||
                kind == CatalogKind.agendaEvent) {
              expect(teacher, findsNothing);
            } else {
              final rect = tester.getRect(teacher);
              expect(rect.right, closeTo(frame.right - 12, .1));
              expect(rect.bottom, closeTo(frame.bottom - bottom, .1));
              await tester.tap(teacher);
              expect(taps, 1);
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets(
    'gallery controls and rule sheets remain usable across window sizes',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      for (final width in [390.0, 900.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(const CardCatalogPreview());
        await tester.pumpAndSettle();
        await tester.tap(find.text('设计规则').first);
        await tester.pumpAndSettle();
        expect(find.text('高度与溢出'), findsOneWidget);
        await tester.tap(find.text('关闭').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('catalog-theme')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('local review renders for summary and detail pairs', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final directory = Directory('build/card-catalog-evidence')
      ..createSync(recursive: true);
    for (final kind in [
      CatalogKind.homeCourse,
      CatalogKind.ispaceDeadline,
      CatalogKind.deadlineDetail,
      CatalogKind.agendaCourse,
      CatalogKind.agendaDeadline,
      CatalogKind.examWeek,
    ]) {
      final entry = catalogEntries.firstWhere((e) => e.kind == kind);
      for (final proposed in [false, true]) {
        await sample(
          tester,
          entry,
          textCase: CatalogTextCase.short,
          proposed: proposed,
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('sample-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${directory.path}/${entry.id}-${proposed ? 'proposed' : 'current'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    }
  });
}
