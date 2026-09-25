import '../models/assistant_models.dart';

class AssistantToolPlan {
  const AssistantToolPlan({
    required this.sources,
    required this.needsCurrentLocation,
    required this.needsSchedule,
  });

  final Set<AssistantContextSource> sources;
  final bool needsCurrentLocation;
  final bool needsSchedule;
}

class AssistantToolPlanner {
  const AssistantToolPlanner();

  AssistantToolPlan plan(
    String message, {
    required Set<AssistantContextSource> availableSources,
  }) {
    final normalized = message.trim().toLowerCase();
    final selected = <AssistantContextSource>{};
    final ispaceIntent = _containsAny(normalized, const ['ispace', 'moodle']);
    final hasMoodleModuleType = RegExp(
      r'\b(?:assignment|booking|choice|feedback|folder|forum|label|'
      r'mediasite|page|quiz|resource|url)\b',
    ).hasMatch(normalized);
    final moodleModuleMutationIntent = _containsAny(normalized, const [
      '提交',
      '交卷',
      '直接开始',
      '全部开始',
      '选第一个',
      '标记完成',
      '标为完成',
      '标成已完成',
      '设为完成',
      '取消完成',
      'submit',
      'finalize',
      'start all',
      'choose the first',
      'mark as',
      'mark complete',
      'mark done',
    ]);
    final moodleModuleInventoryIntent =
        !moodleModuleMutationIntent &&
        hasMoodleModuleType &&
        _containsAny(normalized, const [
          '哪些',
          '几个',
          '多少',
          '哪门课',
          '包含',
          '提供',
          '目录',
          '课程',
          '模块',
          '活动',
          'which course',
          'how many',
          'catalog',
          'course',
          'module',
          'activity',
          'list',
        ]);
    final hasCatalogAggregateLanguage = _containsAny(normalized, const [
      '多少',
      '数量',
      '计数',
      '统计',
      '总数',
      '分布',
      '占比',
      '比例',
      '聚合',
      '最多',
      '最少',
      '几种',
      'how many',
      'count',
      'number of',
      'distribution',
      'breakdown',
      'total',
      'percentage',
      'ratio',
      'aggregate',
      'aggregation',
      'most',
      'least',
    ]);
    final moodleModuleTypeAggregateIntent =
        !moodleModuleMutationIntent &&
        hasMoodleModuleType &&
        hasCatalogAggregateLanguage;
    final genericMoodleCatalogAggregateIntent =
        moodleModuleTypeAggregateIntent ||
        (ispaceIntent &&
            _containsAny(normalized, const [
              '模块',
              '活动类型',
              '内容类型',
              'module',
              'activity type',
              'content type',
            ]) &&
            hasCatalogAggregateLanguage);
    final namedMoodleModuleDetailIntent =
        RegExp(r'\blab\s*\d+\b').hasMatch(normalized) ||
        _containsAny(normalized, const [
          '提交状态',
          '已提交',
          '仍可编辑',
          '草稿',
          '最终提交',
          '团队作业',
          '作业入口',
          '作业题目',
          '作业要求',
          '提交开关',
          '提交锁',
          '分组限制',
          '迟交',
          '文件提交',
          'submission state',
          'submission status',
          'submitted',
          'editable',
          'draft',
          'finalize',
          'finalise',
          'team assignment',
          'team submission',
          'assignment entry',
          'assignment instructions',
          'assignment requirements',
          'submissions enabled',
          'submission locked',
          'late submission',
          'file submission',
          'file limit',
          'maximum files',
          'max files',
          'per-file',
          'submission statement',
        ]);
    final courseContentInventoryIntent =
        _containsAny(normalized, const [
          '资料',
          '作业',
          '论坛',
          '课件',
          '文件',
          '隐藏模块',
          '不可见模块',
          'learning material',
          'course material',
          'assignment',
          'forum',
          'hidden module',
          'inaccessible module',
        ]) &&
        _containsAny(normalized, const [
          '哪些',
          '所有',
          '当前',
          '目前',
          '已有',
          '已经',
          '只有',
          '包含',
          '提供',
          'which',
          'all',
          'current',
          'contains',
          'provides',
          'only',
        ]);
    final ispaceEvidenceGapIntent =
        ispaceIntent &&
        _containsAny(normalized, const [
          '证据还缺',
          '证据缺失',
          '缺哪些信息',
          'missing evidence',
          'evidence gaps',
          'what is missing',
        ]);
    final moodleModuleAccessQuestionIntent =
        hasMoodleModuleType &&
        (ispaceIntent ||
            RegExp(r'\blab\s*\d+\b').hasMatch(normalized) ||
            RegExp(r'\b(?:assignment|choice|quiz)\b').hasMatch(normalized) ||
            _containsAny(normalized, const [
              '课程',
              '模块',
              '活动',
              'course',
              'module',
              'activity',
            ])) &&
        _containsAny(normalized, const [
          '能否',
          '能不能',
          '是否',
          '为什么',
          '可读',
          '可见',
          '可操作',
          '权限',
          '实际状态',
          'can i',
          'can this',
          'currently',
          'access',
          'visible',
          'operable',
          'verify',
        ]);
    final explicitIspaceCatalogIntent =
        namedMoodleModuleDetailIntent ||
        courseContentInventoryIntent ||
        moodleModuleAccessQuestionIntent ||
        moodleModuleInventoryIntent ||
        genericMoodleCatalogAggregateIntent ||
        _containsAny(normalized, const [
          '课程目录',
          '当前目录',
          '目录中',
          '资料类型',
          '模块类型',
          '可见资料',
          '课程进度',
          '进度百分比',
          '开始时间',
          '开课时间',
          '开始日期',
          '结束时间',
          '结束日期',
          '开放日期',
          '截止日期',
          '开放时间',
          '关闭时间',
          '关闭日期',
          '隐藏模块',
          '不可见模块',
          '完成追踪',
          '手动完成',
          '自动完成',
          '显示成绩',
          '成绩显示',
          'show grades',
          'showgrades',
          'course catalog',
          'material type',
          'material-type',
          'module type',
          'module-type',
          'visible material',
          'course progress',
          'progress percentage',
          'course start',
          'start date',
          'course end',
          'end date',
          'open date',
          'close date',
          'opening time',
          'closing time',
          'hidden module',
          'inaccessible module',
          'completion tracking',
          'manual completion',
          'automatic completion',
        ]) ||
        (_containsAny(normalized, const [
              '课程',
              '目录',
              '模块',
              'course',
              'catalog',
              'module',
              'ispace',
              'moodle',
            ]) &&
            _containsAny(normalized, const [
              'assignment',
              'booking',
              'choice',
              'feedback',
              'folder',
              'forum',
              'label',
              'mediasite',
              'page',
              'quiz',
              'resource',
              'url',
            ]));
    final explicitlyRestrictsIspaceOverview = _containsAny(normalized, const [
      '只读取',
      '只列出',
      '只使用',
      '仅使用',
      '只复述',
      '不要使用',
      '不要查询',
      '不要读取',
      '不要推断',
      '勿读取',
      'overview only',
      'course list only',
      'only the course overview',
      'use only',
      'only use',
      'do not query',
      "don't query",
      'do not use',
      "don't use",
      'do not read',
      "don't read",
      'do not load',
      "don't load",
    ]);
    final mentionsIspaceOverviewDetails = _containsAny(normalized, const [
      'ddl',
      '截止',
      '作业',
      '测验',
      '课件',
      '文件',
      '老师',
      '教师',
      'deadline',
      'assignment',
      'quiz',
      'courseware',
      'file',
      'teacher',
      '成绩',
      'show grades',
      'showgrades',
    ]);
    final explicitIspaceCourseOverviewIntent =
        ispaceIntent &&
        _containsAny(normalized, const [
          '课程概览',
          '课程列表',
          '课程名称',
          '课程代码',
          'course overview',
          'course list',
          'course names',
          'course ids',
          'course codes',
        ]) &&
        (!mentionsIspaceOverviewDetails || explicitlyRestrictsIspaceOverview);
    final programmeFacultyIntent = _containsAny(normalized, const [
      '专业信息',
      '专业代码',
      '专业名称',
      '年级',
      '我的专业',
      '我们专业',
      '本专业',
      '结合专业',
      '结合一下专业',
      '专业导师',
      '专业老师',
      '专业教师',
      'my programme',
      'my program',
      'our programme',
      'our program',
      'my major',
      'our major',
      'my degree',
      'my discipline',
      'academic profile',
      'programme code',
      'program code',
      'programme name',
      'program name',
      'year level',
      'faculty for my major',
      'supervisor for my',
      'advisor for my',
    ]);
    final facultyPublicInfoIntent =
        _containsAny(normalized, const [
          '老师',
          '教师',
          '教授',
          '导师',
          'teacher',
          'faculty',
          'professor',
          'lecturer',
          'supervisor',
          'advisor',
        ]) &&
        _containsAny(normalized, const [
          '科研',
          '研究方向',
          '专业方向',
          '时间安排',
          '办公时间',
          '个人介绍',
          '简介',
          '任职',
          'research',
          'specialism',
          'specialization',
          'availability',
          'office hour',
          'biography',
          'profile',
        ]);
    final academicCalendarDocumentIntent =
        _containsAny(normalized, const [
          '校历 pdf',
          '校历pdf',
          '官方校历文件',
          'academic calendar pdf',
          'official academic calendar',
          'class schedule pdf',
          'official class schedule',
        ]) ||
        (_containsAny(normalized, const [
              'pdf',
              'document',
              'official document',
              '文件名',
              '链接',
              'file name',
              'filename',
              'https link',
              'link',
              'url',
            ]) &&
            _containsAny(normalized, const ['semester', 's1', 's2', '学期']) &&
            RegExp(
              r'(?:ay\s*)?20\d{2}\s*[-/]\s*(?:\d{2}|20\d{2})',
            ).hasMatch(normalized));
    final academicCalendarIntent =
        academicCalendarDocumentIntent ||
        _containsAny(normalized, const [
          '校历',
          '假期',
          '补课',
          '调休',
          'reading week',
          '阅读周',
          'academic calendar',
          'make up class',
          'holiday',
        ]);
    final taCourseIntent =
        _containsAny(normalized, const [
          'ta课',
          'ta 课',
          '助教课',
          '助教课程',
          '固定日程',
          '新建日程',
          '创建日程',
          '修改日程',
          '删除日程',
          '编辑日程',
          '新增日程',
          '个人日程',
        ]) ||
        RegExp(
          r'\b(?:ta\s+courses?|fixed\s+schedules?|personal\s+schedules?|(?:create|add|edit|update|delete)\s+(?:a\s+)?(?:schedule|event))\b',
          caseSensitive: false,
        ).hasMatch(normalized) ||
        (!hasMoodleModuleType &&
            RegExp(
              r'\b(?:my|our)\s+(?:(?:weekly|regular)\s+)?'
              r'(?:tutorials?|workshops?|lab\s+sessions?|office\s+hours?)\b',
              caseSensitive: false,
            ).hasMatch(normalized));
    final taCourseManagementIntent =
        taCourseIntent &&
        (_containsAny(normalized, const [
              '新建',
              '新增',
              '增加',
              '创建',
              '编辑',
              '修改',
              '删除',
              '移除',
              '移动',
              '移到',
              '挪到',
              '调到',
              '改到',
              '改为',
              '改成',
              '变更',
              '设为',
              '调整',
            ]) ||
            RegExp(
              r'\b(?:add|create|edit|update|delete|remove|move|reschedule|change)\b',
              caseSensitive: false,
            ).hasMatch(normalized));
    final taScheduleTargetIntent =
        _containsAny(normalized, const [
          '我的课表',
          '和我的课表',
          '与我的课表',
          '我其他安排',
          '我的其他安排',
        ]) ||
        RegExp(
          r'\b(?:my\s+schedule|my\s+classes|personal\s+schedule|my\s+other\s+plans)\b',
          caseSensitive: false,
        ).hasMatch(normalized);
    final taScheduleConflictIntent =
        _containsAny(normalized, const ['冲突', '撞课', '重叠']) ||
        RegExp(
          r'\b(?:conflicts?|clashes?|overlaps?)\b',
          caseSensitive: false,
        ).hasMatch(normalized);
    final taScheduleComparisonIntent =
        taScheduleTargetIntent && taScheduleConflictIntent;
    final explicitPersonalScheduleIntent =
        _containsAny(normalized, const [
          '课表',
          '我的安排',
          '安排我',
          '我有什么课',
          '我有啥课',
          '我的课程',
          '我今天',
          '我明天',
          '今天我',
          '明天我',
          '几点',
          'timetable',
          'my schedule',
          'my classes',
          'my class',
          'my agenda',
          'what do i have',
          "what's on my schedule",
          'what is on my schedule',
        ]) ||
        (!academicCalendarDocumentIntent &&
            _containsAny(normalized, const [
              'class schedule',
              'course schedule',
            ]));
    final generalAgendaIntent = _containsAny(normalized, const [
      '今天',
      '明天',
      '本周',
      '下周',
      '接下来',
      '要紧的',
      '待处理',
      '日程',
      'schedule',
      'calendar',
      'today',
      'tomorrow',
      'this week',
      'next week',
      'what should i do next',
      'what should i deal with next',
    ]);
    final useGeneralAgendaSources =
        generalAgendaIntent &&
        !facultyPublicInfoIntent &&
        !taCourseManagementIntent;
    final explicitMisScheduleIntent = _containsAny(normalized, const [
      'mis 课程',
      'mis课程',
      'mis 课表',
      'mis课表',
      'mis class',
      'mis course',
      'mis timetable',
      'mis schedule',
    ]);
    final explicitScheduleReferenceIntent =
        explicitMisScheduleIntent ||
        _containsAny(normalized, const [
          '课表',
          '上课',
          '几点',
          '我的安排',
          'timetable',
          'class schedule',
          'my schedule',
          'my classes',
          'my agenda',
        ]);
    final ispaceDeadlineOnlyIntent =
        ispaceIntent &&
        !explicitScheduleReferenceIntent &&
        ((useGeneralAgendaSources &&
                _containsAny(normalized, const [
                  '任务',
                  '待办',
                  'task',
                  'to-do',
                  'todo',
                ])) ||
            _containsAny(normalized, const [
              'ddl',
              '截止',
              '时间线',
              '逾期',
              'deadline',
              'due',
              'timeline',
              'overdue',
            ]));
    final calendarOnlyIntent =
        academicCalendarIntent &&
        !_containsAny(normalized, const [
          '安排',
          '日程',
          '课程',
          '课表',
          'ddl',
          '考试',
          'what do i have',
          'my schedule',
          'my agenda',
          'classes',
          'deadlines',
          'exams',
        ]);
    final scheduleIntent =
        (explicitPersonalScheduleIntent ||
            (useGeneralAgendaSources && !calendarOnlyIntent)) &&
        !ispaceDeadlineOnlyIntent &&
        (!taCourseManagementIntent || taScheduleComparisonIntent);
    final misExamIntent = _containsAny(normalized, const [
      '考试安排',
      '考试时间',
      '考试',
      '期末考试',
      '考场',
      '座位',
      'exam timetable',
      'exam schedule',
      'final exam',
      'exam room',
      'exam seat',
    ]);
    final historicalCourseRequest =
        _containsAny(normalized, const [
          '上学期',
          '上一学期',
          '去年',
          '往年',
          '历史课程',
          '以前的课程',
          'last semester',
          'previous term',
          'last year',
          'past course',
        ]) ||
        RegExp(r'\b20\d{2}\b').hasMatch(normalized);

    void include(AssistantContextSource source) {
      if (availableSources.contains(source)) {
        selected.add(source);
      }
    }

    if (programmeFacultyIntent) {
      include(AssistantContextSource.academicProfile);
    }

    if (_containsAny(normalized, const [
      '当前页面',
      '当前 flutter 页面',
      '当前 flutter 页面语义',
      '这个页面',
      '当前打开',
      '正在看的',
      '这门课',
      '这个作业',
      '这个测验',
      '这里',
      'current page',
      'current flutter page',
      'current flutter page semantics',
      'this page',
      'this course',
      'this assignment',
      'this quiz',
    ])) {
      include(AssistantContextSource.currentPage);
    }

    final needsTermCourses =
        !taCourseIntent &&
        !programmeFacultyIntent &&
        !academicCalendarDocumentIntent &&
        _containsAny(normalized, const [
          '课程',
          '老师',
          '教师',
          '教授',
          '导师',
          '办公室',
          '办公地点',
          '这学期',
          '本学期',
          '上学期',
          '上一学期',
          '剩下的课',
          '复习',
          '课件',
          '课程资料',
          '资料包',
          '打包',
          'zip',
          'course',
          'class',
          'teacher',
          'faculty',
          'professor',
          'office',
          'semester',
          'term',
        ]);
    final needsRichCourseContext = _containsAny(normalized, const [
      '哪些课程',
      '课程列表',
      '所有课程',
      '剩下的课',
      '这学期',
      '本学期',
      '上学期',
      '上一学期',
      '去年',
      '往年',
      '历史课程',
      '以前的课程',
      '老师',
      '教师',
      '教授',
      '导师',
      '办公室',
      '办公地点',
      '课件',
      '课程资料',
      '资料包',
      '打包',
      'zip',
      'which course',
      'course list',
      'all courses',
      'semester',
      'term',
      'teacher',
      'faculty',
      'professor',
      'lecturer',
      'supervisor',
      'advisor',
      'office',
      'courseware',
      'course material',
    ]);
    if (needsTermCourses && (!scheduleIntent || needsRichCourseContext)) {
      include(AssistantContextSource.courses);
      if (!historicalCourseRequest) {
        include(AssistantContextSource.termCourses);
      }
    }
    if (!programmeFacultyIntent &&
        _containsAny(normalized, const [
          '老师',
          '教师',
          '教授',
          '导师',
          '课件',
          '讲义',
          '课程资料',
          '章节',
          '课程内容',
          '课程目录',
          '资料类型',
          '模块类型',
          '可见资料',
          '课程进度',
          '进度百分比',
          '开始时间',
          '开课时间',
          '开始日期',
          '结束时间',
          '结束日期',
          '开放日期',
          '截止日期',
          '开放时间',
          '关闭时间',
          '关闭日期',
          '隐藏模块',
          '不可见模块',
          '完成追踪',
          '手动完成',
          '自动完成',
          '文件清单',
          '上学期',
          '上一学期',
          '去年',
          '往年',
          '历史课程',
          '以前的课程',
          'teacher',
          'faculty',
          'professor',
          'lecturer',
          'supervisor',
          'advisor',
          'courseware',
          'lecture note',
          'course material',
          'course catalog',
          'material type',
          'module type',
          'visible material',
          'course progress',
          'progress percentage',
          'course start',
          'start date',
          'course end',
          'end date',
          'open date',
          'close date',
          'opening time',
          'closing time',
          'hidden module',
          'inaccessible module',
          'completion tracking',
          'manual completion',
          'automatic completion',
          'module',
          'section',
          'last semester',
          'previous term',
          'last year',
          'past course',
        ])) {
      include(AssistantContextSource.ispaceCourseCatalog);
      include(AssistantContextSource.ispaceToolResults);
    }
    if (_containsAny(normalized, const [
      'ddl',
      '截止',
      '作业',
      '提交',
      '测验',
      '待办',
      '要紧的',
      '待处理',
      '需要处理',
      '时间线',
      '逾期',
      'assignment',
      'quiz',
      'deadline',
      'due',
      'to-do',
      'todo',
      'upcoming work',
      'timeline',
      'overdue',
    ])) {
      include(AssistantContextSource.deadlines);
    }
    if (_containsAny(normalized, const [
      '作业要求',
      '作业内容',
      '提交作业',
      '上传作业',
      '帮我提交',
      '作业文件',
      '文件提交',
      '测验',
      'assignment requirement',
      'submit assignment',
      'upload assignment',
      'quiz',
    ])) {
      include(AssistantContextSource.ispaceActivity);
      include(AssistantContextSource.ispaceToolResults);
      include(AssistantContextSource.deadlines);
    }
    final needsQuizAttempt =
        _containsAny(normalized, const [
          '答题',
          '作答',
          '答案',
          '保存答案',
          '交卷',
          '提交测验',
          '完成测验',
          'answer quiz',
          'quiz answer',
          'save answer',
          'finish quiz',
          'submit quiz',
        ]) ||
        (_containsAny(normalized, const ['测验', 'quiz']) &&
            _containsAny(normalized, const ['提交', '完成', 'submit', 'finish']));
    if (needsQuizAttempt) {
      include(AssistantContextSource.ispaceQuizAttempt);
      include(AssistantContextSource.ispaceActivity);
      include(AssistantContextSource.ispaceToolResults);
      include(AssistantContextSource.deadlines);
    }
    final needsSchedule =
        scheduleIntent ||
        (!facultyPublicInfoIntent &&
            !historicalCourseRequest &&
            needsTermCourses &&
            needsRichCourseContext);
    if (needsSchedule) {
      include(AssistantContextSource.schedule);
      if (!taCourseManagementIntent) {
        include(AssistantContextSource.deadlines);
      }
      if (needsTermCourses && needsRichCourseContext) {
        include(AssistantContextSource.termCourses);
      }
    }
    if (academicCalendarIntent ||
        (useGeneralAgendaSources &&
            !ispaceDeadlineOnlyIntent &&
            !needsQuizAttempt)) {
      include(AssistantContextSource.academicCalendar);
    }
    if (misExamIntent ||
        (useGeneralAgendaSources &&
            !ispaceDeadlineOnlyIntent &&
            !needsQuizAttempt &&
            !academicCalendarDocumentIntent)) {
      include(AssistantContextSource.examTimetable);
    }
    if (_containsAny(normalized, const [
      '邮件',
      '邮箱',
      '收件箱',
      '发给',
      '回复',
      'email',
      'mail',
      'inbox',
    ])) {
      include(AssistantContextSource.selectedMail);
      include(AssistantContextSource.mailSummaries);
      include(AssistantContextSource.mailToolResults);
      include(AssistantContextSource.courses);
      include(AssistantContextSource.termCourses);
    }
    final moodleCompletionOrChoiceIntent = _containsAny(normalized, const [
      '标记完成',
      '标为完成',
      '设为完成',
      '改为未完成',
      '取消完成',
      '完成状态',
      'choice活动',
      'choice 活动',
      '提交choice',
      '提交 choice',
      'mark as complete',
      'mark as done',
      'mark incomplete',
      'completion status',
      'choice activity',
      'submit choice',
      'submit the choice',
    ]);
    if (!moodleCompletionOrChoiceIntent &&
        _containsAny(normalized, const [
          '活动',
          '讲座',
          '比赛',
          '报名',
          'activity',
          'event',
        ])) {
      include(AssistantContextSource.schoolActivities);
    }
    if (taCourseIntent && (!scheduleIntent || taCourseManagementIntent)) {
      include(AssistantContextSource.taCourses);
    }
    if (ispaceIntent) {
      if (!ispaceDeadlineOnlyIntent && !explicitMisScheduleIntent) {
        include(AssistantContextSource.courses);
      }
      include(AssistantContextSource.deadlines);
      if (_containsAny(normalized, const [
        '内容',
        '文件',
        '课件',
        '老师',
        '教师',
        'content',
        'file',
        'material',
        'teacher',
      ])) {
        include(AssistantContextSource.ispaceCourseCatalog);
        include(AssistantContextSource.ispaceToolResults);
      }
      if (_containsAny(normalized, const [
        '作业',
        '提交',
        '测验',
        'assignment',
        'quiz',
      ])) {
        include(AssistantContextSource.ispaceActivity);
        include(AssistantContextSource.ispaceToolResults);
      }
    }

    if (_containsAny(normalized, const [
      '课程成绩',
      '我的成绩',
      'ispace成绩',
      'ispace 成绩',
      'course grade',
      'my grade',
      'grade report',
    ])) {
      include(AssistantContextSource.courses);
      include(AssistantContextSource.ispaceCourseCatalog);
      include(AssistantContextSource.ispaceToolResults);
    }

    if (moodleCompletionOrChoiceIntent) {
      include(AssistantContextSource.courses);
      include(AssistantContextSource.ispaceCourseCatalog);
      include(AssistantContextSource.ispaceToolResults);
    }

    if (hasMoodleModuleType && moodleModuleMutationIntent) {
      include(AssistantContextSource.courses);
      include(AssistantContextSource.ispaceCourseCatalog);
      include(AssistantContextSource.ispaceToolResults);
    }

    if (explicitIspaceCatalogIntent) {
      include(AssistantContextSource.ispaceCourseCatalog);
      include(AssistantContextSource.ispaceToolResults);
      selected.remove(AssistantContextSource.courses);
      selected.remove(AssistantContextSource.termCourses);
      if (!explicitScheduleReferenceIntent &&
          !taScheduleComparisonIntent &&
          !_containsAny(normalized, const ['课程安排', 'course schedule'])) {
        selected.remove(AssistantContextSource.schedule);
      }
      if (!_containsAny(normalized, const [
        'ddl',
        '截止',
        '待办',
        '作业',
        'deadline',
        'due',
        'to-do',
        'todo',
        'assignment',
      ])) {
        selected.remove(AssistantContextSource.deadlines);
      }
    }

    if (genericMoodleCatalogAggregateIntent &&
        !moodleModuleMutationIntent &&
        !namedMoodleModuleDetailIntent) {
      selected.remove(AssistantContextSource.schoolActivities);
      selected.remove(AssistantContextSource.ispaceActivity);
      selected.remove(AssistantContextSource.ispaceQuizAttempt);
      if (!_containsAny(normalized, const [
        'ddl',
        '截止',
        '待办',
        '逾期',
        'deadline',
        'due',
        'to-do',
        'todo',
        'overdue',
      ])) {
        selected.remove(AssistantContextSource.deadlines);
      }
    }

    if (explicitIspaceCourseOverviewIntent && !explicitIspaceCatalogIntent) {
      selected.clear();
      include(AssistantContextSource.courses);
    }

    if (_containsAny(normalized, const [
      '哪个先截止',
      '哪一个先截止',
      '相差多久',
      'which is due first',
      'which deadline comes first',
      'how far apart',
    ])) {
      selected.clear();
      include(AssistantContextSource.deadlines);
    }

    if (ispaceEvidenceGapIntent) {
      selected.clear();
      include(AssistantContextSource.deadlines);
      include(AssistantContextSource.ispaceCourseCatalog);
      include(AssistantContextSource.ispaceToolResults);
    }

    final needsLocation = _containsAny(normalized, const [
      '我在哪',
      '我现在在哪',
      '当前位置',
      '我的位置',
      '定位',
      '附近',
      '离我',
      'current location',
      'where am i',
      'near me',
    ]);
    if (needsLocation) {
      selected.add(AssistantContextSource.currentLocation);
    }

    return AssistantToolPlan(
      sources: Set.unmodifiable(selected),
      needsCurrentLocation: needsLocation,
      needsSchedule: needsSchedule && !explicitIspaceCourseOverviewIntent,
    );
  }

  bool _containsAny(String source, List<String> terms) {
    return terms.any(source.contains);
  }
}
