part of 'mail_page.dart';

class ComposeMailPage extends StatefulWidget {
  const ComposeMailPage({
    super.key,
    required this.mailService,
    required this.credentials,
    this.replyTo,
    this.draftDetail,
    this.initialRecipient = '',
    this.initialSubject = '',
    this.initialBody = '',
    this.initialHtmlBody,
    this.replyAll = false,
    this.onSent,
    this.onClosed,
    this.embeddedInWorkspace = false,
    this.onOutcome,
    this.closeMailServiceOnDispose = false,
    this.autoSaveDrafts = true,
    this.assistantPrepared = false,
    this.recipientDirectory,
    this.senderAvatarService,
    this.filePicker,
    this.signatureStore,
    this.senderDisplayName,
  });

  final MailService mailService;
  final MailAccessCredentials credentials;

  /// Set when replying to an existing message.
  final MailMessageDetail? replyTo;

  /// Set when continuing to edit an existing draft.
  /// Pre-fills all fields and tracks the draft UID for deletion on send.
  final MailMessageDetail? draftDetail;

  /// Initial values prepared by a confirmed assistant action.
  final String initialRecipient;
  final String initialSubject;
  final String initialBody;

  /// Canonical rich HTML passed by the forwarding or assistant route.
  final String? initialHtmlBody;
  final bool replyAll;
  final VoidCallback? onSent;
  final VoidCallback? onClosed;
  final bool embeddedInWorkspace;
  final ValueChanged<String>? onOutcome;

  /// Used by one-off assistant compose routes that own their service instance.
  final bool closeMailServiceOnDispose;

  /// Assistant-prepared compose routes disable automatic APPEND draft writes.
  final bool autoSaveDrafts;

  /// Shows a non-blocking animated edge while the user reviews AI-filled data.
  final bool assistantPrepared;

  /// Optional official-directory search dependency for deterministic tests.
  final MailRecipientDirectory? recipientDirectory;

  /// Shares the same official teacher and organization avatar pipeline used by
  /// the mailbox list and detail page.
  final MailSenderAvatarService? senderAvatarService;

  /// Allows the picker boundary to be verified without invoking native UI.
  final FilePicker? filePicker;

  /// The profile owner injects the current central-profile display name. The
  /// editor falls back to the mailbox local part while that profile is loading.
  final String? senderDisplayName;
  final MailComposeSignatureStore? signatureStore;

  @override
  State<ComposeMailPage> createState() => _ComposeMailPageState();
}

enum _ComposeExitChoice { keepEditing, discard, save }

@visibleForTesting
double mailComposeFontPointToPixels(int points) => points * 96 / 72;

@visibleForTesting
String mailComposeFontPixelsToPointLabel(String? cssValue) {
  if (cssValue == null || cssValue.trim().isEmpty) return '11';
  final match = RegExp(
    r'^(\d+(?:\.\d+)?)(px|pt)?$',
  ).firstMatch(cssValue.trim().toLowerCase());
  if (match == null) return '11';
  final value = double.tryParse(match.group(1)!);
  if (value == null || !value.isFinite || value <= 0) return '11';
  final points = match.group(2) == 'pt' ? value : value * 72 / 96;
  final rounded = points.round();
  if ((points - rounded).abs() < 0.05) return '$rounded';
  return points.toStringAsFixed(1);
}

class _ComposeMailPageState extends State<ComposeMailPage> {
  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _bccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;
  late final RichMailEditorController _richEditorController;
  late RichMailDocument _richDocument;
  late final MailRecipientDirectory _recipientDirectory =
      widget.recipientDirectory ?? MailRecipientDirectory();
  late final bool _ownsRecipientDirectory = widget.recipientDirectory == null;
  late final MailSenderAvatarService _senderAvatarService =
      widget.senderAvatarService ??
      IoMailSenderAvatarService.sharedPortraitCache;
  late final MailComposeSignatureStore _signatureStore =
      widget.signatureStore ?? MailComposeSignatureStore();

  int? _draftUid;
  int? _draftMailboxUidValidity;
  Timer? _draftTimer;
  Future<void>? _draftSaveFuture;
  late String _lastSavedTo;
  late String _lastSavedCc;
  late String _lastSavedBcc;
  late String _lastSavedSubject;
  late String _lastSavedBody;
  late String _lastSavedBodyHtml;
  late String _lastSavedAttachmentSignature;
  late MailComposeSignature _lastSavedSignature;
  bool _isSending = false;
  bool _isSavingDraft = false;
  bool _isClosing = false;
  bool _showCarbonCopy = false;
  MailComposeSignature _signature = MailComposeSignature.none;
  late bool _assistantReviewActive;
  final List<MailComposeAttachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    _assistantReviewActive = widget.assistantPrepared;
    final draft = widget.draftDetail;
    final replyTo = widget.replyTo;

    if (draft != null) {
      // Continue editing an existing draft
      _toController = TextEditingController(
        text: !widget.assistantPrepared || widget.initialRecipient.isEmpty
            ? draft.recipients
            : widget.initialRecipient,
      );
      _ccController = TextEditingController(text: draft.cc ?? '');
      _bccController = TextEditingController();
      _showCarbonCopy = _ccController.text.trim().isNotEmpty;
      _subjectController = TextEditingController(
        text: !widget.assistantPrepared || widget.initialSubject.isEmpty
            ? draft.subject
            : widget.initialSubject,
      );
      _bodyController = TextEditingController(
        text: !widget.assistantPrepared || widget.initialBody.isEmpty
            ? draft.body
            : widget.initialBody,
      );
      _draftUid = draft.uid;
      _draftMailboxUidValidity = draft.mailboxUidValidity;
    } else if (replyTo != null) {
      // Reply
      _toController = TextEditingController(
        text: _extractEmail(replyTo.sender),
      );
      _ccController = TextEditingController(
        text: widget.replyAll
            ? replyAllCarbonCopy(
                replyTo.recipients,
                replyTo.cc,
                replyTo.sender,
                widget.credentials.emailAddress,
              )
            : '',
      );
      _showCarbonCopy = _ccController.text.isNotEmpty;
      _bccController = TextEditingController();
      _subjectController = TextEditingController(
        text: replyTo.subject.startsWith('Re:')
            ? replyTo.subject
            : 'Re: ${replyTo.subject}',
      );
      _bodyController = TextEditingController(text: widget.initialBody);
    } else {
      // New compose, optionally pre-filled by a confirmed assistant action.
      _toController = TextEditingController(text: widget.initialRecipient);
      _ccController = TextEditingController();
      _bccController = TextEditingController();
      _subjectController = TextEditingController(text: widget.initialSubject);
      _bodyController = TextEditingController(text: widget.initialBody);
    }

    final draftHtml = draft?.htmlBody;
    final providedInitialHtml = widget.initialHtmlBody?.trim();
    final initialHtml =
        draft != null &&
            !widget.assistantPrepared &&
            draftHtml != null &&
            draftHtml.trim().isNotEmpty
        ? _stripBnbuSignature(draftHtml)
        : (providedInitialHtml?.isNotEmpty == true
              ? providedInitialHtml
              : null);
    _richDocument = initialHtml != null
        ? RichMailDocument.fromHtml(
            MailComposeHtmlSanitizer.sanitize(initialHtml),
            fallbackText: _bodyController.text,
          )
        : RichMailDocument.fromPlainText(_bodyController.text);
    _richEditorController = RichMailEditorController(
      initialDocument: _richDocument,
    );

    // Set last-saved baseline so draft timer doesn't fire immediately.
    _lastSavedTo = _toController.text;
    _lastSavedCc = _ccController.text;
    _lastSavedBcc = _bccController.text;
    _lastSavedSubject = _subjectController.text;
    _lastSavedBody = _bodyController.text;
    _lastSavedBodyHtml = _richDocument.html;
    _lastSavedAttachmentSignature = _attachmentSignature;
    _lastSavedSignature = _signature;
    unawaited(_loadSignaturePreference());

