import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/assistant_models.dart';
import '../models/course_summary.dart';
import '../models/mail_models.dart';
import '../models/ta_course_entry.dart';
import '../models/timeline_item.dart';
import '../state/app_session_controller.dart';

class AssistantActionRuntime {
  const AssistantActionRuntime._();

  static String normalizeOwner(String value) => value.trim().toLowerCase();

  static String timelineIdentity(TimelineItem item) {
    return _digest([
      'timeline',
      item.id,
      item.courseId,
      item.instanceId,
      item.moduleName,
      item.title,
      item.courseName,
      item.sortTime?.toUtc().toIso8601String() ?? '',
    ]);
  }

  static String moodleModuleIdentity(String moduleRef) =>
      'moodle-module:${moduleRef.trim()}';

  static String courseIdentity(CourseSummary course) {
    return _digest([
      'course',
      course.id,
      course.fullName,
      course.shortName,
      course.categoryName,
    ]);
  }

  static String mailIdentity({
    required MailFolder folder,
    required int uid,
    required int mailboxUidValidity,
  }) {
    return _digest(['mail', folder.name, uid, mailboxUidValidity]);
  }

  static String mailAttachmentIdentity({
    required MailFolder folder,
    required int uid,
    required int mailboxUidValidity,
    required String partId,
  }) {
    return _digest([
      'mail_attachment',
      folder.name,
      uid,
      mailboxUidValidity,
      partId,
    ]);
  }

  static String taCourseCollectionIdentity({required int collectionRevision}) {
    return _digest(['ta_course_collection', collectionRevision]);
  }

  static String taCourseEntryIdentity({
    required TaCourseEntry entry,
    required int collectionRevision,
  }) {
    return _digest([
      'ta_course_entry',
      entry.id,
      entry.kind.name,
      entry.courseKey,
      entry.courseCode,
      entry.semesterId,
      entry.title,
      entry.location,
      entry.weekday,
      entry.startMinutes,
      entry.endMinutes,
      entry.repeatType.name,
      entry.weekStart?.toUtc().toIso8601String() ?? '',
      entry.revision,
      collectionRevision,
    ]);
  }

  static bool actionBelongsToLease(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final owner = normalizeOwner(action.sessionOwner);
    return owner.isNotEmpty && owner == normalizeOwner(lease.owner);
  }

  static bool actionExpired(AssistantAction action, DateTime now) {
    final expiresAt = action.expiresAt;
    return expiresAt != null && !expiresAt.isAfter(now.toUtc());
  }

  static String _digest(List<Object> parts) {
    final normalized = parts
        .map((part) => part.toString().trim().toLowerCase())
        .join('');
    return sha256.convert(utf8.encode(normalized)).toString();
  }
}
