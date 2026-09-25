import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/assistant_models.dart';
import '../models/mail_models.dart';
import '../models/mail_radar_models.dart';
import 'ai_assistant_service.dart';
import 'mail_radar_attachment_processor.dart';
import 'mail_service.dart';
import 'mail_source_service.dart';
import 'sync/account_sync_storage.dart';

part 'mail_radar_light_analyzer.dart';
part 'mail_source_analyzer.dart';

abstract interface class MailRadarAnalyzer {
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  });
}

List<Uri> extractMailRadarHttpLinks(MailMessageDetail detail) {
  final candidates = <String>[];
  candidates.addAll(
    RegExp(
      r'''https?://[^\s<>"']+''',
      caseSensitive: false,
    ).allMatches(detail.body).map((match) => match.group(0) ?? ''),
  );
  final html = detail.htmlBody;
  if (html != null && html.trim().isNotEmpty) {
    final fragment = html_parser.parseFragment(html);
    candidates.addAll(
      fragment
          .querySelectorAll('a[href]')
          .map((element) => element.attributes['href'] ?? ''),
    );
  }

  final links = <Uri>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    final normalized = candidate.trim().replaceFirst(
      RegExp(r'[\)\]\}\.,;:!?]+$'),
      '',
    );
    final uri = Uri.tryParse(normalized);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (scheme != 'https' && scheme != 'http') ||
        !seen.add(uri.toString())) {
      continue;
    }
    links.add(uri);
    if (links.length == 16) break;
  }
  return links;
}

class SmallUMailRadarAnalyzer implements MailRadarAnalyzer {
  static const maxConcurrentAttachmentAnalyses = 2;
  static const maxCombinedAttachmentTextCharacters = 30000;
  static const maxAttachmentTextCharactersPerFile = 12000;
  static const maxModelAttachments = 3;

  const SmallUMailRadarAnalyzer({
    required this.assistantService,
    AiAssistantMailRadarService? radarService,
    Object? attachmentService,
    this.attachmentProcessor = const MailRadarAttachmentProcessor(),
    this.targetLanguageTagProvider = _defaultTargetLanguageTag,
  }) : radarService =
           radarService ?? attachmentService as AiAssistantMailRadarService;

  final AiAssistantService assistantService;
  final AiAssistantMailRadarService radarService;
  final MailRadarAttachmentProcessor attachmentProcessor;
  final String Function() targetLanguageTagProvider;

