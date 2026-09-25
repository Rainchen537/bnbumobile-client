import 'mail_models.dart';
import 'assistant_models.dart';

const mailRadarDefaultTargetLanguageTag = 'zh-Hans';

String mailRadarMessageKey(MailFolder folder, int validity, int uid) =>
    folder == MailFolder.inbox
    ? '${validity}_$uid'
    : '${folder.name}:${validity}_$uid';

enum MailRadarMembership { automatic, included, excluded }

const mailRadarAnalysisContractVersion = '2026-09-08-mail-radar-light-v1';
const mailRadarSupportedTargetLanguageTags = <String>{
  'zh-Hans',
  'zh-Hant',
  'en',
};

String normalizeMailRadarTargetLanguageTag(String value) {
  final normalized = value.trim();
  return mailRadarSupportedTargetLanguageTags.contains(normalized)
      ? normalized
      : mailRadarDefaultTargetLanguageTag;
}

final RegExp _mailRadarExplicitTimezone = RegExp(
  r'(北京时间|中国标准时间|东八区|当地时间|本地时间|香港时间|澳门时间|台湾时间|日本时间|韩国时间|印度时间|英国时间|美国[^，。；;]*时间|欧洲[^，。；;]*时间|太平洋时间|大西洋时间|中部时间|东部时间|山地时间|\b(?:UTC|GMT)(?:\s*[+-]\s*\d{1,2}(?::?\d{2})?)?\b|\b(?:CST|PST|PDT|EST|EDT|MST|MDT|CET|CEST|BST|IST|HKT|JST|KST|AEST|AEDT)\b|[+-]\d{2}:?\d{2}|[A-Za-z_]+/[A-Za-z_]+)',
  caseSensitive: false,
);

/// Adds the mail radar's default time zone only when the source did not
/// explicitly identify another one.
String normalizeMailRadarDeadlineTimezone(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || _mailRadarExplicitTimezone.hasMatch(normalized)) {
    return normalized;
  }
  return '$normalized（北京时间 UTC+8）';
}

enum MailRadarPriority {
  urgent('紧急'),
  high('重要'),
  normal('普通'),
  low('低优先级');

  const MailRadarPriority(this.label);
  final String label;
}

enum MailRadarCategory {
  direct('直接来信'),
  deadline('截止事项'),
  action('待办事项'),
  event('活动安排'),
  notice('校园通知'),
  system('系统邮件'),
  lowPriority('稍后阅读');

  const MailRadarCategory(this.label);
  final String label;
}

enum MailRadarSenderRole {
  teacher('教师'),
  student('同学'),
  personal('个人来信'),
  department('校内部门'),
  system('系统'),
  unknown('未知');

  const MailRadarSenderRole(this.label);
  final String label;
}

class MailRadarActionLink {
  const MailRadarActionLink({required this.label, required this.sourceIndex});

  final String label;
  final int sourceIndex;

  Map<String, Object?> toJson() => {
    'label': label,
    'source_index': sourceIndex,
  };

  factory MailRadarActionLink.fromJson(Map<String, dynamic> json) =>
      MailRadarActionLink(
        label: json['label'] as String? ?? '',
        sourceIndex: json['source_index'] as int? ?? 0,
      );
}

class MailRadarToolUse {
  const MailRadarToolUse({
    required this.name,
    required this.status,
    this.query = '',
  });

  final String name;
  final String status;
  final String query;

  Map<String, Object?> toJson() => {
    'name': name,
    'status': status,
    'query': query,
  };

  factory MailRadarToolUse.fromJson(Map<String, dynamic> json) =>
      MailRadarToolUse(
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? '',
        query: json['query'] as String? ?? '',
      );
}

class MailRadarRemoteRequest {
  const MailRadarRemoteRequest({
    required this.clientRequestId,
    required this.uid,
    required this.mailboxUidValidity,
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.receivedAt,
    required this.bodyExcerpt,
    required this.recipients,
    required this.cc,
    required this.listId,
    required this.precedence,
    required this.replyHeaders,
    required this.attachmentContext,
    required this.sourceLinks,
    required this.attachments,
    this.targetLanguageTag = mailRadarDefaultTargetLanguageTag,
    this.lightweight = false,
    this.bodySha256 = '',
    this.sourceFolder = MailFolder.inbox,
    this.bodyCoverage = 'unknown',
  });

