import 'assistant/assistant_client_tool_catalog.dart';
import '../models/assistant_models.dart';
import '../models/mail_models.dart';
import '../state/app_session_controller.dart';
import 'assistant/assistant_mail_content_reader.dart';
import 'assistant_context_builder.dart';
import 'assistant_location_service.dart';

class AssistantContextToolExecutor {
  const AssistantContextToolExecutor({
    required AssistantContextBuilder contextBuilder,
    required AppSessionController sessionController,
    required AssistantLocationService locationService,
    AssistantMailContentReader? mailContentReader,
    this.mailRadarReader,
    void Function(AssistantIspaceCatalogDiagnostics diagnostics)?
    onIspaceCatalogDiagnostics,
  }) : _contextBuilder = contextBuilder,
       _sessionController = sessionController,
       _locationService = locationService,
       _mailContentReader = mailContentReader,
       _onIspaceCatalogDiagnostics = onIspaceCatalogDiagnostics;

  final Future<AssistantMailToolResultContext> Function(Map<String, dynamic>)?
  mailRadarReader;
  final AssistantContextBuilder _contextBuilder;
  final AppSessionController _sessionController;
  final AssistantLocationService _locationService;
  final AssistantMailContentReader? _mailContentReader;
  final void Function(AssistantIspaceCatalogDiagnostics diagnostics)?
  _onIspaceCatalogDiagnostics;

  static const toolSources = assistantClientToolSources;

  static const noArgumentTools = <AssistantContextSource, String>{
    AssistantContextSource.academicProfile: 'get_academic_profile',
    AssistantContextSource.courses: 'get_courses',
    AssistantContextSource.termCourses: 'get_term_courses',
    AssistantContextSource.deadlines: 'get_deadlines',
    AssistantContextSource.schedule: 'get_schedule',
    AssistantContextSource.academicCalendar: 'get_academic_calendar',
    AssistantContextSource.examTimetable: 'get_exam_timetable',
    AssistantContextSource.mailSummaries: 'get_mail_summaries',
    AssistantContextSource.selectedMail: 'get_selected_mail',
    AssistantContextSource.schoolActivities: 'get_school_activities',
    AssistantContextSource.taCourses: 'get_ta_courses',
    AssistantContextSource.currentPage: 'get_current_page',
    AssistantContextSource.currentLocation: 'get_current_location',
  };

