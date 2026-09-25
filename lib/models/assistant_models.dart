import 'assistant_content_page.dart';
import 'assistant_text.dart';
import 'dart:convert';
import 'dart:typed_data';

enum AssistantContextSource {
  academicProfile('academic_profile'),
  courses('courses'),
  termCourses('term_courses'),
  ispaceCourseCatalog('ispace_course_catalog'),
  ispaceActivity('ispace_activity'),
  ispaceQuizAttempt('ispace_quiz_attempt'),
  ispaceToolResults('ispace_tool_results'),
  deadlines('deadlines'),
  schedule('schedule'),
  academicCalendar('academic_calendar'),
  examTimetable('exam_timetable'),
  mailSummaries('mail_summaries'),
  selectedMail('selected_mail'),
  mailToolResults('mail_tool_results'),
  schoolActivities('school_activities'),
  taCourses('ta_courses'),
  currentPage('current_page'),
  currentLocation('current_location');

  const AssistantContextSource(this.wireValue);

  final String wireValue;

  static AssistantContextSource parse(Object? value) {
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw FormatException('不支持的小U上下文来源：$value'),
    );
  }
}

enum AssistantServerTool {
  officialDirectory('official_directory');

  const AssistantServerTool(this.wireValue);

  final String wireValue;

  static AssistantServerTool parse(Object? value) {
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw FormatException('不支持的小U服务端工具：$value'),
    );
  }
}

class AssistantPlannedServerTool {
  const AssistantPlannedServerTool({required this.name, required this.query});

  final AssistantServerTool name;
  final String query;

  factory AssistantPlannedServerTool.fromJson(Map<String, dynamic> json) {
    final query = _requiredString(json, 'query').trim();
    if (query.isEmpty || query.length > 254) {
      throw const FormatException('小U服务端工具查询词无效。');
    }
    return AssistantPlannedServerTool(
      name: AssistantServerTool.parse(json['name']),
      query: query,
    );
  }

  Map<String, dynamic> toJson() => {'name': name.wireValue, 'query': query};
}

class AssistantPlanNavigation {
  const AssistantPlanNavigation({required this.targetId});

  final String targetId;

  factory AssistantPlanNavigation.fromJson(Map<String, dynamic> json) {
    if (_requiredString(json, 'type') != 'open_app_tab') {
      throw const FormatException('小U规划了不支持的导航动作。');
    }
    final targetId = _requiredString(json, 'target_id');
    if (!const {
      'home',
      'mail',
      'ispace',
      'schedule',
      'user',
    }.contains(targetId)) {
      throw const FormatException('小U规划了不支持的页面。');
    }
    return AssistantPlanNavigation(targetId: targetId);
  }
}

enum AssistantThinkingMode {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const AssistantThinkingMode(this.wireValue, this.label);

  final String wireValue;
  final String label;

  String wireValueForProtocol(int agentProtocolVersion) {
    if (agentProtocolVersion >= 2) {
      return wireValue;
    }
    return this == AssistantThinkingMode.high ? 'deep' : 'simple';
  }

  static AssistantThinkingMode parse(Object? value) {
    if (value == 'simple') return AssistantThinkingMode.low;
    if (value == 'deep') return AssistantThinkingMode.high;
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw FormatException('不支持的小U思考强度：$value'),
    );
  }
}

enum AssistantCourseFileScope {
  all('all'),
  presentations('presentations'),
  presentationsAndPdf('presentations_and_pdf'),
  documents('documents'),
  media('media'),
  archives('archives');

  const AssistantCourseFileScope(this.wireValue);

  final String wireValue;

  static AssistantCourseFileScope? parseOptional(Object? value) {
    if (value == null || value == '') {
      return null;
    }
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw FormatException('不支持的课程文件范围：$value'),
    );
  }
}

enum AssistantMailReferenceKind { message, draft }

enum AssistantAttachmentReferenceKind {
  file('file'),
  image('image'),
  resource('resource');

  const AssistantAttachmentReferenceKind(this.wireValue);

  final String wireValue;

  static AssistantAttachmentReferenceKind parse(Object? value) =>
      values.firstWhere(
        (candidate) => candidate.wireValue == value,
        orElse: () => throw const FormatException('小U附件引用类型无效。'),
      );
}

/// Display-only metadata for an attachment that accompanied a user turn.
///
/// The bytes, local path, resource identity and source URI deliberately remain
/// outside conversation history. The stored message can separately keep
/// current-process runtime attachments for an image thumbnail.
class AssistantAttachmentReference {
  const AssistantAttachmentReference({required this.kind, required this.name});

  factory AssistantAttachmentReference.fromInputAttachment(
    AssistantInputAttachment attachment,
  ) {
    final name = attachment.name.trim();
    if (name.isEmpty || name.length > 255) {
      throw const FormatException('小U附件引用名称无效。');
    }
    return AssistantAttachmentReference(
      kind: attachment.isResourceReference
          ? AssistantAttachmentReferenceKind.resource
          : attachment.mimeType.startsWith('image/')
          ? AssistantAttachmentReferenceKind.image
          : AssistantAttachmentReferenceKind.file,
      name: name,
    );
  }

  final AssistantAttachmentReferenceKind kind;
  final String name;

  Map<String, dynamic> toJson() => {'kind': kind.wireValue, 'name': name};

  factory AssistantAttachmentReference.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty || name.length > 255) {
      throw const FormatException('小U附件引用名称无效。');
    }
    return AssistantAttachmentReference(
      kind: AssistantAttachmentReferenceKind.parse(json['kind']),
      name: name.trim(),
    );
  }
}

/// A user-selected mail reference shown as an attachment in a 小U draft.
///
/// It deliberately carries no MIME bytes. A received message is resolved on
/// demand through the account-bound IMAP reader using its stable folder,
/// UIDVALIDITY and UID tuple. A compose draft is already user-authored and is
/// only included in a request after the user submits the 小U prompt.
class AssistantMailReference {
  const AssistantMailReference.message({
    required this.folder,
    required this.uid,
    required this.mailboxUidValidity,
    required this.sender,
    required this.subject,
    required this.receivedAt,
  }) : kind = AssistantMailReferenceKind.message,
       recipients = '',
       body = '';

  const AssistantMailReference.draft({
    required this.recipients,
    required this.subject,
    required this.body,
  }) : kind = AssistantMailReferenceKind.draft,
       folder = '',
       uid = 0,
       mailboxUidValidity = 0,
       sender = '',
       receivedAt = null;

  final AssistantMailReferenceKind kind;
  final String folder;
  final int uid;
  final int mailboxUidValidity;
  final String sender;
  final String recipients;
  final String subject;
  final String body;
  final DateTime? receivedAt;

  bool get isMessage => kind == AssistantMailReferenceKind.message;

  String get displayName {
    final normalizedSubject = subject.trim();
    if (normalizedSubject.isNotEmpty) return normalizedSubject;
    return isMessage ? '无主题邮件' : '未命名邮件草稿';
  }

  Map<String, dynamic> toJson() => {
    'kind': isMessage ? 'message' : 'draft',
    if (isMessage) ...{
      'folder': folder,
      'uid': uid,
      'mailbox_uid_validity': mailboxUidValidity,
      'sender': sender,
      if (receivedAt != null)
        'received_at': receivedAt!.toUtc().toIso8601String(),
    } else ...{
      'recipients': recipients,
      'body': body,
    },
    'subject': subject,
  };

  factory AssistantMailReference.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final subject = json['subject'];
    if (kind is! String || subject is! String || subject.length > 300) {
      throw const FormatException('小U邮件引用格式无效。');
    }
    if (kind == 'message') {
      final folder = json['folder'];
      final uid = json['uid'];
      final validity = json['mailbox_uid_validity'];
      final sender = json['sender'];
      final receivedAt = DateTime.tryParse(
        json['received_at'] as String? ?? '',
      );
      if (folder is! String ||
          folder.isEmpty ||
          folder.length > 80 ||
          uid is! int ||
          uid <= 0 ||
          validity is! int ||
          validity <= 0 ||
          sender is! String ||
          sender.trim().isEmpty ||
          sender.length > 320 ||
          receivedAt == null) {
        throw const FormatException('小U邮件引用格式无效。');
      }
      return AssistantMailReference.message(
        folder: folder,
        uid: uid,
        mailboxUidValidity: validity,
        sender: sender,
        subject: subject,
        receivedAt: receivedAt.toLocal(),
      );
    }
    if (kind == 'draft') {
      final recipients = json['recipients'];
      final body = json['body'];
      if (recipients is! String ||
          recipients.length > 4000 ||
          body is! String ||
          body.length > 12000) {
        throw const FormatException('小U邮件草稿引用格式无效。');
      }
      return AssistantMailReference.draft(
        recipients: recipients,
        subject: subject,
        body: body,
      );
    }
    throw const FormatException('小U邮件引用格式无效。');
  }

  String providerPrompt() {
    if (isMessage) {
      return '用户已明确附加一封邮件。请基于已读取的邮件正文回答；'
          '不得把标题或摘要当作正文。';
    }
    return [
      '用户已明确附加一份待发送邮件草稿。',
      '收件人：$recipients',
      '主题：$subject',
      '正文：$body',
    ].join('\n');
  }
}

/// Raw attachment admission limit, independent of provider context capacity.
abstract final class AssistantAttachmentLimits {
  static const maxFileBytes = 50 * 1024 * 1024;
  static const maxTotalBytes = 50 * 1024 * 1024;
}

class AssistantInputAttachment {
  AssistantInputAttachment({
    required this.name,
    required this.mimeType,
    required Uint8List bytes,
    this.resourceId,
    this.resourceByteCount,
    this.localFilePath,
    this.localByteCount,
    this.mailReference,
  }) : bytes = Uint8List.fromList(bytes);

  factory AssistantInputAttachment.mailReference(
    AssistantMailReference reference,
  ) {
    return AssistantInputAttachment(
      name: reference.displayName,
      mimeType: 'application/x-bnbu-mail-reference',
      bytes: Uint8List(0),
      mailReference: reference,
    );
  }

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String? resourceId;
  final int? resourceByteCount;
  final String? localFilePath;
  final int? localByteCount;
  final AssistantMailReference? mailReference;