  static String _defaultTargetLanguageTag() =>
      mailRadarDefaultTargetLanguageTag;

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
    final targetLanguageTag = normalizeMailRadarTargetLanguageTag(
      targetLanguageTagProvider(),
    );
    final receivedAt = detail.date ?? summary.date ?? DateTime.now();
    final uidValidity = detail.mailboxUidValidity ?? summary.mailboxUidValidity;
    if (uidValidity == null) {
      throw const FormatException('邮件缺少 UIDVALIDITY，无法安全缓存分析结果。');
    }
    if (looksLikeMailRecallSubject(detail.subject)) {
      return MailRadarItem(
        key: mailRadarMessageKey(detail.folder, uidValidity, detail.uid),
        sourceFolder: detail.folder,
        originalIsSeen: detail.isSeen,
        uid: detail.uid,
        mailboxUidValidity: uidValidity,
        subject: detail.subject,
        sender: detail.sender,
        recipients: detail.recipients,
        receivedAt: receivedAt,
        summaryZh: _recalledBySender(targetLanguageTag),
        translationZh: '',
        priority: MailRadarPriority.normal,
        category: MailRadarCategory.notice,
        senderRole: MailRadarSenderRole.system,
        actionZh: '',
        deadlineText: '',
        relatedThreadKey: _normalizedSubject(detail.subject),
        attachmentNotes: const [],
        analyzedAt: DateTime.now(),
        isRecallNotice: true,
        analysisRequestId: clientRequestId,
        analysisLanguageTag: targetLanguageTag,
      );
    }
    if (!await assistantService.isEnabled(username)) {
      throw const MailServiceException('请先在“我的”中开启小U，再使用邮件雷达。');
    }
    final attachmentWork = <MailAttachment>[];
    var hasInlineImages = false;
    for (final attachment in detail.attachments) {
      if (looksLikeInlineImageAttachment(
        attachment.name,
        attachment.mimeType,
      )) {
        hasInlineImages = true;
        continue;
      }
      attachmentWork.add(attachment);
    }
    final preparedAttachments = await _prepareAttachments(
      credentials: credentials,
      detail: detail,
      attachments: attachmentWork,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
    final attachmentPayload = _attachmentPayload(preparedAttachments);

    final sender = _senderParts(detail.sender);
    final sanitizedBody = _sanitizeSensitive(detail.body);
    final cleanBody = _balancedExcerpt(sanitizedBody, 7800);
    final bodyCoverage =
        sanitizedBody.length > 7800 || sanitizedBody != detail.body
        ? 'partial'
        : 'complete';
    final sourceLinks = extractMailRadarHttpLinks(detail);
    final result = await radarService.analyzeMailRadar(
      username: username,
      request: MailRadarRemoteRequest(
        clientRequestId: clientRequestId,
        uid: detail.uid,
        mailboxUidValidity: uidValidity,
        senderName: _limit(sender.$1, 160),
        senderEmail: _limit(sender.$2, 254),
        subject: _limit(detail.subject, 300),
        receivedAt: receivedAt,
        bodyExcerpt: cleanBody,
        recipients: _limit(_sanitizeSensitive(detail.recipients), 500),
        cc: _limit(_sanitizeSensitive(detail.cc ?? ''), 500),
        listId: _limit(_sanitizeSensitive(detail.listId ?? ''), 160),
        precedence: _limit(_sanitizeSensitive(detail.precedence ?? ''), 80),
        replyHeaders: _limit(
          _sanitizeSensitive(
            '${detail.inReplyTo ?? ''} ${detail.references ?? ''}',
          ),
          320,
        ),
        attachmentContext: _limit(
          '正文覆盖：$bodyCoverage\n${attachmentPayload.promptContext}',
          2000,
        ),
        sourceLinks: sourceLinks
            .map(_redactedUrlForAnalysis)
            .toList(growable: false),
        attachments: attachmentPayload.modelAttachments,
        targetLanguageTag: targetLanguageTag,
      ),
      isOperationActive: isOperationActive,
    );
    final json = result.result;
    final attachmentNotes = _attachmentNotes(
      json['attachment_notes'],
      preparedAttachments,
      attachmentPayload.coverage,
    );
    final actionLinks = _actionLinks(json['action_links'], sourceLinks);
    final category = _category(json['category'] as String?);
    final senderRole = _senderRole(json['sender_role'] as String?);
    final direct = json['is_direct_correspondence'] == true;
    final needsTranslation = json['needs_translation'] == true;
    final recallNotice =
        json['is_recall_notice'] == true ||
        looksLikeMailRecallSubject(detail.subject);
    final promotionalBroadcast =
        !direct &&
        looksLikeOptionalBroadcastPromotion(
          subject: detail.subject,
          sender: detail.sender,
          content: cleanBody,
        );
    final resolvedCategory = direct
        ? MailRadarCategory.direct
        : promotionalBroadcast
        ? MailRadarCategory.notice
        : category;
    return MailRadarItem(
      key: mailRadarMessageKey(detail.folder, uidValidity, detail.uid),
      sourceFolder: detail.folder,
      originalIsSeen: detail.isSeen,
      uid: detail.uid,
      mailboxUidValidity: uidValidity,
      subject: detail.subject,
      sender: detail.sender,
      recipients: detail.recipients,
      receivedAt: receivedAt,
      summaryZh: recallNotice
          ? _recalledBySender(targetLanguageTag)
          : _string(
              json,
              'summary_zh',
              fallback: _missingSummary(targetLanguageTag),
            ),
      translationZh: !recallNotice && needsTranslation
          ? _string(json, 'translation_zh', fallback: cleanBody)
          : '',
      priority: recallNotice || promotionalBroadcast
          ? MailRadarPriority.normal
          : _priority(json['priority'] as String?),
      category: resolvedCategory,
      senderRole: direct && senderRole == MailRadarSenderRole.unknown
          ? MailRadarSenderRole.personal
          : senderRole,
      actionZh: recallNotice ? '' : _string(json, 'action_zh'),
      actionLinks: recallNotice ? const [] : actionLinks,
      deadlineText: recallNotice
          ? ''
          : normalizeMailRadarDeadlineTimezone(_string(json, 'deadline_text')),
      bodyCoverage: bodyCoverage,
      attachmentCoverage: attachmentPayload.coverage,
      messageHash: _messageHashes(detail.messageId ?? '').firstOrNull ?? '',
      referenceHashes: _messageHashes(
        '${detail.inReplyTo ?? ''} ${detail.references ?? ''}',
      ),
      deadlineAt: _verifiedDeadline(json, cleanBody),
      deadlineEvidence: _verifiedDeadline(json, cleanBody) == null
          ? ''
          : _string(json, 'deadline_evidence'),
      relatedThreadKey: _string(
        json,
        'related_thread_key',
        fallback: _normalizedSubject(detail.subject),
      ),
      attachmentNotes: recallNotice ? const [] : attachmentNotes,
      analyzedAt: DateTime.now(),
      isRecallNotice: recallNotice,
      hasInlineImages: !recallNotice && hasInlineImages,
      analysisRequestId: result.clientRequestId,
      toolUses: result.toolUses,
      memorySuggestions: result.memorySuggestions,
      analysisLanguageTag: targetLanguageTag,
    );
  }

