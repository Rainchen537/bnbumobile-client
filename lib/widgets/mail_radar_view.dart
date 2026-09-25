import 'bnbu_loading.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'bnbu_menu.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/campus_time.dart';
import '../models/assistant_models.dart';
import '../models/mail_radar_models.dart';
import '../services/mail_radar_rule_store.dart';
import '../services/mail_presentation.dart';
import 'mail_message_row.dart';
import '../models/mail_models.dart';
import '../services/native_actions.dart';
import '../state/ai_assistant_controller.dart';
import '../state/mail_radar_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_notice.dart' hide ScaffoldMessenger;

class MailRadarView extends StatefulWidget {
  const MailRadarView({
    super.key,
    required this.controller,
    this.assistantController,
    required this.onOpenOriginal,
    this.onReply,
    this.onScheduleReminder,
    this.onOpenExternalLink,
    this.onSaveAttachment,
    this.rowBuilder,
    this.itemFilter,
    this.showRangeSelector = true,
    this.onChooseRange,
  }) : _analysisPreview = false;

  /// Preserves the former analysis panel for isolated regression coverage
  /// while its product interaction is being redesigned. App routes use the
  /// default constructor, whose rows open the original message directly.
  @visibleForTesting
  const MailRadarView.analysisPreview({
    super.key,
    required this.controller,
    this.assistantController,
    required this.onOpenOriginal,
    this.onReply,
    this.onScheduleReminder,
    this.onOpenExternalLink,
    this.onSaveAttachment,
    this.rowBuilder,
    this.itemFilter,
    this.showRangeSelector = false,
    this.onChooseRange,
  }) : _analysisPreview = true;

  final MailRadarController controller;
  final bool _analysisPreview;
  final bool showRangeSelector;
  final VoidCallback? onChooseRange;
  final Widget Function(BuildContext, MailRadarItem, VoidCallback)? rowBuilder;
  final bool Function(MailRadarItem)? itemFilter;
  final AiAssistantController? assistantController;
  final Future<void> Function(MailRadarItem item) onOpenOriginal;
  final Future<void> Function(MailMessageDetail detail)? onReply;
  final Future<String?> Function(String title, String body, DateTime at)?
  onScheduleReminder;
  final Future<void> Function(String url)? onOpenExternalLink;
  final Future<void> Function(String name, Uint8List bytes)? onSaveAttachment;

  @override
  State<MailRadarView> createState() => _MailRadarViewState();
}

class _MailRadarMemoryEditor extends StatefulWidget {
  const _MailRadarMemoryEditor({
    required this.presentation,
    required this.initialValue,
  });

  final BnbuAdaptiveModalPresentation presentation;
  final String initialValue;

  @override
  State<_MailRadarMemoryEditor> createState() => _MailRadarMemoryEditorState();
}

class _MailRadarMemoryEditorState extends State<_MailRadarMemoryEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BnbuModalFrame(
      preserveReferenceGeometry: true,
      presentation: widget.presentation,
      title: '编辑记忆候选',
      icon: LucideIcons.brain300,
      bottomBar: Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.of(context).pop(value);
          },
          icon: const Icon(LucideIcons.save300, size: 18),
          label: const BnbuText('保存'),
        ),
      ),
      child: TextField(
        key: const ValueKey('mail-radar-memory-editor'),
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 1000,
        decoration: InputDecoration(labelText: context.l10n.text('记忆内容')),
      ),
    );
  }
}

