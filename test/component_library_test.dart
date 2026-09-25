import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/component_library_preview.dart';

void main() {
  for (final width in [280.0, 390.0, 760.0]) {
    for (final label in ['搜索', 'Search']) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('every reveal frame fits $label at $width / $scale', (
          tester,
        ) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SizedBox(
                    width: width,
                    child: BnbuRevealSearch.hidden(
                      controller: controller,
                      onChanged: (_) {},
                      hintText: label,
                      collapsedLabel: label,
                      controlKey: const ValueKey('field'),
                    ),
                  ),
                ),
              ),
            ),
          );
          final field = find.byKey(const ValueKey('field'));
          final painter = TextPainter(
            text: TextSpan(
              text: label,
              style: Theme.of(tester.element(field)).textTheme.bodyLarge,
            ),
            textScaler: TextScaler.linear(scale),
            textDirection: TextDirection.ltr,
          )..layout();
          final minimumTextWidth = painter.width;
          painter.dispose();
          await tester.tap(field);
          await tester.pump();
          for (var frame = 0; frame < 15; frame++) {
            final editor = find.descendant(
              of: field,
              matching: find.byType(EditableText),
            );
            expect(
              tester.getSize(editor).width,
              greaterThanOrEqualTo(minimumTextWidth),
              reason: 'frame $frame',
            );
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pumpAndSettle();
        });
      }
    }
  }

  for (final dark in [false, true]) {
    for (final persistent in [false, true]) {
      testWidgets(
        'search border half contrast dark=$dark persistent=$persistent',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          final search = persistent
              ? BnbuRevealSearch.persistent
              : BnbuRevealSearch.hidden;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: Scaffold(
                body: SizedBox(
                  width: 358,
                  child: search(
                    controller: controller,
                    onChanged: (_) {},
                    controlKey: const ValueKey('field'),
                  ),
                ),
              ),
            ),
          );
          final field = find.byKey(const ValueKey('field'));
          await tester.tap(field);
          await tester.pumpAndSettle();
          final decoration = tester.widget<TextField>(field).decoration!;
          final tokens = tester.element(field).bnbuTheme;
          final focus = dark
              ? BnbuColorTokens.darkSearchFocus
              : BnbuColorTokens.lightSearchFocus;
          expect(
            decoration.enabledBorder!.borderSide.color,
            tokens.border.withValues(alpha: tokens.border.a * .5),
          );
          expect(
            decoration.focusedBorder!.borderSide.color,
            focus.withValues(alpha: focus.a * .5),
          );
          expect(decoration.focusedBorder!.borderSide.width, 1.4);
          await tester.enterText(field, 'query');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(controller.text, isEmpty);
          expect(tester.getSize(field).width, persistent ? 358 : 100);
        },
      );
    }
  }
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('library controls stretch and keep state at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ComponentLibraryPreview());
      final hidden = find.byKey(const ValueKey('library-hidden-search'));
      final persistent = find.byKey(
        const ValueKey('library-persistent-search'),
      );
      await tester.tap(hidden);
      await tester.pumpAndSettle();
      await tester.enterText(hidden, 'T3');
      await tester.tap(find.text('宽屏'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(hidden).controller!.text, 'T3');
      expect(tester.getSize(persistent).width, width == 390 ? 350 : 760);
      await tester.tap(find.byKey(const ValueKey('library-persistent-close')));
      await tester.pumpAndSettle();
      expect(tester.getSize(persistent).width, width == 390 ? 350 : 760);
      await tester.tap(find.byKey(const ValueKey('library-menu')));
      await tester.pumpAndSettle();
      expect(find.byType(BnbuMenuItem<String>), findsNWidgets(6));
      await tester.tap(find.text('已发送'));
      await tester.pumpAndSettle();
      expect(find.text('已发送'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('library-theme')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(hidden).controller!.text, 'T3');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
