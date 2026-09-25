import 'dart:async';
import 'package:flutter/material.dart';
import 'mail_sender_identity.dart';
import 'mail_forward_content.dart';
import 'mail_presentation.dart';

import '../config/app_config.dart';
import '../l10n/bnbu_localizations.dart';
import '../models/assistant_models.dart';
import '../models/course_summary.dart';
import '../models/mail_models.dart';
import '../models/quiz_attempt_data.dart';
import '../models/ta_course_entry.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../pages/campus_navigation_page.dart';
import '../pages/campus_landmarks_page.dart';
import '../pages/campus_directory_page.dart';
import 'campus_landmark_store.dart';
import '../pages/academic_calendar_page.dart';
import '../pages/student_ecard_page.dart';
import '../pages/course_detail_page.dart';
import '../pages/mail_page.dart';
import '../pages/official_web_page.dart';
import '../pages/leave_application_page.dart';
import '../pages/ta_course_manager_page.dart';
import '../pages/timeline_detail_page.dart';
import '../state/app_session_controller.dart';
import '../state/mail_assistant_intent_controller.dart';
import '../state/root_shell_controller.dart';
import '../state/ta_course_controller.dart';
import '../widgets/bnbu_notice.dart';
import 'assistant_action_runtime.dart';
import 'assistant_tool_registry.dart';
import 'mail_attachment_store.dart';
import 'mail_service.dart';
import 'mail_service_factory.dart';
import 'moodle_api_client.dart';
import 'official_url_policy.dart';
import 'prepared_assistant_action.dart';

class AiAssistantActionExecutor {
  AiAssistantActionExecutor({
    required GlobalKey<NavigatorState> navigatorKey,
    required AppSessionController controller,
    MailService Function()? mailServiceFactory,
    Future<void> Function()? beforeNavigation,
    TaCourseController? taCourseController,
    RootShellController? rootShellController,
    MailAssistantIntentController? mailIntentController,
    DateTime Function()? now,
    CampusLandmarkStore? meLifeStore,
    this.onActionOutcome,
  }) : _navigatorKey = navigatorKey,
       _controller = controller,
       _mailServiceFactory = mailServiceFactory ?? createMailService,
       _beforeNavigation = beforeNavigation,
       _taCourseController = taCourseController,
       _rootShellController = rootShellController,
       _mailIntentController = mailIntentController,
       _now = now ?? DateTime.now,
       _meLifeStore = meLifeStore ?? CampusLandmarkStore.shared;
  final CampusLandmarkStore _meLifeStore;

  final GlobalKey<NavigatorState> _navigatorKey;
  final AppSessionController _controller;
  final MailService Function() _mailServiceFactory;
  final Future<void> Function()? _beforeNavigation;
  final TaCourseController? _taCourseController;
  final RootShellController? _rootShellController;
  final MailAssistantIntentController? _mailIntentController;
  final DateTime Function() _now;
  final void Function(AssistantAction, String)? onActionOutcome;

  BnbuLocalizations get _localizations {
    final context = _navigatorKey.currentContext;
    return context == null
        ? const BnbuLocalizations(Locale('zh'))
        : BnbuLocalizations.of(context);
  }

  Future<PreparedAssistantAction> prepare(AssistantAction action) async {
    final definition = AssistantToolRegistry.definitionFor(action.type);
    _validateConfirmationDeclaration(action, definition);
    final lease = _validatedLease(action);
    if (definition.isUnsupported) {
      return PreparedAssistantAction.unsupported(
        action: action,
        unsupportedReason: definition.unsupportedReason,
      );
    }

    switch (action.type) {
      case AssistantActionType.composeEmail:
        return _prepareComposeEmail(action, lease);
      case AssistantActionType.submitAssignment:
        return _prepareAssignmentSubmission(action, lease);
      case AssistantActionType.openPage:
        return _prepareOfficialPage(action, lease);
      case AssistantActionType.openAssignment:
        return _prepareOpenAssignment(action, lease);
      case AssistantActionType.openCourse:
        return _prepareOpenCourse(action, lease);
      case AssistantActionType.openMail:
        return _prepareOpenMail(action, lease);
      case AssistantActionType.showCampusPlace:
        return _prepareCampusPlace(action, lease);
      case AssistantActionType.prepareCoursePack:
        return _prepareCoursePack(action, lease);
      case AssistantActionType.downloadAttachment:
        return _prepareDownloadAttachment(action, lease);
      case AssistantActionType.batchDownloadCourseFiles:
        return _prepareBatchDownloadCourseFiles(action, lease);
      case AssistantActionType.uploadAssignmentFile:
        return _prepareAssignmentFileUpload(action, lease);
      case AssistantActionType.startQuizAttempt:
      case AssistantActionType.saveQuizAnswers:
      case AssistantActionType.submitQuizAttempt:
        return _prepareQuizAction(action, lease);
      case AssistantActionType.setIspaceCompletion:
      case AssistantActionType.submitIspaceChoice:
        return _prepareIspaceMutation(action, lease);
      case AssistantActionType.deleteMail:
      case AssistantActionType.restoreMail:
        return _prepareMailMutation(action, lease);
      case AssistantActionType.openCampusPage:
        return _prepareCampusPage(action, lease);
      case AssistantActionType.openMeLifeEntry:
        return _prepareMeLifeEntry(action, lease);
      case AssistantActionType.openDirectoryEntry:
        if (action.url.isNotEmpty ||
            action.requiresConfirmation ||
            (action.targetId.isNotEmpty &&
                !RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(action.targetId))) {
          throw const AiAssistantActionException('政教目录参数无效。');
        }
        return PreparedAssistantAction.ready(
          action: action,
          sessionLease: lease,
          handoffKind: AssistantActionHandoffKind.directoryEntry,
          title: action.title,
          summary: '打开政教目录',
        );
      case AssistantActionType.openAppTab:
        return _prepareAppTab(action, lease);
      case AssistantActionType.openOfficialSystem:
        return _prepareOfficialSystem(action, lease);
      case AssistantActionType.openTaCourseManager:
      case AssistantActionType.addTaCourse:
      case AssistantActionType.updateTaCourse:
      case AssistantActionType.deleteTaCourse:
        return _prepareTaCourse(action, lease);
      case AssistantActionType.scheduleNotification:
        return _prepareNotification(action, lease);
    }
  }

