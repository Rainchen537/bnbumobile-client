import '../state/account_habits.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/bnbu_loading.dart';
import '../services/assistant_history_store.dart';
import '../services/ai_assistant_service.dart';
import '../services/native_actions.dart';
import '../services/study_history_summary.dart';
import '../services/study_mode_skill.dart';
import '../state/ai_assistant_controller.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/safe_assistant_markdown.dart';
import '../widgets/study_document_viewer.dart';

bool isStudyQuestionPending(
  AssistantConversation? conversation, {
  required bool isConversationSending,
}) {
  if (!isConversationSending || conversation == null) return false;
  final latestUserMessage = conversation.messages.reversed
      .where((message) => message.isUser)
      .firstOrNull;
  return latestUserMessage?.studyContext?.type ==
      AssistantStudyEntryType.question;
}

class StudyWorkspaceTabController extends ChangeNotifier {
  StudyWorkspaceTabController(Iterable<AssistantStudyDocument> documents)
    : _documents = List.of(documents) {
    _activeKey = _documents.firstOrNull?.key;
  }

  final List<AssistantStudyDocument> _documents;
  String? _activeKey;

  List<AssistantStudyDocument> get documents => List.unmodifiable(_documents);
  String? get activeKey => _activeKey;

  bool contains(String key) => _documents.any((item) => item.key == key);

  void add(AssistantStudyDocument document, {bool activate = true}) {
    final exists = contains(document.key);
    if (!exists) _documents.add(document);
    final nextActiveKey = activate || _activeKey == null
        ? document.key
        : _activeKey;
    if (exists && nextActiveKey == _activeKey) return;
    _activeKey = nextActiveKey;
    notifyListeners();
  }

  void activate(String key) {
    if (!contains(key) || _activeKey == key) return;
    _activeKey = key;
    notifyListeners();
  }

  void remove(String key) {
    final index = _documents.indexWhere((item) => item.key == key);
    if (index < 0) return;
    final removedActiveDocument = _activeKey == key;
    _documents.removeAt(index);
    if (removedActiveDocument) {
      if (_documents.isEmpty) {
        _activeKey = null;
      } else {
        final nextIndex = index < _documents.length
            ? index
            : _documents.length - 1;
        _activeKey = _documents[nextIndex].key;
      }
    }
    notifyListeners();
  }

  void moveBefore(String sourceKey, String targetKey) {
    final sourceIndex = _documents.indexWhere((item) => item.key == sourceKey);
    final targetIndex = _documents.indexWhere((item) => item.key == targetKey);
    if (sourceIndex < 0 || targetIndex < 0 || sourceIndex == targetIndex) {
      return;
    }
    final document = _documents.removeAt(sourceIndex);
    final insertion = _documents.indexWhere((item) => item.key == targetKey);
    _documents.insert(insertion, document);
    notifyListeners();
  }
}

class StudyWorkspaceView extends StatefulWidget {
  const StudyWorkspaceView({
    super.key,
    required this.sessionController,
    required this.assistantController,
    required this.initialDocument,
    required this.fallback,
    this.tabController,
    this.onExternalTabDrop,
    this.onAllDocumentsClosed,
  });

  final AppSessionController sessionController;
  final AiAssistantController assistantController;
  final AssistantStudyDocument initialDocument;
  final Widget fallback;
  final StudyWorkspaceTabController? tabController;
  final Future<void> Function(AssistantStudyDocument document, Offset offset)?
  onExternalTabDrop;
  final VoidCallback? onAllDocumentsClosed;

  @override
  State<StudyWorkspaceView> createState() => _StudyWorkspaceViewState();
}

class _StudyWorkspaceViewState extends State<StudyWorkspaceView> {
  static const _skill = StudyModeSkill();
  final Map<String, _DocumentRuntime> _runtime = {};
  final Map<String, Future<AssistantStudyDocumentCopy>> _documentCopies = {};
  final Map<String, String> _activeStudyConversationIds = {};
  double _thumbnailWidth = 220;
  double _assistantWidth = 360;
  double _organizationHeight = 196;
  String _organizationPrompt = StudyModeSkill.defaultOrganizationInstruction;
  Timer? _layoutSaveDebounce;
  late final StudyWorkspaceTabController _tabController;
  late final bool _ownsTabController;

  @override
  void initState() {
    super.initState();
    _ownsTabController = widget.tabController == null;
    _tabController =
        widget.tabController ??
        StudyWorkspaceTabController([widget.initialDocument]);
    _tabController.addListener(_handleTabsChanged);
    _tabController.activate(widget.initialDocument.key);
    unawaited(widget.assistantController.initialize());
    unawaited(_restorePreferences());
  }

  @override
  void dispose() {
    _layoutSaveDebounce?.cancel();
    _tabController.removeListener(_handleTabsChanged);
    if (_ownsTabController) _tabController.dispose();
    for (final runtime in _runtime.values) {
      runtime.dispose();
    }
    super.dispose();
  }

