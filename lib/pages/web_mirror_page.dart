import 'file_preview_page.dart';
import '../widgets/file_preview_frame.dart';
import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';

import '../widgets/bnbu_loading.dart';
import '../config/app_config.dart';
import '../models/assistant_models.dart';
import '../models/web_session_snapshot.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/assistant_history_store.dart';
import '../services/native_actions.dart';
import '../services/desktop_download_service.dart';
import '../services/ispace_desktop_files.dart';
import '../services/study_window_manager.dart';
import '../state/app_session_controller.dart';
import '../state/study_mode_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/native_mirror_webview.dart';

Future<void> downloadIspaceDesktopFile(
  BuildContext context, {
  required AppSessionController controller,
  required String url,
  required String filename,
  required bool Function() isActive,
}) async {
  final lease = controller.captureSessionLease();
  bool active() => context.mounted && isActive() && (lease?.isActive ?? false);
  if (!active()) return;
  BnbuToast.show(context, context.l10n.text('正在下载文件…'));
  try {
    final path = await IspaceDesktopFiles(
      controller,
    ).download(url: url, filename: filename, isActive: active);
    if (!context.mounted || !active()) return;
    if (path == null) {
      BnbuToast.hide(context);
      return;
    }
    BnbuToast.show(
      context,
      '${context.l10n.text('文件已保存到下载位置')}：${File(path).uri.pathSegments.last}',
      kind: BnbuToastKind.success,
      actionLabel: context.l10n.text('打开'),
      onAction: () async {
        if (!active()) return;
        try {
          await const DesktopDownloadService().openSavedFile(path);
        } catch (_) {
          if (context.mounted && active()) {
            BnbuToast.show(context, context.l10n.text('无法打开这个文件。'));
          }
        }
      },
    );
  } catch (_) {
    if (context.mounted && active()) {
      BnbuToast.show(
        context,
        context.l10n.text('文件下载失败，请检查网络和下载位置后重试。'),
        kind: BnbuToastKind.warning,
      );
    }
  }
}

class WebMirrorPage extends StatefulWidget {
  const WebMirrorPage({
    super.key,
    required this.controller,
    required this.title,
    required this.pathOrUrl,
    this.showFileActions = false,
    this.actionPathOrUrl,
    this.studyItems = const [],
    this.additionalActions = const [],
    this.studyDocumentOpener,
  });

  final AppSessionController controller;
  final String title;
  final String pathOrUrl;
  final bool showFileActions;
  final String? actionPathOrUrl;
  final List<String> studyItems;
  final List<Widget> additionalActions;
  final Future<void> Function(AssistantStudyDocument document)?
  studyDocumentOpener;

  @override
  State<WebMirrorPage> createState() => _WebMirrorPageState();
}

