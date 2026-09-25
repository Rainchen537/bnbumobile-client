import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assistant_models.dart';
import 'secure_storage_options.dart';

enum AssistantMessageFeedback {
  up('up'),
  down('down');

  const AssistantMessageFeedback(this.wireValue);

  final String wireValue;

  static AssistantMessageFeedback? parseOptional(Object? value) {
    if (value == null || value == '') {
      return null;
    }
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw FormatException('不支持的小U回复反馈：$value'),
    );
  }
}

enum AssistantConversationKind {
  general('general'),
  study('study');

  const AssistantConversationKind(this.wireValue);

  final String wireValue;

  static AssistantConversationKind parse(Object? value) {
    if (value == null || value == '') return general;
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw FormatException('不支持的小U会话类型：$value'),
    );
  }
}

class AssistantStudyDocument {
  const AssistantStudyDocument({
    required this.key,
    required this.title,
    required this.sourceUrl,
  });

  final String key;
  final String title;
  final String sourceUrl;

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'source_url': sourceUrl,
  };

  factory AssistantStudyDocument.fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final title = json['title'];
    final sourceUrl = json['source_url'];
    if (key is! String ||
        key.isEmpty ||
        key.length > 128 ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 180 ||
        sourceUrl is! String ||
        sourceUrl.trim().isEmpty ||
        sourceUrl.length > 2048) {
      throw const FormatException('小U学业文件格式无效。');
    }
    return AssistantStudyDocument(
      key: key,
      title: title.trim(),
      sourceUrl: sourceUrl.trim(),
    );
  }
}

enum AssistantStudyEntryType {
  question('question'),
  organization('organization');

  const AssistantStudyEntryType(this.wireValue);
  final String wireValue;

  static AssistantStudyEntryType parse(Object? value) => values.firstWhere(
    (candidate) => candidate.wireValue == value,
    orElse: () => throw FormatException('不支持的学业记录类型：$value'),
  );
}

class AssistantStudyMessageContext {
  const AssistantStudyMessageContext({
    required this.type,
    required this.pages,
    required this.scope,
  });

  final AssistantStudyEntryType type;
  final List<int> pages;
  final String scope;

  Map<String, dynamic> toJson() => {
    'type': type.wireValue,
    'pages': pages,
    'scope': scope,
  };

  factory AssistantStudyMessageContext.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'];
    final scope = json['scope'];
    if (rawPages is! List ||
        rawPages.isEmpty ||
        rawPages.length > 120 ||
        scope is! String ||
        scope.isEmpty ||
        scope.length > 32) {
      throw const FormatException('小U学业页范围格式无效。');
    }
    final pages = rawPages.whereType<int>().toSet().toList()..sort();
    if (pages.length != rawPages.length || pages.any((page) => page < 1)) {
      throw const FormatException('小U学业页范围格式无效。');
    }
    return AssistantStudyMessageContext(
      type: AssistantStudyEntryType.parse(json['type']),
      pages: List.unmodifiable(pages),
      scope: scope,
    );
  }
}

class AssistantActivity {
  const AssistantActivity({
    required this.label,
    this.completed = true,
    this.failed = false,
  });

  final String label;
  final bool completed;
  final bool failed;

  AssistantActivity copyWith({bool? completed, bool? failed}) =>
      AssistantActivity(
        label: label,
        completed: completed ?? this.completed,
        failed: failed ?? this.failed,
      );

  Map<String, dynamic> toJson() => {
    'label': label,
    if (!completed) 'completed': false,
    if (failed) 'failed': true,
  };

  factory AssistantActivity.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    if (label is! String || label.trim().isEmpty || label.length > 160) {
      throw const FormatException('小U调用过程格式无效。');
    }
    final normalizedLabel = label.trim();
    final failed =
        json['failed'] == true || normalizedLabel == '网络连接暂未恢复，已保留这轮问题';
    return AssistantActivity(
      label: normalizedLabel,
      completed: failed || json['completed'] != false,
      failed: failed,
    );
  }
}

