import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/me_life_presentation.dart';

/// Geometry is measured from the 1206px reference at a 402px logical viewport.
class LifeBadge extends StatelessWidget {
  const LifeBadge({
    super.key,
    required this.text,
    required this.style,
    this.scale = 1,
    this.expand = false,
    this.truncate = true,
  });
  final String text;
  final LifeStyle style;
  final double scale;
  final bool expand, truncate;
  @override
  Widget build(BuildContext context) {
    final brand = style.template == 'brand';
    final flame = style.template == 'flame';
    final leading = style.template == 'rank';
    final font = (brand ? 12 : 12) * scale;
    final label = Text(
      text,
      maxLines: truncate ? 1 : null,
      overflow: truncate ? TextOverflow.ellipsis : TextOverflow.visible,
      style: TextStyle(
        fontSize: font,
        height: 1.18,
        color: style.foreground,
        fontWeight: brand ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (leading) ...[
          Container(
            width: (style.template == 'rank' ? 25.3 : 17.3) * scale,
            height: 17.3 * scale,
            decoration: BoxDecoration(
              color: style.accent,
              borderRadius: BorderRadius.circular(2 * scale),
            ),
            child: CustomPaint(
              painter: _BadgeMark(
                style.template,
                style.foreground,
                DefaultTextStyle.of(context).style.fontFamily,
              ),
            ),
          ),
          SizedBox(width: 4 * scale),
        ],
        Flexible(fit: expand ? FlexFit.tight : FlexFit.loose, child: label),
        if (style.template == 'rank') ...[
          SizedBox(width: 6 * scale),
          Icon(Icons.chevron_right, color: style.foreground, size: 15 * scale),
        ],
      ],
    );
    return CustomPaint(
      key: ValueKey('life-style-${style.template}'),
      painter: brand ? _BrandTail(style.accent) : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal:
              (flame
                  ? 5
                  : leading
                  ? 0
                  : brand
                  ? 4.3
                  : 5) *
              scale,
          vertical:
              (flame
                  ? 2
                  : brand
                  ? 1.5
                  : leading
                  ? 0
                  : .8) *
              scale,
        ),
        decoration: BoxDecoration(
          color: flame
              ? Color.alphaBlend(
                  style.accent.withValues(alpha: .12),
                  style.background,
                )
              : style.background,
          border: flame
              ? Border.all(
                  color: style.foreground.withValues(alpha: .16),
                  width: .55 * scale,
                )
              : leading || brand
              ? null
              : Border.all(color: style.border, width: .55 * scale),
          borderRadius: BorderRadius.circular(
            (flame
                    ? 4
                    : brand
                    ? 4
                    : leading
                    ? 2.3
                    : 1.7) *
                scale,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(right: leading && !flame ? 5 * scale : 0),
          child: row,
        ),
      ),
    );
  }
}

class _BrandTail extends CustomPainter {
  const _BrandTail(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - 3)
        ..lineTo(2.3, size.height + 2.3)
        ..lineTo(2.3, size.height - 3)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BrandTail old) => old.color != color;
}

class _BadgeMark extends CustomPainter {
  const _BadgeMark(this.kind, this.color, this.fontFamily);
  final String? fontFamily;
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate((size.width - size.height) / 2, 0);
    canvas.scale(size.height / 24, size.height / 24);
    if (kind == 'flame') {
      final flame = Path()
        ..moveTo(13.5, 2)
        ..cubicTo(15, 7, 8, 8, 10, 13)
        ..cubicTo(7, 12, 7, 9, 7, 8)
        ..cubicTo(1, 14, 5, 22, 12, 22)
        ..cubicTo(21, 22, 22, 13, 17, 8)
        ..cubicTo(18, 13, 14, 13, 15, 8)
        ..cubicTo(15, 5, 14, 3, 13.5, 2)
        ..close();
      canvas.drawPath(
        flame,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xffffdb5a), Color(0xffff9300)],
          ).createShader(const Rect.fromLTWH(2, 2, 20, 20)),
      );
    } else {
      final text = TextPainter(
        text: TextSpan(
          text: '榜',
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset((24 - text.width) / 2, (24 - text.height) / 2));
      for (final side in [-1, 1]) {
        for (var i = 0; i < 4; i++) {
          canvas.save();
          canvas.translate(side < 0 ? -2.0 : 26.0, 6.0 + i * 3.2);
          canvas.rotate(side * (.65 + i * .1));
          canvas.drawOval(
            const Rect.fromLTWH(-.7, -1.8, 1.4, 3.6),
            Paint()..color = color.withValues(alpha: .72),
          );
          canvas.restore();
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BadgeMark old) =>
      old.kind != kind || old.color != color || old.fontFamily != fontFamily;
}

/// Only the white sheet overscrolls, with a short, progressively resisted travel.
class LifeSheetPhysics extends ClampingScrollPhysics {
  const LifeSheetPhysics({super.parent});
  @override
  LifeSheetPhysics applyTo(ScrollPhysics? ancestor) =>
      LifeSheetPhysics(parent: buildParent(ancestor));
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (offset > 0 && position.pixels <= position.minScrollExtent) {
      final excess = (position.minScrollExtent - position.pixels).clamp(0, 24);
      return offset * .18 * math.pow(1 - excess / 24, 2);
    }
    return offset;
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.minScrollExtent) {
      return value < position.minScrollExtent - 24
          ? value - (position.minScrollExtent - 24)
          : 0;
    }
    if (position.pixels < position.minScrollExtent &&
        value <= position.minScrollExtent) {
      return 0;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.pixels < position.minScrollExtent) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        position.minScrollExtent,
        velocity,
        tolerance: toleranceFor(position),
      );
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