  final String clientRequestId;
  final int uid;
  final int mailboxUidValidity;
  final String senderName;
  final String senderEmail;
  final String subject;
  final DateTime receivedAt;
  final String bodyExcerpt;
  final String recipients;
  final String cc;
  final String listId;
  final String precedence;
  final String replyHeaders;
  final String attachmentContext;
  final List<String> sourceLinks;
  final List<AssistantInputAttachment> attachments;
  final String targetLanguageTag;
  final bool lightweight;
  final String bodySha256;
  final MailFolder sourceFolder;
  final String bodyCoverage;
}

class MailRadarRemoteAnalysis {
  const MailRadarRemoteAnalysis({
    required this.clientRequestId,
    required this.result,
    required this.toolUses,
    required this.memorySuggestions,
  });

  /// The exact client request ID accepted by the server. This can differ from
  /// the initial ID when a pre-dispatch idempotency conflict is recovered.
  final String clientRequestId;
  final Map<String, dynamic> result;
  final List<MailRadarToolUse> toolUses;
  final List<AssistantMemorySuggestion> memorySuggestions;
}

enum MailRadarTaskStatus {
  pending('待处理'),
  waiting('等待回复'),
  snoozed('稍后处理'),
  completed('已完成'),
  cancelled('已取消');

  const MailRadarTaskStatus(this.label);
  final String label;
}

class MailRadarItem {
  const MailRadarItem({
    this.sourceFolder = MailFolder.inbox,
    this.membership = MailRadarMembership.automatic,
    this.originalIsSeen = false,
    required this.key,
    required this.uid,
    required this.mailboxUidValidity,
    required this.subject,
    required this.sender,
    this.recipients = '',
    required this.receivedAt,
    required this.summaryZh,
    required this.translationZh,
    required this.priority,
    required this.category,
    required this.senderRole,
    required this.actionZh,
    this.actionLinks = const [],
    required this.deadlineText,
    required this.relatedThreadKey,
    required this.attachmentNotes,
    required this.analyzedAt,
    this.updatedAt,
    this.taskStatus = MailRadarTaskStatus.pending,
    this.snoozedUntil,
    this.deadlineAt,
    this.deadlineEvidence = '',
    this.deadlinePrecision = '',
    this.bodyCoverage = 'unknown',
    this.attachmentCoverage = const {},
    this.messageHash = '',
    this.referenceHashes = const [],
    this.userFieldTimes = const {},
    this.completed = false,
    this.userCorrectedCategory = false,
    this.isRecallNotice = false,
    this.hasInlineImages = false,
    this.hasSourceAttachments = false,
    this.isUnread = false,
    this.analysisPending = false,
    this.analysisRequestId = '',
    this.toolUses = const [],
    this.memorySuggestions = const [],
    this.analysisLanguageTag = mailRadarDefaultTargetLanguageTag,
    this.analysisContractVersion = mailRadarAnalysisContractVersion,
  });

  final String key;
  final MailFolder sourceFolder;
  final MailRadarMembership membership;
  final bool originalIsSeen;
  final int uid;
  final int mailboxUidValidity;
  final String subject;
  final String sender;
  final String recipients;
  final DateTime receivedAt;
  final String summaryZh;
  final String translationZh;
  final MailRadarPriority priority;
  final MailRadarCategory category;
  final MailRadarSenderRole senderRole;
  final String actionZh;
  final List<MailRadarActionLink> actionLinks;
  final String deadlineText;
  final String relatedThreadKey;
  final List<String> attachmentNotes;
  final DateTime analyzedAt;
  final DateTime? updatedAt;
  final MailRadarTaskStatus taskStatus;
  final DateTime? snoozedUntil;
  final DateTime? deadlineAt;
  final String deadlineEvidence;

