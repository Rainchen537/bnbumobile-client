import 'timeline_item.dart';

enum TimelineDetailType { generic, assignment, forum, mediasite }

class TimelineDetailData {
  TimelineDetailData({
    required this.item,
    required this.type,
    this.assignmentId = 0,
    this.assignmentName = '',
    this.assignmentIntro = '',
    this.assignmentIntroHtml = '',
    this.assignmentIntroFiles = const [],
    this.openDateEpoch = 0,
    this.dueDateEpoch = 0,
    this.cutoffDateEpoch = 0,
    this.gradingDueDateEpoch = 0,
    this.submissionStatus = '',
    this.gradingStatus = '',
    this.canEditSubmission = false,
    this.feedbackSummary = '',
    this.supportsFileSubmission = false,
    this.supportsOnlineTextSubmission = false,
    this.maxFileSubmissions = 0,
    this.maxSubmissionSizeBytes = 0,
    this.submissionFiles = const [],
    this.submissionDrafts = false,
    this.requiresSubmissionStatement = false,
    this.submissionStatement = '',
    this.teamSubmission = false,
    this.requireAllTeamMembersSubmit = false,
    this.preventSubmissionNotInGroup = false,
    this.timeLimitSeconds = 0,
    this.submissionsEnabled = false,
    this.submissionLocked = false,
    this.canFinalizeSubmission = false,
    this.forumId = 0,
    this.forumName = '',
    this.forumDescription = '',
    this.forumDiscussions = const [],
    this.canStartDiscussion = false,
    this.mediasiteLaunchUrl = '',
    this.hints = const [],
  });

  final TimelineItem item;
  final TimelineDetailType type;
  final int assignmentId;
  final String assignmentName;
  final String assignmentIntro;
  final String assignmentIntroHtml;
  final List<SubmissionFile> assignmentIntroFiles;
  final int openDateEpoch;
  final int dueDateEpoch;
  final int cutoffDateEpoch;
  final int gradingDueDateEpoch;
  final String submissionStatus;
  final String gradingStatus;
  final bool canEditSubmission;
  final String feedbackSummary;
  final bool supportsFileSubmission;
  final bool supportsOnlineTextSubmission;
  final int maxFileSubmissions;
  final int maxSubmissionSizeBytes;
  final List<SubmissionFile> submissionFiles;
  final bool submissionDrafts;
  final bool requiresSubmissionStatement;
  final String submissionStatement;
  final bool teamSubmission;
  final bool requireAllTeamMembersSubmit;
  final bool preventSubmissionNotInGroup;
  final int timeLimitSeconds;
  final bool submissionsEnabled;
  final bool submissionLocked;
  final bool canFinalizeSubmission;
  final int forumId;
  final String forumName;
  final String forumDescription;
  final List<ForumDiscussion> forumDiscussions;
  final bool canStartDiscussion;
  final String mediasiteLaunchUrl;
  final List<String> hints;

  DateTime? get openDate => _toDateTime(openDateEpoch);
  DateTime? get dueDate => _toDateTime(dueDateEpoch);
  DateTime? get cutoffDate => _toDateTime(cutoffDateEpoch);
  DateTime? get gradingDueDate => _toDateTime(gradingDueDateEpoch);

  static DateTime? _toDateTime(int timestampSeconds) {
    if (timestampSeconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      timestampSeconds * 1000,
      isUtc: true,
    );
  }
}

class AssignmentSubmissionOutcome {
  const AssignmentSubmissionOutcome({
    required this.status,
    required this.draftSaved,
    required this.finalSubmitted,
  });

  final String status;
  final bool draftSaved;
  final bool finalSubmitted;
}

class SubmissionFile {
  SubmissionFile({
    required this.fileName,
    required this.fileUrl,
    required this.fileSize,
    required this.mimeType,
    required this.modifiedEpoch,
  });

  final String fileName;
  final String fileUrl;
  final int fileSize;
  final String mimeType;
  final int modifiedEpoch;

  DateTime? get modifiedAt {
    if (modifiedEpoch <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      modifiedEpoch * 1000,
      isUtc: true,
    );
  }
}

class ForumDiscussion {
  ForumDiscussion({
    required this.id,
    required this.subject,
    required this.messagePreview,
    required this.author,
    required this.timeModifiedEpoch,
    required this.replyCount,
    required this.pinned,
    required this.locked,
    required this.discussionUrl,
  });

  final int id;
  final String subject;
  final String messagePreview;
  final String author;
  final int timeModifiedEpoch;
  final int replyCount;
  final bool pinned;
  final bool locked;
  final String discussionUrl;

  DateTime? get timeModifiedAt {
    if (timeModifiedEpoch <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      timeModifiedEpoch * 1000,
      isUtc: true,
    );
  }
}

class ForumPost {
  ForumPost({
    required this.id,
    required this.subject,
    required this.message,
    required this.author,
    required this.timeCreatedEpoch,
    required this.parentId,
    required this.isPrivateReply,
  });

  final int id;
  final String subject;
  final String message;
  final String author;
  final int timeCreatedEpoch;
  final int parentId;
  final bool isPrivateReply;

  DateTime? get timeCreatedAt {
    if (timeCreatedEpoch <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      timeCreatedEpoch * 1000,
      isUtc: true,
    );
  }
}
