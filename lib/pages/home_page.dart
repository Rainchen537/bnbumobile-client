import '../models/campus_landmark.dart';
import '../services/campus_landmark_store.dart';
import 'campus_landmarks_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../config/app_config.dart';
import '../models/campus_time.dart';
import '../models/home_overview.dart';
import '../models/timeline_item.dart';
import '../services/assistant_history_store.dart';
import '../services/home_card_visibility_service.dart';
import '../services/study_history_summary.dart';
import '../services/study_window_manager.dart';
import '../state/ai_assistant_controller.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../theme/campus_reference_theme.dart';
import '../theme/course_color_palette.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/timeline_summary_card.dart';
import 'academic_calendar_page.dart';
import 'campus_navigation_page.dart';
import 'campus_directory_page.dart';
import 'duoduo_campus_wall_page.dart';
import 'official_web_page.dart';
import 'leave_application_page.dart';
import 'cis_checkin_page.dart';
import 'grade_report_page.dart';
import 'official_campus_map_page.dart';
import 'student_ecard_page.dart';
import 'timeline_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onGoToIspace,
    required this.onGoToSchedule,
    required this.onGoToUser,
    this.onOpenCourse,
    this.homeCardVisibilityService,
    this.clock = DateTime.now,
  });

  final AppSessionController controller;
  final VoidCallback onGoToIspace;
  final VoidCallback onGoToSchedule;
  final VoidCallback onGoToUser;
  final ValueChanged<HomeCourseOccurrence>? onOpenCourse;
  final HomeCardVisibilityService? homeCardVisibilityService;
  final DateTime Function() clock;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const double _wideOverviewHeight = 276;

  final DateFormat _timeFormatter = DateFormat('HH:mm');
  late DateTime _now;
  Timer? _clockTimer;
  String? _requestedTimetableOwner;
  bool _refreshScheduled = false;
  AppSessionLease? _checkinPreloadLease;
  bool _checkinPreloadScheduled = false;
  bool _homeCardVisibilityLoaded = false;
  AiAssistantController? _assistantController;
  late HomeCardVisibilityService _homeCardVisibilityService;
  late bool _ownsHomeCardVisibilityService;
  HomeCardVisibility _homeCardVisibility = HomeCardVisibility.defaults;

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = widget.clock();
      });
    });
    widget.controller.addListener(_handleControllerChanged);
    CampusLandmarkStore.shared.addListener(_landmarksChanged);
    unawaited(CampusLandmarkStore.shared.refresh());
    _configureHomeCardVisibilityService(widget.homeCardVisibilityService);
    unawaited(_initializeHomeCardVisibility());
    _scheduleTimetableRefresh();
    _scheduleCheckinPreload();
  }

  void _openDuoduoCampusWall() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const DuoduoCampusWallPage(),
      ),
    );
  }

  void _openStudentEcard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StudentEcardPage(
          controller: widget.controller,
          onGoToUser: widget.onGoToUser,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.homeCardVisibilityService,
      widget.homeCardVisibilityService,
    )) {
      if (_ownsHomeCardVisibilityService) {
        _homeCardVisibilityService.dispose();
      }
      _configureHomeCardVisibilityService(widget.homeCardVisibilityService);
      unawaited(_initializeHomeCardVisibility());
    }
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
    _requestedTimetableOwner = null;
    _checkinPreloadLease = null;
    _scheduleTimetableRefresh();
    _scheduleCheckinPreload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AssistantContextScope.maybeAssistantControllerOf(
      context,
    );
    if (identical(controller, _assistantController)) return;
    _assistantController = controller;
    if (controller != null) unawaited(controller.initialize());
  }

  @override
  void dispose() {
    CampusLandmarkStore.shared.removeListener(_landmarksChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    _clockTimer?.cancel();
    if (_ownsHomeCardVisibilityService) {
      _homeCardVisibilityService.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshHomeCardVisibility());
    }
  }

  void _configureHomeCardVisibilityService(HomeCardVisibilityService? service) {
    _homeCardVisibilityLoaded = false;
    _homeCardVisibility = HomeCardVisibility.defaults;
    _homeCardVisibilityService =
        service ?? const DefaultHomeCardVisibilityService();
    _ownsHomeCardVisibilityService = false;
  }

  Future<void> _initializeHomeCardVisibility() async {
    final service = _homeCardVisibilityService;
    if (service is CachedHomeCardVisibilityService) {
      final cachedService = service as CachedHomeCardVisibilityService;
      final cached = await cachedService.loadCached();
      if (!mounted || !identical(service, _homeCardVisibilityService)) return;
      if (cached != null) {
        if (cached.version >= _homeCardVisibility.version) {
          setState(() {
            _homeCardVisibility = cached;
            _homeCardVisibilityLoaded = true;
          });
          _scheduleCheckinPreload();
        }
      } else {
        setState(() => _homeCardVisibilityLoaded = true);
      }
    } else if (mounted && identical(service, _homeCardVisibilityService)) {
      setState(() => _homeCardVisibilityLoaded = true);
    }
    await _refreshHomeCardVisibility(service: service);
  }

  void _landmarksChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshHomeCardVisibility({
    HomeCardVisibilityService? service,
  }) async {
    final activeService = service ?? _homeCardVisibilityService;
    final visibility = await activeService.load();
    if (!mounted || !identical(activeService, _homeCardVisibilityService)) {
      return;
    }
    if (visibility.version < _homeCardVisibility.version) return;
    setState(() {
      _homeCardVisibilityLoaded = true;
      _homeCardVisibility = visibility;
    });
    _scheduleCheckinPreload();
  }

  void _handleControllerChanged() {
    if (!widget.controller.isLoggedIn) {
      _requestedTimetableOwner = null;
      _checkinPreloadLease = null;
      return;
    }
    _scheduleTimetableRefresh();
    _scheduleCheckinPreload();
  }

  void _scheduleCheckinPreload() {
    if (_checkinPreloadScheduled || _checkinPreloadLease?.isActive == true) {
      return;
    }
    _checkinPreloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkinPreloadScheduled = false;
      if (!mounted ||
          !_homeCardVisibilityLoaded ||
          !_homeCardVisibility.isVisible(HomeServiceCard.checkIn) ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        return;
      }
      final controller = widget.controller;
      if (!controller.canOpenOfficialSchoolSession) return;
      final lease = controller.captureSessionLease();
      if (lease == null || !lease.isActive) return;
      _checkinPreloadLease = lease;
      unawaited(controller.prewarmCheckinProjects());
    });
  }

  void _scheduleTimetableRefresh() {
    if (_refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) {
        return;
      }
      final controller = widget.controller;
      final owner = controller.username;
      if (!controller.isLoggedIn ||
          owner == null ||
          controller.timetable != null ||
          controller.isLoadingTimetable ||
          _requestedTimetableOwner == owner) {
        return;
      }
      _requestedTimetableOwner = owner;
      unawaited(controller.refreshTimetable());
    });
  }

  Future<void> _refresh() async {
    final visibilityRefresh = _refreshHomeCardVisibility();
    if (!widget.controller.isLoggedIn) {
      await visibilityRefresh;
      widget.onGoToUser();
      return;
    }
    await Future.wait<void>([
      widget.controller.refreshTimeline(),
      widget.controller.refreshTimetable(),
      visibilityRefresh,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final listenable = _assistantController == null
        ? widget.controller
        : Listenable.merge([widget.controller, _assistantController!]);
    return BnbuLoadingRegion(
      child: AnimatedBuilder(
        animation: listenable,
        builder: (context, _) {
          final controller = widget.controller;
          final nextCourse = findNextCourseOccurrence(
            controller.timetable,
            now: _now,
          );
          final nextDeadline = findRelevantDeadline(
            controller.timelineItems,
            now: _now,
          );
          final isLoading =
              controller.isLoadingTimeline || controller.isLoadingTimetable;

          return Scaffold(
            backgroundColor: tokens.canvas,
            body: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final windowClass = BnbuBreakpoints.fromWidth(
                    constraints.maxWidth,
                  );
                  final horizontalPadding = switch (windowClass) {
                    BnbuWindowClass.compact => tokens.space16,
                    BnbuWindowClass.medium => tokens.space24,
                    BnbuWindowClass.expanded => tokens.space32,
                  };
                  final bottomObstruction =
                      windowClass == BnbuWindowClass.compact
                      ? MediaQuery.paddingOf(context).bottom
                      : 0.0;
                  return BnbuRefreshIndicator(
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      key: const ValueKey('home-scroll-view'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            windowClass == BnbuWindowClass.compact
                                ? tokens.space12
                                : tokens.space24,
                            horizontalPadding,
                            tokens.space32 + bottomObstruction,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: BnbuConstrainedContent(
                              child: _buildAdaptiveHomeContent(
                                context,
                                windowClass: windowClass,
                                nextCourse: nextCourse,
                                nextDeadline: nextDeadline,
                                isLoading: isLoading,
                                studyConversations:
                                    _assistantController
                                        ?.studyConversationHistory ??
                                    const <AssistantConversation>[],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdaptiveHomeContent(
    BuildContext context, {
    required BnbuWindowClass windowClass,
    required HomeCourseOccurrence? nextCourse,
    required HomeDeadline? nextDeadline,
    required bool isLoading,
    required List<AssistantConversation> studyConversations,
  }) {
    final tokens = context.bnbuTheme;
    final controller = widget.controller;
    final courseCard = _buildCourseCard(
      context,
      occurrence: nextCourse,
      isLoggedIn: controller.isLoggedIn,
      isLoading: controller.isLoadingTimetable,
      error: controller.timetableError,
    );
    final deadlineCard = _buildDeadlineCard(
      context,
      deadline: nextDeadline,
      isLoggedIn: controller.isLoggedIn,
      isLoading: controller.isLoadingTimeline,
    );
    final progress = BnbuUpdateProgress(
      active: isLoading,
      color: tokens.brandBlue,
    );

    if (windowClass == BnbuWindowClass.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDateHeader(context),
          progress,
          SizedBox(height: tokens.space16),
          courseCard,
          SizedBox(height: tokens.space12),
          deadlineCard,
          SizedBox(height: tokens.space24),
          _buildQuickAccessPanel(context, windowClass: windowClass),
        ],
      );
    }

    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final wideOverviewHeight =
        _wideOverviewHeight + (textScale > 1 ? (textScale - 1) * 200 : 0);
    return Column(
      key: const ValueKey('home-wide-workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        progress,
        SizedBox(
          height: wideOverviewHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 184, child: _buildExpandedDatePanel(context)),
              SizedBox(width: tokens.space24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: courseCard),
                    SizedBox(height: tokens.space12),
                    Expanded(child: deadlineCard),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space24),
        _buildQuickAccessPanel(context, windowClass: windowClass),
        if (windowClass.isExpanded && AppConfig.studyModeEnabled) ...[
          SizedBox(height: tokens.space24),
          _buildStudyModePanel(context, studyConversations),
        ],
      ],
    );
  }

  Widget _buildExpandedDatePanel(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final foreground = Colors.white.withValues(alpha: 0.96);
    return BnbuSurfaceCard(
      key: const ValueKey('home-expanded-date-panel'),
      backgroundColor: const Color(0xFF1E3A5F),
      borderColor: const Color(0xFF31577F),
      padding: EdgeInsets.fromLTRB(
        tokens.space16,
        tokens.space24,
        tokens.space16,
        tokens.space16,
      ),
      child: SizedBox(
        height: 236,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BnbuText(
              context.l10n.formatMonth(_now),
              style: theme.textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            BnbuText(
              DateFormat('dd').format(_now),
              style: theme.textTheme.displaySmall?.copyWith(
                color: foreground,
                fontSize: 72,
                height: 0.98,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Container(
              width: 32,
              height: 2,
              color: Colors.white.withValues(alpha: 0.72),
            ),
            SizedBox(height: tokens.space12),
            BnbuText(
              _weekdayLabel(_now.weekday),
              style: theme.textTheme.titleLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: tokens.space4),
            BnbuText(
              DateFormat('yyyy').format(_now),
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.70),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuText(
      _todayLabel(_now),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildCourseCard(
    BuildContext context, {
    required HomeCourseOccurrence? occurrence,
    required bool isLoggedIn,
    required bool isLoading,
    required String? error,
  }) {
    final tone = _courseTone(occurrence?.phase);
    final timetable = widget.controller.timetable;
    final courseAccent = occurrence == null || timetable == null
        ? null
        : CourseColorPalette.colorForCourse(
            occurrence.course,
            timetable,
            context.bnbuTheme,
          );
    final title =
        occurrence?.course.name ??
        (isLoading
            ? '正在同步课表…'
            : isLoggedIn
            ? '暂无后续课程'
            : '登录后查看下一门课');
    final room = occurrence == null
        ? (error == null ? '--' : '同步失败')
        : occurrence.meeting.room.isEmpty
        ? '教室待确认'
        : occurrence.meeting.room;
    final status = occurrence == null
        ? (isLoading ? '同步中' : '下一门课')
        : _courseStatusLabel(occurrence);
    final time = occurrence == null
        ? '--:--'
        : '${_timeFormatter.format(occurrence.campusStartsAt)} - ${_timeFormatter.format(occurrence.campusEndsAt)}';

    return _buildOverviewCard(
      context,
      cardKey: const ValueKey('home-next-course-card'),
      source: '下一节课',
      status: status,
      title: title,
      contextLabel: room,
      time: time,
      icon: occurrence?.phase == HomeCoursePhase.inProgress
          ? LucideIcons.circlePlay500
          : LucideIcons.bookOpen300,
      tone: tone,
      accentColor: courseAccent,
      onTap: occurrence == null || widget.onOpenCourse == null
          ? widget.onGoToSchedule
          : () => widget.onOpenCourse!(occurrence),
      semanticHint: occurrence == null ? '打开完整课表' : '在课表中定位并打开课程详情',
    );
  }

  Widget _buildDeadlineCard(
    BuildContext context, {
    required HomeDeadline? deadline,
    required bool isLoggedIn,
    required bool isLoading,
  }) {
    final tone = _deadlineTone(deadline?.phase);
    final item = deadline?.item;
    final title =
        item?.title ??
        (isLoading
            ? '正在同步 DDL…'
            : isLoggedIn
            ? '暂无待办 DDL'
            : '登录后查看下一个 DDL');
    final status = deadline == null
        ? (isLoading ? '同步中' : '下一个 DDL')
        : _deadlineStatusLabel(deadline);
    final time = deadline == null
        ? '--:--'
        : context.l10n.formatMonthDayTime(deadline.dueAt);

    final onTap = item == null ? null : () => _openDeadline(item);
    if (item == null) {
      return _buildOverviewCard(
        context,
        cardKey: const ValueKey('home-recent-task-card'),
        source: 'iSpace',
        status: status,
        title: title,
        contextLabel: '--',
        time: time,
        icon: LucideIcons.clipboardList300,
        tone: tone,
        onTap: null,
        semanticHint: '打开作业详情和提交入口',
      );
    }
    final accent = timelineSummaryAccentColor(
      item,
      context.bnbuTheme,
      now: _now,
    );
    return BnbuTimelineSummaryCard(
      key: const ValueKey('home-recent-task-card'),
      item: item,
      deadlineLabel: time,
      statusLabel: status,
      accentColor: accent,
      onTap: onTap,
      showIspaceLabel: true,
      semanticHint: '打开作业详情和提交入口',
    );
  }

  Widget _buildOverviewCard(
    BuildContext context, {
    required Key cardKey,
    required String source,
    required String status,
    required String title,
    required String contextLabel,
    required String time,
    required IconData icon,
    required _HomeTone tone,
    Color? accentColor,
    required VoidCallback? onTap,
    required String semanticHint,
  }) {
    final tokens = context.bnbuTheme;
    final toneColors = _homeToneColors(tokens, tone.kind);
    final foreground = accentColor ?? toneColors.foreground;
    final theme = Theme.of(context);
    final useStackedMeta = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      button: onTap != null,
      hint: semanticHint,
      child: BnbuSurfaceCard(
        key: cardKey,
        onTap: onTap,
        backgroundColor: tokens.surface,
        borderRadius: BorderRadius.zero,
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 116),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 5,
                child: ColoredBox(
                  key: cardKey == const ValueKey('home-next-course-card')
                      ? const ValueKey('home-course-accent')
                      : null,
                  color: foreground,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  tokens.space16 + 5,
                  tokens.space12,
                  tokens.space12,
                  tokens.space12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (useStackedMeta) ...[
                      Row(
                        children: [
                          Icon(icon, size: 17, color: foreground),
                          SizedBox(width: tokens.space8),
                          Expanded(
                            child: BnbuText(
                              source,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.space8),
                          BnbuText(
                            status,
                            key: ValueKey('home-primary-status-$status'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: tokens.space4),
                      BnbuText(
                        contextLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else
                      Row(
                        children: [
                          Icon(icon, size: 17, color: foreground),
                          SizedBox(width: tokens.space8),
                          BnbuText(
                            source,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: tokens.space4),
                          BnbuText(
                            '·',
                            style: TextStyle(color: tokens.textMuted),
                          ),
                          SizedBox(width: tokens.space4),
                          Expanded(
                            child: BnbuText(
                              contextLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.space8),
                          BnbuText(
                            status,
                            key: ValueKey('home-primary-status-$status'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: tokens.space12),
                    BnbuText(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.22,
                      ),
                    ),
                    SizedBox(height: tokens.space12),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.clock3300,
                          size: 16,
                          color: tokens.textMuted,
                        ),
                        SizedBox(width: tokens.space4),
                        Expanded(
                          child: BnbuText(
                            time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            LucideIcons.arrowRight300,
                            color: tokens.textMuted,
                            size: 19,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAccessPanel(
    BuildContext context, {
    required BnbuWindowClass windowClass,
  }) {
    final colors = CampusReferenceTheme.of(context);
    final compact = windowClass == BnbuWindowClass.compact;
    final actions = <_HomeQuickAction>[
      _HomeQuickAction(
        card: HomeServiceCard.campusDirectory,
        icon: LucideIcons.contactRound300,
        title: '政教信息',
        onTap: _openCampusDirectory,
      ),
      _HomeQuickAction(
        card: HomeServiceCard.portal,
        icon: LucideIcons.landmark300,
        title: '统一门户',
        onTap: () {
          unawaited(
            _openOfficialPage(
              AppConfig.bnbuPortalBaseUrl,
              title: '统一门户',
              presentation: OfficialWebPresentation.portalLayout,
            ),
          );
        },
      ),
      _HomeQuickAction(
        card: HomeServiceCard.ispace,
        icon: LucideIcons.graduationCap300,
        title: 'iSpace',
        onTap: widget.onGoToIspace,
      ),
      _HomeQuickAction(
        card: HomeServiceCard.campusLandmarks,
        icon: LucideIcons.building2300,
        title: CampusLandmarkStore.shared.catalog == null
            ? 'ME生活'
            : landmarkText(
                CampusLandmarkStore.shared.catalog!.title,
                context,
                CampusLandmarkStore.shared.catalog!.defaultLanguage,
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CampusLandmarksPage(
              owner: widget.controller.username ?? 'local',
              controller: widget.controller,
            ),
          ),
        ),
      ),
      _HomeQuickAction(
        card: HomeServiceCard.campusNavigation,
        icon: LucideIcons.mapPinned300,
        title: '校园导航',
        onTap: _openCampusNavigation,
      ),
      _HomeQuickAction(
        card: HomeServiceCard.officialMap,
        icon: LucideIcons.map300,
        title: '官方地图',
        onTap: () {
          unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const OfficialCampusMapPage(),
              ),
            ),
          );
        },
      ),
      _HomeQuickAction(
        card: HomeServiceCard.mis,
        icon: LucideIcons.table2300,
        title: 'MIS 教务',
        onTap: () {
          unawaited(
            _openOfficialPage(AppConfig.bnbuMisBaseUrl, title: 'MIS 教务系统'),
          );
        },
      ),
      _HomeQuickAction(
        card: HomeServiceCard.publicDirectory,
        icon: LucideIcons.contactRound300,
        title: '公开目录',
        onTap: () {
          unawaited(
            _openOfficialPage(
              'https://www.bnbu.edu.cn/en/about_us/contact_us.htm',
              title: '学校公开目录',
            ),
          );
        },
      ),
      _HomeQuickAction(
        card: HomeServiceCard.academicCalendar,
        icon: LucideIcons.calendarDays300,
        title: '校历',
        onTap: _openAcademicCalendar,
      ),
      _HomeQuickAction(
        card: HomeServiceCard.gradeReport,
        icon: LucideIcons.chartNoAxesCombined300,
        title: '绩点',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => GradeReportPage(controller: widget.controller),
          ),
        ),
      ),
      _HomeQuickAction(
        card: HomeServiceCard.leaveApplication,
        icon: LucideIcons.filePenLine300,
        title: '请假申请',
        onTap: () {
          unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LeaveApplicationPage(controller: widget.controller),
              ),
            ),
          );
        },
      ),
      _HomeQuickAction(
        card: HomeServiceCard.checkIn,
        icon: LucideIcons.clipboardCheck300,
        title: '打卡查看',
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CisCheckinPage(controller: widget.controller),
          ),
        ),
      ),
      if (StudentEcardPage.supportsPlatform(Theme.of(context).platform))
        _HomeQuickAction(
          card: HomeServiceCard.ecard,
          icon: LucideIcons.idCard300,
          title: 'eCard',
          onTap: _openStudentEcard,
        ),
      _HomeQuickAction(
        card: HomeServiceCard.duoduo,
        icon: LucideIcons.messagesSquare300,
        title: '朵朵校园墙',
        onTap: _openDuoduoCampusWall,
      ),
    ];
    if (!_homeCardVisibilityLoaded) return const SizedBox.shrink();
    final visibleActions = actions
        .where((action) => _homeCardVisibility.isVisible(action.card))
        .toList(growable: false);
    if (visibleActions.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      key: const ValueKey('home-quick-access-panel'),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: compact ? 17 : 23),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = compact ? 3 : 4;
            final gap = compact ? 2.0 : 10.0;
            final tileWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            final visualScale = (tileWidth / (compact ? 116.0 : 190.0)).clamp(
              .90,
              1.10,
            );
            return Wrap(
              spacing: gap,
              runSpacing: compact ? 8 : 12,
              children: [
                for (final action in visibleActions)
                  SizedBox(
                    width: tileWidth,
                    child: _buildQuickAction(
                      context,
                      action: action,
                      compact: compact,
                      visualScale: visualScale,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStudyModePanel(
    BuildContext context,
    List<AssistantConversation> conversations,
  ) {
    final mono = AppTheme.monochromeTokens(Theme.of(context).brightness);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final documents = recentStudyDocuments(conversations, limit: 3);
    final recentConversations = conversations.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final activity = recentConversations.take(2).toList(growable: false);
    return BnbuSurfaceCard(
      key: const ValueKey('home-study-mode-panel'),
      padding: EdgeInsets.zero,
      backgroundColor: mono.surface,
      borderColor: mono.border,
      child: SizedBox(
        height: 164 + (textScale - 1) * 100,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 184,
              padding: EdgeInsets.all(mono.space16),
              color: mono.textPrimary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.graduationCap300,
                    size: 20,
                    color: mono.surface,
                  ),
                  const Spacer(),
                  BnbuText(
                    '${documents.length}',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: mono.surface,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  BnbuText(
                    '学业模式',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: mono.surface),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StudyPanelSectionHeader(label: '最近文件', tokens: mono),
                  Divider(height: 1, color: mono.border),
                  Expanded(
                    child: documents.isEmpty
                        ? Center(
                            child: BnbuText(
                              '暂无学业记录',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: mono.textSecondary),
                            ),
                          )
                        : Row(
                            children: [
                              for (
                                var index = 0;
                                index < documents.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  VerticalDivider(width: 1, color: mono.border),
                                Expanded(
                                  child: _StudyDocumentHomeTile(
                                    conversation: documents[index],
                                    tokens: mono,
                                    onTap: () {
                                      final document =
                                          documents[index].studyDocument;
                                      if (document != null) {
                                        unawaited(
                                          StudyWindowManager.open(document),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: mono.border),
            SizedBox(
              width: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StudyPanelSectionHeader(label: '最近动态', tokens: mono),
                  Divider(height: 1, color: mono.border),
                  Expanded(
                    child: activity.isEmpty
                        ? Center(
                            child: BnbuText(
                              '暂无动态',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: mono.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activity.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              indent: mono.space12,
                              endIndent: mono.space12,
                              color: mono.border,
                            ),
                            itemBuilder: (context, index) {
                              final conversation = activity[index];
                              return _StudyActivityHomeTile(
                                title: studyConversationDisplayTitle(
                                  conversation,
                                ),
                                relativeTime: studyRelativeTime(
                                  conversation.updatedAt,
                                  now: _now,
                                ),
                                tokens: mono,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required _HomeQuickAction action,
    required bool compact,
    required double visualScale,
  }) {
    final colors = CampusReferenceTheme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final icon = Icon(
      action.icon,
      color: colors.muted,
      size: (compact ? 23 : 20) * visualScale,
    );
    final label = Text(
      context.l10n.text(action.title),
      key: ValueKey('home-service-title-${action.title}'),
      textAlign: compact ? TextAlign.center : TextAlign.start,
      style: colors.text((compact ? 11 : 13) * visualScale, height: 1.5),
    );
    return Semantics(
      button: true,
      label: context.l10n.text(action.title),
      child: Material(
        key: ValueKey('home-quick-action-${action.title}'),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(7),
          hoverColor: colors.hover,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 2 : 8 * visualScale,
              vertical: 14 * visualScale + (textScale - 1) * 7,
            ),
            child: compact
                ? Column(children: [icon, const SizedBox(height: 9), label])
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 11),
                      Expanded(child: label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _openCampusNavigation() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CampusNavigationPage(owner: widget.controller.username ?? 'local'),
      ),
    );
  }

  void _openAcademicCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AcademicCalendarPage()),
    );
  }

  void _openCampusDirectory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CampusDirectoryPage(controller: widget.controller),
      ),
    );
  }

  Future<void> _openOfficialPage(
    String url, {
    required String title,
    OfficialWebPresentation presentation = OfficialWebPresentation.original,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OfficialWebPage(
          controller: widget.controller,
          title: title,
          url: url,
          presentation: presentation,
        ),
      ),
    );
  }

  Future<void> _openDeadline(TimelineItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TimelineDetailPage(controller: widget.controller, item: item),
      ),
    );
  }

  String _todayLabel(DateTime date) {
    return context.l10n.formatMonthDayWithWeekday(date);
  }

  String _weekdayLabel(int weekday) {
    return const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
  }

  String _courseStatusLabel(HomeCourseOccurrence occurrence) {
    switch (occurrence.phase) {
      case HomeCoursePhase.inProgress:
        return '正在上课';
      case HomeCoursePhase.within30Minutes:
        final minutes = occurrence.startsAt
            .difference(_now)
            .inMinutes
            .clamp(1, 30);
        return '$minutes 分钟后';
      case HomeCoursePhase.laterToday:
        return '今天稍后';
      case HomeCoursePhase.future:
        final campusNow = toBnbuCampusClock(_now);
        final campusStartsAt = occurrence.campusStartsAt;
        final tomorrow = DateTime(
          campusNow.year,
          campusNow.month,
          campusNow.day,
        ).add(const Duration(days: 1));
        if (_isSameDate(campusStartsAt, tomorrow)) {
          return '明天';
        }
        return _weekdayLabel(campusStartsAt.weekday);
    }
  }

  String _deadlineStatusLabel(HomeDeadline deadline) {
    final difference = deadline.dueAt.difference(_now);
    switch (deadline.phase) {
      case HomeDeadlinePhase.overdue:
        return '已逾期 ${_compactDuration(_now.difference(deadline.dueAt))}';
      case HomeDeadlinePhase.within1Hour:
        return '仅剩 ${difference.inMinutes.clamp(1, 60)} 分钟';
      case HomeDeadlinePhase.within24Hours:
        return '仅剩 ${difference.inHours.clamp(1, 24)} 小时';
      case HomeDeadlinePhase.within3Days:
        return '剩余 ${difference.inDays.clamp(1, 3)} 天';
      case HomeDeadlinePhase.future:
        return '剩余 ${_compactDuration(difference)}';
    }
  }

  String _compactDuration(Duration duration) {
    if (duration.inDays >= 1) {
      return '${duration.inDays} 天';
    }
    if (duration.inHours >= 1) {
      return '${duration.inHours} 小时';
    }
    return '${duration.inMinutes.clamp(1, 59)} 分钟';
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  _HomeTone _courseTone(HomeCoursePhase? phase) {
    switch (phase) {
      case HomeCoursePhase.inProgress:
        return const _HomeTone(BnbuStatusKind.success);
      case HomeCoursePhase.within30Minutes:
        return const _HomeTone(BnbuStatusKind.warning);
      case HomeCoursePhase.laterToday:
        return const _HomeTone(BnbuStatusKind.info);
      case HomeCoursePhase.future:
      case null:
        return const _HomeTone(BnbuStatusKind.neutral);
    }
  }

  _HomeTone _deadlineTone(HomeDeadlinePhase? phase) {
    switch (phase) {
      case HomeDeadlinePhase.overdue:
      case HomeDeadlinePhase.within1Hour:
        return const _HomeTone(BnbuStatusKind.danger);
      case HomeDeadlinePhase.within24Hours:
      case HomeDeadlinePhase.within3Days:
        return const _HomeTone(BnbuStatusKind.warning);
      case HomeDeadlinePhase.future:
        return const _HomeTone(BnbuStatusKind.info);
      case null:
        return const _HomeTone(BnbuStatusKind.neutral);
    }
  }
}

class _StudyPanelSectionHeader extends StatelessWidget {
  const _StudyPanelSectionHeader({required this.label, required this.tokens});

  final String label;
  final BnbuThemeExtension tokens;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return SizedBox(
      height: 40 + (textScale - 1) * 16,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: BnbuText(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _StudyDocumentHomeTile extends StatelessWidget {
  const _StudyDocumentHomeTile({
    required this.conversation,
    required this.tokens,
    required this.onTap,
  });

  final AssistantConversation conversation;
  final BnbuThemeExtension tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final document = conversation.studyDocument;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: document == null ? null : onTap,
        child: Padding(
          padding: EdgeInsets.all(tokens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.fileText300,
                    size: 17,
                    color: tokens.textPrimary,
                  ),
                  const Spacer(),
                  Icon(
                    LucideIcons.arrowUpRight300,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ],
              ),
              const Spacer(),
              BnbuText(
                document?.title ?? conversation.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              SizedBox(height: tokens.space4),
              BnbuText(
                studyRelativeTime(conversation.updatedAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyActivityHomeTile extends StatelessWidget {
  const _StudyActivityHomeTile({
    required this.title,
    required this.relativeTime,
    required this.tokens,
  });

  final String title;
  final String relativeTime;
  final BnbuThemeExtension tokens;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return SizedBox(
      height: 56 + (textScale - 1) * 24,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space12),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tokens.textPrimary,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: tokens.space8),
            Expanded(
              child: BnbuText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: tokens.space8),
            BnbuText(
              relativeTime,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTone {
  const _HomeTone(this.kind);

  final BnbuStatusKind kind;
}

class _HomeQuickAction {
  const _HomeQuickAction({
    required this.card,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final HomeServiceCard card;
  final IconData icon;
  final String title;
  final VoidCallback onTap;
}

({Color foreground, Color background}) _homeToneColors(
  BnbuThemeExtension tokens,
  BnbuStatusKind kind,
) {
  return switch (kind) {
    BnbuStatusKind.success => (
      foreground: tokens.success,
      background: tokens.successContainer,
    ),
    BnbuStatusKind.warning => (
      foreground: tokens.warning,
      background: tokens.warningContainer,
    ),
    BnbuStatusKind.danger => (
      foreground: tokens.danger,
      background: tokens.dangerContainer,
    ),
    BnbuStatusKind.info => (
      foreground: tokens.info,
      background: tokens.infoContainer,
    ),
    BnbuStatusKind.neutral => (
      foreground: tokens.brandBlue,
      background: tokens.surface,
    ),
  };
}
