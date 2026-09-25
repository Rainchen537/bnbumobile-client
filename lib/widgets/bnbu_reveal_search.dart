import 'bnbu_loading.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

enum BnbuRevealSearchMode { pageCentered, local }

/// Recesses browsing content while an empty search is focused. The barrier
/// owns the complete pointer sequence, so dismissal cannot activate a tile.
class BnbuSoftSearchBody extends StatelessWidget {
  const BnbuSoftSearchBody({
    super.key,
    required this.active,
    required this.onDismiss,
    required this.child,
  });
  final bool active;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(
          excluding: active,
          child: IgnorePointer(
            ignoring: active,
            child: AnimatedSlide(
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: active ? const Offset(0, .018) : Offset.zero,
              child: AnimatedOpacity(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                opacity: active ? .34 : 1,
                child: child,
              ),
            ),
          ),
        ),
        if (active)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('soft-search-dismiss-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// A search control that rests as a centered, borderless search affordance and
/// reveals its editable surface only after the user activates it.
///
/// [pageCentered] expects the widget to receive the page's full available
/// width. A [trailingAction] is positioned independently, so it never shifts
/// the resting search affordance away from the page center. [local] expands
/// only inside the slot allocated by its caller, which keeps neighbouring
/// toolbar commands and popup content stable.
class BnbuRevealSearch extends StatefulWidget {
  const BnbuRevealSearch({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = '搜索',
    this.collapsedLabel = '搜索',
    this.mode = BnbuRevealSearchMode.pageCentered,
    this.focusNode,
    this.isLoading = false,
    this.expandedMaxWidth,
    this.collapsedWidth = 100,
    this.alwaysExpanded = false,
    this.expandHitTarget = false,
    this.softMode = false,
    this.collapseOnFocusLoss = true,
    this.preserveQueryOnDismiss = false,
    this.onTapOutside,
    this.collapseOnTapOutside = false,
    this.duration = const Duration(milliseconds: 220),
    this.trailingAction,
    this.trailingExtent = 44,
    this.clearOnCollapse = true,
    this.onCollapsed,
    this.surfaceColor,
    this.useMutedSurface = false,
    this.foregroundColor,
    this.secondaryColor,
    this.borderColor,
    this.focusColor,
    this.controlKey,
    this.closeKey,
    this.trailingKey,
  }) : assert(
         mode == BnbuRevealSearchMode.pageCentered || trailingAction == null,
         'Local search actions belong outside the allocated search slot.',
       );

  /// Component-library hidden search. Container constraints control width.
  const BnbuRevealSearch.hidden({
    Key? key,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String hintText = '搜索',
    String collapsedLabel = '搜索',
    BnbuRevealSearchMode mode = BnbuRevealSearchMode.pageCentered,
    FocusNode? focusNode,
    bool isLoading = false,
    double? expandedMaxWidth,
    bool softMode = false,
    bool preserveQueryOnDismiss = false,
    bool collapseOnFocusLoss = true,
    TapRegionCallback? onTapOutside,
    VoidCallback? onCollapsed,
    Widget? trailingAction,
    Key? controlKey,
    Key? closeKey,
  }) : this(
         key: key,
         controller: controller,
         onChanged: onChanged,
         hintText: hintText,
         collapsedLabel: collapsedLabel,
         mode: mode,
         focusNode: focusNode,
         isLoading: isLoading,
         expandedMaxWidth: expandedMaxWidth,
         softMode: softMode,
         preserveQueryOnDismiss: preserveQueryOnDismiss,
         collapseOnFocusLoss: collapseOnFocusLoss,
         onTapOutside: onTapOutside,
         onCollapsed: onCollapsed,
         trailingAction: trailingAction,
         controlKey: controlKey,
         closeKey: closeKey,
         alwaysExpanded: false,
         useMutedSurface: true,
       );

  /// Component-library persistent search. Container constraints control width.
  const BnbuRevealSearch.persistent({
    Key? key,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String hintText = '搜索',
    String collapsedLabel = '搜索',
    BnbuRevealSearchMode mode = BnbuRevealSearchMode.pageCentered,
    FocusNode? focusNode,
    bool isLoading = false,
    double? expandedMaxWidth,
    bool softMode = false,
    bool preserveQueryOnDismiss = false,
    bool collapseOnFocusLoss = true,
    TapRegionCallback? onTapOutside,
    VoidCallback? onCollapsed,
    Widget? trailingAction,
    Key? controlKey,
    Key? closeKey,
  }) : this(
         key: key,
         controller: controller,
         onChanged: onChanged,
         hintText: hintText,
         collapsedLabel: collapsedLabel,
         mode: mode,
         focusNode: focusNode,
         isLoading: isLoading,
         expandedMaxWidth: expandedMaxWidth,
         softMode: softMode,
         preserveQueryOnDismiss: preserveQueryOnDismiss,
         collapseOnFocusLoss: collapseOnFocusLoss,
         onTapOutside: onTapOutside,
         onCollapsed: onCollapsed,
         trailingAction: trailingAction,
         controlKey: controlKey,
         closeKey: closeKey,
         alwaysExpanded: true,
         useMutedSurface: true,
       );

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final String collapsedLabel;
  final BnbuRevealSearchMode mode;
  final FocusNode? focusNode;
  final bool isLoading;
  final double? expandedMaxWidth;
  final double collapsedWidth;
  final bool alwaysExpanded;
  final bool expandHitTarget;

  /// Compact, full-slot activation with dismissal back to the quiet affordance.
  final bool softMode;

  /// Search surfaces with additional editable filters retain their query when
  /// focus moves into those filters. Outside taps still dismiss the surface.
  final bool collapseOnFocusLoss;

  /// Passive focus loss and outside taps only dismiss the keyboard while a
  /// query exists. Explicit cancel, Escape and back still clear the search.
  final bool preserveQueryOnDismiss;
  final TapRegionCallback? onTapOutside;
  final bool collapseOnTapOutside;
  final Duration duration;
  final Widget? trailingAction;
  final double trailingExtent;
  final bool clearOnCollapse;
  final VoidCallback? onCollapsed;
  final Color? surfaceColor;
  final bool useMutedSurface;
  final Color? foregroundColor;
  final Color? secondaryColor;
  final Color? borderColor;
  final Color? focusColor;
  final Key? controlKey;
  final Key? closeKey;
  final Key? trailingKey;

  @override
  State<BnbuRevealSearch> createState() => _BnbuRevealSearchState();
}

class _BnbuRevealSearchState extends State<BnbuRevealSearch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late bool _ownsFocusNode = widget.focusNode == null;
  bool _expanded = false;
  bool _collapsing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _focusNode.addListener(_handleFocusChanged);
    if (widget.alwaysExpanded || widget.controller.text.isNotEmpty) {
      _expanded = true;
      _animation.value = 1;
    }
  }

