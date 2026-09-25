import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/schedule_grid_geometry.dart';
import 'package:bnbu_me/widgets/schedule_scroll_physics.dart';

void main() {
  test('consecutive holidays use one 1.5 unit column and retain each date', () {
    final dates = List.generate(7, (i) => DateTime(2026, 9, 21 + i));
    final groups = buildScheduleDayColumns(dates, {
      5: '中秋假期',
      6: '中秋假期',
      7: '中秋假期',
    });
    expect(groups.length, 5);
    expect(groups.take(4).map((g) => g.weight), everyElement(1));
    expect(groups.last.weight, 1.5);
    expect(groups.last.dates, dates.sublist(4));
    expect(groups.expand((g) => g.dates), dates);
    expect(groups.last.holidayLabels, ['中秋假期']);
  });
  test('isolated holidays and nonconsecutive dates do not merge', () {
    final dates = [DateTime(2026, 10, 1), DateTime(2026, 10, 3)];
    final groups = buildScheduleDayColumns(dates, {4: '假期', 6: '假期'});
    expect(groups.length, 2);
    expect(groups.map((g) => g.weight), everyElement(1));
  });
  test(
    'top pull has stronger resistance while normal scrolling is unchanged',
    () {
      const physics = ScheduleScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
      const original = BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
      FixedScrollMetrics metrics(double pixels) => FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 600,
        pixels: pixels,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      );
      expect(
        physics.applyPhysicsToUserOffset(metrics(0), 30),
        lessThan(original.applyPhysicsToUserOffset(metrics(0), 30) / 2),
      );
      expect(
        physics.applyPhysicsToUserOffset(metrics(200), 30),
        original.applyPhysicsToUserOffset(metrics(200), 30),
      );
      expect(
        physics.applyPhysicsToUserOffset(metrics(0), -30),
        original.applyPhysicsToUserOffset(metrics(0), -30),
      );
    },
  );
}