  /// Empty only for records written before precision was explicit.
  final String deadlinePrecision;
  final String bodyCoverage;
  final Map<String, String> attachmentCoverage;
  final String messageHash;
  final List<String> referenceHashes;
  final Map<String, String> userFieldTimes;

  MailRadarTaskStatus get effectiveStatus =>
      completed ? MailRadarTaskStatus.completed : taskStatus;
  MailRadarTaskStatus taskStatusAt(DateTime now) =>
      effectiveStatus == MailRadarTaskStatus.snoozed &&
          snoozedUntil != null &&
          !snoozedUntil!.isAfter(now)
      ? MailRadarTaskStatus.pending
      : effectiveStatus;
  bool get isResolved =>
      completed || taskStatus == MailRadarTaskStatus.cancelled;
  bool isStronglyRelated(MailRadarItem other) =>
      messageHash.isNotEmpty &&
      other.messageHash.isNotEmpty &&
      (referenceHashes.contains(other.messageHash) ||
          other.referenceHashes.contains(messageHash) ||
          referenceHashes.any(other.referenceHashes.contains));

  final bool completed;
  final bool userCorrectedCategory;
  final bool isRecallNotice;
  final bool hasInlineImages;
  final bool hasSourceAttachments;
  final bool isUnread;
  final bool analysisPending;
  final String analysisRequestId;
  final List<MailRadarToolUse> toolUses;
  final List<AssistantMemorySuggestion> memorySuggestions;
  final String analysisLanguageTag;
  final String analysisContractVersion;

  DateTime get syncUpdatedAt => updatedAt ?? analyzedAt;

  MailMessageSummary toSummary() => MailMessageSummary(
    uid: uid,
    subject: subject,
    sender: sender,
    recipients: recipients,
    preview: summaryZh,
    hasHtmlBody: false,
    date: receivedAt,
    isSeen: originalIsSeen,
    hasAttachments:
        hasSourceAttachments || attachmentNotes.isNotEmpty || hasInlineImages,
    folder: sourceFolder,
    mailboxUidValidity: mailboxUidValidity,
  );

  MailRadarItem copyWith({
    MailRadarMembership? membership,
    bool? originalIsSeen,
    MailRadarCategory? category,
    MailRadarTaskStatus? taskStatus,
    DateTime? snoozedUntil,
    Map<String, String>? userFieldTimes,
    bool? completed,
    bool? userCorrectedCategory,
    bool? isUnread,
    bool? analysisPending,
    String? analysisRequestId,
    List<MailRadarToolUse>? toolUses,
    List<AssistantMemorySuggestion>? memorySuggestions,
    String? analysisLanguageTag,
    String? analysisContractVersion,
    DateTime? updatedAt,
  }) => MailRadarItem(
    sourceFolder: sourceFolder,
    membership: membership ?? this.membership,
    originalIsSeen: originalIsSeen ?? this.originalIsSeen,
    taskStatus: taskStatus ?? this.taskStatus,
    snoozedUntil:
        taskStatus != null && taskStatus != MailRadarTaskStatus.snoozed
        ? null
        : snoozedUntil ?? this.snoozedUntil,
    deadlineAt: deadlineAt,
    deadlineEvidence: deadlineEvidence,
    deadlinePrecision: deadlinePrecision,
    bodyCoverage: bodyCoverage,
    attachmentCoverage: attachmentCoverage,
    messageHash: messageHash,
    referenceHashes: referenceHashes,
    userFieldTimes: userFieldTimes ?? this.userFieldTimes,
    key: key,
    uid: uid,
    mailboxUidValidity: mailboxUidValidity,
    subject: subject,
    sender: sender,
    recipients: recipients,
    receivedAt: receivedAt,
    summaryZh: summaryZh,
    translationZh: translationZh,
    priority: priority,
    category: category ?? this.category,
    senderRole: senderRole,
    actionZh: actionZh,
    actionLinks: actionLinks,
    deadlineText: deadlineText,
    relatedThreadKey: relatedThreadKey,
    attachmentNotes: attachmentNotes,
    analyzedAt: analyzedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completed: completed ?? this.completed,
    userCorrectedCategory: userCorrectedCategory ?? this.userCorrectedCategory,
    isRecallNotice: isRecallNotice,
    hasInlineImages: hasInlineImages,
    hasSourceAttachments: hasSourceAttachments,
    isUnread: isUnread ?? this.isUnread,
    analysisPending: analysisPending ?? this.analysisPending,
    analysisRequestId: analysisRequestId ?? this.analysisRequestId,
    toolUses: toolUses ?? this.toolUses,
    memorySuggestions: memorySuggestions ?? this.memorySuggestions,
    analysisLanguageTag: analysisLanguageTag ?? this.analysisLanguageTag,
    analysisContractVersion:
        analysisContractVersion ?? this.analysisContractVersion,
  );