  List<AssistantStudyDocument> get _documents => _tabController.documents;

  void _handleTabsChanged() {
    if (!mounted) return;
    final liveKeys = _tabController.documents
        .map((document) => document.key)
        .toSet();
    for (final key
        in _runtime.keys
            .where((key) => !liveKeys.contains(key))
            .toList(growable: false)) {
      final removedRuntime = _runtime.remove(key);
      if (removedRuntime != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          removedRuntime.dispose();
        });
      }
      _documentCopies.remove(key);
      _activeStudyConversationIds.remove(key);
    }
    setState(() {});
  }

  AssistantStudyDocument get _activeDocument {
    final documents = _documents;
    return documents.firstWhere(
      (document) => document.key == _tabController.activeKey,
      orElse: () => documents.first,
    );
  }

  _DocumentRuntime _runtimeFor(AssistantStudyDocument document) =>
      _runtime.putIfAbsent(document.key, _DocumentRuntime.new);

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return AnimatedBuilder(
      animation: widget.assistantController,
      builder: (context, _) {
        final documents = _documents;
        if (documents.isEmpty) return widget.fallback;
        final activeDocument = _activeDocument;
        final activeIndex = documents.indexWhere(
          (document) => document.key == activeDocument.key,
        );
        return Column(
          key: const ValueKey('ispace-study-mode'),
          children: [
            _buildDocumentTabs(context, documents),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: activeIndex,
                      children: [
                        for (final document in documents)
                          KeyedSubtree(
                            key: ValueKey('study-document-${document.key}'),
                            child: _buildDocumentPane(context, document),
                          ),
                      ],
                    ),
                  ),
                  _ResizeDivider(
                    axis: Axis.vertical,
                    onDelta: (delta) => _resizeAssistant(delta),
                  ),
                  SizedBox(
                    width: _assistantWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: tokens.surface),
                      child: _buildAssistant(
                        context,
                        activeDocument,
                        _runtimeFor(activeDocument),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDocumentTabs(
    BuildContext context,
    List<AssistantStudyDocument> documents,
  ) {
    final tokens = context.bnbuTheme;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 6),
              itemCount: documents.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (context, index) {
                final document = documents[index];
                final active = document.key == _tabController.activeKey;
                return DragTarget<AssistantStudyDocument>(
                  onWillAcceptWithDetails: (details) =>
                      details.data.key != document.key,
                  onAcceptWithDetails: (details) =>
                      _tabController.moveBefore(details.data.key, document.key),
                  builder: (context, candidates, _) =>
                      Draggable<AssistantStudyDocument>(
                        data: document,
                        maxSimultaneousDrags: 1,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 168,
                            height: 31,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              border: Border.all(color: tokens.border),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: BnbuText(
                              document.title,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontSize: 10, height: 1.1),
                            ),
                          ),
                        ),
                        childWhenDragging: const SizedBox(width: 80),
                        onDragEnd: (details) {
                          if (!details.wasAccepted) {
                            unawaited(
                              widget.onExternalTabDrop?.call(
                                document,
                                details.offset,
                              ),
                            );
                          }
                        },
                        child: Semantics(
                          selected: active,
                          button: true,
                          label: context.l10n.text(
                            '${document.title}，可拖动合并或拆分窗口',
                          ),
                          child: InkWell(
                            onTap: () => _tabController.activate(document.key),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 182),
                              padding: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                color: active
                                    ? tokens.surfaceMuted
                                    : tokens.surface,
                                border: Border(
                                  bottom: BorderSide(
                                    color: active
                                        ? tokens.textPrimary
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.fileText300, size: 12),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: BnbuText(
                                      document.title,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(fontSize: 10, height: 1.1),
                                    ),
                                  ),
                                  if (documents.length > 1)
                                    _StudyTabIconButton(
                                      tooltip: context.l10n.text('关闭文件'),
                                      onPressed: () =>
                                          _closeDocument(document.key),
                                      icon: LucideIcons.x300,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _StudyTabIconButton(
              tooltip: context.l10n.text('学业记录'),
              onPressed: _showAllStudyFiles,
              icon: LucideIcons.library300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentPane(
    BuildContext context,
    AssistantStudyDocument document,
  ) {
    final runtime = _runtimeFor(document);
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<AssistantStudyDocumentCopy>(
            future: _documentCopies.putIfAbsent(
              document.key,
              () => _prepareDocument(document),
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: Semantics(
                    label: context.l10n.text('正在同步学业文件'),
                    child: const BnbuActivityIndicator(),
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BnbuText(snapshot.error?.toString() ?? '学业文件无法读取'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => setState(() {
                          _documentCopies.remove(document.key);
                        }),
                        icon: const Icon(LucideIcons.refreshCw300, size: 18),
                        label: const BnbuText('重试'),
                      ),
                    ],
                  ),
                );
              }
              final copy = snapshot.data!;
              return StudyDocumentViewer(
                title: document.title,
                bytes: copy.bytes,
                mimeType: copy.mimeType,
                thumbnailWidth: _thumbnailWidth,
                onThumbnailWidthChanged: (delta) => _resizeThumbnails(delta),
                onDocumentReady: (access) => runtime.access = access,
                onPageChanged: (page) {
                  setState(() {
                    runtime.currentPage = page;
                    runtime.organizationError = null;
                    runtime.organizing = false;
                  });
                },
                bottomPanel: _buildOrganization(context, document, runtime),
                fallback: widget.fallback,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOrganization(
    BuildContext context,
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) {
    final tokens = context.bnbuTheme;
    final conversation = _conversationFor(document);
    final conversationPending =
        conversation != null &&
        widget.assistantController.isConversationSending(conversation.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ResizeDivider(
          axis: Axis.horizontal,
          onDelta: (delta) => _resizeOrganization(-delta),
        ),
        Container(
          key: const ValueKey('study-mode-translation-panel'),
          height: _organizationHeight,
          padding: EdgeInsets.fromLTRB(
            tokens.space12,
            tokens.space4,
            tokens.space8,
            tokens.space8,
          ),
          color: tokens.surface,
          child: Column(
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(LucideIcons.notebookTabs300, size: 15),
                          SizedBox(width: tokens.space8),
                          BnbuText(
                            '本页整理',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          if (runtime.currentPage != null) ...[
                            SizedBox(width: tokens.space8),
                            Flexible(
                              child: BnbuText(
                                runtime.currentPage!.pageLabel,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _CompactStudyIconButton(
                      tooltip: context.l10n.text('整理设置'),
                      onPressed: _editOrganizationPrompt,
                      icon: LucideIcons.settings2300,
                    ),
                    SizedBox(width: tokens.space4),
                    _CompactStudyIconButton(
                      tooltip: context.l10n.text(
                        _organizationFor(document, runtime).isEmpty
                            ? '整理本页'
                            : '重新整理本页',
                      ),
                      emphasized: true,
                      onPressed: runtime.organizing || conversationPending
                          ? null
                          : () => _requestOrganization(document, runtime),
                      icon: LucideIcons.sparkles300,
                      loading: runtime.organizing,
                      badgeIcon: _organizationFor(document, runtime).isEmpty
                          ? null
                          : LucideIcons.refreshCw300,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SingleChildScrollView(
                    child: runtime.organizationError != null
                        ? Semantics(
                            liveRegion: true,
                            label: runtime.organizationError,
                            child: BnbuText(
                              runtime.organizationError!,
                              style: TextStyle(color: tokens.danger),
                            ),
                          )
                        : _organizationFor(document, runtime).isEmpty
                        ? const BnbuText('点击右上角按钮后开始整理')
                        : SafeAssistantMarkdown(
                            data: _organizationFor(document, runtime),
                            actions: const [],
                            onAction: (_) {},
                            fontScale: 0.8,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssistant(
    BuildContext context,
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) {
    final tokens = context.bnbuTheme;
    final conversation = _conversationFor(document);
    if (runtime.showingQuestionHistory) {
      return _buildQuestionHistory(context, document, runtime);
    }
    final messages =
        conversation?.messages
            .where(
              (message) =>
                  message.studyContext?.type ==
                  AssistantStudyEntryType.question,
            )
            .toList(growable: false) ??
        const <AssistantStoredMessage>[];
    final conversationPending =
        conversation != null &&
        widget.assistantController.isConversationSending(conversation.id);
    final pendingQuestion = isStudyQuestionPending(
      conversation,
      isConversationSending: conversationPending,
    );
    return Column(
      children: [
        SizedBox(
          height: 42,
          child: Padding(
            padding: EdgeInsets.only(
              left: tokens.space12,
              right: tokens.space8,
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.messageCircleQuestion300, size: 16),
                SizedBox(width: tokens.space8),
                BnbuText('学业问答', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                _CompactStudyIconButton(
                  tooltip: context.l10n.text('问答历史'),
                  onPressed: () => setState(() {
                    runtime.showingQuestionHistory = true;
                  }),
                  icon: LucideIcons.history300,
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: tokens.border),
        Expanded(
          child: messages.isEmpty && !pendingQuestion
              ? const Center(child: BnbuText('暂无问答记录'))
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    tokens.space12,
                    tokens.space8,
                    tokens.space12,
                    tokens.space12,
                  ),
                  itemCount: messages.length + (pendingQuestion ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: BnbuActivityIndicator()),
                      );
                    }
                    final message = messages[index];
                    return _StudyMessageBubble(message: message);
                  },
                ),
        ),
        Divider(height: 1, color: tokens.border),
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.space12,
            tokens.space8,
            tokens.space12,
            tokens.space12,
          ),
          child: Column(
            children: [
              TextField(
                key: const ValueKey('study-mode-question-field'),
                controller: runtime.questionController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _ask(document, runtime),
                decoration: InputDecoration(
                  hintText: context.l10n.text('询问小U'),
                  filled: true,
                  fillColor: tokens.surfaceMuted,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radius12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radius12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radius12),
                    borderSide: BorderSide(
                      color: tokens.textSecondary,
                      width: 1.2,
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  suffixIcon: _CompactStudyIconButton(
                    tooltip: context.l10n.text('发送'),
                    emphasized: true,
                    onPressed: runtime.asking || conversationPending
                        ? null
                        : () => _ask(document, runtime),
                    icon: LucideIcons.arrowUp300,
                    loading: runtime.asking,
                  ),
                ),
              ),
              SizedBox(height: tokens.space8),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<StudyQuestionScope>(
                  key: const ValueKey('study-mode-question-scope'),
                  segments: [
                    ButtonSegment(
                      value: StudyQuestionScope.currentPage,
                      icon: const Icon(LucideIcons.file300, size: 15),
                      tooltip: context.l10n.text('询问本页'),
                    ),
                    ButtonSegment(
                      value: StudyQuestionScope.selectedPages,
                      icon: const Icon(LucideIcons.files300, size: 15),
                      tooltip: context.l10n.text('选择多页提问'),
                    ),
                    ButtonSegment(
                      value: StudyQuestionScope.wholeDocument,
                      icon: const Icon(LucideIcons.bookOpen300, size: 15),
                      tooltip: context.l10n.text('询问全文件'),
                    ),
                  ],
                  style: SegmentedButton.styleFrom(
                    minimumSize: const Size(36, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    selectedBackgroundColor: tokens.textPrimary,
                    selectedForegroundColor: tokens.surface,
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                  ),
                  selected: {runtime.questionScope},
                  onSelectionChanged: (selection) =>
                      _changeScope(selection.single, document, runtime),
                  showSelectedIcon: false,
                ),
              ),
              if (runtime.questionError != null) ...[
                SizedBox(height: tokens.space8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    liveRegion: true,
                    label: runtime.questionError,
                    child: BnbuText(
                      runtime.questionError!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.danger),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionHistory(
    BuildContext context,
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) {
    final tokens = context.bnbuTheme;
    final conversations = studyQuestionConversationsForDocument(
      widget.assistantController.studyConversationHistory,
      document.key,
    );
    return Column(
      key: const ValueKey('study-mode-question-history'),
      children: [
        SizedBox(
          height: 42,
          child: Padding(
            padding: EdgeInsets.only(left: tokens.space4, right: tokens.space8),
            child: Row(
              children: [
                _CompactStudyIconButton(
                  tooltip: context.l10n.text('返回问答'),
                  onPressed: () => setState(() {
                    runtime.showingQuestionHistory = false;
                  }),
                  icon: LucideIcons.arrowLeft300,
                ),
                SizedBox(width: tokens.space4),
                Expanded(
                  child: BnbuText(
                    '问答记录',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                _CompactStudyIconButton(
                  tooltip: context.l10n.text('新建问答'),
                  onPressed: () =>
                      _startNewStudyConversation(document, runtime),
                  icon: LucideIcons.squarePen300,
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: tokens.border),
        Expanded(
          child: conversations.isEmpty
              ? const Center(child: BnbuText('暂无问答记录'))
              : ListView.separated(
                  padding: EdgeInsets.symmetric(vertical: tokens.space8),
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: tokens.space16,
                    endIndent: tokens.space16,
                    color: tokens.border,
                  ),
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final selected =
                        _conversationFor(document)?.id == conversation.id;
                    return _StudyConversationHistoryTile(
                      key: ValueKey(
                        'study-question-history-${conversation.id}',
                      ),
                      title: studyConversationDisplayTitle(conversation),
                      relativeTime: studyRelativeTime(conversation.updatedAt),
                      selected: selected,
                      onTap: () => _selectStudyConversation(
                        document,
                        conversation.id,
                        runtime,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  AssistantConversation? _conversationFor(AssistantStudyDocument document) {
    final preferredId = _activeStudyConversationIds[document.key];
    if (preferredId != null) {
      final preferred = widget.assistantController.conversationById(
        preferredId,
      );
      if (preferred?.kind == AssistantConversationKind.study &&
          preferred?.studyDocument?.key == document.key) {
        return preferred;
      }
    }
    for (final conversation in widget.assistantController.conversations) {
      if (conversation.kind == AssistantConversationKind.study &&
          conversation.studyDocument?.key == document.key) {
        _activeStudyConversationIds[document.key] = conversation.id;
        return conversation;
      }
    }
    return null;
  }

  String _organizationFor(
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) {
    final pageNumber = runtime.currentPage?.pageNumber;
    if (pageNumber == null) return '';
    final cached = runtime.organizations[pageNumber];
    if (cached != null && cached.isNotEmpty) return cached;
    for (final conversation
        in widget.assistantController.studyConversationHistory) {
      if (conversation.studyDocument?.key != document.key) continue;
      for (final message in conversation.messages.reversed) {
        if (message.role == 'assistant' &&
            !message.isError &&
            message.studyContext?.type ==
                AssistantStudyEntryType.organization &&
            message.studyContext?.pages.contains(pageNumber) == true) {
          return message.content;
        }
      }
    }
    return '';
  }

  Future<String?> _conversationIdFor(AssistantStudyDocument document) async {
    final existing = _conversationFor(document);
    if (existing != null) return existing.id;
    final id = await widget.assistantController.ensureStudyConversation(
      document,
    );
    if (id != null) _activeStudyConversationIds[document.key] = id;
    return id;
  }

  Future<void> _startNewStudyConversation(
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) async {
    final id = await widget.assistantController.createStudyConversation(
      document,
    );
    if (id == null || !mounted) return;
    setState(() {
      _activeStudyConversationIds[document.key] = id;
      runtime.showingQuestionHistory = false;
      runtime.questionError = null;
      runtime.questionController.clear();
    });
  }

  void _selectStudyConversation(
    AssistantStudyDocument document,
    String conversationId,
    _DocumentRuntime runtime,
  ) {
    setState(() {
      _activeStudyConversationIds[document.key] = conversationId;
      runtime.showingQuestionHistory = false;
      runtime.questionError = null;
    });
  }

  Future<void> _requestOrganization(
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) async {
    if (_organizationFor(document, runtime).isEmpty) {
      await _organize(document, runtime);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(LucideIcons.refreshCw300, size: 20),
        title: const BnbuText('重新整理本页'),
        content: const BnbuText('现有整理内容将被新结果替换。'),
        actions: [
          IconButton(
            tooltip: context.l10n.text('取消'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            icon: const Icon(LucideIcons.x300, size: 17),
          ),
          BnbuModalActionButton(
            tooltip: context.l10n.text('确认重新整理'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: LucideIcons.sparkles300,
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _organize(document, runtime);
  }

  Future<void> _organize(
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) async {
    final page = runtime.currentPage;
    if (page == null || runtime.organizing) return;
    setState(() {
      runtime.organizing = true;
      runtime.organizationError = null;
    });
    final context = AssistantStudyMessageContext(
      type: AssistantStudyEntryType.organization,
      pages: [page.pageNumber],
      scope: 'current_page',
    );
    try {
      final request = await _skill.organize(
        page: page,
        outputLanguage: WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag(),
        customInstruction: AccountHabits.shared.read(
          'study.organization_prompt',
          _organizationPrompt,
        ),
      );
      final conversationId = await _conversationIdFor(document);
      if (conversationId == null) return;
      await widget.assistantController.send(
        request.prompt,
        conversationId: conversationId,
        attachments: request.attachments,
        visibleMessage: '整理${page.pageLabel}',
        studyContext: context,
      );
      final conversation = widget.assistantController.conversationById(
        conversationId,
      );
      final result = conversation?.messages.reversed.firstWhere(
        (message) =>
            message.role == 'assistant' &&
            message.studyContext?.type ==
                AssistantStudyEntryType.organization &&
            message.studyContext?.pages.contains(page.pageNumber) == true,
        orElse: () => AssistantStoredMessage(
          role: 'assistant',
          content: '整理失败',
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        if (result == null || result.isError) {
          runtime.organizationError = result?.content ?? '整理失败，请重试。';
        } else {
          runtime.organizations[page.pageNumber] = result.content;
        }
      });
    } on StudyPageImageUnavailableException catch (error) {
      if (mounted) {
        setState(() => runtime.organizationError = error.message);
      }
    } finally {
      if (mounted) setState(() => runtime.organizing = false);
    }
  }

  Future<void> _ask(
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) async {
    final question = runtime.questionController.text.trim();
    if (question.isEmpty || runtime.currentPage == null || runtime.asking) {
      return;
    }
    setState(() {
      runtime.asking = true;
      runtime.questionError = null;
    });
    try {
      final pages = await _loadScopePages(runtime);
      if (pages.isEmpty) return;
      final request = await _skill.answerPages(
        pages: pages,
        question: question,
        outputLanguage: WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag(),
        scope: runtime.questionScope,
      );
      final conversationId = await _conversationIdFor(document);
      if (conversationId == null) return;
      runtime.questionController.clear();
      await widget.assistantController.send(
        request.prompt,
        conversationId: conversationId,
        attachments: request.attachments,
        visibleMessage: question,
        studyContext: AssistantStudyMessageContext(
          type: AssistantStudyEntryType.question,
          pages: pages.map((page) => page.pageNumber).toList(growable: false),
          scope: switch (runtime.questionScope) {
            StudyQuestionScope.currentPage => 'current_page',
            StudyQuestionScope.selectedPages => 'selected_pages',
            StudyQuestionScope.wholeDocument => 'whole_document',
          },
        ),
      );
    } on StudyPageImageUnavailableException catch (error) {
      if (mounted) setState(() => runtime.questionError = error.message);
    } finally {
      if (mounted) setState(() => runtime.asking = false);
    }
  }

  Future<List<StudyPageSnapshot>> _loadScopePages(
    _DocumentRuntime runtime,
  ) async {
    final current = runtime.currentPage;
    if (current == null) return const [];
    final access = runtime.access;
    final pageNumbers = switch (runtime.questionScope) {
      StudyQuestionScope.currentPage => <int>{current.pageNumber},
      StudyQuestionScope.selectedPages => runtime.selectedPages,
      StudyQuestionScope.wholeDocument => {
        for (var page = 1; page <= current.pageCount; page++) page,
      },
    };
    if (access == null) return [current];
    final pages = <StudyPageSnapshot>[];
    for (final pageNumber in pageNumbers.toList()..sort()) {
      final page = pageNumber == current.pageNumber
          ? current
          : await access.loadPage(pageNumber);
      if (page != null) pages.add(page);
    }
    return pages;
  }

  Future<void> _changeScope(
    StudyQuestionScope scope,
    AssistantStudyDocument document,
    _DocumentRuntime runtime,
  ) async {
    if (scope != StudyQuestionScope.selectedPages) {
      setState(() => runtime.questionScope = scope);
      return;
    }
    final current = _runtimeFor(document).currentPage;
    if (current == null) return;
    final selected = await _selectPages(
      current.pageCount,
      current.pageNumber,
      runtime.selectedPages,
    );
    if (selected == null || !mounted) return;
    setState(() {
      runtime.selectedPages = selected;
      runtime.questionScope = StudyQuestionScope.selectedPages;
    });
  }

  Future<Set<int>?> _selectPages(
    int pageCount,
    int currentPage,
    Set<int> selectedPages,
  ) {
    final initial = selectedPages.isEmpty
        ? {currentPage}
        : selectedPages.take(StudyModeSkill.maxVisualPages).toSet();
    return showBnbuAdaptiveModal<Set<int>>(
      context: context,
      dialogMaxWidth: 620,
      dialogMaxHeight: 560,
      semanticLabel: context.l10n.text('选择页面'),
      builder: (dialogContext, presentation) {
        final selected = Set<int>.of(initial);
        return StatefulBuilder(
          builder: (context, setDialogState) => BnbuModalFrame(
            presentation: presentation,
            title:
                '选择页面  ${selected.length} / ${StudyModeSkill.maxVisualPages}',
            icon: LucideIcons.files300,
            actions: [
              BnbuModalActionButton(
                tooltip: context.l10n.text('完成'),
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(selected),
                icon: LucideIcons.check300,
              ),
            ],
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 480 ? 7 : 5;
                return GridView.builder(
                  key: const ValueKey('study-page-selector-grid'),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: 44,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: pageCount,
                  itemBuilder: (context, index) {
                    final page = index + 1;
                    final checked = selected.contains(page);
                    final enabled =
                        checked ||
                        selected.length < StudyModeSkill.maxVisualPages;
                    return _StudyPageSelectionButton(
                      page: page,
                      selected: checked,
                      enabled: enabled,
                      onPressed: () => setDialogState(() {
                        checked ? selected.remove(page) : selected.add(page);
                      }),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAllStudyFiles() async {
    final documents = <String, AssistantStudyDocument>{};
    for (final conversation
        in widget.assistantController.studyConversationHistory) {
      final document = conversation.studyDocument;
      if (document != null) documents[document.key] = document;
    }
    final selected = await showBnbuAdaptiveModal<AssistantStudyDocument>(
      context: context,
      dialogMaxWidth: 580,
      dialogMaxHeight: 560,
      semanticLabel: context.l10n.text('学业模式'),
      builder: (dialogContext, presentation) => BnbuModalFrame(
        presentation: presentation,
        title: '学业模式',
        icon: LucideIcons.library300,
        child: SizedBox(
          child: documents.isEmpty
              ? const Center(child: BnbuText('暂无学业记录'))
              : ListView.separated(
                  itemCount: documents.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final document = documents.values.elementAt(index);
                    return ListTile(
                      key: ValueKey('study-file-${document.key}'),
                      leading: const Icon(LucideIcons.fileText300),
                      title: BnbuText(document.title),
                      trailing: const Icon(LucideIcons.arrowUpRight300),
                      onTap: () => Navigator.of(dialogContext).pop(document),
                    );
                  },
                ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _tabController.add(selected, activate: true);
  }

  void _closeDocument(String key) {
    _tabController.remove(key);
    if (_documents.isEmpty) widget.onAllDocumentsClosed?.call();
  }

  void _resizeThumbnails(double delta) {
    setState(() => _thumbnailWidth = (_thumbnailWidth + delta).clamp(150, 360));
    _scheduleLayoutSave();
  }

  void _resizeAssistant(double delta) {
    setState(() => _assistantWidth = (_assistantWidth - delta).clamp(300, 620));
    _scheduleLayoutSave();
  }

  void _resizeOrganization(double delta) {
    setState(
      () => _organizationHeight = (_organizationHeight + delta).clamp(128, 420),
    );
    _scheduleLayoutSave();
  }

  void _scheduleLayoutSave() {
    _layoutSaveDebounce?.cancel();
    _layoutSaveDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_saveLayout()),
    );
  }

  Future<Map<String, String>> _loadHeaders(
    AssistantStudyDocument document,
  ) async {
    try {
      final snapshot = await widget.sessionController.prepareWebSession();
      if (!urlsHaveSameOrigin(document.sourceUrl, snapshot.baseUrl)) {
        return const {};
      }
      final header = snapshot.cookies
          .where((cookie) => cookie.name.trim().isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      return header.isEmpty ? const {} : {'Cookie': header};
    } catch (_) {
      return const {};
    }
  }

  Future<AssistantStudyDocumentCopy> _prepareDocument(
    AssistantStudyDocument document,
  ) async {
    final remote = await widget.assistantController.downloadStudyDocument(
      document,
    );
    if (remote != null) return remote;

    final headers = await _loadHeaders(document);
    final request = http.Request(
      'GET',
      Uri.parse(_downloadUrl(document.sourceUrl)),
    )..headers.addAll(headers);
    final client = http.Client();
    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiAssistantException('课件读取失败（HTTP ${response.statusCode}）。');
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received > 64 * 1024 * 1024) {
          throw const AiAssistantException('学业文件超过 64 MB。');
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      final responseMime = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      final mimeType = _studyMimeType(document, bytes, responseMime);
      await widget.assistantController.uploadStudyDocument(
        document,
        mimeType: mimeType,
        bytes: bytes,
      );
      return AssistantStudyDocumentCopy(bytes: bytes, mimeType: mimeType);
    } on TimeoutException {
      throw const AiAssistantNetworkException('同步学业文件超时。');
    } finally {
      client.close();
    }
  }

  String _studyMimeType(
    AssistantStudyDocument document,
    Uint8List bytes,
    String? responseMime,
  ) {
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2d) {
      return 'application/pdf';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04 &&
        (responseMime?.contains('presentation') == true ||
            '${document.title} ${document.sourceUrl}'.toLowerCase().contains(
              '.pptx',
            ))) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    throw const AiAssistantException('学业模式目前只支持 PDF 与 PPTX。');
  }

  String _downloadUrl(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !uri.path.contains('/pluginfile.php')) return sourceUrl;
    final query = Map<String, String>.from(uri.queryParameters)
      ..putIfAbsent('forcedownload', () => '1');
    return uri.replace(queryParameters: query).toString();
  }

  Future<void> _restorePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final storedOrganizationPrompt = AccountHabits.shared.managed
        ? AccountHabits.shared.read<String?>('study.organization_prompt', null)
        : preferences.getString('bnbu.study.organization_prompt.v1');
    if (!mounted) return;
    setState(() {
      _thumbnailWidth =
          preferences.getDouble('bnbu.study.thumbnail_width.v1') ?? 220;
      _assistantWidth =
          preferences.getDouble('bnbu.study.assistant_width.v1') ?? 360;
      _organizationHeight =
          preferences.getDouble('bnbu.study.organization_height.v1') ?? 196;
      _organizationPrompt = storedOrganizationPrompt?.trim().isNotEmpty == true
          ? storedOrganizationPrompt!.trim()
          : StudyModeSkill.defaultOrganizationInstruction;
    });
  }

  Future<void> _saveLayout() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setDouble('bnbu.study.thumbnail_width.v1', _thumbnailWidth),
      preferences.setDouble('bnbu.study.assistant_width.v1', _assistantWidth),
      preferences.setDouble(
        'bnbu.study.organization_height.v1',
        _organizationHeight,
      ),
    ]);
  }

  Future<void> _editOrganizationPrompt() async {
    final editor = TextEditingController(
      text: AccountHabits.shared.read(
        'study.organization_prompt',
        _organizationPrompt,
      ),
    );
    final value = await showBnbuAdaptiveModal<String>(
      context: context,
      dialogMaxWidth: 620,
      dialogMaxHeight: 480,
      semanticLabel: context.l10n.text('整理提示词'),
      builder: (dialogContext, presentation) => BnbuModalFrame(
        presentation: presentation,
        title: '整理提示词',
        icon: LucideIcons.slidersHorizontal300,
        actions: [
          IconButton(
            tooltip: context.l10n.text('恢复预设'),
            onPressed: () {
              editor.value = const TextEditingValue(
                text: StudyModeSkill.defaultOrganizationInstruction,
                selection: TextSelection.collapsed(
                  offset: StudyModeSkill.defaultOrganizationInstruction.length,
                ),
              );
            },
            icon: const Icon(LucideIcons.rotateCcw300, size: 17),
          ),
          BnbuModalActionButton(
            tooltip: context.l10n.text('保存'),
            onPressed: () {
              final prompt = editor.text.trim();
              Navigator.of(dialogContext).pop(
                prompt.isEmpty
                    ? StudyModeSkill.defaultOrganizationInstruction
                    : prompt,
              );
            },
            icon: LucideIcons.check300,
          ),
        ],
        child: TextField(
          key: const ValueKey('study-organization-prompt-field'),
          controller: editor,
          autofocus: presentation.isDialog,
          minLines: 7,
          maxLines: 12,
          decoration: InputDecoration(labelText: context.l10n.text('提示词')),
        ),
      ),
    );
    editor.dispose();
    if (value == null || !mounted) return;
    final preferences = await SharedPreferences.getInstance();
    if (AccountHabits.shared.managed) {
      await AccountHabits.shared.set('study.organization_prompt', value);
    } else {
      await preferences.setString('bnbu.study.organization_prompt.v1', value);
    }
    if (mounted) setState(() => _organizationPrompt = value);
  }
}

class _DocumentRuntime {
  final TextEditingController questionController = TextEditingController();
  StudyPageSnapshot? currentPage;
  StudyDocumentAccess? access;
  final Map<int, String> organizations = {};
  String? organizationError;
  bool organizing = false;
  bool showingQuestionHistory = false;
  StudyQuestionScope questionScope = StudyQuestionScope.currentPage;
  Set<int> selectedPages = {};
  String? questionError;
  bool asking = false;

  void dispose() {
    questionController.dispose();
  }
}

class _StudyMessageBubble extends StatelessWidget {
  const _StudyMessageBubble({required this.message});

  final AssistantStoredMessage message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: tokens.space8),
        padding: message.isUser
            ? EdgeInsets.symmetric(
                horizontal: tokens.space12,
                vertical: tokens.space8,
              )
            : EdgeInsets.symmetric(vertical: tokens.space4),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: message.isUser ? tokens.surfaceMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radius12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isUser)
              SelectableText(message.content)
            else
              SafeAssistantMarkdown(
                data: message.content,
                actions: message.actions,
                onAction: (_) {},
                fontScale: 0.8,
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactStudyIconButton extends StatelessWidget {
  const _CompactStudyIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.emphasized = false,
    this.loading = false,
    this.badgeIcon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool emphasized;
  final bool loading;
  final IconData? badgeIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        maximumSize: const Size.square(36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: emphasized ? tokens.textPrimary : Colors.transparent,
        foregroundColor: emphasized ? tokens.surface : tokens.textPrimary,
        disabledBackgroundColor: emphasized
            ? tokens.surfaceMuted
            : Colors.transparent,
        disabledForegroundColor: tokens.textSecondary,
      ),
      icon: loading
          ? SizedBox.square(
              dimension: 14,
              child: BnbuActivityIndicator(
                color: emphasized ? tokens.surface : tokens.textSecondary,
              ),
            )
          : badgeIcon == null
          ? Icon(icon, size: 16)
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 16),
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: emphasized ? tokens.surface : tokens.textPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: emphasized ? tokens.textPrimary : tokens.surface,
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1.75),
                      child: Icon(
                        badgeIcon,
                        size: 10,
                        color: emphasized ? tokens.textPrimary : tokens.surface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StudyTabIconButton extends StatelessWidget {
  const _StudyTabIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(28),
        minimumSize: const Size.square(28),
        maximumSize: const Size.square(28),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: tokens.textPrimary,
        disabledForegroundColor: tokens.textMuted,
      ),
      icon: Icon(icon, size: 11),
    );
  }
}

class _StudyConversationHistoryTile extends StatelessWidget {
  const _StudyConversationHistoryTile({
    super.key,
    required this.title,
    required this.relativeTime,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String relativeTime;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Material(
      color: selected ? tokens.surfaceMuted : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.space16),
            child: Row(
              children: [
                Expanded(
                  child: BnbuText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: tokens.space12),
                BnbuText(
                  relativeTime,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudyPageSelectionButton extends StatelessWidget {
  const _StudyPageSelectionButton({
    required this.page,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final int page;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Material(
      color: selected ? tokens.textPrimary : tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(tokens.radius12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(LucideIcons.check300, size: 14, color: tokens.surface),
                SizedBox(width: tokens.space4),
              ],
              BnbuText(
                '$page',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? tokens.surface
                      : enabled
                      ? tokens.textPrimary
                      : tokens.textMuted,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResizeDivider extends StatelessWidget {
  const _ResizeDivider({required this.axis, required this.onDelta});

  final Axis axis;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return MouseRegion(
      cursor: axis == Axis.vertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: axis == Axis.vertical
            ? (details) => onDelta(details.delta.dx)
            : null,
        onVerticalDragUpdate: axis == Axis.horizontal
            ? (details) => onDelta(details.delta.dy)
            : null,
        child: SizedBox(
          width: axis == Axis.vertical ? 7 : null,
          height: axis == Axis.horizontal ? 7 : null,
          child: Center(
            child: ColoredBox(
              color: tokens.border,
              child: SizedBox(
                width: axis == Axis.vertical ? 1 : double.infinity,
                height: axis == Axis.horizontal ? 1 : double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
