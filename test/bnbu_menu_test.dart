import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_menu.dart';

void main() {
  testWidgets(
    'choice rows preserve radio selection, disabled state and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var selected = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => RadioGroup<int>(
                groupValue: selected,
                onChanged: (value) => setState(() => selected = value!),
                child: Column(
                  children: [
                    BnbuChoiceTile(
                      value: 1,
                      selected: selected == 1,
                      title: const Text('Follow application appearance'),
                    ),
                    BnbuChoiceTile(
                      value: 2,
                      selected: selected == 2,
                      title: const Text('浅色'),
                    ),
                    const BnbuChoiceTile(
                      value: 3,
                      selected: false,
                      enabled: false,
                      title: Text('不可用'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('浅色'));
      await tester.pump();
      expect(selected, 2);
      await tester.tap(find.text('不可用'));
      await tester.pump();
      expect(selected, 2);
      for (final tile in find.byType(RadioListTile<int>).evaluate()) {
        expect(
          tester.getSize(find.byWidget(tile.widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('menu preserves selection, cancel and focus dark=$dark', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var value = 'week';
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
            highlightColor: const Color(0xFFFF00FF),
          ),
          home: Scaffold(
            body: Center(
              child: BnbuMenuButton<String>(
                focusNode: focus,
                initialValue: value,
                onSelected: (selected) => value = selected,
                onCanceled: () => cancelled++,
                itemBuilder: (_) => [
                  BnbuMenuItem(
                    value: 'week',
                    selected: true,
                    child: const Text('本周'),
                  ),
                  BnbuMenuItem(value: 'all', child: const Text('全部')),
                  BnbuMenuItem(
                    value: 'disabled',
                    enabled: false,
                    child: const Text('不可用'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('筛选'),
                ),
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == const Color(0xFFFF00FF),
        ),
        findsNothing,
      );
      final selectedContext = tester.element(find.text('本周'));
      final selectedSurface = selectedContext.bnbuTheme.selectedSurface;
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color == selectedSurface,
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('不可用'));
      expect(value, 'week');
      expect(find.text('全部'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(value, 'week');
      expect(cancelled, 1);
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(value, 'all');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long large-text menu wraps within the phone and keeps targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: BnbuMenuButton<int>(
            itemBuilder: (_) => [
              BnbuMenuItem(
                value: 1,
                child: const Text('Complete course materials'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final item = tester.getRect(find.byType(BnbuMenuItem<int>));
    expect(item.left, greaterThanOrEqualTo(0));
    expect(item.right, lessThanOrEqualTo(320));
    expect(item.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