  Future<AssistantAgentToolResult> execute(
    AssistantAgentToolCall call, {
    required bool allowCurrentLocation,
    String requestMessage = '',
    String contextVersion = '3',
    Set<String> availableMailIdentities = const {},
    void Function(String progress)? onProgress,
  }) async {
    final clock = Stopwatch()..start();
    final source = toolSources[call.name];
    if (source == null) {
      throw const AiAssistantToolExecutionException('小U请求了客户端不支持的工具。');
    }
    if (source != AssistantContextSource.ispaceCourseCatalog &&
        source != AssistantContextSource.ispaceActivity &&
        source != AssistantContextSource.ispaceQuizAttempt &&
        source != AssistantContextSource.ispaceToolResults &&
        source != AssistantContextSource.mailToolResults &&
        call.name != 'read_academic_calendar_document' &&
        call.arguments.isNotEmpty) {
      throw const AiAssistantToolExecutionException('小U工具参数无效。');
    }
    onProgress?.call('小U正在调用「${_skillLabelFor(source)}」技能');

    if (source == AssistantContextSource.academicProfile ||
        source == AssistantContextSource.schedule ||
        source == AssistantContextSource.termCourses ||
        source == AssistantContextSource.examTimetable ||
        source == AssistantContextSource.taCourses &&
            _contextBuilder.fixedScheduleEnabled) {
      await _sessionController.ensureTimetableLoaded();
    }
    if (source == AssistantContextSource.schedule ||
        source == AssistantContextSource.taCourses) {
      final loadResult = await _contextBuilder.ensureTaCoursesLoaded();
      if (loadResult != null && !loadResult.isSuccess) {
        throw const AiAssistantToolExecutionException('本机固定日程暂时无法读取，请稍后重试。');
      }
    }
    if (source == AssistantContextSource.academicProfile &&
        !_contextBuilder.availableSources().contains(source)) {
      throw const AiAssistantToolExecutionException('课表中暂时没有可识别的专业信息。');
    }

    AssistantCurrentLocationContext? currentLocation;
    AssistantIspaceCourseCatalogContext? ispaceCourseCatalog;
    AssistantIspaceActivityContext? ispaceActivity;
    AssistantIspaceQuizAttemptContext? ispaceQuizAttempt;
    final ispaceToolResults = <AssistantIspaceToolResultContext>[];
    AssistantAcademicCalendarContext? academicCalendar;
    List<AssistantMailSummaryContext>? mailSummaries;
    final mailToolResults = <AssistantMailToolResultContext>[];
    if (source == AssistantContextSource.currentLocation) {
      if (!allowCurrentLocation) {
        throw const AiAssistantToolExecutionException(
          '这次问题没有明确请求当前位置，已拒绝定位工具。',
        );
      }
      currentLocation = await _locationService.currentLocation();
    } else if (source == AssistantContextSource.academicCalendar) {
      if (call.name == 'read_academic_calendar_document') {
        final kind = call.arguments['kind'];
        final offset = call.arguments['offset'] ?? 0;
        if (kind is! String ||
            !const {'academic_calendar', 'class_schedule'}.contains(kind) ||
            offset is! int ||
            offset < 0 ||
            call.arguments.keys.any(
              (key) => key != 'kind' && key != 'offset',
            )) {
          throw const AiAssistantToolExecutionException('校历正文参数无效。');
        }
        academicCalendar = await _contextBuilder.readAcademicCalendarDocument(
          kind,
          offset,
        );
      } else {
        academicCalendar = await _contextBuilder.loadAcademicCalendar();
      }
    } else if (source == AssistantContextSource.ispaceCourseCatalog) {
      final rawQuery = call.arguments['query'];
      if (rawQuery is! String ||
          rawQuery.trim().isEmpty ||
          rawQuery.trim().length > 300) {
        throw const AiAssistantToolExecutionException('小U课程目录工具参数无效。');
      }
      final includeDetails = call.arguments['include_details'];
      if (includeDetails != null && includeDetails is! bool) {
        throw const AiAssistantToolExecutionException('小U课程目录工具参数无效。');
      }
      final rawDetailLevel = call.arguments['detail_level'];
      final requestedDetailLevel = switch (rawDetailLevel) {
        null => null,
        'summary' => AssistantIspaceCatalogDetailLevel.summary,
        'aggregates' => AssistantIspaceCatalogDetailLevel.aggregates,
        'modules' => AssistantIspaceCatalogDetailLevel.modules,
        'files' => AssistantIspaceCatalogDetailLevel.files,
        'teachers' => AssistantIspaceCatalogDetailLevel.teachers,
        'full' => AssistantIspaceCatalogDetailLevel.full,
        _ => throw const AiAssistantToolExecutionException('小U课程目录工具参数无效。'),
      };
      final originalMessage = requestMessage.trim();
      final effectiveDetailLevel =
          originalMessage.isNotEmpty &&
              _contextBuilder.hasExplicitIspaceModuleCandidate(
                originalMessage,
              ) &&
              (requestedDetailLevel ==
                      AssistantIspaceCatalogDetailLevel.summary ||
                  requestedDetailLevel ==
                      AssistantIspaceCatalogDetailLevel.aggregates)
          ? AssistantIspaceCatalogDetailLevel.modules
          : requestedDetailLevel;
      final detailMessage = originalMessage.isEmpty
          ? rawQuery.trim()
          : '$originalMessage\n${rawQuery.trim()}';
      final effectiveIncludeDetails = effectiveDetailLevel == null
          ? includeDetails == true ||
                _contextBuilder.needsIspaceCourseDetails(detailMessage)
          : effectiveDetailLevel != AssistantIspaceCatalogDetailLevel.summary;
      ispaceCourseCatalog = await _contextBuilder.loadIspaceCourseCatalog(
        originalMessage.isNotEmpty &&
                _contextBuilder.hasExplicitIspaceCourseMatch(originalMessage)
            ? originalMessage
            : rawQuery.trim(),
        entityQuery: originalMessage,
        includeDetails: effectiveIncludeDetails,
        detailLevelOverride:
            effectiveDetailLevel ??
            _contextBuilder.ispaceCatalogDetailLevel(
              detailMessage,
              includeDetails: effectiveIncludeDetails,
            ),
        onDiagnostics: _onIspaceCatalogDiagnostics,
      );
    } else if (source == AssistantContextSource.ispaceActivity) {
      final rawItemId = call.arguments['item_id'];
      if (rawItemId is! String ||
          rawItemId.trim().isEmpty ||
          rawItemId.trim().length > 120 ||
          call.arguments.length != 1) {
        throw const AiAssistantToolExecutionException('小U活动详情工具参数无效。');
      }
      try {
        ispaceActivity = await _contextBuilder.loadIspaceActivity(
          rawItemId.trim(),
        );
      } catch (_) {
        throw const AiAssistantToolExecutionException(
          '该 iSpace 活动已变化，请重新读取活动索引。',
        );
      }
    } else if (source == AssistantContextSource.ispaceQuizAttempt) {
      final rawItemId = call.arguments['item_id'];
      if (rawItemId is! String ||
          rawItemId.trim().isEmpty ||
          rawItemId.trim().length > 120 ||
          call.arguments.length != 1) {
        throw const AiAssistantToolExecutionException('小U测验工具参数无效。');
      }
      try {
        ispaceQuizAttempt = await _contextBuilder.loadIspaceQuizAttempt(
          rawItemId.trim(),
        );
      } catch (_) {
        throw const AiAssistantToolExecutionException(
          '该 Quiz 状态已变化，请重新读取活动索引。',
        );
      }
    } else if (source == AssistantContextSource.ispaceToolResults) {
      if (contextVersion != '4' && contextVersion != '5') {
        throw const AiAssistantToolExecutionException('当前服务端不支持 iSpace 多结果工具。');
      }
      if (call.name == 'read_ispace_content') {
        final ref = call.arguments['module_ref'];
        final kind = call.arguments['kind'] ?? 'description';
        final offset = call.arguments['offset'] ?? 0;
        final itemId = call.arguments['item_id'] ?? 0;
        final page = call.arguments['page'] ?? 0;
        if (ref is! String ||
            kind is! String ||
            offset is! int ||
            offset < 0 ||
            itemId is! int ||
            itemId < 0 ||
            page is! int ||
            page < 0 ||
            !const {
              'description',
              'quiz',
              'files',
              'file',
              'discussion',
            }.contains(kind) ||
            call.arguments.keys.any(
              (key) => !const {
                'module_ref',
                'kind',
                'offset',
                'item_id',
                'page',
              }.contains(key),
            )) {
          throw const AiAssistantToolExecutionException('小U正文读取参数无效。');
        }
        ispaceToolResults.add(
          await _contextBuilder.readIspaceContent(
            ref,
            kind: kind,
            offset: offset,
            itemId: itemId,
            page: page,
          ),
        );
      } else if (call.name == 'get_ispace_module') {
        final moduleRef = call.arguments['module_ref'];
        if (moduleRef is! String ||
            !RegExp(
              r'^m1:[1-9][0-9]{0,19}:[1-9][0-9]{0,19}:'
              r'[1-9][0-9]{0,19}:[a-z][a-z0-9_]{0,79}$',
            ).hasMatch(moduleRef) ||
            call.arguments.length != 1) {
          throw const AiAssistantToolExecutionException('小U课程模块工具参数无效。');
        }
        ispaceToolResults.add(
          await _contextBuilder.loadIspaceModule(
            moduleRef,
            includeContent: contextVersion == '5',
          ),
        );
      } else if (call.name == 'get_ispace_course_grades') {
        final courseId = call.arguments['course_id'];
        if (courseId is! String ||
            !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(courseId) ||
            call.arguments.length != 1) {
          throw const AiAssistantToolExecutionException('小U课程成绩工具参数无效。');
        }
        ispaceToolResults.add(
          await _contextBuilder.loadIspaceCourseGrades(courseId),
        );
      } else {
        throw const AiAssistantToolExecutionException('小U请求了未知的 iSpace 工具。');
      }
    } else if (source == AssistantContextSource.mailSummaries) {
      mailSummaries = await _contextBuilder.loadMailSummaries();
    } else if (source == AssistantContextSource.mailToolResults) {
      if (contextVersion != '5') {
        throw const AiAssistantToolExecutionException('当前服务端不支持邮件正文工具。');
      }
      final reader = _mailContentReader;
      if (reader == null) {
        throw const AiAssistantToolExecutionException('当前客户端无法读取邮件正文。');
      }
      if (call.name == 'get_mail_radar') {
        if (mailRadarReader == null) {
          throw const AiAssistantToolExecutionException('邮件雷达不可用。');
        }
        mailToolResults.add(await mailRadarReader!(call.arguments));
      } else if (call.name == 'find_mail_messages') {
        mailToolResults.add(
          await reader.findMessages(
            _mailSearchRequest(call.arguments),
            protocolVersion: (call.arguments['protocol_version'] as int?) ?? 1,
          ),
        );
      } else if (call.name == 'read_mail_attachment_text') {
        final args = call.arguments;
        final part = args['part_id'];
        final offset = args['offset'] ?? 0;
        if (part is! String ||
            part.isEmpty ||
            offset is! int ||
            offset < 0 ||
            args.keys.any(
              (key) => !const {
                'folder',
                'uid',
                'mailbox_uid_validity',
                'part_id',
                'offset',
              }.contains(key),
            )) {
          throw const AiAssistantToolExecutionException('邮件附件参数无效。');
        }
        final identities = _mailIdentities({
          'messages': [
            {
              'folder': args['folder'],
              'uid': args['uid'],
              'mailbox_uid_validity': args['mailbox_uid_validity'],
            },
          ],
        });
        final identity = identities.single;
        if (!availableMailIdentities.contains(
          '${identity.folder.name}:${identity.mailboxUidValidity}:${identity.uid}',
        )) {
          throw const AiAssistantToolExecutionException('请先读取目标邮件。');
        }
        mailToolResults.add(
          await reader.readAttachment(identity, part, offset: offset),
        );
      } else if (call.name == 'read_mail_messages') {
        final identities = _mailIdentities(call.arguments);
        if (identities.any(
          (identity) => !availableMailIdentities.contains(
            '${identity.folder.name}:${identity.mailboxUidValidity}:${identity.uid}',
          ),
        )) {
          throw const AiAssistantToolExecutionException(
            '小U请求的邮件没有出现在当前已加载结果中。',
          );
        }
        mailToolResults.add(
          await reader.readMessages(
            identities,
            bodyOffset: (call.arguments['body_offset'] as int?) ?? 0,
            protocolVersion: (call.arguments['protocol_version'] as int?) ?? 1,
          ),
        );
      } else {
        throw const AiAssistantToolExecutionException('小U请求了未知的邮件工具。');
      }
    }

    final context = _contextBuilder.build(
      {source},
      contextVersion: contextVersion,
      currentLocation: currentLocation,
      ispaceCourseCatalog: ispaceCourseCatalog,
      ispaceActivity: ispaceActivity,
      ispaceQuizAttempt: ispaceQuizAttempt,
      ispaceToolResults: ispaceToolResults,
      academicCalendar: academicCalendar,
      mailSummaries: mailSummaries,
      mailToolResults: mailToolResults,
    );
    return AssistantAgentToolResult(
      callId: call.callId,
      context: context,
      elapsedMilliseconds: clock.elapsedMilliseconds,
    );
  }