  bool get isResourceReference => resourceId?.trim().isNotEmpty == true;
  bool get isLocalFileReference => localFilePath?.trim().isNotEmpty == true;
  bool get isMailReference => mailReference != null;
  int get effectiveByteCount =>
      localByteCount ?? resourceByteCount ?? bytes.length;

  Map<String, dynamic> toJson() {
    if (isMailReference) {
      throw StateError('邮件引用必须通过小U邮件上下文读取，不能作为文件上传。');
    }
    if (isLocalFileReference) {
      throw StateError('本机作业文件引用不能发送到小U服务。');
    }
    return {
      'name': name,
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
    };
  }
}

enum AssistantActionType {
  composeEmail('compose_email'),
  submitAssignment('submit_assignment'),
  openPage('open_page'),
  openAssignment('open_assignment'),
  openCourse('open_course'),
  openMail('open_mail'),
  showCampusPlace('show_campus_place'),
  prepareCoursePack('prepare_course_pack'),
  downloadAttachment('download_attachment'),
  batchDownloadCourseFiles('batch_download_course_files'),
  uploadAssignmentFile('upload_assignment_file'),
  startQuizAttempt('start_quiz_attempt'),
  saveQuizAnswers('save_quiz_answers'),
  submitQuizAttempt('submit_quiz_attempt'),
  setIspaceCompletion('set_ispace_completion'),
  submitIspaceChoice('submit_ispace_choice'),
  deleteMail('delete_mail'),
  restoreMail('restore_mail'),
  openCampusPage('open_campus_page'),
  openMeLifeEntry('open_me_life_entry'),
  openDirectoryEntry('open_directory_entry'),
  openAppTab('open_app_tab'),
  openOfficialSystem('open_official_system'),
  openTaCourseManager('open_ta_course_manager'),
  addTaCourse('add_ta_course'),
  updateTaCourse('update_ta_course'),
  deleteTaCourse('delete_ta_course'),
  scheduleNotification('schedule_notification');

  const AssistantActionType(this.wireValue);

  final String wireValue;

  static AssistantActionType parse(Object? value) {
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw FormatException('不支持的小U动作：$value'),
    );
  }
}

class AssistantCapabilities {
  const AssistantCapabilities({
    required this.available,
    required this.model,
    required this.contextSources,
    required this.actions,
    required this.storesConversationContent,
    required this.purchaseApiAvailable,
    this.fixedScheduleVersion = 0,
    this.publicDirectoryToolsVersion = 0,
    this.contextVersion = '2',
    this.supportedContextVersions = const {'2'},
    this.agentProtocolVersion = 0,
    this.agentPlanningRequired = true,
    this.clientToolManifestSupported = false,
    this.agentMaxOutputTokens = 2000,
    this.agentExecutionBudgetSeconds = 480,
    this.agentTotalTokenBudget = 120000,
    this.thinkingModes = const {
      AssistantThinkingMode.low,
      AssistantThinkingMode.high,
    },
    this.mailRadarEnabled = false,
  });

  final bool available;
  final String? model;
  final int fixedScheduleVersion;
  final int publicDirectoryToolsVersion;
  final String contextVersion;
  final Set<String> supportedContextVersions;
  final Set<String> contextSources;
  final Set<String> actions;
  final bool storesConversationContent;
  final bool purchaseApiAvailable;
  final int agentProtocolVersion;
  final bool agentPlanningRequired;
  final bool clientToolManifestSupported;
  final int agentMaxOutputTokens;
  final int agentExecutionBudgetSeconds;
  final int agentTotalTokenBudget;
  final Set<AssistantThinkingMode> thinkingModes;
  final bool mailRadarEnabled;

  /// Only the negotiated v3 protocol uses this bounded SSE transport.
  bool get supportsAgentTurnStream => agentProtocolVersion == 3;

  String get negotiatedContextVersion {
    for (final version in const ['5', '4', '3', '2']) {
      if (supportedContextVersions.contains(version)) return version;
    }
    throw const FormatException('小U服务与客户端没有共同的上下文协议。');
  }

  factory AssistantCapabilities.fromJson(Map<String, dynamic> json) {
    final contextVersion = _optionalString(json, 'context_version');
    final effectiveContextVersion = contextVersion.isEmpty
        ? '2'
        : contextVersion;
    return AssistantCapabilities(
      fixedScheduleVersion: json['fixed_schedule_version'] == 2 ? 2 : 0,
      publicDirectoryToolsVersion: json['public_directory_tools_version'] == 1
          ? 1
          : 0,
      available: _requiredBool(json, 'available'),
      model: json['model'] as String?,
      contextVersion: effectiveContextVersion,
      supportedContextVersions: json['supported_context_versions'] == null
          ? {effectiveContextVersion}
          : _stringSet(json['supported_context_versions']),
      contextSources: _stringSet(json['context_sources']),
      actions: _stringSet(json['actions']),
      storesConversationContent: _requiredBool(
        json,
        'stores_conversation_content',
      ),
      purchaseApiAvailable: _requiredBool(json, 'purchase_api_available'),
      mailRadarEnabled: json['mail_radar_enabled'] == true,
      agentProtocolVersion: _negotiateAgentProtocol(json),
      clientToolManifestSupported:
          json['client_tool_manifest_supported'] == true,
      agentPlanningRequired: json['agent_planning_required'] != false,
      agentMaxOutputTokens: _boundedCapabilityInt(
        json,
        'agent_max_output_tokens',
        fallback: 2000,
        minimum: 256,
        maximum: 4096,
      ),
      agentExecutionBudgetSeconds: _boundedCapabilityInt(
        json,
        'agent_execution_budget_seconds',
        fallback: 480,
        minimum: 60,
        maximum: 540,
      ),
      agentTotalTokenBudget: _boundedCapabilityInt(
        json,
        'agent_total_token_budget',
        fallback: 120000,
        minimum: 10000,
        maximum: 500000,
      ),
      thinkingModes: _thinkingModesFromCapability(json['thinking_modes']),
    );
  }
}

int _negotiateAgentProtocol(Map<String, dynamic> json) {
  final advertised = json['agent_protocol_version'];
  if (advertised == null || advertised == 0) return 0;
  final versions = json['supported_agent_protocol_versions'];
  final supported = versions is List
      ? versions.whereType<int>().toSet()
      : {advertised};
  for (final version in const [3, 2, 1]) {
    if (supported.contains(version)) return version;
  }
  throw const FormatException('小U服务协议需要更新客户端。');
}

Set<AssistantThinkingMode> _thinkingModesFromCapability(Object? value) {
  if (value is! List) {
    return const {AssistantThinkingMode.low, AssistantThinkingMode.high};
  }
  final raw = value.whereType<String>().toSet();
  if (raw.contains('simple') || raw.contains('deep')) {
    return const {AssistantThinkingMode.low, AssistantThinkingMode.high};
  }
  final parsed = value.map(AssistantThinkingMode.parse).toSet();
  return parsed.isEmpty
      ? const {AssistantThinkingMode.low, AssistantThinkingMode.high}
      : Set.unmodifiable(parsed);
}

class AssistantQuota {
  const AssistantQuota({
    required this.periodStart,
    required this.periodEnd,
    required this.monthlyQuotaTokens,
    required this.creditBalanceTokens,
    required this.usedTokens,
    required this.reservedTokens,
    required this.remainingTokens,
    this.unlimited = false,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final int? monthlyQuotaTokens;
  final int creditBalanceTokens;
  final int usedTokens;
  final int reservedTokens;
  final int? remainingTokens;
  final bool unlimited;

  factory AssistantQuota.fromJson(Map<String, dynamic> json) {
    return AssistantQuota(
      periodStart: _requiredDateTime(json, 'period_start'),
      periodEnd: _requiredDateTime(json, 'period_end'),
      monthlyQuotaTokens: json['monthly_quota_tokens'] == null
          ? null
          : _requiredInt(json, 'monthly_quota_tokens'),
      creditBalanceTokens: _requiredInt(json, 'credit_balance_tokens'),
      usedTokens: _requiredInt(json, 'used_tokens'),
      reservedTokens: _requiredInt(json, 'reserved_tokens'),
      remainingTokens: json['remaining_tokens'] == null
          ? null
          : _requiredInt(json, 'remaining_tokens'),
      unlimited: json['unlimited'] == true,
    );
  }
}

class AssistantContextPlan {
  const AssistantContextPlan({
    required this.requestId,
    required this.sources,
    this.serverTools = const [],
    this.navigation,
    required this.usage,
    required this.quota,
  });

  final String requestId;
  final Set<AssistantContextSource> sources;
  final List<AssistantPlannedServerTool> serverTools;
  final AssistantPlanNavigation? navigation;
  final AssistantTokenUsage usage;
  final AssistantQuota quota;

  factory AssistantContextPlan.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    if (rawSources is! List) {
      throw const FormatException('小U上下文规划结果格式无效。');
    }
    final sources = rawSources.map(AssistantContextSource.parse).toSet();
    if (sources.length != rawSources.length) {
      throw const FormatException('小U上下文规划结果包含重复来源。');
    }
    final rawServerTools = json['server_tools'] ?? const <dynamic>[];
    if (rawServerTools is! List) {
      throw const FormatException('小U服务端工具规划结果格式无效。');
    }
    final serverTools = rawServerTools
        .map((value) => AssistantPlannedServerTool.fromJson(_object(value)))
        .toList(growable: false);
    if (serverTools.map((item) => item.name).toSet().length !=
        serverTools.length) {
      throw const FormatException('小U服务端工具规划结果包含重复项。');
    }
    return AssistantContextPlan(
      requestId: _requiredString(json, 'request_id'),
      sources: Set.unmodifiable(sources),
      serverTools: List.unmodifiable(serverTools),
      navigation: json['navigation'] == null
          ? null
          : AssistantPlanNavigation.fromJson(_object(json['navigation'])),
      usage: AssistantTokenUsage.fromJson(_object(json['usage'])),
      quota: AssistantQuota.fromJson(_object(json['quota'])),
    );
  }
}

class AssistantTokenUsage {
  const AssistantTokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  factory AssistantTokenUsage.fromJson(Map<String, dynamic> json) {
    return AssistantTokenUsage(
      inputTokens: _requiredInt(json, 'input_tokens'),
      outputTokens: _requiredInt(json, 'output_tokens'),
      totalTokens: _requiredInt(json, 'total_tokens'),
    );
  }
}

class AssistantAction {
  const AssistantAction({
    required this.type,
    required this.title,
    required this.requiresConfirmation,
    required this.targetId,
    required this.url,
    required this.recipient,
    this.mailMode = '',
    required this.subject,
    required this.body,
    required this.placeQuery,
    this.actionId = '',
    this.sessionOwner = '',
    this.targetIdentity = '',
    this.expiresAt,
    this.mailUid,
    this.mailFolder = '',
    this.mailboxUidValidity,
    this.mailPartId = '',
    this.attachmentName = '',
    this.courseFileScope,
    this.scheduleKind = '',
    this.scheduleCourseKey = '',
    this.taTitle = '',
    this.taLocation = '',
    this.taWeekday,
    this.taStartMinutes,
    this.taEndMinutes,
    this.taRepeatType = '',
    this.taWeekStart,
    this.taExpectedEntryRevision,
    this.taExpectedCollectionRevision,
    this.notificationTitle = '',
    this.notificationBody = '',
    this.notificationAt,
    this.scheduleDate = '',
    this.scheduleView = '',
    this.quizAttemptId,
    this.quizResponses = const [],
    this.ispaceCompleted,
    this.choiceOptionIds = const [],
    this.localAttachments = const [],
  });

