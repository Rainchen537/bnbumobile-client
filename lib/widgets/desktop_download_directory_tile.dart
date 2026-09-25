import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/desktop_download_service.dart';
import '../theme/app_theme.dart';
import 'bnbu_notice.dart';

class DesktopDownloadDirectoryTile extends StatefulWidget {
  const DesktopDownloadDirectoryTile({
    super.key,
    required this.purpose,
    this.enabled = true,
    this.service = const DesktopDownloadService(),
  });
  final DesktopDownloadPurpose purpose;
  final bool enabled;
  final DesktopDownloadService service;

  @override
  State<DesktopDownloadDirectoryTile> createState() =>
      _DesktopDownloadDirectoryTileState();
}

class _DesktopDownloadDirectoryTileState
    extends State<DesktopDownloadDirectoryTile> {
  String? _path;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _change(() => widget.service.directory(widget.purpose), notify: false);
  }

  Future<void> _change(
    Future<String?> Function() action, {
    bool notify = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await action();
      if (mounted && path != null) setState(() => _path = path);
    } catch (_) {
      if (mounted && notify) {
        BnbuToast.show(
          context,
          context.l10n.text('下载位置不可用，请重新选择文件夹。'),
          kind: BnbuToastKind.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('download-directory-${widget.purpose.name}'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: const Icon(LucideIcons.folderDown300, size: 22),
    title: BnbuText(
      widget.purpose == DesktopDownloadPurpose.single
          ? 'iSpace 单个下载位置'
          : '全部下载位置',
    ),
    subtitle: Tooltip(
      message: _path ?? context.l10n.text('请选择下载文件夹'),
      child: Text(
        _path ?? context.l10n.text(_busy ? '正在读取…' : '请选择下载文件夹'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    onTap: _busy || !widget.enabled
        ? null
        : () => _change(() => widget.service.chooseDirectory(widget.purpose)),
    trailing: IconButton(
      tooltip: context.l10n.text('恢复系统下载目录'),
      icon: const Icon(LucideIcons.rotateCcw300, size: 18),
      onPressed: _busy || !widget.enabled
          ? null
          : () => _change(() => widget.service.resetDirectory(widget.purpose)),
    ),
  );
}
