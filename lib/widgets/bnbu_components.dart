import 'bnbu_loading.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

class BnbuPageScaffold extends StatelessWidget {
  const BnbuPageScaffold({
    super.key,
    required this.header,
    required this.children,
    this.footer,
    this.padding,
  });

  final Widget header;
  final List<Widget> children;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: ListView(
          padding: padding ?? EdgeInsets.all(tokens.space16),
          children: [
            header,
            SizedBox(height: tokens.space16),
            ...children,
            if (footer != null) ...[SizedBox(height: tokens.space24), footer!],
          ],
        ),
      ),
    );
  }
}

class BnbuPageHeader extends StatelessWidget {
  const BnbuPageHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            SizedBox(
              width: tokens.minInteractiveDimension,
              height: tokens.minInteractiveDimension,
              child: Center(child: leading),
            ),
            SizedBox(width: tokens.space8),
          ],
          Expanded(
            child: BnbuText(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: tokens.space8),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: tokens.minInteractiveDimension,
                minHeight: tokens.minInteractiveDimension,
              ),
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ],
      ),
    );
  }
}

class BnbuSurfaceCard extends StatelessWidget {
  const BnbuSurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadiusGeometry? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Material(
      color: backgroundColor ?? tokens.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(tokens.radius16),
        side: BorderSide(color: borderColor ?? tokens.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? EdgeInsets.all(tokens.space16),
          child: child,
        ),
      ),
    );
  }
}

class BnbuSectionHeader extends StatelessWidget {
  const BnbuSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.space8),
        child: Row(
          children: [
            Expanded(
              child: BnbuText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: tokens.space8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: tokens.minInteractiveDimension,
                  minHeight: tokens.minInteractiveDimension,
                ),
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BnbuCompactActionTile extends StatelessWidget {
  const BnbuCompactActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.size = BnbuSizeTokens.compactTile,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final effectiveSize = math.max(size, tokens.minInteractiveDimension);
    final background = selected ? tokens.brandBlue : tokens.surface;
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : tokens.textPrimary;
    final iconColor = selected ? foreground : tokens.brandBlue;
    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      child: SizedBox.square(
        dimension: effectiveSize,
        child: Material(
          color: background,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius16),
            side: BorderSide(
              color: selected ? tokens.brandBlue : tokens.border,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(tokens.space8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: iconColor),
                  SizedBox(height: tokens.space4),
                  Flexible(
                    child: Center(
                      child: BnbuText(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum BnbuStatusKind { success, warning, danger, info, neutral }

class BnbuStatusBadge extends StatelessWidget {
  const BnbuStatusBadge({
    super.key,
    required this.label,
    this.kind = BnbuStatusKind.neutral,
    this.icon,
  });

  final String label;
  final BnbuStatusKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final colors = _statusColors(tokens, kind);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space8,
        vertical: tokens.space4,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.foreground),
            SizedBox(width: tokens.space4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: BnbuText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BnbuNotice extends StatelessWidget {
  const BnbuNotice({
    super.key,
    required this.message,
    this.kind = BnbuStatusKind.info,
    this.icon,
    this.action,
  });

  final String message;
  final BnbuStatusKind kind;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final colors = _statusColors(tokens, kind);
    return Padding(
      padding: EdgeInsets.all(tokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _statusIcon(kind), color: colors.foreground),
          SizedBox(width: tokens.space12),
          Expanded(
            child: BnbuText(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
            ),
          ),
          if (action != null) ...[
            SizedBox(width: tokens.space8),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: tokens.minInteractiveDimension,
                minHeight: tokens.minInteractiveDimension,
              ),
              child: action,
            ),
          ],
        ],
      ),
    );
  }
}

class BnbuLoadingState extends StatelessWidget {
  const BnbuLoadingState({super.key, this.title = '正在加载'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return _BnbuStatePanel(
      icon: const SizedBox.square(dimension: 28, child: BnbuInitialLoading()),
      title: title,
    );
  }
}

class BnbuErrorState extends StatelessWidget {
  const BnbuErrorState({
    super.key,
    this.title = '加载失败',
    this.message,
    this.action,
  });

  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return _BnbuStatePanel(
      icon: Icon(LucideIcons.circleAlert200, color: tokens.danger, size: 32),
      title: title,
      message: message,
      action: action,
    );
  }
}

class BnbuEmptyState extends StatelessWidget {
  const BnbuEmptyState({
    super.key,
    this.title = '暂无内容',
    this.message,
    this.action,
  });

  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return _BnbuStatePanel(
      icon: Icon(LucideIcons.inbox200, color: tokens.textMuted, size: 32),
      title: title,
      message: message,
      action: action,
    );
  }
}

class BnbuActionPreviewItem {
  const BnbuActionPreviewItem({required this.label, required this.value});

  final String label;
  final String value;
}

class BnbuActionPreviewSurface extends StatelessWidget {
  const BnbuActionPreviewSurface({
    super.key,
    required this.title,
    required this.items,
    this.actions = const [],
  });

  final String title;
  final List<BnbuActionPreviewItem> items;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          BnbuText(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (items.isNotEmpty) ...[
            SizedBox(height: tokens.space12),
            ...items.map((item) => _PreviewRow(item: item)),
          ],
          if (actions.isNotEmpty) ...[
            SizedBox(height: tokens.space16),
            Wrap(
              spacing: tokens.space8,
              runSpacing: tokens.space8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _BnbuStatePanel extends StatelessWidget {
  const _BnbuStatePanel({
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final Widget icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.all(tokens.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(height: tokens.space12),
          BnbuText(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (message != null) ...[
            SizedBox(height: tokens.space8),
            BnbuText(
              message!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (action != null) ...[
            SizedBox(height: tokens.space16),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: tokens.minInteractiveDimension,
                minHeight: tokens.minInteractiveDimension,
              ),
              child: action,
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item});

  final BnbuActionPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: BnbuText(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: tokens.textMuted),
            ),
          ),
          SizedBox(width: tokens.space12),
          Expanded(
            child: BnbuText(
              item.value,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

({Color foreground, Color background}) _statusColors(
  BnbuThemeExtension tokens,
  BnbuStatusKind kind,
) {
  return switch (kind) {
    BnbuStatusKind.success => (
      foreground: tokens.success,
      background: tokens.successContainer,
    ),
    BnbuStatusKind.warning => (
      foreground: tokens.warning,
      background: tokens.warningContainer,
    ),
    BnbuStatusKind.danger => (
      foreground: tokens.danger,
      background: tokens.dangerContainer,
    ),
    BnbuStatusKind.info => (
      foreground: tokens.info,
      background: tokens.infoContainer,
    ),
    BnbuStatusKind.neutral => (
      foreground: tokens.textSecondary,
      background: tokens.surfaceMuted,
    ),
  };
}

IconData _statusIcon(BnbuStatusKind kind) {
  return switch (kind) {
    BnbuStatusKind.success => LucideIcons.circleCheck300,
    BnbuStatusKind.warning => LucideIcons.triangleAlert300,
    BnbuStatusKind.danger => LucideIcons.circleAlert300,
    BnbuStatusKind.info => LucideIcons.info300,
    BnbuStatusKind.neutral => LucideIcons.circle300,
  };
}
