import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marks a native page whose content was prepared by the assistant and still
/// needs the user's final review. The frame never intercepts page gestures.
class AssistantReviewFrame extends StatefulWidget {
  const AssistantReviewFrame({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<AssistantReviewFrame> createState() => _AssistantReviewFrameState();
}

class _AssistantReviewFrameState extends State<AssistantReviewFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AssistantReviewFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                key: const ValueKey('assistant-review-frame'),
                painter: _AssistantReviewFramePainter(_controller.value),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistantReviewFramePainter extends CustomPainter {
  const _AssistantReviewFramePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 3.0;
    final rect = Offset.zero & size;
    final inset = rect.deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF2378FF),
          Color(0xFF7357FF),
          Color(0xFFB64CFF),
          Color(0xFF2378FF),
        ],
        stops: const [0, 0.36, 0.72, 1],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(3)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AssistantReviewFramePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