  Map<String, Object?> toJson() => {
    'source_folder': sourceFolder.name,
    'membership': membership.name,
    'original_is_seen': originalIsSeen,
    'task_status': effectiveStatus.name,
    'snoozed_until': snoozedUntil?.toUtc().toIso8601String(),
    'deadline_at': deadlineAt?.toUtc().toIso8601String(),
    'deadline_evidence': deadlineEvidence,
    'deadline_precision': deadlinePrecision,
    'body_coverage': bodyCoverage,
    'attachment_coverage': attachmentCoverage,
    'message_hash': messageHash,
    'reference_hashes': referenceHashes,
    'user_field_times': userFieldTimes,
    'key': key,
    'uid': uid,
    'mailbox_uid_validity': mailboxUidValidity,
    'subject': subject,
    'sender': sender,
    'recipients': recipients,
    'received_at': receivedAt.toIso8601String(),
    'summary_zh': summaryZh,
    'translation_zh': translationZh,
    'priority': priority.name,
    'category': category.name,
    'sender_role': senderRole.name,
    'action_zh': actionZh,
    'action_links': actionLinks.map((link) => link.toJson()).toList(),
    'deadline_text': deadlineText,
    'related_thread_key': relatedThreadKey,
    'attachment_notes': attachmentNotes,
    'analyzed_at': analyzedAt.toIso8601String(),
    'updated_at': syncUpdatedAt.toIso8601String(),
    'completed': completed,
    'user_corrected_category': userCorrectedCategory,
    'is_recall_notice': isRecallNotice,
    'has_inline_images': hasInlineImages,
    'has_source_attachments': hasSourceAttachments,
    'is_unread': isUnread,
    'analysis_pending': analysisPending,
    'analysis_request_id': analysisRequestId,
    'tool_uses': toolUses.map((item) => item.toJson()).toList(growable: false),
    'memory_suggestions': memorySuggestions
        .map((item) => item.toJson())
        .toList(growable: false),
    'analysis_language_tag': analysisLanguageTag,
    'analysis_contract_version': analysisContractVersion,
  };

