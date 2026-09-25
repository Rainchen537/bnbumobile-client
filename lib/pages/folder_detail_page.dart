import '../widgets/ispace_content_padding.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../theme/app_theme.dart';

import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../services/native_actions.dart';
import '../services/desktop_download_service.dart';
import '../state/app_session_controller.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_notice.dart';
import 'web_mirror_page.dart';

class FolderDetailPage extends StatefulWidget {
  const FolderDetailPage({
    super.key,
    required this.controller,
    required this.course,
    required this.module,
  });

  final AppSessionController controller;
  final CourseSummary course;
  final CourseModule module;

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  static const MethodChannel _nativeActionsChannel = MethodChannel(
    'ispace/native_actions',
  );

  List<CourseModuleContent> _files = const [];
  String _descriptionHtml = '';
  bool _loading = false;
  bool _isDownloading = false;
  String? _error;

  String get _downloadFolderUrl {
    final raw = widget.module.url.trim();
    final parsed = Uri.tryParse(raw);
    final idFromQuery = parsed?.queryParameters['id']?.trim() ?? '';
    final cmid = int.tryParse(idFromQuery) ?? widget.module.id;
    if (cmid <= 0) {
      return '';
    }
    return '${widget.controller.baseUrl}/mod/folder/download_folder.php?id=$cmid';
  }