  String _recalledBySender(String targetLanguageTag) =>
      switch (targetLanguageTag) {
        'en' => 'Recalled by sender',
        'zh-Hant' => '發件人已撤回',
        _ => '发件人已撤回',
      };

  String _missingSummary(String targetLanguageTag) =>
      switch (targetLanguageTag) {
        'en' => 'Xiao U did not generate a summary',
        'zh-Hant' => '小U未生成摘要',
        _ => '小U未生成摘要',
      };

  Future<List<MailRadarPreparedAttachment>> _prepareAttachments({
    required MailAccessCredentials credentials,
    required MailMessageDetail detail,
    required List<MailAttachment> attachments,
    required MailService mailService,
    required bool Function()? isOperationActive,
  }) async {
    if (attachments.isEmpty) return const [];
    final prepared = List<MailRadarPreparedAttachment?>.filled(
      attachments.length,
      null,
    );
    var nextIndex = 0;
    Future<void> runWorker() async {
      while (nextIndex < attachments.length) {
        final index = nextIndex++;
        final attachment = attachments[index];
        if (index >= 6) {
          prepared[index] = MailRadarPreparedAttachment(
            name: attachment.name,
            note: '未读取：本次附件预算已用完',
          );
          continue;
        }
        try {
          prepared[index] = await attachmentProcessor.prepare(
            credentials: credentials,
            message: detail,
            attachment: attachment,
            mailService: mailService,
            isOperationActive: isOperationActive,
          );
        } catch (error) {
          if (error is AiAssistantOperationCancelledException) rethrow;
          prepared[index] = MailRadarPreparedAttachment(
            name: attachment.name,
            note: '本机读取失败',
          );
        }
      }
    }

    final workerCount = attachments.length < maxConcurrentAttachmentAnalyses
        ? attachments.length
        : maxConcurrentAttachmentAnalyses;
    await Future.wait([
      for (var index = 0; index < workerCount; index++) runWorker(),
    ]);
    return prepared.whereType<MailRadarPreparedAttachment>().toList(
      growable: false,
    );
  }

