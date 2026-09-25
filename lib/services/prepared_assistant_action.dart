import '../models/assistant_models.dart';
import '../models/course_summary.dart';
import '../models/mail_models.dart';
import '../models/quiz_attempt_data.dart';
import '../models/ta_course_entry.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../state/app_session_controller.dart';
import '../state/mail_assistant_intent_controller.dart';
import '../state/root_shell_controller.dart';
import 'mail_service.dart';

enum AssistantActionPreparationStatus { ready, stale, unsupported }

enum AssistantActionHandoffKind {
  none,
  appTab,
  campusPage,
  meLifeEntry,
  directoryEntry,
  officialPage,
  assignmentDetail,
  assignmentFileUpload,
  courseDetail,
  courseBatchDownload,
  mailDetail,
  mailAttachment,
  mailMutation,
  campusPlace,
  mailCompose,
  assignmentOnlineText,
  taCourseManager,
  localNotification,
  quizMutation,
  ispaceMutation,
}

class AssistantActionPreviewField {
  const AssistantActionPreviewField({
    required this.key,
    required this.label,
    required this.value,
    required this.editable,
    this.maxLength = 0,
  });

  final String key;
  final String label;
  final String value;
  final bool editable;
  final int maxLength;
}

enum AssistantTaCourseIntentKind { open, add, update, delete }

class AssistantTaCourseIntent {
  const AssistantTaCourseIntent({
    required this.kind,
    required this.expectedCollectionRevision,
    required this.targetIdentity,
    this.entry,
    this.expectedEntryRevision,
  });

  final AssistantTaCourseIntentKind kind;
  final TaCourseEntry? entry;
  final int? expectedEntryRevision;
  final int expectedCollectionRevision;
  final String targetIdentity;
}

class PreparedAssistantAction {
  PreparedAssistantAction.ready({
    required this.action,
    required this.handoffKind,
    required this.title,
    required this.summary,
    this.previewFields = const [],
    this.sessionLease,
    this.rootNavigationPrepared = false,
    this.mailCredentials,
    this.mailService,
    this.mailDetail,
    this.mailRecipient = '',
    this.mailSubject = '',
    this.mailBody = '',
    this.timelineItem,
    this.timelineDetail,
    this.assignmentDraft = '',
    this.assignmentFiles = const [],
    this.officialUri,
    this.officialTitle = '',
    this.course,
    this.appTab,
    this.mailIntent,
    this.campusPlaceQuery = '',
    this.taCourseIntent,
    this.notificationTitle = '',
    this.notificationBody = '',
    this.notificationAt,
    this.quizSnapshot,
    this.quizAnswers = const [],
  }) : status = AssistantActionPreparationStatus.ready,
       unsupportedReason = '';

  PreparedAssistantAction.stale({required this.action})
    : status = AssistantActionPreparationStatus.stale,
      handoffKind = AssistantActionHandoffKind.none,
      title = action.title,
      summary = '',
      previewFields = const [],
      unsupportedReason = '',
      sessionLease = null,
      rootNavigationPrepared = false,
      mailCredentials = null,
      mailService = null,
      mailDetail = null,
      mailRecipient = '',
      mailSubject = '',
      mailBody = '',
      timelineItem = null,
      timelineDetail = null,
      assignmentDraft = '',
      assignmentFiles = const [],
      officialUri = null,
      officialTitle = '',
      course = null,
      appTab = null,
      mailIntent = null,
      campusPlaceQuery = '',
      taCourseIntent = null,
      notificationTitle = '',
      notificationBody = '',
      notificationAt = null,
      quizSnapshot = null,
      quizAnswers = const [];

  PreparedAssistantAction.unsupported({
    required this.action,
    required this.unsupportedReason,
  }) : status = AssistantActionPreparationStatus.unsupported,
       handoffKind = AssistantActionHandoffKind.none,
       title = action.title,
       summary = unsupportedReason,
       previewFields = const [],
       sessionLease = null,
       rootNavigationPrepared = false,
       mailCredentials = null,
       mailService = null,
       mailDetail = null,
       mailRecipient = '',
       mailSubject = '',
       mailBody = '',
       timelineItem = null,
       timelineDetail = null,
       assignmentDraft = '',
       assignmentFiles = const [],
       officialUri = null,
       officialTitle = '',
       course = null,
       appTab = null,
       mailIntent = null,
       campusPlaceQuery = '',
       taCourseIntent = null,
       notificationTitle = '',
       notificationBody = '',
       notificationAt = null,
       quizSnapshot = null,
       quizAnswers = const [];

  final AssistantAction action;
  final AssistantActionPreparationStatus status;
  final AssistantActionHandoffKind handoffKind;
  final String title;
  final String summary;
  final List<AssistantActionPreviewField> previewFields;
  final String unsupportedReason;
  final AppSessionLease? sessionLease;
  final bool rootNavigationPrepared;

  final MailAccessCredentials? mailCredentials;
  final MailService? mailService;
  final MailMessageDetail? mailDetail;
  final String mailRecipient;
  final String mailSubject;
  final String mailBody;

  final TimelineItem? timelineItem;
  final TimelineDetailData? timelineDetail;
  final String assignmentDraft;
  final List<UploadFilePayload> assignmentFiles;

  final Uri? officialUri;
  final String officialTitle;
  final CourseSummary? course;
  final AppTab? appTab;
  final AssistantMailIntent? mailIntent;
  final String campusPlaceQuery;
  final AssistantTaCourseIntent? taCourseIntent;
  final String notificationTitle;
  final String notificationBody;
  final DateTime? notificationAt;
  final QuizAttemptSnapshot? quizSnapshot;
  final List<QuizAnswerDraft> quizAnswers;
}