  @override
  void initState() {
    super.initState();
    _descriptionHtml = widget.module.descriptionHtml.trim();
    _files = _normalizeFiles(widget.module.contents);
    if (_files.isEmpty || _descriptionHtml.isEmpty) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sections = await widget.controller.loadCourseContents(
        widget.course.id,
      );
      final latest = _resolveFolderModule(sections);
      if (!mounted) {
        return;
      }
      if (latest == null) {
        setState(() {
          _error = 'Folder 内容加载失败，请稍后重试。';
        });
      } else {
        setState(() {
          _descriptionHtml = latest.descriptionHtml.trim();
          _files = _normalizeFiles(latest.contents);
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Folder 内容加载失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  CourseModule? _resolveFolderModule(List<CourseContentSection> sections) {
    final targetModuleId = widget.module.id;
    final targetInstanceId = widget.module.instance;
    final targetUrl = widget.module.url.trim();

    for (final section in sections) {
      for (final module in section.modules) {
        final modName = module.modName.toLowerCase();
        if (!modName.contains('folder')) {
          continue;
        }
        if (targetModuleId > 0 && module.id == targetModuleId) {
          return module;
        }
        if (targetInstanceId > 0 && module.instance == targetInstanceId) {
          return module;
        }
        if (targetUrl.isNotEmpty &&
            module.url.trim().isNotEmpty &&
            module.url.trim() == targetUrl) {
          return module;
        }
      }
    }
    return null;
  }

  List<CourseModuleContent> _normalizeFiles(List<CourseModuleContent> source) {
    final files = source
        .where((item) => item.fileName.trim().isNotEmpty)
        .toList(growable: false);
    files.sort((a, b) {
      final orderCompare = a.sortOrder.compareTo(b.sortOrder);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
    });
    return files;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bnbuTheme.canvas,
      appBar: BnbuSecondaryAppBar(
        bar: AppBar(
          title: BnbuText(widget.module.name),
          actions: [
            if (_downloadFolderUrl.isNotEmpty)
              IconButton(
                onPressed: _isDownloading ? null : _downloadFolder,
                tooltip: context.l10n.text(
                  _isDownloading ? '正在下载文件夹' : '下载文件夹',
                ),
                icon: _isDownloading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: BnbuActivityIndicator(),
                      )
                    : const Icon(LucideIcons.download300),
              ),
            IconButton(
              onPressed: _loading ? null : _refresh,
              tooltip: context.l10n.text('刷新'),
              icon: const Icon(LucideIcons.refreshCw300),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: BnbuConstrainedContent(
          maxWidth: BnbuBreakpoints.contentMax,
          child: IspaceContentPadding(
            top: 12,
            bottom: 16,
            child: _buildFolderContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overview = <Widget>[
          _summaryCard(context),
          BnbuUpdateProgress(active: _loading && _files.isNotEmpty),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _errorBox(context, _error!),
          ],
          if (_descriptionHtml.isNotEmpty) ...[
            const SizedBox(height: 12),
            _descriptionPanel(_descriptionHtml),
          ],
        ];
        if (constraints.maxWidth < BnbuBreakpoints.tabletWorkspace) {
          return ListView(
            children: [
              ...overview,
              const SizedBox(height: 12),
              _filesCard(context),
            ],
          );
        }

        final overviewWidth = (constraints.maxWidth * 0.36)
            .clamp(320.0, 380.0)
            .toDouble();
        return Row(
          key: const ValueKey('folder-tablet-split-layout'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('folder-tablet-overview-pane'),
              width: overviewWidth,
              child: ListView(children: overview),
            ),
            const SizedBox(width: 16),
            Expanded(
              key: const ValueKey('folder-tablet-files-pane'),
              child: ListView(children: [_filesCard(context)]),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.bnbuTheme.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            widget.course.fullName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.bnbuTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          BnbuText(
            '共 ${_files.length} 个文件',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _downloadFolderUrl.isEmpty || _isDownloading
                ? null
                : _downloadFolder,
            icon: _isDownloading
                ? const SizedBox.square(
                    dimension: 18,
                    child: BnbuActivityIndicator(),
                  )
                : const Icon(LucideIcons.archive300),
            label: BnbuText(_isDownloading ? '正在准备下载…' : '下载整个文件夹'),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      child: BnbuText(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _descriptionPanel(String descriptionHtml) {
    final html = _buildHtmlDocument(descriptionHtml);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.bnbuTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 260,
          child: MirrorWebViewPanel.html(
            controller: widget.controller,
            htmlContent: html,
          ),
        ),
      ),
    );
  }

  Widget _filesCard(BuildContext context) {
    if (_files.isEmpty) {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: BnbuInitialLoading(),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(18),
        child: BnbuText('当前 Folder 暂无可展示文件。'),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.bnbuTheme.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: _files.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: BnbuText('当前 Folder 暂无可展示文件。'),
            )
          : Column(
              children: [
                for (var i = 0; i < _files.length; i++) ...[
                  _fileTile(context, _files[i]),
                  if (i != _files.length - 1)
                    const Divider(height: 1, indent: 14, endIndent: 14),
                ],
              ],
            ),
    );
  }

  Widget _fileTile(BuildContext context, CourseModuleContent file) {
    final fileUrl = file.fileUrl.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: fileUrl.isEmpty ? null : () => _openFilePreview(file),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.bnbuTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  _fileIcon(file),
                  size: 18,
                  color: context.bnbuTheme.brandBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BnbuText(
                      file.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    BnbuText(
                      _fileMeta(file),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.bnbuTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight300),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(CourseModuleContent file) {
    final name = file.fileName.toLowerCase();
    final mime = file.mimeType.toLowerCase();
    if (mime.startsWith('image/') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return LucideIcons.image300;
    }
    if (name.endsWith('.pdf') || mime.contains('pdf')) {
      return LucideIcons.fileText300;
    }
    if (name.endsWith('.ppt') || name.endsWith('.pptx')) {
      return LucideIcons.presentation300;
    }
    if (name.endsWith('.doc') ||
        name.endsWith('.docx') ||
        mime.contains('word')) {
      return LucideIcons.fileText300;
    }
    if (name.endsWith('.xls') ||
        name.endsWith('.xlsx') ||
        mime.contains('excel') ||
        mime.contains('spreadsheet')) {
      return LucideIcons.table2300;
    }
    if (name.endsWith('.zip') ||
        name.endsWith('.rar') ||
        mime.contains('zip')) {
      return LucideIcons.archive300;
    }
    return LucideIcons.file300;
  }

  String _fileMeta(CourseModuleContent file) {
    final parts = <String>[];
    if (file.fileSize > 0) {
      parts.add(_formatBytes(file.fileSize));
    }
    if (file.timeModifiedAt != null) {
      parts.add(
        context.l10n.formatFullDateTime(file.timeModifiedAt!.toLocal()),
      );
    }
    if (file.mimeType.trim().isNotEmpty) {
      parts.add(file.mimeType.trim());
    }
    return parts.isEmpty ? '点击预览' : parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size = size / 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size < 10 && unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}';
  }

  Future<void> _openFilePreview(CourseModuleContent file) async {
    final previewUrl = _toPreviewUrl(file.fileUrl);
    if (previewUrl.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebMirrorPage(
          controller: widget.controller,
          title: file.fileName,
          pathOrUrl: previewUrl,
          showFileActions: true,
        ),
      ),
    );
  }

  String _toPreviewUrl(String sourceUrl) {
    final absolute = _resolveAbsoluteUrl(sourceUrl);
    if (absolute.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(absolute);
    if (uri == null) {
      return absolute;
    }
    final normalizedPath = uri.path.replaceFirst(
      '/webservice/pluginfile.php',
      '/pluginfile.php',
    );
    final query = Map<String, String>.from(uri.queryParameters);
    query.remove('token');
    final normalized = uri.replace(
      path: normalizedPath,
      queryParameters: query.isEmpty ? null : query,
    );
    return normalized.toString();
  }

  String _resolveAbsoluteUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${widget.controller.baseUrl}$trimmed';
    }
    return '${widget.controller.baseUrl}/$trimmed';
  }

  Future<void> _downloadFolder() async {
    if (_downloadFolderUrl.isEmpty || _isDownloading) {
      return;
    }
    setState(() => _isDownloading = true);
    if (DesktopDownloadService.supported) {
      try {
        await downloadIspaceDesktopFile(
          context,
          controller: widget.controller,
          url: _downloadFolderUrl,
          filename: '${_safeFileName(widget.module.name)}.zip',
          isActive: () => mounted,
        );
      } finally {
        if (mounted) setState(() => _isDownloading = false);
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox.square(dimension: 18, child: BnbuActivityIndicator()),
            SizedBox(width: 12),
            Expanded(child: BnbuText('正在准备文件夹压缩包，请稍候…')),
          ],
        ),
        duration: Duration(minutes: 1),
      ),
    );

    final fileName = '${_safeFileName(widget.module.name)}.zip';
    String cookieHeader = '';
    String cookieOrigin = '';
    try {
      final snapshot = await widget.controller.prepareWebSession();
      if (urlsHaveSameOrigin(_downloadFolderUrl, snapshot.baseUrl)) {
        cookieHeader = snapshot.cookies
            .where((cookie) => cookie.name.trim().isNotEmpty)
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; ');
        cookieOrigin = snapshot.baseUrl;
      }
    } catch (_) {
      cookieHeader = '';
      cookieOrigin = '';
    }
    try {
      final downloadResult = await _nativeActionsChannel
          .invokeMethod<dynamic>('downloadFile', {
            'url': _downloadFolderUrl,
            'filename': fileName,
            'title': widget.module.name,
            if (cookieHeader.isNotEmpty) 'cookieHeader': cookieHeader,
            if (cookieOrigin.isNotEmpty) 'cookieOrigin': cookieOrigin,
          });
      if (!mounted) {
        return;
      }
      final completedName = downloadedFileDisplayName(
        downloadResult,
        fallback: fileName,
      );
      final message =
          downloadResult is String && downloadResult.trim().isNotEmpty
          ? completedName.isEmpty
                ? '文件夹下载完成。'
                : '下载完成：$completedName'
          : '已开始下载：$fileName';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: BnbuText(message)));
    } on PlatformException {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: BnbuText('系统下载不可用，已切换到网页下载。')));
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebMirrorPage(
            controller: widget.controller,
            title: '下载文件夹',
            pathOrUrl: _downloadFolderUrl,
            showFileActions: true,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  String _safeFileName(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return 'folder';
    }
    return normalized.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _buildHtmlDocument(String rawHtml) {
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body {
        margin: 0;
        padding: 10px 4px;
        color: ${context.bnbuTheme.textPrimary.cssRgb};
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
        font-size: 16px;
        line-height: 1.5;
        background: ${context.bnbuTheme.canvas.cssRgb};
      }
      img, video, iframe {
        max-width: 100%;
        height: auto;
      }
      table {
        width: 100%;
        max-width: 100%;
        border-collapse: collapse;
      }
      a {
        color: ${context.bnbuTheme.brandBlue.cssRgb};
      }
      pre, code {
        white-space: pre-wrap;
      }
    </style>
  </head>
  <body>$rawHtml</body>
</html>
''';
  }
}