  Future<void> execute(
    AssistantAction action, {
    bool userConfirmed = false,
  }) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      throw const AiAssistantActionException('当前页面暂时无法执行该操作。');
    }
    final definition = AssistantToolRegistry.definitionFor(action.type);
    _validateConfirmationDeclaration(action, definition);
    if (action.requiresConfirmation && !userConfirmed) {
      throw const AiAssistantActionException('该操作必须先由用户确认。');
    }

    try {
      final prepared = await prepare(action);
      switch (prepared.status) {
        case AssistantActionPreparationStatus.ready:
          await _handoff(navigator, prepared);
          return;
        case AssistantActionPreparationStatus.stale:
          return;
        case AssistantActionPreparationStatus.unsupported:
          throw AiAssistantActionException(prepared.unsupportedReason);
      }
    } catch (_) {
      onActionOutcome?.call(action, 'failed');
      rethrow;
    }
  }

  Future<PreparedAssistantAction> _prepareComposeEmail(
    AssistantAction action,
    AppSessionLease lease,
  ) async {
    final recipient = action.recipient.trim().toLowerCase();
    final subject = _limit(action.subject, 300);
    final body = _limit(action.body, 8000);
    if (action.mailUid == null && !_isOfficialEmail(recipient)) {
      throw const AiAssistantActionException('邮件收件人需使用有效的 BNBU 官方邮箱。');
    }
    if (subject.isEmpty || body.isEmpty) {
      throw const AiAssistantActionException('邮件主题和正文不能为空。');
    }
    final credentials = await _controller.loadMailAccessCredentials();
    if (!lease.isActive) {
      return PreparedAssistantAction.stale(action: action);
    }
    if (credentials == null) {
      throw const AiAssistantActionException('当前登录状态无法发送邮件。');
    }
    MailMessageDetail? replyTo;
    if (action.mailUid != null) {
      final (folder, uid, validity) = _validatedMailFields(action);
      if (action.mailMode == 'draft' && folder != MailFolder.drafts) {
        throw const AiAssistantActionException('目标邮件不在草稿箱。');
      }
      if (action.mailMode == 'forward' && !_isOfficialEmail(recipient)) {
        throw const AiAssistantActionException('请在原生写信页确认收件人。');
      }
      final service = _mailServiceFactory();
      try {
        replyTo = await service.readMessage(
          credentials: credentials,
          folder: folder,
          uid: uid,
          expectedMailboxUidValidity: validity,
          markAsSeen: false,
        );
        final match = RegExp(r'<([^<>]+)>').firstMatch(replyTo.sender);
        final sender = (match?.group(1) ?? replyTo.sender).trim().toLowerCase();
        if ((action.mailMode != 'forward' &&
                action.mailMode != 'draft' &&
                sender != recipient) ||
            replyTo.uid != uid ||
            replyTo.mailboxUidValidity != validity ||
            replyTo.folder != folder) {
          throw const AiAssistantActionException('邮件回复对象已变化，请重新读取原邮件。');
        }
      } finally {
        await service.close();
      }
      if (!lease.isActive) return PreparedAssistantAction.stale(action: action);
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.mailCompose,
      title: '打开写邮件',
      summary: '将在原生写邮件页面预填内容，由你最终发送。',
      previewFields: [
        AssistantActionPreviewField(
          key: 'recipient',
          label: '收件人',
          value: recipient,
          editable: true,
          maxLength: 254,
        ),
        AssistantActionPreviewField(
          key: 'subject',
          label: '主题',
          value: subject,
          editable: true,
          maxLength: 300,
        ),
        AssistantActionPreviewField(
          key: 'body',
          label: '正文',
          value: body,
          editable: true,
          maxLength: 8000,
        ),
      ],
      sessionLease: lease,
      mailCredentials: credentials,
      mailDetail: replyTo,
      mailRecipient: recipient,
      mailSubject: subject,
      mailBody: body,
    );
  }

  Future<PreparedAssistantAction> _prepareAssignmentSubmission(
    AssistantAction action,
    AppSessionLease lease,
  ) async {
    final text = _limit(action.body, 8000);
    if (text.isEmpty) {
      throw const AiAssistantActionException('作业提交内容不能为空。');
    }
    final item = await _validatedTimelineItem(action);
    final detail = await _controller.loadTimelineDetail(item);
    if (!lease.isActive) {
      return PreparedAssistantAction.stale(action: action);
    }
    final currentItem = await _validatedTimelineItem(action);
    if (detail.type != TimelineDetailType.assignment ||
        detail.assignmentId <= 0 ||
        !detail.canEditSubmission ||
        !detail.supportsOnlineTextSubmission) {
      throw const AiAssistantActionException('该作业当前不支持在线文本提交。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.assignmentOnlineText,
      title: '打开作业提交页',
      summary: '将在原生作业页预填在线文本草稿，由你再次确认后提交。',
      previewFields: [
        AssistantActionPreviewField(
          key: 'body',
          label: '在线文本草稿',
          value: text,
          editable: true,
          maxLength: 8000,
        ),
      ],
      sessionLease: lease,
      timelineItem: currentItem,
      timelineDetail: detail,
      assignmentDraft: text,
    );
  }

  Future<PreparedAssistantAction> _prepareQuizAction(
    AssistantAction action,
    AppSessionLease lease,
  ) async {
    final item = await _validatedTimelineItem(action);
    final snapshot = await _controller.loadQuizAttempt(item);
    if (!lease.isActive) {
      return PreparedAssistantAction.stale(action: action);
    }
    if (!_isModuleRef(action.targetId) && snapshot.itemId != action.targetId) {
      throw const AiAssistantActionException('Quiz 活动标识已变化，请重新读取题目。');
    }
    if (action.type == AssistantActionType.startQuizAttempt) {
      if (!snapshot.canStart || snapshot.hasActiveAttempt) {
        throw const AiAssistantActionException('Quiz 已经开始或当前无法开始。');
      }
      return PreparedAssistantAction.ready(
        action: action,
        handoffKind: AssistantActionHandoffKind.quizMutation,
        title: '开始 Quiz',
        summary: '确认后将创建新的作答 attempt；不会自动交卷。',
        previewFields: [
          AssistantActionPreviewField(
            key: 'quiz',
            label: '测验',
            value: item.title,
            editable: false,
          ),
        ],
        sessionLease: lease,
        timelineItem: item,
        quizSnapshot: snapshot,
      );
    }
    if (!snapshot.hasActiveAttempt ||
        snapshot.attemptId != action.quizAttemptId) {
      throw const AiAssistantActionException('Quiz attempt 已变化，请重新生成答案。');
    }
    if ((action.type == AssistantActionType.saveQuizAnswers &&
            !snapshot.canSave) ||
        (action.type == AssistantActionType.submitQuizAttempt &&
            !snapshot.canFinish)) {
      throw const AiAssistantActionException('Quiz 当前不允许执行该操作。');
    }
    final drafts = _validatedQuizDrafts(action, snapshot);
    final preview = _quizPreviewFields(snapshot, drafts);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.quizMutation,
      title: action.type == AssistantActionType.saveQuizAnswers
          ? '保存 Quiz 答案'
          : '最终提交 Quiz',
      summary: action.type == AssistantActionType.saveQuizAnswers
          ? '确认后只保存答案，保留 attempt，不会交卷。'
          : '确认后将结束 attempt 并最终交卷，此操作不可撤回。',
      previewFields: preview,
      sessionLease: lease,
      timelineItem: item,
      quizSnapshot: snapshot,
      quizAnswers: drafts,
    );
  }

  List<QuizAnswerDraft> _validatedQuizDrafts(
    AssistantAction action,
    QuizAttemptSnapshot snapshot,
  ) {
    if (action.quizResponses.isEmpty) {
      throw const AiAssistantActionException('没有可处理的 Quiz 答案。');
    }
    final questions = {
      for (final question in snapshot.questions) question.slot: question,
    };
    final seen = <String>{};
    return action.quizResponses
        .map((response) {
          final question = questions[response.slot];
          final identity = '${response.slot}:${response.fieldName}';
          if (question == null || !seen.add(identity)) {
            throw const AiAssistantActionException('Quiz 答案包含失效或重复字段。');
          }
          final fields = question.fields.where(
            (field) => field.name == response.fieldName,
          );
          if (fields.length != 1) {
            throw const AiAssistantActionException('Quiz 答案字段已变化，请重新生成答案。');
          }
          final field = fields.single;
          if (response.value.length > field.maxLength ||
              (field.options.isNotEmpty &&
                  !field.options.any(
                    (option) => option.value == response.value,
                  ))) {
            throw const AiAssistantActionException('Quiz 答案值不在当前允许范围内。');
          }
          return QuizAnswerDraft(
            slot: response.slot,
            fieldName: response.fieldName,
            value: response.value,
          );
        })
        .toList(growable: false);
  }

  List<AssistantActionPreviewField> _quizPreviewFields(
    QuizAttemptSnapshot snapshot,
    List<QuizAnswerDraft> drafts,
  ) {
    final questions = {
      for (final question in snapshot.questions) question.slot: question,
    };
    return drafts
        .map((draft) {
          final question = questions[draft.slot]!;
          final field = question.fields.singleWhere(
            (candidate) => candidate.name == draft.fieldName,
          );
          final optionMatches = field.options.where(
            (option) => option.value == draft.value,
          );
          final answer = optionMatches.isEmpty
              ? draft.value
              : optionMatches.single.label;
          final prompt = question.prompt.trim();
          return AssistantActionPreviewField(
            key: 'quiz_${draft.slot}_${draft.fieldName}',
            label: question.number.isEmpty
                ? '第 ${draft.slot} 题'
                : '第 ${question.number} 题',
            value: prompt.isEmpty ? answer : '$prompt\n答案：$answer',
            editable: false,
            maxLength: 4500,
          );
        })
        .toList(growable: false);
  }

  PreparedAssistantAction _prepareOfficialPage(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final Uri uri;
    try {
      uri = OfficialUrlPolicy.requireBnbuUrl(action.url);
    } on FormatException {
      throw const AiAssistantActionException('小U返回的页面需为 BNBU 官方 HTTPS 页面。');
    }
    final title = _limit(action.title, 80);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.officialPage,
      title: title.isEmpty ? 'BNBU 官网' : title,
      summary: uri.toString(),
      sessionLease: lease,
      officialUri: uri,
      officialTitle: title.isEmpty ? 'BNBU 官网' : title,
    );
  }

  Future<PreparedAssistantAction> _prepareOpenAssignment(
    AssistantAction action,
    AppSessionLease lease,
  ) async {
    final item = await _validatedTimelineItem(action);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.assignmentDetail,
      title: item.title,
      summary: item.courseName,
      sessionLease: lease,
      timelineItem: item,
    );
  }

  PreparedAssistantAction _prepareOpenCourse(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final course = _validatedCourse(action);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.courseDetail,
      title: course.fullName,
      summary: course.shortName,
      sessionLease: lease,
      course: course,
    );
  }

  PreparedAssistantAction _prepareCoursePack(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final course = _validatedCourse(action);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.courseDetail,
      title: course.fullName,
      summary: '小U只会打开课程资料清单，不会自动批量下载。',
      sessionLease: lease,
      course: course,
    );
  }

  PreparedAssistantAction _prepareDownloadAttachment(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final (folder, uid, mailboxUidValidity) = _validatedMailFields(action);
    final partId = _limit(action.mailPartId, 160);
    final attachmentName = _limit(action.attachmentName, 255);
    if (partId.isEmpty || attachmentName.isEmpty) {
      throw const AiAssistantActionException('附件引用不完整，请重新打开邮件后再试。');
    }
    final identity = AssistantActionRuntime.mailAttachmentIdentity(
      folder: folder,
      uid: uid,
      mailboxUidValidity: mailboxUidValidity,
      partId: partId,
    );
    if (action.targetIdentity != identity) {
      throw const AiAssistantActionException('附件引用已失效，请重新打开邮件后再试。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.mailAttachment,
      title: '下载邮件附件',
      summary: attachmentName,
      previewFields: [
        AssistantActionPreviewField(
          key: 'attachment_name',
          label: '附件',
          value: attachmentName,
          editable: false,
          maxLength: 255,
        ),
      ],
      sessionLease: lease,
    );
  }

  PreparedAssistantAction _prepareBatchDownloadCourseFiles(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final course = _validatedCourse(action);
    final scope = switch (action.courseFileScope) {
      AssistantCourseFileScope.presentations => '演示文稿',
      AssistantCourseFileScope.presentationsAndPdf => '演示文稿与 PDF 课件',
      AssistantCourseFileScope.documents => '文档',
      AssistantCourseFileScope.media => '音视频',
      AssistantCourseFileScope.archives => '压缩包',
      AssistantCourseFileScope.all || null => '全部文件',
    };
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.courseBatchDownload,
      title: '打包课程资料',
      summary:
          '${course.fullName} · 将重新读取真实文件清单，预选安全范围内的$scope，'
          '确认实际数量与大小后在本机生成 ZIP。',
      sessionLease: lease,
      course: course,
    );
  }

  Future<PreparedAssistantAction> _prepareAssignmentFileUpload(
    AssistantAction action,
    AppSessionLease lease,
  ) async {
    final item = await _validatedTimelineItem(action);
    final detail = await _controller.loadTimelineDetail(item);
    if (!lease.isActive) {
      return PreparedAssistantAction.stale(action: action);
    }
    final currentItem = await _validatedTimelineItem(action);
    if (detail.type != TimelineDetailType.assignment ||
        detail.assignmentId <= 0 ||
        !detail.canEditSubmission ||
        !detail.supportsFileSubmission) {
      throw const AiAssistantActionException('该作业当前不支持文件提交。');
    }
    final assignmentFiles = action.localAttachments
        .where((item) => item.isLocalFileReference)
        .map(
          (item) => UploadFilePayload(
            fileName: item.name,
            filePath: item.localFilePath,
          ),
        )
        .where((item) => item.hasUsableContent)
        .toList(growable: false);
    if (detail.maxFileSubmissions > 0 &&
        assignmentFiles.length > detail.maxFileSubmissions) {
      throw AiAssistantActionException(
        '该作业最多允许 ${detail.maxFileSubmissions} 个文件。',
      );
    }
    if (detail.maxSubmissionSizeBytes > 0 &&
        action.localAttachments.any(
          (item) =>
              item.isLocalFileReference &&
              item.effectiveByteCount > detail.maxSubmissionSizeBytes,
        )) {
      throw const AiAssistantActionException('选择的文件超过该作业允许的单文件大小。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.assignmentFileUpload,
      title: '打开作业文件提交',
      summary: assignmentFiles.isEmpty
          ? '将在原生作业页重新校验状态并打开文件选择器，不会自动提交。'
          : '已准备 ${assignmentFiles.length} 个本机文件；将在原生作业页再次由你确认提交。',
      sessionLease: lease,
      timelineItem: currentItem,
      timelineDetail: detail,
      assignmentFiles: assignmentFiles,
    );
  }

  PreparedAssistantAction _prepareMailMutation(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final (folder, uid, mailboxUidValidity) = _validatedMailIdentity(action);
    final isRestore = action.type == AssistantActionType.restoreMail;
    if (isRestore && folder != MailFolder.trash) {
      throw const AiAssistantActionException('只有已删除邮箱中的邮件可以恢复。');
    }
    if (!isRestore && folder == MailFolder.trash) {
      throw const AiAssistantActionException('小U不能请求永久删除已删除邮箱中的邮件。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.mailMutation,
      title: isRestore ? '恢复邮件' : '删除邮件',
      summary: '将在原生邮箱重新读取并校验邮件，由你最终确认。',
      sessionLease: lease,
      mailIntent: AssistantMailIntent(
        kind: isRestore
            ? AssistantMailIntentKind.restore
            : AssistantMailIntentKind.delete,
        folder: folder,
        uid: uid,
        mailboxUidValidity: mailboxUidValidity,
        targetIdentity: action.targetIdentity,
      ),
    );
  }

  Future<PreparedAssistantAction> _prepareMeLifeEntry(
    AssistantAction action,
    AppSessionLease lease,
  ) async {
    if (action.url.isNotEmpty ||
        action.requiresConfirmation ||
        (action.targetId.isNotEmpty &&
            !RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(action.targetId))) {
      throw const AiAssistantActionException('ME生活条目参数无效。');
    }
    await _meLifeStore.refresh();
    if (!lease.isActive) return PreparedAssistantAction.stale(action: action);
    if (_meLifeStore.failed || _meLifeStore.catalog == null) {
      throw const AiAssistantActionException('ME生活目录暂时无法更新，请稍后重试。');
    }
    if (action.targetId.isNotEmpty &&
        !_meLifeStore.catalog!.landmarks.any(
          (item) => item.id == action.targetId,
        )) {
      throw const AiAssistantActionException('该条目已更新或下架，请重新询问小U。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      sessionLease: lease,
      handoffKind: AssistantActionHandoffKind.meLifeEntry,
      title: action.title,
      summary: '打开ME生活',
    );
  }

  PreparedAssistantAction _prepareCampusPage(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    if (!{
          'academic_calendar',
          'class_schedule',
          'leave',
          'ecard',
          'schedule',
        }.contains(action.targetId) ||
        action.url.isNotEmpty ||
        action.requiresConfirmation ||
        !{'', 'horizontal', 'vertical'}.contains(action.scheduleView)) {
      throw const AiAssistantActionException('校园页面参数无效。');
    }
    if (action.targetId != 'schedule' &&
        (action.scheduleDate.isNotEmpty || action.scheduleView.isNotEmpty)) {
      throw const AiAssistantActionException('该页面不接受课表参数。');
    }
    if (action.scheduleDate.isNotEmpty) {
      final date = DateTime.tryParse(action.scheduleDate);
      if (date == null ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(action.scheduleDate) ||
          date.toIso8601String().substring(0, 10) != action.scheduleDate) {
        throw const AiAssistantActionException('课表日期无效。');
      }
    }
    final context = _navigatorKey.currentContext;
    if (action.targetId == 'ecard' &&
        (context == null ||
            !StudentEcardPage.supportsPlatform(Theme.of(context).platform))) {
      return PreparedAssistantAction.unsupported(
        action: action,
        unsupportedReason: 'eCard仅在手机和平板提供。',
      );
    }
    return PreparedAssistantAction.ready(
      action: action,
      sessionLease: lease,
      handoffKind: AssistantActionHandoffKind.campusPage,
      title: action.title,
      summary: '打开校园页面',
    );
  }

  PreparedAssistantAction _prepareAppTab(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final tab = switch (action.targetId) {
      'home' => AppTab.home,
      'mail' => AppTab.mail,
      'ispace' => AppTab.ispace,
      'schedule' => AppTab.schedule,
      'user' => AppTab.user,
      _ => null,
    };
    if (tab == null) {
      throw const AiAssistantActionException('小U返回了无效的应用页面。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.appTab,
      title: action.title,
      summary: '切换到应用内现有页面。',
      sessionLease: lease,
      appTab: tab,
    );
  }

  PreparedAssistantAction _prepareOfficialSystem(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final (title, rawUrl) = switch (action.targetId) {
      'portal' => ('BNBU Portal', AppConfig.bnbuPortalBaseUrl),
      'mis' => ('BNBU MIS', AppConfig.bnbuMisBaseUrl),
      _ => throw const AiAssistantActionException('小U返回了无效的学校系统。'),
    };
    final Uri uri;
    try {
      uri = OfficialUrlPolicy.requireTrustedPageUrl(rawUrl);
    } on FormatException {
      throw const AiAssistantActionException('学校系统地址配置无效。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.officialPage,
      title: title,
      summary: '将在 App 内安全打开并使用当前学校登录会话。',
      sessionLease: lease,
      officialUri: uri,
      officialTitle: title,
    );
  }

  PreparedAssistantAction _prepareOpenMail(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    _validatedMailIdentity(action);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.mailDetail,
      title: action.title,
      summary: '将按 mailbox、UID 和 UIDVALIDITY 重新读取邮件。',
      sessionLease: lease,
    );
  }

  PreparedAssistantAction _prepareCampusPlace(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final query = _limit(action.placeQuery, 160);
    if (query.isEmpty) {
      throw const AiAssistantActionException('小U没有提供要打开的校园地点。');
    }
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.campusPlace,
      title: action.title,
      summary: query,
      sessionLease: lease,
      campusPlaceQuery: query,
    );
  }

  PreparedAssistantAction _prepareTaCourse(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final controller = _taCourseController;
    if (controller == null) {
      throw const AiAssistantActionException('固定日程管理暂时不可用。');
    }

    if (action.type == AssistantActionType.openTaCourseManager) {
      return PreparedAssistantAction.ready(
        action: action,
        handoffKind: AssistantActionHandoffKind.taCourseManager,
        title: '打开 固定日程管理',
        summary: '将在原生 固定日程管理页继续操作。',
        sessionLease: lease,
        taCourseIntent: AssistantTaCourseIntent(
          kind: AssistantTaCourseIntentKind.open,
          expectedCollectionRevision: controller.revision,
          targetIdentity: AssistantActionRuntime.taCourseCollectionIdentity(
            collectionRevision: controller.revision,
          ),
        ),
      );
    }

    final expectedCollectionRevision = action.taExpectedCollectionRevision;
    if (expectedCollectionRevision == null ||
        expectedCollectionRevision != controller.revision) {
      throw const AiAssistantActionException('固定日程列表已更新，请重新询问小U。');
    }

    if (action.type == AssistantActionType.addTaCourse) {
      final expectedIdentity =
          AssistantActionRuntime.taCourseCollectionIdentity(
            collectionRevision: controller.revision,
          );
      if (action.targetIdentity != expectedIdentity) {
        throw const AiAssistantActionException('固定日程列表已更新，请重新询问小U。');
      }
      final draft = _taEntryFromAction(
        action,
        id: TaCourseEntry.createId(),
        revision: 0,
      );
      return PreparedAssistantAction.ready(
        action: action,
        handoffKind: AssistantActionHandoffKind.taCourseManager,
        title: '新增日程',
        summary: '${draft.displayTitle} · ${draft.timeRangeLabel}',
        previewFields: _taPreviewFields(draft),
        sessionLease: lease,
        taCourseIntent: AssistantTaCourseIntent(
          kind: AssistantTaCourseIntentKind.add,
          entry: draft,
          expectedCollectionRevision: expectedCollectionRevision,
          targetIdentity: expectedIdentity,
        ),
      );
    }

    final matches = controller.entries.where(
      (entry) => entry.id == action.targetId,
    );
    if (matches.length != 1) {
      throw const AiAssistantActionException('没有找到对应的 日程。');
    }
    final liveEntry = matches.single;
    final expectedEntryRevision = action.taExpectedEntryRevision;
    final expectedIdentity = AssistantActionRuntime.taCourseEntryIdentity(
      entry: liveEntry,
      collectionRevision: controller.revision,
    );
    if (expectedEntryRevision == null ||
        expectedEntryRevision != liveEntry.revision ||
        action.targetIdentity != expectedIdentity) {
      throw const AiAssistantActionException('这条 日程已更新，请重新询问小U。');
    }

    if (action.type == AssistantActionType.deleteTaCourse) {
      return PreparedAssistantAction.ready(
        action: action,
        handoffKind: AssistantActionHandoffKind.taCourseManager,
        title: '删除日程',
        summary: '${liveEntry.displayTitle} · ${liveEntry.timeRangeLabel}',
        previewFields: _taPreviewFields(liveEntry),
        sessionLease: lease,
        taCourseIntent: AssistantTaCourseIntent(
          kind: AssistantTaCourseIntentKind.delete,
          entry: liveEntry,
          expectedEntryRevision: expectedEntryRevision,
          expectedCollectionRevision: expectedCollectionRevision,
          targetIdentity: expectedIdentity,
        ),
      );
    }

    final draft = _taEntryFromAction(
      action,
      id: liveEntry.id,
      revision: liveEntry.revision,
    ).copyWith(activeWeekStarts: liveEntry.activeWeekStarts);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.taCourseManager,
      title: '编辑日程',
      summary: '${draft.displayTitle} · ${draft.timeRangeLabel}',
      previewFields: _taPreviewFields(draft),
      sessionLease: lease,
      taCourseIntent: AssistantTaCourseIntent(
        kind: AssistantTaCourseIntentKind.update,
        entry: draft,
        expectedEntryRevision: expectedEntryRevision,
        expectedCollectionRevision: expectedCollectionRevision,
        targetIdentity: expectedIdentity,
      ),
    );
  }

  PreparedAssistantAction _prepareNotification(
    AssistantAction action,
    AppSessionLease lease,
  ) {
    final title = action.notificationTitle.trim();
    final body = action.notificationBody.trim();
    final scheduledAt = action.notificationAt?.toLocal();
    if (title.isEmpty || body.isEmpty || scheduledAt == null) {
      throw const AiAssistantActionException('提醒信息不完整，请让小U重新生成。');
    }
    if (title.length > 160 || body.length > 1000) {
      throw const AiAssistantActionException('提醒内容过长，请精简后重试。');
    }
    final now = _now();
    if (!scheduledAt.isAfter(now.add(const Duration(minutes: 1)))) {
      throw const AiAssistantActionException('提醒时间必须至少晚于现在 1 分钟。');
    }
    if (scheduledAt.isAfter(now.add(const Duration(days: 366)))) {
      throw const AiAssistantActionException('提醒时间不能超过未来 366 天。');
    }
    final timeLabel = _localizations.formatFullDateTime(scheduledAt);
    return PreparedAssistantAction.ready(
      action: action,
      handoffKind: AssistantActionHandoffKind.localNotification,
      title: action.title,
      summary: '将在 $timeLabel 发送本地提醒',
      sessionLease: lease,
      notificationTitle: title,
      notificationBody: body,
      notificationAt: scheduledAt,
      previewFields: [
        AssistantActionPreviewField(
          key: 'notification_title',
          label: '提醒标题',
          value: title,
          editable: false,
        ),
        AssistantActionPreviewField(
          key: 'notification_body',
          label: '提醒内容',
          value: body,
          editable: false,
        ),
        AssistantActionPreviewField(
          key: 'notification_at',
          label: '提醒时间',
          value: timeLabel,
          editable: false,
        ),
      ],
    );
  }

  Future<PreparedAssistantAction> _prepareIspaceMutation(
    AssistantAction action,
    AppSessionLease lease,
  ) async {
    final expectedIdentity = AssistantActionRuntime.moodleModuleIdentity(
      action.targetId,
    );
    if (action.targetIdentity != expectedIdentity) {
      throw const AiAssistantActionException('iSpace 课程模块已变化，请重新询问小U。');
    }
    if (action.type == AssistantActionType.setIspaceCompletion) {
      final completed = action.ispaceCompleted;
      if (completed == null || action.choiceOptionIds.isNotEmpty) {
        throw const AiAssistantActionException('小U返回的完成状态无效。');
      }
      await _controller.assistantModuleCompletionState(action.targetId);
      if (!lease.isActive) {
        return PreparedAssistantAction.stale(action: action);
      }
      return PreparedAssistantAction.ready(
        action: action,
        handoffKind: AssistantActionHandoffKind.ispaceMutation,
        title: action.title,
        summary: completed ? '标记为完成' : '标记为未完成',
        sessionLease: lease,
        previewFields: [
          AssistantActionPreviewField(
            key: 'ispace_completed',
            label: '完成状态',
            value: completed ? '完成' : '未完成',
            editable: false,
          ),
        ],
      );
    }

    if (action.type == AssistantActionType.submitIspaceChoice) {
      final optionIds = action.choiceOptionIds
          .map(int.tryParse)
          .whereType<int>()
          .toList(growable: false);
      if (optionIds.isEmpty ||
          optionIds.length != action.choiceOptionIds.length ||
          optionIds.toSet().length != optionIds.length) {
        throw const AiAssistantActionException('小U返回的 Choice 选项无效。');
      }
      final access = await _controller.loadAssistantModuleAccess(
        action.targetId,
      );
      if (!lease.isActive) {
        return PreparedAssistantAction.stale(action: action);
      }
      final selectable = {
        for (final option in access.choiceOptions)
          if (!option.disabled) option.id: option.label,
      };
      if (!access.canWrite || !optionIds.every(selectable.containsKey)) {
        throw const AiAssistantActionException('该 Choice 当前不允许提交所选选项。');
      }
      if (!access.choiceAllowMultiple && optionIds.length != 1) {
        throw const AiAssistantActionException('该 Choice 当前只允许选择一个选项。');
      }
      return PreparedAssistantAction.ready(
        action: action,
        handoffKind: AssistantActionHandoffKind.ispaceMutation,
        title: action.title,
        summary: optionIds.map((id) => selectable[id]!).join('、'),
        sessionLease: lease,
        previewFields: [
          AssistantActionPreviewField(
            key: 'choice_option_ids',
            label: 'Choice 选项',
            value: optionIds.map((id) => selectable[id]!).join('、'),
            editable: false,
          ),
        ],
      );
    }
    throw const AiAssistantActionException('iSpace 操作类型无效。');
  }

  TaCourseEntry _taEntryFromAction(
    AssistantAction action, {
    required String id,
    required int revision,
  }) {
    final title = _limit(action.taTitle, 160);
    final location = _limit(action.taLocation, 160);
    final weekday = action.taWeekday;
    final startMinutes = action.taStartMinutes;
    final endMinutes = action.taEndMinutes;
    final repeatType = switch (action.taRepeatType) {
      'weekly' => TaCourseRepeatType.weekly,
      'singleWeek' => TaCourseRepeatType.singleWeek,
      _ => null,
    };
    if (title.isEmpty ||
        weekday == null ||
        weekday < 1 ||
        weekday > 7 ||
        startMinutes == null ||
        startMinutes < 0 ||
        startMinutes >= 24 * 60 ||
        endMinutes == null ||
        endMinutes <= startMinutes ||
        endMinutes > 24 * 60 ||
        repeatType == null ||
        (repeatType == TaCourseRepeatType.singleWeek &&
            action.taWeekStart == null)) {
      throw const AiAssistantActionException('小U返回的 日程草稿格式无效。');
    }
    final isTa = action.scheduleKind == 'ta';
    if (!isTa && action.scheduleCourseKey.isNotEmpty) {
      throw const AiAssistantActionException('普通日程不能携带课程关联。');
    }
    if (!['', 'schedule', 'ta'].contains(action.scheduleKind)) {
      throw const AiAssistantActionException('请重新生成固定日程。');
    }
    final timetable = _taCourseController?.timetable;
    final candidates = timetable?.courses
        .where(
          (course) =>
              TaCourseEntry.bindingKey(timetable, course) ==
              action.scheduleCourseKey,
        )
        .toList();
    if (isTa && (candidates == null || candidates.length != 1)) {
      throw const AiAssistantActionException('请选择真实的所属课程。');
    }
    final course = isTa ? candidates!.single : null;
    return TaCourseEntry(
      kind: isTa ? FixedScheduleKind.ta : FixedScheduleKind.schedule,
      courseKey: isTa ? action.scheduleCourseKey : '',
      courseCode: course?.code ?? '',
      semesterId: isTa ? timetable!.selectedSemesterId : '',

      id: id,
      title: course?.name ?? title,
      location: location,
      weekday: weekday,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      repeatType: repeatType,
      weekStart: repeatType == TaCourseRepeatType.singleWeek
          ? TaCourseEntry.normalizeWeekStart(action.taWeekStart!.toLocal())
          : null,
      revision: revision,
    );
  }

  List<AssistantActionPreviewField> _taPreviewFields(TaCourseEntry entry) {
    return [
      AssistantActionPreviewField(
        key: 'schedule_kind',
        label: '类型',
        value: entry.kindLabel,
        editable: true,
      ),
      AssistantActionPreviewField(
        key: 'ta_title',
        label: '名称',
        value: entry.displayTitle,
        editable: true,
        maxLength: 160,
      ),
      AssistantActionPreviewField(
        key: 'ta_location',
        label: '地点',
        value: entry.displayLocation,
        editable: true,
        maxLength: 160,
      ),
      AssistantActionPreviewField(
        key: 'ta_time',
        label: '时间',
        value: '星期${entry.weekday} ${entry.timeRangeLabel}',
        editable: true,
      ),
      AssistantActionPreviewField(
        key: 'ta_repeat_type',
        label: '重复',
        value: entry.repeatType == TaCourseRepeatType.weekly ? '每周' : '单周',
        editable: true,
      ),
    ];
  }

  Future<void> _handoff(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final lease = prepared.sessionLease;
    if (lease == null || !lease.isActive || !navigator.mounted) {
      await prepared.mailService?.close();
      return;
    }

    switch (prepared.handoffKind) {
      case AssistantActionHandoffKind.directoryEntry:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'CampusDirectoryPage'),
              builder: (_) => CampusDirectoryPage(
                controller: _controller,
                initialOrganizationId: prepared.action.targetId,
              ),
            ),
          ),
        );
        onActionOutcome?.call(prepared.action, 'opened');
        return;
      case AssistantActionHandoffKind.meLifeEntry:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        final id = prepared.action.targetId;
        if (id.isNotEmpty &&
            !_meLifeStore.catalog!.landmarks.any((item) => item.id == id)) {
          throw const AiAssistantActionException('该条目已更新或下架，请重新询问小U。');
        }
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              settings: RouteSettings(
                name: id.isEmpty
                    ? 'CampusLandmarksPage'
                    : 'CampusLandmarkDetailPage',
              ),
              builder: (_) => id.isEmpty
                  ? CampusLandmarksPage(
                      store: _meLifeStore,
                      owner: lease.owner,
                      controller: _controller,
                    )
                  : CampusLandmarkDetailPage(
                      id: id,
                      store: _meLifeStore,
                      owner: lease.owner,
                      controller: _controller,
                    ),
            ),
          ),
        );
        onActionOutcome?.call(prepared.action, 'opened');
        return;
      case AssistantActionHandoffKind.campusPage:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        final action = prepared.action;
        if (action.targetId == 'schedule') {
          final shell = _rootShellController;
          if (shell == null) throw const AiAssistantActionException('课表暂时不可用。');
          shell.openScheduleView(
            date: DateTime.tryParse(action.scheduleDate),
            view: action.scheduleView,
          );
          onActionOutcome?.call(action, 'opened');
          return;
        }
        final Widget page;
        switch (action.targetId) {
          case 'academic_calendar':
          case 'class_schedule':
            page = AcademicCalendarPage(
              initialDocumentIndex: action.targetId == 'class_schedule' ? 1 : 0,
            );
          case 'ecard':
            page = StudentEcardPage(
              controller: _controller,
              onGoToUser: () => _rootShellController?.selectTab(AppTab.user),
            );
          case 'leave':
            page = LeaveApplicationPage(
              controller: _controller,
              onReturnHome: () => _rootShellController?.selectTab(AppTab.home),
            );
          default:
            throw const AiAssistantActionException('校园页面无效。');
        }
        await navigator.push<void>(
          MaterialPageRoute<void>(builder: (_) => page),
        );
        if (lease.isActive) onActionOutcome?.call(action, 'opened');
        return;
      case AssistantActionHandoffKind.appTab:
        await _prepareRootNavigation();
        if (!lease.isActive) return;
        final shellController = _rootShellController;
        if (shellController == null) {
          throw const AiAssistantActionException('应用页面导航暂时不可用。');
        }
        shellController.selectTab(prepared.appTab!);
        return;
      case AssistantActionHandoffKind.mailCompose:
        await _handoffComposeMail(navigator, prepared);
        return;
      case AssistantActionHandoffKind.assignmentOnlineText:
        await _handoffAssignmentSubmission(navigator, prepared);
        return;
      case AssistantActionHandoffKind.officialPage:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        await navigator.push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'OfficialWebPage'),
            builder: (_) => OfficialWebPage(
              controller: _controller,
              title: prepared.officialTitle,
              url: prepared.officialUri!.toString(),
            ),
          ),
        );
        return;
      case AssistantActionHandoffKind.assignmentDetail:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        await navigator.push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'TimelineDetailPage'),
            builder: (_) => TimelineDetailPage(
              controller: _controller,
              item: prepared.timelineItem!,
            ),
          ),
        );
        return;
      case AssistantActionHandoffKind.assignmentFileUpload:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        await navigator.push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'TimelineDetailPage'),
            builder: (_) => TimelineDetailPage(
              controller: _controller,
              item: prepared.timelineItem!,
              initialDetail: prepared.timelineDetail,
              initialFileUploadIntent: prepared.assignmentFiles.isEmpty,
              initialUploadFiles: prepared.assignmentFiles,
              onAssignmentOutcome: (status) {
                if (lease.isActive) {
                  onActionOutcome?.call(prepared.action, status);
                }
              },
            ),
          ),
        );
        return;
      case AssistantActionHandoffKind.courseDetail:
        if (prepared.action.type == AssistantActionType.prepareCoursePack) {
          _showMessage(navigator, prepared.summary);
        }
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        await navigator.push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'CourseDetailPage'),
            builder: (_) => CourseDetailPage(
              controller: _controller,
              course: prepared.course!,
            ),
          ),
        );
        return;
      case AssistantActionHandoffKind.courseBatchDownload:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        await navigator.push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'CourseDetailPage'),
            builder: (_) => CourseDetailPage(
              controller: _controller,
              course: prepared.course!,
              initialBatchDownloadIntent: true,
              initialBatchFileScope:
                  prepared.action.courseFileScope ??
                  AssistantCourseFileScope.all,
            ),
          ),
        );
        return;
      case AssistantActionHandoffKind.mailDetail:
        await _handoffOpenMail(navigator, prepared);
        return;
      case AssistantActionHandoffKind.mailAttachment:
        await _handoffMailAttachment(navigator, prepared);
        return;
      case AssistantActionHandoffKind.mailMutation:
        await _handoffMailMutation(prepared);
        return;
      case AssistantActionHandoffKind.campusPlace:
        await _prepareRootNavigation();
        if (!navigator.mounted || !lease.isActive) return;
        await navigator.push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'CampusNavigationPage'),
            builder: (_) => CampusNavigationPage(
              initialQuery: prepared.campusPlaceQuery,
              owner: lease.owner,
            ),
          ),
        );
        return;
      case AssistantActionHandoffKind.taCourseManager:
        await _handoffTaCourseManager(navigator, prepared);
        return;
      case AssistantActionHandoffKind.localNotification:
        final error = await _controller.scheduleAssistantReminder(
          title: prepared.notificationTitle,
          body: prepared.notificationBody,
          scheduledAt: prepared.notificationAt!,
        );
        if (error != null) {
          throw AiAssistantActionException(error);
        }
        if (navigator.mounted && lease.isActive) {
          _showMessage(navigator, '提醒已设置');
          onActionOutcome?.call(prepared.action, 'reminder_scheduled');
        }
        return;
      case AssistantActionHandoffKind.quizMutation:
        await _handoffQuizMutation(navigator, prepared);
        return;
      case AssistantActionHandoffKind.ispaceMutation:
        await _handoffIspaceMutation(navigator, prepared);
        return;
      case AssistantActionHandoffKind.none:
        return;
    }
  }

  Future<void> _handoffQuizMutation(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final lease = prepared.sessionLease!;
    switch (prepared.action.type) {
      case AssistantActionType.startQuizAttempt:
        await _controller.startQuizAttempt(prepared.timelineItem!);
        if (navigator.mounted && lease.isActive) {
          _showMessage(navigator, 'Quiz 已开始，可继续让小U读取题目');
        }
        return;
      case AssistantActionType.saveQuizAnswers:
        await _controller.saveQuizAttempt(
          snapshot: prepared.quizSnapshot!,
          answers: prepared.quizAnswers,
        );
        if (navigator.mounted && lease.isActive) {
          _showMessage(navigator, 'Quiz 答案已保存，尚未交卷');
        }
        return;
      case AssistantActionType.submitQuizAttempt:
        await _controller.finishQuizAttempt(
          snapshot: prepared.quizSnapshot!,
          answers: prepared.quizAnswers,
        );
        if (navigator.mounted && lease.isActive) {
          _showMessage(navigator, 'Quiz 已最终提交');
        }
        return;
      default:
        throw const AiAssistantActionException('Quiz 操作类型无效。');
    }
  }

  Future<void> _handoffIspaceMutation(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final lease = prepared.sessionLease!;
    final action = prepared.action;
    if (action.type == AssistantActionType.setIspaceCompletion) {
      await _controller.setAssistantModuleCompletion(
        moduleRef: action.targetId,
        completed: action.ispaceCompleted!,
      );
      if (navigator.mounted && lease.isActive) {
        _showMessage(navigator, action.ispaceCompleted! ? '已标记为完成' : '已标记为未完成');
      }
      return;
    }
    if (action.type == AssistantActionType.submitIspaceChoice) {
      await _controller.submitAssistantChoice(
        moduleRef: action.targetId,
        optionIds: action.choiceOptionIds.map(int.parse).toList(),
      );
      if (navigator.mounted && lease.isActive) {
        _showMessage(navigator, 'Choice 已提交');
      }
      return;
    }
    throw const AiAssistantActionException('iSpace 操作类型无效。');
  }

  Future<void> _handoffComposeMail(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final lease = prepared.sessionLease!;
    await _prepareRootNavigation();
    if (!navigator.mounted || !lease.isActive) {
      return;
    }
    final service = _mailServiceFactory();
    var handedOff = false;
    var finalOutcome = 'cancelled';
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'ComposeMailPage'),
          builder: (_) => ComposeMailPage(
            senderDisplayName: mailSenderDisplayName(_controller),
            mailService: service,
            credentials: prepared.mailCredentials!,
            replyTo:
                prepared.action.mailMode == 'forward' ||
                    prepared.action.mailMode == 'draft'
                ? null
                : prepared.mailDetail,
            draftDetail: prepared.action.mailMode == 'draft'
                ? prepared.mailDetail
                : null,
            replyAll: prepared.action.mailMode == 'reply_all',
            onOutcome: (status) {
              finalOutcome = status;
              if (lease.isActive) {
                onActionOutcome?.call(prepared.action, status);
              }
            },
            onSent: () {
              finalOutcome = 'sent';
              if (lease.isActive) {
                onActionOutcome?.call(prepared.action, 'sent');
              }
            },
            initialRecipient: prepared.mailRecipient,
            initialSubject: prepared.mailSubject,
            initialBody:
                prepared.action.mailMode == 'forward' &&
                    prepared.mailDetail != null
                ? MailForwardContent.plainText(
                    prepared.mailDetail!,
                    _forwardedTimeLabel(prepared.mailDetail!),
                    leadingText: prepared.mailBody,
                  )
                : prepared.mailBody,
            initialHtmlBody:
                prepared.action.mailMode == 'forward' &&
                    prepared.mailDetail != null
                ? MailForwardContent.html(
                    prepared.mailDetail!,
                    _forwardedTimeLabel(prepared.mailDetail!),
                    leadingText: prepared.mailBody,
                  )
                : null,
            closeMailServiceOnDispose: true,
            autoSaveDrafts: false,
            assistantPrepared: true,
          ),
        ),
      );
      handedOff = true;
      if (lease.isActive && finalOutcome == 'cancelled') {
        onActionOutcome?.call(prepared.action, 'cancelled');
      }
    } finally {
      if (!handedOff) {
        await service.close();
      }
    }
  }

  String _forwardedTimeLabel(MailMessageDetail detail) {
    final sentAt = detail.date;
    if (sentAt == null) return '未知时间';
    return _localizations
        .dateTimeFormatter(fullMonth: true)
        .format(mailDisplayDate(sentAt));
  }

  Future<void> _handoffAssignmentSubmission(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final lease = prepared.sessionLease!;
    await _prepareRootNavigation();
    if (!navigator.mounted || !lease.isActive) {
      return;
    }
    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'TimelineDetailPage'),
        builder: (_) => TimelineDetailPage(
          controller: _controller,
          item: prepared.timelineItem!,
          initialDetail: prepared.timelineDetail,
          initialOnlineTextDraft: prepared.assignmentDraft,
          onAssignmentOutcome: (status) {
            if (lease.isActive) onActionOutcome?.call(prepared.action, status);
          },
        ),
      ),
    );
  }

  Future<void> _handoffTaCourseManager(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final lease = prepared.sessionLease!;
    final controller = _taCourseController;
    if (controller == null) {
      throw const AiAssistantActionException('固定日程管理暂时不可用。');
    }
    await _prepareRootNavigation();
    if (!navigator.mounted || !lease.isActive) {
      return;
    }
    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'TaCourseManagerPage'),
        builder: (_) => TaCourseManagerPage(
          controller: controller,
          initialAssistantIntent: prepared.taCourseIntent,
        ),
      ),
    );
  }

  Future<void> _handoffMailMutation(PreparedAssistantAction prepared) async {
    final lease = prepared.sessionLease!;
    final shellController = _rootShellController;
    final intentController = _mailIntentController;
    if (shellController == null || intentController == null) {
      throw const AiAssistantActionException('原生邮箱操作暂时不可用。');
    }
    await _prepareRootNavigation();
    if (!lease.isActive) return;
    intentController.publish(prepared.mailIntent!);
    shellController.selectTab(AppTab.mail);
  }

  Future<void> _handoffMailAttachment(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final action = prepared.action;
    final lease = prepared.sessionLease!;
    final (folder, uid, mailboxUidValidity) = _validatedMailFields(action);
    final partId = action.mailPartId.trim();
    final attachmentName = action.attachmentName.trim();

    await _prepareRootNavigation();
    if (!navigator.mounted || !lease.isActive) return;
    final credentials = await _controller.loadMailAccessCredentials();
    if (!lease.isActive) return;
    if (credentials == null) {
      throw const AiAssistantActionException('当前登录状态无法读取邮箱。');
    }
    final service = _mailServiceFactory();
    try {
      final detail = await service.readMessage(
        credentials: credentials,
        folder: folder,
        uid: uid,
        expectedMailboxUidValidity: mailboxUidValidity,
      );
      if (!lease.isActive) return;
      if (detail.uid != uid ||
          detail.folder != folder ||
          detail.mailboxUidValidity != mailboxUidValidity) {
        throw const AiAssistantActionException('邮件引用已失效，请刷新邮箱后重试。');
      }
      final attachments = detail.attachments.where(
        (attachment) =>
            attachment.partId?.trim() == partId &&
            attachment.name.trim() == attachmentName,
      );
      if (attachments.length != 1) {
        throw const AiAssistantActionException('附件已变化，请重新打开邮件后再试。');
      }
      if (!navigator.mounted || !lease.isActive) return;
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'MailDetailPage'),
          builder: (_) => MailDetailPage(
            senderDisplayName: mailSenderDisplayName(_controller),
            detail: detail,
            timeFormat: _localizations.dateTimeFormatter(fullMonth: true),
            onReply: () {
              if (!lease.isActive || !navigator.mounted) {
                return;
              }
              navigator.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ComposeMailPage(
                    senderDisplayName: mailSenderDisplayName(_controller),
                    mailService: service,
                    credentials: credentials,
                    replyTo: detail,
                  ),
                ),
              );
            },
            mailService: service,
            credentials: credentials,
            attachmentStore: const IoMailAttachmentStore(),
            onAttachmentSaved: (savedPart) {
              if (lease.isActive && savedPart == partId) {
                onActionOutcome?.call(prepared.action, 'downloaded');
              }
            },
            initialAttachmentPartId: partId,
            initialAttachmentName: attachmentName,
          ),
        ),
      );
    } finally {
      await service.close();
    }
  }

  Future<void> _handoffOpenMail(
    NavigatorState navigator,
    PreparedAssistantAction prepared,
  ) async {
    final action = prepared.action;
    final lease = prepared.sessionLease!;
    final (folder, uid, mailboxUidValidity) = _validatedMailIdentity(action);

    await _prepareRootNavigation();
    if (!navigator.mounted || !lease.isActive) {
      return;
    }
    final credentials = await _controller.loadMailAccessCredentials();
    if (!lease.isActive) {
      return;
    }
    if (credentials == null) {
      throw const AiAssistantActionException('当前登录状态无法读取邮箱。');
    }
    final service = _mailServiceFactory();
    try {
      final detail = await service.readMessage(
        credentials: credentials,
        folder: folder,
        uid: uid,
        expectedMailboxUidValidity: mailboxUidValidity,
      );
      if (!lease.isActive) {
        return;
      }
      if (detail.uid != uid ||
          detail.folder != folder ||
          detail.mailboxUidValidity != mailboxUidValidity) {
        throw const AiAssistantActionException('邮件引用已失效，请刷新邮箱后重试。');
      }
      if (!navigator.mounted || !lease.isActive) {
        return;
      }
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'MailDetailPage'),
          builder: (_) => MailDetailPage(
            senderDisplayName: mailSenderDisplayName(_controller),
            detail: detail,
            timeFormat: _localizations.dateTimeFormatter(fullMonth: true),
            onReply: () {
              if (!lease.isActive || !navigator.mounted) {
                return;
              }
              navigator.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ComposeMailPage(
                    senderDisplayName: mailSenderDisplayName(_controller),
                    mailService: service,
                    credentials: credentials,
                    replyTo: detail,
                  ),
                ),
              );
            },
            mailService: service,
            credentials: credentials,
            attachmentStore: const IoMailAttachmentStore(),
          ),
        ),
      );
    } finally {
      await service.close();
    }
  }

  AppSessionLease _validatedLease(AssistantAction action) {
    final lease = _controller.captureSessionLease();
    if (lease == null || !lease.isActive) {
      throw const AiAssistantActionException('当前登录状态无法执行该操作。');
    }
    if (AssistantActionRuntime.actionExpired(action, _now())) {
      throw const AiAssistantActionException('这个小U操作已过期，请重新询问。');
    }
    if (!AssistantActionRuntime.actionBelongsToLease(action, lease)) {
      throw const AiAssistantActionException('这个小U操作不属于当前登录账号，已阻止执行。');
    }
    return lease;
  }

  Future<TimelineItem> _validatedTimelineItem(AssistantAction action) async {
    if (_isModuleRef(action.targetId)) {
      if (action.targetIdentity !=
          AssistantActionRuntime.moodleModuleIdentity(action.targetId)) {
        throw const AiAssistantActionException('这个 iSpace 模块已更新，请重新读取后重试。');
      }
      try {
        return await _controller.resolveAssistantModuleTimelineItem(
          action.targetId,
        );
      } on MoodleApiException {
        throw const AiAssistantActionException('没有找到对应的 iSpace 课程模块。');
      }
    }
    final id = int.tryParse(action.targetId);
    final matches = _controller.timelineItems.where((item) => item.id == id);
    if (matches.isEmpty) {
      throw const AiAssistantActionException('没有找到对应的 DDL 或作业。');
    }
    final item = matches.first;
    if (action.targetIdentity.trim().isEmpty ||
        action.targetIdentity !=
            AssistantActionRuntime.timelineIdentity(item)) {
      throw const AiAssistantActionException('这个 DDL 或作业已更新，请刷新后重试。');
    }
    return item;
  }

  bool _isModuleRef(String value) => RegExp(
    r'^m1:[1-9][0-9]{0,19}:[1-9][0-9]{0,19}:'
    r'[1-9][0-9]{0,19}:[a-z][a-z0-9_]{0,79}$',
  ).hasMatch(value.trim());

  CourseSummary _validatedCourse(AssistantAction action) {
    final id = int.tryParse(action.targetId);
    final matches = _controller.courses.where((course) => course.id == id);
    if (matches.isEmpty) {
      throw const AiAssistantActionException('没有找到对应课程。');
    }
    final course = matches.first;
    if (action.targetIdentity.trim().isEmpty ||
        action.targetIdentity !=
            AssistantActionRuntime.courseIdentity(course)) {
      throw const AiAssistantActionException('这个课程引用已更新，请刷新后重试。');
    }
    return course;
  }

  (MailFolder, int, int) _validatedMailFields(AssistantAction action) {
    final uid = action.mailUid;
    final mailboxUidValidity = action.mailboxUidValidity;
    final folders = MailFolder.values.where(
      (folder) => folder.name == action.mailFolder,
    );
    if (uid == null ||
        uid <= 0 ||
        mailboxUidValidity == null ||
        mailboxUidValidity <= 0 ||
        folders.length != 1) {
      throw const AiAssistantActionException('邮件引用已失效，请刷新邮箱后重试。');
    }
    return (folders.single, uid, mailboxUidValidity);
  }

  (MailFolder, int, int) _validatedMailIdentity(AssistantAction action) {
    final (folder, uid, mailboxUidValidity) = _validatedMailFields(action);
    final identity = AssistantActionRuntime.mailIdentity(
      folder: folder,
      uid: uid,
      mailboxUidValidity: mailboxUidValidity,
    );
    if (action.targetIdentity.trim().isEmpty ||
        action.targetIdentity != identity) {
      throw const AiAssistantActionException('邮件引用已失效，请刷新邮箱后重试。');
    }
    return (folder, uid, mailboxUidValidity);
  }

  void _validateConfirmationDeclaration(
    AssistantAction action,
    AssistantToolDefinition definition,
  ) {
    if (definition.requiresConfirmation && !action.requiresConfirmation) {
      throw const AiAssistantActionException('小U返回了未声明确认要求的操作，已阻止执行。');
    }
  }

  Future<void> _prepareRootNavigation() async {
    await _beforeNavigation?.call();
  }

  void _showMessage(NavigatorState navigator, String message) {
    final overlay = navigator.overlay;
    if (overlay == null) return;
    BnbuToast.showInOverlay(overlay, message);
  }

  bool _isOfficialEmail(String value) {
    final parts = value.split('@');
    if (parts.length != 2 ||
        !RegExp(r'^[a-z0-9._%+-]{1,64}$').hasMatch(parts.first)) {
      return false;
    }
    final domain = parts.last;
    return domain == 'bnbu.edu.cn' || domain.endsWith('.bnbu.edu.cn');
  }

  String _limit(String value, int maxLength) {
    final normalized = value.trim();
    return normalized.length <= maxLength
        ? normalized
        : normalized.substring(0, maxLength);
  }
}

class AiAssistantActionException implements Exception {
  const AiAssistantActionException(this.message);

  final String message;

  @override
  String toString() => message;
}