  final AssistantActionType type;
  final String title;
  final bool requiresConfirmation;
  final String targetId;
  final String url;
  final String recipient;
  final String mailMode;
  final String subject;
  final String body;
  final String placeQuery;
  final String actionId;
  final String sessionOwner;
  final String targetIdentity;
  final DateTime? expiresAt;
  final int? mailUid;
  final String mailFolder;
  final int? mailboxUidValidity;
  final String mailPartId;
  final String attachmentName;
  final AssistantCourseFileScope? courseFileScope;
  final String scheduleKind;
  final String scheduleCourseKey;
  final String taTitle;
  final String taLocation;
  final int? taWeekday;
  final int? taStartMinutes;
  final int? taEndMinutes;
  final String taRepeatType;
  final DateTime? taWeekStart;
  final int? taExpectedEntryRevision;
  final int? taExpectedCollectionRevision;
  final String notificationTitle;
  final String notificationBody;
  final DateTime? notificationAt;
  final String scheduleDate;
  final String scheduleView;
  final int? quizAttemptId;
  final List<AssistantQuizResponse> quizResponses;
  final bool? ispaceCompleted;
  final List<String> choiceOptionIds;
  final List<AssistantInputAttachment> localAttachments;

  factory AssistantAction.fromJson(Map<String, dynamic> json) {
    final type = AssistantActionType.parse(json['type']);
    final requiresConfirmation = _requiredBool(json, 'requires_confirmation');
    final targetId = _optionalString(json, 'target_id');
    final ispaceCompleted = json['ispace_completed'] == null
        ? null
        : _requiredBool(json, 'ispace_completed');
    final choiceOptionIds = json['choice_option_ids'] == null
        ? const <String>[]
        : _stringList(json['choice_option_ids']);
    if (choiceOptionIds.length > 20 ||
        choiceOptionIds.any(
          (optionId) => !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(optionId),
        )) {
      throw const FormatException('小U Choice 选项标识无效。');
    }
    if (type == AssistantActionType.setIspaceCompletion) {
      if (!requiresConfirmation ||
          ispaceCompleted == null ||
          choiceOptionIds.isNotEmpty ||
          !RegExp(
            r'^m1:[1-9][0-9]{0,19}:[1-9][0-9]{0,19}:'
            r'[1-9][0-9]{0,19}:[a-z][a-z0-9_]{0,79}$',
          ).hasMatch(targetId)) {
        throw const FormatException('小U完成状态动作无效。');
      }
    } else if (type == AssistantActionType.submitIspaceChoice) {
      if (!requiresConfirmation ||
          ispaceCompleted != null ||
          choiceOptionIds.isEmpty ||
          !RegExp(
            r'^m1:[1-9][0-9]{0,19}:[1-9][0-9]{0,19}:'
            r'[1-9][0-9]{0,19}:choice$',
          ).hasMatch(targetId)) {
        throw const FormatException('小U Choice 提交动作无效。');
      }
    } else if (ispaceCompleted != null || choiceOptionIds.isNotEmpty) {
      throw const FormatException('小U iSpace 动作字段无效。');
    }
    var courseFileScope = AssistantCourseFileScope.parseOptional(
      json['course_file_scope'],
    );
    if (type == AssistantActionType.batchDownloadCourseFiles &&
        courseFileScope == null) {
      courseFileScope = AssistantCourseFileScope.all;
    } else if (type != AssistantActionType.batchDownloadCourseFiles &&
        courseFileScope != null) {
      throw const FormatException('小U课程文件动作范围无效。');
    }
    return AssistantAction(
      type: type,
      title: _requiredString(json, 'title'),
      requiresConfirmation: requiresConfirmation,
      targetId: targetId,
      url: _optionalString(json, 'url'),
      recipient: _optionalString(json, 'recipient'),
      mailMode: _optionalString(json, 'mail_mode'),
      subject: _optionalString(json, 'subject'),
      body: _optionalString(json, 'body'),
      placeQuery: _optionalString(json, 'place_query'),
      actionId: _optionalString(json, 'action_id'),
      sessionOwner: _optionalString(json, 'session_owner'),
      targetIdentity: _optionalString(json, 'target_identity'),
      expiresAt: _optionalDateTime(json, 'expires_at'),
      mailUid: _optionalPositiveInt(json, 'mail_uid'),
      mailFolder: _optionalString(json, 'mail_folder'),
      mailboxUidValidity: _optionalPositiveInt(json, 'mailbox_uid_validity'),
      mailPartId: _optionalString(json, 'mail_part_id'),
      attachmentName: _optionalString(json, 'attachment_name'),
      courseFileScope: courseFileScope,
      scheduleKind: _optionalString(json, 'schedule_kind'),
      scheduleCourseKey: _optionalString(json, 'schedule_course_key'),
      taTitle: _optionalString(json, 'ta_title'),
      taLocation: _optionalString(json, 'ta_location'),
      taWeekday: _optionalPositiveInt(json, 'ta_weekday'),
      taStartMinutes: _optionalNonNegativeInt(json, 'ta_start_minutes'),
      taEndMinutes: _optionalPositiveInt(json, 'ta_end_minutes'),
      taRepeatType: _optionalString(json, 'ta_repeat_type'),
      taWeekStart: _optionalDateTime(json, 'ta_week_start'),
      taExpectedEntryRevision: _optionalNonNegativeInt(
        json,
        'ta_expected_entry_revision',
      ),
      taExpectedCollectionRevision: _optionalNonNegativeInt(
        json,
        'ta_expected_collection_revision',
      ),
      notificationTitle: _optionalString(json, 'notification_title'),
      notificationBody: _optionalString(json, 'notification_body'),
      notificationAt: _optionalTimezoneAwareDateTime(json, 'notification_at'),
      scheduleDate: _optionalString(json, 'schedule_date'),
      scheduleView: _optionalString(json, 'schedule_view'),
      quizAttemptId: _optionalPositiveInt(json, 'quiz_attempt_id'),
      quizResponses: json['quiz_responses'] == null
          ? const []
          : _objectList(
              json['quiz_responses'],
            ).map(AssistantQuizResponse.fromJson).toList(growable: false),
      ispaceCompleted: ispaceCompleted,
      choiceOptionIds: choiceOptionIds,
    );
  }

