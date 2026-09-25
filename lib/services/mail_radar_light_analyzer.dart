part of 'mail_radar_analyzer.dart';

/// The inbox classifier used by the current application. The older analyzer
/// remains available to decode and regression-test the previous contract.
class LightMailRadarAnalyzer extends SmallUMailRadarAnalyzer {
  const LightMailRadarAnalyzer({
    required super.assistantService,
    super.radarService,
    super.attachmentService,
    super.attachmentProcessor = const MailRadarAttachmentProcessor(
      includeVisuals: false,
    ),
    super.targetLanguageTagProvider,
  });

  /// Only inspect documents when the body cannot independently explain the
  /// message or explicitly delegates the essential information to them.
  static bool needsAttachmentEvidence(String body) {
    final meaningful = body.replaceAll(RegExp(r'\s+'), '').length;
    if (meaningful < 96) return true;
    final delegated = RegExp(
      r'(详见|詳見|参阅|參閱|查看|见|見|see|refer\s+to|consult|截止|日期|要求).{0,24}'
      r'(附件|附檔|attached|attachment)|'
      r'(附件|附檔|attached|attachment).{0,40}(截止|日期|时间|時間|要求|deadline|schedule|instructions)',
      caseSensitive: false,
    ).hasMatch(body);
    if (!delegated) return false;
    const date =
        r'(\d{1,2}\s*[月/]\s*\d{1,2}|\d{4}-\d{1,2}-\d{1,2}|'
        r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2})';
    const deadline = r'(截止|提交|报名|報名|deadline|due|submit|before)';
    final explicitDeadline = RegExp(
      '$deadline.{0,72}$date|$date.{0,72}$deadline',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(body);
    return !explicitDeadline;
  }

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    void requireActive() {
      if (!(isOperationActive?.call() ?? true)) {
        throw const AiAssistantOperationCancelledException();
      }
    }

    requireActive();
    if (looksLikeMailRecallSubject(detail.subject)) {
      // The legacy entry returns a deterministic recall result before any
      // account, attachment or Provider operation.
      return super.analyze(
        clientRequestId: clientRequestId,
        username: username,
        credentials: credentials,
        summary: summary,
        detail: detail,
        mailService: mailService,
        isOperationActive: isOperationActive,
      );
    }
    if (!await assistantService.isEnabled(username)) {
      throw const MailServiceException('请先在“我的”中开启小U，再使用邮件雷达。');
    }
    requireActive();
    final validity = detail.mailboxUidValidity ?? summary.mailboxUidValidity;
    if (validity == null || validity <= 0 || detail.uid <= 0) {
      throw const FormatException('邮件身份已失效，请刷新邮箱。');
    }
    final language = normalizeMailRadarTargetLanguageTag(
      targetLanguageTagProvider(),
    );
    final sanitizedBody = _sanitizeSensitive(detail.body);
    final excerpt = _balancedExcerpt(sanitizedBody, 7800);
    final coverage = sanitizedBody.isEmpty
        ? 'unread'
        : excerpt != sanitizedBody || sanitizedBody != detail.body
        ? 'partial'
        : 'complete';
    final documents = needsAttachmentEvidence(sanitizedBody)
        ? detail.attachments
              .where(
                (item) =>
                    !item.mimeType.toLowerCase().startsWith('image/') &&
                    !looksLikeInlineImageAttachment(item.name, item.mimeType),
              )
              .take(3)
              .toList(growable: false)
        : const <MailAttachment>[];
    final prepared = await _prepareAttachments(
      credentials: credentials,
      detail: detail,
      attachments: documents,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
    requireActive();
    final attachmentPayload = _attachmentPayload(
      prepared
          .map((item) {
            final boundedText = _balancedExcerpt(item.text, 4000);
            return MailRadarPreparedAttachment(
              name: item.name,
              text: boundedText,
              note: item.note,
              sourceComplete:
                  item.sourceComplete &&
                  item.visuals.isEmpty &&
                  boundedText == item.text,
            );
          })
          .toList(growable: false),
    );
    // A text-only classifier never turns inline images or QR codes into a
    // second vision workload. The normal reader still displays original media.
    final evidenceAttachments = attachmentPayload.modelAttachments
        .where((item) => item.mimeType.startsWith('text/'))
        .toList(growable: false);
    final sender = _senderParts(detail.sender);
    final result = await radarService.analyzeMailRadar(
      username: username,
      request: MailRadarRemoteRequest(
        clientRequestId: clientRequestId,
        uid: detail.uid,
        mailboxUidValidity: validity,
        senderName: _limit(sender.$1, 160),
        senderEmail: _limit(sender.$2, 254),
        subject: _limit(detail.subject, 300),
        receivedAt: detail.date ?? summary.date ?? DateTime.now(),
        bodyExcerpt: excerpt,
        recipients: _limit(_sanitizeSensitive(detail.recipients), 500),
        cc: _limit(_sanitizeSensitive(detail.cc ?? ''), 500),
        listId: _limit(_sanitizeSensitive(detail.listId ?? ''), 160),
        precedence: _limit(_sanitizeSensitive(detail.precedence ?? ''), 80),
        replyHeaders: '',
        attachmentContext: _limit(attachmentPayload.promptContext, 900),
        sourceLinks: const [],
        attachments: evidenceAttachments,
        targetLanguageTag: language,
        lightweight: true,
        bodySha256: sha256.convert(utf8.encode(sanitizedBody)).toString(),
        sourceFolder: detail.folder,
        bodyCoverage: coverage,
      ),
      isOperationActive: isOperationActive,
    );
    requireActive();
    final json = result.result;
    final categoryName = json['category'];
    final priorityName = json['priority'];
    final rawSummary = json['summary_zh'];
    if (rawSummary is! String ||
        !MailRadarCategory.values.any((value) => value.name == categoryName) ||
        !MailRadarPriority.values.any((value) => value.name == priorityName)) {
      throw const AiAssistantException('邮件标签响应格式无效。');
    }
    final category = MailRadarCategory.values.byName(categoryName as String);
    final promotional =
        category != MailRadarCategory.direct &&
        looksLikeOptionalBroadcastPromotion(
          subject: detail.subject,
          sender: detail.sender,
          content: excerpt,
        );
    final corpus = [
      excerpt,
      ...evidenceAttachments.map(
        (item) => utf8.decode(item.bytes, allowMalformed: true),
      ),
    ].join('\n');
    final precision = json['deadline_precision'];
    final deadline = precision == 'date' || precision == 'datetime'
        ? _verifiedDeadline(json, corpus)
        : null;
    final oneLine = rawSummary.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.isEmpty && category != MailRadarCategory.deadline) {
      throw const AiAssistantException('邮件标签响应缺少摘要。');
    }
    final rawDeadlineText = _string(json, 'deadline_text');
    return MailRadarItem(
      key: mailRadarMessageKey(detail.folder, validity, detail.uid),
      sourceFolder: detail.folder,
      originalIsSeen: detail.isSeen,
      hasSourceAttachments:
          detail.attachments.isNotEmpty || summary.hasAttachments,
      uid: detail.uid,
      mailboxUidValidity: validity,
      subject: detail.subject,
      sender: detail.sender,
      recipients: detail.recipients,
      receivedAt: detail.date ?? summary.date ?? DateTime.now(),
      summaryZh: String.fromCharCodes(oneLine.runes.take(80)),
      translationZh: '',
      priority: promotional
          ? MailRadarPriority.normal
          : MailRadarPriority.values.byName(priorityName as String),
      category: promotional ? MailRadarCategory.notice : category,
      senderRole: category == MailRadarCategory.direct
          ? MailRadarSenderRole.personal
          : MailRadarSenderRole.unknown,
      actionZh: '',
      deadlineText: deadline != null || corpus.contains(rawDeadlineText)
          ? rawDeadlineText
          : '',
      deadlineAt: deadline,
      deadlinePrecision: deadline == null ? 'none' : precision as String,
      deadlineEvidence: deadline == null
          ? ''
          : _string(json, 'deadline_evidence'),
      bodyCoverage: coverage,
      attachmentCoverage: attachmentPayload.coverage,
      relatedThreadKey: '',
      attachmentNotes: const [],
      analyzedAt: DateTime.now(),
      analysisRequestId: result.clientRequestId,
      analysisLanguageTag: language,
      toolUses: const [],
      memorySuggestions: const [],
    );
  }
}
