import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_reveal_search.dart';

void main() {
  testWidgets('reveal first frame leaves room for the complete search label', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: BnbuRevealSearch(
              controller: controller,
              onChanged: (_) {},
              controlKey: const ValueKey('search'),
            ),
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('search'));
    final context = tester.element(field);
    final painter = TextPainter(
      text: TextSpan(text: '搜索', style: Theme.of(context).textTheme.bodyLarge),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelWidth = painter.width;
    painter.dispose();
    await tester.tap(field);
    await tester.pump();
    for (var frame = 0; frame < 14; frame++) {
      final editor = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      expect(
        tester.getSize(editor).width,
        greaterThanOrEqualTo(labelWidth),
        reason: 'frame $frame',
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
  });

  for (final preserve in [false, true]) {
    testWidgets('soft search passive dismissal preserves query=$preserve', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                BnbuRevealSearch(
                  controller: controller,
                  focusNode: focus,
                  onChanged: changes.add,
                  softMode: true,
                  preserveQueryOnDismiss: preserve,
                  controlKey: const ValueKey('search'),
                  closeKey: const ValueKey('close'),
                ),
                const Expanded(child: SizedBox.expand(key: ValueKey('blank'))),
              ],
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('search'));
      for (final dismissal in ['focus', 'outside', 'submit']) {
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'query');
        await tester.pumpAndSettle();
        changes.clear();
        switch (dismissal) {
          case 'focus':
            focus.unfocus();
          case 'outside':
            await tester.tapAt(
              tester.getCenter(find.byKey(const ValueKey('blank'))),
            );
          case 'submit':
            await tester.testTextInput.receiveAction(TextInputAction.search);
        }
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(controller.text, preserve ? 'query' : '');
        expect(changes, preserve ? isEmpty : ['']);
        expect(tester.getSize(field).width, preserve ? 800 : 100);
      }
      for (final dismissal in ['cancel', 'escape', 'back']) {
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'query');
        await tester.pumpAndSettle();
        switch (dismissal) {
          case 'cancel':
            await tester.tap(find.byKey(const ValueKey('close')));
          case 'escape':
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'back':
            await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(controller.text, isEmpty);
        expect(tester.getSize(field).width, 100);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'page search stays centered while its independent trailing action leaves',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 390,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BnbuRevealSearch(
                      controller: controller,
                      onChanged: (_) {},
                      controlKey: const ValueKey('search'),
                      closeKey: const ValueKey('close'),
                      trailingAction: IconButton(
                        key: const ValueKey('trailing'),
                        onPressed: () {},
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final field = find.byKey(const ValueKey('search'));
      final trailing = find.byKey(const ValueKey('trailing'));
      final collapsed = tester.getRect(field);
      expect(collapsed.width, 100);
      expect(collapsed.center.dx, 195);
      expect(trailing.hitTestable(), findsOneWidget);
      expect(tester.getRect(trailing).right, 390);
      expect(tester.getRect(trailing).overlaps(collapsed), isFalse);
      expect(
        tester.widget<TextField>(field).decoration?.fillColor,
        Colors.transparent,
      );

      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(field).width, greaterThan(collapsed.width));
      expect(tester.getRect(field).center.dx, 195);
      await tester.pumpAndSettle();
      expect(tester.getRect(field).width, 390);
      expect(trailing.hitTestable(), findsNothing);
      expect(
        tester.widget<TextField>(field).decoration?.fillColor,
        BnbuColorTokens.lightSurface,
      );
    },
  );

  testWidgets('escape clears and collapses an expanded search', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: BnbuRevealSearch(
              controller: controller,
              onChanged: changes.add,
              mode: BnbuRevealSearchMode.local,
              controlKey: const ValueKey('search'),
            ),
          ),
        ),
      ),
    );

    final field = find.byKey(const ValueKey('search'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'T3');
    expect(controller.text, 'T3');
    expect(tester.getRect(field).width, 260);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(changes.last, isEmpty);
    expect(tester.getRect(field).width, 100);
  });

  testWidgets(
    'reduced motion reveals immediately and initial text starts open',
    (tester) async {
      final controller = TextEditingController(text: 'T3-602');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: 280,
                child: BnbuRevealSearch(
                  controller: controller,
                  onChanged: (_) {},
                  controlKey: const ValueKey('search'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getRect(find.byKey(const ValueKey('search'))).width, 280);
      expect(controller.text, 'T3-602');
    },
  );
}