  AssistantAction copyWith({
    String? title,
    bool? requiresConfirmation,
    String? targetId,
    String? url,
    String? recipient,
    String? mailMode,
    String? subject,
    String? body,
    String? placeQuery,
    String? actionId,
    String? sessionOwner,
    String? targetIdentity,
    DateTime? expiresAt,
    int? mailUid,
    String? mailFolder,
    int? mailboxUidValidity,
    String? mailPartId,
    String? attachmentName,
    AssistantCourseFileScope? courseFileScope,
    String? scheduleKind,
    String? scheduleCourseKey,
    String? taTitle,
    String? taLocation,
    int? taWeekday,
    int? taStartMinutes,
    int? taEndMinutes,
    String? taRepeatType,
    DateTime? taWeekStart,
    bool clearTaWeekStart = false,
    int? taExpectedEntryRevision,
    int? taExpectedCollectionRevision,
    String? notificationTitle,
    String? notificationBody,
    DateTime? notificationAt,
    String? scheduleDate,
    String? scheduleView,
    int? quizAttemptId,
    List<AssistantQuizResponse>? quizResponses,
    bool? ispaceCompleted,
    List<String>? choiceOptionIds,
    List<AssistantInputAttachment>? localAttachments,
  }) {
    return AssistantAction(
      type: type,
      title: title ?? this.title,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      targetId: targetId ?? this.targetId,
      url: url ?? this.url,
      recipient: recipient ?? this.recipient,
      mailMode: mailMode ?? this.mailMode,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      placeQuery: placeQuery ?? this.placeQuery,
      actionId: actionId ?? this.actionId,
      sessionOwner: sessionOwner ?? this.sessionOwner,
      targetIdentity: targetIdentity ?? this.targetIdentity,
      expiresAt: expiresAt ?? this.expiresAt,
      mailUid: mailUid ?? this.mailUid,
      mailFolder: mailFolder ?? this.mailFolder,
      mailboxUidValidity: mailboxUidValidity ?? this.mailboxUidValidity,
      mailPartId: mailPartId ?? this.mailPartId,
      attachmentName: attachmentName ?? this.attachmentName,
      courseFileScope: courseFileScope ?? this.courseFileScope,
      scheduleKind: scheduleKind ?? this.scheduleKind,
      scheduleCourseKey: scheduleCourseKey ?? this.scheduleCourseKey,
      taTitle: taTitle ?? this.taTitle,
      taLocation: taLocation ?? this.taLocation,
      taWeekday: taWeekday ?? this.taWeekday,
      taStartMinutes: taStartMinutes ?? this.taStartMinutes,
      taEndMinutes: taEndMinutes ?? this.taEndMinutes,
      taRepeatType: taRepeatType ?? this.taRepeatType,
      taWeekStart: clearTaWeekStart ? null : taWeekStart ?? this.taWeekStart,
      taExpectedEntryRevision:
          taExpectedEntryRevision ?? this.taExpectedEntryRevision,
      taExpectedCollectionRevision:
          taExpectedCollectionRevision ?? this.taExpectedCollectionRevision,
      notificationTitle: notificationTitle ?? this.notificationTitle,
      notificationBody: notificationBody ?? this.notificationBody,
      notificationAt: notificationAt ?? this.notificationAt,
      scheduleDate: scheduleDate ?? this.scheduleDate,
      scheduleView: scheduleView ?? this.scheduleView,
      quizAttemptId: quizAttemptId ?? this.quizAttemptId,
      quizResponses: quizResponses ?? this.quizResponses,
      ispaceCompleted: ispaceCompleted ?? this.ispaceCompleted,
      choiceOptionIds: choiceOptionIds ?? this.choiceOptionIds,
      localAttachments: localAttachments ?? this.localAttachments,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.wireValue,
    'title': title,
    'requires_confirmation': requiresConfirmation,
    'target_id': targetId,
    'url': url,
    'recipient': recipient,
    if (mailMode.isNotEmpty) 'mail_mode': mailMode,
    'subject': subject,
    'body': body,
    'place_query': placeQuery,
    'action_id': actionId,
    'session_owner': sessionOwner,
    'target_identity': targetIdentity,
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
    if (mailUid != null) 'mail_uid': mailUid,
    'mail_folder': mailFolder,
    if (mailboxUidValidity != null) 'mailbox_uid_validity': mailboxUidValidity,
    'mail_part_id': mailPartId,
    'attachment_name': attachmentName,
    'course_file_scope': courseFileScope?.wireValue ?? '',
    if (scheduleKind.isNotEmpty) 'schedule_kind': scheduleKind,
    if (scheduleCourseKey.isNotEmpty) 'schedule_course_key': scheduleCourseKey,
    'ta_title': taTitle,
    'ta_location': taLocation,
    if (taWeekday != null) 'ta_weekday': taWeekday,
    if (taStartMinutes != null) 'ta_start_minutes': taStartMinutes,
    if (taEndMinutes != null) 'ta_end_minutes': taEndMinutes,
    'ta_repeat_type': taRepeatType,
    if (taWeekStart != null)
      'ta_week_start': taWeekStart!.toUtc().toIso8601String(),
    if (taExpectedEntryRevision != null)
      'ta_expected_entry_revision': taExpectedEntryRevision,
    if (taExpectedCollectionRevision != null)
      'ta_expected_collection_revision': taExpectedCollectionRevision,
    'notification_title': notificationTitle,
    'notification_body': notificationBody,
    if (scheduleDate.isNotEmpty) 'schedule_date': scheduleDate,
    if (scheduleView.isNotEmpty) 'schedule_view': scheduleView,
    if (notificationAt != null)
      'notification_at': notificationAt!.toUtc().toIso8601String(),
    if (quizAttemptId != null) 'quiz_attempt_id': quizAttemptId,
    'quiz_responses': quizResponses
        .map((item) => item.toJson())
        .toList(growable: false),
    if (ispaceCompleted != null) 'ispace_completed': ispaceCompleted,
    'choice_option_ids': choiceOptionIds,
  };
}

class AssistantQuizResponse {
  const AssistantQuizResponse({
    required this.slot,
    required this.fieldName,
    required this.value,
  });

  final int slot;
  final String fieldName;
  final String value;

  factory AssistantQuizResponse.fromJson(Map<String, dynamic> json) {
    final slot = _requiredInt(json, 'slot');
    final fieldName = _requiredString(json, 'field_name').trim();
    final value = _requiredString(json, 'value');
    if (slot <= 0 ||
        slot > 10000 ||
        fieldName.isEmpty ||
        fieldName.length > 160 ||
        value.length > 4000) {
      throw const FormatException('小U测验答案格式无效。');
    }
    return AssistantQuizResponse(
      slot: slot,
      fieldName: fieldName,
      value: value,
    );
  }

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'field_name': fieldName,
    'value': value,
  };
}

class AssistantSuggestion {
  const AssistantSuggestion({
    required this.label,
    required this.message,
    required this.isOther,
  });

  final String label;
  final String message;
  final bool isOther;

  factory AssistantSuggestion.fromJson(Map<String, dynamic> json) {
    final label = _requiredString(json, 'label').trim();
    final message = _optionalString(json, 'message').trim();
    final kind = _requiredString(json, 'kind');
    if (label.length > 40 ||
        message.length > 300 ||
        (kind != 'submit' && kind != 'other')) {
      throw const FormatException('小U建议选项格式无效。');
    }
    final isOther = kind == 'other';
    if (isOther
        ? label != '其他' || message.isNotEmpty
        : label == '其他' || message.isEmpty) {
      throw const FormatException('小U建议选项格式无效。');
    }
    return AssistantSuggestion(
      label: label,
      message: message,
      isOther: isOther,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'message': message,
    'kind': isOther ? 'other' : 'submit',
  };
}

enum AssistantMemorySuggestionStatus { pending, saved, dismissed }

class AssistantMemorySuggestion {
  const AssistantMemorySuggestion({
    required this.content,
    this.status = AssistantMemorySuggestionStatus.pending,
    this.memoryType = 'persona',
    this.sourceId = '',
  });

  final String content;
  final AssistantMemorySuggestionStatus status;
  final String memoryType;
  final String sourceId;

  bool get isPending => status == AssistantMemorySuggestionStatus.pending;

  AssistantMemorySuggestion copyWith({
    String? content,
    AssistantMemorySuggestionStatus? status,
    String? memoryType,
    String? sourceId,
  }) => AssistantMemorySuggestion(
    content: content ?? this.content,
    status: status ?? this.status,
    memoryType: memoryType ?? this.memoryType,
    sourceId: sourceId ?? this.sourceId,
  );

  factory AssistantMemorySuggestion.fromJson(Map<String, dynamic> json) {
    final content = _requiredString(json, 'content').trim();
    final rawStatus = _optionalString(json, 'status');
    final status = switch (rawStatus) {
      '' || 'pending' => AssistantMemorySuggestionStatus.pending,
      'saved' => AssistantMemorySuggestionStatus.saved,
      'dismissed' => AssistantMemorySuggestionStatus.dismissed,
      _ => throw const FormatException('小U记忆建议格式无效。'),
    };
    if (content.isEmpty || content.length > 1000) {
      throw const FormatException('小U记忆建议格式无效。');
    }
    return AssistantMemorySuggestion(
      content: content,
      status: status,
      memoryType: switch (_optionalString(json, 'memory_type')) {
        'episodic' => 'episodic',
        'instruction' => 'instruction',
        _ => 'persona',
      },
      sourceId: _optionalString(json, 'source_id'),
    );
  }

  Map<String, dynamic> toJson() => {
    'content': content,
    'status': status.name,
    'memory_type': memoryType,
    'source_id': sourceId,
  };
}

class AssistantChatResult {
  const AssistantChatResult({
    required this.requestId,
    required this.answer,
    required this.actions,
    required this.usage,
    required this.quota,
    this.suggestions = const [],
    this.memorySuggestions = const [],
    this.publicToolReceipts = const [],
  });

  final String requestId;
  final String answer;
  final List<AssistantAction> actions;
  final List<AssistantSuggestion> suggestions;
  final List<AssistantMemorySuggestion> memorySuggestions;
  final List<Map<String, dynamic>> publicToolReceipts;
  final AssistantTokenUsage usage;
  final AssistantQuota quota;

  factory AssistantChatResult.fromJson(Map<String, dynamic> json) {
    final suggestions = json['suggestions'] == null
        ? const <AssistantSuggestion>[]
        : _objectList(
            json['suggestions'],
          ).map(AssistantSuggestion.fromJson).toList(growable: false);
    _requireValidSuggestions(suggestions);
    final memorySuggestions = json['memory_suggestions'] == null
        ? const <AssistantMemorySuggestion>[]
        : _objectList(json['memory_suggestions'])
              .map(AssistantMemorySuggestion.fromJson)
              .take(3)
              .toList(growable: false);
    return AssistantChatResult(
      requestId: _requiredString(json, 'request_id'),
      answer: normalizeAssistantProse(_requiredString(json, 'answer')),
      actions: _objectList(
        json['actions'],
      ).map(AssistantAction.fromJson).toList(growable: false),
      suggestions: List.unmodifiable(suggestions),
      memorySuggestions: List.unmodifiable(memorySuggestions),
      publicToolReceipts: List.unmodifiable(
        _objectList(json['public_tool_receipts'] ?? const []).take(32),
      ),
      usage: AssistantTokenUsage.fromJson(_object(json['usage'])),
      quota: AssistantQuota.fromJson(_object(json['quota'])),
    );
  }
}

class AssistantAgentToolCall {
  const AssistantAgentToolCall({
    required this.callId,
    required this.name,
    required this.arguments,
  });

  final String callId;
  final String name;
  final Map<String, dynamic> arguments;

  factory AssistantAgentToolCall.fromJson(Map<String, dynamic> json) {
    final callId = _requiredString(json, 'call_id');
    final name = _requiredString(json, 'name');
    if (callId.length > 200 ||
        name.length > 80 ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw const FormatException('小U工具调用格式无效。');
    }
    final arguments = _object(json['arguments']);
    return AssistantAgentToolCall(
      callId: callId,
      name: name,
      arguments: Map.unmodifiable(arguments),
    );
  }
}

class AssistantAgentToolResult {
  const AssistantAgentToolResult({
    required this.callId,
    required this.context,
    this.elapsedMilliseconds,
  });

  final String callId;
  final AssistantContextPayload context;
  final int? elapsedMilliseconds;

  Map<String, dynamic> toJson() => {
    'call_id': callId,
    if (elapsedMilliseconds != null) 'client_duration_ms': elapsedMilliseconds,
    'context': context.toJson(),
  };
}

class AssistantAgentTurnResult {
  const AssistantAgentTurnResult({
    required this.requestId,
    required this.conversationId,
    required this.round,
    required this.toolCalls,
    required this.continuationToken,
    required this.chatResult,
    required this.usage,
    required this.quota,
  });

