import 'package:flutter/widgets.dart';

/// A deliberate pull at the top; normal in-range timetable scrolling is intact.
class ScheduleScrollPhysics extends BouncingScrollPhysics {
  const ScheduleScrollPhysics({super.parent});

  @override
  ScheduleScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      ScheduleScrollPhysics(parent: buildParent(ancestor));

  @override
  double get dragStartDistanceMotionThreshold => 24;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final adjusted = super.applyPhysicsToUserOffset(position, offset);
    return position.pixels <= position.minScrollExtent && offset > 0
        ? adjusted * 0.3
        : adjusted;
  }
}