  factory MailRadarItem.fromJson(Map<String, dynamic> json) {
    T named<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((value) => value.name == name).firstOrNull ?? fallback;
    final subject = json['subject'] as String? ?? '';
    final sender = json['sender'] as String? ?? '';
    final summary = json['summary_zh'] as String? ?? '';
    final userCorrectedCategory = json['user_corrected_category'] == true;
    final recallNotice =
        json['is_recall_notice'] == true || looksLikeMailRecallSubject(subject);
    final promotionalBroadcast = looksLikeOptionalBroadcastPromotion(
      subject: subject,
      sender: sender,
      content: summary,
    );
    final rawAttachmentNotes = (json['attachment_notes'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final hasInlineImages =
        json['has_inline_images'] == true ||
        rawAttachmentNotes.any(looksLikeInlineImageAttachmentNote);
    return MailRadarItem(
      sourceFolder: named(
        MailFolder.values,
        json['source_folder'] as String?,
        MailFolder.inbox,
      ),
      membership: named(
        MailRadarMembership.values,
        json['membership'] as String?,
        MailRadarMembership.automatic,
      ),
      originalIsSeen:
          json['original_is_seen'] == true ||
          (json['original_is_seen'] == null && json['completed'] == true),
      key: json['key'] as String,
      uid: json['uid'] as int,
      mailboxUidValidity: json['mailbox_uid_validity'] as int,
      subject: subject,
      sender: sender,
      recipients: json['recipients'] as String? ?? '',
      receivedAt: DateTime.parse(json['received_at'] as String),
      taskStatus: named(
        MailRadarTaskStatus.values,
        json['task_status'] as String?,
        MailRadarTaskStatus.pending,
      ),
      snoozedUntil: DateTime.tryParse(json['snoozed_until'] as String? ?? ''),
      deadlineAt: DateTime.tryParse(json['deadline_at'] as String? ?? ''),
      deadlineEvidence: json['deadline_evidence'] as String? ?? '',
      deadlinePrecision:
          const {
            'none',
            'date',
            'datetime',
          }.contains(json['deadline_precision'])
          ? json['deadline_precision'] as String
          : '',
      bodyCoverage: json['body_coverage'] as String? ?? 'unknown',
      attachmentCoverage: (json['attachment_coverage'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      messageHash: json['message_hash'] as String? ?? '',
      referenceHashes: (json['reference_hashes'] as List? ?? const [])
          .whereType<String>()
          .take(32)
          .toList(),
      userFieldTimes: (json['user_field_times'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      summaryZh: recallNotice ? '发件人已撤回' : summary,
      translationZh: recallNotice
          ? ''
          : json['translation_zh'] as String? ?? '',
      priority: promotionalBroadcast
          ? MailRadarPriority.normal
          : named(
              MailRadarPriority.values,
              json['priority'] as String?,
              MailRadarPriority.normal,
            ),
      category: promotionalBroadcast && !userCorrectedCategory
          ? MailRadarCategory.notice
          : named(
              MailRadarCategory.values,
              json['category'] as String?,
              MailRadarCategory.notice,
            ),
      senderRole: named(
        MailRadarSenderRole.values,
        json['sender_role'] as String?,
        MailRadarSenderRole.unknown,
      ),
      actionZh: recallNotice ? '' : json['action_zh'] as String? ?? '',
      actionLinks: recallNotice
          ? const []
          : (json['action_links'] as List? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(MailRadarActionLink.fromJson)
                .where((link) => link.label.isNotEmpty && link.sourceIndex > 0)
                .toList(growable: false),
      deadlineText: recallNotice
          ? ''
          : normalizeMailRadarDeadlineTimezone(
              json['deadline_text'] as String? ?? '',
            ),
      relatedThreadKey: json['related_thread_key'] as String? ?? '',
      attachmentNotes: recallNotice
          ? const []
          : rawAttachmentNotes
                .where((note) => !looksLikeInlineImageAttachmentNote(note))
                .toList(growable: false),
      analyzedAt: DateTime.parse(json['analyzed_at'] as String),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      completed: json['completed'] == true,
      userCorrectedCategory: userCorrectedCategory,
      isRecallNotice: recallNotice,
      hasInlineImages: !recallNotice && hasInlineImages,
      hasSourceAttachments: json['has_source_attachments'] == true,
      // Cached items created before unread tracking are treated as already
      // viewed so an upgrade does not mark the whole 30-day history as new.
      isUnread: json['is_unread'] == true,
      analysisPending: json['analysis_pending'] == true,
      analysisRequestId: json['analysis_request_id'] as String? ?? '',
      toolUses: (json['tool_uses'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MailRadarToolUse.fromJson)
          .where((item) => item.name.isNotEmpty && item.status.isNotEmpty)
          .toList(growable: false),
      memorySuggestions: (json['memory_suggestions'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AssistantMemorySuggestion.fromJson)
          .take(3)
          .toList(growable: false),
      // Results created before language-aware analysis were always generated
      // in Simplified Chinese. Preserve them for zh-Hans users without an
      // unnecessary full-inbox reanalysis after upgrade.
      analysisLanguageTag: normalizeMailRadarTargetLanguageTag(
        json['analysis_language_tag'] as String? ??
            mailRadarDefaultTargetLanguageTag,
      ),
      // A missing marker identifies a result produced before detail-open
      // translation repair. Keep it stale so the user can upgrade only the
      // message they actually open instead of rescanning the full mailbox.
      analysisContractVersion:
          json['analysis_contract_version'] as String? ?? '',
    );
  }
}

bool looksLikeInlineImageAttachment(String name, String mimeType) {
  final normalizedMime = mimeType.trim().toLowerCase();
  if (normalizedMime.startsWith('image/')) return true;
  final normalizedName = name.trim().toLowerCase();
  return RegExp(r'\.(png|jpe?g|webp|gif)$').hasMatch(normalizedName);
}

bool looksLikeInlineImageAttachmentNote(String note) {
  final name = note.split('：').first.trim();
  return looksLikeInlineImageAttachment(name, '');
}

bool looksLikeOptionalBroadcastPromotion({
  required String subject,
  required String sender,
  required String content,
}) {
  final normalized = '$subject\n$sender\n$content'.toLowerCase();
  final promotional = const [
    'job opportunities',
    'career opportunities',
    'intern recruitment',
    'internship recruitment',
    'recruitment',
    '招聘',
    '实习机会',
    '实习生',
    '宣讲会',
    'newsletter',
    'promotion',
    '优惠',
    '促销',
  ].any(normalized.contains);
  if (!promotional) return false;
  return subject.contains('【') ||
      subject.contains('[') ||
      normalized.contains('career@') ||
      normalized.contains('career centre') ||
      normalized.contains('career center') ||
      normalized.contains('职业发展中心') ||
      normalized.contains('all students') ||
      normalized.contains('群发');
}

bool looksLikeMailRecallSubject(String subject) {
  final normalized = subject.trim().toLowerCase();
  return normalized.contains('发件人已撤回邮件') ||
      normalized.contains('撤回了一封邮件') ||
      normalized.contains('message recall') ||
      normalized.contains('recall:') ||
      normalized.contains('recalled message');
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Independent user edits survive newer analysis and edits on other devices.
MailRadarItem mergeMailRadarItem(MailRadarItem left, MailRadarItem right) {
  final analysis = left.analysisPending != right.analysisPending
      ? (left.analysisPending ? right : left)
      : (right.analyzedAt.isAfter(left.analyzedAt) ? right : left);
  MailRadarItem latest(String field) {
    DateTime stamp(MailRadarItem item) =>
        DateTime.tryParse(item.userFieldTimes[field] ?? '') ??
        item.syncUpdatedAt;
    final l = stamp(left);
    final r = stamp(right);
    if (l == r) {
      // A stable tie break makes repeated device merges converge.
      return right.toJson().toString().compareTo(left.toJson().toString()) > 0
          ? right
          : left;
    }
    return r.isAfter(l) ? right : left;
  }

  final state = latest('status');
  final category = latest('category');
  final read = latest('read');
  final memory = latest('memory');
  final membership = latest('membership');
  final originalRead = latest('original_read');
  return analysis.copyWith(
    membership: membership.membership,
    originalIsSeen: originalRead.originalIsSeen,
    completed: state.completed,
    taskStatus: state.effectiveStatus,
    snoozedUntil: state.snoozedUntil,
    category: category.userCorrectedCategory
        ? category.category
        : analysis.category,
    userCorrectedCategory: category.userCorrectedCategory,
    isUnread: state.completed ? false : read.isUnread,
    memorySuggestions: memory.memorySuggestions,
    updatedAt: left.syncUpdatedAt.isAfter(right.syncUpdatedAt)
        ? left.syncUpdatedAt
        : right.syncUpdatedAt,
    userFieldTimes: {
      for (final field in [
        'status',
        'category',
        'read',
        'memory',
        'membership',
        'original_read',
      ])
        field:
            latest(field).userFieldTimes[field] ??
            latest(field).syncUpdatedAt.toUtc().toIso8601String(),
    },
  );
}
