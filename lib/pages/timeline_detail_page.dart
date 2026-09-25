import '../widgets/ispace_content_padding.dart';
import '../widgets/bnbu_menu.dart';
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../theme/app_theme.dart';

import '../models/assistant_models.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/assignment_file_selection.dart';
import '../services/moodle_api_client.dart';
import '../state/app_session_controller.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/assignment_file_drop_zone.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/bnbu_creation_form.dart';
import '../widgets/bnbu_notice.dart';
import 'web_mirror_page.dart';

class TimelineDetailPage extends StatefulWidget {
  const TimelineDetailPage({
    super.key,
    required this.controller,
    required this.item,
    this.initialDetail,
    this.initialOnlineTextDraft = '',
    this.onAssignmentOutcome,
    this.initialFileUploadIntent = false,
    this.initialUploadFiles = const [],
  });

  final AppSessionController controller;
  final TimelineItem item;
  final TimelineDetailData? initialDetail;
  final String initialOnlineTextDraft;
  final ValueChanged<String>? onAssignmentOutcome;
  final bool initialFileUploadIntent;
  final List<UploadFilePayload> initialUploadFiles;

  @override
  State<TimelineDetailPage> createState() => _TimelineDetailPageState();
}

class _TimelineDetailPageState extends State<TimelineDetailPage> {
  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;

  TimelineDetailData? _detail;
  bool _loading = true;
  bool _submittingText = false;
  bool _submittingFiles = false;
  bool _finalizingAssignment = false;
  String? _error;
  late final AssignmentFileSelection _fileSelection;
  AppSessionLease? _filePageLease;
  bool _selectingFiles = false;
  int _selectionEpoch = 0;
  List<UploadFilePayload> get _pickedFiles => _fileSelection.files;
  bool get _assignmentBusy =>
      _loading ||
      _selectingFiles ||
      _submittingFiles ||
      _submittingText ||
      _finalizingAssignment;
  bool get _canSelectFiles =>
      !_assignmentBusy &&
      _detail?.assignmentId != 0 &&
      _detail?.supportsFileSubmission == true &&
      _detail?.canEditSubmission == true &&
      _filePageLease?.isActive == true;
  late bool _pendingInitialFileUpload;

  @override
  void initState() {
    super.initState();
    _fileSelection = AssignmentFileSelection(
      initialFiles: widget.initialUploadFiles,
    );
    _filePageLease = widget.controller.captureSessionLease();
    widget.controller.addListener(_checkFileSession);
    _pendingInitialFileUpload =
        widget.initialFileUploadIntent && _pickedFiles.isEmpty;
    final initialDetail = widget.initialDetail;
    if (initialDetail != null && !widget.initialFileUploadIntent) {
      _detail = initialDetail;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = AssistantContextScope.maybeOf(context);
    if (coordinator == null || identical(coordinator, _contextCoordinator)) {
      return;
    }
    _contextRegistration?.dispose();
    _contextCoordinator = coordinator;
    _contextRegistration = coordinator.register(
      AssistantContextContribution(
        currentPage: () => AssistantCurrentPageContext(
          pageType: 'assignment',
          title: widget.item.title,
          selectedItemId: widget.item.id.toString(),
          summary: widget.item.courseName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_checkFileSession);
    _fileSelection.dispose();
    _contextRegistration?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _selectionEpoch++;
    setState(() {
      _loading = true;
      _error = null;
      _fileSelection.clear();
    });
    try {
      final detail = await widget.controller.loadTimelineDetail(widget.item);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
      });
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '详情加载失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _scheduleInitialFileUpload();
      }
    }
  }

