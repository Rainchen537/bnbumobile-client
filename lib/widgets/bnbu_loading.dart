import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../l10n/bnbu_localizations.dart';

/// Shared, transparent activity glyph, including compact inline controls.
class BnbuActivityIndicator extends StatelessWidget {
  const BnbuActivityIndicator({
    super.key,
    this.color,
    this.size = 20,
    this.animating = true,
  });

  final Color? color;
  final double size;
  final bool animating;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.text('正在加载'),
    child: SizedBox.square(
      dimension: size,
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: CupertinoActivityIndicator(
            radius: math.max(1, constraints.biggest.shortestSide / 2),
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            animating: animating && !MediaQuery.disableAnimationsOf(context),
          ),
        ),
      ),
    ),
  );
}

/// One independently updating content region. Pull refresh suppresses its
/// background bar and initial spinner, while other panes remain independent.
class BnbuLoadingRegion extends StatefulWidget {
  const BnbuLoadingRegion({super.key, required this.child});
  final Widget child;
  @override
  State<BnbuLoadingRegion> createState() => _BnbuLoadingRegionState();
}

class _BnbuLoadingRegionState extends State<BnbuLoadingRegion> {
  final _active = <Object>{};
  void setPulling(Object owner, bool active) {
    if (!mounted) return;
    final changed = active ? _active.add(owner) : _active.remove(owner);
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      _PullLoadingScope(active: _active.isNotEmpty, child: widget.child);
}

class _PullLoadingScope extends InheritedWidget {
  const _PullLoadingScope({required this.active, required super.child});
  final bool active;
  static bool pulling(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PullLoadingScope>()?.active ??
      false;
  @override
  bool updateShouldNotify(_PullLoadingScope oldWidget) =>
      active != oldWidget.active;
}

/// A permanently reserved, thin slot for an existing surface being updated.
class BnbuUpdateProgress extends StatelessWidget {
  const BnbuUpdateProgress({
    super.key,
    required this.active,
    this.color,
    this.height = 2,
  });
  final bool active;
  final Color? color;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: active && !_PullLoadingScope.pulling(context)
        ? LinearProgressIndicator(
            minHeight: height,
            color: color ?? Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.transparent,
            value: MediaQuery.disableAnimationsOf(context) ? 0.35 : null,
            semanticsLabel: context.l10n.text('正在加载'),
          )
        : null,
  );
}

/// Waiting in an already empty canvas, without duplicating a pull gesture.
class BnbuInitialLoading extends StatelessWidget {
  const BnbuInitialLoading({super.key});
  @override
  Widget build(BuildContext context) => _PullLoadingScope.pulling(context)
      ? const SizedBox.shrink()
      : const Center(child: BnbuActivityIndicator());
}

/// Keep Flutter's refresh gesture/async lifecycle, with the same bare glyph on
/// every platform. The overlay never intercepts scrolling or taps.
class BnbuRefreshIndicator extends StatefulWidget {
  const BnbuRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final Color? color;

  @override
  State<BnbuRefreshIndicator> createState() => _BnbuRefreshIndicatorState();
}

class _BnbuRefreshIndicatorState extends State<BnbuRefreshIndicator> {
  RefreshIndicatorStatus? _status;
  _BnbuLoadingRegionState? _region;
  bool get _pulling =>
      _status != null &&
      _status != RefreshIndicatorStatus.canceled &&
      _status != RefreshIndicatorStatus.done;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _region = context.findAncestorStateOfType<_BnbuLoadingRegionState>();
  }

  @override
  void dispose() {
    final region = _region;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => region?.setPulling(this, false),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PullLoadingScope(
    active: _pulling,
    child: Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          onStatusChange: (status) {
            if (mounted) {
              setState(() => _status = status);
              _region?.setPulling(this, _pulling);
            }
          },
          child: widget.child,
        ),
        if (_status != null &&
            _status != RefreshIndicatorStatus.canceled &&
            _status != RefreshIndicatorStatus.done)
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(child: BnbuActivityIndicator(color: widget.color)),
            ),
          ),
      ],
    ),
  );
}
