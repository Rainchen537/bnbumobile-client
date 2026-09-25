import 'assistant_history_store.dart';

String studyConversationDisplayTitle(AssistantConversation conversation) {
  for (final message in conversation.messages) {
    if (!message.isUser ||
        message.studyContext?.type != AssistantStudyEntryType.question) {
      continue;
    }
    final normalized = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) continue;
    return normalized.length <= 34
        ? normalized
        : '${normalized.substring(0, 34)}…';
  }
  return conversation.studyDocument?.title ?? conversation.title;
}

String studyRelativeTime(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(value);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  if (difference.inDays < 30) return '${difference.inDays ~/ 7} 周前';
  if (difference.inDays < 365) return '${difference.inDays ~/ 30} 个月前';
  return '${difference.inDays ~/ 365} 年前';
}

List<AssistantConversation> studyQuestionConversationsForDocument(
  Iterable<AssistantConversation> conversations,
  String documentKey,
) {
  final result =
      conversations
          .where(
            (conversation) =>
                conversation.kind == AssistantConversationKind.study &&
                conversation.studyDocument?.key == documentKey &&
                conversation.messages.any(
                  (message) =>
                      message.studyContext?.type ==
                      AssistantStudyEntryType.question,
                ),
          )
          .toList(growable: false)
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return List.unmodifiable(result);
}

List<AssistantConversation> recentStudyDocuments(
  Iterable<AssistantConversation> conversations, {
  int limit = 3,
}) {
  final latestByDocument = <String, AssistantConversation>{};
  final sorted = conversations.toList(growable: false)
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  for (final conversation in sorted) {
    final key = conversation.studyDocument?.key;
    if (key == null || latestByDocument.containsKey(key)) continue;
    latestByDocument[key] = conversation;
    if (latestByDocument.length >= limit) break;
  }
  return List.unmodifiable(latestByDocument.values);
}
