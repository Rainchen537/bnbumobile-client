import '../models/assistant_models.dart';

enum AssistantActionRisk { low, medium, high }

enum AssistantActionTargetBinding {
  none,
  bnbuHttpsUrl,
  timelineItem,
  timelineItemOrMoodleModule,
  moodleModule,
  course,
  mailStableIdentity,
  mailAttachmentIdentity,
  appTab,
  officialSystem,
  campusQuery,
  taCourseCollection,
  taCourseEntry,
}

enum AssistantToolExecutionMode { handoff, executeInApp, unsupported }

class AssistantToolPreviewFieldSchema {
  const AssistantToolPreviewFieldSchema({
    required this.key,
    required this.label,
    required this.editable,
    this.maxLength = 0,
  });

  final String key;
  final String label;
  final bool editable;
  final int maxLength;
}

class AssistantToolDefinition {
  const AssistantToolDefinition({
    required this.type,
    required this.risk,
    required this.requiredContext,
    required this.targetBinding,
    required this.previewSchema,
    required this.editablePreview,
    required this.requiresConfirmation,
    required this.executionMode,
    this.unsupportedReason = '',
  });

  final AssistantActionType type;
  final AssistantActionRisk risk;
  final Set<AssistantContextSource> requiredContext;
  final AssistantActionTargetBinding targetBinding;
  final List<AssistantToolPreviewFieldSchema> previewSchema;
  final bool editablePreview;
  final bool requiresConfirmation;
  final AssistantToolExecutionMode executionMode;
  final String unsupportedReason;

  bool get isUnsupported =>
      executionMode == AssistantToolExecutionMode.unsupported;
}

class AssistantToolRegistry {
  const AssistantToolRegistry._();

