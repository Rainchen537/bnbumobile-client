import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_time.dart';

void main() {
  test('converts an instant to the fixed UTC+8 campus clock', () {
    final campusClock = toBnbuCampusClock(DateTime.utc(2026, 7, 19, 17, 30));

    expect(campusClock, DateTime(2026, 7, 20, 1, 30));
  });

  test('converts campus wall-clock fields back to the UTC instant', () {
    final instant = bnbuCampusClockToUtc(DateTime(2026, 7, 20, 9));

    expect(instant, DateTime.utc(2026, 7, 20, 1));
  });
}
