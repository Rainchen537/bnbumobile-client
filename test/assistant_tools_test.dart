import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/assistant_tool_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final historyKey = SecretKey(List<int>.generate(32, (index) => index));
  SharedPreferencesAssistantHistoryStore historyStore() =>
      SharedPreferencesAssistantHistoryStore(key: () async => historyKey);

  test('parses timezone-aware local notification action fields', () {
    final action = AssistantAction.fromJson({
      'type': 'schedule_notification',
      'title': '设置提醒',
      'requires_confirmation': true,
      'target_id': '',
      'url': '',
      'recipient': '',
      'subject': '',
      'body': '',
      'place_query': '',
      'notification_title': '带校园卡',
      'notification_body': '出门前记得带校园卡。',
      'notification_at': '2026-07-24T08:00:00+08:00',
    });

    expect(action.type, AssistantActionType.scheduleNotification);
    expect(action.notificationTitle, '带校园卡');
    expect(action.notificationAt?.toUtc(), DateTime.utc(2026, 7, 24));
    expect(
      () => AssistantAction.fromJson({
        ...action.toJson(),
        'notification_at': '2026-07-24T08:00:00',
      }),
      throwsFormatException,
    );
  });

  test('parses typed iSpace mutation action fields', () {
    final completion = AssistantAction.fromJson(const {
      'action_id': 'completion-1',
      'type': 'set_ispace_completion',
      'title': '标记完成',
      'requires_confirmation': true,
      'target_id': 'm1:42:101:88:page',
      'ispace_completed': true,
      'choice_option_ids': <String>[],
    });
    final choice = AssistantAction.fromJson(const {
      'action_id': 'choice-1',
      'type': 'submit_ispace_choice',
      'title': '提交 Choice',
      'requires_confirmation': true,
      'target_id': 'm1:42:102:89:choice',
      'ispace_completed': null,
      'choice_option_ids': ['11', '12'],
    });

    expect(completion.type, AssistantActionType.setIspaceCompletion);
    expect(completion.ispaceCompleted, isTrue);
    expect(choice.type, AssistantActionType.submitIspaceChoice);
    expect(choice.choiceOptionIds, ['11', '12']);
    expect(choice.toJson()['choice_option_ids'], ['11', '12']);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('tool planner reads location only for explicit location intent', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();

    final regular = planner.plan('帮我整理今天的课程', availableSources: available);
    final location = planner.plan('我现在在哪里？', availableSources: available);

    expect(regular.needsCurrentLocation, isFalse);
    expect(
      regular.sources,
      isNot(contains(AssistantContextSource.currentLocation)),
    );
    expect(location.needsCurrentLocation, isTrue);
    expect(location.sources, contains(AssistantContextSource.currentLocation));
  });

  test('tool planner requests schedule before the source is loaded', () {
    const planner = AssistantToolPlanner();

    final plan = planner.plan(
      '我明天有什么课？',
      availableSources: const {AssistantContextSource.courses},
    );

    expect(plan.needsSchedule, isTrue);
  });

  test('Moodle completion and Choice intents request v4 module evidence', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();

    for (final message in ['把 Week 2 标记完成', 'Submit the Choice activity']) {
      final plan = planner.plan(message, availableSources: available);
      expect(plan.sources, contains(AssistantContextSource.courses));
      expect(
        plan.sources,
        contains(AssistantContextSource.ispaceCourseCatalog),
      );
      expect(plan.sources, contains(AssistantContextSource.ispaceToolResults));
    }
  });

  test('agenda intent includes schedule, DDL, official calendar and exams', () {
    const planner = AssistantToolPlanner();

    final plan = planner.plan(
      '安排我今天的课程和 DDL',
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.sources, {
      AssistantContextSource.schedule,
      AssistantContextSource.deadlines,
      AssistantContextSource.academicCalendar,
      AssistantContextSource.examTimetable,
    });

    final combinedEnglish = planner.plan(
      'What do I have tomorrow? Separate MIS classes, TA courses, deadlines, '
      'academic calendar events and MIS exams.',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(combinedEnglish.sources, contains(AssistantContextSource.schedule));
    expect(combinedEnglish.sources, contains(AssistantContextSource.deadlines));
    expect(
      combinedEnglish.sources,
      contains(AssistantContextSource.academicCalendar),
    );
    expect(
      combinedEnglish.sources,
      contains(AssistantContextSource.examTimetable),
    );

    for (final message in const [
      '今天的安排',
      '明天我有什么课',
      '我几点有课？',
      "What's on my schedule tomorrow?",
      'What am I doing today?',
    ]) {
      final plan = planner.plan(
        message,
        availableSources: AssistantContextSource.values.toSet(),
      );
      expect(
        plan.sources,
        contains(AssistantContextSource.schedule),
        reason: message,
      );
    }
  });

  test('today-scoped iSpace task question remains deadline-only', () {
    const planner = AssistantToolPlanner();
    final plan = planner.plan(
      '今天有哪些 iSpace 任务截止？如果没有，请告诉我最近一个截止事项。',
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.sources, {AssistantContextSource.deadlines});
    expect(plan.needsSchedule, isFalse);
  });

  test('iSpace Timeline and overdue counts remain deadline-only', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();

    for (final message in const [
      '当前 iSpace Timeline 有多少项？其中多少项已经逾期？',
      'How many items are in my iSpace Timeline, and how many are overdue?',
    ]) {
      expect(planner.plan(message, availableSources: available).sources, {
        AssistantContextSource.deadlines,
      }, reason: message);
    }
  });

  test('pure iSpace module aggregates select only the catalog tools', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();

    for (final message in const [
      '统计全部 iSpace 模块的类型分布，按数量列出。',
      'Aggregate my iSpace Assignment module types by count.',
      'iSpace 课程活动类型中，数量最多和最少的分别是什么？',
      '只依据当前目录聚合回答：Assignment 类型一共有多少个？',
    ]) {
      expect(planner.plan(message, availableSources: available).sources, {
        AssistantContextSource.ispaceCourseCatalog,
        AssistantContextSource.ispaceToolResults,
      }, reason: message);
    }
  });

  test('read-only manual completion inventory selects only catalog tools', () {
    const planner = AssistantToolPlanner();
    final plan = planner.plan(
      '列出当前支持手动完成的可见模块名称，不要实际修改完成状态。',
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.sources, {
      AssistantContextSource.ispaceCourseCatalog,
      AssistantContextSource.ispaceToolResults,
    });
  });

  test(
    'iSpace deadline wording does not erase an explicit schedule request',
    () {
      const planner = AssistantToolPlanner();
      final available = AssistantContextSource.values.toSet();

      for (final message in const [
        '请结合我的 iSpace DDL 和明天课表安排优先级。',
        '我的课表中课程开始时间是什么？',
      ]) {
        final plan = planner.plan(message, availableSources: available);
        expect(
          plan.sources,
          contains(AssistantContextSource.schedule),
          reason: message,
        );
      }
    },
  );

  test('named deadline comparison does not become a teacher catalog query', () {
    const planner = AssistantToolPlanner();
    final plan = planner.plan(
      'EEP Teacher Feedback 2026 和 EEP Student Feedback 2026 '
      '哪个先截止？相差多久？统一使用北京时间。',
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.sources, {AssistantContextSource.deadlines});
    expect(plan.needsSchedule, isFalse);
  });

  test('acceptance phrases select the exact minimum client context', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();

    for (final message in const [
      '请读取我的专业信息，告诉我专业代码、专业名称和年级。',
      'Read my real academic profile and report the programme code, programme name, and year level.',
    ]) {
      expect(planner.plan(message, availableSources: available).sources, {
        AssistantContextSource.academicProfile,
      }, reason: message);
    }

    for (final message in const [
      '请读取当前 Flutter 页面语义，告诉我现在位于哪个页面以及可见的主要功能；只读取当前页面。',
      'Read the current Flutter page semantics only. Tell me which page I am on and the main visible functions.',
    ]) {
      expect(planner.plan(message, availableSources: available).sources, {
        AssistantContextSource.currentPage,
      }, reason: message);
    }

    for (final message in const [
      '请读取我当前 iSpace 课程概览，列出真实课程名称和课程代码；不要使用 MIS 课表。',
      '请读取我当前 iSpace 课程概览，列出真实课程名称和课程 ID；只使用课程概览，不要读取课表、DDL 或校历。',
      'Read my current iSpace course overview only. List the real course names and iSpace course IDs. Do not query MIS schedule or deadlines.',
      'Read my current iSpace course overview. Use only the course overview and do not read schedule, deadlines, or calendar.',
    ]) {
      expect(planner.plan(message, availableSources: available).sources, {
        AssistantContextSource.courses,
      }, reason: message);
    }

    final agenda = planner.plan(
      '请读取今天的真实日程，分别列出 MIS 课程、本机 TA、iSpace DDL、校历事件和 MIS 考试状态。',
      availableSources: available,
    );
    expect(agenda.sources, {
      AssistantContextSource.schedule,
      AssistantContextSource.deadlines,
      AssistantContextSource.academicCalendar,
      AssistantContextSource.examTimetable,
    });
  });

  test('practical iSpace catalog questions select catalog evidence', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();

    for (final message in const [
      '当前 iSpace 一共有多少个模块？其中多少个当前可见、多少个不可见？',
      'How many Moodle modules are in my current iSpace catalog, and how many are visible?',
      '统计当前全部 iSpace 模块的类型分布，按数量从高到低列出。',
      '请区分两门数据结构课，比较它们当前在 iSpace 中可见的资料类型。',
      '基于当前课程目录，哪些课程除了公告论坛外没有其他可见学习模块？',
      '哪些课程有明确的进度百分比？没有进度值不能当成 0%。',
      '按课程开始时间整理当前 iSpace 课程。',
      '按课程开始时间整理我当前 iSpace 课程：哪些是 2026 年 8 月底新开的，哪些是更早的通用课程？',
      'Summarize the module-type distribution across my current iSpace catalog.',
    ]) {
      final sources = planner
          .plan(message, availableSources: available)
          .sources;
      expect(
        sources,
        contains(AssistantContextSource.ispaceCourseCatalog),
        reason: message,
      );
      expect(
        sources,
        isNot(contains(AssistantContextSource.courses)),
        reason: message,
      );
      expect(
        sources,
        isNot(contains(AssistantContextSource.termCourses)),
        reason: message,
      );
      expect(
        sources,
        isNot(contains(AssistantContextSource.deadlines)),
        reason: message,
      );
    }

    for (final message in const [
      'iSpace 课程概览里的 show grades 能力是否等于我已经有成绩？',
      '哪些课程包含 Feedback 活动？',
      '当前目录中的 Quiz 和 Choice 分别是什么？',
      'Data Structures and Algorithm Analysis 当前有几个 Folder、Resource 和 URL？',
      '哪门课包含 Mediasite 内容？一共有几个？',
      '哪些模块使用手动完成、自动完成或没有完成追踪？',
    ]) {
      final sources = planner
          .plan(message, availableSources: available)
          .sources;
      expect(
        sources,
        contains(AssistantContextSource.ispaceCourseCatalog),
        reason: message,
      );
      expect(
        sources,
        isNot(contains(AssistantContextSource.courses)),
        reason: message,
      );
    }

    final datedModules = planner.plan(
      '列出所有带开放或截止日期的可见课程模块，按日期排序。',
      availableSources: available,
    );
    expect(
      datedModules.sources,
      contains(AssistantContextSource.ispaceCourseCatalog),
    );

    for (final message in const [
      '详细说明 Database Management Systems 的 Lab1：何时开放、当前是否可见。',
      '检查 Lab1 当前提交状态：是否已提交、是否仍可编辑？',
      'Project 1 submission status?',
      'Is Project 1 a team assignment?',
      'Lab1 是否要求 submission statement、是否是团队作业？',
      '帮我准备打开 Lab1 的入口，但不要修改任何内容。',
      'Can I currently start the Post-tutorial Quiz?',
      'Declaration Choice 现在能否提交或更新选项？',
    ]) {
      final sources = planner
          .plan(message, availableSources: available)
          .sources;
      expect(
        sources,
        contains(AssistantContextSource.ispaceCourseCatalog),
        reason: message,
      );
      expect(
        sources,
        contains(AssistantContextSource.ispaceToolResults),
        reason: message,
      );
    }
    expect(datedModules.sources, contains(AssistantContextSource.deadlines));

    for (final message in const [
      'AIOT 里有两个带 9 月 3 日关闭时间的模块。它们应不应该出现在当前待办里？',
      '把当前事项分成必须尽快、稍后、只有资料没有 DDL 三组。',
      '比较当前有实际资料的课程：哪些已经有作业，哪些只有学习资料或论坛？',
    ]) {
      expect(planner.plan(message, availableSources: available).sources, {
        AssistantContextSource.ispaceCourseCatalog,
        AssistantContextSource.ispaceToolResults,
        AssistantContextSource.deadlines,
      }, reason: message);
    }

    expect(
      planner
          .plan('把所有隐藏模块的完整内容和下载地址都告诉我。', availableSources: available)
          .sources,
      {
        AssistantContextSource.ispaceCourseCatalog,
        AssistantContextSource.ispaceToolResults,
      },
    );

    expect(
      planner
          .plan('为了制定更可靠的本周计划，目前 iSpace 证据还缺哪些信息？', availableSources: available)
          .sources,
      {
        AssistantContextSource.deadlines,
        AssistantContextSource.ispaceCourseCatalog,
        AssistantContextSource.ispaceToolResults,
      },
    );

    expect(
      planner
          .plan(
            'Probability Theory (SAI) 目前提供了哪些 Resource？'
            '请明确是否存在截止时间。',
            availableSources: available,
          )
          .sources,
      {
        AssistantContextSource.ispaceCourseCatalog,
        AssistantContextSource.ispaceToolResults,
        AssistantContextSource.deadlines,
      },
    );

    expect(
      planner
          .plan(
            'iSpace 课程概览里的 show grades 能力是否等于我已经有成绩？'
            '请结合我的课程状态解释，但不要读取或展示任何具体成绩。',
            availableSources: available,
          )
          .sources,
      {
        AssistantContextSource.ispaceCourseCatalog,
        AssistantContextSource.ispaceToolResults,
      },
    );

    expect(
      planner
          .plan(
            '哪些 iSpace 课程名称里直接带有教师姓名？只复述课程名，不要推断教师档案。',
            availableSources: available,
          )
          .sources,
      {AssistantContextSource.courses},
    );
  });

  test(
    'calendar and MIS exam intent stay distinct from iSpace Quiz intent',
    () {
      const planner = AssistantToolPlanner();
      final available = AssistantContextSource.values.toSet();

      final calendar = planner.plan(
        'Reading Week 哪几天？哪天补课？',
        availableSources: available,
      );
      final exam = planner.plan('我的期末考试考场和座位在哪？', availableSources: available);
      final quiz = planner.plan('打开本周 Quiz 并保存答案', availableSources: available);

      expect(
        calendar.sources,
        contains(AssistantContextSource.academicCalendar),
      );
      expect(exam.sources, contains(AssistantContextSource.examTimetable));
      expect(
        exam.sources,
        isNot(contains(AssistantContextSource.ispaceQuizAttempt)),
      );
      expect(quiz.sources, contains(AssistantContextSource.ispaceQuizAttempt));
      expect(
        quiz.sources,
        isNot(contains(AssistantContextSource.examTimetable)),
      );
      expect(
        planner.plan('我有考试吗？', availableSources: available).sources,
        contains(AssistantContextSource.examTimetable),
      );
    },
  );

  test('official calendar PDF requests use only the calendar source', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();

    final supportedSemesterDocuments = planner.plan(
      'List exactly the two official PDF file names and HTTPS links for '
      'Semester 1 of AY2026-27.',
      availableSources: available,
    );
    final classScheduleDocument = planner.plan(
      'Show me the official Class Schedule PDF for AY2026-27.',
      availableSources: available,
    );
    final personalClassSchedule = planner.plan(
      'Show my class schedule for tomorrow.',
      availableSources: available,
    );

    expect(supportedSemesterDocuments.sources, {
      AssistantContextSource.academicCalendar,
    });
    expect(classScheduleDocument.sources, {
      AssistantContextSource.academicCalendar,
    });
    expect(
      personalClassSchedule.sources,
      contains(AssistantContextSource.schedule),
    );
  });

  test('thinking effort uses native levels and maps only legacy protocol', () {
    expect(AssistantThinkingMode.parse('low'), AssistantThinkingMode.low);
    expect(AssistantThinkingMode.parse('medium'), AssistantThinkingMode.medium);
    expect(AssistantThinkingMode.parse('high'), AssistantThinkingMode.high);
    expect(AssistantThinkingMode.parse('simple'), AssistantThinkingMode.low);
    expect(AssistantThinkingMode.parse('deep'), AssistantThinkingMode.high);
    expect(AssistantThinkingMode.low.wireValueForProtocol(1), 'simple');
    expect(AssistantThinkingMode.medium.wireValueForProtocol(1), 'simple');
    expect(AssistantThinkingMode.high.wireValueForProtocol(1), 'deep');
    expect(AssistantThinkingMode.medium.wireValueForProtocol(2), 'medium');

    final legacyCapabilities = AssistantCapabilities.fromJson(const {
      'available': true,
      'model': 'legacy-provider',
      'thinking_modes': ['simple', 'deep'],
      'context_sources': [],
      'actions': [],
      'stores_conversation_content': true,
      'purchase_api_available': false,
    });
    expect(
      legacyCapabilities.thinkingModes,
      containsAll({AssistantThinkingMode.low, AssistantThinkingMode.high}),
    );
  });

  test('compact network activity survives local history serialization', () {
    final stored = AssistantStoredMessage(
      role: 'assistant',
      content: '网络暂时没有恢复，这轮问题已经保留。',
      createdAt: DateTime.utc(2026, 8, 7),
      isError: true,
      compactError: true,
      retryMessage: '继续原问题',
      activities: const [
        AssistantActivity(label: '网络连接暂未恢复，已保留这轮问题', failed: true),
      ],
    );

    final restored = AssistantStoredMessage.fromJson(stored.toJson());

    expect(restored.compactError, isTrue);
    expect(restored.canRetry, isTrue);
    expect(restored.activities.single.failed, isTrue);
    expect(restored.activities.single.completed, isTrue);
  });

  test('legacy remote history restores compact network presentation', () {
    final restored = AssistantStoredMessage.fromJson({
      'role': 'assistant',
      'content': '网络暂时没有恢复，这轮问题已经保留。',
      'created_at': '2026-08-07T00:00:00.000Z',
      'is_error': true,
      'retry_message': '继续原问题',
      'activities': [
        {'label': '网络连接暂未恢复，已保留这轮问题'},
      ],
    });

    expect(restored.compactError, isTrue);
    expect(restored.canRetry, isTrue);
    expect(restored.activities.single.failed, isTrue);
  });

  test('bilingual composite questions expose every supported safe source', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();
    final questions = [
      '结合我的专业和今天课表，看看 DDL 和邮箱，再按导师科研方向给我建议',
      'On this course page, check the Moodle course materials and the quiz, '
          'then help me save the quiz answers.',
      '看看我附近有什么活动，再查一下 TA 课和助教课程',
      'What should I deal with next? Check my classes, due work, faculty '
          'research for my major, and my inbox.',
      '校历和期末考试安排也一起看。',
    ];

    final exposed = <AssistantContextSource>{};
    for (final question in questions) {
      exposed.addAll(
        planner.plan(question, availableSources: available).sources,
      );
    }

    expect(exposed, containsAll(AssistantContextSource.values));
  });

  test('ambiguous Chinese and English agenda requests combine safely', () {
    const planner = AssistantToolPlanner();
    final available = AssistantContextSource.values.toSet();
    final plans = [
      planner.plan(
        '我今天还有啥要紧的，老师那边、iSpace 和邮箱有没有需要处理的？',
        availableSources: available,
      ),
      planner.plan(
        'What should I deal with next? Consider my classes, due work, '
        'faculty information and my inbox.',
        availableSources: available,
      ),
    ];

    for (final plan in plans) {
      expect(plan.sources, contains(AssistantContextSource.schedule));
      expect(plan.sources, contains(AssistantContextSource.deadlines));
      expect(plan.sources, contains(AssistantContextSource.courses));
      expect(plan.sources, contains(AssistantContextSource.termCourses));
      expect(
        plan.sources,
        contains(AssistantContextSource.ispaceCourseCatalog),
      );
      expect(plan.sources, contains(AssistantContextSource.mailSummaries));
      expect(plan.sources, contains(AssistantContextSource.selectedMail));
    }
  });

  test('teacher public availability does not read the student schedule', () {
    const planner = AssistantToolPlanner();
    final plan = planner.plan(
      "What are Professor Chen's research areas and office hours?",
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.needsSchedule, isFalse);
    expect(plan.sources, isNot(contains(AssistantContextSource.schedule)));
    expect(plan.sources, isNot(contains(AssistantContextSource.deadlines)));
  });

  test('teacher directory questions request term course context', () {
    const planner = AssistantToolPlanner();

    final plan = planner.plan(
      '我这学期接下来课程的老师办公室和邮箱是什么？',
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.needsSchedule, isTrue);
    expect(plan.sources, contains(AssistantContextSource.termCourses));
    expect(plan.sources, contains(AssistantContextSource.courses));
    expect(plan.sources, contains(AssistantContextSource.ispaceCourseCatalog));
  });

  test('programme faculty questions request the bounded academic profile', () {
    const planner = AssistantToolPlanner();

    for (final message in ['结合一下我的专业，如果我要科研哪个导师更适合我？', '帮我总结一下我们专业的所有导师']) {
      final plan = planner.plan(
        message,
        availableSources: AssistantContextSource.values.toSet(),
      );
      expect(plan.sources, contains(AssistantContextSource.academicProfile));
      expect(plan.sources, {AssistantContextSource.academicProfile});
      expect(plan.needsSchedule, isFalse);
    }
  });

  test('courseware ZIP requests include the stable course catalog', () {
    const planner = AssistantToolPlanner();

    final plan = planner.plan(
      '把我上学期 C 语言的所有课件打包成 zip',
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.sources, isNot(contains(AssistantContextSource.courses)));
    expect(plan.sources, isNot(contains(AssistantContextSource.termCourses)));
    expect(plan.sources, contains(AssistantContextSource.ispaceCourseCatalog));
  });

  test(
    'quiz and assignment submission requests select stable activity data',
    () {
      const planner = AssistantToolPlanner();

      final quizPlan = planner.plan(
        '打开 Step 4 quiz，我确认后再提交',
        availableSources: AssistantContextSource.values.toSet(),
      );
      final filePlan = planner.plan(
        '把我做好的作业文件上传并提交',
        availableSources: AssistantContextSource.values.toSet(),
      );

      for (final plan in [quizPlan, filePlan]) {
        expect(plan.sources, contains(AssistantContextSource.deadlines));
        expect(plan.sources, contains(AssistantContextSource.ispaceActivity));
      }
      expect(
        quizPlan.sources,
        contains(AssistantContextSource.ispaceQuizAttempt),
      );
    },
  );

  test(
    'iSpace activity keeps timeline, course-module and instance IDs apart',
    () {
      final payload = AssistantContextPayload(
        sources: const {AssistantContextSource.ispaceActivity},
        ispaceActivity: AssistantIspaceActivityContext(
          itemId: '89055',
          courseId: '1531',
          courseModuleId: '270762',
          instanceId: '90210',
          activityType: 'quiz',
          title: 'Step 4: Post-tutorial Quiz',
          courseName: 'AIoT',
          summary: 'Quiz activity',
          openAt: null,
          dueAt: null,
          closeAt: null,
          submissionStatus: 'in_progress',
          canEditSubmission: true,
          supportsFileSubmission: false,
          supportsOnlineTextSubmission: false,
          maxFileSubmissions: 0,
          maxSubmissionSizeBytes: 0,
          files: const [],
        ),
      ).toJson();

      final activity = payload['ispace_activity'] as Map<String, dynamic>;
      expect(activity['item_id'], '89055');
      expect(activity['course_module_id'], '270762');
      expect(activity['instance_id'], '90210');
      expect(activity['activity_type'], 'quiz');
    },
  );

  test('last-year course list avoids current-term-only context', () {
    const planner = AssistantToolPlanner();

    final plan = planner.plan(
      '帮我整理一下去年的课程列表',
      availableSources: AssistantContextSource.values.toSet(),
    );

    expect(plan.sources, contains(AssistantContextSource.courses));
    expect(plan.sources, contains(AssistantContextSource.ispaceCourseCatalog));
    expect(plan.sources, isNot(contains(AssistantContextSource.termCourses)));
    expect(plan.sources, isNot(contains(AssistantContextSource.schedule)));
  });

  test('context version 3 serializes bounded current location fields', () {
    final payload = AssistantContextPayload(
      sources: const {AssistantContextSource.currentLocation},
      currentLocation: AssistantCurrentLocationContext(
        latitude: 22.35,
        longitude: 114.17,
        accuracyMeters: 8.5,
        observedAt: DateTime.parse('2026-07-21T18:00:00+08:00'),
      ),
    ).toJson();

    expect(payload['version'], '3');
    expect(payload['sources'], ['current_location']);
    expect(payload['current_location'], containsPair('accuracy_meters', 8.5));
    expect(
      (payload['current_location'] as Map<String, dynamic>)['observed_at'],
      '2026-07-21T10:00:00.000Z',
    );
  });

  test('submit assignment action preserves confirmation and editable text', () {
    final action = AssistantAction.fromJson(const {
      'type': 'submit_assignment',
      'title': '提交作业',
      'requires_confirmation': true,
      'target_id': '7',
      'body': 'Draft answer',
    });

    expect(action.type, AssistantActionType.submitAssignment);
    expect(action.requiresConfirmation, isTrue);
    expect(action.targetId, '7');
    expect(action.copyWith(body: 'Edited answer').body, 'Edited answer');
  });

  test(
    'native handoff actions preserve typed targets and attachment fields',
    () {
      final attachment = AssistantAction.fromJson(const {
        'action_id': 'attachment-1',
        'type': 'download_attachment',
        'title': '下载附件',
        'requires_confirmation': true,
        'mail_uid': 17,
        'mail_folder': 'inbox',
        'mailbox_uid_validity': 9001,
        'mail_part_id': '2.1',
        'attachment_name': 'report.pdf',
      });
      final appTab = AssistantAction.fromJson(const {
        'action_id': 'tab-mail',
        'type': 'open_app_tab',
        'title': '打开邮箱',
        'requires_confirmation': false,
        'target_id': 'mail',
      });
      final officialSystem = AssistantAction.fromJson(const {
        'action_id': 'system-mis',
        'type': 'open_official_system',
        'title': '打开 MIS',
        'requires_confirmation': false,
        'target_id': 'mis',
      });

      expect(attachment.type, AssistantActionType.downloadAttachment);
      expect(attachment.mailPartId, '2.1');
      expect(attachment.attachmentName, 'report.pdf');
      expect(
        attachment.copyWith(attachmentName: 'renamed.pdf').attachmentName,
        'renamed.pdf',
      );
      expect(attachment.toJson()['mail_part_id'], '2.1');
      expect(attachment.toJson()['attachment_name'], 'report.pdf');
      expect(appTab.type, AssistantActionType.openAppTab);
      expect(appTab.targetId, 'mail');
      expect(officialSystem.type, AssistantActionType.openOfficialSystem);
      expect(officialSystem.targetId, 'mis');
    },
  );

  test('TA course intent selects context and preserves revision fields', () {
    const planner = AssistantToolPlanner();
    final plan = planner.plan(
      '把周二的 TA 课改到下午三点',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(plan.sources, contains(AssistantContextSource.taCourses));
    final addPlan = planner.plan(
      '帮我增加一个周一上午的TA课，八点到九点，地点暂时不确定',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(addPlan.sources, contains(AssistantContextSource.taCourses));
    final englishPlan = planner.plan(
      'Does the official 2026-10-10 Monday make-up move my weekly Monday '
      'Acceptance TA course to Saturday?',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(englishPlan.sources, contains(AssistantContextSource.taCourses));
    final quotedWorkshopCoursePlan = planner.plan(
      '请只读概括课程“Data Analysis Workshop”：有多少章节、多少模块，以及是否提供进度。',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      quotedWorkshopCoursePlan.sources,
      contains(AssistantContextSource.ispaceCourseCatalog),
    );
    expect(
      quotedWorkshopCoursePlan.sources,
      isNot(contains(AssistantContextSource.taCourses)),
    );
    final genericAgendaPlan = planner.plan(
      'What do I have tomorrow? Separate MIS classes, TA courses, deadlines, '
      'academic calendar events and MIS exams.',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      genericAgendaPlan.sources,
      contains(AssistantContextSource.schedule),
    );
    expect(
      genericAgendaPlan.sources,
      isNot(contains(AssistantContextSource.taCourses)),
    );
    final managementPlan = planner.plan(
      'Move my TA course to tomorrow.',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(managementPlan.sources, equals({AssistantContextSource.taCourses}));
    final chineseManagementPlan = planner.plan(
      '把 TA 课移到明天上午十点。',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      chineseManagementPlan.sources,
      equals({AssistantContextSource.taCourses}),
    );
    final taTimetableWordingPlan = planner.plan(
      '把 TA 课表改到明天。',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      taTimetableWordingPlan.sources,
      equals({AssistantContextSource.taCourses}),
    );
    final vagueConflictPlan = planner.plan(
      '我的 TA 课会冲突吗？',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      vagueConflictPlan.sources,
      equals({AssistantContextSource.taCourses}),
    );
    final nonTaScheduleChangePlan = planner.plan(
      '我的课表有变更吗？',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      nonTaScheduleChangePlan.sources,
      contains(AssistantContextSource.schedule),
    );
    expect(
      nonTaScheduleChangePlan.sources,
      isNot(contains(AssistantContextSource.taCourses)),
    );
    final nonTaScheduleAdjustmentPlan = planner.plan(
      '调整我的课表。',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      nonTaScheduleAdjustmentPlan.sources,
      contains(AssistantContextSource.schedule),
    );
    expect(
      nonTaScheduleAdjustmentPlan.sources,
      isNot(contains(AssistantContextSource.taCourses)),
    );
    final conflictPlan = planner.plan(
      'Move my TA course to tomorrow. Will it conflict with my schedule?',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      conflictPlan.sources,
      equals({
        AssistantContextSource.schedule,
        AssistantContextSource.taCourses,
      }),
    );
    final dataCoursePlan = planner.plan(
      'Review my Data Course materials.',
      availableSources: AssistantContextSource.values.toSet(),
    );
    expect(
      dataCoursePlan.sources,
      isNot(contains(AssistantContextSource.taCourses)),
    );

    final action = AssistantAction.fromJson(const {
      'type': 'update_ta_course',
      'title': '编辑 TA 课',
      'requires_confirmation': true,
      'target_id': 'ta-1',
      'ta_title': 'Programming TA',
      'ta_location': 'B201',
      'ta_weekday': 2,
      'ta_start_minutes': 900,
      'ta_end_minutes': 950,
      'ta_repeat_type': 'weekly',
      'ta_expected_entry_revision': 3,
      'ta_expected_collection_revision': 5,
    });

    expect(action.type, AssistantActionType.updateTaCourse);
    expect(action.taExpectedEntryRevision, 3);
    expect(action.taExpectedCollectionRevision, 5);
    expect(action.copyWith(taStartMinutes: 930).taStartMinutes, 930);
  });

  test('local history is restored per hashed account key', () async {
    final store = historyStore();
    final conversation = AssistantConversation(
      id: 'conversation-1',
      title: '课程安排',
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21, 1),
      branchGroupId: 'conversation-root',
      branchedFromMessageIndex: 0,
      messages: [
        AssistantStoredMessage(
          role: 'user',
          content: '明天有什么课？',
          createdAt: DateTime.utc(2026, 7, 21),
        ),
        AssistantStoredMessage(
          role: 'assistant',
          content: '明天有一节课。',
          createdAt: DateTime.utc(2026, 7, 21, 1),
          feedback: AssistantMessageFeedback.up,
        ),
      ],
    );

    await store.save('Student01', [conversation]);

    final restored = await store.load('student01');
    final otherAccount = await store.load('student02');
    final preferences = await SharedPreferences.getInstance();

    expect(restored.single.messages.first.content, '明天有什么课？');
    expect(restored.single.messages.last.feedback, AssistantMessageFeedback.up);
    expect(restored.single.branchGroupId, 'conversation-root');
    expect(restored.single.branchedFromMessageIndex, 0);
    expect(otherAccount, isEmpty);
    expect(
      preferences.getKeys().single,
      allOf(
        startsWith('bnbu.ai_assistant.history.v2.'),
        isNot(contains('student01')),
      ),
    );
  });

  test(
    'assistant suggestions persist locally as bounded display choices',
    () async {
      final store = historyStore();
      final conversation = AssistantConversation(
        id: 'conversation-suggestions',
        title: 'TA 课',
        createdAt: DateTime.utc(2026, 7, 23),
        updatedAt: DateTime.utc(2026, 7, 23, 1),
        messages: [
          AssistantStoredMessage(
            role: 'assistant',
            content: '请选择重复方式。',
            createdAt: DateTime.utc(2026, 7, 23, 1),
            suggestions: const [
              AssistantSuggestion(
                label: '每周',
                message: '请设置为每周重复。',
                isOther: false,
              ),
              AssistantSuggestion(label: '其他', message: '', isOther: true),
            ],
          ),
        ],
      );

      await store.save('Student01', [conversation]);
      final restored = await store.load('student01');

      expect(restored.single.messages.single.suggestions, hasLength(2));
      expect(restored.single.messages.single.suggestions.last.isOther, isTrue);
      expect(
        restored.single.messages.single.suggestions.first.message,
        '请设置为每周重复。',
      );
    },
  );
}