  ({
    String promptContext,
    List<AssistantInputAttachment> modelAttachments,
    Map<String, String> coverage,
  })
  _attachmentPayload(List<MailRadarPreparedAttachment> prepared) {
    if (prepared.isEmpty) {
      return (
        promptContext: '无',
        modelAttachments: const [],
        coverage: const {},
      );
    }
    final promptLines = <String>[];
    final combinedText = StringBuffer();
    final visuals = <AssistantInputAttachment>[];
    final coverage = <String, String>{};
    var remainingText = maxCombinedAttachmentTextCharacters;
    for (final item in prepared) {
      if (item.note.isNotEmpty) {
        promptLines.add('${item.name}：${item.note}');
        coverage[item.name] = 'unread';
        continue;
      }
      var included = false;
      var partial = !item.sourceComplete;
      final safeText = _sanitizeSensitive(item.text.trim());
      partial = partial || safeText != item.text.trim();
      if (remainingText >= 80 && safeText.isNotEmpty) {
        final excerpt = _balancedExcerpt(
          safeText,
          remainingText < maxAttachmentTextCharactersPerFile
              ? remainingText
              : maxAttachmentTextCharactersPerFile,
        );
        if (excerpt.isNotEmpty) {
          combinedText.writeln('附件：${item.name}');
          combinedText.writeln(excerpt);
          combinedText.writeln();
          remainingText -= excerpt.length;
          included = true;
          partial = partial || excerpt.length < safeText.length;
        }
      }
      // Reserve one model slot for combined text whenever any text exists.
      final visualBudget = prepared.any((entry) => entry.text.trim().isNotEmpty)
          ? 2
          : 3;
      final selectedVisuals = item.visuals
          .take(visualBudget - visuals.length)
          .toList();
      visuals.addAll(selectedVisuals);
      included = included || selectedVisuals.isNotEmpty;
      partial =
          partial ||
          selectedVisuals.length < item.visuals.length ||
          (item.text.isNotEmpty && remainingText == 0);
      coverage[item.name] = !included
          ? 'unread'
          : partial
          ? 'partial'
          : 'complete';
      promptLines.add('${item.name}：${coverage[item.name]}');
    }
    final modelAttachments = <AssistantInputAttachment>[];
    if (combinedText.isNotEmpty) {
      modelAttachments.add(
        AssistantInputAttachment(
          name: '邮件附件提取文本.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(utf8.encode(combinedText.toString())),
        ),
      );
    }
    modelAttachments.addAll(
      visuals.take(maxModelAttachments - modelAttachments.length),
    );
    return (
      promptContext: _limit(promptLines.join('\n'), 900),
      modelAttachments: List.unmodifiable(modelAttachments),
      coverage: Map.unmodifiable(coverage),
    );
  }

  List<String> _attachmentNotes(
    Object? raw,
    List<MailRadarPreparedAttachment> prepared,
    Map<String, String> coverage,
  ) {
    final allowedNames = {
      for (final item in prepared)
        if (item.hasAnalyzableContent && coverage[item.name] != 'unread')
          item.name: item.name,
    };
    final summaries = <String, String>{};
    if (raw is List) {
      for (final value in raw.whereType<Map<String, dynamic>>()) {
        final requestedName = value['name']?.toString().trim() ?? '';
        final name = allowedNames[requestedName];
        final summary = value['summary_zh']?.toString().trim() ?? '';
        if (name == null || summary.isEmpty || summaries.containsKey(name)) {
          continue;
        }
        summaries[name] = _limit(summary, 500);
      }
    }
    return [
      for (final item in prepared)
        if (item.note.isNotEmpty)
          '${item.name}：${item.note}'
        else if (coverage[item.name] == 'unread')
          '${item.name}：本次未读取'
        else if (summaries[item.name] case final summary?)
          '${item.name}：$summary',
    ];
  }

  String _balancedExcerpt(String value, int max) {
    if (max <= 0) return '';
    if (value.length <= max) return value;
    if (max < 80) return String.fromCharCodes(value.runes.take(max));
    final headLength = (max * .7).floor();
    final tailLength = max - headLength - 18;
    return '${value.substring(0, headLength)}\n...[中间省略]...\n${value.substring(value.length - tailLength)}';
  }

  List<MailRadarActionLink> _actionLinks(Object? raw, List<Uri> sourceLinks) {
    if (raw is! List || sourceLinks.isEmpty) return const [];
    final result = <MailRadarActionLink>[];
    final selected = <int>{};
    for (final value in raw.whereType<Map<String, dynamic>>()) {
      final rawIndex = value['source_index'];
      final sourceIndex = rawIndex is int
          ? rawIndex
          : int.tryParse(rawIndex?.toString() ?? '');
      if (sourceIndex == null ||
          sourceIndex < 1 ||
          sourceIndex > sourceLinks.length ||
          !selected.add(sourceIndex)) {
        continue;
      }
      final label = _string(value, 'label', fallback: '打开相关链接');
      result.add(
        MailRadarActionLink(label: _limit(label, 60), sourceIndex: sourceIndex),
      );
      if (result.length == 4) break;
    }
    return result;
  }

