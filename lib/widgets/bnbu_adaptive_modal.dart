import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'bnbu_adaptive.dart';
import 'bnbu_liquid_glass.dart';
import 'bnbu_notice.dart' show BnbuToast;

enum BnbuAdaptiveModalPresentation { bottomSheet, dialog }

extension BnbuAdaptiveModalPresentationX on BnbuAdaptiveModalPresentation {
  bool get isDialog => this == BnbuAdaptiveModalPresentation.dialog;
}

typedef BnbuAdaptiveModalBuilder =
    Widget Function(
      BuildContext context,
      BnbuAdaptiveModalPresentation presentation,
    );

/// Presents the same task as a touch-first bottom sheet on compact layouts and
/// as a bounded, keyboard-friendly dialog when the available width is larger.
Future<T?> showBnbuAdaptiveModal<T>({
  required BuildContext context,
  required BnbuAdaptiveModalBuilder builder,
  double dialogMaxWidth = 640,
  double dialogMaxHeight = 720,
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool barrierDismissible = true,
  bool useSafeArea = true,
  bool useRootNavigator = false,
  Color? bottomSheetBackgroundColor,
  Color? dialogBackgroundColor,
  String? semanticLabel,
  Key? contentKey,
  BorderRadius? borderRadius,
  BorderRadius? bottomSheetBorderRadius,
}) {
  // A previous page's transient feedback must not cover this task's header.
  BnbuToast.hide(context, immediately: true);
  final windowClass = BnbuBreakpoints.fromWidth(
    MediaQuery.sizeOf(context).width,
  );
  if (!windowClass.usesCenteredModal) {
    final liquidGlassEnabled = BnbuLiquidGlassScope.isEnabled(context);
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      useSafeArea: useSafeArea,
      isScrollControlled: isScrollControlled,
      isDismissible: barrierDismissible,
      enableDrag: enableDrag,
      clipBehavior: Clip.antiAlias,
      // The content header itself remains draggable. A Material grabber would
      // reserve another full touch target above that header on every phone.
      showDragHandle: false,
      shape: (bottomSheetBorderRadius ?? borderRadius) == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: (bottomSheetBorderRadius ?? borderRadius)!,
            ),
      requestFocus: true,
      backgroundColor:
          bottomSheetBackgroundColor ??
          (liquidGlassEnabled ? Colors.transparent : null),
      builder: (modalContext) => _BnbuAdaptiveModalSemantics(
        key: contentKey,
        semanticLabel: semanticLabel,
        child: builder(modalContext, BnbuAdaptiveModalPresentation.bottomSheet),
      ),
    );
  }

  return showDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
    barrierDismissible: barrierDismissible,
    requestFocus: true,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    builder: (dialogContext) {
      final tokens = dialogContext.bnbuTheme;
      return Dialog(
        backgroundColor: dialogBackgroundColor ?? tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.all(tokens.space24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(tokens.radius24),
          side: BorderSide(color: tokens.border),
        ),
        child: ConstrainedBox(
          key: const ValueKey('bnbu-adaptive-modal-dialog'),
          constraints: BoxConstraints(
            maxWidth: dialogMaxWidth,
            maxHeight: dialogMaxHeight,
          ),
          child: SizedBox(
            width: dialogMaxWidth,
            child: _BnbuAdaptiveModalSemantics(
              key: contentKey,
              semanticLabel: semanticLabel,
              child: builder(
                dialogContext,
                BnbuAdaptiveModalPresentation.dialog,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _BnbuAdaptiveModalSemantics extends StatelessWidget {
  const _BnbuAdaptiveModalSemantics({
    super.key,
    required this.child,
    this.semanticLabel,
  });

  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: semanticLabel != null,
      label: semanticLabel,
      explicitChildNodes: true,
      child: FocusTraversalGroup(child: child),
    );
  }
}

/// Shared visual frame for task-oriented adaptive modals.
///
/// The header stays compact on desktop, actions remain icon-led, and only the
/// body owns scrolling. This keeps selectors and editors visually consistent
/// without duplicating dialog chrome in every feature.
class BnbuModalFrame extends StatelessWidget {
  const BnbuModalFrame({
    super.key,
    this.preserveReferenceGeometry = false,
    required this.presentation,
    required this.title,
    required this.child,
    this.icon,
    this.titleTrailing,
    this.actions = const [],
    this.bottomBar,
    this.bodyPadding,
    this.showDividers = true,
    this.showClose = true,
    this.titleStyle,
  });

  final bool preserveReferenceGeometry;
  final BnbuAdaptiveModalPresentation presentation;
  final String title;
  final IconData? icon;
  final Widget? titleTrailing;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottomBar;
  final EdgeInsetsGeometry? bodyPadding;
  final bool showDividers;
  final bool showClose;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BnbuSecondaryHeader(
          referenceScale: preserveReferenceGeometry ? 0.65 : 1,
          child: SizedBox(
            height: preserveReferenceGeometry
                ? (presentation.isDialog ? 52 : 56)
                : BnbuHeaderMetrics.height,
            child: Padding(
              padding: EdgeInsets.only(
                left: tokens.space16,
                right: tokens.space8,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    SizedBox(width: tokens.space8),
                  ],
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: BnbuText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                titleStyle ??
                                (preserveReferenceGeometry
                                    ? Theme.of(
                                        context,
                                      ).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      )
                                    : BnbuHeaderMetrics.titleStyle),
                          ),
                        ),
                        if (titleTrailing != null) ...[
                          SizedBox(width: tokens.space8),
                          titleTrailing!,
                        ],
                      ],
                    ),
                  ),
                  ...actions,
                  if (showClose)
                    IconButton(
                      tooltip: context.l10n.text('关闭'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        LucideIcons.x300,
                        size: preserveReferenceGeometry
                            ? 18
                            : BnbuHeaderMetrics.iconSize,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDividers) Divider(height: 1, color: tokens.border),
        Flexible(
          child: Padding(
            padding: bodyPadding ?? EdgeInsets.all(tokens.space16),
            child: child,
          ),
        ),
        if (bottomBar != null) ...[
          if (showDividers) Divider(height: 1, color: tokens.border),
          Padding(padding: EdgeInsets.all(tokens.space8), child: bottomBar!),
        ],
      ],
    );
    if (presentation.isDialog) return content;
    final sheetRadius = BorderRadius.vertical(
      top: Radius.circular(tokens.radius24),
    );
    final sheet = Material(
      color: BnbuLiquidGlassScope.isEnabled(context)
          ? Colors.transparent
          : tokens.surface,
      borderRadius: sheetRadius,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(top: false, child: content),
    );
    if (!BnbuLiquidGlassScope.isEnabled(context)) {
      return sheet;
    }
    return BnbuLiquidGlassSurface(
      key: const ValueKey('ios-liquid-glass-bottom-sheet'),
      borderRadius: sheetRadius,
      tintColor: tokens.brandBlue,
      child: sheet,
    );
  }
}

/// High-contrast icon action for modal headers and confirmation rows.
///
/// Light mode deliberately stays white with a dark glyph. Dark mode uses the
/// semantic surface with a light glyph, avoiding primary/onPrimary collisions.
class BnbuModalActionButton extends StatelessWidget {
  const BnbuModalActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        maximumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        disabledBackgroundColor: tokens.surfaceMuted,
        disabledForegroundColor: tokens.textMuted,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
        ),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}
