import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import 'bnbu_menu.dart';
import 'bnbu_adaptive.dart';

abstract final class FilePreviewMetrics {
  static const toolbarHeight = 44.0;
  static const titleSize = 17.0;
  static const iconSize = BnbuHeaderMetrics.iconSize;
  static const margin = 3.0;
}

/// Shared file-reading geometry; colours always come from BNBU.ME tokens.
class FilePreviewAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FilePreviewAppBar({
    super.key,
    required this.title,
    this.onShare,
    this.onReload,
    this.extraActions = const [],
  });
  final String title;
  final VoidCallback? onShare;
  final VoidCallback? onReload;
  final List<Widget> extraActions;
  @override
  Size get preferredSize =>
      const Size.fromHeight(FilePreviewMetrics.toolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: FilePreviewMetrics.toolbarHeight,
    backgroundColor: context.bnbuTheme.canvas,
    foregroundColor: context.bnbuTheme.textPrimary,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: Navigator.canPop(context)
        ? IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.maybePop(context),
            icon: const BnbuBackIcon(),
          )
        : null,
    leadingWidth: 48,
    titleSpacing: 0,
    title: Tooltip(
      message: title,
      child: BnbuText(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: FilePreviewMetrics.titleSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    actions: [
      ...extraActions,
      if (onShare != null || onReload != null)
        BnbuMenuButton<String>(
          tooltip: context.l10n.text('更多'),
          icon: const Icon(
            LucideIcons.ellipsis300,
            size: FilePreviewMetrics.iconSize,
          ),
          onSelected: (value) {
            if (value == 'share') onShare?.call();
            if (value == 'reload') onReload?.call();
          },
          itemBuilder: (context) => [
            PopupMenuItem(enabled: false, child: SelectableText(title)),
            if (onShare != null)
              PopupMenuItem(value: 'share', child: BnbuText('保存或分享')),
            if (onReload != null)
              PopupMenuItem(value: 'reload', child: BnbuText('刷新')),
          ],
        ),
    ],
  );
}

/// Keep short documents against the toolbar while retaining bounded zoom/pan.
Matrix4 normalizeFilePreviewMatrix(
  Matrix4 matrix,
  Size viewSize,
  PdfPageLayout layout,
  PdfViewerController? controller,
) {
  if (controller == null || !controller.isReady) return matrix;
  final zoom = math.max(matrix.zoom, controller.minScale);
  final center = filePreviewCenter(
    matrix.calcPosition(viewSize),
    viewSize,
    layout.documentSize,
    zoom,
  );
  return controller.calcMatrixFor(center, zoom: zoom, viewSize: viewSize);
}

@visibleForTesting
Offset filePreviewCenter(
  Offset position,
  Size view,
  Size document,
  double zoom,
) {
  final halfWidth = view.width / (2 * zoom);
  final halfHeight = view.height / (2 * zoom);
  final x = document.width <= halfWidth * 2
      ? document.width / 2
      : position.dx.clamp(halfWidth, document.width - halfWidth);
  final y = document.height <= halfHeight * 2
      ? halfHeight
      : position.dy.clamp(halfHeight, document.height - halfHeight);
  return Offset(x, y);
}