class AssistantStoredMessage {
  const AssistantStoredMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.actions = const [],
    this.suggestions = const [],
    this.memorySuggestions = const [],
    this.isError = false,
    this.compactError = false,
    this.retryMessage,
    this.retryAttachments = const [],
    this.runtimeAttachments = const [],
    this.attachmentReferences = const [],
    this.mailReferences = const [],
    this.feedback,
    this.activities = const [],
    this.studyContext,
    this.receiptKey = '',
  });

  final String receiptKey;
  final String role;
  final String content;
  final DateTime createdAt;
  final List<AssistantAction> actions;
  final List<AssistantSuggestion> suggestions;
  final List<AssistantMemorySuggestion> memorySuggestions;
  final bool isError;
  final bool compactError;
  final String? retryMessage;
  final List<AssistantInputAttachment> retryAttachments;

  /// Current-process attachment values used only for transient thumbnails.
  /// This list is never serialized to local or remote conversation history.
  final List<AssistantInputAttachment> runtimeAttachments;

  /// Bounded display metadata for ordinary attachments. No bytes, paths,
  /// resource IDs or source URIs are retained.
  final List<AssistantAttachmentReference> attachmentReferences;

  /// Stable received-mail identities or explicit compose drafts attached to a
  /// user turn. These are encrypted with the conversation history and never
  /// serialized as ordinary provider files.
  final List<AssistantMailReference> mailReferences;
  final AssistantMessageFeedback? feedback;
  final List<AssistantActivity> activities;
  final AssistantStudyMessageContext? studyContext;

  bool get isUser => role == 'user';
  bool get canRetry =>
      isError && retryMessage != null && retryMessage!.trim().isNotEmpty;

  AssistantStoredMessage copyWith({
    String? content,
    List<AssistantAction>? actions,
    List<AssistantSuggestion>? suggestions,
    List<AssistantMemorySuggestion>? memorySuggestions,
    bool? isError,
    bool? compactError,
    String? retryMessage,
    List<AssistantInputAttachment>? retryAttachments,
    List<AssistantInputAttachment>? runtimeAttachments,
    List<AssistantAttachmentReference>? attachmentReferences,
    List<AssistantMailReference>? mailReferences,
    AssistantMessageFeedback? feedback,
    List<AssistantActivity>? activities,
    bool clearFeedback = false,
    AssistantStudyMessageContext? studyContext,
  }) {
    return AssistantStoredMessage(
      receiptKey: receiptKey,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      actions: actions ?? this.actions,
      suggestions: suggestions ?? this.suggestions,
      memorySuggestions: memorySuggestions ?? this.memorySuggestions,
      isError: isError ?? this.isError,
      compactError: compactError ?? this.compactError,
      retryMessage: retryMessage ?? this.retryMessage,
      retryAttachments: retryAttachments ?? this.retryAttachments,
      runtimeAttachments: runtimeAttachments ?? this.runtimeAttachments,
      attachmentReferences: attachmentReferences ?? this.attachmentReferences,
      mailReferences: mailReferences ?? this.mailReferences,
      feedback: clearFeedback ? null : feedback ?? this.feedback,
      activities: activities ?? this.activities,
      studyContext: studyContext ?? this.studyContext,
    );
  }

  Map<String, dynamic> toJson() => {
    if (receiptKey.isNotEmpty) 'receipt_key': receiptKey,
    'role': role,
    'content': content,
    'created_at': createdAt.toUtc().toIso8601String(),
    'actions': actions.map((action) => action.toJson()).toList(growable: false),
    'suggestions': suggestions
        .map((suggestion) => suggestion.toJson())
        .toList(growable: false),
    if (memorySuggestions.isNotEmpty)
      'memory_suggestions': memorySuggestions
          .map((suggestion) => suggestion.toJson())
          .toList(growable: false),
    if (isError) 'is_error': true,
    if (compactError) 'compact_error': true,
    if (isError && retryMessage != null) 'retry_message': retryMessage,
    if (attachmentReferences.isNotEmpty)
      'attachment_references': attachmentReferences
          .map((reference) => reference.toJson())
          .toList(growable: false),
    if (mailReferences.isNotEmpty)
      'mail_references': mailReferences
          .map((reference) => reference.toJson())
          .toList(growable: false),
    if (feedback != null) 'feedback': feedback!.wireValue,
    if (activities.isNotEmpty)
      'activities': activities
          .map((activity) => activity.toJson())
          .toList(growable: false),
    if (studyContext != null) 'study_context': studyContext!.toJson(),
  };

  factory AssistantStoredMessage.fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    final content = json['content'];
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    if ((role != 'user' && role != 'assistant') ||
        content is! String ||
        createdAt == null) {
      throw const FormatException('小U本地消息格式无效。');
    }
    final rawActions = json['actions'];
    final actions = rawActions is List
        ? rawActions
              .whereType<Map>()
              .map(
                (item) =>
                    AssistantAction.fromJson(item.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <AssistantAction>[];
    final rawSuggestions = json['suggestions'];
    final suggestions = rawSuggestions is List
        ? rawSuggestions
              .whereType<Map>()
              .map(
                (item) =>
                    AssistantSuggestion.fromJson(item.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <AssistantSuggestion>[];
    final rawMemorySuggestions = json['memory_suggestions'];
    final memorySuggestions = rawMemorySuggestions is List
        ? rawMemorySuggestions
              .whereType<Map>()
              .map(
                (item) => AssistantMemorySuggestion.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .take(3)
              .toList(growable: false)
        : const <AssistantMemorySuggestion>[];
    final isError = json['is_error'] == true;
    final retryMessage = json['retry_message'];
    final rawAttachmentReferences = json['attachment_references'];
    final attachmentReferences = rawAttachmentReferences is List
        ? rawAttachmentReferences
              .whereType<Map>()
              .map(
                (item) => AssistantAttachmentReference.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .take(3)
              .toList(growable: false)
        : const <AssistantAttachmentReference>[];
    final rawMailReferences = json['mail_references'];
    final mailReferences = rawMailReferences is List
        ? rawMailReferences
              .whereType<Map>()
              .map(
                (item) => AssistantMailReference.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .take(3)
              .toList(growable: false)
        : const <AssistantMailReference>[];
    final feedback = AssistantMessageFeedback.parseOptional(json['feedback']);
    final rawActivities = json['activities'];
    final activities = rawActivities is List
        ? rawActivities
              .whereType<Map>()
              .map(
                (item) =>
                    AssistantActivity.fromJson(item.cast<String, dynamic>()),
              )
              .take(32)
              .toList(growable: false)
        : const <AssistantActivity>[];
    final compactError =
        json['compact_error'] == true ||
        (isError &&
            activities.any(
              (activity) =>
                  activity.failed || activity.label == '网络连接暂未恢复，已保留这轮问题',
            ));
    final rawStudyContext = json['study_context'];
    final studyContext = rawStudyContext is Map
        ? AssistantStudyMessageContext.fromJson(
            rawStudyContext.cast<String, dynamic>(),
          )
        : null;
    final normalizedContent = _migrateLegacyMailAttachmentSuffix(
      content,
      role: role,
      mailReferences: mailReferences,
    );
    final suggestionLabels = suggestions
        .where((item) => !item.isOther)
        .map((item) => item.label.toLowerCase())
        .toSet();
    final suggestionMessages = suggestions
        .where((item) => !item.isOther)
        .map((item) => item.message.toLowerCase())
        .toSet();
    if (suggestions.length > 5 ||
        (normalizedContent.trim().isEmpty &&
            attachmentReferences.isEmpty &&
            mailReferences.isEmpty) ||
        (role == 'user' && suggestions.isNotEmpty) ||
        (role == 'user' && memorySuggestions.isNotEmpty) ||
        (role == 'user' && isError) ||
        (compactError && !isError) ||
        (role == 'user' && feedback != null) ||
        (isError && feedback != null) ||
        (role == 'user' && activities.isNotEmpty) ||
        (role != 'user' && attachmentReferences.isNotEmpty) ||
        (role != 'user' && mailReferences.isNotEmpty) ||
        (isError &&
            (actions.isNotEmpty ||
                suggestions.isNotEmpty ||
                memorySuggestions.isNotEmpty)) ||
        (retryMessage != null &&
            (retryMessage is! String ||
                retryMessage.trim().isEmpty ||
                retryMessage.length > 4000)) ||
        (suggestions.isNotEmpty &&
            (suggestions.length < 2 ||
                !suggestions.last.isOther ||
                suggestions
                    .take(suggestions.length - 1)
                    .any((item) => item.isOther) ||
                suggestionLabels.length != suggestions.length - 1 ||
                suggestionMessages.length != suggestions.length - 1))) {
      throw const FormatException('小U本地建议选项格式无效。');
    }
    return AssistantStoredMessage(
      role: role,
      content: normalizedContent,
      createdAt: createdAt,
      receiptKey: json['receipt_key'] as String? ?? '',
      actions: actions,
      suggestions: suggestions,
      memorySuggestions: List.unmodifiable(memorySuggestions),
      isError: isError,
      compactError: compactError,
      retryMessage: retryMessage is String ? retryMessage : null,
      attachmentReferences: List.unmodifiable(attachmentReferences),
      mailReferences: List.unmodifiable(mailReferences),
      feedback: feedback,
      activities: List.unmodifiable(activities),
      studyContext: studyContext,
    );
  }
}

String _migrateLegacyMailAttachmentSuffix(
  String content, {
  required String role,
  required List<AssistantMailReference> mailReferences,
}) {
  if (role != 'user' || mailReferences.isEmpty) return content;
  final generatedSuffix =
      '\n\n附件：${mailReferences.map((item) => item.displayName).join('、')}';
  if (!content.endsWith(generatedSuffix)) return content;
  return content.substring(0, content.length - generatedSuffix.length);
}

const _assistantHistoryMaxConversations = 36;
const _assistantHistoryMaxMessagesPerConversation = 40;
const _assistantHistoryMaxContentLength = 12000;
const _assistantHistoryTargetBytes = 480 * 1024;

/// Produces the exact bounded shape used by local encryption and remote sync.
///
/// A malformed legacy message is omitted without preventing unrelated history
/// from syncing. Runtime attachment bytes and paths are deliberately discarded.
List<AssistantConversation> normalizeAssistantHistorySnapshot(
  Iterable<AssistantConversation> conversations,
) {
  final bounded =
      conversations
          .map(_normalizeAssistantHistoryConversation)
          .whereType<AssistantConversation>()
          .toList(growable: true)
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  if (bounded.length > _assistantHistoryMaxConversations) {
    bounded.removeRange(_assistantHistoryMaxConversations, bounded.length);
  }

  int payloadBytes() => utf8
      .encode(
        jsonEncode(
          bounded
              .map((conversation) => conversation.toJson())
              .toList(growable: false),
        ),
      )
      .length;

  while (bounded.isNotEmpty && payloadBytes() > _assistantHistoryTargetBytes) {
    var changed = false;
    for (var index = bounded.length - 1; index >= 0; index--) {
      final conversation = bounded[index];
      if (conversation.messages.isNotEmpty) {
        bounded[index] = conversation.copyWith(
          messages: conversation.messages.sublist(1),
        );
        changed = true;
        break;
      }
    }
    if (!changed) bounded.removeLast();
  }
  return List.unmodifiable(bounded);
}

AssistantConversation? _normalizeAssistantHistoryConversation(
  AssistantConversation conversation,
) {
  final id =
      conversation.id.isNotEmpty &&
          conversation.id.length <= 128 &&
          RegExp(r'^[0-9A-Za-z._-]+$').hasMatch(conversation.id)
      ? conversation.id
      : 'legacy-${sha256.convert(utf8.encode(conversation.id)).toString().substring(0, 32)}';
  final boundedTitle = _limitAssistantHistoryText(conversation.title, 60);
  final title = boundedTitle.isEmpty ? '旧对话' : boundedTitle;
  if ((conversation.kind == AssistantConversationKind.study) !=
      (conversation.studyDocument != null)) {
    return null;
  }
  final studyDocument = conversation.studyDocument;
  if (studyDocument != null) {
    try {
      AssistantStudyDocument.fromJson(studyDocument.toJson());
    } on FormatException {
      return null;
    }
  }
  final messages = conversation.messages
      .skip(
        conversation.messages.length >
                _assistantHistoryMaxMessagesPerConversation
            ? conversation.messages.length -
                  _assistantHistoryMaxMessagesPerConversation
            : 0,
      )
      .map(
        (message) =>
            _normalizeAssistantHistoryMessage(message, kind: conversation.kind),
      )
      .whereType<AssistantStoredMessage>()
      .toList(growable: false);
  final branchGroupId = conversation.branchGroupId;
  final validBranchGroupId =
      branchGroupId != null &&
          branchGroupId.isNotEmpty &&
          branchGroupId.length <= 128 &&
          RegExp(r'^[0-9A-Za-z._-]+$').hasMatch(branchGroupId)
      ? branchGroupId
      : null;
  final branchIndex = conversation.branchedFromMessageIndex;
  return AssistantConversation(
    id: id,
    title: title,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt.isBefore(conversation.createdAt)
        ? conversation.createdAt
        : conversation.updatedAt,
    messages: List.unmodifiable(messages),
    branchGroupId: validBranchGroupId,
    branchedFromMessageIndex:
        branchIndex != null && branchIndex >= 0 && branchIndex <= 39
        ? branchIndex
        : null,
    kind: conversation.kind,
    studyDocument: studyDocument,
  );
}

AssistantStoredMessage? _normalizeAssistantHistoryMessage(
  AssistantStoredMessage message, {
  required AssistantConversationKind kind,
}) {
  if (message.role != 'user' && message.role != 'assistant') return null;
  if ((kind == AssistantConversationKind.general &&
          message.studyContext != null) ||
      (kind == AssistantConversationKind.study &&
          message.studyContext == null)) {
    return null;
  }
  final context = message.studyContext;
  final normalizedContext =
      context == null ||
          const {
            'current_page',
            'selected_pages',
            'whole_document',
          }.contains(context.scope)
      ? context
      : AssistantStudyMessageContext(
          type: context.type,
          pages: context.pages,
          scope: context.pages.length == 1 ? 'current_page' : 'selected_pages',
        );
  final attachmentReferences = message.role == 'user'
      ? message.attachmentReferences
            .map(_normalizeAssistantAttachmentReference)
            .whereType<AssistantAttachmentReference>()
            .take(3)
            .toList(growable: false)
      : const <AssistantAttachmentReference>[];
  final remainingReferences = 3 - attachmentReferences.length;
  final mailReferences = message.role == 'user'
      ? message.mailReferences
            .map(_normalizeAssistantMailReference)
            .whereType<AssistantMailReference>()
            .take(remainingReferences)
            .toList(growable: false)
      : const <AssistantMailReference>[];
  final content = _limitAssistantHistoryText(
    message.content,
    _assistantHistoryMaxContentLength,
  );
  if (content.trim().isEmpty &&
      attachmentReferences.isEmpty &&
      mailReferences.isEmpty) {
    return null;
  }
  return AssistantStoredMessage(
    role: message.role,
    content: content,
    createdAt: message.createdAt,
    receiptKey: message.receiptKey.length <= 128 ? message.receiptKey : '',
    actions: message.role == 'assistant'
        ? message.actions.take(8).toList(growable: false)
        : const [],
    suggestions: message.role == 'assistant'
        ? _boundedAssistantSuggestions(message)
        : const [],
    memorySuggestions: message.role == 'assistant'
        ? message.memorySuggestions.take(3).toList(growable: false)
        : const [],
    isError: message.role == 'assistant' && message.isError,
    compactError:
        message.role == 'assistant' && message.isError && message.compactError,
    retryMessage: message.role == 'assistant' && message.isError
        ? message.retryMessage == null
              ? null
              : _limitAssistantHistoryText(message.retryMessage!, 4000)
        : null,
    attachmentReferences: attachmentReferences,
    mailReferences: mailReferences,
    feedback: message.role == 'assistant' && !message.isError
        ? message.feedback
        : null,
    activities: message.role == 'assistant'
        ? message.activities
              .take(32)
              .map((activity) => activity.copyWith(completed: true))
              .toList(growable: false)
        : const [],
    studyContext: normalizedContext,
  );
}

AssistantAttachmentReference? _normalizeAssistantAttachmentReference(
  AssistantAttachmentReference reference,
) {
  try {
    return AssistantAttachmentReference.fromJson(reference.toJson());
  } on FormatException {
    return null;
  }
}

AssistantMailReference? _normalizeAssistantMailReference(
  AssistantMailReference reference,
) {
  try {
    return AssistantMailReference.fromJson(reference.toJson());
  } on FormatException {
    return null;
  }
}

List<AssistantSuggestion> _boundedAssistantSuggestions(
  AssistantStoredMessage message,
) {
  if (message.suggestions.length < 2 ||
      message.suggestions.length > 5 ||
      !message.suggestions.last.isOther ||
      message.suggestions
          .take(message.suggestions.length - 1)
          .any((item) => item.isOther)) {
    return const [];
  }
  final labels = message.suggestions
      .take(message.suggestions.length - 1)
      .map((item) => item.label.toLowerCase())
      .toSet();
  final messages = message.suggestions
      .take(message.suggestions.length - 1)
      .map((item) => item.message.toLowerCase())
      .toSet();
  return labels.length == message.suggestions.length - 1 &&
          messages.length == message.suggestions.length - 1
      ? message.suggestions.take(5).toList(growable: false)
      : const [];
}

String _limitAssistantHistoryText(String value, int maxLength) =>
    value.length <= maxLength ? value : value.substring(0, maxLength);

class AssistantConversation {
  const AssistantConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.branchGroupId,
    this.branchedFromMessageIndex,
    this.kind = AssistantConversationKind.general,
    this.studyDocument,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AssistantStoredMessage> messages;
  final String? branchGroupId;
  final int? branchedFromMessageIndex;
  final AssistantConversationKind kind;
  final AssistantStudyDocument? studyDocument;

  String get effectiveBranchGroupId => branchGroupId ?? id;

  AssistantConversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<AssistantStoredMessage>? messages,
    String? branchGroupId,
    int? branchedFromMessageIndex,
    AssistantConversationKind? kind,
    AssistantStudyDocument? studyDocument,
  }) {
    return AssistantConversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      branchGroupId: branchGroupId ?? this.branchGroupId,
      branchedFromMessageIndex:
          branchedFromMessageIndex ?? this.branchedFromMessageIndex,
      kind: kind ?? this.kind,
      studyDocument: studyDocument ?? this.studyDocument,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'messages': messages
        .map((message) => message.toJson())
        .toList(growable: false),
    if (branchGroupId != null) 'branch_group_id': branchGroupId,
    if (branchedFromMessageIndex != null)
      'branched_from_message_index': branchedFromMessageIndex,
    if (kind != AssistantConversationKind.general) 'kind': kind.wireValue,
    if (studyDocument != null) 'study_document': studyDocument!.toJson(),
  };

  factory AssistantConversation.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updated_at'] as String? ?? '');
    final rawMessages = json['messages'];
    final branchGroupId = json['branch_group_id'];
    final branchedFromMessageIndex = json['branched_from_message_index'];
    final kind = AssistantConversationKind.parse(json['kind']);
    final rawStudyDocument = json['study_document'];
    final studyDocument = rawStudyDocument is Map
        ? AssistantStudyDocument.fromJson(
            rawStudyDocument.cast<String, dynamic>(),
          )
        : null;
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        createdAt == null ||
        updatedAt == null ||
        rawMessages is! List) {
      throw const FormatException('小U本地会话格式无效。');
    }
    if ((branchGroupId != null &&
            (branchGroupId is! String || branchGroupId.isEmpty)) ||
        (branchedFromMessageIndex != null &&
            (branchedFromMessageIndex is! int ||
                branchedFromMessageIndex < 0)) ||
        (kind == AssistantConversationKind.study && studyDocument == null) ||
        (kind == AssistantConversationKind.general && studyDocument != null)) {
      throw const FormatException('小U本地分支格式无效。');
    }
    final messages = <AssistantStoredMessage>[];
    for (final rawMessage in rawMessages.whereType<Map>()) {
      try {
        messages.add(
          AssistantStoredMessage.fromJson(rawMessage.cast<String, dynamic>()),
        );
      } on FormatException {
        // Keep the rest of a locally stored conversation readable.
      }
    }
    if ((kind == AssistantConversationKind.general &&
            messages.any((message) => message.studyContext != null)) ||
        (kind == AssistantConversationKind.study &&
            messages.any((message) => message.studyContext == null))) {
      throw const FormatException('小U学业会话消息格式无效。');
    }
    return AssistantConversation(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      messages: List.unmodifiable(messages),
      branchGroupId: branchGroupId as String?,
      branchedFromMessageIndex: branchedFromMessageIndex as int?,
      kind: kind,
      studyDocument: studyDocument,
    );
  }
}

abstract interface class AssistantHistoryStore {
  Future<List<AssistantConversation>> load(String username);

  Future<void> save(String username, List<AssistantConversation> conversations);
}

abstract interface class AssistantThinkingModeStore {
  Future<AssistantThinkingMode> load(String username);

  Future<void> save(String username, AssistantThinkingMode mode);
}

class SharedPreferencesAssistantThinkingModeStore
    implements AssistantThinkingModeStore {
  SharedPreferencesAssistantThinkingModeStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;

  @override
  Future<AssistantThinkingMode> load(String username) async {
    final preferences = await _preferencesLoader();
    final stored = preferences.getString(_key(username));
    if (stored == null || stored.isEmpty) {
      return AssistantThinkingMode.low;
    }
    try {
      final mode = AssistantThinkingMode.parse(stored);
      // Medium existed in the previous three-choice UI. Keep the enum for
      // wire compatibility but migrate the persisted user preference to the
      // conservative low mode before the new two-choice control is shown.
      if (mode == AssistantThinkingMode.medium) {
        await save(username, AssistantThinkingMode.low);
        return AssistantThinkingMode.low;
      }
      return mode;
    } on FormatException {
      return AssistantThinkingMode.low;
    }
  }

  @override
  Future<void> save(String username, AssistantThinkingMode mode) async {
    final preferences = await _preferencesLoader();
    if (!await preferences.setString(_key(username), mode.wireValue)) {
      throw const AssistantHistoryException('无法保存小U思考强度。');
    }
  }

  String _key(String username) {
    final normalized = username.trim().toLowerCase();
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return 'bnbu.ai_assistant.thinking_mode.v1.$digest';
  }
}

class SharedPreferencesAssistantHistoryStore implements AssistantHistoryStore {
  SharedPreferencesAssistantHistoryStore({
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<SecretKey> Function()? key,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _key = key ?? _deviceKey;

  static const _secureKeyName = 'bnbu.ai-assistant-history.key.v1';
  static const _encryptedVersion = 'v2';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: macOsSecureStorageOptions,
  );
  static Future<SecretKey>? _keyFuture;

  final Future<SharedPreferences> Function() _preferencesLoader;
  final Future<SecretKey> Function() _key;
  final Cipher _cipher = AesGcm.with256bits();

  static Future<SecretKey> _deviceKey() => _keyFuture ??= (() async {
    try {
      final encoded = await _storage.read(key: _secureKeyName);
      if (encoded != null) {
        final bytes = base64Decode(encoded);
        if (bytes.length != 32) {
          throw const FormatException('Invalid assistant history key');
        }
        return SecretKey(bytes);
      }
      final key = await AesGcm.with256bits().newSecretKey();
      await _storage.write(
        key: _secureKeyName,
        value: base64Encode(await key.extractBytes()),
      );
      return key;
    } catch (_) {
      _keyFuture = null;
      rethrow;
    }
  })();

  @override
  Future<List<AssistantConversation>> load(String username) async {
    final preferences = await _preferencesLoader();
    final encryptedKey = _encryptedKey(username);
    final encrypted = preferences.getString(encryptedKey);
    if (encrypted != null) {
      return _decodeEncrypted(encryptedKey, encrypted);
    }

    final legacyKey = _legacyKey(username);
    final legacy = preferences.getString(legacyKey);
    if (legacy == null || legacy.isEmpty) {
      return const [];
    }

    final conversations = _decodeConversations(legacy);
    if (conversations.isEmpty && !_isEmptyHistory(legacy)) {
      return const [];
    }
    try {
      await _writeEncrypted(preferences, encryptedKey, legacy);
      if (!await preferences.remove(legacyKey)) {
        throw const AssistantHistoryException('无法清理未加密的小U本地历史。');
      }
      return conversations;
    } catch (_) {
      // Never restore a plaintext copy into a live session when the keychain
      // or encrypted preferences are unavailable. A later launch can retry
      // the migration while the original record remains untouched.
      return const [];
    }
  }

  Future<List<AssistantConversation>> _decodeEncrypted(
    String encryptedKey,
    String encoded,
  ) async {
    try {
      final bytes = await _cipher.decrypt(
        SecretBox.fromConcatenation(
          base64Decode(encoded),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: await _key(),
        aad: utf8.encode(encryptedKey),
      );
      return _decodeConversations(utf8.decode(bytes));
    } catch (_) {
      // A corrupt ciphertext or unavailable key is a cache miss. In
      // particular, do not fall back to a previous plaintext v1 value.
      return const [];
    }
  }

  @override
  Future<void> save(
    String username,
    List<AssistantConversation> conversations,
  ) async {
    final bounded = normalizeAssistantHistorySnapshot(conversations);
    final encoded = jsonEncode(
      bounded
          .map((conversation) => conversation.toJson())
          .toList(growable: false),
    );
    final preferences = await _preferencesLoader();
    final encryptedKey = _encryptedKey(username);
    try {
      await _writeEncrypted(preferences, encryptedKey, encoded);
      final legacyKey = _legacyKey(username);
      if (preferences.containsKey(legacyKey) &&
          !await preferences.remove(legacyKey)) {
        throw const AssistantHistoryException('无法清理未加密的小U本地历史。');
      }
    } on AssistantHistoryException {
      rethrow;
    } catch (_) {
      throw const AssistantHistoryException('无法保存加密的小U本地历史。');
    }
  }

  Future<void> _writeEncrypted(
    SharedPreferences preferences,
    String encryptedKey,
    String encoded,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(encoded),
      secretKey: await _key(),
      aad: utf8.encode(encryptedKey),
    );
    if (!await preferences.setString(
      encryptedKey,
      base64Encode(box.concatenation()),
    )) {
      throw const AssistantHistoryException('无法保存加密的小U本地历史。');
    }
  }

  List<AssistantConversation> _decodeConversations(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return const [];
      }
      final conversations = <AssistantConversation>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          conversations.add(
            AssistantConversation.fromJson(item.cast<String, dynamic>()),
          );
        } on FormatException {
          // Keep the rest of a locally stored history readable.
        }
      }
      conversations.sort(
        (left, right) => right.updatedAt.compareTo(left.updatedAt),
      );
      return conversations
          .take(_assistantHistoryMaxConversations)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  bool _isEmptyHistory(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      return decoded is List && decoded.isEmpty;
    } catch (_) {
      return false;
    }
  }

  String _accountDigest(String username) {
    final normalized = username.trim().toLowerCase();
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  String _encryptedKey(String username) =>
      'bnbu.ai_assistant.history.$_encryptedVersion.${_accountDigest(username)}';

  String _legacyKey(String username) =>
      'bnbu.ai_assistant.history.v1.${_accountDigest(username)}';
}

class AssistantHistoryException implements Exception {
  const AssistantHistoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