  static AssistantContextPayload merge(
    Iterable<AssistantContextPayload> values,
  ) {
    var sources = <AssistantContextSource>{};
    var contextVersion = '3';
    AssistantAcademicProfileContext? academicProfile;
    var courses = const <AssistantCourseContext>[];
    AssistantTermContext? term;
    var termCourses = const <AssistantTermCourseContext>[];
    AssistantIspaceCourseCatalogContext? ispaceCourseCatalog;
    AssistantIspaceActivityContext? ispaceActivity;
    AssistantIspaceQuizAttemptContext? ispaceQuizAttempt;
    final ispaceToolResults = <AssistantIspaceToolResultContext>[];
    final ispaceToolResultKeys = <String>{};
    var deadlines = const <AssistantDeadlineContext>[];
    var schedule = const <AssistantScheduleContext>[];
    AssistantAcademicCalendarContext? academicCalendar;
    AssistantExamTimetableContext? examTimetable;
    var mailSummaries = const <AssistantMailSummaryContext>[];
    AssistantSelectedMailContext? selectedMail;
    final mailToolResults = <AssistantMailToolResultContext>[];
    final mailToolResultKeys = <String>{};
    var schoolActivities = const <AssistantSchoolActivityContext>[];
    var taCourses = const <AssistantTaCourseContext>[];
    int? taCourseCollectionRevision;
    var fixedScheduleVersion = 0;
    var fixedScheduleCourses = const <Map<String, String>>[];
    AssistantCurrentPageContext? currentPage;
    AssistantCurrentLocationContext? currentLocation;

    for (final value in values) {
      final parsedVersion = int.tryParse(value.version) ?? 3;
      final parsedCurrentVersion = int.tryParse(contextVersion) ?? 3;
      if (parsedVersion > parsedCurrentVersion) contextVersion = value.version;
      sources = {...sources, ...value.sources};
      if (value.sources.contains(AssistantContextSource.academicProfile)) {
        academicProfile = value.academicProfile;
      }
      if (value.sources.contains(AssistantContextSource.courses)) {
        courses = value.courses;
      }
      if (value.sources.contains(AssistantContextSource.termCourses)) {
        term = value.term;
        termCourses = value.termCourses;
      }
      if (value.sources.contains(AssistantContextSource.ispaceCourseCatalog)) {
        ispaceCourseCatalog = value.ispaceCourseCatalog;
      }
      if (value.sources.contains(AssistantContextSource.ispaceActivity)) {
        ispaceActivity = value.ispaceActivity;
      }
      if (value.sources.contains(AssistantContextSource.ispaceQuizAttempt)) {
        ispaceQuizAttempt = value.ispaceQuizAttempt;
      }
      if (value.sources.contains(AssistantContextSource.ispaceToolResults)) {
        for (final result in value.ispaceToolResults) {
          if (ispaceToolResultKeys.add(result.resultKey) &&
              ispaceToolResults.length < 32) {
            ispaceToolResults.add(result);
          }
        }
      }
      if (value.sources.contains(AssistantContextSource.deadlines)) {
        deadlines = value.deadlines;
      }
      if (value.sources.contains(AssistantContextSource.schedule)) {
        schedule = value.schedule;
      }
      if (value.sources.contains(AssistantContextSource.academicCalendar)) {
        academicCalendar = value.academicCalendar;
      }
      if (value.sources.contains(AssistantContextSource.examTimetable)) {
        examTimetable = value.examTimetable;
      }
      if (value.sources.contains(AssistantContextSource.mailSummaries)) {
        mailSummaries = value.mailSummaries;
      }
      if (value.sources.contains(AssistantContextSource.selectedMail)) {
        selectedMail = value.selectedMail;
      }
      if (value.sources.contains(AssistantContextSource.mailToolResults)) {
        for (final result in value.mailToolResults) {
          if (mailToolResultKeys.add(result.resultKey) &&
              mailToolResults.length < 32) {
            mailToolResults.add(result);
          }
        }
      }
      if (value.sources.contains(AssistantContextSource.schoolActivities)) {
        schoolActivities = value.schoolActivities;
      }
      if (value.sources.contains(AssistantContextSource.taCourses)) {
        fixedScheduleVersion = value.fixedScheduleVersion;
        fixedScheduleCourses = value.fixedScheduleCourses;
        taCourses = value.taCourses;
        taCourseCollectionRevision = value.taCourseCollectionRevision;
      }
      if (value.sources.contains(AssistantContextSource.currentPage)) {
        currentPage = value.currentPage;
      }
      if (value.sources.contains(AssistantContextSource.currentLocation)) {
        currentLocation = value.currentLocation;
      }
    }

    return AssistantContextPayload(
      sources: Set.unmodifiable(sources),
      version: contextVersion,
      academicProfile: academicProfile,
      courses: courses,
      term: term,
      termCourses: termCourses,
      ispaceCourseCatalog: ispaceCourseCatalog,
      ispaceActivity: ispaceActivity,
      ispaceQuizAttempt: ispaceQuizAttempt,
      ispaceToolResults: List.unmodifiable(ispaceToolResults),
      deadlines: deadlines,
      schedule: schedule,
      academicCalendar: academicCalendar,
      examTimetable: examTimetable,
      mailSummaries: mailSummaries,
      selectedMail: selectedMail,
      mailToolResults: List.unmodifiable(mailToolResults),
      schoolActivities: schoolActivities,
      fixedScheduleVersion: fixedScheduleVersion,
      fixedScheduleCourses: fixedScheduleCourses,
      taCourses: taCourses,
      taCourseCollectionRevision: taCourseCollectionRevision,
      currentPage: currentPage,
      currentLocation: currentLocation,
    );
  }