class _MailRadarViewState extends State<MailRadarView> {
  final Set<String> _savingAttachments = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant MailRadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _formatReceivedAt(DateTime instant) =>
      context.l10n.formatMonthDayTime(toBnbuCampusClock(instant));

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.isLoading && controller.visibleItems.isEmpty) {
      return const Center(child: BnbuActivityIndicator());
    }
    final colors = MailSurfaceColors(context);
    final items = controller.hasConsent
        ? controller.visibleItems
              .where((item) => widget.itemFilter?.call(item) ?? true)
              .toList()
        : <MailRadarItem>[];
    return BnbuLoadingRegion(
      child: ColoredBox(
        color: colors.background,
        child: Column(
          children: [
            BnbuUpdateProgress(
              active:
                  (controller.isScanning || controller.isLoading) &&
                  items.isNotEmpty,
              height: 1,
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: BnbuText(
                  controller.error!,
                  style: TextStyle(color: context.bnbuTheme.danger),
                ),
              ),
            Expanded(
              child: BnbuRefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  key: const ValueKey('mail-radar-scroll'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.isEmpty ? 1 : items.length,
                  itemBuilder: (context, index) {
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: controller.isScanning
                            ? const BnbuInitialLoading()
                            : const Center(child: BnbuText('暂无雷达邮件')),
                      );
                    }
                    final item = items[index];
                    final builder = widget.rowBuilder;
                    if (builder != null) {
                      return builder(context, item, () => _openItem(item));
                    }
                    return MailMessageRow(
                      key: ValueKey('mail-radar-row-${item.key}'),
                      message: item.toSummary(),
                      timeLabel: formatMailListDate(
                        item.receivedAt,
                        now: DateTime.now(),
                        locale: Localizations.localeOf(context).toString(),
                      ),
                      avatarService: null,
                      tags: [
                        if (item.priority == MailRadarPriority.urgent ||
                            item.priority == MailRadarPriority.high)
                          MailRowTag(
                            item.priority.label,
                            const Color(0xFFEC6868),
                          ),
                        MailRowTag(
                          item.analysisPending ? '等待分析' : item.category.label,
                          colors.accent,
                        ),
                      ],
                      subjectColor: item.priority == MailRadarPriority.urgent
                          ? const Color(0xFFEC6868)
                          : null,
                      onTap: () => _openItem(item),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      await widget.controller.refreshOriginalReadStates();
      await widget.controller.retryNow();
    } catch (error) {
      if (mounted) {
        BnbuToast.show(context, error.toString(), kind: BnbuToastKind.warning);
      }
    }
  }

  Widget _memoryCandidateRow(
    BuildContext context,
    MailRadarItem item,
    AssistantMemorySuggestion suggestion,
  ) {
    final tokens = context.bnbuTheme;
    return Padding(
      key: ValueKey('mail-radar-memory-${item.key}-${suggestion.content}'),
      padding: EdgeInsets.fromLTRB(
        tokens.space16,
        tokens.space12,
        tokens.space8,
        tokens.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: BnbuText(suggestion.content)),
          IconButton(
            tooltip: context.l10n.text('保存'),
            onPressed: () =>
                unawaited(_saveMemoryCandidate(item, suggestion, edit: false)),
            icon: const Icon(LucideIcons.save300, size: 18),
          ),
          IconButton(
            tooltip: context.l10n.text('编辑'),
            onPressed: () =>
                unawaited(_saveMemoryCandidate(item, suggestion, edit: true)),
            icon: const Icon(LucideIcons.penLine300, size: 18),
          ),
          IconButton(
            tooltip: context.l10n.text('忽略'),
            onPressed: () => unawaited(
              widget.controller.resolveMemorySuggestion(
                item,
                suggestion,
                status: AssistantMemorySuggestionStatus.dismissed,
              ),
            ),
            icon: const Icon(LucideIcons.x300, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMemoryCandidate(
    MailRadarItem item,
    AssistantMemorySuggestion suggestion, {
    required bool edit,
  }) async {
    final assistantController = widget.assistantController;
    if (assistantController == null) {
      if (mounted) {
        BnbuToast.show(context, '小U记忆暂不可用', kind: BnbuToastKind.danger);
      }
      return;
    }
    var content = suggestion.content;
    if (edit) {
      final edited = await showBnbuAdaptiveModal<String>(
        context: context,
        dialogMaxWidth: 560,
        dialogMaxHeight: 320,
        semanticLabel: context.l10n.text('编辑记忆候选'),
        builder: (context, presentation) => _MailRadarMemoryEditor(
          presentation: presentation,
          initialValue: content,
        ),
      );
      if (edited == null || !mounted) return;
      content = edited;
    }
    await assistantController.addMemory(
      content,
      memoryType: suggestion.memoryType,
      sourceId: suggestion.sourceId,
    );
    final saved = assistantController.memories.any(
      (memory) =>
          !memory.deleted &&
          memory.content.trim().toLowerCase() == content.trim().toLowerCase(),
    );
    if (!saved || !mounted) return;
    await widget.controller.resolveMemorySuggestion(
      item,
      suggestion,
      status: AssistantMemorySuggestionStatus.saved,
      content: content,
    );
    if (mounted) {
      BnbuToast.show(context, '已保存到小U记忆', kind: BnbuToastKind.success);
    }
  }

  Future<void> _openItem(MailRadarItem item) async {
    if (!widget._analysisPreview) {
      try {
        await widget.onOpenOriginal(item);
      } catch (error) {
        if (mounted) {
          BnbuToast.show(
            context,
            error.toString(),
            kind: BnbuToastKind.warning,
          );
        }
      }
      return;
    }
    try {
      await widget.controller.markOpened(item);
    } catch (_) {
      // A local unread-state write must not block access to the mail details.
    }
    if (!mounted) return;
    final needsTranslationRefresh = widget.controller
        .needsDetailTranslationRefresh(item);
    final preparedItem = widget.controller.prepareItemForDetail(item);
    await showBnbuAdaptiveModal<void>(
      context: context,
      dialogMaxWidth: 760,
      dialogMaxHeight: 760,
      semanticLabel: context.l10n.text('邮件雷达详情'),
      contentKey: const ValueKey('mail-radar-detail-modal'),
      builder: (modalContext, presentation) {
        return FutureBuilder<MailRadarItem>(
          future: preparedItem,
          initialData: item,
          builder: (context, snapshot) => _detailFrame(
            context,
            presentation,
            snapshot.data ?? item,
            isPreparingTranslation:
                needsTranslationRefresh &&
                snapshot.connectionState != ConnectionState.done,
            translationFailed: needsTranslationRefresh && snapshot.hasError,
          ),
        );
      },
    );
  }

  Widget _detailFrame(
    BuildContext modalContext,
    BnbuAdaptiveModalPresentation presentation,
    MailRadarItem item, {
    required bool isPreparingTranslation,
    required bool translationFailed,
  }) {
    final tokens = modalContext.bnbuTheme;
    final related = widget.controller.relatedTo(item);
    final newer = related
        .where(
          (other) =>
              item.isStronglyRelated(other) &&
              other.receivedAt.isAfter(item.receivedAt) &&
              !other.analysisPending,
        )
        .firstOrNull;
    return BnbuModalFrame(
      preserveReferenceGeometry: true,
      presentation: presentation,
      title: item.subject.trim().isEmpty ? '无主题邮件' : item.subject,
      icon: LucideIcons.mailOpen300,
      bottomBar: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: tokens.space8,
          runSpacing: tokens.space8,
          alignment: WrapAlignment.end,
          children: [
            BnbuMenuButton<String>(
              tooltip: modalContext.l10n.text('更多'),
              icon: const Icon(LucideIcons.ellipsis300),
              onSelected: (value) => unawaited(
                _reportOperation(switch (value) {
                  'category' => _correctCategory(modalContext, item),
                  'status' => _changeStatus(modalContext, item),
                  'reminder' => _scheduleReminder(modalContext, item),
                  'rules' => _manageRules(modalContext),
                  _ => Future<void>.value(),
                }),
              ),
              itemBuilder: (_) => [
                if (!item.analysisPending)
                  const PopupMenuItem(value: 'status', child: BnbuText('处理状态')),
                if (!item.analysisPending)
                  const PopupMenuItem(
                    value: 'category',
                    child: BnbuText('纠正分类'),
                  ),
                if (!item.analysisPending && widget.onScheduleReminder != null)
                  const PopupMenuItem(
                    value: 'reminder',
                    child: BnbuText('设置提醒'),
                  ),
                const PopupMenuItem(value: 'rules', child: BnbuText('分类规则')),
              ],
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(modalContext);
                await widget.onOpenOriginal(item);
              },
              icon: const Icon(LucideIcons.mailOpen300),
              label: const BnbuText('查看原始邮件'),
            ),
            if (!item.isRecallNotice && widget.onReply != null)
              OutlinedButton.icon(
                key: ValueKey('mail-radar-reply-${item.key}'),
                onPressed: () {
                  Navigator.pop(modalContext);
                  unawaited(_replyToItem(item));
                },
                icon: const Icon(LucideIcons.reply300),
                label: const BnbuText('回复邮件'),
              ),
            if (!item.analysisPending)
              FilledButton.icon(
                onPressed: () async {
                  await widget.controller.setCompleted(item, !item.isResolved);
                  if (modalContext.mounted) Navigator.pop(modalContext);
                },
                icon: Icon(
                  item.completed
                      ? LucideIcons.undo2300
                      : LucideIcons.circleCheckBig300,
                ),
                label: BnbuText(item.completed ? '移回待处理' : '标记完成'),
              ),
          ],
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          BnbuText(item.sender, style: TextStyle(color: tokens.textSecondary)),
          SizedBox(height: tokens.space24),
          if (item.analysisPending)
            _detailBlock(modalContext, '小U状态', '分析尚未完成，将在后台自动重试。')
          else if (item.isRecallNotice)
            BnbuText(
              '发件人已撤回',
              style: Theme.of(modalContext).textTheme.titleLarge,
            )
          else ...[
            if (isPreparingTranslation)
              _detailBlock(modalContext, '翻译', '正在准备邮件翻译…')
            else if (translationFailed)
              _detailBlock(modalContext, '翻译', '暂时无法生成翻译，请稍后重新打开。')
            else if (item.translationZh.isNotEmpty)
              _detailBlock(modalContext, '翻译', item.translationZh),
            _detailBlock(
              modalContext,
              '处理状态',
              modalContext.l10n.text(item.taskStatusAt(DateTime.now()).label),
            ),
            _detailBlock(
              modalContext,
              '读取范围',
              '${modalContext.l10n.text('正文')}: ${_coverageLabel(item.bodyCoverage)}${item.attachmentCoverage.isEmpty ? '' : '\n${item.attachmentCoverage.entries.map((entry) => '${entry.key}：${_coverageLabel(entry.value)}').join('\n')}'}',
            ),
            if (newer != null) ...[
              _detailBlock(
                modalContext,
                '后续更新',
                '${newer.summaryZh}\n${newer.deadlineText}',
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(modalContext);
                  unawaited(_openItem(newer));
                },
                child: const BnbuText('查看最新往来'),
              ),
            ],
            _detailBlock(modalContext, '小U摘要', item.summaryZh),
            if (item.deadlineEvidence.isNotEmpty)
              _detailBlock(modalContext, '时间原文', item.deadlineEvidence),
            if (item.toolUses.isNotEmpty)
              _detailBlock(
                modalContext,
                '调用记录',
                item.toolUses.map(_toolUseLabel).join('\n'),
              ),
            if (item.actionZh.isNotEmpty || item.actionLinks.isNotEmpty)
              _actionBlock(modalContext, item),
            if (item.deadlineText.isNotEmpty)
              _detailBlock(modalContext, '截止时间', item.deadlineText),
            if (item.hasInlineImages) _inlineImages(modalContext, item),
            if (item.attachmentNotes.isNotEmpty)
              _detailBlock(
                modalContext,
                '附件',
                item.attachmentNotes.join('\n\n'),
              ),
            _downloadableAttachments(modalContext, item),
            for (final suggestion in item.memorySuggestions)
              if (suggestion.status == AssistantMemorySuggestionStatus.pending)
                _memoryCandidateRow(modalContext, item, suggestion),
            if (related.isNotEmpty)
              _detailBlock(
                modalContext,
                '关联邮件',
                related
                    .map(
                      (value) =>
                          '${modalContext.l10n.text(item.isStronglyRelated(value) ? '同一邮件往来' : '主题相关')} · ${_formatReceivedAt(value.receivedAt)}  ${value.subject}\n${value.summaryZh}${value.deadlineText.isEmpty ? '' : '\n${value.deadlineText}'}',
                    )
                    .join('\n\n'),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _replyToItem(MailRadarItem item) async {
    final callback = widget.onReply;
    if (callback == null) return;
    try {
      final detail = await widget.controller.loadMessageDetail(item);
      if (!mounted) return;
      await callback(detail);
    } catch (_) {
      if (!mounted) return;
      BnbuToast.show(context, '无法准备回复邮件', kind: BnbuToastKind.danger);
    }
  }

  Widget _actionBlock(BuildContext context, MailRadarItem item) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText('下一步', style: Theme.of(context).textTheme.titleSmall),
          if (item.actionZh.isNotEmpty) ...[
            SizedBox(height: tokens.space8),
            SelectableText(item.actionZh),
          ],
          if (item.actionLinks.isNotEmpty) ...[
            SizedBox(height: tokens.space12),
            Wrap(
              spacing: tokens.space8,
              runSpacing: tokens.space8,
              children: [
                for (final link in item.actionLinks)
                  OutlinedButton.icon(
                    onPressed: () => _confirmExternalLink(item, link),
                    icon: const Icon(LucideIcons.externalLink300, size: 17),
                    label: BnbuText(link.label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmExternalLink(
    MailRadarItem item,
    MailRadarActionLink link,
  ) async {
    Uri uri;
    try {
      uri = await widget.controller.resolveActionLink(item, link);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('邮件中的外部链接已变化，请刷新后重试。')));
      return;
    }
    if (!mounted) return;
    final scheme = uri.scheme.toLowerCase();
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (scheme != 'https' && scheme != 'http')) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('该外部链接无效，无法打开。')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const BnbuText('即将打开外部链接'),
        content: BnbuText(
          '将离开 BNBU.ME 并打开 ${uri.host}。外部网站可能收集访问和填写的信息，请注意隐私安全，不要提交邮箱密码、验证码或其他登录凭据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const BnbuText('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(LucideIcons.externalLink300),
            label: const BnbuText('确认打开'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final opener = widget.onOpenExternalLink;
      if (opener != null) {
        await opener(uri.toString());
      } else {
        await const NativeActions().openExternalUrl(uri.toString());
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('系统无法打开这个外部链接。')));
    }
  }

  Widget _detailBlock(BuildContext context, String title, String value) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(title, style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: tokens.space8),
          SelectableText(value),
        ],
      ),
    );
  }

  Widget _inlineImages(BuildContext context, MailRadarItem item) {
    final tokens = context.bnbuTheme;
    return FutureBuilder<List<MailRadarInlineImage>>(
      future: widget.controller.loadInlineImages(item),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: EdgeInsets.only(bottom: tokens.space16),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 20,
                child: BnbuActivityIndicator(),
              ),
            ),
          );
        }
        final images = snapshot.data ?? const <MailRadarInlineImage>[];
        if (images.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: tokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final image in images) ...[
                if (image.name.trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: tokens.space8),
                    child: BnbuText(
                      image.name,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radius12),
                  child: ColoredBox(
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 440),
                      child: Image.memory(
                        image.bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed:
                        _savingAttachments.contains('${item.key}:${image.name}')
                        ? null
                        : () => _saveAttachment(
                            item: item,
                            name: image.name,
                            bytes: image.bytes,
                          ),
                    icon: const Icon(LucideIcons.download300, size: 17),
                    label: const BnbuText('保存图片'),
                  ),
                ),
                SizedBox(height: tokens.space12),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _downloadableAttachments(BuildContext context, MailRadarItem item) {
    final tokens = context.bnbuTheme;
    return FutureBuilder<List<MailAttachment>>(
      future: widget.controller.loadDownloadableAttachments(item),
      builder: (context, snapshot) {
        final attachments = (snapshot.data ?? const <MailAttachment>[])
            .where((attachment) {
              final isPreviewableImage = looksLikeInlineImageAttachment(
                attachment.name,
                attachment.mimeType,
              );
              return !isPreviewableImage || attachment.size > 20 * 1024 * 1024;
            })
            .toList(growable: false);
        if (attachments.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: tokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BnbuText('保存附件', style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: tokens.space8),
              Wrap(
                spacing: tokens.space8,
                runSpacing: tokens.space8,
                children: [
                  for (final attachment in attachments)
                    OutlinedButton.icon(
                      onPressed:
                          _savingAttachments.contains(
                            '${item.key}:${attachment.partId}',
                          )
                          ? null
                          : () => _downloadAndSaveAttachment(item, attachment),
                      icon: const Icon(LucideIcons.download300, size: 17),
                      label: BnbuText(attachment.name),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadAndSaveAttachment(
    MailRadarItem item,
    MailAttachment attachment,
  ) async {
    final savingKey = '${item.key}:${attachment.partId}';
    setState(() => _savingAttachments.add(savingKey));
    try {
      final bytes = await widget.controller.downloadAttachment(
        item,
        attachment,
      );
      await _saveAttachment(
        item: item,
        name: attachment.name,
        bytes: bytes,
        savingKey: savingKey,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('附件保存失败，请稍后重试。')));
    } finally {
      if (mounted) setState(() => _savingAttachments.remove(savingKey));
    }
  }

  Future<void> _saveAttachment({
    required MailRadarItem item,
    required String name,
    required Uint8List bytes,
    String? savingKey,
  }) async {
    final key = savingKey ?? '${item.key}:$name';
    final managesState = savingKey == null;
    if (managesState) setState(() => _savingAttachments.add(key));
    try {
      final saver = widget.onSaveAttachment;
      if (saver != null) {
        await saver(safeAttachmentFileName(name), bytes);
      } else {
        await FilePicker.platform.saveFile(
          dialogTitle: '保存邮件附件',
          fileName: safeAttachmentFileName(name),
          bytes: bytes,
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('附件保存失败，请稍后重试。')));
    } finally {
      if (managesState && mounted) {
        setState(() => _savingAttachments.remove(key));
      }
    }
  }

  Future<void> _saveRule(MailRadarRule rule) =>
      _reportOperation(widget.controller.saveRule(rule));

  Future<void> _reportOperation(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (mounted) {
        BnbuToast.show(context, '操作未保存，请重试。', kind: BnbuToastKind.danger);
      }
    }
  }

  String _coverageLabel(String status) => context.l10n.text(switch (status) {
    'complete' => '完整读取',
    'partial' => '部分读取',
    'unread' => '未读取',
    _ => '覆盖范围未知',
  });

  Future<void> _scheduleReminder(
    BuildContext parent,
    MailRadarItem item,
  ) async {
    final callback = widget.onScheduleReminder;
    if (callback == null) return;
    final now = DateTime.now();
    final suggested =
        item.deadlineAt?.isAfter(now) == true &&
            item.deadlineAt!.isBefore(now.add(const Duration(days: 365)))
        ? item.deadlineAt!
        : now.add(const Duration(hours: 1));
    final today = toBnbuCampusClock(now);
    final initial = toBnbuCampusClock(suggested);
    final date = await showDatePicker(
      context: parent,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 366)),
      helpText: parent.l10n.text('北京时间'),
    );
    if (date == null || !parent.mounted) return;
    final time = await showTimePicker(
      context: parent,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: parent.l10n.text('北京时间'),
    );
    if (time == null || !parent.mounted) return;
    final at = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 8));
    if (!at.isAfter(DateTime.now())) {
      BnbuToast.show(parent, '请选择未来时间。', kind: BnbuToastKind.warning);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: parent,
      builder: (context) => AlertDialog(
        title: const BnbuText('设置提醒'),
        content: Text(
          '${item.subject}\n${_formatReceivedAt(at)} ${parent.l10n.text('北京时间')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const BnbuText('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !parent.mounted) return;
    final error = await callback(
      item.subject,
      item.actionZh.isEmpty ? item.summaryZh : item.actionZh,
      at,
    );
    if (!parent.mounted) return;
    BnbuToast.show(
      parent,
      error ?? '提醒已设置',
      kind: error == null ? BnbuToastKind.success : BnbuToastKind.danger,
    );
  }

  Future<void> _changeStatus(BuildContext parent, MailRadarItem item) async {
    final selected = await showDialog<MailRadarTaskStatus>(
      context: parent,
      builder: (context) => SimpleDialog(
        title: const BnbuText('处理状态'),
        children: [
          for (final status in MailRadarTaskStatus.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, status),
              child: BnbuText(status.label),
            ),
        ],
      ),
    );
    if (selected == null || !parent.mounted) return;
    DateTime? until;
    if (selected == MailRadarTaskStatus.snoozed) {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: parent,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 366)),
      );
      if (date == null || !parent.mounted) return;
      final time = await showTimePicker(
        context: parent,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );
      if (time == null || !parent.mounted) return;
      until = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (!until.isAfter(DateTime.now())) return;
    }
    await widget.controller.setTaskStatus(item, selected, until: until);
    if (parent.mounted) Navigator.pop(parent);
  }

  Future<void> _manageRules(BuildContext parent) async {
    await showDialog<void>(
      context: parent,
      builder: (context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => AlertDialog(
          title: const BnbuText('分类规则'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.controller.rules.isEmpty) const BnbuText('暂无分类规则'),
                  for (final rule in widget.controller.rules)
                    ListTile(
                      title: Text(rule.sender),
                      onTap: () async {
                        final category = await showDialog<MailRadarCategory>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: const BnbuText('纠正分类'),
                            children: [
                              for (final category in MailRadarCategory.values)
                                SimpleDialogOption(
                                  onPressed: () =>
                                      Navigator.pop(context, category),
                                  child: BnbuText(category.label),
                                ),
                            ],
                          ),
                        );
                        if (category != null) {
                          await _saveRule(
                            MailRadarRule(
                              sender: rule.sender,
                              category: category,
                              enabled: rule.enabled,
                            ),
                          );
                        }
                      },
                      subtitle: BnbuText(rule.category.label),
                      leading: Switch(
                        value: rule.enabled,
                        onChanged: (value) => _saveRule(
                          MailRadarRule(
                            sender: rule.sender,
                            category: rule.category,
                            enabled: value,
                          ),
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: context.l10n.text('删除'),
                        icon: const Icon(LucideIcons.trash2300),
                        onPressed: () => _reportOperation(
                          widget.controller.deleteRule(rule.sender),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const BnbuText('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _correctCategory(
    BuildContext parentContext,
    MailRadarItem item,
  ) async {
    final selected = await showDialog<MailRadarCategory>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const BnbuText('纠正分类'),
        children: [
          for (final category in MailRadarCategory.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, category),
              child: BnbuText(category.label),
            ),
        ],
      ),
    );
    if (selected != null) {
      await widget.controller.correctCategory(item, selected);
      final sender = MailRadarRule.senderAddress(item.sender);
      if (parentContext.mounted && sender.isNotEmpty) {
        final persist = await showDialog<bool>(
          context: parentContext,
          builder: (context) => AlertDialog(
            title: const BnbuText('应用范围'),
            content: Text(sender),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const BnbuText('只改这封'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const BnbuText('同一发件人的新邮件'),
              ),
            ],
          ),
        );
        if (persist == true) {
          await _saveRule(MailRadarRule(sender: sender, category: selected));
        }
      }
      if (parentContext.mounted) Navigator.pop(parentContext);
    }
  }

  String _toolUseLabel(MailRadarToolUse tool) {
    final name = switch (tool.name) {
      'official_directory' => '政教信息',
      'approved_memory' => '已批准记忆',
      _ => tool.name,
    };
    final status = switch (tool.status) {
      'used' => '已使用',
      'empty' => '无匹配',
      'unavailable' => '暂不可用',
      _ => tool.status,
    };
    return '$name · $status';
  }
}
