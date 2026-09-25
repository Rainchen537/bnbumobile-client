import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Only the active status line shimmers. Text and semantics never change with
/// the animation, and background/offstage/reduced-motion states stop its ticker.
class AssistantThinkingText extends StatefulWidget {
  const AssistantThinkingText({
    super.key,
    required this.text,
    required this.active,
    this.failed = false,
  });
  final String text;
  final bool active;
  final bool failed;

  @override
  State<AssistantThinkingText> createState() => _AssistantThinkingTextState();
}

class _AssistantThinkingTextState extends State<AssistantThinkingText>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  bool _foreground = true;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _synchronize() {
    _animate =
        widget.active &&
        !widget.failed &&
        _foreground &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_animate) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronize();
  }

  @override
  void didUpdateWidget(AssistantThinkingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) setState(_synchronize);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final color = widget.failed ? tokens.warning : tokens.textMuted;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w400);
    if (!_animate) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: BnbuText(widget.text, style: style),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      child: AnimatedBuilder(
        animation: _animation,
        child: BnbuText(
          widget.text,
          style: style?.copyWith(color: Colors.white),
        ),
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-3 + _animation.value * 6, 0),
            end: Alignment(-1 + _animation.value * 6, 0),
            colors: [color, tokens.textPrimary, color],
            stops: const [0, 0.5, 1],
          ).createShader(bounds),
          child: child,
        ),
      ),
    );
  }
}