  final String requestId;
  final String conversationId;
  final int round;
  final List<AssistantAgentToolCall> toolCalls;
  final String continuationToken;
  final AssistantChatResult? chatResult;
  final AssistantTokenUsage usage;
  final AssistantQuota quota;

  bool get requiresTools => toolCalls.isNotEmpty;

  factory AssistantAgentTurnResult.fromJson(Map<String, dynamic> json) {
    final status = _requiredString(json, 'status');
    final round = _requiredInt(json, 'round');
    if (round < 1) {
      throw const FormatException('小U Agent 轮次无效。');
    }
    final toolCalls = _objectList(
      json['tool_calls'],
    ).map(AssistantAgentToolCall.fromJson).toList(growable: false);
    final continuationToken = _optionalString(json, 'continuation_token');
    final usage = AssistantTokenUsage.fromJson(_object(json['usage']));
    final quota = AssistantQuota.fromJson(_object(json['quota']));
    AssistantChatResult? chatResult;
    if (status == 'requires_tools') {
      if (toolCalls.isEmpty ||
          toolCalls.length > 4 ||
          continuationToken.isEmpty) {
        throw const FormatException('小U Agent 工具请求格式无效。');
      }
    } else if (status == 'completed') {
      if (toolCalls.isNotEmpty || continuationToken.isNotEmpty) {
        throw const FormatException('小U Agent 完成结果格式无效。');
      }
      chatResult = AssistantChatResult.fromJson(json);
    } else {
      throw const FormatException('小U Agent 状态无效。');
    }
    return AssistantAgentTurnResult(
      requestId: _requiredString(json, 'request_id'),
      conversationId: _requiredString(json, 'conversation_id'),
      round: round,
      toolCalls: List.unmodifiable(toolCalls),
      continuationToken: continuationToken,
      chatResult: chatResult,
      usage: usage,
      quota: quota,
    );
  }
}

void _requireValidSuggestions(List<AssistantSuggestion> suggestions) {
  if (suggestions.isEmpty) {
    return;
  }
  if (suggestions.length < 2 ||
      suggestions.length > 5 ||
      !suggestions.last.isOther ||
      suggestions.take(suggestions.length - 1).any((item) => item.isOther)) {
    throw const FormatException('小U建议选项格式无效。');
  }
  final labels = suggestions
      .take(suggestions.length - 1)
      .map((item) => item.label.toLowerCase())
      .toSet();
  final messages = suggestions
      .take(suggestions.length - 1)
      .map((item) => item.message.toLowerCase())
      .toSet();
  if (labels.length != suggestions.length - 1 ||
      messages.length != suggestions.length - 1) {
    throw const FormatException('小U建议选项包含重复内容。');
  }
}

class AssistantConversationMessage {
  const AssistantConversationMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AssistantCourseContext {
  const AssistantCourseContext({
    required this.courseId,
    required this.name,
    required this.teachers,
  });

  final String courseId;
  final String name;
  final List<String> teachers;

  Map<String, dynamic> toJson() => {
    'course_id': courseId,
    'name': name,
    'teachers': teachers,
  };
}

class AssistantIspaceCourseCatalogContext {
  const AssistantIspaceCourseCatalogContext({
    required this.courses,
    required this.complete,
    required this.omittedCourseCount,
    required this.failedCourseCount,
    required this.truncated,
  });

  final List<AssistantIspaceCourseContext> courses;
  final bool complete;
  final int omittedCourseCount;
  final int failedCourseCount;
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'courses': courses.map((item) => item.toJson()).toList(growable: false),
    'complete': complete,
    'omitted_course_count': omittedCourseCount,
    'failed_course_count': failedCourseCount,
    'truncated': truncated,
  };
}

class AssistantIspaceCourseContext {
  const AssistantIspaceCourseContext({
    required this.courseId,
    required this.name,
    required this.shortName,
    required this.category,
    required this.startAt,
    required this.endAt,
    required this.teachers,
    required this.sections,
    required this.truncated,
    this.progress,
    this.completionEnabled = false,
    this.completionUserTracked = false,
    this.completed = false,
    this.showGrades = false,
    this.sectionCount,
    this.visibleSectionCount,
    this.moduleCount,
    this.visibleModuleCount,
    this.moduleTypeCounts = const {},
    this.visibleModuleTypeCounts = const {},
    this.completionTrackingCounts = const {},
    this.visibleCompletionTrackingCounts = const {},
  });

  final String courseId;
  final String name;
  final String shortName;
  final String category;
  final DateTime? startAt;
  final DateTime? endAt;
  final List<String> teachers;
  final List<AssistantIspaceSectionContext> sections;
  final bool truncated;
  final int? progress;
  final bool completionEnabled;
  final bool completionUserTracked;
  final bool completed;
  final bool showGrades;
  final int? sectionCount;
  final int? visibleSectionCount;
  final int? moduleCount;
  final int? visibleModuleCount;
  final Map<String, int> moduleTypeCounts;
  final Map<String, int> visibleModuleTypeCounts;
  final Map<String, int> completionTrackingCounts;
  final Map<String, int> visibleCompletionTrackingCounts;

  Map<String, dynamic> toJson() => {
    'course_id': courseId,
    'name': name,
    'short_name': shortName,
    'category': category,
    if (startAt != null) 'start_at': startAt!.toUtc().toIso8601String(),
    if (endAt != null) 'end_at': endAt!.toUtc().toIso8601String(),
    'teachers': teachers,
    'sections': sections.map((item) => item.toJson()).toList(growable: false),
    'truncated': truncated,
    if (progress != null) 'progress': progress,
    'completion_enabled': completionEnabled,
    'completion_user_tracked': completionUserTracked,
    'completed': completed,
    'show_grades': showGrades,
    if (sectionCount != null) 'section_count': sectionCount,
    if (visibleSectionCount != null)
      'visible_section_count': visibleSectionCount,
    if (moduleCount != null) 'module_count': moduleCount,
    if (visibleModuleCount != null) 'visible_module_count': visibleModuleCount,
    if (moduleCount != null) 'module_type_counts': moduleTypeCounts,
    if (visibleModuleCount != null)
      'visible_module_type_counts': visibleModuleTypeCounts,
    if (moduleCount != null)
      'completion_tracking_counts': completionTrackingCounts,
    if (visibleModuleCount != null)
      'visible_completion_tracking_counts': visibleCompletionTrackingCounts,
  };
}

class AssistantIspaceSectionContext {
  const AssistantIspaceSectionContext({
    required this.sectionId,
    required this.name,
    required this.modules,
    this.userVisible = true,
  });

  final String sectionId;
  final String name;
  final List<AssistantIspaceModuleContext> modules;
  final bool userVisible;

  Map<String, dynamic> toJson() => {
    'section_id': sectionId,
    'name': name,
    'modules': modules.map((item) => item.toJson()).toList(growable: false),
    'user_visible': userVisible,
  };
}

class AssistantIspaceModuleContext {
  const AssistantIspaceModuleContext({
    required this.moduleId,
    required this.name,
    required this.moduleType,
    required this.files,
    this.moduleRef = '',
    this.instanceId = '',
    this.userVisible = true,
    this.availabilityInfo = '',
    this.completionTracking = 0,
    this.completionState = 0,
    this.completedAt,
    this.canManualComplete = false,
    this.canDownloadFiles = false,
    this.dates = const [],
  });

  final String moduleId;
  final String name;
  final String moduleType;
  final List<AssistantIspaceFileContext> files;
  final String moduleRef;
  final String instanceId;
  final bool userVisible;
  final String availabilityInfo;
  final int completionTracking;
  final int completionState;
  final DateTime? completedAt;
  final bool canManualComplete;
  final bool canDownloadFiles;
  final List<AssistantIspaceModuleDateContext> dates;

  Map<String, dynamic> toJson() => {
    'module_id': moduleId,
    'name': name,
    'module_type': moduleType,
    'files': files.map((item) => item.toJson()).toList(growable: false),
    if (moduleRef.isNotEmpty) 'module_ref': moduleRef,
    if (instanceId.isNotEmpty) 'instance_id': instanceId,
    'user_visible': userVisible,
    'availability_info': availabilityInfo,
    'completion_tracking': completionTracking,
    'completion_state': completionState,
    if (completedAt != null)
      'completed_at': completedAt!.toUtc().toIso8601String(),
    'can_manual_complete': canManualComplete,
    'can_download_files': canDownloadFiles,
    'dates': dates.map((item) => item.toJson()).toList(growable: false),
  };
}

class AssistantIspaceModuleDateContext {
  const AssistantIspaceModuleDateContext({
    required this.label,
    required this.dataId,
    required this.at,
  });

  final String label;
  final String dataId;
  final DateTime? at;

  Map<String, dynamic> toJson() => {
    'label': label,
    'data_id': dataId,
    if (at != null) 'at': at!.toUtc().toIso8601String(),
  };
}

class AssistantIspaceFileContext {
  const AssistantIspaceFileContext({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.author,
  });

  final String name;
  final String mimeType;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final String author;

  Map<String, dynamic> toJson() => {
    'name': name,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    if (modifiedAt != null)
      'modified_at': modifiedAt!.toUtc().toIso8601String(),
    'author': author,
  };
}

class AssistantTermContext {
  const AssistantTermContext({required this.label, required this.asOf});

  final String label;
  final DateTime asOf;

  Map<String, dynamic> toJson() => {
    'label': label,
    'as_of': asOf.toUtc().toIso8601String(),
  };
}

class AssistantTermCourseContext extends AssistantCourseContext {
  const AssistantTermCourseContext({
    required super.courseId,
    required super.name,
    required super.teachers,
    required this.nextStartsAt,
    required this.nextRoom,
  });

  final DateTime? nextStartsAt;
  final String nextRoom;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    if (nextStartsAt != null)
      'next_starts_at': nextStartsAt!.toUtc().toIso8601String(),
    'next_room': nextRoom,
  };
}

class AssistantDeadlineContext {
  const AssistantDeadlineContext({
    required this.itemId,
    required this.title,
    required this.courseName,
    required this.activityType,
    required this.dueAt,
    this.courseId = '',
    this.courseModuleId = '',
    this.instanceId = '',
  });

