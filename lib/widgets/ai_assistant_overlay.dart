import 'bnbu_loading.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../config/app_config.dart';
import '../services/app_navigation_coordinator.dart';
import '../state/app_session_controller.dart';
import '../state/assistant_presentation_controller.dart';
import '../state/study_mode_controller.dart';
import '../state/root_shell_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive.dart';
import 'bnbu_liquid_glass.dart';
import 'small_u_logo.dart';
import 'small_u_glass_logo.dart';

class AiAssistantOverlay extends StatefulWidget {
  const AiAssistantOverlay({
    super.key,
    required this.sessionController,
    required this.presentationController,
    required this.navigationCoordinator,
    this.studyModeController,
    this.shellController,
  });

  final AppSessionController sessionController;
  final AssistantPresentationController presentationController;
  final AppNavigationCoordinator navigationCoordinator;
  final StudyModeController? studyModeController;
  final RootShellController? shellController;

  @override
  State<AiAssistantOverlay> createState() => _AiAssistantOverlayState();
}

class _AiAssistantOverlayState extends State<AiAssistantOverlay> {
  static const double _buttonExtent = 56;
  static const double _edgeInset = 10;
  static const double _bottomNavigationClearance = 76;
  static const double _keyboardPageControlsClearance = 64;

  static const _edgeHideOffset = _buttonExtent * 0.6;
  static const _snapDistance = 24.0;
  static const _hideThreshold = 16.0;

