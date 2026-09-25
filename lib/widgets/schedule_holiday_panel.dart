import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps the holiday surface inside the visible timetable, without changing
/// the full-day layout used by the time axis, courses and deadlines.
class ScheduleHolidayPanel extends StatelessWidget {
  const ScheduleHolidayPanel({
    super.key,
    required this.scrollController,
    required this.viewportKey,
    required this.pinnedHeaderExtent,
    this.rowHeight = 72,
    this.rowOffsets = const [],
    this.reduceMotion = false,
    required this.backgroundColor,
    required this.borderColor,
    required this.child,
  });

  final ScrollController scrollController;
  final GlobalKey viewportKey;
  final double pinnedHeaderExtent;
  final double rowHeight;
  final List<double> rowOffsets;
  final bool reduceMotion;
  final Color backgroundColor;
  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => _HolidaySurface(configuration: this);
}

class _HolidaySurface extends SingleChildRenderObjectWidget {
  _HolidaySurface({required this.configuration})
    : super(child: configuration.child);

  final ScheduleHolidayPanel configuration;

  @override
  RenderScheduleHolidayPanel createRenderObject(BuildContext context) {
    return RenderScheduleHolidayPanel(
      scrollController: configuration.scrollController,
      viewportKey: configuration.viewportKey,
      pinnedHeaderExtent: configuration.pinnedHeaderExtent,
      rowHeight: configuration.rowHeight,
      rowOffsets: configuration.rowOffsets,
      backgroundColor: configuration.backgroundColor,
      borderColor: configuration.borderColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderScheduleHolidayPanel renderObject,
  ) {
    renderObject.update(
      scrollController: configuration.scrollController,
      viewportKey: configuration.viewportKey,
      pinnedHeaderExtent: configuration.pinnedHeaderExtent,
      rowHeight: configuration.rowHeight,
      rowOffsets: configuration.rowOffsets,
      backgroundColor: configuration.backgroundColor,
      borderColor: configuration.borderColor,
    );
  }
}

class RenderScheduleHolidayPanel extends RenderShiftedBox {
  RenderScheduleHolidayPanel({
    required ScrollController scrollController,
    required GlobalKey viewportKey,
    required double pinnedHeaderExtent,
    required double rowHeight,
    List<double> rowOffsets = const [],
    required Color backgroundColor,
    required Color borderColor,
  }) : _scrollController = scrollController,
       _viewportKey = viewportKey,
       _pinnedHeaderExtent = pinnedHeaderExtent,
       _rowHeight = rowHeight,
       _rowOffsets = rowOffsets,
       _backgroundColor = backgroundColor,
       _borderColor = borderColor,
       super(null);

  ScrollController _scrollController;
  GlobalKey _viewportKey;
  double _pinnedHeaderExtent;
  double _rowHeight;
  List<double> _rowOffsets;
  Color _backgroundColor;
  Color _borderColor;

  /// Actual painted bounds in local coordinates, not the full-day layout size.
  @visibleForTesting
  Rect get visiblePanelBounds => _visiblePanelBounds;
  Rect _visiblePanelBounds = Rect.zero;

  void update({
    required ScrollController scrollController,
    required GlobalKey viewportKey,
    required double pinnedHeaderExtent,
    required double rowHeight,
    List<double> rowOffsets = const [],
    required Color backgroundColor,
    required Color borderColor,
  }) {
    if (_scrollController != scrollController) {
      if (attached) _scrollController.removeListener(_scrollChanged);
      _scrollController = scrollController;
      if (attached) _scrollController.addListener(_scrollChanged);
    }
    _viewportKey = viewportKey;
    _pinnedHeaderExtent = pinnedHeaderExtent;
    _rowHeight = rowHeight;
    _rowOffsets = rowOffsets;
    _backgroundColor = backgroundColor;
    _borderColor = borderColor;
    _scrollChanged();
  }

  void _scrollChanged() {
    // Repaint in the scrolling frame: no post-frame setState or a one-frame lag.
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrollController.addListener(_scrollChanged);
  }

  @override
  void detach() {
    _scrollController.removeListener(_scrollChanged);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(BoxConstraints(maxWidth: size.width), parentUsesSize: true);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    _visiblePanelBounds = Rect.zero;
    if (viewport is! RenderBox || !viewport.hasSize) return;

    final origin = viewport.globalToLocal(localToGlobal(Offset.zero));
    // The yellow surface must meet the viewport edges throughout scrolling.
    // Moving its frame creates false non-holiday gaps above/below the panel.
    final top = math.max(0.0, _pinnedHeaderExtent - origin.dy);
    final bottom = math.min(size.height, viewport.size.height - origin.dy);
    if (bottom <= top || size.width <= 0) return;
    final bounds = Rect.fromLTRB(0, top, size.width, bottom);
    _visiblePanelBounds = bounds;
    final canvasBounds = bounds.shift(offset);
    context.canvas.drawRect(canvasBounds, Paint()..color = _backgroundColor);
    // Faint time-row seams follow the real grid. The frame always stays flush
    // with the viewport; only the label gets a momentary directional cue.
    if (_rowHeight > 0) {
      final linePaint = Paint()
        ..color = _borderColor.withValues(alpha: 0.24)
        ..strokeWidth = 1;
      final seams = _rowOffsets.isNotEmpty
          ? _rowOffsets
          : [
              for (
                var y = (top / _rowHeight).ceil() * _rowHeight;
                y < bottom;
                y += _rowHeight
              )
                y,
            ];
      for (final y in seams.where((y) => y >= top && y < bottom)) {
        context.canvas.drawLine(
          offset + Offset(0, y),
          offset + Offset(size.width, y),
          linePaint,
        );
      }
    }
    if (bounds.shortestSide >= 1) {
      context.canvas.drawRect(
        canvasBounds.deflate(0.5),
        Paint()
          ..color = _borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final label = child;
    if (label == null) return;
    // Anchor inside the actual grid. Scrolling (including a pull beyond the
    // top) moves the label with its panel; only the visible grid ends constrain it.
    final center =
        math.min(size.height, viewport.size.height - _pinnedHeaderExtent) / 2;
    final labelTop = (center - label.size.height / 2).clamp(
      top,
      math.max(top, bottom - label.size.height),
    );
    (label.parentData! as BoxParentData).offset = Offset(
      (size.width - label.size.width) / 2,
      labelTop.toDouble(),
    );
    context.pushClipRect(needsCompositing, offset, bounds, super.paint);
  }

  // The surface is decorative. Courses and deadlines painted above it keep
  // their own hit targets; all scrolling remains owned by the timetable.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}