    if (widget.autoSaveDrafts) {
      _draftTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _autoSaveDraft(),
      );
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _richEditorController.dispose();
    _draftTimer?.cancel();
    if (_ownsRecipientDirectory) {
      _recipientDirectory.dispose();
    }
    if (widget.closeMailServiceOnDispose) {
      unawaited(widget.mailService.close());
    }
    super.dispose();
  }

  bool get _hasChanges =>
      _toController.text != _lastSavedTo ||
      _ccController.text != _lastSavedCc ||
      _bccController.text != _lastSavedBcc ||
      _subjectController.text != _lastSavedSubject ||
      _bodyController.text != _lastSavedBody ||
      _richDocument.html != _lastSavedBodyHtml ||
      _attachmentSignature != _lastSavedAttachmentSignature ||
      _signature != _lastSavedSignature;

  String get _attachmentSignature =>
      _attachments.map((item) => '${item.name}:${item.bytes.length}').join('|');

  String get _signatureName {
    final injected = widget.senderDisplayName?.trim() ?? '';
    if (injected.isNotEmpty) return injected;
    return widget.credentials.emailAddress.split('@').first;
  }

  String get _signatureHtml => _signature != MailComposeSignature.bnbuMe
      ? ''
      : '''
<div data-bnbu-signature="v1">
  <hr style="border:0;border-top:1px solid #d7dee7;margin:22px 0 14px">
  <p style="margin:0;color:#6b7581;font-size:14px;font-weight:600">北师港浸大BNBU</p>
  <p style="margin:3px 0 0;font-size:14px;font-weight:600">${_escapeHtml(_signatureName)}</p>
  <p style="margin:3px 0 0;color:#7e8792;font-size:12px">来自BNBU.ME</p>
</div>''';

  String get _serializedHtml =>
      '${MailComposeHtmlSanitizer.sanitize(_richDocument.html)}$_signatureHtml';

  String get _serializedPlainText {
    if (_signature != MailComposeSignature.bnbuMe) return _richDocument.text;
    return [
      _richDocument.text.trimRight(),
      '北师港浸大BNBU',
      _signatureName,
      '来自BNBU.ME',
    ].where((line) => line.isNotEmpty).join('\n');
  }

  String _stripBnbuSignature(String value) => value.replaceFirst(
    RegExp(
      r'''<div\s+[^>]*data-bnbu-signature\s*=\s*["']v1["'][^>]*>.*?</div>''',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );

  Future<void> _loadSignaturePreference() async {
    final preference = await _signatureStore.load(
      widget.credentials.emailAddress,
    );
    if (!mounted || preference == _signature) return;
    setState(() => _signature = preference);
  }

  Future<void> _selectSignature(MailComposeSignature signature) async {
    if (_signature == signature) return;
    setState(() => _signature = signature);
    await _signatureStore.save(widget.credentials.emailAddress, signature);
  }

  Future<void> _autoSaveDraft() async {
    if (!widget.autoSaveDrafts || !mounted || _isSavingDraft || _isSending) {
      return;
    }
    await _refreshRichDocument();
    if (!_hasChanges || !mounted || _isSavingDraft || _isSending) return;
    final operation = _saveDraftChanges();
    _draftSaveFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_draftSaveFuture, operation)) {
        _draftSaveFuture = null;
      }
    }
  }

  Future<void> _saveDraftChanges({bool bestEffort = true}) async {
    await _refreshRichDocument();
    if (!mounted) return;
    final savedTo = _toController.text;
    final savedCc = _ccController.text;
    final savedBcc = _bccController.text;
    final savedSubject = _subjectController.text;
    final savedBody = _bodyController.text;
    final savedBodyHtml = _richDocument.html;
    final savedSignature = _signature;
    final composeData = _buildComposeData();
    setState(() => _isSavingDraft = true);
    try {
      final draftIdentity = await widget.mailService.saveDraft(
        credentials: widget.credentials,
        composeData: composeData,
        existingDraftUid: _draftUid,
        expectedMailboxUidValidity: _draftMailboxUidValidity,
      );
      if (!mounted) return;
      setState(() {
        _draftUid = draftIdentity?.uid;
        _draftMailboxUidValidity = draftIdentity?.mailboxUidValidity;
        _lastSavedTo = savedTo;
        _lastSavedCc = savedCc;
        _lastSavedBcc = savedBcc;
        _lastSavedSubject = savedSubject;
        _lastSavedBody = savedBody;
        _lastSavedBodyHtml = savedBodyHtml;
        _lastSavedSignature = savedSignature;
        _lastSavedAttachmentSignature = _attachmentSignature;
      });
      widget.onOutcome?.call('draft_saved');
      if (draftIdentity?.previousDraftRetained == true) {
        BnbuToast.show(
          context,
          '新草稿已保存，旧草稿暂时保留在草稿箱。',
          kind: BnbuToastKind.warning,
        );
      }
    } catch (_) {
      if (!bestEffort) rethrow;
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  MailComposeData _buildComposeData() {
    final replyTo = widget.replyTo;
    final body = _serializedPlainText;
    final editorHtml = _serializedHtml;
    final htmlBody = replyTo != null
        ? _buildReplyHtml(replyTo, editorHtml)
        : (editorHtml.trim().isEmpty ? null : editorHtml);
    final selected = <String>{};
    String unique(String value) {
      try {
        return parseMailRecipientAddresses(value)
            .where((address) => selected.add(address.email.toLowerCase()))
            .map((address) => address.email)
            .join(', ');
      } on FormatException {
        return value.trim();
      }
    }

    final to = unique(_toController.text);
    final cc = unique(_ccController.text);
    final bcc = unique(_bccController.text);
    return MailComposeData(
      to: to,
      cc: cc.isEmpty ? null : cc,
      bcc: bcc.isEmpty ? null : bcc,
      subject: _subjectController.text.trim(),
      body: body,
      attachments: List.unmodifiable(_attachments),
      htmlBody: htmlBody,
      inReplyTo: replyTo?.messageId,
      references: replyTo?.messageId,
    );
  }

  String _buildReplyHtml(MailMessageDetail original, String userHtml) {
    final dateStr = original.date != null
        ? context.l10n.formatFullDateTime(original.date!)
        : '';
    final originalBody = original.htmlBody != null
        ? MailComposeHtmlSanitizer.sanitize(original.htmlBody!)
        : '<pre>${_escapeHtml(original.body)}</pre>';
    return '''
${MailComposeHtmlSanitizer.sanitize(userHtml)}
<hr style="border:none;border-top:1px solid #d0d0d0;margin:16px 0">
<div style="color:#666;font-size:0.9em;margin-bottom:8px;line-height:1.8">
  <b>发件人：</b>${_escapeHtml(original.sender)}<br>
  <b>时 间：</b>$dateStr<br>
  <b>收件人：</b>${_escapeHtml(original.recipients)}<br>
  <b>主 题：</b>${_escapeHtml(original.subject)}
</div>
<blockquote style="margin:0;padding-left:12px;border-left:3px solid #ccc;color:#444">
  $originalBody
</blockquote>
''';
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _truncateBody(String body) {
    final normalized = body.replaceAll('\n', ' ').trim();
    if (normalized.length <= 200) return normalized;
    return '${normalized.substring(0, 200)}...';
  }

  Future<void> _sendEmail() async {
    if (!_canSend) return;
    final to = _toController.text.trim();
    if (to.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('请填写收件人')));
      return;
    }
    await _refreshRichDocument();
    if (!mounted) return;
    _draftTimer?.cancel();
    setState(() {
      _isSending = true;
      _assistantReviewActive = false;
    });
    try {
      await _draftSaveFuture;
      if (!mounted) return;
      await widget.mailService.sendEmail(
        credentials: widget.credentials,
        composeData: _buildComposeData(),
      );
      // Delete the draft after sending (both auto-saved and pre-existing)
      final draftUid = _draftUid;
      if (draftUid != null) {
        try {
          await widget.mailService.deleteMessages(
            credentials: widget.credentials,
            folder: MailFolder.drafts,
            uids: [draftUid],
            expectedMailboxUidValidity: _draftMailboxUidValidity,
          );
        } catch (_) {}
      }
      if (!mounted) return;
      widget.onSent?.call();
      BnbuToast.show(context, '邮件已发送', kind: BnbuToastKind.success);
      _closeEditor();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      widget.onOutcome?.call('failed');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText('发送失败：$error')));
    }
  }

  Future<void> _pickAttachments() async {
    await _pickComposeFiles();
  }

  Future<Uint8List?> _pickInlineImage() async {
    FilePickerResult? result;
    try {
      result = await (widget.filePicker ?? FilePicker.platform).pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: true,
        type: FileType.image,
      );
    } on Object {
      if (mounted) {
        BnbuToast.show(context, '无法读取所选图片', kind: BnbuToastKind.danger);
      }
      return null;
    }
    if (!mounted || result == null || result.files.isEmpty) return null;
    try {
      return await readMailComposeAttachment(
        result.files.single,
        maxBytes: 2 * 1024 * 1024,
      );
    } on MailComposeAttachmentReadException catch (error) {
      if (mounted) {
        final message = switch (error.failure) {
          MailComposeAttachmentReadFailure.empty => '所选图片为空文件',
          MailComposeAttachmentReadFailure.tooLarge => '内嵌图片不能超过 2 MB',
          MailComposeAttachmentReadFailure.unavailable => '无法读取所选图片',
        };
        BnbuToast.show(context, message, kind: BnbuToastKind.warning);
      }
      return null;
    }
  }

  Future<void> _pickComposeFiles({FileType type = FileType.any}) async {
    FilePickerResult? result;
    try {
      result = await (widget.filePicker ?? FilePicker.platform).pickFiles(
        allowMultiple: true,
        withData: false,
        withReadStream: true,
        type: type,
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('无法打开或读取所选附件，请重新选择')));
      return;
    }
    if (!mounted || result == null) return;
    const maxFileBytes = 10 * 1024 * 1024;
    const maxTotalBytes = 20 * 1024 * 1024;
    var remaining =
        maxTotalBytes -
        _attachments.fold<int>(0, (total, item) => total + item.bytes.length);
    final accepted = <MailComposeAttachment>[];
    var tooLargeCount = 0;
    var emptyCount = 0;
    var unavailableCount = 0;
    var totalLimitCount = 0;
    for (final file in result.files) {
      if (remaining <= 0 || (file.size > 0 && file.size > remaining)) {
        totalLimitCount++;
        continue;
      }
      try {
        final bytes = await readMailComposeAttachment(
          file,
          maxBytes: maxFileBytes,
        );
        if (bytes.length > remaining) {
          totalLimitCount++;
          continue;
        }
        accepted.add(
          MailComposeAttachment(
            name: safeAttachmentFileName(file.name),
            bytes: bytes,
          ),
        );
        remaining -= bytes.length;
      } on MailComposeAttachmentReadException catch (error) {
        switch (error.failure) {
          case MailComposeAttachmentReadFailure.empty:
            emptyCount++;
          case MailComposeAttachmentReadFailure.tooLarge:
            tooLargeCount++;
          case MailComposeAttachmentReadFailure.unavailable:
            unavailableCount++;
        }
      }
    }
    if (!mounted) return;
    if (accepted.isNotEmpty) {
      setState(() => _attachments.addAll(accepted));
    }
    final skippedCount =
        tooLargeCount + emptyCount + unavailableCount + totalLimitCount;
    if (skippedCount > 0) {
      final reasons = <String>[
        if (tooLargeCount > 0) '$tooLargeCount 个超过 10 MB',
        if (emptyCount > 0) '$emptyCount 个为空文件',
        if (unavailableCount > 0) '$unavailableCount 个无法读取',
        if (totalLimitCount > 0) '$totalLimitCount 个超出 20 MB 总量',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: BnbuText(
            accepted.isEmpty
                ? '未能添加附件：${reasons.join('、')}'
                : '已添加 ${accepted.length} 个附件；${reasons.join('、')}未添加',
          ),
        ),
      );
    }
  }

  void _editorCommand(String command, [Object? value]) {
    unawaited(_richEditorController.execute(command, value));
  }

  Future<void> _insertLink() async {
    final url = await showBnbuCreationModal<String>(
      context: context,
      maxWidth: 520,
      maxHeight: 320,
      semanticLabel: context.l10n.text('插入链接'),
      builder: (dialogContext, presentation) => BnbuTextCreationEditor(
        preserveReferenceGeometry: true,
        title: '插入链接',
        actionLabel: '插入',
        hint: 'https://',
        avoidKeyboard: !presentation.isDialog,
        fieldKey: const ValueKey('compose-link-field'),
        autofocus: true,
        keyboardType: TextInputType.url,
      ),
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    _editorCommand('setLink', url.trim());
  }

  void _onRichDocumentChanged(RichMailDocument document) {
    _richDocument = RichMailDocument(
      html: MailComposeHtmlSanitizer.sanitize(document.html),
      json: document.json,
      text: document.text,
    );
    if (_bodyController.text != document.text) {
      _bodyController.value = TextEditingValue(
        text: document.text,
        selection: TextSelection.collapsed(offset: document.text.length),
      );
    }
  }

  Future<void> _refreshRichDocument() async {
    final document = await _richEditorController.snapshot();
    _onRichDocumentChanged(document);
  }

  void _closeEditor() {
    if (widget.onClosed != null) {
      widget.onClosed!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onCancel() async {
    if (_isClosing) return;
    _isClosing = true;
    if (_assistantReviewActive && mounted) {
      setState(() => _assistantReviewActive = false);
    }
    try {
      _draftTimer?.cancel();
      await _draftSaveFuture;
      if (!mounted) return;
      await _refreshRichDocument();
      if (!mounted) return;
      final hasContent =
          _toController.text.trim().isNotEmpty ||
          _ccController.text.trim().isNotEmpty ||
          _bccController.text.trim().isNotEmpty ||
          _subjectController.text.trim().isNotEmpty ||
          _bodyController.text.trim().isNotEmpty ||
          _attachments.isNotEmpty;
      if (!_hasChanges || !hasContent) {
        _closeEditor();
        return;
      }

      final choice = await showDialog<_ComposeExitChoice>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(LucideIcons.filePenLine300),
          title: const BnbuText('保存草稿？'),
          actions: [
            TextButton(
              key: const ValueKey('compose-exit-discard'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _ComposeExitChoice.discard),
              child: const BnbuText('不保存'),
            ),
            TextButton(
              key: const ValueKey('compose-exit-continue'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _ComposeExitChoice.keepEditing),
              child: const BnbuText('继续编辑'),
            ),
            FilledButton(
              key: const ValueKey('compose-exit-save'),
              onPressed: () =>
                  Navigator.pop(dialogContext, _ComposeExitChoice.save),
              child: const BnbuText('保存并关闭'),
            ),
          ],
        ),
      );
      if (!mounted ||
          choice == null ||
          choice == _ComposeExitChoice.keepEditing) {
        return;
      }
      if (choice == _ComposeExitChoice.save) {
        try {
          await _saveDraftChanges(bestEffort: false);
        } on Object catch (error) {
          if (!mounted) return;
          BnbuToast.show(context, '草稿保存失败：$error', kind: BnbuToastKind.danger);
          return;
        }
        if (!mounted) return;
        BnbuToast.show(context, '草稿已保存', kind: BnbuToastKind.success);
      }
      if (mounted) _closeEditor();
    } finally {
      _isClosing = false;
    }
  }

  Future<void> _saveDraftManually() async {
    if (_isSending || _isSavingDraft) return;
    try {
      await _saveDraftChanges(bestEffort: false);
      if (!mounted) return;
      BnbuToast.show(context, '草稿已保存', kind: BnbuToastKind.success);
    } on Object catch (error) {
      if (!mounted) return;
      BnbuToast.show(context, '草稿保存失败：$error', kind: BnbuToastKind.danger);
    }
  }

  Future<void> _previewEmail() async {
    await _refreshRichDocument();
    if (!mounted) return;
    final tokens = context.bnbuTheme;
    await showBnbuAdaptiveModal<void>(
      context: context,
      dialogMaxWidth: 720,
      dialogMaxHeight: 720,
      semanticLabel: context.l10n.text('邮件预览'),
      builder: (modalContext, presentation) => BnbuModalFrame(
        preserveReferenceGeometry: true,
        presentation: presentation,
        title: '邮件预览',
        icon: LucideIcons.eye300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BnbuText(
              _subjectController.text.trim().isEmpty
                  ? '无主题'
                  : _subjectController.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                modalContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: tokens.space4),
            BnbuText(
              _toController.text.trim(),
              style: Theme.of(
                modalContext,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            Divider(height: tokens.space24, color: tokens.border),
            Flexible(
              child: NativeHtmlMailView(
                htmlContent: _richDocument.html.isEmpty
                    ? '<p></p>'
                    : _richDocument.html,
                fallbackText: _richDocument.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDraft = widget.draftDetail != null;
    final isReply = widget.replyTo != null;
    final title = isDraft ? '编辑草稿' : (isReply ? '回复邮件' : '新建邮件');
    final tokens = context.bnbuTheme;
    final scaffold = LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final useDesktopWorkspace =
            (constraints.maxWidth >= BnbuBreakpoints.tabletWorkspace ||
                (widget.embeddedInWorkspace &&
                    MediaQuery.sizeOf(context).width >=
                        BnbuBreakpoints.tabletWorkspace)) &&
            textScale <= 1.2;
        if (useDesktopWorkspace) {
          return _buildDesktopScaffold(title: title, isReply: isReply);
        }
        return _buildCompactScaffold(
          title: title,
          isDraft: isDraft,
          isReply: isReply,
        );
      },
    );
    return AssistantReviewFrame(
      active: _assistantReviewActive,
      child: ColoredBox(color: tokens.canvas, child: scaffold),
    );
  }

  bool get _canSend {
    if (_isSending) return false;
    try {
      if (parseMailRecipientAddresses(_toController.text).isEmpty) return false;
      parseMailRecipientAddresses(_ccController.text);
      parseMailRecipientAddresses(_bccController.text);
      return true;
    } on FormatException {
      return false;
    }
  }

  // Wide composition keeps its established workspace header.
  Widget _composeCreationHeader(String title) => BnbuCreationHeader(
    preserveReferenceGeometry: true,
    titleFontSize: 20 / 0.65,
    subtitleFontSize: 12 / 0.65,
    title: title,
    subtitle: widget.credentials.emailAddress,
    closeKey: const ValueKey('compose-close'),
    closeEnabled: !_isSending,
    onClose: _onCancel,
    action: ListenableBuilder(
      listenable: Listenable.merge([
        _toController,
        _ccController,
        _bccController,
      ]),
      builder: (context, _) => BnbuCreationAction(
        key: const ValueKey('compose-send'),
        label: '发送',
        // Keep the reference header geometry; 24 paints at 15.6px after its
        // 0.65 scale, making only this primary action more legible.
        fontSize: 24,
        onPressed: _canSend ? _sendEmail : null,
        busy: _isSending,
      ),
    ),
  );

  // Phone composition has its own reference layout. Keep it outside the
  // grouped creation-form and shared secondary-header scaling systems.
  Widget _buildCompactScaffold({
    required String title,
    required bool isDraft,
    required bool isReply,
  }) {
    final colors = MailSurfaceColors(context);
    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        top: false,
        bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
        child: Padding(
          padding: EdgeInsets.only(
            top: (MediaQuery.paddingOf(context).top - 6).clamp(
              0,
              double.infinity,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                key: const ValueKey('compose-reference-header'),
                height:
                    44 +
                    (MediaQuery.textScalerOf(context).scale(17) / 17 - 1).clamp(
                          0,
                          double.infinity,
                        ) *
                        40,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 68),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BnbuText(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: colors.foreground,
                            ),
                          ),
                          Text(
                            widget.credentials.emailAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: colors.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 6,
                      child: IconButton(
                        key: const ValueKey('compose-close'),
                        tooltip: context.l10n.text('关闭'),
                        onPressed: _isSending ? null : _onCancel,
                        icon: Icon(
                          LucideIcons.x300,
                          size: 26,
                          color: colors.foreground,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          _toController,
                          _ccController,
                          _bccController,
                        ]),
                        builder: (context, _) => TextButton(
                          key: const ValueKey('compose-send'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(54, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.padded,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            backgroundColor: const Color(0xFF3187F4),
                            disabledBackgroundColor: const Color(
                              0xFF3187F4,
                            ).withValues(alpha: .42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _canSend ? _sendEmail : null,
                          child: _isSending
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: BnbuActivityIndicator(
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                )
                              : const BnbuText('发送'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SizedBox(
                  key: const ValueKey('compose-compact-editor'),
                  width: double.infinity,
                  child: _buildEditor(
                    isDraft: isDraft,
                    isReply: isReply,
                    desktop: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopScaffold({required String title, required bool isReply}) {
    final tokens = context.bnbuTheme;
    final commandStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      foregroundColor: tokens.textSecondary,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    );
    return Scaffold(
      key: const ValueKey('compose-desktop-workspace'),
      backgroundColor: BnbuCreationStyle.background(context),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            children: [
              _composeCreationHeader(title),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('compose-save-draft'),
                    style: commandStyle,
                    onPressed: _isSending || _isSavingDraft
                        ? null
                        : _saveDraftManually,
                    icon: const Icon(LucideIcons.save300, size: 16),
                    label: const BnbuText('保存'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('compose-desktop-attachment'),
                    style: commandStyle,
                    onPressed: _isSending ? null : _pickAttachments,
                    icon: const Icon(LucideIcons.paperclip300, size: 16),
                    label: const BnbuText('附件'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('compose-preview'),
                    style: commandStyle,
                    onPressed: _isSending ? null : _previewEmail,
                    icon: const Icon(LucideIcons.eye300, size: 16),
                    label: const BnbuText('预览'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SizedBox(
                  key: const ValueKey('compose-desktop-editor'),
                  child: _buildEditor(
                    isDraft: widget.draftDetail != null,
                    isReply: isReply,
                    desktop: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnvelope({
    required bool isDraft,
    required bool isReply,
    required bool desktop,
  }) => BnbuCreationGroup(
    children: [
      _buildRecipientAutocomplete(
        autofocus: desktop && !isDraft && !isReply,
        desktop: desktop,
      ),
      if (_showCarbonCopy) ...[
        _RecipientField(
          directory: _recipientDirectory,
          avatarService: _senderAvatarService,
          label: '抄送',
          controller: _ccController,
          fieldKey: const ValueKey('compose-cc-field'),
          desktop: desktop,
        ),
        _RecipientField(
          directory: _recipientDirectory,
          avatarService: _senderAvatarService,
          label: '密送',
          controller: _bccController,
          fieldKey: const ValueKey('compose-bcc-field'),
          desktop: desktop,
        ),
      ],
      _ComposeField(
        label: '主题',
        controller: _subjectController,
        fieldKey: const ValueKey('compose-subject-field'),
        dense: desktop,
      ),
    ],
  );

  Widget _buildEditor({
    required bool isDraft,
    required bool isReply,
    required bool desktop,
  }) {
    if (!desktop) {
      return _buildCompactEditor(isDraft: isDraft, isReply: isReply);
    }
    return Column(
      children: [
        BnbuUpdateProgress(active: _isSavingDraft),
        _buildEnvelope(isDraft: isDraft, isReply: isReply, desktop: true),
        const SizedBox(height: 24),
        Expanded(
          child: BnbuCreationSurface(
            child: Column(
              children: [
                _buildComposerToolbar(desktop: true),
                Divider(
                  height: .5,
                  thickness: .5,
                  indent: 16,
                  color: context.bnbuTheme.border.withValues(alpha: .45),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Expanded(
                          child: RichMailEditor(
                            controller: _richEditorController,
                            autofocus: isReply,
                            onChanged: _onRichDocumentChanged,
                            onPickImage: _pickInlineImage,
                          ),
                        ),
                        _buildSignaturePreview(desktop: true),
                        if (isReply)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              child: _buildQuotedBlock(widget.replyTo!),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_attachments.isNotEmpty) _buildAttachmentList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactEditor({required bool isDraft, required bool isReply}) {
    final colors = MailSurfaceColors(context);
    final divider = Divider(
      height: .5,
      thickness: .5,
      indent: 15,
      endIndent: 15,
      color: colors.dark ? colors.divider : const Color(0xFFF4F4F4),
    );
    return Column(
      children: [
        BnbuUpdateProgress(active: _isSavingDraft),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildRecipientAutocomplete(
                      autofocus: false,
                      desktop: false,
                    ),
                    divider,
                    if (_showCarbonCopy) ...[
                      _RecipientField(
                        controller: _ccController,
                        directory: _recipientDirectory,
                        label: '抄送',
                        fieldKey: const ValueKey('compose-cc-field'),
                        avatarService: _senderAvatarService,
                        desktop: false,
                      ),
                      divider,
                      _RecipientField(
                        controller: _bccController,
                        directory: _recipientDirectory,
                        label: '密送',
                        fieldKey: const ValueKey('compose-bcc-field'),
                        avatarService: _senderAvatarService,
                        desktop: false,
                      ),
                      divider,
                    ],
                    _ComposeField(
                      label: '主题',
                      controller: _subjectController,
                      fieldKey: const ValueKey('compose-subject-field'),
                    ),
                    divider,
                  ],
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: RichMailEditor(
                    controller: _richEditorController,
                    autofocus: isReply || !isDraft,
                    onChanged: _onRichDocumentChanged,
                    onPickImage: _pickInlineImage,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isReply)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: _buildQuotedBlock(widget.replyTo!),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildSignaturePreview(desktop: false),
        ),
        if (_attachments.isNotEmpty) _buildAttachmentList(),
        _buildMobileComposerToolbar(),
      ],
    );
  }

  Widget _buildAttachmentList() {
    final tokens = context.bnbuTheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: tokens.space12),
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, __) => SizedBox(width: tokens.space8),
        itemBuilder: (_, index) {
          final attachment = _attachments[index];
          return InputChip(
            label: BnbuText(attachment.name, overflow: TextOverflow.ellipsis),
            onDeleted: _isSending
                ? null
                : () => setState(() => _attachments.removeAt(index)),
          );
        },
      ),
    );
  }

  Widget _buildComposerToolbar({required bool desktop}) {
    assert(desktop);
    final tokens = context.bnbuTheme;
    final iconStyle = IconButton.styleFrom(
      minimumSize: const Size.square(32),
      maximumSize: const Size.square(32),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final menuStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: tokens.textPrimary,
      textStyle: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
    );
    final toolbarHeight =
        38.0 +
        ((MediaQuery.textScalerOf(context).scale(14) / 14) - 1).clamp(0, 1) *
            15;
    return ListenableBuilder(
      listenable: _richEditorController,
      builder: (context, _) {
        final state = _richEditorController.toolbarState;
        ButtonStyle activeStyle(bool active) => active
            ? iconStyle.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  tokens.brandBlue.withValues(alpha: .1),
                ),
                foregroundColor: WidgetStatePropertyAll(tokens.brandBlue),
              )
            : iconStyle;
        return ColoredBox(
          key: const ValueKey('compose-editor-toolbar'),
          color: BnbuCreationStyle.group(context),
          child: SizedBox(
            height: toolbarHeight,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        IconButton(
                          key: const ValueKey('compose-toolbar-undo'),
                          tooltip: context.l10n.text('撤销'),
                          style: iconStyle,
                          onPressed: _isSending
                              ? null
                              : () => _editorCommand('undo'),
                          icon: const Icon(LucideIcons.undo2300, size: 16),
                        ),
                        IconButton(
                          key: const ValueKey('compose-toolbar-redo'),
                          tooltip: context.l10n.text('重做'),
                          style: iconStyle,
                          onPressed: _isSending
                              ? null
                              : () => _editorCommand('redo'),
                          icon: const Icon(LucideIcons.redo2300, size: 16),
                        ),
                        IconButton(
                          key: const ValueKey('compose-toolbar-clear-format'),
                          tooltip: context.l10n.text('清除格式'),
                          style: iconStyle,
                          onPressed: _isSending
                              ? null
                              : () => _editorCommand('clearFormat'),
                          icon: const Icon(LucideIcons.eraser300, size: 16),
                        ),
                        _DesktopCommandDivider(color: tokens.border),
                        _buildSmallUMenu(menuStyle),
                        _buildInsertMenu(menuStyle),
                        _buildFontMenu(menuStyle),
                        _buildFontSizeMenu(menuStyle, state.fontSize),
                        IconButton(
                          key: const ValueKey('compose-toolbar-bold'),
                          tooltip: context.l10n.text('粗体'),
                          style: activeStyle(state.bold),
                          onPressed: _isSending
                              ? null
                              : () => _editorCommand('bold'),
                          icon: const Icon(LucideIcons.bold300, size: 16),
                        ),
                        IconButton(
                          key: const ValueKey('compose-toolbar-italic'),
                          tooltip: context.l10n.text('斜体'),
                          style: activeStyle(state.italic),
                          onPressed: _isSending
                              ? null
                              : () => _editorCommand('italic'),
                          icon: const Icon(LucideIcons.italic300, size: 16),
                        ),
                        IconButton(
                          key: const ValueKey('compose-toolbar-underline'),
                          tooltip: context.l10n.text('下划线'),
                          style: activeStyle(state.underline),
                          onPressed: _isSending
                              ? null
                              : () => _editorCommand('underline'),
                          icon: const Icon(LucideIcons.underline300, size: 16),
                        ),
                        _buildColorMenu(iconStyle),
                        _buildMoreFormatMenu(iconStyle),
                      ],
                    ),
                  ),
                ),
                _buildSignatureMenu(iconStyle),
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsertMenu(ButtonStyle textStyle) => BnbuMenuButton<String>(
    key: const ValueKey('compose-toolbar-insert'),
    tooltip: context.l10n.text('插入'),
    onSelected: (value) {
      switch (value) {
        case 'image':
          _editorCommand('requestImage');
        case 'link':
          unawaited(_insertLink());
        case 'table-2':
          _editorCommand('insertTable', const {'rows': 2, 'cols': 2});
        case 'table-3':
          _editorCommand('insertTable', const {'rows': 3, 'cols': 3});
      }
    },
    child: IgnorePointer(
      child: TextButton.icon(
        style: textStyle,
        onPressed: () {},
        icon: const Icon(LucideIcons.circlePlus300, size: 15),
        label: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BnbuText('插入'),
            Icon(LucideIcons.chevronDown300, size: 13),
          ],
        ),
      ),
    ),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'image', child: BnbuText('图片')),
      PopupMenuItem(value: 'link', child: BnbuText('链接')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'table-2', child: BnbuText('插入 2 × 2 表格')),
      PopupMenuItem(value: 'table-3', child: BnbuText('插入 3 × 3 表格')),
    ],
  );

  Widget _buildFontMenu(ButtonStyle textStyle) {
    final current = _richEditorController.toolbarState.fontFamily;
    return BnbuMenuButton<void>(
      key: const ValueKey('compose-toolbar-font'),
      tooltip: context.l10n.text('字体'),
      padding: EdgeInsets.zero,
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          enabled: false,
          height: 336,
          padding: EdgeInsets.zero,
          child: _DesktopFontMenuPanel(
            currentFamily: current,
            onSelected: (family) {
              Navigator.of(context).pop();
              _editorCommand('fontFamily', family);
            },
          ),
        ),
      ],
      child: IgnorePointer(
        child: TextButton.icon(
          style: textStyle,
          onPressed: () {},
          icon: const Icon(LucideIcons.type300, size: 15),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BnbuText(_fontFamilyLabel(current)),
              const Icon(LucideIcons.chevronDown300, size: 13),
            ],
          ),
        ),
      ),
    );
  }

  String _fontFamilyLabel(String? value) {
    if (value == null || value.isEmpty || value == 'system-ui') return '默认字体';
    if (value.contains('PingFang')) return '苹方';
    if (value.contains('Songti')) return '宋体';
    if (value.contains('Kaiti')) return '楷体';
    return value.split(',').first.replaceAll('"', '').trim();
  }

  Widget _buildFontSizeMenu(ButtonStyle textStyle, String? selectedSize) =>
      BnbuMenuButton<int>(
        key: const ValueKey('compose-toolbar-font-size'),
        tooltip: context.l10n.text('字号'),
        onSelected: (size) =>
            _editorCommand('fontSize', mailComposeFontPointToPixels(size)),
        child: IgnorePointer(
          child: TextButton.icon(
            style: textStyle,
            onPressed: () {},
            icon: const Icon(LucideIcons.caseUpper300, size: 15),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BnbuText(mailComposeFontPixelsToPointLabel(selectedSize)),
                const Icon(LucideIcons.chevronDown300, size: 13),
              ],
            ),
          ),
        ),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 8, child: BnbuText('8')),
          PopupMenuItem(value: 9, child: BnbuText('9')),
          PopupMenuItem(value: 10, child: BnbuText('10')),
          PopupMenuItem(value: 11, child: BnbuText('11')),
          PopupMenuItem(value: 12, child: BnbuText('12')),
          PopupMenuItem(value: 14, child: BnbuText('14')),
          PopupMenuItem(value: 16, child: BnbuText('16')),
          PopupMenuItem(value: 18, child: BnbuText('18')),
          PopupMenuItem(value: 20, child: BnbuText('20')),
          PopupMenuItem(value: 24, child: BnbuText('24')),
        ],
      );

  Widget _buildColorMenu(ButtonStyle iconStyle) => BnbuMenuButton<void>(
    key: const ValueKey('compose-toolbar-color'),
    tooltip: context.l10n.text('文字颜色与高亮'),
    padding: EdgeInsets.zero,
    itemBuilder: (_) => [
      PopupMenuItem<void>(
        enabled: false,
        height: 246,
        padding: EdgeInsets.zero,
        child: _DesktopColorPalette(
          onColor: (color) {
            Navigator.of(context).pop();
            _editorCommand('color', color);
          },
          onHighlight: (color) {
            Navigator.of(context).pop();
            _editorCommand('highlight', color);
          },
        ),
      ),
    ],
    child: IgnorePointer(
      child: IconButton(
        style: iconStyle,
        onPressed: () {},
        icon: const _ComposeColorGlyph(),
      ),
    ),
  );

  Widget _buildMoreFormatMenu(ButtonStyle iconStyle) => BnbuMenuButton<void>(
    key: const ValueKey('compose-toolbar-more'),
    tooltip: context.l10n.text('更多'),
    padding: EdgeInsets.zero,
    itemBuilder: (_) => [
      PopupMenuItem<void>(
        enabled: false,
        height: 112,
        padding: EdgeInsets.zero,
        child: _DesktopMoreFormatPanel(
          tableActive: _richEditorController.toolbarState.table,
          onCommand: (name, [value]) {
            Navigator.of(context).pop();
            if (name == 'align') {
              _editorCommand(name, value);
            } else {
              _editorCommand(name);
            }
          },
        ),
      ),
    ],
    child: IgnorePointer(
      child: TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 7),
        ),
        onPressed: () {},
        icon: const Icon(LucideIcons.ellipsis300, size: 16),
        label: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BnbuText('更多'),
            Icon(LucideIcons.chevronDown300, size: 13),
          ],
        ),
      ),
    ),
  );

  Widget _buildSignatureMenu(ButtonStyle iconStyle) =>
      BnbuMenuButton<MailComposeSignature>(
        key: const ValueKey('compose-toolbar-signature'),
        tooltip: context.l10n.text('签名'),
        icon: const Icon(LucideIcons.signature300, size: 17),
        onSelected: (signature) => unawaited(_selectSignature(signature)),
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: MailComposeSignature.none,
            checked: _signature == MailComposeSignature.none,
            child: const BnbuText('不使用签名'),
          ),
          CheckedPopupMenuItem(
            value: MailComposeSignature.bnbuMe,
            checked: _signature == MailComposeSignature.bnbuMe,
            child: const BnbuText('使用 BNBU.ME 签名'),
          ),
        ],
      );

  Widget _buildSmallUMenu(ButtonStyle iconStyle, {bool compact = false}) =>
      BnbuMenuButton<String>(
        key: const ValueKey('compose-toolbar-small-u'),
        tooltip: context.l10n.text('小U智能'),
        onSelected: (value) {
          if (value == 'ask') {
            unawaited(_askAssistantForDraft());
          } else {
            BnbuToast.show(context, '智能翻译暂未开放。', kind: BnbuToastKind.info);
          }
        },
        child: IgnorePointer(
          child: compact
              ? IconButton(
                  style: iconStyle,
                  onPressed: () {},
                  icon: const SmallULogo(size: 18, monochrome: true),
                )
              : TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {},
                  icon: const SmallULogo(size: 17, monochrome: true),
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BnbuText('小U智能'),
                      Icon(LucideIcons.chevronDown300, size: 13),
                    ],
                  ),
                ),
        ),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'ask', child: BnbuText('询问小U')),
          PopupMenuItem(value: 'translate', child: BnbuText('智能翻译')),
        ],
      );

  Future<void> _askAssistantForDraft() async {
    final launcher =
        AssistantContextScope.maybeOpenAssistantWithMailReferenceOf(context);
    if (launcher == null) {
      BnbuToast.show(context, '小U当前不可用。', kind: BnbuToastKind.warning);
      return;
    }
    await _refreshRichDocument();
    if (!mounted) return;
    final recipients = _assistantDraftRecipients();
    final subject = _subjectController.text.trim();
    final body = _serializedPlainText.trim();
    if (recipients.length > 4000 ||
        subject.length > 300 ||
        body.length > 12000) {
      BnbuToast.show(
        context,
        '草稿内容过长，暂时无法作为小U附件。',
        kind: BnbuToastKind.warning,
      );
      return;
    }
    try {
      await launcher(
        AssistantMailReference.draft(
          recipients: recipients,
          subject: subject,
          body: body,
        ),
      );
    } on Object {
      if (mounted) {
        BnbuToast.show(context, '暂时无法创建小U对话。', kind: BnbuToastKind.danger);
      }
    }
  }

  String _assistantDraftRecipients() {
    final fields = <String>[
      if (_toController.text.trim().isNotEmpty)
        '收件人：${_toController.text.trim()}',
      if (_ccController.text.trim().isNotEmpty)
        '抄送：${_ccController.text.trim()}',
      if (_bccController.text.trim().isNotEmpty)
        '密送：${_bccController.text.trim()}',
    ];
    return fields.join('\n');
  }

  Widget _buildSignaturePreview({required bool desktop}) {
    if (_signature != MailComposeSignature.bnbuMe) {
      return const SizedBox.shrink();
    }
    final tokens = context.bnbuTheme;
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    // Keep the signature visually separate from the keyboard toolbar whenever
    // there is enough usable height, without crowding a short keyboard view.
    final bottomBreathingRoom = desktop
        ? 12.0
        : (availableHeight >= 500 ? 52.0 : 16.0);
    final schoolSize = desktop ? 12.0 : 13.0;
    final nameSize = desktop ? 13.0 : 16.0;
    final sourceSize = desktop ? 11.0 : 12.0;
    return Padding(
      key: const ValueKey('compose-signature-preview'),
      padding: EdgeInsets.only(
        top: desktop ? 12 : 16,
        bottom: bottomBreathingRoom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('compose-signature-divider'),
              width: 126,
              height: 1,
              color: tokens.border,
            ),
            SizedBox(height: desktop ? 9 : 10),
            BnbuText(
              '北师港浸大BNBU',
              style: TextStyle(
                fontSize: schoolSize,
                height: 1.25,
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: desktop ? 2 : 3),
            BnbuText(
              _signatureName,
              style: TextStyle(
                fontSize: nameSize,
                height: 1.28,
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: desktop ? 2 : 3),
            BnbuText(
              '来自BNBU.ME',
              style: TextStyle(
                fontSize: sourceSize,
                height: 1.25,
                color: tokens.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientAutocomplete({
    required bool autofocus,
    required bool desktop,
  }) => _RecipientField(
    controller: _toController,
    directory: _recipientDirectory,
    label: '收件人',
    fieldKey: const ValueKey('compose-recipient-field'),
    avatarService: _senderAvatarService,
    desktop: desktop,
    autofocus: autofocus,
    trailing: TextButton(
      key: const ValueKey('compose-toggle-cc-bcc'),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.only(left: 6),
        foregroundColor: context.bnbuTheme.textSecondary,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      ),
      onPressed: () => setState(() => _showCarbonCopy = !_showCarbonCopy),
      child: BnbuText(_showCarbonCopy ? '收起' : '抄送／密送'),
    ),
  );

  Widget _buildMobileComposerToolbar() {
    final colors = MailSurfaceColors(context);
    final media = MediaQuery.of(context);
    final menuHeight =
        (media.size.height - media.viewInsets.bottom - media.padding.top - 64)
            .clamp(48.0, 560.0);
    return ColoredBox(
      key: const ValueKey('compose-editor-toolbar'),
      color: colors.dark ? const Color(0xFF242527) : const Color(0xFFF5F6F7),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 10),
            IconButton(
              key: const ValueKey('compose-add-attachment'),
              tooltip: context.l10n.text('添加附件'),
              onPressed: _isSending ? null : _pickAttachments,
              icon: Icon(
                LucideIcons.paperclip300,
                size: 24,
                color: colors.foreground,
              ),
            ),
            const Spacer(),
            BnbuMenuButton<String>(
              key: const ValueKey('compose-mobile-tools'),
              position: PopupMenuPosition.over,
              offset: Offset(0, -menuHeight),
              constraints: BoxConstraints(
                minWidth: 224,
                maxWidth: 320,
                maxHeight: menuHeight,
              ),
              tooltip: context.l10n.text('更多'),
              enabled: !_isSending,
              style: IconButton.styleFrom(fixedSize: const Size.square(44)),
              icon: Icon(
                LucideIcons.listFilter300,
                size: 24,
                color: colors.foreground,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'image':
                    _editorCommand('requestImage');
                  case 'link':
                    unawaited(_insertLink());
                  case 'bullets':
                    _editorCommand('bulletList');
                  case 'numbered':
                    _editorCommand('orderedList');
                  case 'quote':
                    _editorCommand('blockquote');
                  case 'divider':
                    _editorCommand('horizontalRule');
                  case 'signature-none':
                    unawaited(_selectSignature(MailComposeSignature.none));
                  case 'signature-bnbu':
                    unawaited(_selectSignature(MailComposeSignature.bnbuMe));
                  case 'ask':
                    unawaited(_askAssistantForDraft());
                  case 'translate':
                    BnbuToast.show(
                      context,
                      '智能翻译暂未开放。',
                      kind: BnbuToastKind.info,
                    );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'image', child: BnbuText('添加图片')),
                const PopupMenuItem(value: 'link', child: BnbuText('插入链接')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'bullets', child: BnbuText('项目列表')),
                const PopupMenuItem(value: 'numbered', child: BnbuText('编号列表')),
                const PopupMenuItem(value: 'quote', child: BnbuText('引用')),
                const PopupMenuItem(value: 'divider', child: BnbuText('分隔线')),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: 'signature-none',
                  checked: _signature == MailComposeSignature.none,
                  child: const BnbuText('不使用签名'),
                ),
                CheckedPopupMenuItem(
                  value: 'signature-bnbu',
                  checked: _signature == MailComposeSignature.bnbuMe,
                  child: const BnbuText('使用 BNBU.ME 签名'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'ask', child: BnbuText('询问小U')),
                const PopupMenuItem(
                  value: 'translate',
                  child: BnbuText('智能翻译'),
                ),
              ],
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotedBlock(MailMessageDetail original) {
    final tokens = context.bnbuTheme;
    final dateStr = original.date != null
        ? context.l10n.formatFullDateTime(original.date!)
        : '';
    return Padding(
      padding: EdgeInsets.only(top: tokens.space12),
      child: BnbuSurfaceCard(
        backgroundColor: tokens.surfaceMuted,
        padding: EdgeInsets.all(tokens.space16),
        child: Container(
          padding: EdgeInsets.only(left: tokens.space12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: tokens.border, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QuoteInfoLine(label: '发件人', value: original.sender),
              if (dateStr.isNotEmpty)
                _QuoteInfoLine(label: '时　间', value: dateStr),
              _QuoteInfoLine(label: '收件人', value: original.recipients),
              _QuoteInfoLine(label: '主　题', value: original.subject),
              SizedBox(height: tokens.space8),
              BnbuText(
                _truncateBody(original.body),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _extractEmail(String input) {
    // Extract first email address from "Name <email>, Name2 <email2>" or plain emails
    final emailRegex = RegExp(r'<([^>]+)>');
    final match = emailRegex.firstMatch(input);
    if (match != null) return match.group(1)?.trim() ?? input.trim();
    // plain email or comma-separated
    return input.split(',').first.trim();
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _ComposeField extends StatelessWidget {
  const _ComposeField({
    required this.label,
    required this.controller,
    this.fieldKey,
    this.dense = false,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final rowHeight = 52.0 + (textScale - 1).clamp(0, 2) * 32;
    final horizontalPadding = dense
        ? EdgeInsets.only(left: tokens.space16)
        : const EdgeInsets.symmetric(horizontal: 15);
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: horizontalPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: dense
                  ? 72
                  : 52 * MediaQuery.textScalerOf(context).scale(16) / 16,
              child: Align(
                alignment: Alignment.centerLeft,
                child: BnbuText(
                  '$label：',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: dense
                        ? tokens.textSecondary
                        : MailSurfaceColors(context).secondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MailRecipientOption extends StatelessWidget {
  const _MailRecipientOption({
    required this.suggestion,
    required this.highlighted,
    required this.senderAvatarService,
    required this.onTap,
  });

  final MailRecipientSuggestion suggestion;
  final bool highlighted;
  final MailSenderAvatarService senderAvatarService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Semantics(
      button: true,
      label: '${suggestion.displayName} ${suggestion.email}',
      child: InkWell(
        onTap: onTap,
        child: ColoredBox(
          color: highlighted ? tokens.surfaceMuted : Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space12,
              vertical: tokens.space8,
            ),
            child: Row(
              children: [
                MailSenderAvatar(
                  sender: '${suggestion.displayName} <${suggestion.email}>',
                  diameter: 36,
                  senderAvatarService: senderAvatarService,
                ),
                SizedBox(width: tokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: BnbuText(
                              suggestion.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          SizedBox(width: tokens.space8),
                          Flexible(
                            child: BnbuText(
                              suggestion.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tokens.brandBlue),
                            ),
                          ),
                        ],
                      ),
                      if (suggestion.contextLabel.isNotEmpty)
                        BnbuText(
                          suggestion.contextLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: tokens.textSecondary),
                        ),
                    ],
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

class _DesktopCommandDivider extends StatelessWidget {
  const _DesktopCommandDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: color,
  );
}

class _ComposeColorGlyph extends StatelessWidget {
  const _ComposeColorGlyph();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 17,
    height: 19,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'A',
          style: TextStyle(
            fontSize: 15,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 2),
        ColoredBox(
          color: Color(0xFF3187F4),
          child: SizedBox(width: 14, height: 2),
        ),
      ],
    ),
  );
}

class _FontFamilyChoice {
  const _FontFamilyChoice(this.label, this.cssFamily);

  final String label;
  final String cssFamily;
}

const _mailFontChoices = <_FontFamilyChoice>[
  _FontFamilyChoice('默认字体', 'system-ui'),
  _FontFamilyChoice('苹方', 'PingFang SC, sans-serif'),
  _FontFamilyChoice('宋体', 'Songti SC, serif'),
  _FontFamilyChoice('楷体', 'Kaiti SC, serif'),
  _FontFamilyChoice('Helvetica Neue', 'Helvetica Neue, Arial, sans-serif'),
  _FontFamilyChoice('Arial', 'Arial, sans-serif'),
  _FontFamilyChoice('Times New Roman', 'Times New Roman, serif'),
];

class _DesktopFontMenuPanel extends StatefulWidget {
  const _DesktopFontMenuPanel({
    required this.currentFamily,
    required this.onSelected,
  });

  final String? currentFamily;
  final ValueChanged<String> onSelected;

  @override
  State<_DesktopFontMenuPanel> createState() => _DesktopFontMenuPanelState();
}

class _DesktopFontMenuPanelState extends State<_DesktopFontMenuPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final filtered = _mailFontChoices
        .where((choice) {
          final needle = _query.trim().toLowerCase();
          return needle.isEmpty ||
              choice.label.toLowerCase().contains(needle) ||
              choice.cssFamily.toLowerCase().contains(needle);
        })
        .toList(growable: false);
    return SizedBox(
      width: 260,
      height: 336,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
            child: BnbuRevealSearch(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              hintText: context.l10n.text('搜索字体'),
              mode: BnbuRevealSearchMode.local,
              surfaceColor: tokens.surface,
              controlKey: const ValueKey('compose-font-search'),
              closeKey: const ValueKey('compose-font-search-close'),
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final choice = filtered[index];
                  final selected =
                      widget.currentFamily == choice.cssFamily ||
                      (choice.cssFamily == 'system-ui' &&
                          (widget.currentFamily == null ||
                              widget.currentFamily!.isEmpty));
                  return InkWell(
                    onTap: () => widget.onSelected(choice.cssFamily),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: BnbuText(
                              choice.label,
                              style: TextStyle(
                                fontFamily: choice.cssFamily,
                                fontSize: 13,
                                color: tokens.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(
                              LucideIcons.check300,
                              size: 15,
                              color: tokens.brandBlue,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopColorPalette extends StatefulWidget {
  const _DesktopColorPalette({
    required this.onColor,
    required this.onHighlight,
  });

  final ValueChanged<String> onColor;
  final ValueChanged<String> onHighlight;

  @override
  State<_DesktopColorPalette> createState() => _DesktopColorPaletteState();
}

class _DesktopColorPaletteState extends State<_DesktopColorPalette> {
  final _hexController = TextEditingController(text: '#3187F4');

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String? get _validHex {
    final value = _hexController.text.trim();
    return RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value) ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    const colors = <Color>[
      Color(0xFF172235),
      Color(0xFF3187F4),
      Color(0xFFD94841),
      Color(0xFF1E9A5B),
      Color(0xFF8A52D7),
      Color(0xFFE18A20),
    ];
    Widget section(String label, ValueChanged<String> apply) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BnbuText(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          children: [
            for (final color in colors)
              InkResponse(
                onTap: () => apply(
                  '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                ),
                radius: 16,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.border),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return SizedBox(
      width: 244,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            section('文字颜色', widget.onColor),
            const SizedBox(height: 12),
            section('文字高亮', widget.onHighlight),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('compose-color-hex'),
                    controller: _hexController,
                    onChanged: (_) => setState(() {}),
                    maxLength: 7,
                    decoration: const InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: '#3187F4',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _validHex == null
                      ? null
                      : () => widget.onColor(_validHex!),
                  child: const BnbuText('文字'),
                ),
                TextButton(
                  onPressed: _validHex == null
                      ? null
                      : () => widget.onHighlight(_validHex!),
                  child: const BnbuText('高亮'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopMoreFormatPanel extends StatelessWidget {
  const _DesktopMoreFormatPanel({
    required this.tableActive,
    required this.onCommand,
  });

  final bool tableActive;
  final void Function(String name, [String? value]) onCommand;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    Widget action(
      IconData icon,
      String tooltip,
      String command, [
      String? value,
    ]) => IconButton(
      tooltip: tooltip,
      onPressed: () => onCommand(command, value),
      icon: Icon(icon, size: 17),
      color: tokens.textPrimary,
      visualDensity: VisualDensity.compact,
    );
    Widget group(
      IconData icon,
      String tooltip,
      List<_DesktopFormatAction> actions, {
      bool enabled = true,
      Key? buttonKey,
    }) => BnbuMenuButton<_DesktopFormatAction>(
      key: buttonKey,
      enabled: enabled,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      onSelected: (action) => onCommand(action.command, action.value),
      itemBuilder: (_) => [
        for (final action in actions)
          PopupMenuItem(
            value: action,
            child: Row(
              children: [
                Icon(action.icon, size: 16, color: tokens.textSecondary),
                const SizedBox(width: 9),
                BnbuText(action.label),
              ],
            ),
          ),
      ],
      child: Icon(
        icon,
        size: 18,
        color: enabled ? tokens.textPrimary : tokens.textMuted,
      ),
    );
    return SizedBox(
      width: 382,
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          children: [
            action(LucideIcons.strikethrough300, '删除线', 'strike'),
            action(LucideIcons.highlighter300, '清除高亮', 'clearHighlight'),
            group(LucideIcons.alignLeft300, '对齐', const [
              _DesktopFormatAction(
                '左对齐',
                LucideIcons.alignLeft300,
                'align',
                'left',
              ),
              _DesktopFormatAction(
                '居中',
                LucideIcons.alignCenter300,
                'align',
                'center',
              ),
              _DesktopFormatAction(
                '右对齐',
                LucideIcons.alignRight300,
                'align',
                'right',
              ),
              _DesktopFormatAction(
                '两端对齐',
                LucideIcons.alignJustify300,
                'align',
                'justify',
              ),
            ]),
            group(LucideIcons.list300, '列表', const [
              _DesktopFormatAction('项目列表', LucideIcons.list300, 'bulletList'),
              _DesktopFormatAction(
                '编号列表',
                LucideIcons.listOrdered300,
                'orderedList',
              ),
            ]),
            action(LucideIcons.indentIncrease300, '增加缩进', 'sink'),
            action(LucideIcons.indentDecrease300, '减少缩进', 'lift'),
            group(LucideIcons.rows3300, '行距', const [
              _DesktopFormatAction(
                '紧凑行距',
                LucideIcons.rows3300,
                'lineHeight',
                '1.4',
              ),
              _DesktopFormatAction(
                '标准行距',
                LucideIcons.rows3300,
                'lineHeight',
                '1.6',
              ),
              _DesktopFormatAction(
                '宽松行距',
                LucideIcons.rows3300,
                'lineHeight',
                '2',
              ),
            ]),
            action(LucideIcons.quote300, '引用', 'blockquote'),
            action(LucideIcons.minus300, '分隔线', 'horizontalRule'),
            group(
              LucideIcons.table300,
              '表格编辑',
              const [
                _DesktopFormatAction(
                  '表格前插入行',
                  LucideIcons.table300,
                  'addRowBefore',
                ),
                _DesktopFormatAction(
                  '表格后插入行',
                  LucideIcons.table300,
                  'addRowAfter',
                ),
                _DesktopFormatAction(
                  '删除当前行',
                  LucideIcons.trash2300,
                  'deleteRow',
                ),
                _DesktopFormatAction(
                  '表格前插入列',
                  LucideIcons.columns300,
                  'addColumnBefore',
                ),
                _DesktopFormatAction(
                  '表格后插入列',
                  LucideIcons.columns300,
                  'addColumnAfter',
                ),
                _DesktopFormatAction(
                  '删除当前列',
                  LucideIcons.trash2300,
                  'deleteColumn',
                ),
                _DesktopFormatAction(
                  '合并或拆分单元格',
                  LucideIcons.merge300,
                  'mergeOrSplit',
                ),
                _DesktopFormatAction(
                  '切换表头行',
                  LucideIcons.tableProperties300,
                  'toggleHeaderRow',
                ),
                _DesktopFormatAction(
                  '删除表格',
                  LucideIcons.trash2300,
                  'deleteTable',
                ),
              ],
              enabled: tableActive,
              buttonKey: const ValueKey('compose-more-table'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopFormatAction {
  const _DesktopFormatAction(this.label, this.icon, this.command, [this.value]);

  final String label;
  final IconData icon;
  final String command;
  final String? value;
}