  static const definitions = <AssistantActionType, AssistantToolDefinition>{
    AssistantActionType.composeEmail: AssistantToolDefinition(
      type: AssistantActionType.composeEmail,
      risk: AssistantActionRisk.high,
      requiredContext: {
        AssistantContextSource.courses,
        AssistantContextSource.termCourses,
        AssistantContextSource.mailSummaries,
        AssistantContextSource.selectedMail,
        AssistantContextSource.mailToolResults,
      },
      targetBinding: AssistantActionTargetBinding.none,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'recipient',
          label: '收件人',
          editable: true,
          maxLength: 254,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'subject',
          label: '主题',
          editable: true,
          maxLength: 300,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'body',
          label: '正文',
          editable: true,
          maxLength: 8000,
        ),
      ],
      editablePreview: true,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.submitAssignment: AssistantToolDefinition(
      type: AssistantActionType.submitAssignment,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.deadlines},
      targetBinding: AssistantActionTargetBinding.timelineItemOrMoodleModule,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'body',
          label: '在线文本草稿',
          editable: true,
          maxLength: 8000,
        ),
      ],
      editablePreview: true,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openPage: AssistantToolDefinition(
      type: AssistantActionType.openPage,
      risk: AssistantActionRisk.low,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.bnbuHttpsUrl,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openAssignment: AssistantToolDefinition(
      type: AssistantActionType.openAssignment,
      risk: AssistantActionRisk.low,
      requiredContext: {AssistantContextSource.deadlines},
      targetBinding: AssistantActionTargetBinding.timelineItemOrMoodleModule,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openCourse: AssistantToolDefinition(
      type: AssistantActionType.openCourse,
      risk: AssistantActionRisk.low,
      requiredContext: {AssistantContextSource.courses},
      targetBinding: AssistantActionTargetBinding.course,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openMail: AssistantToolDefinition(
      type: AssistantActionType.openMail,
      risk: AssistantActionRisk.medium,
      requiredContext: {
        AssistantContextSource.mailSummaries,
        AssistantContextSource.selectedMail,
        AssistantContextSource.mailToolResults,
      },
      targetBinding: AssistantActionTargetBinding.mailStableIdentity,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.showCampusPlace: AssistantToolDefinition(
      type: AssistantActionType.showCampusPlace,
      risk: AssistantActionRisk.low,
      requiredContext: {
        AssistantContextSource.currentLocation,
        AssistantContextSource.currentPage,
      },
      targetBinding: AssistantActionTargetBinding.campusQuery,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.prepareCoursePack: AssistantToolDefinition(
      type: AssistantActionType.prepareCoursePack,
      risk: AssistantActionRisk.medium,
      requiredContext: {AssistantContextSource.courses},
      targetBinding: AssistantActionTargetBinding.course,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.downloadAttachment: AssistantToolDefinition(
      type: AssistantActionType.downloadAttachment,
      risk: AssistantActionRisk.medium,
      requiredContext: {
        AssistantContextSource.selectedMail,
        AssistantContextSource.mailToolResults,
      },
      targetBinding: AssistantActionTargetBinding.mailAttachmentIdentity,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'attachment_name',
          label: '附件',
          editable: false,
          maxLength: 255,
        ),
      ],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.batchDownloadCourseFiles: AssistantToolDefinition(
      type: AssistantActionType.batchDownloadCourseFiles,
      risk: AssistantActionRisk.medium,
      requiredContext: {AssistantContextSource.courses},
      targetBinding: AssistantActionTargetBinding.course,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.uploadAssignmentFile: AssistantToolDefinition(
      type: AssistantActionType.uploadAssignmentFile,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.deadlines},
      targetBinding: AssistantActionTargetBinding.timelineItemOrMoodleModule,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.startQuizAttempt: AssistantToolDefinition(
      type: AssistantActionType.startQuizAttempt,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.ispaceQuizAttempt},
      targetBinding: AssistantActionTargetBinding.timelineItemOrMoodleModule,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.executeInApp,
    ),
    AssistantActionType.saveQuizAnswers: AssistantToolDefinition(
      type: AssistantActionType.saveQuizAnswers,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.ispaceQuizAttempt},
      targetBinding: AssistantActionTargetBinding.timelineItemOrMoodleModule,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.executeInApp,
    ),
    AssistantActionType.submitQuizAttempt: AssistantToolDefinition(
      type: AssistantActionType.submitQuizAttempt,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.ispaceQuizAttempt},
      targetBinding: AssistantActionTargetBinding.timelineItemOrMoodleModule,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.executeInApp,
    ),
    AssistantActionType.setIspaceCompletion: AssistantToolDefinition(
      type: AssistantActionType.setIspaceCompletion,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.ispaceToolResults},
      targetBinding: AssistantActionTargetBinding.moodleModule,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'ispace_completed',
          label: '完成状态',
          editable: false,
        ),
      ],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.executeInApp,
    ),
    AssistantActionType.submitIspaceChoice: AssistantToolDefinition(
      type: AssistantActionType.submitIspaceChoice,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.ispaceToolResults},
      targetBinding: AssistantActionTargetBinding.moodleModule,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'choice_option_ids',
          label: 'Choice 选项',
          editable: false,
        ),
      ],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.executeInApp,
    ),
    AssistantActionType.deleteMail: AssistantToolDefinition(
      type: AssistantActionType.deleteMail,
      risk: AssistantActionRisk.high,
      requiredContext: {
        AssistantContextSource.mailSummaries,
        AssistantContextSource.selectedMail,
        AssistantContextSource.mailToolResults,
      },
      targetBinding: AssistantActionTargetBinding.mailStableIdentity,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.restoreMail: AssistantToolDefinition(
      type: AssistantActionType.restoreMail,
      risk: AssistantActionRisk.high,
      requiredContext: {
        AssistantContextSource.mailSummaries,
        AssistantContextSource.mailToolResults,
      },
      targetBinding: AssistantActionTargetBinding.mailStableIdentity,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openCampusPage: AssistantToolDefinition(
      type: AssistantActionType.openCampusPage,
      risk: AssistantActionRisk.low,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.none,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openDirectoryEntry: AssistantToolDefinition(
      type: AssistantActionType.openDirectoryEntry,
      risk: AssistantActionRisk.low,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.none,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openMeLifeEntry: AssistantToolDefinition(
      type: AssistantActionType.openMeLifeEntry,
      risk: AssistantActionRisk.low,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.none,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openAppTab: AssistantToolDefinition(
      type: AssistantActionType.openAppTab,
      risk: AssistantActionRisk.low,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.appTab,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openOfficialSystem: AssistantToolDefinition(
      type: AssistantActionType.openOfficialSystem,
      risk: AssistantActionRisk.medium,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.officialSystem,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.openTaCourseManager: AssistantToolDefinition(
      type: AssistantActionType.openTaCourseManager,
      risk: AssistantActionRisk.low,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.none,
      previewSchema: [],
      editablePreview: false,
      requiresConfirmation: false,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.addTaCourse: AssistantToolDefinition(
      type: AssistantActionType.addTaCourse,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.taCourses},
      targetBinding: AssistantActionTargetBinding.taCourseCollection,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'ta_title',
          label: '名称',
          editable: true,
          maxLength: 160,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_location',
          label: '地点',
          editable: true,
          maxLength: 160,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_weekday',
          label: '星期',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_start_minutes',
          label: '开始时间',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_end_minutes',
          label: '结束时间',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_repeat_type',
          label: '重复方式',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_week_start',
          label: '适用周',
          editable: true,
        ),
      ],
      editablePreview: true,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.updateTaCourse: AssistantToolDefinition(
      type: AssistantActionType.updateTaCourse,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.taCourses},
      targetBinding: AssistantActionTargetBinding.taCourseEntry,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'ta_title',
          label: '名称',
          editable: true,
          maxLength: 160,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_location',
          label: '地点',
          editable: true,
          maxLength: 160,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_weekday',
          label: '星期',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_start_minutes',
          label: '开始时间',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_end_minutes',
          label: '结束时间',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_repeat_type',
          label: '重复方式',
          editable: true,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_week_start',
          label: '适用周',
          editable: true,
        ),
      ],
      editablePreview: true,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.deleteTaCourse: AssistantToolDefinition(
      type: AssistantActionType.deleteTaCourse,
      risk: AssistantActionRisk.high,
      requiredContext: {AssistantContextSource.taCourses},
      targetBinding: AssistantActionTargetBinding.taCourseEntry,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'ta_title',
          label: '将删除',
          editable: false,
          maxLength: 160,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'ta_location',
          label: '地点',
          editable: false,
          maxLength: 160,
        ),
      ],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.handoff,
    ),
    AssistantActionType.scheduleNotification: AssistantToolDefinition(
      type: AssistantActionType.scheduleNotification,
      risk: AssistantActionRisk.high,
      requiredContext: {},
      targetBinding: AssistantActionTargetBinding.none,
      previewSchema: [
        AssistantToolPreviewFieldSchema(
          key: 'notification_title',
          label: '提醒标题',
          editable: false,
          maxLength: 160,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'notification_body',
          label: '提醒内容',
          editable: false,
          maxLength: 1000,
        ),
        AssistantToolPreviewFieldSchema(
          key: 'notification_at',
          label: '提醒时间',
          editable: false,
        ),
      ],
      editablePreview: false,
      requiresConfirmation: true,
      executionMode: AssistantToolExecutionMode.executeInApp,
    ),
  };

  static AssistantToolDefinition definitionFor(AssistantActionType type) {
    return definitions[type] ??
        (throw FormatException('不支持的小U动作：${type.wireValue}'));
  }

  static bool requiresConfirmation(AssistantActionType type) {
    return definitionFor(type).requiresConfirmation;
  }
}
