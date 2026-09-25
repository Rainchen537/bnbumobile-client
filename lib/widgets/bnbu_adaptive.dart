import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Window classes are based on the space available to the current widget,
/// rather than on a device name or a fixed screen orientation.
enum BnbuWindowClass { compact, medium, expanded }

abstract final class BnbuBreakpoints {
  static const compactMax = 699.0;
  static const mediumMax = 1099.0;

  /// Available content width at which task pages can expose a persistent
  /// secondary pane without squeezing the primary workspace.
  static const tabletWorkspace = 880.0;
  static const expandedNavigation = 1100.0;
  static const contentMax = 1440.0;
  static const sideNavigationWidth = 72.0;
  static const sideNavigationCollapsedWidth = sideNavigationWidth;
  static const sideNavigationExpandedWidth = sideNavigationWidth;

  static BnbuWindowClass fromWidth(double width) {
    if (width <= compactMax) {
      return BnbuWindowClass.compact;
    }
    if (width <= mediumMax) {
      return BnbuWindowClass.medium;
    }
    return BnbuWindowClass.expanded;
  }
}

/// Shared visual rhythm for page-level toolbars.
///
/// The 64 px rail matches the mail workspace: 8 px vertical insets around a
/// 48 px interaction target. Icons stay visually compact without shrinking
/// their mouse, keyboard, or touch hit area.
abstract final class BnbuTopBarMetrics {
  static const height = 64.0;
  static const controlExtent = 48.0;
  static const iconSize = 20.0;
  static const compactTopInset = 12.0;
}

/// Shared native title sizes for phones, tablets and desktop windows.
abstract final class BnbuHeaderMetrics {
  static const height = 44.0;
  static const titleSize = 17.0;
  static const iconSize = 24.0;
  static const actionSize = 16.0;
  static const titleStyle = TextStyle(
    fontSize: titleSize,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
}

/// Same glyph and explicit painted size as the map/calendar reading header.
/// An IconTheme alone cannot normalize platform-specific BackButton glyphs.
class BnbuBackIcon extends StatelessWidget {
  const BnbuBackIcon({super.key});

  @override
  Widget build(BuildContext context) =>
      const Icon(LucideIcons.chevronLeft300, size: BnbuHeaderMetrics.iconSize);
}

/// A shared, unscaled title-region boundary. Layout and hit coordinates stay
/// native; callers obtain explicit visual sizes from BnbuHeaderMetrics.
class BnbuSecondaryHeader extends StatelessWidget {
  const BnbuSecondaryHeader({
    super.key,
    required this.child,
    this.referenceScale = 1,
  });
  final Widget child;

  /// Reserved for the user's protected, pre-existing mail reference geometry.
  final double referenceScale;
  @override
  Widget build(BuildContext context) => referenceScale == 1
      ? child
      : LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: constraints.maxWidth / referenceScale,
              child: child,
            ),
          ),
        );
}

class BnbuSecondaryAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const BnbuSecondaryAppBar({super.key, required this.bar});

  final AppBar bar;
  double get _height => math.max(
    BnbuHeaderMetrics.height,
    (bar.toolbarHeight ?? 56) > 56 ? bar.toolbarHeight! : 0,
  );
  @override
  Size get preferredSize =>
      Size.fromHeight(_height + (bar.bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        bar.foregroundColor ??
        theme.appBarTheme.foregroundColor ??
        theme.colorScheme.onSurface;
    final icons =
        bar.iconTheme ??
        theme.appBarTheme.iconTheme ??
        IconThemeData(color: foreground);
    final actionIcons =
        bar.actionsIconTheme ?? theme.appBarTheme.actionsIconTheme ?? icons;
    return ActionIconTheme(
      data: (ActionIconTheme.of(context) ?? const ActionIconThemeData())
          .copyWith(backButtonIconBuilder: (_) => const BnbuBackIcon()),
      child: AppBar(
        key: bar.key,
        leading: bar.leading,
        automaticallyImplyLeading: bar.automaticallyImplyLeading,
        title: bar.title,
        actions: bar.actions,
        automaticallyImplyActions: bar.automaticallyImplyActions,
        flexibleSpace: bar.flexibleSpace,
        bottom: bar.bottom,
        elevation: bar.elevation,
        scrolledUnderElevation: bar.scrolledUnderElevation ?? 0,
        notificationPredicate: bar.notificationPredicate,
        shadowColor: bar.shadowColor,
        surfaceTintColor: bar.surfaceTintColor ?? Colors.transparent,
        shape: bar.shape,
        backgroundColor: bar.backgroundColor,
        foregroundColor: bar.foregroundColor,
        iconTheme: icons.copyWith(size: BnbuHeaderMetrics.iconSize),
        actionsIconTheme: actionIcons.copyWith(
          size: BnbuHeaderMetrics.iconSize,
        ),
        primary: bar.primary,
        centerTitle: bar.centerTitle,
        excludeHeaderSemantics: bar.excludeHeaderSemantics,
        titleSpacing: bar.titleSpacing ?? 0,
        toolbarOpacity: bar.toolbarOpacity,
        bottomOpacity: bar.bottomOpacity,
        toolbarHeight: _height,
        leadingWidth: bar.leadingWidth ?? 48,
        toolbarTextStyle: bar.toolbarTextStyle,
        titleTextStyle:
            (bar.titleTextStyle ??
                    Theme.of(context).appBarTheme.titleTextStyle ??
                    const TextStyle())
                .merge(BnbuHeaderMetrics.titleStyle)
                .copyWith(
                  color: bar.titleTextStyle?.color ?? bar.foregroundColor,
                ),
        systemOverlayStyle: bar.systemOverlayStyle,
        forceMaterialTransparency: bar.forceMaterialTransparency,
        useDefaultSemanticsOrder: bar.useDefaultSemanticsOrder,
        clipBehavior: bar.clipBehavior,
        actionsPadding: bar.actionsPadding,
        animateColor: bar.animateColor,
      ),
    );
  }
}

extension BnbuWindowClassX on BnbuWindowClass {
  bool get usesSideNavigation => this != BnbuWindowClass.compact;

  bool get usesCenteredModal => this != BnbuWindowClass.compact;

  bool get isExpanded => this == BnbuWindowClass.expanded;

  /// Window-level overlays reserve one stable rail width for each window class.
  ///
  /// All wide windows use the same fixed rail, including existing installations
  /// with a saved expansion preference.
  double get stableSideNavigationWidth => switch (this) {
    BnbuWindowClass.compact => 0,
    BnbuWindowClass.medium => BnbuBreakpoints.sideNavigationCollapsedWidth,
    BnbuWindowClass.expanded => BnbuBreakpoints.sideNavigationExpandedWidth,
  };
}

class BnbuConstrainedContent extends StatelessWidget {
  const BnbuConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = BnbuBreakpoints.contentMax,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
