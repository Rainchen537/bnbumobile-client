// Synthetic review data. No account, network, persistence or production routes.
import 'package:flutter/material.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/timetable_data.dart';

enum CatalogKind {
  homeCourse,
  homeDeadline,
  homeEmpty,
  ispaceDeadline,
  deadlineDetail,
  agendaCourse,
  courseDetail,
  agendaTa,
  agendaEvent,
  agendaDeadline,
  gridCourse,
  gridTa,
  gridEvent,
  gridDeadline,
  examWeek,
  examDay,
  courseRow,
  moduleRow,
  manager,
}

class CatalogEntry {
  const CatalogEntry(
    this.kind,
    this.name,
    this.page,
    this.source,
    this.current,
    this.expansion,
    this.proposal,
  );
  final CatalogKind kind;
  final String name, page, source, current, expansion, proposal;
  String get id => kind.name;
}

const catalogEntries = <CatalogEntry>[
  CatalogEntry(
    CatalogKind.homeCourse,
    '首页 · 下一节课',
    '首页',
    'lib/pages/home_page.dart · _buildOverviewCard',
    '课程色／5px色条；首行图标、下一节课、教室、上课状态；中部课程名；末行时钟、起止时间、进入箭头。普通表面与1px边框。',
    '最小116；标题最多2行、教室1行后省略；字号>1.3时教室移至第二行且最多2行。首行状态不限制行数。宽屏两卡各132起，随字号增高；末行跟随标题。',
    '保留课程色、教室和上课状态；标题预留两行，时间与箭头固定底部。普通卡不改变字段职责，宽屏继续成对等高。',
  ),
  CatalogEntry(
    CatalogKind.homeDeadline,
    '首页 · 最近 DDL',
    '首页',
    'lib/pages/home_page.dart · _buildDeadlineCard',
    '品牌蓝，逾期危险红；5px色条；17px活动图标、iSpace、课程名与右上完整截止时间；两行标题；底部倒计时与箭头。',
    '最小116；来源普通1行／大字2行；标题最多2行；倒计时1行省略。时间优先完整，过宽缩放；标题变短会令底部上移。首页每30秒更新。',
    '沿用蓝色与现有逾期提示；无年份日期；固定两行标题区与底部，倒计时600字重。24小时内统一“仅剩”。',
  ),
  CatalogEntry(
    CatalogKind.homeEmpty,
    '首页 · 同步／空状态',
    '首页',
    'lib/pages/home_page.dart · _buildCourseCard / _buildDeadlineCard',
    '复用首页概览外壳；按同步、未登录、无后续课程或无DDL显示占位标题、状态与--时间。课程空态仍可进入课表，DDL空态无箭头。',
    '沿用概览卡最小116与标题2行；标题会改变高度，宽屏仍占一张等高卡的位置。',
    '本轮保留首页占位的布局稳定性；不造倒计时或无效箭头。是否改为无边框空态保留为后续取舍。',
  ),
  CatalogEntry(
    CatalogKind.ispaceDeadline,
    'iSpace · 待办摘要',
    'iSpace',
    'lib/widgets/timeline_summary_card.dart / lib/pages/ispace_page.dart',
    '与首页共用摘要组件但不重复iSpace标识。当前日期含年；蓝色、逾期红色；底部当前为天数或h/m，24小时内没有“仅剩”。',
    '来源1行、大字2行；标题2行；底部1行；最小116。当前无独立倒计时定时器，依赖页面重建。<1分钟还未截止也可能被标逾期。',
    '保留活动类型和蓝色语义；年月格式改为月日时分，与首页共用倒计时表达。底部锚定，标题短时保留空白。',
  ),
  CatalogEntry(
    CatalogKind.deadlineDetail,
    '课表 · DDL 详情摘要',
    '课表',
    'lib/pages/schedule_page.dart · _showDeadlineDetail',
    '共用iSpace摘要，强调色保持红色；不显示iSpace字符或箭头，整卡不可点；下方独立打开iSpace按钮。当前底部是活动状态。',
    '摘要标题最多2行；说明在卡片外完整换行并使弹层滚动。手机当前缺DDL详情标题，宽屏有标题与关闭。',
    '补齐DDL详情标题；摘要底部使用加粗倒计时；详细活动状态和说明留在下方；完整标题允许增高。保留独立打开按钮，无虚假箭头。',
  ),
  CatalogEntry(
    CatalogKind.agendaCourse,
    '纵表 · MIS 课程',
    '课表',
    'lib/pages/schedule_page.dart · _buildCourseSummaryCard',
    '课程色／5px通高色条；首行时钟、起止时间、箭头；中间课程名；底部地点与独立教师链接。教师链接至少44高。',
    '没有固定高度，IntrinsicHeight随内容增长；标题最多2行，地点与教师各1行省略；教师存在时末行至少44高。',
    '按用户2026-09-12反馈恢复原排列：左上时钟与时间、右上箭头、左下地点、右下教师。四角内缩统一，44px教师命中区向卡内延伸；标题预留两行。',
  ),
  CatalogEntry(
    CatalogKind.courseDetail,
    '课表 · 课程详情摘要',
    '课表',
    'lib/pages/schedule_page.dart · _showCourseDetail',
    '复用纵表课程摘要，去掉整卡点击与箭头，教师链接仍保留；弹层有课程详情标题与关闭。',
    '摘要标题仍被限制2行；本次时间、类型、学分、节次、全部课时、备注在下方按内容增高和滚动。',
    '按用户反馈恢复原课程卡排列和标题两行／地点一行限制；左上时间、左下地点、右下教师固定；详情不显示箭头，其他字段继续在下方。',
  ),
  CatalogEntry(
    CatalogKind.agendaTa,
    '纵表 · TA',
    '课表',
    'lib/pages/schedule_page.dart · _buildCourseSummaryCard',
    '与MIS课程同壳，名称与颜色继承所属课程；不显示教师链接，也不在卡面额外写TA。',
    '标题2行、地点1行；缺少教师44高命中区，因此通常比MIS课程卡矮。',
    '继承课程名称和颜色，沿用原左上时间／右上箭头／左下地点排列；与MIS四角内缩及底部预留一致，无教师时右下留空。',
  ),
  CatalogEntry(
    CatalogKind.agendaEvent,
    '纵表 · 普通固定日程',
    '课表',
    'lib/pages/schedule_page.dart · _buildCourseSummaryCard',
    '复用课程摘要，但名称、地点和独立日程色来自本机日程；无教师链接。',
    '标题2行、地点1行；随内容增高；同样受无教师行导致的高度差影响。',
    '保留独立日程名称和配色，恢复原时间与箭头位置；地点固定左下，右下留空；四角内缩与MIS／TA一致。',
  ),
  CatalogEntry(
    CatalogKind.agendaDeadline,
    '纵表 · DDL',
    '课表',
    'lib/pages/schedule_page.dart · _buildDeadlineSummaryCard',
    '红色5px条、警告图标；首行截止时间与箭头；标题2行；底部课程名。当前没有倒计时。',
    '左条固定116高，正文可超过116而色条不跟随；课程名1行，时间1行均省略。',
    '保留用户2026-09-12认可的红色iSpace摘要方案：活动图标、课程与截止在上，倒计时与箭头在下，全高色条；尚未迁入正式页面。',
  ),
  CatalogEntry(
    CatalogKind.gridCourse,
    '横表 · MIS 课程块',
    '横表',
    'lib/pages/schedule_page.dart · _buildMeetingBlock / _buildMeetingTextContent',
    '课程色8%底、0.5px边界、1.5px色条；课程名与下方时间／教室，空教室时用教师；无独立箭头。',
    '高度严格按时间轴与时长分配，不被文字撑高；先保留一行标题，再分配时间地点与剩余标题行；极短块只裁显示标题。',
    '保持当前结构和时间比例；不套摘要卡最小高度、两行占位或底部箭头；预览方案补齐字号测量。短时段点击进入完整详情。',
  ),
  CatalogEntry(
    CatalogKind.gridTa,
    '横表 · TA 课程块',
    '横表',
    'lib/pages/schedule_page.dart · _buildMeetingBlock',
    '同课程块，名称和颜色继承课程；时间、教室来自TA；无教师回退、无TA标记。',
    '由真实时长决定高度，文字按可用高度截断；命中高度至少44。',
    '保留横表几何和来源，不增加浮标或摘要卡留白。',
  ),
  CatalogEntry(
    CatalogKind.gridEvent,
    '横表 · 普通日程块',
    '横表',
    'lib/pages/schedule_page.dart · _buildMeetingBlock',
    '同横表课程块，使用独立日程色、名称、时间和地点。',
    '严格按时长占位，文字不能撑高；无教师回退。',
    '继续与时间轴绑定，共用课程块的排版规则。',
  ),
  CatalogEntry(
    CatalogKind.gridDeadline,
    '横表 · DDL 时间点',
    '横表',
    'lib/pages/schedule_page.dart · _buildDeadlineBlock / _buildDeadlineCard',
    '红色圆形警告标记、白色图标和轻阴影；标题与日期在Tooltip，点击进入DDL详情。',
    '固定小图形，至少44命中；绝不按标题增加网格高度。',
    '保留点状时间标记；详情负责完整内容，不强行变成矩形卡。',
  ),
  CatalogEntry(
    CatalogKind.examWeek,
    '课表 · 本周考试',
    '考试',
    'lib/pages/schedule_page.dart · _buildExamCard(showDate: true)',
    '普通直角表面；红色4px条位于内边距内；首行月日、星期、时间；课程名、课程代码、考场、座位、备注。无点击箭头。',
    '课程名最多2行，其他非空字段完整换行；内容自然撑高，色条随IntrinsicHeight增高。',
    '色条试改为贴左通高5px，与摘要卡对齐；完整保留时间、考场、座位和备注，不追求固定高度。',
  ),
  CatalogEntry(
    CatalogKind.examDay,
    '纵表 · 当日考试',
    '考试',
    'lib/pages/schedule_page.dart · _buildExamCard(showDate: false)',
    '复用本周考试卡，首行只显示起止时间；日期由纵表分组标题承担。',
    '与本周考试相同，备注等内容会撑高；空字段整项隐藏。',
    '与本周考试同壳，继续省去重复日期；不新增倒计时或进入箭头。',
  ),
  CatalogEntry(
    CatalogKind.courseRow,
    'iSpace · 课程列表行',
    'iSpace',
    'lib/pages/ispace_page.dart · _buildCourseCard',
    '当前实际为无底托ListTile；17px/500完整课程名，非空短名在下方，右侧18px箭头。',
    '全名和短名未设maxLines，完整换行撑高；短名为空则隐藏整行。',
    '保留目录型文字行，不增加色条、倒计时或固定高度。',
  ),
  CatalogEntry(
    CatalogKind.moduleRow,
    'iSpace · 章节活动行',
    'iSpace',
    'lib/widgets/ispace_course_workspace.dart · ListTile / _moduleDeadline',
    '20px官方活动图标、16px/400标题；可选截止日期；完成态勾号或右箭头。',
    '标题与日期自然换行；无截止字段则无副行；完成状态仅更换尾图标。',
    '保持轻量课程目录；仅在预览中试用不含年的紧凑截止时间，不增加第二个倒计时层。',
  ),
  CatalogEntry(
    CatalogKind.manager,
    '固定日程 · 管理行',
    '管理',
    'lib/pages/ta_course_manager_page.dart · _buildCourseCard',
    '课程／日程色4%底、1.5px左边线；16px标题、13px星期时间、12px类型／重复／地点；右侧三点菜单；失联TA显示警告。',
    '各文字未设maxLines，完整换行撑高；所属课程不可用时新增警告行。',
    '保留管理密度、重复规则与菜单；不套大号概览卡，不添加虚假进入箭头。',
  ),
];

