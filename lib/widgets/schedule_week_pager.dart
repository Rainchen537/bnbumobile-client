import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Three adjacent, locally rendered weeks. Only transforms tick during a drag;
/// the expensive timetable trees and their text layout remain cached.
///
/// The current child supplies the height in a vertically scrolling sliver.
/// Neighbours are clipped previews, with no taps, semantics or focus until the
/// spring settles. This avoids a second vertical viewport/gesture competition.
class ScheduleWeekPager extends StatefulWidget {
  const ScheduleWeekPager({
    super.key,
    required this.week,
    required this.builder,
    required this.onChanged,
    required this.swipeEnabled,
    this.horizontalController,
  });

  final DateTime week;
  final Widget Function(DateTime week, bool active) builder;
  final ValueChanged<DateTime> onChanged;
  final bool swipeEnabled;
  final ScrollController? horizontalController;

  @override
  State<ScheduleWeekPager> createState() => _ScheduleWeekPagerState();
}

class _ScheduleWeekPagerState extends State<ScheduleWeekPager>
    with SingleTickerProviderStateMixin {
  late DateTime _week = widget.week;
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  DateTime? _destination;
  double _width = 1;
  int _generation = 0;
  bool _dragging = false;
  bool? _scrollDates;
  Drag? _dateDrag;
  ScrollHoldController? _dateHold;
  DragStartDetails? _start;
  double _dragDistance = 0;

  // Deliberate paging: distance is proportional to the visible board, not a
  // small fixed cap that makes a light tablet swipe turn an entire week.
  static const _commitFraction = .40;
  static const _flingVelocity = 1100.0;
  static final _swipeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 200,
    ratio: 1,
  );

  DateTime _adjacent(int delta) =>
      DateTime(_week.year, _week.month, _week.day + delta * 7);

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(covariant ScheduleWeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.week == oldWidget.week) return;
    if (widget.week == _week) {
      // A second arrow tap can return to the starting week before the first
      // transition settles. Catch that spring instead of committing stale UI.
      if (_destination != null) {
        _destination = _week;
        _settle(0, 0, notify: false);
      }
      return;
    }
    final next = widget.week;
    final adjacent = next == _adjacent(-1) || next == _adjacent(1);
    if (!adjacent || _reduceMotion || _dragging) {
      _reset(next);
      return;
    }
    _destination = next;
    _settle(next.isAfter(_week) ? -1 : 1, 0, notify: false);
  }

  void _reset(DateTime week) {
    _generation++;
    _dateDrag?.cancel();
    _dateDrag = null;
    _dateHold?.cancel();
    _dateHold = null;
    _offset.stop();
    _offset.value = 0;
    _week = week;
    _destination = null;
    _dragging = false;
    _scrollDates = null;
    _dragDistance = 0;
  }

  @override
  void dispose() {
    _generation++;
    _dateDrag?.cancel();
    _dateHold?.cancel();
    _offset.dispose();
    super.dispose();
  }

  void _begin(DragStartDetails details) {
    _generation++;
    _offset.stop(); // Keep the exact visual position when catching a spring.
    _dragging = true;
    _scrollDates = null;
    _start = details;
    _dragDistance = 0;
    final controller = widget.horizontalController;
    if (controller != null && controller.hasClients) {
      _dateHold = controller.position.hold(() => _dateHold = null);
    }
  }

  void _update(DragUpdateDetails details) {
    final dx = details.primaryDelta ?? 0;
    if (_scrollDates == null && dx != 0) {
      final controller = widget.horizontalController;
      final position = controller?.hasClients == true
          ? controller!.position
          : null;
      _scrollDates =
          _offset.value == 0 &&
          position != null &&
          (dx < 0 ? position.extentAfter > .5 : position.extentBefore > .5);
      if (_scrollDates!) {
        _dateDrag = position!.drag(_start!, () => _dateDrag = null);
      }
      _dateHold?.cancel();
      _dateHold = null;
    }
    if (_scrollDates == true) {
      // A gesture that starts inside a wide grid belongs to its date columns
      // for its entire lifetime. A fresh outward edge gesture changes week.
      _dateDrag?.update(details);
      return;
    }
    _dragDistance += dx;
    _offset.value = (_offset.value + dx / _width).clamp(-1.0, 1.0);
  }

  void _end(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    if (_scrollDates == true) {
      _dateDrag?.end(details);
      _dateDrag = null;
      _scrollDates = null;
      return;
    }
    _dateHold?.cancel();
    _dateHold = null;
    final velocity = details.primaryVelocity ?? 0;
    final distance = _offset.value * _width;
    final fling =
        velocity.abs() >= _flingVelocity &&
        _dragDistance.abs() >= (_width * .12).clamp(48.0, 96.0);
    final sameDirection = velocity.sign == distance.sign;
    final commit = fling
        ? sameDirection && velocity.sign == _dragDistance.sign
        : distance.abs() >= _width * _commitFraction;
    final target = commit ? _offset.value.sign : 0.0;
    _destination = target == 0 ? _week : _adjacent(target < 0 ? 1 : -1);
    _settle(target, velocity / _width);
  }

  void _cancel() {
    if (!_dragging) return;
    _dragging = false;
    _dateDrag?.cancel();
    _dateDrag = null;
    _dateHold?.cancel();
    _dateHold = null;
    _destination = _week;
    _settle(0, 0);
  }

  Future<void> _settle(
    double target,
    double velocity, {
    bool notify = true,
  }) async {
    final generation = ++_generation;
    final destination = _destination ?? _week;
    try {
      if (!_reduceMotion) {
        // Explicit arrow navigation keeps its existing timing, including on
        // desktop. Only touch-release/cancel uses the gentler swipe response.
        final spring = notify
            ? _swipeSpring
            : const SpringDescription(mass: 1, stiffness: 380, damping: 39);
        // A critical spring can still overshoot with a large release velocity.
        // Bound it by the remaining distance so a near-complete flick never
        // reveals an empty strip beyond the single adjacent preview.
        final maxVelocity = math.min(
          3.5,
          (target - _offset.value).abs() *
              math.sqrt(spring.stiffness / spring.mass),
        );
        await _offset
            .animateWith(
              SpringSimulation(
                spring,
                _offset.value,
                target,
                velocity.clamp(-maxVelocity, maxVelocity),
                tolerance: const Tolerance(distance: .001, velocity: .01),
              ),
            )
            .orCancel;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _week = destination;
        _destination = null;
        _offset.value = 0;
      });
      if (notify && widget.week != destination) widget.onChanged(destination);
    } on TickerCanceled {
      // New gesture, explicit navigation, resize or disposal owns the position.
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = math.max(1, constraints.maxWidth);
      Widget page(int relative) {
        final content = RepaintBoundary(
          child: widget.builder(_adjacent(relative), relative == 0),
        );
        return AnimatedBuilder(
          animation: _offset,
          child: content,
          builder: (context, child) {
            final moving = _offset.value != 0;
            return Offstage(
              offstage: relative != 0 && !moving,
              child: ExcludeFocus(
                excluding: relative != 0 || moving,
                child: ExcludeSemantics(
                  excluding: relative != 0 || moving,
                  child: IgnorePointer(
                    ignoring: relative != 0 || moving,
                    child: Transform.translate(
                      key: relative == 0
                          ? const ValueKey('schedule-week-translation')
                          : null,
                      offset: Offset((relative + _offset.value) * _width, 0),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }

      final pages = ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            page(0),
            for (final relative in [-1, 1])
              Positioned(top: 0, left: 0, right: 0, child: page(relative)),
          ],
        ),
      );
      if (!widget.swipeEnabled) return pages;
      return RawGestureDetector(
        key: const ValueKey('schedule-mobile-week-swipe-surface'),
        behavior: HitTestBehavior.translucent,
        gestures: {
          _WeekDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_WeekDragRecognizer>(
                _WeekDragRecognizer.new,
                (recognizer) => recognizer
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = _begin
                  ..onUpdate = _update
                  ..onEnd = _end
                  ..onCancel = _cancel
                  ..onPointerCanceled = _cancel,
              ),
        },
        child: pages,
      );
    },
  );
}

/// Flutter reports an accepted drag's pointer cancellation through onEnd;
/// distinguish it from a deliberate release before that callback is dispatched.
class _WeekDragRecognizer extends HorizontalDragGestureRecognizer {
  VoidCallback? onPointerCanceled;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerCancelEvent) onPointerCanceled?.call();
    super.handleEvent(event);
  }
}
