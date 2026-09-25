/// A shared piecewise time axis for courses, deadlines and the current time.
class ScheduleGridGeometry {
  ScheduleGridGeometry({
    required this.startMinutes,
    required this.endMinutes,
    required double availableHeight,
    required Iterable<({int startMinutes, int endMinutes})> occupiedRanges,
    double emptyHourWeight = .5,
  }) : assert(endMinutes > startMinutes),
       assert(startMinutes % 60 == 0 && endMinutes % 60 == 0),
       assert(availableHeight > 0),
       assert(emptyHourWeight > 0 && emptyHourWeight <= 1) {
    final count = ((endMinutes - startMinutes) / 60).ceil();
    final ranges = occupiedRanges.toList(growable: false);
    final weights = <double>[];
    for (var index = 0; index < count; index++) {
      final start = startMinutes + index * 60;
      final occupied = ranges.any(
        (range) =>
            range.endMinutes > range.startMinutes &&
            range.startMinutes < start + 60 &&
            range.endMinutes > start,
      );
      // Occupancy changes relative height, never the total grid height.
      // DDLs remain markers rather than occupied time ranges.
      weights.add(occupied ? 1 : emptyHourWeight);
    }
    normalRowHeight = availableHeight / weights.reduce((a, b) => a + b);
    final boundaries = <double>[0];
    for (final weight in weights) {
      boundaries.add(boundaries.last + normalRowHeight * weight);
    }
    // Avoid accumulated rounding leaving even a fractional bottom gap.
    boundaries[boundaries.length - 1] = availableHeight;
    offsets = List.unmodifiable(boundaries);
  }

  final int startMinutes;
  final int endMinutes;
  late final List<double> offsets;
  late final double normalRowHeight;
  double get height => offsets.last;
  double rowHeight(int index) => offsets[index + 1] - offsets[index];

  double offsetFor(double minutes) {
    final value = minutes.clamp(startMinutes, endMinutes) - startMinutes;
    final index = (value / 60).floor();
    if (index >= offsets.length - 1) return height;
    return offsets[index] + rowHeight(index) * (value % 60) / 60;
  }
}

/// Horizontal display groups; every original date retains a distinct lane for
/// real TA/DDL items even when the surrounding holiday surface is compressed.
class ScheduleDayColumn {
  ScheduleDayColumn(this.dates, this.holidayLabels);

  final List<DateTime> dates;
  final List<String> holidayLabels;
  double get weight => dates.length > 1 ? 1.5 : 1;
  bool get isHoliday => holidayLabels.isNotEmpty;
}

List<ScheduleDayColumn> buildScheduleDayColumns(
  List<DateTime> dates,
  Map<int, String> holidays,
) {
  final groups = <ScheduleDayColumn>[];
  for (final date in dates) {
    final label = holidays[date.weekday];
    final previous = groups.isEmpty ? null : groups.last;
    final consecutive =
        previous != null &&
        DateTime(
              previous.dates.last.year,
              previous.dates.last.month,
              previous.dates.last.day + 1,
            ) ==
            date;
    if (label != null &&
        previous != null &&
        previous.isHoliday &&
        consecutive) {
      previous.dates.add(date);
      if (!previous.holidayLabels.contains(label)) {
        previous.holidayLabels.add(label);
      }
    } else {
      groups.add(ScheduleDayColumn([date], [if (label != null) label]));
    }
  }
  return groups;
}
