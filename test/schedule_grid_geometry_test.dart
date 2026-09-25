import 'package:bnbu_me/models/schedule_grid_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'all occupancy combinations preserve total height and relative weights',
    () {
      for (final available in [311.5, 772.0, 1228.0]) {
        for (var mask = 0; mask < 16; mask++) {
          final grid = ScheduleGridGeometry(
            startMinutes: 480,
            endMinutes: 720,
            availableHeight: available,
            occupiedRanges: [
              for (var i = 0; i < 4; i++)
                if ((mask & (1 << i)) != 0)
                  (startMinutes: 480 + i * 60, endMinutes: 540 + i * 60),
            ],
          );
          expect(grid.offsets.first, 0);
          expect(grid.height, available);
          for (var i = 0; i < 4; i++) {
            expect(grid.rowHeight(i), greaterThan(0));
            expect(
              grid.offsetFor(510 + i * 60),
              closeTo(grid.offsets[i] + grid.rowHeight(i) / 2, .000001),
            );
            for (var j = 0; j < 4; j++) {
              if ((mask & (1 << i)) == 0 && (mask & (1 << j)) != 0) {
                expect(
                  grid.rowHeight(i) / grid.rowHeight(j),
                  closeTo(.5, .000001),
                );
              }
            }
          }
        }
      }
    },
  );

  for (final endHour in [22, 23, 24]) {
    test(
      'all idle hours fill the available height with no terminal row at $endHour',
      () {
        final grid = ScheduleGridGeometry(
          startMinutes: 480,
          endMinutes: endHour * 60,
          availableHeight: (endHour - 8) * 60,
          occupiedRanges: const [],
        );
        expect(grid.offsets.length, endHour - 8 + 1);
        expect(grid.normalRowHeight, closeTo(60 / .5, .000001));
        expect(grid.height, closeTo((endHour - 8) * 60, .000001));
        for (var hour = 8; hour < endHour; hour++) {
          expect(grid.rowHeight(hour - 8), closeTo(60, .000001));
          expect(
            grid.offsetFor(hour * 60 + 30),
            closeTo((hour - 8) * 60 + 30, .000001),
          );
        }
        expect(grid.offsetFor(-1), 0);
        expect(grid.offsetFor(endHour * 60), grid.height);
        expect(grid.offsetFor(1500), grid.height);
      },
    );
  }

  test(
    'overlap covers every intersected hour, never counts adjacent boundaries twice',
    () {
      final grid = ScheduleGridGeometry(
        startMinutes: 480,
        endMinutes: 1440,
        availableHeight: 960,
        occupiedRanges: const [
          (startMinutes: 570, endMinutes: 690), // 9:30–11:30
          (startMinutes: 690, endMinutes: 720), // same occupied hour
          (startMinutes: 810, endMinutes: 840), // end exactly at 14:00
          (startMinutes: 1135, endMinutes: 1140), // 18:55 still occupies 18–19
          (startMinutes: 1439, endMinutes: 1440), // last minute of the day
          (startMinutes: 780, endMinutes: 780), // empty range is not occupancy
        ],
      );
      for (var hour = 8; hour < 24; hour++) {
        final occupied = {9, 10, 11, 13, 18, 23}.contains(hour);
        expect(
          grid.rowHeight(hour - 8),
          closeTo(960 / (6 + 10 * .5) * (occupied ? 1 : .5), .000001),
          reason: '$hour:00',
        );
      }
      expect(
        grid.offsetFor(570),
        closeTo(grid.offsets[1] + grid.rowHeight(1) / 2, .000001),
      );
      expect(
        grid.offsetFor(750),
        closeTo(grid.offsets[4] + grid.rowHeight(4) / 2, .000001),
      );
      expect(
        grid.offsetFor(1439),
        closeTo(grid.height - grid.rowHeight(15) / 60, .000001),
      );
      expect(grid.height, 960);
    },
  );

  test('fully occupied axis retains normal height and offsets', () {
    final grid = ScheduleGridGeometry(
      startMinutes: 420,
      endMinutes: 1440,
      availableHeight: 850,
      occupiedRanges: const [(startMinutes: 420, endMinutes: 1440)],
    );
    expect(grid.height, 850);
    expect(grid.normalRowHeight, 50);
    expect(grid.offsetFor(480), 50);
  });
}