enum CatalogTextCase { short, normal, long, extreme }

enum CatalogDueCase { future, boundary, urgent, minute, overdue, missing }

class CatalogFixture {
  const CatalogFixture({
    this.textCase = CatalogTextCase.normal,
    this.dueCase = CatalogDueCase.urgent,
    this.english = false,
    this.activity = 'assign',
    this.missingFields = false,
    this.courseStatus = '今天稍后',
    this.emptyState = '无数据',
  });
  final CatalogTextCase textCase;
  final CatalogDueCase dueCase;
  final bool english, missingFields;
  final String activity;
  final String courseStatus, emptyState;
  static final now = DateTime(2026, 9, 11, 12);
  String get courseTitle => switch (textCase) {
    CatalogTextCase.short => english ? 'Interaction Design' : '交互设计',
    CatalogTextCase.normal => 'Human–Computer Interaction',
    CatalogTextCase.long =>
      'Human–Computer Interaction: Inclusive Systems, Research and Prototyping',
    CatalogTextCase.extreme =>
      'Human–Computer Interaction: Inclusive Systems, Research and Prototyping · 人机交互与校园无障碍系统设计、实验研究及原型评估专题',
  };
  String get title => switch (textCase) {
    CatalogTextCase.short => english ? 'Reading reflection' : '阅读反思',
    CatalogTextCase.normal =>
      english ? 'Assignment 2: Campus accessibility audit' : '作业二：校园无障碍设计调研',
    CatalogTextCase.long =>
      'Assignment 2: Campus accessibility audit and inclusive interface prototype evaluation',
    CatalogTextCase.extreme =>
      'Assignment 2: Campus accessibility audit and inclusive interface prototype evaluation · 请提交完整调研报告、访谈记录、原型文件及个人反思，所有附件均需列明来源',
  };
  String get room => missingFields
      ? ''
      : textCase == CatalogTextCase.extreme
      ? 'T2-306 · Learning Commons Collaborative Design Studio'
      : 'T2-306';
  DateTime? get due => switch (dueCase) {
    CatalogDueCase.future => now.add(const Duration(days: 3, hours: 6)),
    CatalogDueCase.boundary => now.add(const Duration(hours: 24)),
    CatalogDueCase.urgent => now.add(const Duration(hours: 5, minutes: 30)),
    CatalogDueCase.minute => now.add(const Duration(seconds: 45)),
    CatalogDueCase.overdue => now.subtract(const Duration(hours: 2)),
    CatalogDueCase.missing => null,
  };
  TimelineItem get item => TimelineItem(
    id: 1,
    title: title,
    activityState: '待完成',
    activityType: activity,
    moduleName: activity,
    description: '',
    courseName: missingFields ? '' : courseTitle,
    courseId: 1,
    instanceId: 1,
    url: '',
    sortTime: due,
    formattedTime: '',
    isOverdue: dueCase == CatalogDueCase.overdue,
  );
  TimetableMeeting get meeting => TimetableMeeting(
    weekday: 5,
    dayLabel: 'Fri',
    startLabel: '14:00',
    endLabel: '15:50',
    startMinutes: 840,
    endMinutes: 950,
    room: room,
  );
  TimetableCourse course({bool event = false}) => TimetableCourse(
    section: '1001',
    category: 'Major Required',
    code: event ? 'DEMO-EVENT' : 'COMP 3023',
    name: event ? (english ? 'Project group meeting' : '项目小组讨论') : courseTitle,
    teacher: missingFields ? '' : 'Alex Chen',
    meetings: [meeting],
    rooms: [room],
    units: '3',
    remark: '',
  );
}

String previewText(BuildContext context, String chinese, String english) =>
    Localizations.localeOf(context).languageCode == 'en' ? english : chinese;