  @override
  void didUpdateWidget(BnbuRevealSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      if (widget.controller.text.isNotEmpty) _expand(requestFocus: false);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_handleFocusChanged);
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
      _ownsFocusNode = widget.focusNode == null;
      _focusNode.addListener(_handleFocusChanged);
    }
    if (oldWidget.alwaysExpanded != widget.alwaysExpanded) {
      _expanded =
          widget.alwaysExpanded ||
          widget.controller.text.isNotEmpty ||
          _focusNode.hasFocus;
      _animation.value = _expanded ? 1 : 0;
    }
    if (oldWidget.duration != widget.duration) {
      _animation.duration = widget.duration;
    }
  }

  void _handleControllerChanged() {
    if (widget.controller.text.isNotEmpty && !_expanded) {
      _expand(requestFocus: false);
    }
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _expand(requestFocus: false);
    } else if (widget.softMode && widget.collapseOnFocusLoss) {
      _dismissPassively();
    }
  }

  void _dismissPassively() {
    if (widget.preserveQueryOnDismiss &&
        widget.controller.text.trim().isNotEmpty) {
      _focusNode.unfocus();
      return;
    }
    _collapse();
  }

  void _expand({bool requestFocus = true}) {
    if (!_expanded) {
      setState(() => _expanded = true);
      if (MediaQuery.disableAnimationsOf(context)) {
        _animation.value = 1;
      } else {
        _animation.forward();
      }
    }
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _collapse() {
    if (!_expanded || _collapsing) return;
    _collapsing = true;
    _focusNode.unfocus();
    if (widget.clearOnCollapse && widget.controller.text.isNotEmpty) {
      widget.controller.clear();
      widget.onChanged('');
    }
    setState(() => _expanded = widget.alwaysExpanded);
    if (widget.alwaysExpanded) {
      _animation.value = 1;
      widget.onCollapsed?.call();
      _collapsing = false;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 0;
    } else {
      _animation.reverse();
    }
    widget.onCollapsed?.call();
    _collapsing = false;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final height = 44 + (scale - 1).clamp(0, 2.5) * 22.4;
    final surface =
        widget.surfaceColor ??
        (widget.useMutedSurface ? tokens.surfaceMuted : tokens.surface);
    final foreground = widget.foregroundColor ?? tokens.textPrimary;
    final secondary = widget.secondaryColor ?? tokens.textMuted;
    final border = widget.borderColor ?? tokens.border;
    final focus =
        widget.focusColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? BnbuColorTokens.darkSearchFocus
            : BnbuColorTokens.lightSearchFocus);
    final collapsedLabel = context.l10n.text(widget.collapsedLabel);
    final collapsedLabelStyle = Theme.of(
      context,
    ).textTheme.bodyLarge!.copyWith(fontSize: 16, color: secondary);
    final labelPainter = TextPainter(
      text: TextSpan(text: collapsedLabel, style: collapsedLabelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // Keep the existing resting size unless the selected language needs more
    // room for its label, search icon, gap, and field insets.
    final restingWidth = math.max(
      widget.collapsedWidth * scale,
      labelPainter.width + 18 + 6 + 32,
    );
    labelPainter.dispose();

    return PopScope(
      canPop: widget.alwaysExpanded
          ? widget.controller.text.isEmpty && !_focusNode.hasFocus
          : !_expanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _expanded) _collapse();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_expanded) _collapse();
          },
        },
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_animation.value);
                final availableWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : widget.expandedMaxWidth ?? restingWidth;
                final maxWidth = math.min(
                  availableWidth,
                  widget.expandedMaxWidth ?? availableWidth,
                );
                final collapsedWidth = math.min(restingWidth, maxWidth);
                final searchWidth =
                    collapsedWidth + (maxWidth - collapsedWidth) * t;
                final outline = OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radius12),
                  borderSide: BorderSide(
                    color: border.withValues(alpha: border.a * 0.5 * t),
                  ),
                );
                final focusedOutline = outline.copyWith(
                  borderSide: BorderSide(
                    color: focus.withValues(alpha: focus.a * 0.5 * t),
                    width: 1.4,
                  ),
                );

                return ClipRect(
                  child: SizedBox(
                    width: availableWidth,
                    height: height,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (widget.trailingAction != null)
                          PositionedDirectional(
                            key: widget.trailingKey,
                            end: -widget.trailingExtent * t,
                            child: IgnorePointer(
                              ignoring: _expanded,
                              child: Opacity(
                                opacity: 1 - t,
                                child: SizedBox.square(
                                  dimension: widget.trailingExtent,
                                  child: widget.trailingAction,
                                ),
                              ),
                            ),
                          ),
                        if ((widget.expandHitTarget || widget.softMode) &&
                            !_expanded)
                          PositionedDirectional(
                            start: (availableWidth - maxWidth) / 2,
                            end: math.max(
                              (availableWidth - maxWidth) / 2,
                              widget.trailingAction == null
                                  ? 0
                                  : widget.trailingExtent,
                            ),
                            top: 0,
                            bottom: 0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              excludeFromSemantics: true,
                              onTap: _expand,
                            ),
                          ),
                        SizedBox(
                          width: searchWidth,
                          child: TextField(
                            key: widget.controlKey,
                            controller: widget.controller,
                            focusNode: _focusNode,
                            onTap: () => _expand(),
                            onChanged: widget.onChanged,
                            onTapOutside:
                                widget.collapseOnTapOutside || widget.softMode
                                ? (event) {
                                    _dismissPassively();
                                    widget.onTapOutside?.call(event);
                                  }
                                : widget.onTapOutside,
                            textInputAction: TextInputAction.search,
                            textAlign: _expanded
                                ? TextAlign.start
                                : TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(color: foreground),
                            decoration: InputDecoration(
                              hint: _expanded
                                  ? BnbuText(
                                      context.l10n.text(widget.hintText),
                                      style: TextStyle(color: secondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          LucideIcons.search300,
                                          size: 18,
                                          color: secondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            collapsedLabel,
                                            style: collapsedLabelStyle,
                                          ),
                                        ),
                                      ],
                                    ),
                              prefixIcon: _expanded
                                  ? widget.isLoading
                                        ? Padding(
                                            padding: const EdgeInsets.all(11),
                                            child: SizedBox.square(
                                              dimension: 18,
                                              child: BnbuActivityIndicator(
                                                color: focus,
                                              ),
                                            ),
                                          )
                                        : Icon(
                                            LucideIcons.search300,
                                            size: 18,
                                            color: secondary,
                                          )
                                  : null,
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              // Reserve the cancel slot progressively. In the
                              // first frame the field still has its resting
                              // width, so allocating 44px at once crushes the
                              // hint between the two icon slots.
                              suffixIcon: _expanded
                                  ? ClipRect(
                                      child: OverflowBox(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        minWidth: 44,
                                        maxWidth: 44,
                                        child: IgnorePointer(
                                          ignoring: t < 1,
                                          child: Opacity(
                                            opacity: t,
                                            child: IconButton(
                                              key: widget.closeKey,
                                              tooltip: context.l10n.text('取消'),
                                              onPressed: _collapse,
                                              icon: Icon(
                                                LucideIcons.x300,
                                                size: 18,
                                                color: secondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                              suffixIconConstraints: BoxConstraints(
                                minWidth: 44 * t,
                                maxWidth: 44 * t,
                                minHeight: 44,
                                maxHeight: height,
                              ),
                              filled: true,
                              fillColor: Color.lerp(
                                Colors.transparent,
                                surface,
                                t,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              border: outline,
                              enabledBorder: outline,
                              focusedBorder: focusedOutline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