  final String itemId;
  final String title;
  final String courseName;
  final String activityType;
  final DateTime dueAt;
  final String courseId;
  final String courseModuleId;
  final String instanceId;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'title': title,
    'course_name': courseName,
    'activity_type': activityType,
    'due_at': dueAt.toUtc().toIso8601String(),
    'course_id': courseId,
    'course_module_id': courseModuleId,
    'instance_id': instanceId,
  };
}

class AssistantIspaceActivityContext {
  const AssistantIspaceActivityContext({
    required this.itemId,
    required this.courseId,
    required this.courseModuleId,
    required this.instanceId,
    required this.activityType,
    required this.title,
    required this.courseName,
    required this.summary,
    required this.openAt,
    required this.dueAt,
    required this.closeAt,
    required this.submissionStatus,
    required this.canEditSubmission,
    required this.supportsFileSubmission,
    required this.supportsOnlineTextSubmission,
    required this.maxFileSubmissions,
    required this.maxSubmissionSizeBytes,
    required this.files,
    this.gradingStatus = '',
    this.feedbackSummary = '',
    this.submissionFiles = const [],
    this.forumId = '',
    this.forumDiscussions = const [],
    this.canStartDiscussion = false,
    this.submissionDrafts = false,
    this.requiresSubmissionStatement = false,
    this.teamSubmission = false,
    this.requireAllTeamMembersSubmit = false,
    this.preventSubmissionNotInGroup = false,
    this.timeLimitSeconds = 0,
    this.submissionsEnabled = false,
    this.submissionLocked = false,
    this.canFinalizeSubmission = false,
  });

  final String itemId;
  final String courseId;
  final String courseModuleId;
  final String instanceId;
  final String activityType;
  final String title;
  final String courseName;
  final String summary;
  final DateTime? openAt;
  final DateTime? dueAt;
  final DateTime? closeAt;
  final String submissionStatus;
  final bool canEditSubmission;
  final bool supportsFileSubmission;
  final bool supportsOnlineTextSubmission;
  final int maxFileSubmissions;
  final int maxSubmissionSizeBytes;
  final List<AssistantIspaceFileContext> files;
  final String gradingStatus;
  final String feedbackSummary;
  final List<AssistantIspaceFileContext> submissionFiles;
  final String forumId;
  final List<AssistantIspaceForumDiscussionContext> forumDiscussions;
  final bool canStartDiscussion;
  final bool submissionDrafts;
  final bool requiresSubmissionStatement;
  final bool teamSubmission;
  final bool requireAllTeamMembersSubmit;
  final bool preventSubmissionNotInGroup;
  final int timeLimitSeconds;
  final bool submissionsEnabled;
  final bool submissionLocked;
  final bool canFinalizeSubmission;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'course_id': courseId,
    'course_module_id': courseModuleId,
    'instance_id': instanceId,
    'activity_type': activityType,
    'title': title,
    'course_name': courseName,
    'summary': summary,
    if (openAt != null) 'open_at': openAt!.toUtc().toIso8601String(),
    if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
    if (closeAt != null) 'close_at': closeAt!.toUtc().toIso8601String(),
    'submission_status': submissionStatus,
    'can_edit_submission': canEditSubmission,
    'supports_file_submission': supportsFileSubmission,
    'supports_online_text_submission': supportsOnlineTextSubmission,
    'max_file_submissions': maxFileSubmissions,
    'max_submission_size_bytes': maxSubmissionSizeBytes,
    'max_submission_size_scope': 'per_file',
    'files': files.map((item) => item.toJson()).toList(growable: false),
    'grading_status': gradingStatus,
    'feedback_summary': feedbackSummary,
    'submission_files': submissionFiles
        .map((item) => item.toJson())
        .toList(growable: false),
    'forum_id': forumId,
    'forum_discussions': forumDiscussions
        .map((item) => item.toJson())
        .toList(growable: false),
    'can_start_discussion': canStartDiscussion,
    'submission_drafts': submissionDrafts,
    'requires_submission_statement': requiresSubmissionStatement,
    'team_submission': teamSubmission,
    'require_all_team_members_submit': requireAllTeamMembersSubmit,
    'prevent_submission_not_in_group': preventSubmissionNotInGroup,
    'time_limit_seconds': timeLimitSeconds,
    'submissions_enabled': submissionsEnabled,
    'submission_locked': submissionLocked,
    'can_finalize_submission': canFinalizeSubmission,
  };
}

class AssistantIspaceForumDiscussionContext {
  const AssistantIspaceForumDiscussionContext({
    required this.discussionId,
    required this.subject,
    required this.messagePreview,
    required this.author,
    required this.modifiedAt,
    required this.replyCount,
    required this.pinned,
    required this.locked,
  });

  final String discussionId;
  final String subject;
  final String messagePreview;
  final String author;
  final DateTime? modifiedAt;
  final int replyCount;
  final bool pinned;
  final bool locked;

  Map<String, dynamic> toJson() => {
    'discussion_id': discussionId,
    'subject': subject,
    'message_preview': messagePreview,
    'author': author,
    if (modifiedAt != null)
      'modified_at': modifiedAt!.toUtc().toIso8601String(),
    'reply_count': replyCount,
    'pinned': pinned,
    'locked': locked,
  };
}

class AssistantIspaceQuizAttemptContext {
  const AssistantIspaceQuizAttemptContext({
    required this.itemId,
    required this.quizId,
    required this.attemptId,
    required this.state,
    required this.canStart,
    required this.canSave,
    required this.canFinish,
    required this.accessMessage,
    required this.questions,
    required this.truncated,
  });

  final String itemId;
  final int quizId;
  final int attemptId;
  final String state;
  final bool canStart;
  final bool canSave;
  final bool canFinish;
  final String accessMessage;
  final List<AssistantQuizQuestionContext> questions;
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'quiz_id': quizId,
    'attempt_id': attemptId,
    'state': state,
    'can_start': canStart,
    'can_save': canSave,
    'can_finish': canFinish,
    'access_message': accessMessage,
    'questions': questions.map((item) => item.toJson()).toList(growable: false),
    'truncated': truncated,
  };
}

class AssistantQuizQuestionContext {
  const AssistantQuizQuestionContext({
    required this.slot,
    required this.number,
    required this.type,
    required this.prompt,
    required this.status,
    required this.fields,
  });

  final int slot;
  final String number;
  final String type;
  final String prompt;
  final String status;
  final List<AssistantQuizAnswerFieldContext> fields;

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'number': number,
    'type': type,
    'prompt': prompt,
    'status': status,
    'fields': fields.map((item) => item.toJson()).toList(growable: false),
  };
}

class AssistantQuizAnswerFieldContext {
  const AssistantQuizAnswerFieldContext({
    required this.name,
    required this.kind,
    required this.label,
    required this.currentValues,
    required this.options,
    required this.maxLength,
    required this.multiple,
  });

  final String name;
  final String kind;
  final String label;
  final List<String> currentValues;
  final List<AssistantQuizAnswerOptionContext> options;
  final int maxLength;
  final bool multiple;

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind,
    'label': label,
    'current_values': currentValues,
    'options': options.map((item) => item.toJson()).toList(growable: false),
    'max_length': maxLength,
    'multiple': multiple,
  };
}

class AssistantQuizAnswerOptionContext {
  const AssistantQuizAnswerOptionContext({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

class AssistantIspaceGradeItemContext {
  const AssistantIspaceGradeItemContext({
    required this.itemId,
    required this.name,
    required this.moduleType,
    required this.courseModuleId,
    required this.grade,
    required this.range,
    required this.percentage,
    required this.feedback,
    required this.hidden,
    required this.locked,
    required this.submittedAt,
    required this.gradedAt,
  });

  final String itemId;
  final String name;
  final String moduleType;
  final String courseModuleId;
  final String grade;
  final String range;
  final String percentage;
  final String feedback;
  final bool hidden;
  final bool locked;
  final DateTime? submittedAt;
  final DateTime? gradedAt;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'name': name,
    'module_type': moduleType,
    'course_module_id': courseModuleId,
    'grade': grade,
    'range': range,
    'percentage': percentage,
    'feedback': feedback,
    'hidden': hidden,
    'locked': locked,
    if (submittedAt != null)
      'submitted_at': submittedAt!.toUtc().toIso8601String(),
    if (gradedAt != null) 'graded_at': gradedAt!.toUtc().toIso8601String(),
  };
}

class AssistantIspaceCourseGradesContext {
  const AssistantIspaceCourseGradesContext({
    required this.courseId,
    required this.items,
    required this.truncated,
  });

  final String courseId;
  final List<AssistantIspaceGradeItemContext> items;
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'course_id': courseId,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'truncated': truncated,
  };
}

class AssistantIspaceChoiceOptionContext {
  const AssistantIspaceChoiceOptionContext({
    required this.optionId,
    required this.label,
    required this.selected,
    required this.disabled,
    required this.maxAnswers,
  });

  final String optionId;
  final String label;
  final bool selected;
  final bool disabled;
  final int maxAnswers;

  Map<String, dynamic> toJson() => {
    'option_id': optionId,
    'label': label,
    'selected': selected,
    'disabled': disabled,
    'max_answers': maxAnswers,
  };
}

class AssistantIspaceToolResultContext {
  const AssistantIspaceToolResultContext({
    required this.resultKey,
    this.content,
    required this.kind,
    required this.observedAt,
    required this.courseId,
    this.moduleRef = '',
    this.moduleId = '',
    this.instanceId = '',
    this.moduleType = '',
    this.name = '',
    this.courseName = '',
    this.summary = '',
    this.userVisible = true,
    this.availabilityInfo = '',
    this.completionTracking = 0,
    this.completionState = 0,
    this.completedAt,
    this.capabilities = const [],
    this.files = const [],
    this.activity,
    this.quizAttempt,
    this.courseGrades,
    this.choiceOptions = const [],
    this.choiceAllowMultiple = false,
    this.choiceAllowUpdate = false,
    this.truncated = false,
  });

