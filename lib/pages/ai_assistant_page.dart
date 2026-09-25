import 'me_identity_page.dart';
import '../services/me_identity_service.dart';
import '../pages/file_preview_page.dart';
import '../widgets/bnbu_menu.dart';
import '../widgets/assistant_thinking_text.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../config/app_config.dart';
import '../models/assistant_models.dart';
import '../models/assistant_text.dart';
import '../models/assistant_memory.dart';
import '../models/assistant_resource.dart';
import '../services/ai_assistant_service.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/assistant_history_store.dart';
import '../services/assistant_tool_registry.dart';
import '../services/native_actions.dart';
import '../state/ai_assistant_controller.dart';
import '../state/assistant_presentation_controller.dart';
import '../state/assistant_resource_library_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/assistant_resource_library_scope.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/safe_assistant_markdown.dart';
import '../widgets/small_u_logo.dart';

typedef AssistantActionExecutionCallback =
    Future<void> Function(
      AssistantAction action, {
      required bool userConfirmed,
    });

typedef AssistantAttachmentPicker =
    Future<List<AssistantInputAttachment>> Function();

typedef AssistantCameraPicker = Future<AssistantInputAttachment?> Function();

typedef AssistantPhotoPicker =
    Future<List<AssistantInputAttachment>> Function();

enum _AssistantAttachmentSource { resourceLibrary, camera, photos, files }

enum _ConversationAction { delete }

String? _assistantAttachmentMimeType(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'txt' || 'log' => 'text/plain',
    'md' => 'text/markdown',
    'csv' => 'text/csv',
    'json' => 'application/json',
    'xml' => 'application/xml',
    'yaml' || 'yml' => 'application/yaml',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'zip' => 'application/zip',
    '7z' => 'application/x-7z-compressed',
    _ => null,
  };
}

/// 小U会话与输入区的阅读宽度上限，比正文 1440 更窄，避免宽屏出现超长行。
const double _assistantReadingWidth = 800;

/// 常驻侧栏时工作区自绘顶栏的高度。
const double _assistantHeaderHeight = 56;

/// 桌面平台使用指针精度，允许更密的行节奏；触控平台保持 44px 命中高度。
bool get _usesPointerDensity => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// 侧栏所有可见行共享的行高：桌面 28px、触控 44px。
double get _sidebarRowHeight => _usesPointerDensity ? 28.0 : 44.0;

/// 消息区图标操作的命中尺寸：桌面收紧到 32px，触控保持 44px。
double get _inlineActionExtent => _usesPointerDensity ? 32.0 : 44.0;

/// 输入区圆形按钮尺寸，与思考强度分段控件高度对齐。
double get _composerButtonExtent => _usesPointerDensity ? 32.0 : 44.0;

