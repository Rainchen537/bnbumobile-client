import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../services/native_actions.dart';
import '../services/course_archive_export_service.dart';
import '../services/desktop_download_service.dart';
import '../theme/app_theme.dart';
import '../widgets/file_preview_frame.dart';
import '../widgets/bnbu_notice.dart';

Future<void> showFilePreview(
  BuildContext context, {
  required String path,
  required String title,
  required String mimeType,
  NativeActions nativeActions = const NativeActions(),
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => FilePreviewPage(
      path: path,
      title: title,
      mimeType: mimeType,
      nativeActions: nativeActions,
    ),
  ),
);

Future<void> saveOrSharePreview(
  BuildContext context, {
  required String path,
  required String title,
  required String mimeType,
  NativeActions nativeActions = const NativeActions(),
}) async {
  final suffix =
      RegExp(r'\.[a-zA-Z0-9]{1,12}$').firstMatch(path)?.group(0) ?? '';
  final extension = suffix.isEmpty ? '' : suffix.substring(1);
  final fileName =
      RegExp(r'\.[a-zA-Z0-9]{1,12}$').hasMatch(title) || suffix.isEmpty
      ? title
      : '$title$suffix';
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    await nativeActions.shareLocalFile(
      path: path,
      filename: fileName,
      mimeType: mimeType,
    );
  } else {
    await const CourseArchiveExportService().export(
      sourcePath: path,
      fileName: fileName,
      dialogTitle: context.l10n.text('保存文件'),
      isActive: () => context.mounted,
      allowedExtensions: extension.isEmpty ? [] : [extension],
    );
  }
}

class FilePreviewPage extends StatefulWidget {
  const FilePreviewPage({
    super.key,
    required this.path,
    required this.title,
    required this.mimeType,
    this.nativeActions = const NativeActions(),
    this.desktopDownload = false,
    this.isActive,
  });
  final String path, title, mimeType;
  final NativeActions nativeActions;
  final bool desktopDownload;
  final bool Function()? isActive;
  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  bool _sharing = false;
  late final bool _exists = File(widget.path).existsSync();
  late final Future<bool> _nativePreview = widget.nativeActions.canPreviewFile(
    widget.path,
  );
  late final Future<String> _text = _loadText();
  Future<String> _loadText() async {
    final file = File(widget.path);
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('Text preview exceeds limit');
    }
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      if (widget.desktopDownload && DesktopDownloadService.supported) {
        final path = await const DesktopDownloadService().save(
          sourcePath: widget.path,
          fileName: File(widget.path).uri.pathSegments.last,
          isActive: () => mounted && (widget.isActive?.call() ?? true),
        );
        if (mounted && path != null) {
          BnbuToast.show(context, context.l10n.text('文件已保存到下载位置'));
        }
        return;
      }
      await saveOrSharePreview(
        context,
        path: widget.path,
        title: widget.title,
        mimeType: widget.mimeType,
        nativeActions: widget.nativeActions,
      );
    } catch (_) {
      if (mounted) {
        BnbuToast.show(
          context,
          context.l10n.text('文件操作未完成，请重试。'),
          kind: BnbuToastKind.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _fallback() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BnbuText('此文件暂不支持内嵌预览'),
        TextButton(
          onPressed: _sharing ? null : _share,
          child: const BnbuText('保存或分享'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await widget.nativeActions.openFile(
                path: widget.path,
                mimeType: widget.mimeType,
              );
            } catch (_) {
              if (mounted) {
                BnbuToast.show(context, context.l10n.text('无法打开这个文件。'));
              }
            }
          },
          child: const BnbuText('用其他应用打开'),
        ),
      ],
    ),
  );
  Widget _content() {
    final ext =
        (widget.desktopDownload
                ? widget.path
                : widget.title.contains('.')
                ? widget.title
                : widget.path)
            .split('.')
            .last
            .toLowerCase();
    if (widget.mimeType == 'application/pdf' || ext == 'pdf') {
      return PdfViewer.file(
        widget.path,
        params: PdfViewerParams(
          margin: FilePreviewMetrics.margin,
          normalizeMatrix: normalizeFilePreviewMatrix,
          backgroundColor: context.bnbuTheme.canvas,
          errorBannerBuilder: (_, __, ___, ____) => _fallback(),
        ),
      );
    }
    if (widget.mimeType.startsWith('image/') ||
        ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext)) {
      return LayoutBuilder(
        builder: (context, c) => InteractiveViewer(
          minScale: 1,
          maxScale: 8,
          child: Image.file(
            File(widget.path),
            fit: BoxFit.contain,
            width: c.maxWidth,
            height: c.maxHeight,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        ),
      );
    }
    if ([
      'txt',
      'md',
      'csv',
      'json',
      'log',
      'xml',
      'yaml',
      'yml',
    ].contains(ext)) {
      return FutureBuilder<String>(
        future: _text,
        builder: (context, s) => s.hasError
            ? _fallback()
            : s.hasData
            ? SelectionArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Text(s.data!),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return FutureBuilder<bool>(
        future: _nativePreview,
        builder: (context, s) => s.data == true
            ? UiKitView(
                viewType: 'ispace/file_preview',
                creationParams: {'path': widget.path},
                creationParamsCodec: const StandardMessageCodec(),
              )
            : s.connectionState == ConnectionState.done
            ? _fallback()
            : const Center(child: CircularProgressIndicator()),
      );
    }
    return _fallback();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.bnbuTheme.canvas,
    appBar: FilePreviewAppBar(title: widget.title, onShare: _share),
    body: SafeArea(
      top: false,
      child: _exists
          ? _content()
          : const Center(child: BnbuText('本机文件不可用，请返回重新下载。')),
    ),
  );
}