  final AssistantContentPage? content;
  final String resultKey;
  final String kind;
  final DateTime observedAt;
  final String courseId;
  final String moduleRef;
  final String moduleId;
  final String instanceId;
  final String moduleType;
  final String name;
  final String courseName;
  final String summary;
  final bool userVisible;
  final String availabilityInfo;
  final int completionTracking;
  final int completionState;
  final DateTime? completedAt;
  final List<String> capabilities;
  final List<AssistantIspaceFileContext> files;
  final AssistantIspaceActivityContext? activity;
  final AssistantIspaceQuizAttemptContext? quizAttempt;
  final AssistantIspaceCourseGradesContext? courseGrades;
  final List<AssistantIspaceChoiceOptionContext> choiceOptions;
  final bool choiceAllowMultiple;
  final bool choiceAllowUpdate;
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'result_key': resultKey,
    if (content != null) 'content': content!.toJson(),
    'kind': kind,
    'observed_at': observedAt.toUtc().toIso8601String(),
    'course_id': courseId,
    'module_ref': moduleRef,
    'module_id': moduleId,
    'instance_id': instanceId,
    'module_type': moduleType,
    'name': name,
    'course_name': courseName,
    'summary': summary,
    'user_visible': userVisible,
    'availability_info': availabilityInfo,
    'completion_tracking': completionTracking,
    'completion_state': completionState,
    if (completedAt != null)
      'completed_at': completedAt!.toUtc().toIso8601String(),
    'capabilities': capabilities,
    'files': files.map((item) => item.toJson()).toList(growable: false),
    if (activity != null) 'activity': activity!.toJson(),
    if (quizAttempt != null) 'quiz_attempt': quizAttempt!.toJson(),
    if (courseGrades != null) 'course_grades': courseGrades!.toJson(),
    'choice_options': choiceOptions
        .map((item) => item.toJson())
        .toList(growable: false),
    'choice_allow_multiple': choiceAllowMultiple,
    'choice_allow_update': choiceAllowUpdate,
    'truncated': truncated,
  };
}

class AssistantScheduleContext {
  const AssistantScheduleContext({
    required this.courseName,
    required this.room,
    required this.startsAt,
    required this.endsAt,
    this.courseId = '',
  });

  final String courseId;
  final String courseName;
  final String room;
  final DateTime startsAt;
  final DateTime endsAt;

  Map<String, dynamic> toJson() => {
    'course_id': courseId,
    'course_name': courseName,
    'room': room,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
  };
}

class AssistantAcademicCalendarEventContext {
  const AssistantAcademicCalendarEventContext({
    required this.kind,
    required this.name,
    required this.startsOn,
    required this.endsOn,
    this.reason = '',
    this.sourceWeekday,
  });

  final String kind;
  final String name;
  final DateTime startsOn;
  final DateTime endsOn;
  final String reason;
  final int? sourceWeekday;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'name': name,
    'starts_on': _dateOnlyString(startsOn),
    'ends_on': _dateOnlyString(endsOn),
    if (reason.isNotEmpty) 'reason': reason,
    if (sourceWeekday != null) 'source_weekday': sourceWeekday,
  };
}

class AssistantAcademicCalendarDocumentContext {
  const AssistantAcademicCalendarDocumentContext({
    required this.kind,
    required this.title,
    required this.url,
  });

  final String kind;
  final String title;
  final String url;

  Map<String, dynamic> toJson() => {'kind': kind, 'title': title, 'url': url};
}

class AssistantAcademicCalendarContext {
  const AssistantAcademicCalendarContext({
    required this.semesterTitle,
    required this.timezone,
    required this.appliesToSelectedSemester,
    required this.semesterStartsOn,
    required this.lastClassDay,
    required this.events,
    required this.documents,
    this.documentPages = const [],
  });

  final List<Map<String, dynamic>> documentPages;
  final String semesterTitle;
  final String timezone;
  final bool appliesToSelectedSemester;
  final DateTime semesterStartsOn;
  final DateTime lastClassDay;
  final List<AssistantAcademicCalendarEventContext> events;
  final List<AssistantAcademicCalendarDocumentContext> documents;

  Map<String, dynamic> toJson() => {
    'semester_title': semesterTitle,
    if (documentPages.isNotEmpty) 'document_pages': documentPages,
    'timezone': timezone,
    'applies_to_selected_semester': appliesToSelectedSemester,
    'semester_starts_on': _dateOnlyString(semesterStartsOn),
    'last_class_day': _dateOnlyString(lastClassDay),
    'events': events.map((event) => event.toJson()).toList(growable: false),
    'documents': documents
        .map((document) => document.toJson())
        .toList(growable: false),
  };
}

class AssistantExamTimetableEntryContext {
  const AssistantExamTimetableEntryContext({
    required this.courseCode,
    required this.courseName,
    required this.startsAt,
    required this.endsAt,
    required this.room,
    required this.seat,
    required this.remark,
  });

  final String courseCode;
  final String courseName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String room;
  final String seat;
  final String remark;

  Map<String, dynamic> toJson() => {
    'course_code': courseCode,
    'course_name': courseName,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'room': room,
    'seat': seat,
    'remark': remark,
  };
}

class AssistantExamTimetableContext {
  const AssistantExamTimetableContext({
    required this.semesterId,
    required this.semesterName,
    required this.availability,
    required this.entries,
  });

  final String semesterId;
  final String semesterName;
  final String availability;
  final List<AssistantExamTimetableEntryContext> entries;

  Map<String, dynamic> toJson() => {
    'semester_id': semesterId,
    'semester_name': semesterName,
    'availability': availability,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
  };
}

class AssistantMailSummaryContext {
  const AssistantMailSummaryContext({
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.receivedAt,
    required this.preview,
    this.uid,
    this.folder = '',
    this.mailboxUidValidity,
  });

  final int? uid;
  final String folder;
  final int? mailboxUidValidity;
  final String senderName;
  final String senderEmail;
  final String subject;
  final DateTime receivedAt;
  final String preview;

  Map<String, dynamic> toJson() => {
    if (uid != null) 'uid': uid,
    'folder': folder,
    if (mailboxUidValidity != null) 'mailbox_uid_validity': mailboxUidValidity,
    'sender_name': senderName,
    'sender_email': senderEmail,
    'subject': subject,
    'received_at': receivedAt.toUtc().toIso8601String(),
    'preview': preview,
  };
}

