import 'package:bnbu_me/widgets/schedule_week_pager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final initial = DateTime(2026, 12, 28);
  late DateTime week;
  late StateSetter rebuild;
  late int builds;
  late int changes;
  Future<void> mount(
    WidgetTester tester, {
    bool reduced = false,
    ScrollController? dates,
    bool enabled = true,
    double width = 390,
  }) async {
    week = initial;
    builds = 0;
    changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: ScheduleWeekPager(
                    week: week,
                    swipeEnabled: enabled,
                    horizontalController: dates,
                    onChanged: (value) => setState(() {
                      week = value;
                      changes++;
                    }),
                    builder: (value, active) {
                      builds++;
                      final body = SizedBox(
                        width: dates == null ? width : 800,
                        height: 500,
                        child: Center(
                          child: Text('${value.month}/${value.day}'),
                        ),
                      );
                      return dates == null
                          ? body
                          : SingleChildScrollView(
                              controller: active ? dates : null,
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: body,
                            );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double translation(WidgetTester tester) => tester
      .widget<Transform>(
        find.byKey(const ValueKey('schedule-week-translation')),
      )
      .transform
      .storage[12];

  testWidgets(
    'drag is one-to-one, previews join, no per-frame content builds',
    (tester) async {
      await mount(tester);
      final baseline = builds;
      final gesture = await tester.startGesture(const Offset(300, 200));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(translation(tester), closeTo(-40, .01));
      final next = tester.getRect(find.text('1/4'));
      final current = tester.getRect(find.text('12/28'));
      expect(next.center.dx - current.center.dx, closeTo(390, .01));
      for (var i = 0; i < 14; i++) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(builds, baseline);
      expect(week, initial);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(week, DateTime(2027, 1, 4));
      expect(changes, 1);
      expect(find.text('12/28'), findsNothing);
      expect(translation(tester), 0);
    },
  );

  testWidgets(
    'short drag, vertical drag, reversal and pointer cancel do not turn',
    (tester) async {
      await mount(tester);
      await tester.dragFrom(const Offset(250, 200), const Offset(-25, 0));
      await tester.pumpAndSettle();
      expect(week, initial);
      await tester.dragFrom(const Offset(250, 200), const Offset(-20, -170));
      await tester.pumpAndSettle();
      expect(week, initial);
      final gesture = await tester.startGesture(const Offset(290, 200));
      await gesture.moveBy(const Offset(-140, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(125, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(week, initial);
      final canceled = await tester.startGesture(const Offset(290, 200));
      await canceled.moveBy(const Offset(-180, 0));
      await tester.pump();
      await canceled.cancel();
      await tester.pumpAndSettle();
      expect(week, initial);
      expect(changes, 0);
      expect(translation(tester), 0);
    },
  );

  testWidgets(
    'fast flick advances, spring can be caught and reversed without jumping',
    (tester) async {
      await mount(tester);
      await tester.flingFrom(
        const Offset(290, 200),
        const Offset(-65, 0),
        1400,
      );
      await tester.pumpAndSettle();
      expect(week, DateTime(2027, 1, 4));
      await tester.dragFrom(const Offset(290, 200), const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 32));
      final before = translation(tester);
      final catchGesture = await tester.startGesture(const Offset(90, 200));
      await catchGesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(translation(tester), closeTo(before + 30, .1));
      await catchGesture.moveBy(Offset(-translation(tester), 0));
      await tester.pump(const Duration(milliseconds: 180));
      await catchGesture.up();
      await tester.pumpAndSettle();
      expect(week, DateTime(2027, 1, 4));
      expect(translation(tester), 0);
    },
  );

  testWidgets(
    'wide date grid keeps its gesture and only fresh outward edge drag turns',
    (tester) async {
      final dates = ScrollController();
      addTearDown(dates.dispose);
      await mount(tester, dates: dates);
      await tester.dragFrom(const Offset(280, 200), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(dates.offset, greaterThan(150));
      expect(week, initial);
      dates.jumpTo(dates.position.maxScrollExtent);
      await tester.dragFrom(const Offset(280, 200), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(week, DateTime(2027, 1, 4));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'buttons and far jumps keep latest date without duplicate callbacks',
    (tester) async {
      await mount(tester);
      rebuild(() => week = DateTime(2027, 1, 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      rebuild(() => week = DateTime(2027, 1, 11));
      await tester.pumpAndSettle();
      expect(find.text('1/11'), findsOneWidget);
      expect(changes, 0);
      rebuild(() => week = DateTime(2028, 1, 3));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);
      expect(translation(tester), 0);
    },
  );

  testWidgets('reduced motion tracks the finger but has no release animation', (
    tester,
  ) async {
    await mount(tester, reduced: true);
    final gesture = await tester.startGesture(const Offset(280, 200));
    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump();
    expect(week, initial);
    expect(translation(tester), closeTo(-180, .01));
    await gesture.up();
    await tester.pump();
    expect(week, DateTime(2027, 1, 4));
    expect(translation(tester), 0);
    // Re-enabling focus schedules one layout frame, not an animation ticker.
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('light drag springs back; deliberate drag turns at $width', (
      tester,
    ) async {
      await mount(tester, width: width);
      final start = Offset(width * .8, 200);
      await tester.dragFrom(start, Offset(-width * .32, 0));
      await tester.pumpAndSettle();
      expect(week, initial);
      expect(changes, 0);
      expect(translation(tester), 0);
      await tester.dragFrom(start, Offset(-width * .45, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(week, initial);
      await tester.pumpAndSettle();
      expect(week, DateTime(2027, 1, 4));
      expect(changes, 1);
    });
  }

  testWidgets('moderate flick and tiny fast motion do not turn', (
    tester,
  ) async {
    await mount(tester);
    await tester.flingFrom(const Offset(290, 200), const Offset(-65, 0), 900);
    await tester.pumpAndSettle();
    expect(week, initial);
    await tester.flingFrom(const Offset(290, 200), const Offset(-35, 0), 2400);
    await tester.pumpAndSettle();
    expect(week, initial);
    expect(changes, 0);
  });

  testWidgets(
    'fast near-edge release never overshoots or flashes a blank edge',
    (tester) async {
      await mount(tester);
      await tester.flingFrom(
        const Offset(380, 200),
        const Offset(-350, 0),
        6000,
      );
      for (var frame = 0; frame < 80; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(translation(tester), inInclusiveRange(-390.0, 0.0));
        if (changes != 0) break;
      }
      await tester.pumpAndSettle();
      expect(week, DateTime(2027, 1, 4));
      expect(changes, 1);
    },
  );

  testWidgets('deliberate release eases to rest instead of snapping early', (
    tester,
  ) async {
    await mount(tester);
    await tester.dragFrom(const Offset(300, 200), const Offset(-180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(week, initial);
    expect(translation(tester), inExclusiveRange(-300.0, -180.0));
    await tester.pumpAndSettle();
    expect(week, DateTime(2027, 1, 4));
    expect(changes, 1);
  });

  testWidgets('one long gesture turns at most one week', (tester) async {
    await mount(tester);
    final gesture = await tester.startGesture(const Offset(300, 200));
    await gesture.moveBy(const Offset(-900, 0));
    await tester.pump();
    expect(translation(tester), -390);
    expect(week, initial);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(week, DateTime(2027, 1, 4));
    expect(changes, 1);
  });

  testWidgets('a quick reversal cancels even past the distance threshold', (
    tester,
  ) async {
    await mount(tester);
    final gesture = await tester.startGesture(const Offset(370, 200));
    await gesture.moveBy(
      const Offset(-300, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump();
    for (var step = 0; step < 5; step++) {
      await gesture.moveBy(
        const Offset(20, 0),
        timeStamp: Duration(milliseconds: 210 + step * 10),
      );
      await tester.pump();
    }
    expect(translation(tester), closeTo(-200, .01));
    await gesture.up(timeStamp: const Duration(milliseconds: 255));
    await tester.pumpAndSettle();
    expect(week, initial);
    expect(changes, 0);
    expect(translation(tester), 0);
  });

  testWidgets(
    'opposite arrow during a transition cancels the stale destination',
    (tester) async {
      await mount(tester);
      rebuild(() => week = DateTime(2027, 1, 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(translation(tester), lessThan(0));
      rebuild(() => week = initial);
      await tester.pumpAndSettle();
      expect(find.text('12/28'), findsOneWidget);
      expect(translation(tester), 0);
      expect(changes, 0);
    },
  );

  testWidgets(
    'desktop has no new swipe gesture; disposing an animation is safe',
    (tester) async {
      await mount(tester, enabled: false);
      await tester.dragFrom(const Offset(280, 200), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(changes, 0);
      rebuild(() => week = DateTime(2027, 1, 4));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