class _WebMirrorPageState extends State<WebMirrorPage> {
  late final _pageLease = widget.controller.captureSessionLease();
  static const MethodChannel _nativeActionsChannel = MethodChannel(
    'ispace/native_actions',
  );
  static const NativeActions _nativeActions = NativeActions();
  final GlobalKey<_MirrorWebViewPanelState> _panelKey =
      GlobalKey<_MirrorWebViewPanelState>();
  bool _isSharing = false;
  final Object _studyModeOwner = Object();
  StudyModeController? _studyModeController;
  AssistantContextRegistration? _contextRegistration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _studyModeController ??= AssistantContextScope.maybeStudyModeControllerOf(
      context,
    );
    if (_contextRegistration == null) {
      final coordinator = AssistantContextScope.maybeOf(context);
      _contextRegistration = coordinator?.register(
        AssistantContextContribution(
          currentPage: () => AssistantCurrentPageContext(
            pageType: 'course',
            title: widget.title,
            selectedItemId: _resolvedActionUrl(),
            summary: widget.title,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _studyModeController?.deactivate(_studyModeOwner);
    _contextRegistration?.dispose();
    super.dispose();
  }

  bool get _isLocalFilePreview {
    if (AppConfig.studyModeEnabled) return false;
    if (DesktopDownloadService.supported &&
        Uri.tryParse(_resolvedActionUrl())?.path.contains('/pluginfile.php') ==
            true) {
      return true;
    }
    final value =
        '${widget.title} ${Uri.tryParse(_resolvedActionUrl())?.path ?? ''}'
            .toLowerCase();
    return RegExp(
      r'\.(pdf|png|jpe?g|webp|gif|docx?|pptx?|xlsx?|txt|csv|zip)(?:$|\s)',
    ).hasMatch(value);
  }

  Future<String>? _cachedPreview;
  Future<String> _loadPreviewFile() async {
    final owner = widget.controller.username;
    final lease = _pageLease;
    bool active() =>
        mounted &&
        owner == widget.controller.username &&
        (!DesktopDownloadService.supported || (lease?.isActive ?? false));
    final url = _downloadUrl(_resolvedActionUrl());
    final (cookie, origin) = await _loadCookieHeader(url);
    if (!active()) {
      throw StateError('Preview cancelled');
    }
    final path = await _nativeActions.cachePreviewFile(
      url: url,
      filename: _suggestedFileName(url, widget.title),
      cookieHeader: cookie,
      cookieOrigin: origin,
      isActive: DesktopDownloadService.supported ? active : null,
    );
    if (!active()) {
      await File(path).delete();
      throw StateError('Preview cancelled');
    }
    return path;
  }

  bool get _shouldShowFileActions {
    if (widget.showFileActions) {
      return true;
    }
    final source = '${widget.title} ${_resolvedActionUrl()}'.toLowerCase();
    const fileHints = [
      '.pdf',
      '.ppt',
      '.pptx',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '/pluginfile.php',
    ];
    return fileHints.any(source.contains);
  }

  bool get _supportsStudyMode {
    if (!AppConfig.studyModeEnabled) return false;
    final source = '${widget.title} ${_resolvedActionUrl()}'.toLowerCase();
    return source.contains('.pdf') || source.contains('.pptx');
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.monochrome(Theme.of(context).brightness),
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    if (DesktopDownloadService.supported && _pageLease?.isActive != true) {
      return Scaffold(
        appBar: FilePreviewAppBar(title: widget.title),
        body: const Center(child: BnbuText('登录状态已变化，请重新打开课程页面。')),
      );
    }
    if (_isLocalFilePreview) {
      _cachedPreview ??= _loadPreviewFile();
      return FutureBuilder<String>(
        future: _cachedPreview,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return FilePreviewPage(
              path: snapshot.data!,
              title: widget.title,
              mimeType: 'application/octet-stream',
              desktopDownload: DesktopDownloadService.supported,
              isActive: () => mounted && (_pageLease?.isActive ?? false),
            );
          }
          return Scaffold(
            backgroundColor: context.bnbuTheme.canvas,
            appBar: FilePreviewAppBar(title: widget.title),
            body: Center(
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _cachedPreview = null),
                          child: const BnbuText('文件读取失败，重试'),
                        ),
                        if (DesktopDownloadService.supported)
                          TextButton(
                            onPressed: _isSharing ? null : _shareResource,
                            child: const BnbuText('下载此文件'),
                          ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        },
      );
    }

    final tokens = context.bnbuTheme;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: FilePreviewAppBar(
        title: widget.title,
        onShare: _shouldShowFileActions && !_isSharing ? _shareResource : null,
        onReload: () => _panelKey.currentState?.reload(),
        extraActions: widget.additionalActions,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= BnbuBreakpoints.expandedNavigation &&
              _supportsStudyMode;
          final studyModeController = _studyModeController;
          if (wide && studyModeController != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                studyModeController.activate(_studyModeOwner, _openStudyWindow);
              }
            });
          } else if (studyModeController != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                studyModeController.deactivate(_studyModeOwner);
              }
            });
          }
          return _buildFilePreview();
        },
      ),
    );
  }

  Widget _buildFilePreview() {
    return MirrorWebViewPanel(
      key: _panelKey,
      controller: widget.controller,
      pathOrUrl: _resolvedDisplayUrl(),
    );
  }

  Future<void> _openStudyWindow() async {
    if (!StudyWindowManager.supported && widget.studyDocumentOpener == null) {
      return;
    }
    try {
      final sourceUrl = _studySourceUrl(_downloadUrl(_resolvedActionUrl()));
      final document = AssistantStudyDocument(
        key: sha256.convert(utf8.encode(sourceUrl)).toString(),
        title: widget.title,
        sourceUrl: sourceUrl,
      );
      final opener = widget.studyDocumentOpener;
      if (opener != null) {
        await opener(document);
      } else {
        await StudyWindowManager.open(document);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: BnbuText('学业窗口暂时无法打开，请重试。')));
      }
    }
  }

  String _studySourceUrl(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !uri.hasQuery) return sourceUrl;
    final query = Map<String, String>.from(uri.queryParameters)
      ..removeWhere(
        (key, _) => const {
          'token',
          'wstoken',
          'sesskey',
          'access_token',
        }.contains(key.toLowerCase()),
      );
    return uri
        .replace(queryParameters: query.isEmpty ? null : query)
        .toString();
  }

  Future<void> _shareResource() async {
    if (_isSharing) return;
    final url = _downloadUrl(_resolvedActionUrl());
    if (url.isEmpty) {
      return;
    }
    setState(() => _isSharing = true);
    try {
      final fileName = _suggestedFileName(url, widget.title);
      if (DesktopDownloadService.supported) {
        await downloadIspaceDesktopFile(
          context,
          controller: widget.controller,
          url: url,
          filename: fileName,
          isActive: () => mounted,
        );
        return;
      }
      final (cookieHeader, cookieOrigin) = await _loadCookieHeader(url);
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      await _nativeActionsChannel.invokeMethod('shareFile', {
        'url': url,
        'filename': fileName,
        'title': widget.title,
        if (cookieHeader.isNotEmpty) 'cookieHeader': cookieHeader,
        if (cookieOrigin.isNotEmpty) 'cookieOrigin': cookieOrigin,
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('分享文件失败，请稍后重试。')));
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<(String, String)> _loadCookieHeader(String targetUrl) async {
    try {
      final snapshot = await widget.controller.prepareWebSession();
      if (!urlsHaveSameOrigin(targetUrl, snapshot.baseUrl)) {
        return ('', '');
      }
      final header = snapshot.cookies
          .where((cookie) => cookie.name.trim().isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      return (header, snapshot.baseUrl);
    } catch (_) {
      if (DesktopDownloadService.supported) rethrow;
      return ('', '');
    }
  }

  String _resolvedDisplayUrl() {
    return _resolveUrl(widget.pathOrUrl);
  }

  String _resolvedActionUrl() {
    final custom = widget.actionPathOrUrl?.trim() ?? '';
    if (custom.isNotEmpty) {
      return _resolveUrl(custom);
    }
    return _resolvedDisplayUrl();
  }

  String _resolveUrl(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('about:')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${widget.controller.baseUrl}$trimmed';
    }
    return '${widget.controller.baseUrl}/$trimmed';
  }

  String _downloadUrl(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) {
      return sourceUrl;
    }
    if (!uri.path.contains('/pluginfile.php')) {
      return sourceUrl;
    }
    final query = Map<String, String>.from(uri.queryParameters);
    query.putIfAbsent('forcedownload', () => '1');
    return uri.replace(queryParameters: query).toString();
  }

  String _suggestedFileName(String url, String title) {
    if (RegExp(
      r'\.(pdf|png|jpe?g|gif|webp|docx?|pptx?|xlsx?|txt|csv|zip)$',
      caseSensitive: false,
    ).hasMatch(title.trim())) {
      return title.trim();
    }
    final uri = Uri.tryParse(url);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    final normalizedSegment = Uri.decodeComponent(lastSegment).trim();
    if (normalizedSegment.isNotEmpty && normalizedSegment.contains('.')) {
      return normalizedSegment;
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isNotEmpty && normalizedTitle.contains('.')) {
      return normalizedTitle;
    }
    return '';
  }
}

