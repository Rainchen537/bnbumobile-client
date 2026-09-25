import 'package:intl/intl.dart';

import '../models/mail_models.dart';

DateTime mailDisplayDate(DateTime value) =>
    value.toUtc().add(const Duration(hours: 8));

String formatMailListDate(
  DateTime? value, {
  required DateTime now,
  String locale = 'zh_CN',
}) {
  if (value == null) return '';
  final date = mailDisplayDate(value);
  final current = mailDisplayDate(now);
  final today = DateTime.utc(current.year, current.month, current.day);
  final day = DateTime.utc(date.year, date.month, date.day);
  if (day == today) return DateFormat('HH:mm').format(date);
  if (day == today.subtract(const Duration(days: 1))) {
    return locale.startsWith('en') ? 'Yesterday' : '昨天';
  }
  final monday = today.subtract(Duration(days: today.weekday - 1));
  if (!day.isBefore(monday) &&
      day.isBefore(monday.add(const Duration(days: 7)))) {
    if (locale.startsWith('zh')) {
      return '星期${const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}';
    }
    return DateFormat('EEEE', locale).format(date);
  }
  return '${date.month}/${date.day}';
}

/// Only explicit message references create a conversation. Equal subjects do
/// not imply the messages are replies to each other.
List<List<MailMessageSummary>> groupMailConversations(
  List<MailMessageSummary> messages,
) {
  final parents = <String, String>{};
  String root(String key) {
    parents.putIfAbsent(key, () => key);
    if (parents[key] != key) parents[key] = root(parents[key]!);
    return parents[key]!;
  }

  final ids = <String, String>{};
  List<String> references(String value) => RegExp(
    r'<[^<>\s]+>',
  ).allMatches(value).map((match) => match.group(0)!).toList();
  for (final message in messages) {
    final key = message.identityKey;
    root(key);
    for (final id in references(
      '${message.messageId} ${message.inReplyTo} ${message.references}',
    )) {
      final other = ids.putIfAbsent(id, () => key);
      parents[root(key)] = root(other);
    }
  }
  final groups = <String, List<MailMessageSummary>>{};
  for (final message in messages) {
    groups.putIfAbsent(root(message.identityKey), () => []).add(message);
  }
  int newest(MailMessageSummary a, MailMessageSummary b) =>
      (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970));
  final result = groups.values.toList();
  for (final group in result) {
    group.sort(newest);
  }
  result.sort((a, b) => newest(a.first, b.first));
  return result;
}