bool _isLocalAssignmentFile(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return const {
    'pdf',
    'doc',
    'docx',
    'ppt',
    'pptx',
    'xls',
    'xlsx',
    'zip',
    '7z',
  }.contains(extension);
}

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({
    super.key,
    required this.assistantController,
    required this.onExecuteAction,
    this.attachmentPicker,
    this.cameraPicker,
    this.photoPicker,
    this.resourceLibrary,
    this.nativeActions = const NativeActions(),
    this.onOpenStudyDocument,
    this.initialAttachments = const [],
  });

  final AiAssistantController assistantController;
  final AssistantActionExecutionCallback onExecuteAction;
  final AssistantAttachmentPicker? attachmentPicker;
  final AssistantCameraPicker? cameraPicker;
  final AssistantPhotoPicker? photoPicker;
  final AssistantResourceLibraryController? resourceLibrary;
  final NativeActions nativeActions;
  final Future<void> Function(AssistantStudyDocument document)?
  onOpenStudyDocument;
  final List<AssistantInputAttachment> initialAttachments;

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _composerContentKey = GlobalKey();
  final _composerAvoidanceOwner = Object();
  final _imagePicker = ImagePicker();
  int _visibleMessageCount = 0;
  String? _visiblePendingOperationId;
  final Set<String> _autoExecutedActionKeys = <String>{};
  List<AssistantInputAttachment> _attachments = const [];
  AssistantResourceLibraryController? _resourceLibrary;
  AssistantContextCoordinator? _contextCoordinator;
  AssistantPresentationController? _presentationController;
  Object? _runtimeDraftOwnerToken;
  AssistantContextRegistration? _contextRegistration;
  AssistantCurrentPageContext? _sourcePageContext;
  bool _didRecoverLostImages = false;
  bool _restoringRuntimeDraft = false;
  double _historySwipeDistance = 0;

  @override
  void initState() {
    super.initState();
    _attachments = List.unmodifiable(widget.initialAttachments.take(3));
    _messageController.addListener(_saveRuntimeDraft);
    widget.assistantController.addListener(_handleAssistantChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.assistantController.initialize());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final contextCoordinator = AssistantContextScope.maybeOf(context);
    if (!identical(contextCoordinator, _contextCoordinator)) {
      _contextRegistration?.dispose();
      _contextCoordinator = contextCoordinator;
      final previous = contextCoordinator?.snapshot().currentPage;
      final source = previous?.sourcePage ?? previous;
      _sourcePageContext =
          const {
            'me_life',
            'me_life_detail',
            'directory',
            'directory_person',
          }.contains(source?.pageType)
          ? source
          : null;
      _contextRegistration = contextCoordinator?.register(
        AssistantContextContribution(currentPage: _currentPageContext),
      );
    }
    final presentationController =
        AssistantContextScope.maybePresentationControllerOf(context);
    if (!identical(presentationController, _presentationController)) {
      _presentationController = presentationController;
      _runtimeDraftOwnerToken =
          presentationController?.assistantDraftOwnerToken;
      _restoreRuntimeDraft();
    }
    final resourceLibrary =
        widget.resourceLibrary ??
        AssistantResourceLibraryScope.maybeOf(context);
    if (!identical(resourceLibrary, _resourceLibrary)) {
      _resourceLibrary = resourceLibrary;
      if (resourceLibrary != null) {
        _scheduleResourceLibraryInitialization(resourceLibrary);
      }
    }
    if (!_didRecoverLostImages && Platform.isAndroid) {
      _didRecoverLostImages = true;
      unawaited(_recoverLostImages());
    }
  }

  @override
  void didUpdateWidget(covariant AiAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.assistantController, widget.assistantController)) {
      oldWidget.assistantController.removeListener(_handleAssistantChanged);
      widget.assistantController.addListener(_handleAssistantChanged);
      unawaited(widget.assistantController.initialize());
    }
    if (!identical(oldWidget.resourceLibrary, widget.resourceLibrary) &&
        widget.resourceLibrary != null) {
      _resourceLibrary = widget.resourceLibrary;
      _scheduleResourceLibraryInitialization(widget.resourceLibrary!);
    }
  }

  void _scheduleResourceLibraryInitialization(
    AssistantResourceLibraryController resourceLibrary,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_resourceLibrary, resourceLibrary)) {
        return;
      }
      unawaited(resourceLibrary.initialize());
    });
  }

  @override
  void dispose() {
    _presentationController?.clearAssistantBottomAvoidance(
      _composerAvoidanceOwner,
    );
    widget.assistantController.removeListener(_handleAssistantChanged);
    _contextRegistration?.dispose();
    _saveRuntimeDraft();
    _messageController.removeListener(_saveRuntimeDraft);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _restoreRuntimeDraft() {
    final presentationController = _presentationController;
    if (presentationController == null) return;
    _restoringRuntimeDraft = true;
    try {
      if (widget.initialAttachments.isNotEmpty) {
        _messageController.clear();
        _attachments = List.unmodifiable(widget.initialAttachments.take(3));
      } else {
        _messageController.value = TextEditingValue(
          text: presentationController.assistantDraftText,
          selection: TextSelection.collapsed(
            offset: presentationController.assistantDraftText.length,
          ),
        );
        _attachments = List.unmodifiable(
          presentationController.assistantDraftAttachments.take(3),
        );
      }
    } finally {
      _restoringRuntimeDraft = false;
    }
    _saveRuntimeDraft();
  }

  void _saveRuntimeDraft() {
    if (_restoringRuntimeDraft) return;
    final presentationController = _presentationController;
    final ownerToken = _runtimeDraftOwnerToken;
    if (presentationController == null || ownerToken == null) return;
    presentationController.updateAssistantDraft(
      ownerToken: ownerToken,
      text: _messageController.text,
      attachments: _attachments,
    );
  }

  void _replaceAttachments(List<AssistantInputAttachment> attachments) {
    setState(() => _attachments = List.unmodifiable(attachments.take(3)));
    _saveRuntimeDraft();
  }

  void _scheduleComposerAvoidanceReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final render = _composerContentKey.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final media = MediaQuery.of(context);
      final keyboardTop = media.size.height - media.viewInsets.bottom;
      final composerTop = render.localToGlobal(Offset.zero).dy;
      // Keep a visual separation between the floating control and the live
      // composer, including dynamically wrapped attachment cards.
      final clearance = math.max(0.0, keyboardTop - composerTop + 12);
      _presentationController?.updateAssistantBottomAvoidance(
        owner: _composerAvoidanceOwner,
        value: clearance,
        rect: render.localToGlobal(Offset.zero) & render.size,
      );
    });
  }

  AssistantCurrentPageContext _currentPageContext() {
    return AssistantCurrentPageContext(
      pageType: 'ai_assistant',
      sourcePage:
          widget
                  .assistantController
                  .capabilities
                  ?.publicDirectoryToolsVersion ==
              1
          ? _sourcePageContext
          : null,
      title: '小U',
      selectedItemId: widget.assistantController.currentConversationId ?? '',
      summary: AppConfig.studyModeEnabled
          ? '资源库、记忆、学业模式、对话历史、消息和输入区'
          : '资源库、记忆、对话历史、消息和输入区',
    );
  }

  void _handleAssistantChanged() {
    final controller = widget.assistantController;
    final messageCount = controller.currentConversation?.messages.length ?? 0;
    final pendingOperationId = controller.isSendingCurrentConversation
        ? controller.pendingTurn?.operationId
        : null;
    final completedOperationId = _visiblePendingOperationId;
    if (messageCount != _visibleMessageCount ||
        pendingOperationId != _visiblePendingOperationId) {
      _visibleMessageCount = messageCount;
      _visiblePendingOperationId = pendingOperationId;
      _scrollToBottom();
    }
    if (completedOperationId != null && pendingOperationId == null) {
      _scheduleFreshComposeAction();
    }
  }

  void _scheduleFreshComposeAction() {
    final conversation = widget.assistantController.currentConversation;
    if (conversation == null || conversation.messages.isEmpty) return;
    final message = conversation.messages.last;
    if (message.role != 'assistant' || message.isError) return;
    final composeActions = message.actions
        .where((action) => action.type == AssistantActionType.composeEmail)
        .toList(growable: false);
    if (composeActions.length != 1) return;
    final action = composeActions.single;
    final actionKey =
        '${conversation.id}:${message.createdAt.toIso8601String()}:'
        '${action.actionId}:${action.recipient}:${action.subject}';
    if (!_autoExecutedActionKeys.add(actionKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_previewAction(action));
    });
  }

  Future<void> _startNewConversation() async {
    await widget.assistantController.startNewConversation();
    if (!mounted) return;
    _scaffoldKey.currentState?.closeDrawer();
    _scrollToBottom();
  }

  void _selectConversation(String id) {
    widget.assistantController.selectConversation(id);
    _scaffoldKey.currentState?.closeDrawer();
    _scrollToBottom();
  }

  void _selectBranch(int index) {
    widget.assistantController.selectBranch(index);
    _scrollToBottom();
  }

  Future<void> _copyMessage(AssistantStoredMessage message) async {
    await Clipboard.setData(
      ClipboardData(
        text: message.role == 'assistant'
            ? normalizeAssistantProse(message.content)
            : message.content,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: BnbuText('已复制')));
  }

  Future<void> _editUserMessage(AssistantStoredMessage message) async {
    final edited = await showBnbuAdaptiveModal<String>(
      context: context,
      dialogMaxWidth: 620,
      dialogMaxHeight: 520,
      isScrollControlled: true,
      semanticLabel: context.l10n.text('编辑消息'),
      contentKey: const ValueKey('assistant-edit-message-modal'),
      builder: (modalContext, presentation) {
        return _EditAssistantMessageForm(
          initialText: message.content,
          isDialog: presentation.isDialog,
        );
      },
    );
    if (edited == null || !mounted) return;
    await widget.assistantController.editUserMessage(message, edited);
    _scrollToBottom();
  }

  Future<void> _deleteConversation(String id) async {
    await widget.assistantController.deleteConversation(id);
  }

  void _send() {
    final message = _messageController.text.trim();
    if ((message.isEmpty && _attachments.isEmpty) ||
        widget.assistantController.isSendingCurrentConversation) {
      return;
    }
    final attachments = _attachments;
    _messageController.clear();
    _replaceAttachments(const []);
    final ownerToken = _runtimeDraftOwnerToken;
    if (ownerToken != null) {
      _presentationController?.clearAssistantDraft(ownerToken);
    }
    unawaited(
      widget.assistantController.send(message, attachments: attachments),
    );
    _scrollToBottom();
  }

  void _insertComposerNewLine() {
    final value = _messageController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    if (value.text.length - (end - start) >= 4000) {
      return;
    }
    _messageController.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  void _selectSuggestion(AssistantSuggestion suggestion) {
    if (suggestion.isOther) {
      _messageFocusNode.requestFocus();
      return;
    }
    if (widget.assistantController.isSendingCurrentConversation) {
      return;
    }
    if (_messageController.text.trim().isNotEmpty) {
      _messageFocusNode.requestFocus();
      return;
    }
    if (_attachments.isNotEmpty) {
      _messageController.text = suggestion.message;
      _messageController.selection = TextSelection.collapsed(
        offset: suggestion.message.length,
      );
      _messageFocusNode.requestFocus();
      return;
    }
    unawaited(widget.assistantController.send(suggestion.message));
    _scrollToBottom();
  }

  Future<void> _showAttachmentSources() async {
    final source = await showBnbuAdaptiveModal<_AssistantAttachmentSource>(
      context: context,
      dialogMaxWidth: 520,
      dialogMaxHeight: 360,
      semanticLabel: context.l10n.text('添加到对话'),
      contentKey: const ValueKey('assistant-attachment-source-modal'),
      builder: (modalContext, presentation) {
        final tokens = modalContext.bnbuTheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.space16,
            presentation.isDialog ? tokens.space24 : tokens.space16,
            tokens.space16,
            tokens.space24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  tokens.space4,
                  0,
                  tokens.space4,
                  tokens.space12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: BnbuText(
                        '添加到对话',
                        style: Theme.of(modalContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (presentation.isDialog)
                      IconButton(
                        tooltip: context.l10n.text('关闭'),
                        onPressed: () => Navigator.of(modalContext).pop(),
                        icon: const Icon(LucideIcons.x300),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _AttachmentSourceButton(
                      key: const ValueKey(
                        'assistant-attachment-source-resource',
                      ),
                      icon: LucideIcons.archive300,
                      label: '资源库',
                      onTap: () => Navigator.of(
                        modalContext,
                      ).pop(_AssistantAttachmentSource.resourceLibrary),
                    ),
                  ),
                  SizedBox(width: tokens.space8),
                  Expanded(
                    child: _AttachmentSourceButton(
                      key: const ValueKey('assistant-attachment-source-camera'),
                      icon: LucideIcons.camera300,
                      label: '相机',
                      onTap: () => Navigator.of(
                        modalContext,
                      ).pop(_AssistantAttachmentSource.camera),
                    ),
                  ),
                  SizedBox(width: tokens.space8),
                  Expanded(
                    child: _AttachmentSourceButton(
                      key: const ValueKey('assistant-attachment-source-photos'),
                      icon: LucideIcons.images300,
                      label: '照片',
                      onTap: () => Navigator.of(
                        modalContext,
                      ).pop(_AssistantAttachmentSource.photos),
                    ),
                  ),
                  SizedBox(width: tokens.space8),
                  Expanded(
                    child: _AttachmentSourceButton(
                      key: const ValueKey('assistant-attachment-source-files'),
                      icon: LucideIcons.folder300,
                      label: '文件',
                      onTap: () => Navigator.of(
                        modalContext,
                      ).pop(_AssistantAttachmentSource.files),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || source == null) {
      return;
    }
    switch (source) {
      case _AssistantAttachmentSource.resourceLibrary:
        final resource = await _showResourceLibrary(selecting: true);
        if (resource != null && mounted) {
          _attachResource(resource);
        }
      case _AssistantAttachmentSource.camera:
        await _pickCameraAttachment();
      case _AssistantAttachmentSource.photos:
        await _pickPhotoAttachments();
      case _AssistantAttachmentSource.files:
        await _pickFileAttachments();
    }
  }

  Future<void> _pickFileAttachments() async {
    try {
      final picked =
          await (widget.attachmentPicker?.call() ??
              _pickAssistantAttachments());
      _addAttachments(picked);
    } catch (error) {
      widget.assistantController.reportError(error);
    }
  }

  Future<void> _pickCameraAttachment() async {
    try {
      final attachment =
          await widget.cameraPicker?.call() ??
          await _pickImage(ImageSource.camera);
      if (attachment != null) {
        _addAttachments([attachment]);
      }
    } catch (error) {
      widget.assistantController.reportError(error);
    }
  }

  Future<void> _pickPhotoAttachments() async {
    try {
      final picked =
          await widget.photoPicker?.call() ?? await _pickImagesFromLibrary();
      _addAttachments(picked);
    } catch (error) {
      widget.assistantController.reportError(error);
    }
  }

  Future<AssistantInputAttachment?> _pickImage(ImageSource source) async {
    final file = await _imagePicker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
      requestFullMetadata: false,
    );
    return file == null ? null : _attachmentFromXFile(file);
  }

  Future<List<AssistantInputAttachment>> _pickImagesFromLibrary() async {
    final files = await _imagePicker.pickMultiImage(
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
      requestFullMetadata: false,
    );
    final attachments = <AssistantInputAttachment>[];
    for (final file in files.take(3)) {
      attachments.add(await _attachmentFromXFile(file));
    }
    return attachments;
  }

  Future<AssistantInputAttachment> _attachmentFromXFile(XFile file) async {
    final name = File(file.path).uri.pathSegments.last;
    final mimeType = file.mimeType ?? _assistantAttachmentMimeType(name);
    if (mimeType == null || !mimeType.startsWith('image/')) {
      throw AiAssistantException('$name 的图片格式暂不支持。');
    }
    final length = await file.length();
    if (length <= 0 || length > AssistantAttachmentLimits.maxFileBytes) {
      throw AiAssistantException(
        length > AssistantAttachmentLimits.maxFileBytes
            ? '$name 超过 50 MB。'
            : '$name 是空文件。',
      );
    }
    return AssistantInputAttachment(
      name: name,
      mimeType: mimeType,
      bytes: await file.readAsBytes(),
    );
  }

  Future<void> _recoverLostImages() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      if (!mounted || response.isEmpty) return;
      if (response.exception != null) {
        throw AiAssistantException(response.exception!.message ?? '照片恢复失败。');
      }
      final recovered = <AssistantInputAttachment>[];
      for (final file in (response.files ?? const <XFile>[]).take(3)) {
        recovered.add(await _attachmentFromXFile(file));
      }
      _addAttachments(recovered);
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not register image_picker.
    } catch (error) {
      if (mounted) {
        widget.assistantController.reportError(error);
      }
    }
  }

  void _addAttachments(List<AssistantInputAttachment> picked) {
    if (!mounted || picked.isEmpty) {
      return;
    }
    final combined = [..._attachments, ...picked];
    if (combined.length > 3) {
      widget.assistantController.reportError('一次最多添加 3 个附件。');
      return;
    }
    for (final attachment in picked) {
      if (attachment.isMailReference) continue;
      if (attachment.effectiveByteCount >
          AssistantAttachmentLimits.maxFileBytes) {
        widget.assistantController.reportError('${attachment.name} 超过 50 MB。');
        return;
      }
    }
    final providerBytes = combined
        .where((item) => !item.isLocalFileReference)
        .fold<int>(0, (total, item) => total + item.effectiveByteCount);
    if (providerBytes > AssistantAttachmentLimits.maxTotalBytes) {
      widget.assistantController.reportError('附件总大小不能超过 50 MB。');
      return;
    }
    final localBytes = combined
        .where((item) => item.isLocalFileReference)
        .fold<int>(0, (total, item) => total + item.effectiveByteCount);
    if (localBytes > 150 * 1024 * 1024) {
      widget.assistantController.reportError('待提交作业文件总大小不能超过 150 MB。');
      return;
    }
    _replaceAttachments(combined);
  }

  void _attachResource(AssistantResourceItem resource) {
    final library = _resourceLibrary;
    if (library == null) {
      widget.assistantController.reportError('小U资源库暂不可用。');
      return;
    }
    try {
      _addAttachments([library.createReferenceAttachment(resource)]);
    } catch (error) {
      widget.assistantController.reportError(error);
    }
  }

  Future<AssistantResourceItem?> _showResourceLibrary({
    required bool selecting,
  }) {
    final library = _resourceLibrary;
    if (library == null) {
      widget.assistantController.reportError('小U资源库暂不可用。');
      return Future.value();
    }
    return showBnbuAdaptiveModal<AssistantResourceItem>(
      context: context,
      dialogMaxWidth: 760,
      dialogMaxHeight: 680,
      isScrollControlled: true,
      semanticLabel: context.l10n.text('资源库'),
      contentKey: const ValueKey('assistant-resource-library-modal'),
      builder: (modalContext, presentation) {
        final tokens = modalContext.bnbuTheme;
        return AnimatedBuilder(
          animation: library,
          builder: (context, _) {
            return SizedBox(
              height: presentation.isDialog
                  ? 680
                  : MediaQuery.sizeOf(context).height * 0.68,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      tokens.space16,
                      presentation.isDialog ? tokens.space16 : 0,
                      presentation.isDialog ? tokens.space8 : tokens.space16,
                      tokens.space12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: BnbuText(
                            '资源库',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        BnbuText(
                          '${library.resources.length} 项',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        if (presentation.isDialog) ...[
                          SizedBox(width: tokens.space8),
                          IconButton(
                            tooltip: context.l10n.text('关闭'),
                            onPressed: () => Navigator.of(modalContext).pop(),
                            icon: const Icon(LucideIcons.x300),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: library.loading
                        ? const Center(child: BnbuActivityIndicator())
                        : library.resources.isEmpty
                        ? _ResourceLibraryEmptyState(error: library.error)
                        : ListView.separated(
                            padding: EdgeInsets.symmetric(
                              vertical: tokens.space8,
                            ),
                            itemCount: library.resources.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1, indent: 72),
                            itemBuilder: (context, index) {
                              final resource = library.resources[index];
                              return _AssistantResourceTile(
                                resource: resource,
                                selecting: selecting,
                                onTap: selecting
                                    ? () => Navigator.of(
                                        modalContext,
                                      ).pop(resource)
                                    : () => _openResource(resource),
                                onAdd: () =>
                                    Navigator.of(modalContext).pop(resource),
                                onOpen: () => _openResource(resource),
                                onDelete: () => _deleteResource(resource),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showHistoryModalAfterClosingDrawer(
    Future<void> Function() showModal,
  ) async {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      scaffold!.closeDrawer();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
    }
    await showModal();
  }

  Future<void> _openResource(AssistantResourceItem resource) async {
    try {
      await showFilePreview(
        context,
        title: resource.fileName,
        nativeActions: widget.nativeActions,
        path: resource.filePath,
        mimeType: resource.mimeType,
      );
    } on PlatformException catch (error) {
      if (mounted) {
        widget.assistantController.reportError(error.message ?? '无法打开这个资源。');
      }
    }
  }

  Future<void> _deleteResource(AssistantResourceItem resource) async {
    final library = _resourceLibrary;
    if (library == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const BnbuText('删除资源？'),
        content: BnbuText('“${resource.fileName}”会从这台设备的小U资源库中删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const BnbuText('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await library.delete(resource);
    } catch (error) {
      if (mounted) {
        widget.assistantController.reportError(error);
      }
    }
  }

  Future<void> _showMemories() {
    final controller = widget.assistantController;
    return showBnbuAdaptiveModal<void>(
      context: context,
      dialogMaxWidth: 680,
      dialogMaxHeight: 660,
      semanticLabel: context.l10n.text('小U记忆'),
      contentKey: const ValueKey('assistant-memory-modal'),
      builder: (modalContext, presentation) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => SizedBox(
          height: presentation.isDialog
              ? 660
              : MediaQuery.sizeOf(context).height * 0.72,
          child: BnbuModalFrame(
            presentation: presentation,
            title: '记忆',
            icon: LucideIcons.brain300,
            titleTrailing: _AssistantMemorySyncBadge(
              syncing: controller.memoriesSyncing,
              available: controller.memoriesSyncAvailable,
              failed: controller.memoriesSyncFailed,
            ),
            actions: [
              BnbuModalActionButton(
                tooltip: context.l10n.text('添加记忆'),
                onPressed: controller.memories.length >= 50
                    ? null
                    : () => _editMemory(modalContext),
                icon: LucideIcons.plus300,
              ),
            ],
            bodyPadding: EdgeInsets.zero,
            child: controller.memories.isEmpty
                ? const Center(child: Icon(LucideIcons.brain300, size: 34))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: controller.memories.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final memory = controller.memories[index];
                      return ListTile(
                        key: ValueKey('assistant-memory-${memory.id}'),
                        title: SelectableText(memory.content),
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: context.l10n.text('编辑'),
                              onPressed: () =>
                                  _editMemory(modalContext, memory: memory),
                              icon: const Icon(LucideIcons.pencil300, size: 18),
                            ),
                            IconButton(
                              tooltip: context.l10n.text('删除'),
                              onPressed: () =>
                                  _confirmDeleteMemory(modalContext, memory),
                              icon: const Icon(LucideIcons.trash2300, size: 18),
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

  Future<void> _editMemory(
    BuildContext modalContext, {
    AssistantMemoryEntry? memory,
  }) async {
    final content = await showBnbuAdaptiveModal<String>(
      context: modalContext,
      dialogMaxWidth: 560,
      dialogMaxHeight: 360,
      semanticLabel: context.l10n.text(memory == null ? '添加记忆' : '编辑记忆'),
      contentKey: const ValueKey('assistant-memory-editor'),
      builder: (context, presentation) => _AssistantMemoryEditor(
        presentation: presentation,
        initialValue: memory?.content ?? '',
      ),
    );
    if (content == null || !mounted) return;
    if (memory == null) {
      await widget.assistantController.addMemory(content);
    } else {
      await widget.assistantController.updateMemory(memory.id, content);
    }
  }

  Future<void> _saveMemorySuggestion(
    AssistantStoredMessage message,
    AssistantMemorySuggestion suggestion, {
    required bool edit,
  }) async {
    var content = suggestion.content;
    if (edit) {
      final edited = await showBnbuAdaptiveModal<String>(
        context: context,
        dialogMaxWidth: 560,
        dialogMaxHeight: 360,
        semanticLabel: context.l10n.text('编辑记忆建议'),
        contentKey: const ValueKey('assistant-memory-suggestion-editor'),
        builder: (context, presentation) => _AssistantMemoryEditor(
          presentation: presentation,
          initialValue: suggestion.content,
        ),
      );
      if (edited == null || !mounted) return;
      content = edited;
    }
    await widget.assistantController.saveMemorySuggestion(
      message,
      suggestion,
      editedContent: content,
    );
  }

  Future<void> _confirmDeleteMemory(
    BuildContext modalContext,
    AssistantMemoryEntry memory,
  ) async {
    final confirmed = await showDialog<bool>(
      context: modalContext,
      builder: (context) => AlertDialog(
        title: const BnbuText('删除记忆？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const BnbuText('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.assistantController.deleteMemory(memory.id);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final resourceLibrary = _resourceLibrary;
    return Theme(
      data: AppTheme.assistantMonochrome(Theme.of(context).brightness),
      child: Builder(
        builder: (context) => AnimatedBuilder(
          animation: Listenable.merge([
            widget.assistantController,
            MeIdentityService.shared,
            if (resourceLibrary != null) resourceLibrary,
          ]),
          builder: (context, _) {
            final controller = widget.assistantController;
            final owner = controller.meOwner;
            final tokens = context.bnbuTheme;
            return LayoutBuilder(
              builder: (context, constraints) {
                final windowClass = BnbuBreakpoints.fromWidth(
                  constraints.maxWidth,
                );
                final usesDesktopNavigation = windowClass.usesSideNavigation;
                final hasPersistentHistory =
                    constraints.maxWidth >= BnbuBreakpoints.tabletWorkspace;
                final compactPortrait =
                    !hasPersistentHistory &&
                    constraints.maxHeight > constraints.maxWidth;
                final historyPaneWidth = constraints.maxWidth < 1000
                    ? 280.0
                    : 316.0;
                final canPop = Navigator.of(context).canPop();
                final androidDrawerLeading =
                    !kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android &&
                    !hasPersistentHistory;
                // 学业模式入口按当前可用内容宽度判断，与页面其他断点同源。
                final showsStudyMode =
                    AppConfig.studyModeEnabled &&
                    !kIsWeb &&
                    (Platform.isMacOS || Platform.isWindows) &&
                    constraints.maxWidth >= BnbuBreakpoints.expandedNavigation;
                final assistantWorkspace = controller.loading
                    ? const Center(child: BnbuLoadingState(title: '正在唤醒小U'))
                    : Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _assistantReadingWidth,
                          ),
                          child: Column(
                            children: [
                              if (owner != null && controller.requiresMeBinding)
                                TextButton(
                                  onPressed: () => ensureMeBinding(
                                    context,
                                    owner,
                                    mailCredentials:
                                        controller.loadMeMailCredentials,
                                  ),
                                  child: const BnbuText('绑定 ME 账户，继续使用小U'),
                                ),
                              if (controller.error != null)
                                _AssistantErrorBanner(
                                  message: controller.error!,
                                  onDismiss: controller.clearError,
                                ),
                              Expanded(
                                child: _buildConversation(context, controller),
                              ),
                              _buildComposer(context, controller),
                            ],
                          ),
                        ),
                      );
                final scaffold = Scaffold(
                  key: _scaffoldKey,
                  backgroundColor: tokens.canvas,
                  drawerEnableOpenDragGesture: usesDesktopNavigation,
                  drawer: hasPersistentHistory
                      ? null
                      : _buildHistoryDrawer(
                          context,
                          controller,
                          resourceLibrary,
                          showsStudyMode: showsStudyMode,
                        ),
                  // 常驻侧栏时改用工作区内的自绘顶栏，让侧栏占满整列高度，
                  // 标题不再悬在侧栏上方。
                  appBar: hasPersistentHistory
                      ? null
                      : BnbuSecondaryAppBar(
                          bar: AppBar(
                            backgroundColor: tokens.surface,
                            surfaceTintColor: Colors.transparent,
                            automaticallyImplyLeading: false,
                            leading: androidDrawerLeading
                                ? IconButton(
                                    key: const ValueKey(
                                      'assistant-android-history',
                                    ),
                                    tooltip: context.l10n.text('对话与资源'),
                                    onPressed: () {
                                      _messageFocusNode.unfocus();
                                      _scaffoldKey.currentState?.openDrawer();
                                    },
                                    icon: const Icon(
                                      LucideIcons.panelLeft300,
                                      size: 21.6,
                                    ),
                                  )
                                : canPop
                                ? IconButton(
                                    key: ValueKey(
                                      usesDesktopNavigation
                                          ? 'assistant-desktop-back'
                                          : 'assistant-compact-back',
                                    ),
                                    tooltip: context.l10n.text('返回'),
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    icon: const BnbuBackIcon(),
                                  )
                                : null,
                            titleSpacing: tokens.space4,
                            title: BnbuText(
                              '小U',
                              style: BnbuHeaderMetrics.titleStyle,
                            ),
                            actions: _buildHeaderActions(
                              context,
                              controller,
                              showHistoryButton:
                                  usesDesktopNavigation &&
                                  !hasPersistentHistory &&
                                  !androidDrawerLeading,
                              showNewConversation:
                                  compactPortrait &&
                                  (controller
                                          .currentConversation
                                          ?.messages
                                          .isNotEmpty ??
                                      false),
                            ),
                          ),
                        ),
                  body: hasPersistentHistory
                      ? SafeArea(
                          bottom: false,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                key: const ValueKey(
                                  'assistant-desktop-history-pane',
                                ),
                                width: historyPaneWidth,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: tokens.surface,
                                    border: Border(
                                      right: BorderSide(color: tokens.border),
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: _buildHistoryContent(
                                      context,
                                      controller,
                                      resourceLibrary,
                                      showsStudyMode: showsStudyMode,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    _buildWorkspaceHeader(
                                      context,
                                      controller,
                                      canPop: canPop,
                                    ),
                                    Expanded(child: assistantWorkspace),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Semantics(
                          customSemanticsActions: {
                            CustomSemanticsAction(
                              label: context.l10n.text('对话与资源'),
                            ): () =>
                                _scaffoldKey.currentState?.openDrawer(),
                          },
                          child: GestureDetector(
                            key: const ValueKey('assistant-history-swipe'),
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragStart: (_) =>
                                _historySwipeDistance = 0,
                            onHorizontalDragUpdate: (details) =>
                                _historySwipeDistance += details.delta.dx,
                            onHorizontalDragEnd: (details) {
                              if (_historySwipeDistance > 60 ||
                                  (_historySwipeDistance > 20 &&
                                      (details.primaryVelocity ?? 0) > 500)) {
                                _messageFocusNode.unfocus();
                                _scaffoldKey.currentState?.openDrawer();
                              }
                              _historySwipeDistance = 0;
                            },
                            onHorizontalDragCancel: () =>
                                _historySwipeDistance = 0,
                            child: assistantWorkspace,
                          ),
                        ),
                );
                if (!usesDesktopNavigation) {
                  return scaffold;
                }
                return CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    if (canPop)
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          Navigator.of(context).maybePop(),
                  },
                  child: Focus(autofocus: true, child: scaffold),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Android 左上角打开侧栏；其他手机通过右滑、窄桌面通过顶栏访问。
  List<Widget> _buildHeaderActions(
    BuildContext context,
    AiAssistantController controller, {
    required bool showHistoryButton,
    required bool showNewConversation,
  }) {
    final tokens = context.bnbuTheme;
    final quota = controller.quota;
    return [
      if (showHistoryButton)
        IconButton(
          key: const ValueKey('assistant-desktop-history'),
          tooltip: context.l10n.text('对话与资源'),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(LucideIcons.panelLeft300),
        ),
      if (showNewConversation)
        IconButton(
          key: const ValueKey('assistant-compact-new-conversation'),
          tooltip: context.l10n.text('新对话'),
          onPressed: controller.loading ? null : _startNewConversation,
          icon: const Icon(LucideIcons.squarePen300, size: 20),
        ),
      if (quota != null)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.space4),
          child: Tooltip(
            message: context.l10n.text('剩余额度'),
            child: Container(
              key: const ValueKey('assistant-quota-badge'),
              height: 24,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: tokens.space8),
              decoration: BoxDecoration(
                color: tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(tokens.radius12),
              ),
              child: BnbuText(
                quota.unlimited
                    ? '∞'
                    : _formatTokens(quota.remainingTokens ?? 0),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),

      SizedBox(width: tokens.space4),
    ];
  }

  /// 常驻侧栏布局下，只覆盖会话列的顶栏；侧栏自己占满整列高度。
  Widget _buildWorkspaceHeader(
    BuildContext context,
    AiAssistantController controller, {
    required bool canPop,
  }) {
    final tokens = context.bnbuTheme;
    return BnbuSecondaryHeader(
      child: DecoratedBox(
        key: const ValueKey('assistant-workspace-header'),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: SizedBox(
          height: _assistantHeaderHeight,
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  key: const ValueKey('assistant-desktop-back'),
                  tooltip: context.l10n.text('返回'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const BnbuBackIcon(),
                )
              else
                SizedBox(width: tokens.space16),
              Expanded(
                child: BnbuText(
                  controller.currentConversation?.title ?? '新对话',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BnbuHeaderMetrics.titleStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              ..._buildHeaderActions(
                context,
                controller,
                showHistoryButton: false,
                showNewConversation: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryDrawer(
    BuildContext context,
    AiAssistantController controller,
    AssistantResourceLibraryController? resourceLibrary, {
    required bool showsStudyMode,
  }) {
    final tokens = context.bnbuTheme;
    return Drawer(
      width: 300,
      backgroundColor: tokens.surface,
      child: SafeArea(
        child: _buildHistoryContent(
          context,
          controller,
          resourceLibrary,
          showsStudyMode: showsStudyMode,
        ),
      ),
    );
  }

  Widget _buildHistoryContent(
    BuildContext context,
    AiAssistantController controller,
    AssistantResourceLibraryController? resourceLibrary, {
    required bool showsStudyMode,
  }) {
    final tokens = context.bnbuTheme;
    return Column(
      // 顶层默认居中会让分组标题和状态行漂到侧栏中间，必须显式拉伸。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _assistantHeaderHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.isEnglish ? 'MiU' : '小U',
                key: const ValueKey('assistant-sidebar-brand'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ),
        ),
        _buildHistoryShortcut(
          context,
          key: const ValueKey('assistant-new-conversation'),
          icon: LucideIcons.squarePen300,
          title: '新对话',
          onTap: controller.loading ? null : _startNewConversation,
        ),
        SizedBox(height: tokens.space8),
        _buildHistoryShortcut(
          context,
          key: const ValueKey('assistant-resource-heading'),
          icon: LucideIcons.archive300,
          title: '资源库',
          count: resourceLibrary?.resources.length,
          onTap: resourceLibrary == null
              ? null
              : () => unawaited(
                  _showHistoryModalAfterClosingDrawer(
                    () async => _showResourceLibrary(selecting: false),
                  ),
                ),
        ),
        _buildHistoryShortcut(
          context,
          key: const ValueKey('assistant-memory-heading'),
          icon: LucideIcons.brain300,
          title: '记忆',
          count: controller.memories.length,
          onTap: () =>
              unawaited(_showHistoryModalAfterClosingDrawer(_showMemories)),
        ),
        if (resourceLibrary?.loading == true)
          _buildSidebarStatusRow(context, '正在读取')
        else if (resourceLibrary != null &&
            resourceLibrary.resources.isNotEmpty)
          for (final (index, resource)
              in resourceLibrary.resources.take(3).indexed)
            _AssistantResourcePreviewTile(
              key: ValueKey('assistant-resource-preview-$index'),
              resource: resource,
              onAdd: () {
                _attachResource(resource);
                _scaffoldKey.currentState?.closeDrawer();
              },
            ),
        if (showsStudyMode)
          _buildHistoryShortcut(
            context,
            key: const ValueKey('assistant-study-mode-heading'),
            icon: LucideIcons.graduationCap300,
            title: '学业模式',
            count: _studyDocumentCount(controller),
            onTap: () => _showStudyHistory(controller),
          ),
        _buildSidebarSectionLabel(context, '对话'),
        Expanded(
          // ListTile 的选中底色和 ink 绘制在 Material 上；让它与
          // 列表共用视口，滚动时不能越过上方固定入口。
          child: Material(
            type: MaterialType.transparency,
            clipBehavior: Clip.hardEdge,
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: tokens.space8),
              itemCount: controller.conversationHistory.length,
              itemBuilder: (context, index) {
                final conversation = controller.conversationHistory[index];
                final isPending = controller.isConversationSending(
                  conversation.id,
                );
                return _AssistantConversationTile(
                  key: ValueKey('assistant-conversation-${conversation.id}'),
                  conversationId: conversation.id,
                  selected: conversation.id == controller.currentConversationId,
                  pending: isPending,
                  title: conversation.title,
                  onTap: () => _selectConversation(conversation.id),
                  onDelete: () => _deleteConversation(conversation.id),
                );
              },
            ),
          ),
        ),
        SizedBox(height: tokens.space8),
      ],
    );
  }

  /// 侧栏分组标题：与下方对话行的标题左缘对齐，不占用整行节奏。
  Widget _buildSidebarSectionLabel(BuildContext context, String label) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.space24,
        tokens.space12,
        tokens.space16,
        tokens.space4,
      ),
      child: BnbuText(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tokens.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// 侧栏状态行，沿用与快捷行相同的行高与缩进。
  Widget _buildSidebarStatusRow(BuildContext context, String label) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space16),
      child: SizedBox(
        height: _sidebarRowHeight,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 14,
              child: BnbuActivityIndicator(color: tokens.textMuted),
            ),
            SizedBox(width: tokens.space8),
            BnbuText(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryShortcut(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    int? count,
    VoidCallback? onTap,
  }) {
    final tokens = context.bnbuTheme;
    final rowHeight = _sidebarRowHeight;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space8),
      child: ListTile(
        key: key,
        minTileHeight: rowHeight,
        minVerticalPadding: 0,
        minLeadingWidth: 18,
        contentPadding: EdgeInsets.symmetric(horizontal: tokens.space8),
        horizontalTitleGap: tokens.space8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
        ),
        leading: Icon(icon, size: 18, color: tokens.textMuted),
        // 计数放在标题行内，避免 trailing 槽固定预留 32px 横向空间。
        title: Row(
          children: [
            Expanded(
              child: BnbuText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            if (count != null && count > 0) ...[
              SizedBox(width: tokens.space8),
              BnbuText(
                '$count',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  int _studyDocumentCount(AiAssistantController controller) => controller
      .studyConversationHistory
      .map((conversation) => conversation.studyDocument?.key)
      .whereType<String>()
      .toSet()
      .length;

  Future<void> _showStudyHistory(AiAssistantController controller) async {
    final documents = <String, AssistantStudyDocument>{};
    for (final conversation in controller.studyConversationHistory) {
      final document = conversation.studyDocument;
      if (document != null) documents[document.key] = document;
    }
    final selected = await showBnbuAdaptiveModal<AssistantStudyDocument>(
      context: context,
      dialogMaxWidth: 620,
      dialogMaxHeight: 600,
      semanticLabel: context.l10n.text('学业模式'),
      builder: (modalContext, presentation) {
        final tokens = modalContext.bnbuTheme;
        return Padding(
          padding: EdgeInsets.all(tokens.space16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: BnbuText(
                      '学业模式',
                      style: Theme.of(modalContext).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.text('关闭'),
                    onPressed: () => Navigator.of(modalContext).pop(),
                    icon: const Icon(LucideIcons.x300),
                  ),
                ],
              ),
              Divider(color: tokens.border),
              Expanded(
                child: documents.isEmpty
                    ? const Center(child: BnbuText('暂无学业记录'))
                    : ListView(
                        children: [
                          for (final document in documents.values)
                            ListTile(
                              leading: const Icon(LucideIcons.fileText300),
                              title: BnbuText(document.title),
                              trailing: const Icon(LucideIcons.arrowUpRight300),
                              onTap: () =>
                                  Navigator.of(modalContext).pop(document),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    _scaffoldKey.currentState?.closeDrawer();
    await widget.onOpenStudyDocument?.call(selected);
  }

  Widget _buildConversation(
    BuildContext context,
    AiAssistantController controller,
  ) {
    final messages = controller.currentConversation?.messages ?? const [];
    final showPending = controller.isSendingCurrentConversation;
    final lastReplyIndex = messages.lastIndexWhere(
      (message) => !message.isUser,
    );
    if (messages.isEmpty && !showPending) {
      return _buildEmptyState(context);
    }
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        context.bnbuTheme.space16,
        context.bnbuTheme.space16,
        context.bnbuTheme.space16,
        context.bnbuTheme.space24,
      ),
      itemCount: messages.length + (showPending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          final pending = controller.pendingTurnForConversation(
            controller.currentConversationId ?? '',
          );
          return _AssistantThinkingRow(
            activities:
                pending?.activities ??
                const [AssistantActivity(label: '小U正在处理', completed: false)],
          );
        }
        return _AssistantMessageRow(
          message: messages[index],
          branchSwitcher:
              index == lastReplyIndex &&
                  controller.currentConversationBranches.length > 1
              ? _buildBranchSwitcher(context, controller)
              : null,
          onAction: _previewAction,
          onCopy: () => _copyMessage(messages[index]),
          onEdit: messages[index].isUser && !showPending
              ? () => _editUserMessage(messages[index])
              : null,
          onRegenerate:
              !messages[index].isUser &&
                  !messages[index].isError &&
                  !showPending
              ? () => unawaited(
                  controller.regenerateAssistantMessage(messages[index]),
                )
              : null,
          onFeedback: !messages[index].isUser && !messages[index].isError
              ? (feedback) => unawaited(
                  controller.setMessageFeedback(messages[index], feedback),
                )
              : null,
          onRetry: messages[index].canRetry && index == messages.length - 1
              ? () => unawaited(controller.retryFailedMessage(messages[index]))
              : null,
          onMemorySuggestionSave: (suggestion, edit) => unawaited(
            _saveMemorySuggestion(messages[index], suggestion, edit: edit),
          ),
          onMemorySuggestionDismiss: (suggestion) => unawaited(
            controller.dismissMemorySuggestion(messages[index], suggestion),
          ),
        );
      },
    );
  }

  Widget _buildBranchSwitcher(
    BuildContext context,
    AiAssistantController controller,
  ) {
    final branches = controller.currentConversationBranches;
    final index = controller.currentBranchIndex;
    final tokens = context.bnbuTheme;
    return Semantics(
      label: context.l10n.text('对话分支 ${index + 1}，共 ${branches.length} 个'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('assistant-previous-branch'),
            style: _inlineActionStyle(context, foreground: tokens.textMuted),
            tooltip: context.l10n.text('上一个分支'),
            onPressed: index > 0 ? () => _selectBranch(index - 1) : null,
            icon: const Icon(LucideIcons.chevronLeft300, size: 18),
          ),
          BnbuText(
            '${index + 1}/${branches.length}',
            key: const ValueKey('assistant-branch-position'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            key: const ValueKey('assistant-next-branch'),
            style: _inlineActionStyle(context, foreground: tokens.textMuted),
            tooltip: context.l10n.text('下一个分支'),
            onPressed: index + 1 < branches.length
                ? () => _selectBranch(index + 1)
                : null,
            icon: const Icon(LucideIcons.chevronRight300, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final suggestions = [
      '安排我今天的课程和 DDL',
      '帮我写一封课程邮件',
      '查看 iSpace 最近作业',
      '我现在在哪里？',
    ].map(context.l10n.text).toList(growable: false);
    final tokens = context.bnbuTheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        tokens.space24,
        tokens.space32 + tokens.space24,
        tokens.space24,
        tokens.space24,
      ),
      children: [
        const Center(child: SmallULogo(size: 76, monochrome: true)),
        SizedBox(height: tokens.space16),
        BnbuText(
          '今天想做什么？',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: tokens.space24),
        Wrap(
          spacing: tokens.space8,
          runSpacing: tokens.space8,
          alignment: WrapAlignment.center,
          children: suggestions
              .map(
                (suggestion) => ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    _messageController.text = suggestion;
                    _messageController.selection = TextSelection.collapsed(
                      offset: suggestion.length,
                    );
                  },
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildComposer(
    BuildContext context,
    AiAssistantController controller,
  ) {
    final capabilities = controller.capabilities;
    final unavailable =
        !controller.enabled || capabilities == null || !capabilities.available;
    final sendingCurrentConversation = controller.isSendingCurrentConversation;
    final tokens = context.bnbuTheme;
    _scheduleComposerAvoidanceReport();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.space12,
          tokens.space8,
          tokens.space12,
          tokens.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.currentSuggestions.isNotEmpty) ...[
              _AssistantSuggestionStrip(
                suggestions: controller.currentSuggestions,
                enabled: !unavailable && !sendingCurrentConversation,
                onSelected: _selectSuggestion,
              ),
              SizedBox(height: tokens.space8),
            ],
            ListenableBuilder(
              listenable: _messageFocusNode,
              builder: (context, _) {
                final focused = _messageFocusNode.hasFocus;
                return DecoratedBox(
                  key: const ValueKey('assistant-composer-surface'),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(tokens.radius24),
                    border: Border.all(
                      color: focused
                          ? tokens.brandBlue
                          : tokens.border.withValues(alpha: 0.82),
                      width: focused ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.22
                              : 0.07,
                        ),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    key: _composerContentKey,
                    padding: EdgeInsets.all(tokens.space8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_attachments.isNotEmpty) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: tokens.space8,
                              runSpacing: tokens.space8,
                              children: [
                                for (
                                  var index = 0;
                                  index < _attachments.length;
                                  index++
                                )
                                  _AssistantAttachmentCard(
                                    key: ValueKey(
                                      'assistant-attachment-$index',
                                    ),
                                    attachment: _attachments[index],
                                    enabled: controller.enabled,
                                    onRemove: () {
                                      _replaceAttachments([
                                        ..._attachments.take(index),
                                        ..._attachments.skip(index + 1),
                                      ]);
                                    },
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: tokens.space8),
                        ],
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            // Keep the lower controls fixed while making the
                            // prompt field about 70% taller than its previous
                            // one-line resting state.
                            minHeight: _usesPointerDensity ? 54 : 58,
                          ),
                          child: CallbackShortcuts(
                            bindings:
                                Platform.isMacOS ||
                                    Platform.isWindows ||
                                    Platform.isLinux
                                ? <ShortcutActivator, VoidCallback>{
                                    const SingleActivator(
                                      LogicalKeyboardKey.enter,
                                    ): _send,
                                    const SingleActivator(
                                      LogicalKeyboardKey.enter,
                                      shift: true,
                                    ): _insertComposerNewLine,
                                  }
                                : const <ShortcutActivator, VoidCallback>{},
                            child: TextField(
                              key: const ValueKey('assistant-composer-input'),
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              onTapOutside: (_) => _messageFocusNode.unfocus(),
                              enabled: controller.enabled,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 4000,
                              textInputAction: TextInputAction.newline,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: _usesPointerDensity ? 14 : 16,
                                    height: 1.4,
                                    color: tokens.textPrimary,
                                  ),
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                fillColor: Colors.transparent,
                                hintText: context.l10n.text('问问小U'),
                                counterText: '',
                                contentPadding: EdgeInsets.fromLTRB(
                                  tokens.space8,
                                  18,
                                  tokens.space8,
                                  18,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              key: const ValueKey('assistant-add-content'),
                              tooltip: context.l10n.text('添加内容'),
                              onPressed: unavailable
                                  ? null
                                  : _showAttachmentSources,
                              style: IconButton.styleFrom(
                                minimumSize: Size.square(_composerButtonExtent),
                                maximumSize: Size.square(_composerButtonExtent),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: Colors.transparent,
                                foregroundColor: tokens.textPrimary,
                              ),
                              iconSize: 20,
                              icon: const Icon(LucideIcons.plus300),
                            ),
                            SizedBox(width: tokens.space8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _SmartThinkingControl(
                                  mode: controller.thinkingMode,
                                  enabled: !unavailable,
                                  onChanged: controller.setThinkingMode,
                                ),
                              ),
                            ),
                            SizedBox(width: tokens.space8),
                            _ComposerSendButton(
                              enabled:
                                  !unavailable && !sendingCurrentConversation,
                              onPressed: _send,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<List<AssistantInputAttachment>> _pickAssistantAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'txt',
        'md',
        'csv',
        'json',
        'xml',
        'yaml',
        'yml',
        'log',
        'pdf',
        'doc',
        'docx',
        'ppt',
        'pptx',
        'xls',
        'xlsx',
        'zip',
        '7z',
      ],
      allowMultiple: true,
      withData: false,
      withReadStream: true,
    );
    if (result == null) {
      return const [];
    }
    final attachments = <AssistantInputAttachment>[];
    for (final file in result.files.take(3)) {
      final mimeType = _assistantAttachmentMimeType(file.name);
      if (mimeType == null) {
        throw AiAssistantException('${file.name} 的格式暂不支持。');
      }
      if (_isLocalAssignmentFile(file.name)) {
        final path = file.path?.trim() ?? '';
        if (path.isEmpty || file.size <= 0) {
          throw AiAssistantException('${file.name} 无法作为本机作业文件读取。');
        }
        if (file.size > AssistantAttachmentLimits.maxFileBytes) {
          throw AiAssistantException('${file.name} 超过 50 MB。');
        }
        attachments.add(
          AssistantInputAttachment(
            name: file.name,
            mimeType: mimeType,
            bytes: Uint8List(0),
            localFilePath: path,
            localByteCount: file.size,
          ),
        );
        continue;
      }
      const maxBytes = AssistantAttachmentLimits.maxFileBytes;
      final bytes = await _readPickedAttachment(file, maxBytes: maxBytes);
      attachments.add(
        AssistantInputAttachment(
          name: file.name,
          mimeType: mimeType,
          bytes: bytes,
        ),
      );
    }
    return attachments;
  }

  Future<Uint8List> _readPickedAttachment(
    PlatformFile file, {
    required int maxBytes,
  }) async {
    if (file.size <= 0 || file.size > maxBytes) {
      throw AiAssistantException(
        file.size > maxBytes ? '${file.name} 超过 50 MB。' : '${file.name} 是空文件。',
      );
    }
    final stream =
        file.readStream ??
        (file.path?.trim().isNotEmpty == true
            ? File(file.path!).openRead()
            : null);
    if (stream == null) {
      throw const AiAssistantException('无法读取所选附件，请重新选择。');
    }
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in stream) {
      received += chunk.length;
      if (received > maxBytes) {
        throw AiAssistantException('${file.name} 超过允许的大小。');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw AiAssistantException('${file.name} 是空文件。');
    }
    return bytes;
  }

  Future<void> _previewAction(AssistantAction action) async {
    final controller = widget.assistantController;
    final definition = AssistantToolRegistry.definitionFor(action.type);
    if (definition.requiresConfirmation && !action.requiresConfirmation) {
      controller.reportError('小U返回了未声明确认要求的操作，已阻止执行。');
      return;
    }
    if (definition.isUnsupported) {
      controller.reportError(definition.unsupportedReason);
      return;
    }

    if ({
      AssistantActionType.startQuizAttempt,
      AssistantActionType.saveQuizAnswers,
      AssistantActionType.submitQuizAttempt,
    }.contains(action.type)) {
      final confirmed = await _confirmQuizAction(action);
      if (!confirmed) return;
    }

    try {
      // Tapping an assistant action only authorizes navigation into the native
      // workflow. Destructive or externally visible effects remain behind the
      // destination page's own final button.
      await widget.onExecuteAction(
        action,
        userConfirmed: action.requiresConfirmation,
      );
    } catch (error) {
      controller.reportError(error);
    }
  }

  Future<bool> _confirmQuizAction(AssistantAction action) async {
    final isSubmit = action.type == AssistantActionType.submitQuizAttempt;
    final isStart = action.type == AssistantActionType.startQuizAttempt;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: BnbuText(
              isStart
                  ? '确认开始 Quiz'
                  : isSubmit
                  ? '确认最终交卷'
                  : '确认保存答案',
            ),
            content: BnbuText(
              isStart
                  ? '将创建新的作答 attempt。开始后，小U需要重新读取题目。'
                  : isSubmit
                  ? '将提交 ${action.quizResponses.length} 个答案字段并结束本次 attempt。提交后不可撤回。'
                  : '将保存 ${action.quizResponses.length} 个答案字段，保留本次 attempt，尚不会交卷。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const BnbuText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: BnbuText(
                  isSubmit
                      ? '最终交卷'
                      : isStart
                      ? '开始'
                      : '保存答案',
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  // Kept temporarily for compatibility with downstream native editor work.
  // ignore: unused_element
  Future<bool> _confirmNativeHandoffAction(AssistantAction action) async {
    final (title, summary, confirmLabel, details) = switch (action.type) {
      AssistantActionType.downloadAttachment => (
        '确认附件下载',
        '小U会打开原生邮件详情，重新校验附件后才开始下载。',
        '打开邮件并下载',
        [
          ('附件', action.attachmentName),
          ('邮箱', action.mailFolder),
          ('邮件 UID', action.mailUid?.toString() ?? ''),
        ],
      ),
      AssistantActionType.batchDownloadCourseFiles => (
        '确认打包课程资料',
        '小U会重新读取原生课程文件清单，按要求预选并分类显示文件；'
            '显示实际数量与大小供你确认后，App 会自动下载并在本机生成 ZIP。',
        '读取并打包',
        [('课程 ID', action.targetId)],
      ),
      AssistantActionType.uploadAssignmentFile => (
        '确认作业文件上传',
        '小U只会打开原生作业页和文件选择器，不会自动提交文件。',
        '打开文件选择器',
        [('作业 ID', action.targetId)],
      ),
      AssistantActionType.deleteMail => (
        '确认删除邮件',
        '小U会前往原生邮箱重新读取邮件；删除前仍需在邮箱页面最终确认。',
        '前往邮箱确认删除',
        [
          ('邮箱', action.mailFolder),
          ('邮件 UID', action.mailUid?.toString() ?? ''),
        ],
      ),
      AssistantActionType.restoreMail => (
        '确认恢复邮件',
        '小U会前往原生邮箱重新读取邮件；恢复前仍需在邮箱页面最终确认。',
        '前往邮箱确认恢复',
        [
          ('邮箱', action.mailFolder),
          ('邮件 UID', action.mailUid?.toString() ?? ''),
        ],
      ),
      _ => throw StateError('该动作不使用原生交接预览。'),
    };

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: BnbuText(title),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BnbuText(summary),
                  const SizedBox(height: 16),
                  for (final detail in details)
                    if (detail.$2.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BnbuText(
                              detail.$1,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 2),
                            SelectableText(detail.$2),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const BnbuText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: BnbuText(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ignore: unused_element
  Future<bool> _confirmAction(AssistantAction action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const BnbuText('确认操作'),
            content: BnbuText(action.title),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const BnbuText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const BnbuText('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ignore: unused_element
  Future<bool> _confirmNotificationAction(AssistantAction action) async {
    final scheduledAt = action.notificationAt?.toLocal();
    final timeLabel = scheduledAt == null
        ? '时间缺失'
        : context.l10n.formatFullDateTime(scheduledAt);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const BnbuText('确认设置提醒'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BnbuText(
                  action.notificationTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                BnbuText(action.notificationBody),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(LucideIcons.clock3300, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: BnbuText(timeLabel)),
                  ],
                ),
                const SizedBox(height: 12),
                BnbuText(
                  '确认后将由这台设备创建本地通知。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const BnbuText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const BnbuText('设置提醒'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ignore: unused_element
  Future<AssistantAction?> _editEmailAction(AssistantAction action) async {
    var recipient = action.recipient;
    var subject = action.subject;
    var body = action.body;
    return showDialog<AssistantAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('确认邮件草稿'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: recipient,
                  onChanged: (value) => recipient = value,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('收件人'),
                  ),
                ),
                TextFormField(
                  initialValue: subject,
                  onChanged: (value) => subject = value,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('主题'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: body,
                  onChanged: (value) => body = value,
                  minLines: 7,
                  maxLines: 14,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('正文'),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              action.copyWith(
                recipient: recipient,
                subject: subject,
                body: body,
              ),
            ),
            child: const BnbuText('打开写邮件'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<AssistantAction?> _editAssignmentAction(AssistantAction action) async {
    var body = action.body;
    return showDialog<AssistantAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('确认在线文本草稿'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BnbuText(
                action.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: body,
                onChanged: (value) => body = value,
                minLines: 9,
                maxLines: 16,
                decoration: InputDecoration(
                  labelText: context.l10n.text('在线文本'),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(action.copyWith(body: body)),
            child: const BnbuText('打开作业页'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<AssistantAction?> _editTaCourseAction(AssistantAction action) async {
    final formKey = GlobalKey<FormState>();
    var title = action.taTitle;
    var location = action.taLocation;
    var startTime = _formatTaTime(action.taStartMinutes ?? 9 * 60);
    var endTime = _formatTaTime(action.taEndMinutes ?? 9 * 60 + 50);
    var weekday = action.taWeekday ?? DateTime.monday;
    var repeatType = action.taRepeatType == 'singleWeek'
        ? 'singleWeek'
        : 'weekly';
    var weekStart = action.taWeekStart;
    return showDialog<AssistantAction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: BnbuText(
            action.type == AssistantActionType.addTaCourse
                ? '确认新增 TA 课'
                : '确认编辑 TA 课',
          ),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: title,
                      maxLength: 160,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('名称'),
                      ),
                      onChanged: (value) => title = value,
                      validator: (value) =>
                          value?.trim().isEmpty ?? true ? '请输入 TA 课名称' : null,
                    ),
                    TextFormField(
                      initialValue: location,
                      maxLength: 160,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('地点'),
                      ),
                      onChanged: (value) => location = value,
                    ),
                    BnbuDropdownFormField<int>(
                      initialValue: weekday,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('星期'),
                      ),
                      items: List.generate(
                        7,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: BnbuText(_weekdayLabel(index + 1)),
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => weekday = value);
                        }
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: startTime,
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: context.l10n.text('开始时间'),
                              hintText: '09:00',
                            ),
                            onChanged: (value) => startTime = value,
                            validator: (value) =>
                                _parseTaTime(value, allowEndOfDay: false) ==
                                    null
                                ? '请输入 00:00–23:59'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: endTime,
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: context.l10n.text('结束时间'),
                              hintText: '09:50',
                            ),
                            onChanged: (value) => endTime = value,
                            validator: (value) =>
                                _parseTaTime(value, allowEndOfDay: true) == null
                                ? '请输入 00:01–24:00'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    BnbuDropdownFormField<String>(
                      initialValue: repeatType,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('重复方式'),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'weekly',
                          child: BnbuText('每周'),
                        ),
                        DropdownMenuItem(
                          value: 'singleWeek',
                          child: BnbuText('仅一周'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => repeatType = value);
                        }
                      },
                    ),
                    if (repeatType == 'singleWeek')
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const BnbuText('适用周'),
                        subtitle: BnbuText(
                          weekStart == null
                              ? '请选择该周任意一天'
                              : _formatTaDate(weekStart!),
                        ),
                        trailing: const Icon(LucideIcons.calendarDays300),
                        onTap: () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: weekStart ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 366),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 366 * 3),
                            ),
                          );
                          if (selected != null) {
                            setDialogState(() => weekStart = selected);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const BnbuText('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) {
                  return;
                }
                final startMinutes = _parseTaTime(
                  startTime,
                  allowEndOfDay: false,
                )!;
                final endMinutes = _parseTaTime(endTime, allowEndOfDay: true)!;
                if (endMinutes <= startMinutes) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: BnbuText('结束时间必须晚于开始时间')),
                  );
                  return;
                }
                if (repeatType == 'singleWeek' && weekStart == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: BnbuText('请选择 TA 课适用周')),
                  );
                  return;
                }
                Navigator.of(context).pop(
                  action.copyWith(
                    taTitle: title.trim(),
                    taLocation: location.trim(),
                    taWeekday: weekday,
                    taStartMinutes: startMinutes,
                    taEndMinutes: endMinutes,
                    taRepeatType: repeatType,
                    taWeekStart: weekStart,
                    clearTaWeekStart: repeatType == 'weekly',
                  ),
                );
              },
              child: const BnbuText('打开原生编辑器'),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<AssistantAction?> _confirmDeleteTaCourseAction(
    AssistantAction action,
  ) async {
    final time = action.taStartMinutes == null || action.taEndMinutes == null
        ? ''
        : '${_formatTaTime(action.taStartMinutes!)}–${_formatTaTime(action.taEndMinutes!)}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('确认删除 TA 课'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BnbuText(
              action.taTitle.trim().isEmpty ? action.title : action.taTitle,
            ),
            if (action.taLocation.trim().isNotEmpty)
              BnbuText(action.taLocation),
            if (action.taWeekday != null && time.isNotEmpty)
              BnbuText('${_weekdayLabel(action.taWeekday!)} $time'),
            const SizedBox(height: 12),
            const BnbuText('打开 TA 课管理页后还会再次要求确认。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const BnbuText('继续'),
          ),
        ],
      ),
    );
    return confirmed == true ? action : null;
  }

  int? _parseTaTime(String? value, {required bool allowEndOfDay}) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(value?.trim() ?? '');
    if (match == null) {
      return null;
    }
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || minute < 0 || minute > 59) {
      return null;
    }
    if (allowEndOfDay && hour == 24 && minute == 0) {
      return 24 * 60;
    }
    if (hour < 0 || hour > 23) {
      return null;
    }
    final result = hour * 60 + minute;
    if (allowEndOfDay && result == 0) {
      return null;
    }
    return result;
  }

  String _formatTaTime(int minutes) {
    if (minutes == 24 * 60) {
      return '24:00';
    }
    final safe = minutes.clamp(0, 24 * 60 - 1);
    return '${(safe ~/ 60).toString().padLeft(2, '0')}:'
        '${(safe % 60).toString().padLeft(2, '0')}';
  }

  String _weekdayLabel(int weekday) {
    const labels = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return weekday >= 1 && weekday <= labels.length
        ? labels[weekday - 1]
        : '星期';
  }

  String _formatTaDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTokens(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }
}

class _EditAssistantMessageForm extends StatefulWidget {
  const _EditAssistantMessageForm({
    required this.initialText,
    required this.isDialog,
  });

  final String initialText;
  final bool isDialog;

  @override
  State<_EditAssistantMessageForm> createState() =>
      _EditAssistantMessageFormState();
}

class _EditAssistantMessageFormState extends State<_EditAssistantMessageForm> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.space16,
        widget.isDialog ? tokens.space16 : 0,
        tokens.space16,
        tokens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: BnbuText(
                  '编辑消息',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (widget.isDialog)
                IconButton(
                  tooltip: context.l10n.text('关闭'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x300),
                ),
            ],
          ),
          SizedBox(height: tokens.space12),
          TextField(
            key: const ValueKey('assistant-edit-message-field'),
            controller: _controller,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: context.l10n.text('消息'),
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          SizedBox(height: tokens.space12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {
                final value = _controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.of(context).pop(value);
                }
              },
              icon: const Icon(LucideIcons.gitBranch300, size: 18),
              label: const BnbuText('从这里发送'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantConversationTile extends StatefulWidget {
  const _AssistantConversationTile({
    super.key,
    required this.conversationId,
    required this.selected,
    required this.pending,
    required this.title,
    required this.onTap,
    required this.onDelete,
  });

  final String conversationId;
  final bool selected;
  final bool pending;
  final String title;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_AssistantConversationTile> createState() =>
      _AssistantConversationTileState();
}

class _AssistantConversationTileState
    extends State<_AssistantConversationTile> {
  bool _hovered = false;
  bool _menuFocused = false;
  bool _menuOpen = false;

  bool get _usesHoverDisclosure => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  bool get _showMenuButton =>
      !_usesHoverDisclosure || _hovered || _menuFocused || _menuOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final rowHeight = _sidebarRowHeight;
    final baseTitleStyle = Theme.of(context).textTheme.bodyLarge;
    final compactTitleStyle = baseTitleStyle?.copyWith(
      fontSize: (baseTitleStyle.fontSize ?? 16) * 0.85,
      letterSpacing: 0,
      fontWeight: widget.selected ? FontWeight.w600 : baseTitleStyle.fontWeight,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ListTile(
        dense: true,
        minTileHeight: rowHeight,
        minVerticalPadding: 0,
        horizontalTitleGap: tokens.space8,
        visualDensity: const VisualDensity(vertical: -4),
        tileColor: Colors.transparent,
        selectedTileColor: tokens.surfaceMuted,
        selectedColor: tokens.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
        ),
        contentPadding: EdgeInsets.only(
          left: tokens.space16,
          right: tokens.space8,
        ),
        selected: widget.selected,
        title: BnbuText(
          widget.title,
          key: ValueKey(
            'assistant-conversation-title-${widget.conversationId}',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: compactTitleStyle,
        ),
        // 回复进行中时把指示器放在尾部槽位，标题左缘不再左右跳动。
        trailing: FocusScope(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) {
            if (_menuFocused != focused) {
              setState(() => _menuFocused = focused);
            }
          },
          child: widget.pending
              ? SizedBox.square(
                  dimension: rowHeight,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 14,
                      child: BnbuActivityIndicator(color: tokens.textMuted),
                    ),
                  ),
                )
              : AnimatedOpacity(
                  opacity: _showMenuButton ? 1 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  child: BnbuMenuButton<_ConversationAction>(
                    key: ValueKey(
                      'assistant-conversation-menu-${widget.conversationId}',
                    ),
                    enabled: !widget.pending,
                    tooltip: context.l10n.text('更多操作'),
                    icon: const Icon(LucideIcons.ellipsis300, size: 18),
                    padding: EdgeInsets.zero,
                    position: PopupMenuPosition.under,
                    style: IconButton.styleFrom(
                      minimumSize: Size.square(rowHeight),
                      maximumSize: Size.square(rowHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onOpened: () => setState(() => _menuOpen = true),
                    onCanceled: () => setState(() => _menuOpen = false),
                    onSelected: (action) {
                      setState(() => _menuOpen = false);
                      switch (action) {
                        case _ConversationAction.delete:
                          widget.onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      BnbuMenuItem(
                        value: _ConversationAction.delete,
                        icon: LucideIcons.trash2300,
                        destructive: true,
                        child: const BnbuText('删除对话'),
                      ),
                    ],
                  ),
                ),
        ),
        onTap: widget.onTap,
      ),
    );
  }
}

class _AssistantSuggestionStrip extends StatelessWidget {
  const _AssistantSuggestionStrip({
    required this.suggestions,
    required this.enabled,
    required this.onSelected,
  });

  final List<AssistantSuggestion> suggestions;
  final bool enabled;
  final ValueChanged<AssistantSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Semantics(
      container: true,
      label: context.l10n.text('小U提供了${suggestions.length}个选项'),
      child: SizedBox(
        key: const ValueKey('assistant-suggestion-strip'),
        width: double.infinity,
        child: Column(
          children: [
            for (var index = 0; index < suggestions.length; index++) ...[
              Semantics(
                button: true,
                label: context.l10n.text(
                  suggestions[index].isOther
                      ? '其他，自行输入'
                      : '选择${suggestions[index].label}',
                ),
                child: OutlinedButton(
                  key: ValueKey('assistant-suggestion-$index'),
                  onPressed: enabled
                      ? () => onSelected(suggestions[index])
                      : null,
                  style: ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(
                      Size(double.infinity, _usesPointerDensity ? 38 : 48),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(
                        horizontal: tokens.space12,
                        vertical: tokens.space8,
                      ),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radius12),
                      ),
                    ),
                    side: WidgetStateProperty.resolveWith((states) {
                      return BorderSide(
                        color: states.contains(WidgetState.focused)
                            ? tokens.brandBlue
                            : tokens.border,
                        width: states.contains(WidgetState.focused) ? 1.6 : 1,
                      );
                    }),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.pressed)) {
                        return tokens.brandBlue.withValues(alpha: 0.12);
                      }
                      if (states.contains(WidgetState.focused)) {
                        return tokens.surfaceMuted;
                      }
                      return tokens.surface;
                    }),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: BnbuText(
                          suggestions[index].label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(width: tokens.space8),
                      Icon(
                        suggestions[index].isOther
                            ? LucideIcons.penLine300
                            : LucideIcons.arrowRight300,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (index != suggestions.length - 1)
                SizedBox(height: tokens.space8),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmartThinkingControl extends StatelessWidget {
  const _SmartThinkingControl({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final AssistantThinkingMode mode;
  final bool enabled;
  final Future<void> Function(AssistantThinkingMode mode) onChanged;

  @override
  Widget build(BuildContext context) {
    final high = mode == AssistantThinkingMode.high;
    final current = high
        ? AssistantThinkingMode.high
        : AssistantThinkingMode.low;
    final next = high ? AssistantThinkingMode.low : AssistantThinkingMode.high;
    final description = context.l10n.text(high ? 'High，复杂问题' : 'Low，简单问题');
    return Semantics(
      key: const ValueKey('assistant-thinking-mode-control'),
      button: true,
      enabled: enabled,
      label: context.l10n.text('选择思考强度'),
      value: current.label,
      child: IconButton(
        key: const ValueKey('assistant-thinking-mode-toggle'),
        tooltip: description,
        onPressed: enabled ? () => unawaited(onChanged(next)) : null,
        style: IconButton.styleFrom(
          minimumSize: Size.square(_composerButtonExtent),
          maximumSize: Size.square(_composerButtonExtent),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: Colors.transparent,
          foregroundColor: context.bnbuTheme.textPrimary,
        ),
        icon: Icon(
          high ? LucideIcons.brain300 : LucideIcons.messageCircle300,
          size: 20,
        ),
      ),
    );
  }
}

class _ComposerSendButton extends StatelessWidget {
  const _ComposerSendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final hitExtent = _composerButtonExtent;
    final visibleExtent = hitExtent * 0.84;
    final foreground = enabled
        ? Theme.of(context).colorScheme.onPrimary
        : tokens.textMuted;
    return IconButton(
      key: const ValueKey('assistant-send-button'),
      tooltip: context.l10n.text('发送'),
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        minimumSize: Size.square(hitExtent),
        maximumSize: Size.square(hitExtent),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: foreground,
        disabledForegroundColor: tokens.textMuted,
        shape: const CircleBorder(),
      ),
      icon: Container(
        key: const ValueKey('assistant-send-button-visible'),
        width: visibleExtent,
        height: visibleExtent,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? tokens.brandBlue : tokens.surfaceMuted,
        ),
        child: Icon(
          LucideIcons.arrowUp300,
          size: visibleExtent * 0.5,
          color: foreground,
        ),
      ),
    );
  }
}

class _AttachmentSourceButton extends StatelessWidget {
  const _AttachmentSourceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radius16),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: tokens.textPrimary, size: 23),
            ),
            SizedBox(height: tokens.space8),
            BnbuText(
              label,
              maxLines: 1,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantResourcePreviewTile extends StatelessWidget {
  const _AssistantResourcePreviewTile({
    super.key,
    required this.resource,
    required this.onAdd,
  });

  final AssistantResourceItem resource;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final rowHeight = _sidebarRowHeight;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space8),
      child: ListTile(
        minTileHeight: rowHeight,
        minVerticalPadding: 0,
        minLeadingWidth: 18,
        // 预览行是“资源库”的下级，缩进一档但沿用同一行节奏。
        contentPadding: EdgeInsets.only(
          left: tokens.space16,
          right: tokens.space4,
        ),
        horizontalTitleGap: tokens.space8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
        ),
        leading: Icon(
          LucideIcons.folderArchive300,
          color: tokens.textMuted,
          size: 16,
        ),
        title: BnbuText(
          resource.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: tokens.textSecondary),
        ),
        trailing: IconButton(
          tooltip: context.l10n.text('添加 ${resource.fileName}'),
          onPressed: onAdd,
          iconSize: 16,
          style: IconButton.styleFrom(
            minimumSize: Size.square(rowHeight),
            maximumSize: Size.square(rowHeight),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: tokens.textMuted,
          ),
          icon: const Icon(LucideIcons.circlePlus300),
        ),
        onTap: onAdd,
      ),
    );
  }
}

class _AssistantResourceTile extends StatelessWidget {
  const _AssistantResourceTile({
    required this.resource,
    required this.selecting,
    required this.onTap,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
  });

  final AssistantResourceItem resource;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return ListTile(
      contentPadding: EdgeInsets.fromLTRB(
        tokens.space16,
        tokens.space4,
        tokens.space8,
        tokens.space4,
      ),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.brandBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(tokens.radius12),
        ),
        child: Icon(LucideIcons.folderArchive300, color: tokens.brandBlue),
      ),
      title: BnbuText(
        resource.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: BnbuText(
        '${resource.sourceTitle} · '
        '${_formatAttachmentSize(resource.byteCount)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selecting
          ? IconButton(
              tooltip: context.l10n.text('添加到对话'),
              onPressed: onAdd,
              icon: const Icon(LucideIcons.circlePlus300),
            )
          : BnbuMenuButton<_ResourceAction>(
              tooltip: context.l10n.text('资源操作'),
              onSelected: (action) {
                switch (action) {
                  case _ResourceAction.open:
                    onOpen();
                  case _ResourceAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _ResourceAction.open,
                  child: BnbuText('打开'),
                ),
                PopupMenuItem(
                  value: _ResourceAction.delete,
                  child: BnbuText('删除'),
                ),
              ],
            ),
      onTap: onTap,
    );
  }
}

enum _ResourceAction { open, delete }

class _ResourceLibraryEmptyState extends StatelessWidget {
  const _ResourceLibraryEmptyState({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.archive200, size: 34, color: tokens.textMuted),
            SizedBox(height: tokens.space12),
            BnbuText(
              error ?? '资源库为空',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantAttachmentCard extends StatelessWidget {
  const _AssistantAttachmentCard({
    super.key,
    required this.attachment,
    required this.enabled,
    required this.onRemove,
  });

  final AssistantInputAttachment attachment;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final isImage = attachment.mimeType.startsWith('image/');
    final isResource = attachment.isResourceReference;
    final mailReference = attachment.mailReference;
    final isMailReference = mailReference != null;
    return Semantics(
      container: true,
      label: context.l10n.text('已添加附件 ${attachment.name}'),
      child: Container(
        width: 224,
        height: 60,
        padding: EdgeInsets.all(tokens.space8),
        decoration: BoxDecoration(
          color: tokens.surfaceMuted,
          borderRadius: BorderRadius.circular(tokens.radius12),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.brandBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isResource
                    ? LucideIcons.archive300
                    : isMailReference
                    ? LucideIcons.mail300
                    : isImage
                    ? LucideIcons.image300
                    : LucideIcons.file300,
                color: tokens.brandBlue,
                size: 22,
              ),
            ),
            SizedBox(width: tokens.space8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BnbuText(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  BnbuText(
                    isMailReference
                        ? (mailReference.isMessage ? '已附加邮件' : '已附加邮件草稿')
                        : '${isResource
                                  ? '资源库引用'
                                  : isImage
                                  ? '图片'
                                  : '文件'} · '
                              '${_formatAttachmentSize(attachment.effectiveByteCount)}',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.text('移除 ${attachment.name}'),
              onPressed: enabled ? onRemove : null,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              icon: const Icon(LucideIcons.x300, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatAttachmentSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

/// 消息行内图标操作的统一紧凑样式：桌面 28px、触控 44px 命中区。
ButtonStyle _inlineActionStyle(BuildContext context, {Color? foreground}) {
  return IconButton.styleFrom(
    minimumSize: Size.square(_inlineActionExtent),
    maximumSize: Size.square(_inlineActionExtent),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: foreground,
  );
}

class _AssistantUserMessageAttachments extends StatelessWidget {
  const _AssistantUserMessageAttachments({required this.message});

  final AssistantStoredMessage message;

  AssistantInputAttachment? _runtimeImageFor(
    AssistantAttachmentReference reference,
    int index,
  ) {
    if (reference.kind != AssistantAttachmentReferenceKind.image) return null;
    final ordinaryRuntimeAttachments = message.runtimeAttachments
        .where((attachment) => !attachment.isMailReference)
        .toList(growable: false);
    if (index < ordinaryRuntimeAttachments.length) {
      final candidate = ordinaryRuntimeAttachments[index];
      if (candidate.name == reference.name &&
          candidate.mimeType.startsWith('image/') &&
          candidate.bytes.isNotEmpty) {
        return candidate;
      }
    }
    for (final candidate in ordinaryRuntimeAttachments) {
      if (candidate.name == reference.name &&
          candidate.mimeType.startsWith('image/') &&
          candidate.bytes.isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Column(
      key: const ValueKey('assistant-user-attachment-list'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (
          var index = 0;
          index < message.attachmentReferences.length;
          index++
        )
          Padding(
            padding: EdgeInsets.only(
              bottom:
                  index + 1 < message.attachmentReferences.length ||
                      message.mailReferences.isNotEmpty
                  ? tokens.space4
                  : 0,
            ),
            child: _AssistantUserMessageAttachmentCard(
              key: ValueKey('assistant-user-attachment-$index'),
              name: message.attachmentReferences[index].name,
              kind: message.attachmentReferences[index].kind,
              runtimeImage: _runtimeImageFor(
                message.attachmentReferences[index],
                index,
              ),
            ),
          ),
        for (var index = 0; index < message.mailReferences.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index + 1 < message.mailReferences.length
                  ? tokens.space4
                  : 0,
            ),
            child: _AssistantUserMessageAttachmentCard(
              key: ValueKey('assistant-user-mail-attachment-$index'),
              name: message.mailReferences[index].displayName,
              mailReference: message.mailReferences[index],
            ),
          ),
      ],
    );
  }
}

class _AssistantUserMessageAttachmentCard extends StatelessWidget {
  const _AssistantUserMessageAttachmentCard({
    super.key,
    required this.name,
    this.kind,
    this.runtimeImage,
    this.mailReference,
  });

  final String name;
  final AssistantAttachmentReferenceKind? kind;
  final AssistantInputAttachment? runtimeImage;
  final AssistantMailReference? mailReference;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final leading = runtimeImage == null
        ? Icon(
            mailReference != null
                ? LucideIcons.mail300
                : kind == AssistantAttachmentReferenceKind.resource
                ? LucideIcons.archive300
                : kind == AssistantAttachmentReferenceKind.image
                ? LucideIcons.image300
                : LucideIcons.file300,
            size: 18,
            color: tokens.textSecondary,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              runtimeImage!.bytes,
              key: const ValueKey('assistant-user-image-thumbnail'),
              width: 34,
              height: 34,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Icon(
                LucideIcons.image300,
                size: 18,
                color: tokens.textSecondary,
              ),
            ),
          );
    return Semantics(
      container: true,
      label: context.l10n.text(
        mailReference == null ? '附件 $name' : '邮件 ${mailReference!.displayName}',
      ),
      child: Container(
        width: 224,
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space8,
          vertical: tokens.space4,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            SizedBox(width: 34, height: 34, child: Center(child: leading)),
            SizedBox(width: tokens.space8),
            Expanded(
              child: BnbuText(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessageRow extends StatelessWidget {
  const _AssistantMessageRow({
    required this.message,
    required this.onAction,
    required this.onCopy,
    this.onEdit,
    this.onRegenerate,
    this.onFeedback,
    this.onRetry,
    this.branchSwitcher,
    required this.onMemorySuggestionSave,
    required this.onMemorySuggestionDismiss,
  });

  final AssistantStoredMessage message;
  final ValueChanged<AssistantAction> onAction;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final ValueChanged<AssistantMessageFeedback?>? onFeedback;
  final VoidCallback? onRetry;
  final Widget? branchSwitcher;
  final void Function(AssistantMemorySuggestion suggestion, bool edit)
  onMemorySuggestionSave;
  final ValueChanged<AssistantMemorySuggestion> onMemorySuggestionDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    if (message.isUser) {
      final hasText = message.content.trim().isNotEmpty;
      final hasAttachments =
          message.attachmentReferences.isNotEmpty ||
          message.mailReferences.isNotEmpty;
      return Padding(
        padding: EdgeInsets.only(left: tokens.space32, bottom: tokens.space8),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasText)
                  Container(
                    key: const ValueKey('assistant-user-text-bubble'),
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.space16,
                      vertical: tokens.space12,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.brandBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(tokens.radius16),
                      border: Border.all(
                        color: tokens.brandBlue.withValues(alpha: 0.14),
                      ),
                    ),
                    child: SelectableText(message.content),
                  ),
                if (hasAttachments) ...[
                  if (hasText) SizedBox(height: tokens.space4),
                  _AssistantUserMessageAttachments(message: message),
                ],
                if (hasText)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('assistant-user-copy'),
                        tooltip: context.l10n.text('复制'),
                        onPressed: onCopy,
                        style: _inlineActionStyle(
                          context,
                          foreground: tokens.textMuted,
                        ),
                        icon: const Icon(LucideIcons.copy300, size: 16),
                      ),
                      if (onEdit != null)
                        IconButton(
                          key: const ValueKey('assistant-user-edit'),
                          tooltip: context.l10n.text('编辑并创建分支'),
                          onPressed: onEdit,
                          style: _inlineActionStyle(
                            context,
                            foreground: tokens.textMuted,
                          ),
                          icon: const Icon(LucideIcons.penLine300, size: 16),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.activities.isNotEmpty) ...[
          _AssistantActivityDisclosure(
            activities: message.activities,
            active: false,
          ),
          SizedBox(height: tokens.space12),
        ],
        if (!message.compactError)
          SafeAssistantMarkdown(
            key: const ValueKey('assistant-response-content'),
            data: message.content,
            actions: message.actions,
            onAction: onAction,
          ),
        if (message.actions.isNotEmpty) ...[
          SizedBox(height: tokens.space12),
          Wrap(
            spacing: tokens.space8,
            runSpacing: tokens.space8,
            children: message.actions
                .map(
                  (action) => FilledButton.tonalIcon(
                    onPressed: () => onAction(action),
                    icon: Icon(_actionIcon(action.type), size: 18),
                    label: BnbuText(action.title),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (message.memorySuggestions.any((item) => item.isPending)) ...[
          SizedBox(height: tokens.space12),
          _AssistantMemorySuggestionPanel(
            suggestions: message.memorySuggestions
                .where((item) => item.isPending)
                .toList(growable: false),
            onSave: (suggestion) => onMemorySuggestionSave(suggestion, false),
            onEdit: (suggestion) => onMemorySuggestionSave(suggestion, true),
            onDismiss: onMemorySuggestionDismiss,
          ),
        ],
        if (!message.compactError || branchSwitcher != null)
          Wrap(
            key: const ValueKey('assistant-response-actions'),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!message.compactError)
                IconButton(
                  key: const ValueKey('assistant-response-copy'),
                  alignment: Alignment.centerLeft,
                  tooltip: context.l10n.text('复制'),
                  onPressed: onCopy,
                  style: _inlineActionStyle(
                    context,
                    foreground: tokens.textMuted,
                  ),
                  icon: const Icon(LucideIcons.copy300, size: 16),
                ),
              if (onRegenerate != null)
                IconButton(
                  key: const ValueKey('assistant-response-regenerate'),
                  alignment: Alignment.centerLeft,
                  tooltip: context.l10n.text('重新生成并创建分支'),
                  onPressed: onRegenerate,
                  style: _inlineActionStyle(
                    context,
                    foreground: tokens.textMuted,
                  ),
                  icon: const Icon(LucideIcons.refreshCw300, size: 16),
                ),
              if (onFeedback != null) ...[
                IconButton(
                  key: const ValueKey('assistant-response-like'),
                  alignment: Alignment.centerLeft,
                  tooltip: context.l10n.text('赞'),
                  onPressed: () => onFeedback!(
                    message.feedback == AssistantMessageFeedback.up
                        ? null
                        : AssistantMessageFeedback.up,
                  ),
                  style: _inlineActionStyle(context),
                  color: message.feedback == AssistantMessageFeedback.up
                      ? tokens.brandBlue
                      : tokens.textMuted,
                  icon: const Icon(LucideIcons.thumbsUp300, size: 16),
                ),
                IconButton(
                  key: const ValueKey('assistant-response-dislike'),
                  alignment: Alignment.centerLeft,
                  tooltip: context.l10n.text('踩'),
                  onPressed: () => onFeedback!(
                    message.feedback == AssistantMessageFeedback.down
                        ? null
                        : AssistantMessageFeedback.down,
                  ),
                  style: _inlineActionStyle(context),
                  color: message.feedback == AssistantMessageFeedback.down
                      ? tokens.danger
                      : tokens.textMuted,
                  icon: const Icon(LucideIcons.thumbsDown300, size: 16),
                ),
              ],
              ?branchSwitcher,
            ],
          ),
        if (message.isError && onRetry != null) ...[
          SizedBox(height: tokens.space12),
          OutlinedButton.icon(
            key: const ValueKey('assistant-message-retry'),
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw300, size: 18),
            label: const BnbuText('重新生成这轮回复'),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.only(right: tokens.space8, bottom: tokens.space16),
      child: message.isError && !message.compactError
          ? Container(
              width: double.infinity,
              padding: EdgeInsets.all(tokens.space16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(tokens.radius16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.22),
                ),
              ),
              child: content,
            )
          : content,
    );
  }

  IconData _actionIcon(AssistantActionType type) {
    return switch (type) {
      AssistantActionType.composeEmail => LucideIcons.send300,
      AssistantActionType.submitAssignment => LucideIcons.upload300,
      AssistantActionType.openPage => LucideIcons.globe300,
      AssistantActionType.openAssignment => LucideIcons.clipboard300,
      AssistantActionType.openCourse => LucideIcons.graduationCap300,
      AssistantActionType.openMail => LucideIcons.mail300,
      AssistantActionType.showCampusPlace => LucideIcons.mapPin300,
      AssistantActionType.prepareCoursePack => LucideIcons.folders300,
      AssistantActionType.downloadAttachment => LucideIcons.download300,
      AssistantActionType.batchDownloadCourseFiles =>
        LucideIcons.folderArchive300,
      AssistantActionType.uploadAssignmentFile => LucideIcons.upload300,
      AssistantActionType.startQuizAttempt => LucideIcons.play300,
      AssistantActionType.saveQuizAnswers => LucideIcons.save300,
      AssistantActionType.submitQuizAttempt => LucideIcons.send300,
      AssistantActionType.setIspaceCompletion => LucideIcons.circleCheck300,
      AssistantActionType.submitIspaceChoice => LucideIcons.listChecks300,
      AssistantActionType.deleteMail => LucideIcons.trash2300,
      AssistantActionType.restoreMail => LucideIcons.rotateCcw300,
      AssistantActionType.openCampusPage => LucideIcons.calendarDays300,
      AssistantActionType.openMeLifeEntry => LucideIcons.landmark300,
      AssistantActionType.openDirectoryEntry => LucideIcons.landmark300,
      AssistantActionType.openAppTab => LucideIcons.panelsTopLeft300,
      AssistantActionType.openOfficialSystem => LucideIcons.landmark300,
      AssistantActionType.openTaCourseManager => LucideIcons.calendarDays300,
      AssistantActionType.addTaCourse => LucideIcons.squarePlus300,
      AssistantActionType.updateTaCourse => LucideIcons.calendarDays300,
      AssistantActionType.deleteTaCourse => LucideIcons.calendarX300,
      AssistantActionType.scheduleNotification => LucideIcons.bellRing300,
    };
  }
}

class _AssistantMemorySuggestionPanel extends StatelessWidget {
  const _AssistantMemorySuggestionPanel({
    required this.suggestions,
    required this.onSave,
    required this.onEdit,
    required this.onDismiss,
  });

  final List<AssistantMemorySuggestion> suggestions;
  final ValueChanged<AssistantMemorySuggestion> onSave;
  final ValueChanged<AssistantMemorySuggestion> onEdit;
  final ValueChanged<AssistantMemorySuggestion> onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Container(
      key: const ValueKey('assistant-memory-suggestion-panel'),
      width: double.infinity,
      padding: EdgeInsets.all(tokens.space12),
      decoration: BoxDecoration(
        color: tokens.brandBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(tokens.radius16),
        border: Border.all(color: tokens.brandBlue.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.brain300, size: 18),
              SizedBox(width: tokens.space8),
              BnbuText(
                '记忆建议',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          for (final suggestion in suggestions) ...[
            SizedBox(height: tokens.space8),
            Container(
              padding: EdgeInsets.all(tokens.space12),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radius12),
                border: Border.all(color: tokens.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(suggestion.content),
                  SizedBox(height: tokens.space8),
                  Wrap(
                    spacing: tokens.space8,
                    runSpacing: tokens.space8,
                    children: [
                      FilledButton.tonalIcon(
                        key: const ValueKey('assistant-memory-suggestion-save'),
                        onPressed: () => onSave(suggestion),
                        icon: const Icon(LucideIcons.save300, size: 17),
                        label: const BnbuText('保存'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('assistant-memory-suggestion-edit'),
                        onPressed: () => onEdit(suggestion),
                        icon: const Icon(LucideIcons.penLine300, size: 17),
                        label: const BnbuText('编辑'),
                      ),
                      IconButton(
                        key: const ValueKey(
                          'assistant-memory-suggestion-dismiss',
                        ),
                        tooltip: context.l10n.text('忽略'),
                        onPressed: () => onDismiss(suggestion),
                        icon: const Icon(LucideIcons.x300, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantMemorySyncBadge extends StatelessWidget {
  const _AssistantMemorySyncBadge({
    required this.syncing,
    required this.available,
    required this.failed,
  });

  final bool syncing;
  final bool available;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final (label, icon, foreground, background) = !available
        ? (
            '仅本机',
            LucideIcons.cloudOff300,
            tokens.textSecondary,
            tokens.surfaceMuted,
          )
        : failed
        ? (
            '等待同步',
            LucideIcons.refreshCw300,
            tokens.warning,
            tokens.warningContainer,
          )
        : syncing
        ? (
            '同步中',
            LucideIcons.refreshCw300,
            tokens.brandBlue,
            tokens.brandBlue.withValues(alpha: 0.10),
          )
        : (
            '已同步',
            LucideIcons.circleCheck300,
            tokens.success,
            tokens.successContainer,
          );
    return Semantics(
      liveRegion: syncing || failed,
      label: context.l10n.text('记忆$label'),
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('assistant-memory-sync-badge'),
          height: 24,
          padding: EdgeInsets.symmetric(horizontal: tokens.space8),
          decoration: BoxDecoration(
            color: syncing ? Colors.transparent : background,
            borderRadius: BorderRadius.circular(tokens.radius12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (syncing)
                BnbuActivityIndicator(size: 13, color: foreground)
              else
                Icon(icon, size: 13, color: foreground),
              SizedBox(width: tokens.space4),
              BnbuText(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantThinkingRow extends StatelessWidget {
  const _AssistantThinkingRow({required this.activities});

  final List<AssistantActivity> activities;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space24),
      child: _AssistantActivityDisclosure(activities: activities, active: true),
    );
  }
}

class _AssistantActivityDisclosure extends StatefulWidget {
  const _AssistantActivityDisclosure({
    required this.activities,
    required this.active,
  });

  final List<AssistantActivity> activities;
  final bool active;

  @override
  State<_AssistantActivityDisclosure> createState() =>
      _AssistantActivityDisclosureState();
}

class _AssistantActivityDisclosureState
    extends State<_AssistantActivityDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final activities = widget.activities.isEmpty
        ? const [AssistantActivity(label: '小U正在处理', completed: false)]
        : widget.activities;
    final elapsedMatch = !widget.active
        ? RegExp(r'^用时 (\d+) 秒$').firstMatch(activities.last.label)
        : null;
    final seconds = int.tryParse(elapsedMatch?.group(1) ?? '');
    String elapsedLabel(int seconds) {
      final hours = seconds ~/ 3600;
      final minutes = seconds % 3600 ~/ 60;
      final rest = seconds % 60;
      if (context.l10n.isEnglish) {
        return 'Took ${hours > 0 ? '${hours}h ' : ''}${minutes > 0 || hours > 0 ? '${minutes}m ' : ''}${rest}s';
      }
      return '${context.l10n.isTraditionalChinese ? '用時' : '用时'} ${hours > 0 ? '$hours 小时 ' : ''}${minutes > 0 || hours > 0 ? '$minutes 分 ' : ''}$rest 秒';
    }

    final summary = seconds == null
        ? activities.last
        : AssistantActivity(label: elapsedLabel(seconds));
    final visible = _expanded
        ? seconds == null
              ? activities
              : [summary, ...activities.where((a) => a != activities.last)]
        : [summary];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('assistant-activity-disclosure'),
        borderRadius: BorderRadius.circular(tokens.radius12),
        onTap: activities.length > 1
            ? () => setState(() => _expanded = !_expanded)
            : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 0, vertical: tokens.space8),
          child: Column(
            children: [
              for (var index = 0; index < visible.length; index++) ...[
                if (index > 0) SizedBox(height: tokens.space8),
                _AssistantActivityRow(
                  activity: visible[index],
                  showSpinner:
                      widget.active &&
                      index == visible.length - 1 &&
                      !visible[index].completed &&
                      !visible[index].failed,
                  trailing: index == 0 && activities.length > 1
                      ? Icon(
                          _expanded
                              ? LucideIcons.chevronUp300
                              : LucideIcons.chevronDown300,
                          size: 18,
                          color: tokens.textMuted,
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantActivityRow extends StatelessWidget {
  const _AssistantActivityRow({
    required this.activity,
    required this.showSpinner,
    this.trailing,
  });

  final AssistantActivity activity;
  final bool showSpinner;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Row(
      children: [
        Expanded(
          child: AssistantThinkingText(
            text: activity.label,
            active: showSpinner,
            failed: activity.failed,
          ),
        ),
        if (trailing != null) ...[SizedBox(width: tokens.space8), trailing!],
      ],
    );
  }
}

class _AssistantErrorBanner extends StatelessWidget {
  const _AssistantErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: BnbuText(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            IconButton(
              tooltip: context.l10n.text('关闭'),
              onPressed: onDismiss,
              icon: Icon(LucideIcons.x300, color: colors.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMemoryEditor extends StatefulWidget {
  const _AssistantMemoryEditor({
    required this.presentation,
    required this.initialValue,
  });

  final BnbuAdaptiveModalPresentation presentation;
  final String initialValue;

  @override
  State<_AssistantMemoryEditor> createState() => _AssistantMemoryEditorState();
}

class _AssistantMemoryEditorState extends State<_AssistantMemoryEditor> {
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
      presentation: widget.presentation,
      title: widget.initialValue.isEmpty ? '添加记忆' : '编辑记忆',
      icon: LucideIcons.brain300,
      bottomBar: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            onPressed: () {
              final content = _controller.text.trim();
              if (content.isNotEmpty) Navigator.of(context).pop(content);
            },
            child: const BnbuText('保存'),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 1000,
        maxLines: 8,
        minLines: 5,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