  void _scheduleInitialFileUpload() {
    if (!_pendingInitialFileUpload) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_handleInitialFileUpload());
    });
  }

  Future<void> _handleInitialFileUpload() async {
    if (!_pendingInitialFileUpload) return;
    _pendingInitialFileUpload = false;
    final detail = _detail;
    if (detail == null ||
        detail.type != TimelineDetailType.assignment ||
        detail.assignmentId <= 0 ||
        !detail.canEditSubmission ||
        !detail.supportsFileSubmission) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: BnbuText('该作业当前不支持文件提交。')));
      }
      return;
    }
    await _pickFiles();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final useMirrorLayout = detail != null && _shouldRenderMirror(detail);
    return Scaffold(
      backgroundColor: context.bnbuTheme.canvas,
      appBar: BnbuSecondaryAppBar(
        bar: AppBar(
          title: BnbuText(
            _pageTitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              onPressed: _assignmentBusy ? null : _load,
              icon: const Icon(LucideIcons.refreshCw300),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: useMirrorLayout
            ? _loading
                  ? const Center(child: BnbuActivityIndicator())
                  : _error != null
                  ? _buildError(context)
                  : _buildContent(context)
            : BnbuConstrainedContent(
                maxWidth: BnbuBreakpoints.contentMax,
                child: IspaceContentPadding(
                  top: 16,
                  bottom: 16,
                  child: _loading
                      ? const Center(child: BnbuActivityIndicator())
                      : _error != null
                      ? _buildError(context)
                      : _buildContent(context),
                ),
              ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BnbuText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _load, child: const BnbuText('重试')),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final detail = _detail!;
    if (_shouldRenderMirror(detail)) {
      return MirrorWebViewPanel(
        controller: widget.controller,
        pathOrUrl: detail.item.url,
      );
    }

    return ListView(
      children: [
        if (detail.type == TimelineDetailType.assignment)
          _buildAssignmentCard(context, detail)
        else if (detail.type == TimelineDetailType.forum)
          _buildForumCard(context, detail)
        else if (detail.type == TimelineDetailType.mediasite)
          _buildMediaSiteCard(context, detail)
        else
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BnbuText(
                  '暂不支持原生详情',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                const BnbuText('该事件当前没有可用的原生详情数据。'),
                if (detail.hints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final hint in detail.hints) BnbuText('• $hint'),
                ],
              ],
            ),
          ),
      ],
    );
  }

  bool _shouldRenderMirror(TimelineDetailData detail) {
    return detail.type == TimelineDetailType.generic &&
        detail.item.url.trim().isNotEmpty;
  }

  String _pageTitle() {
    final preferred = _detail?.item.title.trim() ?? '';
    final fallback = widget.item.title.trim();
    final resolved = preferred.isEmpty ? fallback : preferred;
    if (resolved.isEmpty) {
      return 'Timeline';
    }
    return resolved;
  }

  Widget _buildAssignmentCard(BuildContext context, TimelineDetailData detail) {
    final overviewCard = _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            '作业',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          _kv(
            '作业名',
            detail.assignmentName.isEmpty
                ? detail.item.title
                : detail.assignmentName,
          ),
          _kv(
            '开始时间',
            detail.openDate == null
                ? '未提供'
                : context.l10n.formatFullDateTime(detail.openDate!.toLocal()),
          ),
          _kv(
            '截止时间',
            detail.dueDate == null
                ? '未提供'
                : context.l10n.formatFullDateTime(detail.dueDate!.toLocal()),
          ),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final times = widget.controller.deadlineReminderTimesFor(
                detail.item,
              );
              if (!widget.controller.isDeadlineReminderEnabled) {
                return _kv('DDL 提醒', '已关闭');
              }
              if (times.isEmpty) {
                return _kv('DDL 提醒', '暂无待发送提醒');
              }
              return _kv(
                'DDL 提醒',
                times
                    .map(context.l10n.formatMonthDayTime)
                    .join(context.l10n.isEnglish ? ', ' : '、'),
              );
            },
          ),
          _kv(
            context.l10n.isEnglish ? 'Submission closes' : '最晚提交',
            detail.cutoffDate == null
                ? '未提供'
                : context.l10n.formatFullDateTime(detail.cutoffDate!.toLocal()),
          ),
          _kv(
            context.l10n.isEnglish ? 'Grading due' : '评分截止',
            detail.gradingDueDate == null
                ? '未提供'
                : context.l10n.formatFullDateTime(
                    detail.gradingDueDate!.toLocal(),
                  ),
          ),
          if (detail.assignmentIntroHtml.isNotEmpty ||
              detail.assignmentIntro.isNotEmpty ||
              detail.assignmentIntroFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            _assignmentInstructionBox(detail),
          ],
        ],
      ),
    );
    final submissionCard = _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusGrid(detail),
          if (detail.hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final hint in detail.hints)
              BnbuText(
                '• $hint',
                style: TextStyle(color: context.bnbuTheme.textMuted),
              ),
          ],
          const SizedBox(height: 12),
          if (detail.supportsFileSubmission)
            _buildFileSubmissionBox(context, detail)
          else
            const BnbuText('当前作业未开放文件提交。'),
          const SizedBox(height: 12),
          if (detail.supportsOnlineTextSubmission)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: (_submittingText || detail.assignmentId <= 0)
                    ? null
                    : () => _openSubmissionDialog(
                        detail,
                        initialText: widget.initialOnlineTextDraft,
                      ),
                child: _submittingText
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: BnbuActivityIndicator(),
                      )
                    : BnbuText(detail.submissionDrafts ? '保存在线文本草稿' : '在线文本提交'),
              ),
            ),
          if (detail.submissionDrafts && detail.canFinalizeSubmission) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _finalizingAssignment || _submittingText || _submittingFiles
                    ? null
                    : () => _confirmFinalizeAssignment(detail),
                icon: _finalizingAssignment
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: BnbuActivityIndicator(),
                      )
                    : const Icon(LucideIcons.send300),
                label: const BnbuText('最终提交作业'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          BnbuText(
            detail.canEditSubmission ? '当前作业允许编辑提交' : '当前作业可能不允许编辑提交',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.bnbuTheme.textMuted),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < BnbuBreakpoints.tabletWorkspace) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              overviewCard,
              const SizedBox(height: 12),
              submissionCard,
            ],
          );
        }
        return Row(
          key: const ValueKey('timeline-assignment-tablet-split-layout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: overviewCard),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: submissionCard),
          ],
        );
      },
    );
  }

  Widget _buildForumCard(BuildContext context, TimelineDetailData detail) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            '论坛',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          _kv(
            '名称',
            detail.forumName.isEmpty ? detail.item.title : detail.forumName,
          ),
          if (detail.forumDescription.isNotEmpty)
            _kv('简介', detail.forumDescription),
          _kv('讨论权限', detail.canStartDiscussion ? '可发起讨论' : '当前不可发起讨论'),
          if (detail.forumDiscussions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const BnbuText(
              '最新讨论',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 6),
            for (final discussion in detail.forumDiscussions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _forumDiscussionTile(context, discussion),
              ),
          ] else ...[
            const SizedBox(height: 6),
            const BnbuText('暂无可见讨论帖子。'),
          ],
          if (detail.hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final hint in detail.hints)
              BnbuText(
                '• $hint',
                style: TextStyle(color: context.bnbuTheme.textMuted),
              ),
          ],
        ],
      ),
    );
  }

  Widget _forumDiscussionTile(
    BuildContext context,
    ForumDiscussion discussion,
  ) {
    final badges = <String>[
      if (discussion.pinned) 'Pinned',
      if (discussion.locked) 'Locked',
      '回复 ${discussion.replyCount}',
    ];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: Material(
        color: context.bnbuTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openForumDiscussion(context, discussion),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BnbuText(
                  discussion.subject,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                BnbuText(
                  '${discussion.author} · ${discussion.timeModifiedAt == null ? '未知时间' : context.l10n.formatFullDateTime(discussion.timeModifiedAt!.toLocal())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.bnbuTheme.textMuted,
                  ),
                ),
                if (discussion.messagePreview.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  BnbuText(
                    discussion.messagePreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.bnbuTheme.textPrimary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: BnbuText(
                        badges.join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.bnbuTheme.brandBlue,
                        ),
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight300, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSiteCard(BuildContext context, TimelineDetailData detail) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            'Mediasite',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          _kv('活动名', detail.item.title),
          _kv(
            '模块类型',
            detail.item.moduleName.isEmpty
                ? 'mediasite'
                : detail.item.moduleName,
          ),
          if (detail.mediasiteLaunchUrl.isNotEmpty)
            _kv('入口 URL', detail.mediasiteLaunchUrl),
          if (detail.item.activityState.isNotEmpty)
            _kv('状态', detail.item.activityState),
          if (detail.mediasiteLaunchUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copyText(
                detail.mediasiteLaunchUrl,
                successMessage: 'Mediasite 链接已复制',
              ),
              icon: const Icon(LucideIcons.copy300),
              label: const BnbuText('复制 Mediasite 链接'),
            ),
          ],
          if (detail.hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final hint in detail.hints)
              BnbuText(
                '• $hint',
                style: TextStyle(color: context.bnbuTheme.textMuted),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statusGrid(TimelineDetailData detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: context.bnbuTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _statusLine(
            '提交状态',
            _displaySubmissionStatus(detail.submissionStatus),
          ),
          _statusLine('评分状态', _displayGradingStatus(detail.gradingStatus)),
          _statusLine(
            '反馈',
            detail.feedbackSummary.isEmpty ? '暂无' : detail.feedbackSummary,
          ),
        ],
      ),
    );
  }

  Widget _assignmentInstructionBox(TimelineDetailData detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: context.bnbuTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.assignmentIntroHtml.isNotEmpty)
            _assignmentIntroHtmlPanel(detail.assignmentIntroHtml)
          else if (detail.assignmentIntro.isNotEmpty)
            BnbuText(
              detail.assignmentIntro,
              style: TextStyle(
                color: context.bnbuTheme.textPrimary,
                height: 1.35,
                fontSize: 14,
              ),
            ),
          if (detail.assignmentIntroFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            BnbuText(
              '说明附件',
              style: TextStyle(
                fontSize: 12,
                color: context.bnbuTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            for (final file in detail.assignmentIntroFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: context.bnbuTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: file.fileUrl.trim().isEmpty
                        ? null
                        : () => _openWebResource(
                            title: file.fileName,
                            pathOrUrl: file.fileUrl,
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.paperclip300, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: BnbuText(
                              file.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (file.fileSize > 0)
                            BnbuText(
                              _formatBytes(file.fileSize),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.bnbuTheme.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _assignmentIntroHtmlPanel(String introHtml) {
    final html = _buildIntroHtmlDocument(introHtml);
    return SizedBox(
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: MirrorWebViewPanel.html(
          controller: widget.controller,
          htmlContent: html,
        ),
      ),
    );
  }

  String _buildIntroHtmlDocument(String rawHtml) {
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

  Widget _statusLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: BnbuText(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: BnbuText(value)),
        ],
      ),
    );
  }

  String _displaySubmissionStatus(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case '':
        return '未知';
      case 'new':
      case 'notsubmitted':
      case 'noattempt':
        return '未提交';
      case 'submitted':
        return '已提交';
      case 'draft':
        return '草稿';
      case 'reopened':
        return '已重新开启';
      default:
        return value.trim();
    }
  }

  String _displayGradingStatus(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case '':
        return '未知';
      case 'notgraded':
        return '未评分';
      case 'graded':
        return '已评分';
      case 'grading':
      case 'inmarking':
        return '评分中';
      default:
        return value.trim();
    }
  }

  Widget _buildFileSubmissionBox(
    BuildContext context,
    TimelineDetailData detail,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: context.bnbuTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            context.l10n.isEnglish ? 'File submissions' : '文件提交',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: context.bnbuTheme.brandBlue,
            ),
          ),
          const SizedBox(height: 6),
          BnbuText(
            '最大文件数：${detail.maxFileSubmissions <= 0 ? '未限制' : detail.maxFileSubmissions}，单文件大小：${_formatBytes(detail.maxSubmissionSizeBytes)}',
            style: TextStyle(
              fontSize: 12,
              color: context.bnbuTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          AssignmentFileDropZone(
            enabled: _canSelectFiles,
            onFiles: (files) => unawaited(_dropFiles(files)),
            onPickFiles: () => unawaited(_pickFiles()),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (!AssignmentFileDropZone.supportsNativeDrop) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _canSelectFiles ? _pickFiles : null,
                          icon: const Icon(LucideIcons.paperclip300),
                          label: const BnbuText('选择文件'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            _assignmentBusy ||
                                detail.assignmentId <= 0 ||
                                _pickedFiles.isEmpty ||
                                !detail.canEditSubmission ||
                                _filePageLease?.isActive != true
                            ? null
                            : () => _submitFiles(detail),
                        child: _submittingFiles
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: BnbuActivityIndicator(),
                              )
                            : BnbuText(
                                detail.submissionDrafts ? '保存文件草稿' : '提交文件',
                              ),
                      ),
                    ),
                  ],
                ),
                if (_selectingFiles) const LinearProgressIndicator(),
                if (_pickedFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final file in _pickedFiles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.file, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(file.fileName)),
                          IconButton(
                            tooltip: context.l10n.text('移除文件'),
                            onPressed: _assignmentBusy
                                ? null
                                : () {
                                    setState(() => _fileSelection.remove(file));
                                  },
                            icon: const Icon(LucideIcons.x, size: 18),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (detail.submissionFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            const BnbuText(
              '已提交文件',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            for (final file in detail.submissionFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: BnbuText(
                  '• ${file.fileName} (${_formatBytes(file.fileSize)})',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    await _selectFiles(() async {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: FileType.any,
      );
      return (
        files:
            result?.files
                .map(
                  (file) => UploadFilePayload(
                    fileName: file.name,
                    filePath: file.path,
                    bytes: file.bytes,
                  ),
                )
                .toList() ??
            <UploadFilePayload>[],
        bookmarks: <UploadFilePayload, Uint8List>{},
      );
    });
  }

  void _checkFileSession() {
    if (_filePageLease?.isActive == true) return;
    _selectionEpoch++;
    _fileSelection.clear();
    if (mounted) setState(() {});
  }

  Future<void> _dropFiles(List<DropItem> dropped) async {
    await _selectFiles(() async {
      if (dropped.any((file) => file is DropItemDirectory)) {
        throw const AssignmentFileSelectionException('请添加文件，不支持文件夹或快捷方式。');
      }
      final files = <UploadFilePayload>[];
      final bookmarks = <UploadFilePayload, Uint8List>{};
      for (final file in dropped) {
        final payload = UploadFilePayload(
          fileName: file.name,
          filePath: file.path,
        );
        files.add(payload);
        final bookmark = file.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          bookmarks[payload] = bookmark;
        }
      }
      return (files: files, bookmarks: bookmarks);
    });
  }

  Future<void> _selectFiles(
    Future<
      ({
        List<UploadFilePayload> files,
        Map<UploadFilePayload, Uint8List> bookmarks,
      })
    >
    Function()
    acquire,
  ) async {
    if (!_canSelectFiles || !(ModalRoute.isCurrentOf(context) ?? true)) return;
    final epoch = ++_selectionEpoch;
    final detail = _detail!;
    bool current() =>
        mounted &&
        epoch == _selectionEpoch &&
        _filePageLease?.isActive == true &&
        identical(_detail, detail);
    setState(() => _selectingFiles = true);
    try {
      final selection = await acquire();
      if (!current()) return;
      await _fileSelection.add(
        selection.files,
        maxFiles: detail.maxFileSubmissions,
        maxBytes: detail.maxSubmissionSizeBytes,
        isCurrent: current,
        bookmarks: selection.bookmarks,
      );
    } catch (error) {
      if (!mounted || !current()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: BnbuText(
            error is AssignmentFileSelectionException
                ? error.message
                : '选择的文件不可读取，请重试。',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _selectingFiles = false);
    }
  }

  Future<void> _submitFiles(TimelineDetailData detail) async {
    if (!_canSelectFiles || _pickedFiles.isEmpty) return;
    setState(() {
      _submittingFiles = true;
    });
    try {
      final outcome = await widget.controller.submitAssignmentFiles(
        assignmentId: detail.assignmentId,
        files: _pickedFiles,
      );
      if (!mounted) {
        return;
      }
      widget.onAssignmentOutcome?.call(
        outcome.finalSubmitted
            ? 'assignment_submitted'
            : outcome.draftSaved
            ? 'assignment_draft_saved'
            : 'assignment_updated',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: BnbuText(_assignmentOutcomeMessage(outcome))),
      );
      await _load();
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText('提交失败：${error.message}')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('提交失败，请稍后重试。')));
    } finally {
      if (mounted) {
        setState(() {
          _submittingFiles = false;
        });
      }
    }
  }

  Future<void> _openSubmissionDialog(
    TimelineDetailData detail, {
    String initialText = '',
  }) async {
    final result = await showBnbuCreationModal<String>(
      context: context,
      semanticLabel: context.l10n.text(
        detail.submissionDrafts ? '保存在线文本草稿' : '在线文本提交',
      ),
      contentKey: const ValueKey('assignment-online-text-editor'),
      builder: (context, presentation) => BnbuTextCreationEditor(
        title: detail.submissionDrafts ? '保存在线文本草稿' : '在线文本提交',
        avoidKeyboard: !presentation.isDialog,
        actionLabel: detail.submissionDrafts ? '保存草稿' : '提交',
        hint: '输入你的作业文本内容',
        initialText: initialText,
        minLines: 6,
        maxLines: 12,
      ),
    );
    final text = result?.trim() ?? '';
    if (!mounted || text.isEmpty) return;

    setState(() {
      _submittingText = true;
    });
    try {
      final outcome = await widget.controller.submitAssignmentOnlineText(
        assignmentId: detail.assignmentId,
        text: text,
      );
      if (!mounted) {
        return;
      }
      widget.onAssignmentOutcome?.call(
        outcome.finalSubmitted
            ? 'assignment_submitted'
            : outcome.draftSaved
            ? 'assignment_draft_saved'
            : 'assignment_updated',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: BnbuText(_assignmentOutcomeMessage(outcome))),
      );
      await _load();
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText('提交失败：${error.message}')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('提交失败，请稍后重试。')));
    } finally {
      if (mounted) {
        setState(() {
          _submittingText = false;
        });
      }
    }
  }

  String _assignmentOutcomeMessage(AssignmentSubmissionOutcome outcome) {
    if (outcome.finalSubmitted) return '作业已提交';
    if (outcome.draftSaved) return '草稿已保存，尚未最终提交';
    return 'iSpace 已接受作业更新';
  }

  Future<void> _confirmFinalizeAssignment(TimelineDetailData detail) async {
    var acceptedStatement = !detail.requiresSubmissionStatement;
    var confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const BnbuText('最终提交作业'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BnbuText('提交后将进入评分流程'),
                  if (detail.requiresSubmissionStatement) ...[
                    const SizedBox(height: 12),
                    BnbuCheckTile(
                      value: acceptedStatement,
                      onChanged: (value) {
                        setDialogState(() {
                          acceptedStatement = value == true;
                        });
                      },
                      title: BnbuText(
                        detail.submissionStatement.trim().isNotEmpty
                            ? detail.submissionStatement.trim()
                            : '接受 iSpace 作业提交声明',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const BnbuText('取消'),
                ),
                FilledButton(
                  onPressed: acceptedStatement
                      ? () {
                          confirmed = true;
                          Navigator.of(dialogContext).pop();
                        }
                      : null,
                  child: const BnbuText('最终提交'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _finalizingAssignment = true;
    });
    try {
      final outcome = await widget.controller.finalizeAssignment(
        assignmentId: detail.assignmentId,
        acceptSubmissionStatement: acceptedStatement,
      );
      if (!mounted) return;
      widget.onAssignmentOutcome?.call(
        outcome.finalSubmitted
            ? 'assignment_submitted'
            : outcome.draftSaved
            ? 'assignment_draft_saved'
            : 'assignment_updated',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: BnbuText(_assignmentOutcomeMessage(outcome))),
      );
      await _load();
    } on MoodleApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText('最终提交失败：${error.message}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('最终提交失败，请稍后重试。')));
    } finally {
      if (mounted) {
        setState(() {
          _finalizingAssignment = false;
        });
      }
    }
  }

  Future<void> _openForumDiscussion(
    BuildContext context,
    ForumDiscussion discussion,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForumDiscussionPage(
          controller: widget.controller,
          discussion: discussion,
        ),
      ),
    );
  }

  Future<void> _copyText(String value, {required String successMessage}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: BnbuText(successMessage)));
  }

  Future<void> _openWebResource({
    required String title,
    required String pathOrUrl,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebMirrorPage(
          controller: widget.controller,
          title: title.trim().isEmpty ? '资源详情' : title,
          pathOrUrl: pathOrUrl,
          showFileActions: true,
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '未限制';
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

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.bnbuTheme.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: context.bnbuTheme.textPrimary, fontSize: 14),
          children: [
            TextSpan(
              text: '${context.l10n.text(key)}: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class ForumDiscussionPage extends StatefulWidget {
  const ForumDiscussionPage({
    super.key,
    required this.controller,
    required this.discussion,
  });

  final AppSessionController controller;
  final ForumDiscussion discussion;

  @override
  State<ForumDiscussionPage> createState() => ForumDiscussionPageState();
}

class ForumDiscussionPageState extends State<ForumDiscussionPage> {
  bool _loading = true;
  String? _error;
  List<ForumPost> _posts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await widget.controller.loadForumDiscussionPosts(
        widget.discussion.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = posts;
      });
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '讨论内容加载失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bnbuTheme.canvas,
      appBar: BnbuSecondaryAppBar(
        bar: AppBar(
          title: BnbuText(
            widget.discussion.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(LucideIcons.refreshCw300),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: BnbuConstrainedContent(
          maxWidth: 1120,
          child: IspaceContentPadding(
            top: 16,
            bottom: 16,
            child: _loading
                ? const Center(child: BnbuActivityIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BnbuText(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _load,
                          child: const BnbuText('重试'),
                        ),
                      ],
                    ),
                  )
                : _posts.isEmpty
                ? const Center(child: BnbuText('暂无帖子内容'))
                : ListView.separated(
                    itemCount: _posts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: context.bnbuTheme.border.withValues(
                                alpha: 0.5,
                              ),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BnbuText(
                              post.subject.isEmpty
                                  ? widget.discussion.subject
                                  : post.subject,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            BnbuText(
                              '${post.author} · ${post.timeCreatedAt == null ? '未知时间' : context.l10n.formatFullDateTime(post.timeCreatedAt!.toLocal())}',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.bnbuTheme.textMuted,
                              ),
                            ),
                            if (post.isPrivateReply)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: BnbuText(
                                  'Private reply',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.bnbuTheme.warning,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            BnbuText(
                              post.message.isEmpty ? '（无正文）' : post.message,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color: context.bnbuTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
