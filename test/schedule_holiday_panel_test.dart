import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/widgets/schedule_holiday_panel.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Holiday bounds survive scroll and resize $brightness $scale', (
        tester,
      ) async {
        final scroll = _HolidayScrollController();
        final viewportKey = GlobalKey();
        const labelKey = ValueKey('holiday-label');
        addTearDown(scroll.dispose);
        tester.view.physicalSize = const Size(900, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var taps = 0;

        Widget page({
          required double precedingHeight,
          bool reduceMotion = false,
          bool tickerEnabled = true,
          ScrollController? controller,
        }) => MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) =>
              TickerMode(enabled: tickerEnabled, child: child!),
          home: Scaffold(
            body: Padding(
              // Simulates surrounding app chrome, safe area and bottom navigation.
              padding: const EdgeInsets.fromLTRB(100, 80, 100, 90),
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: CustomScrollView(
                  key: viewportKey,
                  controller: controller ?? scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(height: precedingHeight),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 1400,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 48,
                              top: 0,
                              width: 100,
                              height: 1400,
                              child: ScheduleHolidayPanel(
                                scrollController: controller ?? scroll,
                                viewportKey: viewportKey,
                                pinnedHeaderExtent: 56,
                                rowHeight: 72,
                                reduceMotion: reduceMotion,
                                backgroundColor: Colors.amber.shade100,
                                borderColor: Colors.amber,
                                child: const Text(
                                  'Reading Week\n假期',
                                  key: labelKey,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 48,
                              top: 250,
                              width: 100,
                              height: 60,
                              child: GestureDetector(
                                onTap: () => taps++,
                                child: const ColoredBox(
                                  color: Colors.blue,
                                  child: Text('DDL'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 700)),
                  ],
                ),
              ),
            ),
          ),
        );

        Rect panelBounds() {
          final panel = tester.renderObject<RenderScheduleHolidayPanel>(
            find.byType(ScheduleHolidayPanel),
          );
          return panel.visiblePanelBounds.shift(
            panel.localToGlobal(Offset.zero),
          );
        }

        void expectBounded() {
          final viewport = tester.getRect(find.byType(CustomScrollView));
          final grid = tester.getRect(find.byType(ScheduleHolidayPanel));
          final bounds = panelBounds();
          expect(
            bounds.top,
            closeTo(grid.top.clamp(viewport.top + 56, viewport.bottom), 0.01),
          );
          expect(
            bounds.bottom,
            closeTo(
              grid.bottom.clamp(viewport.top + 56, viewport.bottom),
              0.01,
            ),
          );
          expect(bounds.left, viewport.left + 48);
          expect(bounds.width, 100);
          final panel = tester.renderObject<RenderScheduleHolidayPanel>(
            find.byType(ScheduleHolidayPanel),
          );
          final firstRow = (panel.visiblePanelBounds.top / 72).ceil() * 72.0;
          expect(
            panel,
            paints..line(
              color: Colors.amber.withValues(alpha: 0.24),
              strokeWidth: 1,
              p1: Offset(0, firstRow),
              p2: Offset(100, firstRow),
            ),
          );
        }

        await tester.pumpWidget(page(precedingHeight: 120));
        await tester.pumpAndSettle();
        expectBounded();
        final initial = tester.getCenter(find.byKey(labelKey)).dy;
        scroll.jumpTo(80);
        await tester.pump();
        expectBounded();
        expect(
          tester.getCenter(find.byKey(labelKey)).dy,
          closeTo(initial - 80, .1),
        );
        scroll.jumpTo(160);
        await tester.pump();
        expectBounded();
        expect(
          tester.getCenter(find.byKey(labelKey)).dy,
          closeTo(initial - 160, .1),
        );
        await tester.tap(find.text('DDL'));
        expect(taps, 1);

        // Moving the scroll content down must move its label by the same amount.
        final before = tester.getCenter(find.byKey(labelKey)).dy;
        scroll.jumpTo(120);
        await tester.pump();
        expect(
          tester.getCenter(find.byKey(labelKey)).dy,
          closeTo(before + 40, .1),
        );
        await tester.pumpWidget(page(precedingHeight: 260, reduceMotion: true));
        await tester.pumpAndSettle();
        expectBounded();
        final shifted = tester.getCenter(find.byKey(labelKey)).dy;
        scroll.jumpTo(160);
        await tester.pump();
        expect(
          tester.getCenter(find.byKey(labelKey)).dy,
          closeTo(shifted - 40, .1),
        );
        tester.view.physicalSize = const Size(1180, 820);
        await tester.pumpAndSettle();
        expectBounded();
        final viewport = tester.getRect(find.byType(CustomScrollView));

        // At the end of the grid the label is clamped, never painted over other sections.
        scroll.jumpTo(1450);
        await tester.pump();
        expectBounded();
        expect(
          tester.getRect(find.byKey(labelKey)).top,
          greaterThanOrEqualTo(viewport.top + 56),
        );
        final replacement = _HolidayScrollController();
        addTearDown(replacement.dispose);
        await tester.pumpWidget(
          page(precedingHeight: 260, controller: replacement),
        );
        await tester.pumpAndSettle();
        expect(scroll.hasActiveListeners, isFalse);
        expectBounded();
        replacement.jumpTo(1700);
        await tester.pump();
        expect(find.byType(ScheduleHolidayPanel), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        // Detached render objects must no longer listen to the controller.
        expect(scroll.hasActiveListeners, isFalse);
        expect(replacement.hasActiveListeners, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _HolidayScrollController extends ScrollController {
  bool get hasActiveListeners => hasListeners;
}