  String _redactedUrlForAnalysis(Uri uri) {
    final withoutFragment = uri.replace(fragment: '');
    var redacted = withoutFragment;
    if (withoutFragment.queryParameters.isNotEmpty) {
      final query = <String, String>{};
      for (final entry in withoutFragment.queryParameters.entries) {
        final sensitive = RegExp(
          r'(token|key|auth|signature|sig|code|session|ticket|password)',
          caseSensitive: false,
        ).hasMatch(entry.key);
        query[entry.key] = sensitive ? '[REDACTED]' : _limit(entry.value, 120);
      }
      redacted = withoutFragment.replace(queryParameters: query);
    }
    final value = redacted.toString();
    if (value.length <= 500) return value;

    // Tracking URLs can carry kilobytes of path/query data. The model only
    // needs a recognizable source and an index; the original URI remains on
    // device for the confirmed open action.
    return Uri(
      scheme: withoutFragment.scheme,
      host: withoutFragment.host,
      port: withoutFragment.hasPort ? withoutFragment.port : null,
    ).toString();
  }

  (String, String) _senderParts(String value) {
    final match = RegExp(
      r'^(.*?)\s*<([^<>]+@[^<>]+)>$',
    ).firstMatch(value.trim());
    if (match != null) {
      return (match.group(1)?.trim() ?? '', match.group(2) ?? '');
    }
    final email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+').firstMatch(value);
    return (
      value.replaceAll(email?.group(0) ?? '', '').trim(),
      email?.group(0) ?? '',
    );
  }

  String _sanitizeSensitive(String value) {
    final lines = value.split(RegExp(r'\r?\n'));
    return lines
        .where((line) {
          final lowered = line.toLowerCase();
          return !RegExp(
            r'(^|\b)(password|passcode|cookie|authorization|api[_ -]?key|access[_ -]?token|refresh[_ -]?token)\s*[:=]',
          ).hasMatch(lowered);
        })
        .map(_redactSensitiveUrlsInText)
        .join('\n');
  }

  String _redactSensitiveUrlsInText(String value) => value.replaceAllMapped(
    RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
    (match) {
      final uri = Uri.tryParse(match.group(0) ?? '');
      return uri == null ? '[REDACTED URL]' : _redactedUrlForAnalysis(uri);
    },
  );

  List<String> _messageHashes(String value) => RegExp(r'<[^<>\s]+>')
      .allMatches(value)
      .take(32)
      .map((match) => sha256.convert(utf8.encode(match.group(0)!)).toString())
      .toSet()
      .toList();

  DateTime? _verifiedDeadline(Map<String, dynamic> json, String body) {
    final evidence = _string(json, 'deadline_evidence');
    final raw = _string(json, 'deadline_at');
    if (evidence.isEmpty ||
        !body.contains(evidence) ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  String _normalizedSubject(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'^(\s*(re|fw|fwd)\s*:\s*)+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _string(
    Map<String, dynamic> json,
    String key, {
    String fallback = '',
  }) {
    final value = json[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  MailRadarPriority _priority(String? value) => switch (value) {
    'urgent' => MailRadarPriority.urgent,
    'high' => MailRadarPriority.high,
    'low' => MailRadarPriority.low,
    _ => MailRadarPriority.normal,
  };

  MailRadarCategory _category(String? value) => switch (value) {
    'deadline' => MailRadarCategory.deadline,
    'action' => MailRadarCategory.action,
    'event' => MailRadarCategory.event,
    'system' => MailRadarCategory.system,
    'lowPriority' => MailRadarCategory.lowPriority,
    _ => MailRadarCategory.notice,
  };

  MailRadarSenderRole _senderRole(String? value) => switch (value) {
    'teacher' => MailRadarSenderRole.teacher,
    'student' => MailRadarSenderRole.student,
    'personal' => MailRadarSenderRole.personal,
    'department' => MailRadarSenderRole.department,
    'system' => MailRadarSenderRole.system,
    _ => MailRadarSenderRole.unknown,
  };

  String _limit(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