  String _skillLabelFor(AssistantContextSource source) {
    return switch (source) {
      AssistantContextSource.academicProfile => '专业信息',
      AssistantContextSource.courses => '课程概览',
      AssistantContextSource.termCourses => '学期课程',
      AssistantContextSource.ispaceCourseCatalog => 'iSpace 课程活动索引',
      AssistantContextSource.ispaceActivity => 'iSpace 活动详情',
      AssistantContextSource.ispaceQuizAttempt => 'iSpace Quiz 作答',
      AssistantContextSource.ispaceToolResults => 'iSpace 课程模块',
      AssistantContextSource.deadlines => '课程 DDL',
      AssistantContextSource.schedule => '课表查询',
      AssistantContextSource.academicCalendar => '校历日期',
      AssistantContextSource.examTimetable => '考试安排',
      AssistantContextSource.mailSummaries => '邮件摘要',
      AssistantContextSource.selectedMail => '当前邮件',
      AssistantContextSource.mailToolResults => '邮件正文',
      AssistantContextSource.schoolActivities => '校园活动',
      AssistantContextSource.taCourses => '固定日程',
      AssistantContextSource.currentPage => '当前页面',
      AssistantContextSource.currentLocation => '当前位置',
    };
  }

  AssistantMailSearchRequest _mailSearchRequest(
    Map<String, dynamic> arguments,
  ) {
    const allowedKeys = {
      'protocol_version',
      'query',
      'sender',
      'folders',
      'lookback_days',
      'official_senders_only',
      'limit',
      'include_body',
      'cursor',
      'search_scope',
    };
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      throw const AiAssistantToolExecutionException('小U邮件搜索参数无效。');
    }
    final query = arguments['query'] ?? '';
    final sender = arguments['sender'] ?? '';
    final lookbackDays = arguments['lookback_days'] ?? 7;
    final officialSendersOnly = arguments['official_senders_only'] ?? false;
    final limit = arguments['limit'] ?? 4;
    final includeBody = arguments['include_body'] ?? true;
    final rawFolders = arguments['folders'] ?? const ['inbox'];
    if (query is! String ||
        sender is! String ||
        lookbackDays is! int ||
        officialSendersOnly is! bool ||
        limit is! int ||
        includeBody is! bool ||
        (arguments['cursor'] != null && arguments['cursor'] is! String) ||
        (arguments['search_scope'] != null &&
            arguments['search_scope'] is! String) ||
        rawFolders is! List ||
        rawFolders.any((value) => value is! String)) {
      throw const AiAssistantToolExecutionException('小U邮件搜索参数无效。');
    }
    final folders = rawFolders
        .map((value) {
          final matches = MailFolder.values.where(
            (folder) => folder.name == value,
          );
          if (matches.length != 1) {
            throw const AiAssistantToolExecutionException('小U邮件文件夹参数无效。');
          }
          return matches.single;
        })
        .toList(growable: false);
    return AssistantMailSearchRequest(
      query: query,
      sender: sender,
      folders: folders,
      lookbackDays: lookbackDays,
      officialSendersOnly: officialSendersOnly,
      limit: limit,
      includeBody: includeBody,
      cursor: (arguments['cursor'] as String?) ?? '',
      searchScope: (arguments['search_scope'] as String?) ?? 'all',
    );
  }

  List<MailMessageIdentity> _mailIdentities(Map<String, dynamic> arguments) {
    if (arguments.keys.any(
          (key) =>
              key != 'messages' &&
              key != 'body_offset' &&
              key != 'protocol_version',
        ) ||
        arguments['messages'] is! List) {
      throw const AiAssistantToolExecutionException('小U邮件读取参数无效。');
    }
    final bodyOffset = arguments['body_offset'] ?? 0;
    if (bodyOffset is! int || bodyOffset < 0) {
      throw const AiAssistantToolExecutionException('邮件续读位置无效。');
    }
    final rawMessages = arguments['messages'] as List;
    if (rawMessages.isEmpty || rawMessages.length > 8) {
      throw const AiAssistantToolExecutionException('小U单批可读取一至八封邮件，请分批读取更多邮件。');
    }
    final identities = rawMessages
        .map((raw) {
          if (raw is! Map ||
              raw.keys.any(
                (key) =>
                    key != 'folder' &&
                    key != 'mailbox_uid_validity' &&
                    key != 'uid',
              )) {
            throw const AiAssistantToolExecutionException('小U邮件读取参数无效。');
          }
          final folderName = raw['folder'];
          final uidValidity = raw['mailbox_uid_validity'];
          final uid = raw['uid'];
          if (folderName is! String ||
              uidValidity is! int ||
              uidValidity <= 0 ||
              uid is! int ||
              uid <= 0) {
            throw const AiAssistantToolExecutionException('小U邮件读取参数无效。');
          }
          final folders = MailFolder.values.where(
            (folder) => folder.name == folderName,
          );
          if (folders.length != 1) {
            throw const AiAssistantToolExecutionException('小U邮件文件夹参数无效。');
          }
          return MailMessageIdentity(
            folder: folders.single,
            uid: uid,
            mailboxUidValidity: uidValidity,
          );
        })
        .toList(growable: false);
    if (identities
            .map(
              (identity) =>
                  '${identity.folder.name}:${identity.mailboxUidValidity}:${identity.uid}',
            )
            .toSet()
            .length !=
        identities.length) {
      throw const AiAssistantToolExecutionException('小U邮件读取参数包含重复邮件。');
    }
    return identities;
  }
}

class AiAssistantToolExecutionException implements Exception {
  const AiAssistantToolExecutionException(this.message);

  final String message;

  @override
  String toString() => message;
}