  Offset? _dragPosition;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.presentationController.restoreFloatingAnchor());
  }

  @override
  void didUpdateWidget(covariant AiAssistantOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.presentationController,
      widget.presentationController,
    )) {
      _dragPosition = null;
      unawaited(widget.presentationController.restoreFloatingAnchor());
    }
  }

  Future<void> _openAssistant() {
    if (widget.presentationController.isAssistantPresented) {
      return widget.presentationController.dismissAssistant();
    }
    if (AppConfig.studyModeEnabled &&
        widget.studyModeController?.active == true) {
      return widget.studyModeController!.open();
    }
    return widget.navigationCoordinator.openAssistant();
  }

  Offset _clampPosition(
    Offset position, {
    required double minLeft,
    required double maxLeft,
    required double minTop,
    required double maxTop,
  }) {
    return Offset(
      position.dx.clamp(minLeft, maxLeft),
      position.dy.clamp(minTop, maxTop),
    );
  }

  void _finishDrag({
    required double minLeft,
    required double maxLeft,
    required double minTop,
    required double maxTop,
    required bool allowHide,
  }) {
    final position = _dragPosition;
    if (position == null) {
      return;
    }
    final hideLeft = allowHide && position.dx < minLeft - _hideThreshold;
    final hideRight = allowHide && position.dx > maxLeft + _hideThreshold;
    final snappedLeft = position.dx <= minLeft + _snapDistance
        ? minLeft
        : position.dx >= maxLeft - _snapDistance
        ? maxLeft
        : position.dx;
    final horizontalRange = maxLeft - minLeft;
    final verticalRange = maxTop - minTop;
    final anchor = Offset(
      horizontalRange <= 0 ? 0 : (snappedLeft - minLeft) / horizontalRange,
      verticalRange <= 0 ? 0 : (position.dy - minTop) / verticalRange,
    );
    setState(() {
      _dragPosition = null;
      _dragging = false;
    });
    widget.presentationController.updateFloatingAnchor(
      anchor,
      edgeHidden: hideLeft || hideRight,
    );
    unawaited(widget.presentationController.persistFloatingAnchor());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.sessionController,
        widget.presentationController,
        if (widget.studyModeController != null) widget.studyModeController!,
        if (widget.shellController != null) widget.shellController!,
      ]),
      builder: (context, _) {
        if (!widget.sessionController.isLoggedIn ||
            widget.presentationController.isFloatingOverlaySuppressed) {
          // Explicit suppression (such as eCard) keeps the saved anchor alive.
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = MediaQuery.paddingOf(context);
              final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
              final windowClass = BnbuBreakpoints.fromWidth(
                constraints.maxWidth,
              );
              // Horizontal snapping uses the actual window edges. Root rails,
              // safe-area content padding and page columns are layout content,
              // so none of them may become a false floating-button edge.
              final desktop = switch (defaultTargetPlatform) {
                TargetPlatform.macOS ||
                TargetPlatform.windows ||
                TargetPlatform.linux => true,
                _ => false,
              };
              final minLeft = math.max(12.0, padding.left + 12);
              final maxLeft = math.max(
                minLeft,
                constraints.maxWidth -
                    _buttonExtent -
                    math.max(12.0, padding.right + 12),
              );
              final minTop = padding.top + _edgeInset;
              // Anchors always use the resting canvas. Obstacles clamp only
              // an overlapping ball, never rescale every saved position.
              final restingClearance = windowClass.usesSideNavigation
                  ? 0.0
                  : _bottomNavigationClearance;
              final maxTop = math.max(
                minTop,
                constraints.maxHeight -
                    padding.bottom -
                    restingClearance -
                    _edgeInset -
                    _buttonExtent,
              );
              final anchor = widget.presentationController.floatingAnchor;
              final allowHide = !desktop && !windowClass.usesSideNavigation;
              final edgeHidden =
                  allowHide &&
                  widget.presentationController.floatingEdgeHidden &&
                  (anchor.dx == 0 || anchor.dx == 1);
              final anchoredPosition = Offset(
                minLeft +
                    (maxLeft - minLeft) * anchor.dx +
                    (edgeHidden
                        ? (anchor.dx == 0
                              ? -(_edgeHideOffset + minLeft)
                              : _edgeHideOffset +
                                    (constraints.maxWidth -
                                        _buttonExtent -
                                        maxLeft))
                        : 0),
                minTop + (maxTop - minTop) * anchor.dy,
              );
              final dragMinLeft =
                  minLeft - (allowHide ? _edgeHideOffset + minLeft : 0);
              final dragMaxLeft =
                  maxLeft +
                  (allowHide
                      ? _edgeHideOffset +
                            constraints.maxWidth -
                            _buttonExtent -
                            maxLeft
                      : 0);
              final composer =
                  widget.presentationController.assistantComposerRect;
              final ball =
                  (_dragPosition ?? anchoredPosition) &
                  const Size(_buttonExtent, _buttonExtent);
              var obstacleTop = keyboardInset > 0
                  ? constraints.maxHeight -
                        keyboardInset -
                        (widget.presentationController.isAssistantPresented
                            ? 12
                            : _keyboardPageControlsClearance)
                  : double.infinity;
              if (widget.presentationController.isAssistantPresented) {
                if (composer != null &&
                    ball.left < composer.right + 12 &&
                    ball.right > composer.left - 12 &&
                    ball.bottom > composer.top - 12) {
                  obstacleTop = math.min(obstacleTop, composer.top - 12);
                } else if (composer == null) {
                  final clearance =
                      widget.presentationController.assistantBottomAvoidance;
                  if (clearance > 0) {
                    obstacleTop = math.min(
                      obstacleTop,
                      constraints.maxHeight - keyboardInset - clearance,
                    );
                  }
                }
              }
              final visibleMaxTop = math.max(
                minTop,
                math.min(maxTop, obstacleTop - _buttonExtent),
              );
              final position = _clampPosition(
                _dragPosition ?? anchoredPosition,
                minLeft: dragMinLeft,
                maxLeft: dragMaxLeft,
                minTop: minTop,
                maxTop: visibleMaxTop,
              );

              return Stack(
                children: [
                  AnimatedPositioned(
                    left: position.dx,
                    top: position.dy,
                    width: _buttonExtent,
                    height: _buttonExtent,
                    duration:
                        _dragging || MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: GestureDetector(
                      key: const ValueKey('assistant-overlay-drag-target'),
                      behavior: HitTestBehavior.translucent,
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: (_) {
                        setState(() {
                          _dragging = true;
                          _dragPosition = position;
                        });
                      },
                      onPanUpdate: (details) {
                        final current = _dragPosition ?? position;
                        setState(() {
                          _dragPosition = _clampPosition(
                            current + details.delta,
                            minLeft: dragMinLeft,
                            maxLeft: dragMaxLeft,
                            minTop: minTop,
                            maxTop: maxTop,
                          );
                        });
                      },
                      onPanEnd: (_) => _finishDrag(
                        minLeft: minLeft,
                        maxLeft: maxLeft,
                        minTop: minTop,
                        maxTop: maxTop,
                        allowHide: allowHide,
                      ),
                      onPanCancel: () => setState(() {
                        _dragPosition = null;
                        _dragging = false;
                      }),
                      child: _AssistantFloatingButton(
                        busy: widget.presentationController.isAssistantBusy,
                        isPresented:
                            widget.presentationController.isAssistantPresented,
                        hasCompletedReply: widget
                            .presentationController
                            .hasUnseenCompletedReply,
                        edgeHidden: edgeHidden,
                        onPressed: () {
                          if (edgeHidden) {
                            widget.presentationController.updateFloatingAnchor(
                              anchor,
                            );
                            unawaited(
                              widget.presentationController
                                  .persistFloatingAnchor(),
                            );
                          } else {
                            unawaited(_openAssistant());
                          }
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _AssistantFloatingButton extends StatelessWidget {
  const _AssistantFloatingButton({
    required this.busy,
    required this.isPresented,
    required this.hasCompletedReply,
    required this.onPressed,
    required this.edgeHidden,
  });

  final bool busy;
  final bool isPresented;
  final bool hasCompletedReply;
  final VoidCallback onPressed;
  final bool edgeHidden;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useLiquidGlass =
        BnbuLiquidGlassScope.isEnabled(context) &&
        !MediaQuery.highContrastOf(context);
    final statusLabel = busy
        ? '，正在回复'
        : hasCompletedReply
        ? '，有新回复'
        : '';
    return Semantics(
      container: true,
      button: true,
      onTap: onPressed,
      label: context.l10n.text(
        '${edgeHidden
            ? '展开'
            : isPresented
            ? '收起'
            : '打开'}小U AI 助手$statusLabel',
      ),
      hint: context.l10n.text('可拖动调整位置'),
      child: ExcludeSemantics(
        child: FloatingActionButton(
          heroTag: 'global-ai-assistant',
          onPressed: onPressed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (useLiquidGlass)
                const SmallUGlassLogo(
                  key: ValueKey('assistant-overlay-liquid-glass'),
                )
              else
                Container(
                  key: const ValueKey('assistant-overlay-solid-surface'),
                  width: _AiAssistantOverlayState._buttonExtent,
                  height: _AiAssistantOverlayState._buttonExtent,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.black : Colors.white,
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF4A4A4A)
                          : const Color(0xFFD8D8D8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const SmallULogo(size: 35.1, monochrome: true),
                ),
              Positioned(
                right: -2,
                top: -2,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  child: busy
                      ? const BnbuActivityIndicator(
                          key: ValueKey('assistant-overlay-loading-indicator'),
                          size: 16,
                        )
                      : hasCompletedReply
                      ? Container(
                          key: const ValueKey(
                            'assistant-overlay-completion-indicator',
                          ),
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            color: const Color(0xFF31A66A),
                            shape: BoxShape.circle,
                            border: Border.all(color: tokens.surface, width: 2),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('assistant-overlay-idle-indicator'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