class AssistantMailAttachmentContext {
  const AssistantMailAttachmentContext({
    required this.partId,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  final String partId;
  final String name;
  final int size;
  final String mimeType;

  Map<String, dynamic> toJson() => {
    'part_id': partId,
    'name': name,
    'size': size,
    'mime_type': mimeType,
  };
}

class AssistantSelectedMailContext {
  const AssistantSelectedMailContext({
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.receivedAt,
    required this.bodyExcerpt,
    this.uid,
    this.folder = '',
    this.mailboxUidValidity,
    this.attachments = const [],
  });

  final int? uid;
  final String folder;
  final int? mailboxUidValidity;
  final String senderName;
  final String senderEmail;
  final String subject;
  final DateTime receivedAt;
  final String bodyExcerpt;
  final List<AssistantMailAttachmentContext> attachments;

  Map<String, dynamic> toJson() => {
    if (uid != null) 'uid': uid,
    'folder': folder,
    if (mailboxUidValidity != null) 'mailbox_uid_validity': mailboxUidValidity,
    'sender_name': senderName,
    'sender_email': senderEmail,
    'subject': subject,
    'received_at': receivedAt.toUtc().toIso8601String(),
    'body_excerpt': bodyExcerpt,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(growable: false),
  };
}

class AssistantMailMessageContext {
  const AssistantMailMessageContext({
    required this.uid,
    required this.folder,
    required this.mailboxUidValidity,
    required this.senderName,
    required this.senderEmail,
    required this.recipients,
    required this.cc,
    required this.subject,
    required this.receivedAt,
    required this.bodyText,
    required this.contentState,
    this.attachments = const [],
    this.bodyOffset = 0,
    this.totalBodyCharacters = 0,
    this.nextBodyOffset,
  });

  final int uid;
  final String folder;
  final int mailboxUidValidity;
  final String senderName;
  final String senderEmail;
  final String recipients;
  final String cc;
  final String subject;
  final DateTime? receivedAt;
  final String bodyText;
  final String contentState;
  final int bodyOffset;
  final int totalBodyCharacters;
  final int? nextBodyOffset;
  final List<AssistantMailAttachmentContext> attachments;

  String get stableIdentity => '$folder:$mailboxUidValidity:$uid';

  Map<String, dynamic> toJson({bool includePaging = true}) => {
    'uid': uid,
    'folder': folder,
    'mailbox_uid_validity': mailboxUidValidity,
    'sender_name': senderName,
    'sender_email': senderEmail,
    'recipients': recipients,
    'cc': cc,
    'subject': subject,
    if (receivedAt != null)
      'received_at': receivedAt!.toUtc().toIso8601String(),
    'body_text': bodyText,
    'content_state': contentState,
    if (includePaging) 'body_offset': bodyOffset,
    if (includePaging) 'total_body_characters': totalBodyCharacters,
    if (includePaging && nextBodyOffset != null)
      'next_body_offset': nextBodyOffset,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(growable: false),
  };
}

class AssistantMailToolResultContext {
  const AssistantMailToolResultContext({
    required this.resultKey,
    this.content,
    this.radarItems = const [],
    this.radarLookbackDays = 0,
    this.radarPendingCount = 0,
    this.attachmentPartId = '',
    this.attachmentName = '',
    required this.kind,
    required this.observedAt,
    required this.completeness,
    required this.messages,
    this.protocolVersion = 2,
    this.nextCursor = '',
    this.scanComplete = true,
    this.scannedCount = 0,
    this.matchedCount = 0,
  });

  final List<Map<String, Object?>> radarItems;
  final int radarLookbackDays;
  final int radarPendingCount;
  final AssistantContentPage? content;
  final String attachmentPartId;
  final String attachmentName;
  final String resultKey;
  final String kind;
  final DateTime observedAt;
  final String completeness;
  final List<AssistantMailMessageContext> messages;
  final int protocolVersion;
  final String nextCursor;
  final bool scanComplete;
  final int scannedCount;
  final int matchedCount;

  Map<String, dynamic> toJson() => {
    'result_key': resultKey,
    if (kind == 'mail_radar') 'radar_items': radarItems,
    if (kind == 'mail_radar') 'radar_lookback_days': radarLookbackDays,
    if (kind == 'mail_radar') 'radar_pending_count': radarPendingCount,
    if (content != null) 'content': content!.toJson(),
    if (attachmentPartId.isNotEmpty) 'attachment_part_id': attachmentPartId,
    if (attachmentName.isNotEmpty) 'attachment_name': attachmentName,
    'kind': kind,
    'observed_at': observedAt.toUtc().toIso8601String(),
    'completeness':
        protocolVersion < 2 && completeness == 'truncated' && messages.isEmpty
        ? 'unavailable'
        : completeness,
    if (protocolVersion >= 2) 'next_cursor': nextCursor,
    if (protocolVersion >= 2) 'scan_complete': scanComplete,
    if (protocolVersion >= 2) 'scanned_count': scannedCount,
    if (protocolVersion >= 2) 'matched_count': matchedCount,
    'messages': messages
        .map((message) => message.toJson(includePaging: protocolVersion >= 2))
        .toList(growable: false),
  };
}

class AssistantSchoolActivityContext {
  const AssistantSchoolActivityContext({
    required this.title,
    this.startsAt,
    this.endsAt,
    required this.location,
    required this.summary,
    required this.sourceUrl,
  });

  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String location;
  final String summary;
  final String sourceUrl;

  Map<String, dynamic> toJson() => {
    'title': title,
    if (startsAt != null) 'starts_at': startsAt!.toUtc().toIso8601String(),
    if (endsAt != null) 'ends_at': endsAt!.toUtc().toIso8601String(),
    'location': location,
    'summary': summary,
    'source_url': sourceUrl,
  };
}

class AssistantTaCourseContext {
  const AssistantTaCourseContext({
    required this.id,
    required this.title,
    required this.location,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    required this.repeatType,
    required this.entryRevision,
    required this.collectionRevision,
    this.weekStart,
    this.kind = '',
    this.courseKey = '',
  });

  final String kind;
  final String courseKey;
  final String id;
  final String title;
  final String location;
  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final String repeatType;
  final DateTime? weekStart;
  final int entryRevision;
  final int collectionRevision;

  Map<String, dynamic> toJson() => {
    if (kind.isNotEmpty) 'kind': kind,
    if (courseKey.isNotEmpty) 'course_key': courseKey,
    'id': id,
    'title': title,
    'location': location,
    'weekday': weekday,
    'start_minutes': startMinutes,
    'end_minutes': endMinutes,
    'repeat_type': repeatType,
    if (weekStart != null) 'week_start': weekStart!.toUtc().toIso8601String(),
    'entry_revision': entryRevision,
    'collection_revision': collectionRevision,
  };
}

class AssistantCurrentPageContext {
  const AssistantCurrentPageContext({
    required this.pageType,
    required this.title,
    this.selectedItemId = '',
    this.summary = '',
    this.sourcePage,
  });

  final String pageType;
  final String title;
  final String selectedItemId;
  final String summary;
  final AssistantCurrentPageContext? sourcePage;

  Map<String, dynamic> toJson({bool includeSource = true}) => {
    'page_type': pageType,
    'title': title,
    'selected_item_id': selectedItemId,
    'summary': summary,
    if (includeSource && sourcePage != null)
      'source_page': sourcePage!.toJson(includeSource: false),
  };
}

class AssistantCurrentLocationContext {
  const AssistantCurrentLocationContext({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.observedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime observedAt;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_meters': accuracyMeters,
    'observed_at': observedAt.toUtc().toIso8601String(),
  };
}

class AssistantAcademicProfileContext {
  const AssistantAcademicProfileContext({
    required this.programmeCode,
    required this.programmeName,
    required this.year,
  });

  final String programmeCode;
  final String programmeName;
  final String year;

  Map<String, dynamic> toJson() => {
    'programme_code': programmeCode,
    'programme_name': programmeName,
    'year': year,
  };
}

class AssistantContextPayload {
  const AssistantContextPayload({
    required this.sources,
    this.version = '3',
    this.mailRadarAvailable = false,
    this.academicProfile,
    this.courses = const [],
    this.term,
    this.termCourses = const [],
    this.ispaceCourseCatalog,
    this.ispaceActivity,
    this.ispaceQuizAttempt,
    this.ispaceToolResults = const [],
    this.deadlines = const [],
    this.schedule = const [],
    this.academicCalendar,
    this.examTimetable,
    this.mailSummaries = const [],
    this.selectedMail,
    this.mailToolResults = const [],
    this.schoolActivities = const [],
    this.taCourses = const [],
    this.taCourseCollectionRevision,
    this.fixedScheduleVersion = 0,
    this.fixedScheduleCourses = const [],
    this.currentPage,
    this.currentLocation,
  });

  final Set<AssistantContextSource> sources;
  final String version;
  final bool mailRadarAvailable;
  final AssistantAcademicProfileContext? academicProfile;
  final List<AssistantCourseContext> courses;
  final AssistantTermContext? term;
  final List<AssistantTermCourseContext> termCourses;
  final AssistantIspaceCourseCatalogContext? ispaceCourseCatalog;
  final AssistantIspaceActivityContext? ispaceActivity;
  final AssistantIspaceQuizAttemptContext? ispaceQuizAttempt;
  final List<AssistantIspaceToolResultContext> ispaceToolResults;
  final List<AssistantDeadlineContext> deadlines;
  final List<AssistantScheduleContext> schedule;
  final AssistantAcademicCalendarContext? academicCalendar;
  final AssistantExamTimetableContext? examTimetable;
  final List<AssistantMailSummaryContext> mailSummaries;
  final AssistantSelectedMailContext? selectedMail;
  final List<AssistantMailToolResultContext> mailToolResults;
  final List<AssistantSchoolActivityContext> schoolActivities;
  final List<AssistantTaCourseContext> taCourses;
  final int? taCourseCollectionRevision;
  final int fixedScheduleVersion;
  final List<Map<String, String>> fixedScheduleCourses;
  final AssistantCurrentPageContext? currentPage;
  final AssistantCurrentLocationContext? currentLocation;

  Map<String, dynamic> toJson() => {
    'version': version,
    if (version == '5' && mailRadarAvailable) 'mail_radar_available': true,
    'sources': sources
        .map((source) => source.wireValue)
        .toList(growable: false),
    if (academicProfile != null) 'academic_profile': academicProfile!.toJson(),
    'courses': courses.map((item) => item.toJson()).toList(growable: false),
    if (term != null) 'term': term!.toJson(),
    'term_courses': termCourses
        .map((item) => item.toJson())
        .toList(growable: false),
    if (ispaceCourseCatalog != null)
      'ispace_course_catalog': ispaceCourseCatalog!.toJson(),
    if (ispaceActivity != null) 'ispace_activity': ispaceActivity!.toJson(),
    if (ispaceQuizAttempt != null)
      'ispace_quiz_attempt': ispaceQuizAttempt!.toJson(),
    if (ispaceToolResults.isNotEmpty)
      'ispace_tool_results': ispaceToolResults
          .map((item) => item.toJson())
          .toList(growable: false),
    'deadlines': deadlines.map((item) => item.toJson()).toList(growable: false),
    'schedule': schedule.map((item) => item.toJson()).toList(growable: false),
    if (academicCalendar != null)
      'academic_calendar': academicCalendar!.toJson(),
    if (examTimetable != null) 'exam_timetable': examTimetable!.toJson(),
    'mail_summaries': mailSummaries
        .map((item) => item.toJson())
        .toList(growable: false),
    if (selectedMail != null) 'selected_mail': selectedMail!.toJson(),
    if (mailToolResults.isNotEmpty)
      'mail_tool_results': mailToolResults
          .map((result) => result.toJson())
          .toList(growable: false),
    'school_activities': schoolActivities
        .map((item) => item.toJson())
        .toList(growable: false),
    if (fixedScheduleVersion == 2) 'fixed_schedule_version': 2,
    if (fixedScheduleVersion == 2)
      'fixed_schedule_courses': fixedScheduleCourses,
    'ta_courses': taCourses
        .map((item) => item.toJson())
        .toList(growable: false),
    if (taCourseCollectionRevision != null)
      'ta_course_collection_revision': taCourseCollectionRevision,
    if (currentPage != null) 'current_page': currentPage!.toJson(),
    if (currentLocation != null) 'current_location': currentLocation!.toJson(),
  };
}

String _dateOnlyString(DateTime value) {
  final date = DateTime(value.year, value.month, value.day);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _object(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  throw const FormatException('小U服务响应格式无效。');
}

List<Map<String, dynamic>> _objectList(Object? value) {
  if (value is! List) {
    throw const FormatException('小U服务响应列表格式无效。');
  }
  return value.map(_object).toList(growable: false);
}

Set<String> _stringSet(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('小U服务能力列表格式无效。');
  }
  return value.cast<String>().toSet();
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    throw const FormatException('小U字符串列表格式无效。');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw const FormatException('小U字符串列表格式无效。');
    }
    result.add(item.trim());
  }
  if (result.length != result.toSet().length) {
    throw const FormatException('小U字符串列表包含重复项。');
  }
  return List.unmodifiable(result);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('小U服务响应缺少必要文本字段。');
  }
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return '';
  }
  if (value is! String) {
    throw const FormatException('小U服务响应文本字段格式无效。');
  }
  return value;
}

int? _optionalPositiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! int || value <= 0) {
    throw const FormatException('小U服务响应数字字段格式无效。');
  }
  return value;
}

int? _optionalNonNegativeInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0) {
    throw const FormatException('小U服务响应数字字段格式无效。');
  }
  return value;
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value == '') {
    return null;
  }
  if (value is! String) {
    throw const FormatException('小U服务响应时间字段格式无效。');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('小U服务响应时间字段格式无效。');
  }
  return parsed;
}

DateTime? _optionalTimezoneAwareDateTime(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value == null || value == '') {
    return null;
  }
  if (value is! String || !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('小U服务响应时间字段缺少时区。');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('小U服务响应时间字段格式无效。');
  }
  return parsed;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw const FormatException('小U服务响应布尔字段格式无效。');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw const FormatException('小U服务响应数字字段格式无效。');
  }
  return value;
}

int _boundedCapabilityInt(
  Map<String, dynamic> json,
  String key, {
  required int fallback,
  required int minimum,
  required int maximum,
}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('小U服务能力数字字段格式无效。');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw const FormatException('小U服务响应时间字段格式无效。');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('小U服务响应时间字段格式无效。');
  }
  return parsed;
}
