import '../widgets/ispace_content_padding.dart';
import '../widgets/bnbu_adaptive.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../services/ispace_page_content.dart';
import '../services/native_actions.dart';
import '../services/desktop_download_service.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_loading.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/courseware_download_button.dart';
import 'web_mirror_page.dart';

/// The compatibility route name is retained; user content is no longer read
/// through the assistant's lossy plain-text interface.
class IspaceTextPage extends StatefulWidget {
  const IspaceTextPage({
    super.key,
    required this.controller,
    required this.course,
    required this.module,
  });
  final AppSessionController controller;
  final CourseSummary course;
  final CourseModule module;
  @override
  State<IspaceTextPage> createState() => _IspaceTextPageState();
}

class _IspaceTextPageState extends State<IspaceTextPage> {
  late final _lease = widget.controller.captureSessionLease();
  late final Future<IspacePageContent> _content = _load();
  bool _attachments = false;
  String? _downloading;
  bool get _active => mounted && (_lease?.isActive ?? false);
  String get _originalUrl => widget.module.url.isEmpty
      ? '/mod/page/view.php?id=${widget.module.id}'
      : widget.module.url;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (mounted && !_active) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<IspacePageContent> _load() async {
    final html = await widget.controller.loadCoursePageHtml(
      widget.course.id,
      widget.module,
    );
    if (!_active) throw const FormatException('内容暂不可用');
    return IspacePageContent.parse(html, widget.controller.baseUrl);
  }

  Future<void> _open(IspacePageLink link) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => WebMirrorPage(
        controller: widget.controller,
        title: link.title,
        pathOrUrl: link.url,
        showFileActions: link.isFile,
      ),
    ),
  );
  Future<void> _download(IspacePageLink link) async {
    if (!_active || _downloading != null) return;
    setState(() => _downloading = link.url);
    try {
      final current = await widget.controller.loadCoursewareDownloadPlan(
        widget.course.id,
      );
      if (!_active) return;
      if (!current.files.any((f) => f.url == link.url)) {
        throw const FormatException();
      }
      if (DesktopDownloadService.supported) {
        if (!mounted) return;
        await downloadIspaceDesktopFile(
          context,
          controller: widget.controller,
          url: link.url,
          filename: link.fileName,
          isActive: () => _active,
        );
        return;
      }
      final session = await widget.controller.prepareWebSession();
      if (!_active) return;
      if (!urlsHaveSameOrigin(link.url, session.baseUrl)) {
        throw const FormatException();
      }
      final result = await const NativeActions().downloadFile(
        url: link.url,
        filename: safeAttachmentFileName(link.fileName),
        title: link.title,
        cookieHeader: session.cookies
            .map((c) => '${c.name}=${c.value}')
            .join('; '),
        cookieOrigin: session.baseUrl,
      );
      if (mounted && _active) {
        BnbuToast.show(
          context,
          result is String && result.isNotEmpty ? '下载完成' : '已加入下载任务',
        );
      }
    } catch (_) {
      if (mounted && _active) {
        BnbuToast.show(context, '下载未完成，请重试', kind: BnbuToastKind.warning);
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const Scaffold(body: SizedBox.shrink());
    return FutureBuilder<IspacePageContent>(
      future: _content,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: BnbuSecondaryAppBar(
              bar: AppBar(title: BnbuText(widget.module.name)),
            ),
            body: const BnbuInitialLoading(),
          );
        }
        final content = snapshot.data;
        if (content == null || (!content.isFileDirectory && !_attachments)) {
          return WebMirrorPage(
            controller: widget.controller,
            title: widget.module.name,
            pathOrUrl: _originalUrl,
            additionalActions: [
              if (content != null && content.links.any((l) => l.isFile))
                IconButton(
                  tooltip: context.l10n.text('附件'),
                  icon: const Icon(LucideIcons.paperclip300),
                  onPressed: () => setState(() => _attachments = true),
                ),
            ],
          );
        }
        final links = _attachments
            ? content.links.where((l) => l.isFile).toList()
            : content.links;
        return Scaffold(
          appBar: BnbuSecondaryAppBar(
            bar: AppBar(
              title: BnbuText(widget.module.name),
              actions: [
                IconButton(
                  tooltip: context.l10n.text('查看原页面'),
                  icon: const Icon(LucideIcons.externalLink300),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WebMirrorPage(
                        controller: widget.controller,
                        title: widget.module.name,
                        pathOrUrl: _originalUrl,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              BnbuUpdateProgress(active: _downloading != null),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: BnbuBreakpoints.contentMax,
                    ),
                    child: IspaceContentPadding(
                      top: 12,
                      bottom: 12,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: CoursewareDownloadButton(
                              controller: widget.controller,
                              course: widget.course,
                              label: '下载本页文件',
                              fileUrls: links
                                  .where((l) => l.isFile)
                                  .map((l) => l.url)
                                  .toSet(),
                            ),
                          ),
                          if (content.notes.isNotEmpty && !_attachments)
                            SelectableText(content.notes),
                          for (var i = 0; i < links.length; i++) ...[
                            if (links[i].group.isNotEmpty &&
                                (i == 0 ||
                                    links[i].group != links[i - 1].group))
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 20,
                                  bottom: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        links[i].group,
                                        style: TextStyle(
                                          color: context.bnbuTheme.textMuted,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    CoursewareDownloadButton(
                                      controller: widget.controller,
                                      course: widget.course,
                                      label: '下载本组',
                                      fileUrls: links
                                          .where(
                                            (l) =>
                                                l.isFile &&
                                                (l.group == links[i].group ||
                                                    l.group.startsWith(
                                                      '${links[i].group} / ',
                                                    )),
                                          )
                                          .map((l) => l.url)
                                          .toSet(),
                                    ),
                                  ],
                                ),
                              ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                links[i].isFile
                                    ? LucideIcons.file300
                                    : LucideIcons.externalLink300,
                                size: 20,
                              ),
                              title: Text(links[i].title),
                              subtitle:
                                  links[i].isFile &&
                                      links[i].title != links[i].fileName
                                  ? Text(links[i].fileName)
                                  : null,
                              onTap: () => _open(links[i]),
                              trailing: links[i].isFile
                                  ? IconButton(
                                      tooltip: context.l10n.text('下载'),
                                      icon: const Icon(LucideIcons.download300),
                                      onPressed: _downloading != null
                                          ? null
                                          : () => _download(links[i]),
                                    )
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