class MirrorWebViewPanel extends StatefulWidget {
  MirrorWebViewPanel({
    super.key,
    required this.controller,
    required String pathOrUrl,
  }) : content = NativeWebContent.url(pathOrUrl);

  MirrorWebViewPanel.html({
    super.key,
    required this.controller,
    required String htmlContent,
  }) : content = NativeWebContent.html(htmlContent);

  final AppSessionController controller;
  final NativeWebContent content;

  @override
  State<MirrorWebViewPanel> createState() => _MirrorWebViewPanelState();
}

class _MirrorWebViewPanelState extends State<MirrorWebViewPanel> {
  Future<WebSessionSnapshot>? _future;
  final NativeMirrorWebViewController _webViewController =
      NativeMirrorWebViewController();
  int _reloadSeed = 0;
  bool _downloading = false;

  Future<void> _download(String url, String? filename, String? mimeType) async {
    if (_downloading) return;
    _downloading = true;
    try {
      final suggested = filename?.trim().isNotEmpty == true
          ? filename!
          : Uri.tryParse(url)?.pathSegments.lastOrNull ?? 'attachment';
      await downloadIspaceDesktopFile(
        context,
        controller: widget.controller,
        url: url,
        filename: resolvedDownloadFilename(
          suggested: suggested,
          contentType: mimeType ?? '',
        ),
        isActive: () => mounted,
      );
    } finally {
      _downloading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<WebSessionSnapshot> _load() {
    return widget.controller.prepareWebSession();
  }

  Future<void> reload() => _reload();

  Future<String> visibleText() => _webViewController.visibleText();

  Future<void> _reload() async {
    final future = _load();
    setState(() {
      _future = future;
      _reloadSeed++;
    });
    try {
      await future;
    } catch (_) {
      // Rendered in UI.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebSessionSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: BnbuActivityIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          final message = snapshot.error?.toString() ?? '官网页面加载失败';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BnbuText(message, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _reload,
                    child: const BnbuText('重试加载'),
                  ),
                ],
              ),
            ),
          );
        }

        final session = snapshot.data!;
        final content = widget.content.isHtml
            ? widget.content
            : NativeWebContent.url(
                _resolveUrl(session.baseUrl, widget.content.value),
              );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: NativeMirrorWebView(
              key: ValueKey((content, _reloadSeed)),
              content: content,
              session: session,
              controller: _webViewController,
              allowExternalHttpsNavigation: true,
              onHtmlLinkTapped: (url) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WebMirrorPage(
                      controller: widget.controller,
                      title: 'iSpace',
                      pathOrUrl: url,
                    ),
                  ),
                );
              },
              onRetry: _reload,
              onDownloadRequested: DesktopDownloadService.supported
                  ? _download
                  : null,
            ),
          ),
        );
      },
    );
  }

  String _resolveUrl(String baseUrl, String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('about:')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$baseUrl$trimmed';
    }
    return '$baseUrl/$trimmed';
  }
}
