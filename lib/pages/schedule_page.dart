import '../state/account_habits.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/schedule_scroll_physics.dart';
import '../widgets/schedule_week_pager.dart';
import '../widgets/bnbu_loading.dart';
import '../models/academic_calendar.dart';
import '../models/campus_time.dart';
import '../models/exam_timetable.dart';
import '../models/ta_course_entry.dart';
import '../models/schedule_grid_geometry.dart';
import '../widgets/fixed_schedule_editor.dart';
import '../models/timetable_data.dart';
import '../models/timeline_item.dart';
import '../services/campus_directory_service.dart';
import '../services/teacher_review_service.dart';
import '../models/campus_directory.dart';
import '../state/app_session_controller.dart';
import '../state/app_theme_mode_controller.dart';
import '../state/root_shell_controller.dart';
import '../state/ta_course_controller.dart';
import '../theme/app_theme.dart';
import '../theme/course_color_palette.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_liquid_glass.dart';
import '../widgets/campus_primary_navigation.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/schedule_holiday_panel.dart';
import '../widgets/timeline_summary_card.dart';
import 'campus_directory_page.dart';
import 'ta_course_manager_page.dart';
import 'timeline_detail_page.dart';

enum _ScheduleWeekLayoutMode { grid, list }

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.controller,
    required this.taCourseController,
    this.now,
    this.directoryService,
    this.teacherReviewService,
    this.shellController,
  });

  final AppSessionController controller;
  final TaCourseController taCourseController;
  final DateTime? now;
  final CampusDirectoryService? directoryService;
  final TeacherReviewService? teacherReviewService;
  final RootShellController? shellController;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const String _legacyShowDeadlinesPreferenceKey =
      'schedule.show_deadlines';
  static const String _showDeadlinesPreferenceKeyPrefix =
      'schedule.show_deadlines.v2';
  static const String _weekLayoutPreferenceKeyPrefix =
      'schedule.week_layout.v1';
  static const double _regularTimeColumnWidth = 32;
  static const double _compactToolbarInset = 12;
  // Before d13f746 the date inherited labelLarge 14px; add exactly 10%.
  static const double _regularWeekFontSize = 15.4;
  static const double _minimumWeekFontSize = 13;
  double _pinnedHeaderExtent = 44;
  double _weekTitleHeight = 44;
  bool _compactToolbar = false;
  double _compactToolbarWidth = 0;
  double _compactToolbarOverflow = -1;
  String? _compactToolbarDate;
  double _compactWeekFontSize = _regularWeekFontSize;
  static const double _compactTimeColumnWidth = 25;
  static const double _regularRowHeight = 72;
  static const double _compactRowHeight = 64;
  static const double _regularHeaderBaseHeight = 28;
  static const double _compactHeaderBaseHeight = 26;
  static const double _regularDeadlineGap = 4;
  static const double _compactDeadlineGap = 3;
  static const double _regularDeadlineEventHeight = 22;
  static const double _compactDeadlineEventHeight = 18;
  static const List<_SlotSpec> _slots = <_SlotSpec>[
    _SlotSpec('8:00 - 8:50', 8 * 60, 9 * 60),
    _SlotSpec('9:00 - 9:50', 9 * 60, 10 * 60),
    _SlotSpec('10:00 - 10:50', 10 * 60, 11 * 60),
    _SlotSpec('11:00 - 11:50', 11 * 60, 12 * 60),
    _SlotSpec('12:00 - 12:50', 12 * 60, 13 * 60),
    _SlotSpec('13:00 - 13:50', 13 * 60, 14 * 60),
    _SlotSpec('14:00 - 14:50', 14 * 60, 15 * 60),
    _SlotSpec('15:00 - 15:50', 15 * 60, 16 * 60),
    _SlotSpec('16:00 - 16:50', 16 * 60, 17 * 60),
    _SlotSpec('17:00 - 17:50', 17 * 60, 18 * 60),
    _SlotSpec('18:00 - 18:50', 18 * 60, 19 * 60),
    _SlotSpec('19:00 - 19:50', 19 * 60, 20 * 60),
    _SlotSpec('20:00 - 20:50', 20 * 60, 21 * 60),
    _SlotSpec('21:00 - 21:50', 21 * 60, 22 * 60),
  ];

  final ScrollController _scrollController = ScrollController();
  final ScrollController _toolbarScrollController = ScrollController();
  final ScrollController _macAgendaScrollController = ScrollController();
  final GlobalKey _macAgendaBoardKey = GlobalKey();

  bool _usesSplit = false;
  bool get _isMac => Theme.of(context).platform == TargetPlatform.macOS;
  final ScrollController _weekGridHorizontalScrollController =
      ScrollController();
  final GlobalKey _weekBoardKey = GlobalKey();
  final GlobalKey _scrollViewportKey = GlobalKey();
  final GlobalKey _currentTimeLineKey = GlobalKey();
  final GlobalKey _currentAgendaDayKey = GlobalKey();
  final GlobalKey _requestedCourseCardKey = GlobalKey();
  late final Future<SharedPreferences> _preferencesFuture;
  late DateTime _visibleWeekStart;
  late DateTime _currentTime;
  Timer? _currentTimeTicker;
  bool _showDeadlines = true;
  _ScheduleWeekLayoutMode? _weekLayoutPreference;
  bool _shouldLocateCurrentTime = false;
  int _deadlineVisibilityVersion = 0;
  int _weekLayoutPreferenceVersion = 0;
  bool _shouldLocateAgendaDay = false;
  int _lastHandledScheduleCourseRequestId = 0;
  int _lastHandledScheduleViewRequestId = 0;
  bool _scheduleCourseRequestQueued = false;
  ScheduleCourseFocusRequest? _activeScheduleCourseRequest;
  _MeetingBlock? _requestedMeetingBlock;

  String get _normalizedPreferenceUsername =>
      widget.controller.username?.trim().toLowerCase() ?? '';

  String get _preferenceOwner {
    final username = _normalizedPreferenceUsername;
    if (username.isEmpty) {
      return 'signed-out';
    }
    return sha256.convert(utf8.encode(username)).toString();
  }

  String get _showDeadlinesPreferenceKey =>
      '$_showDeadlinesPreferenceKeyPrefix.$_preferenceOwner';

  String get _weekLayoutPreferenceKey =>
      '$_weekLayoutPreferenceKeyPrefix.$_preferenceOwner';

  String? get _legacyScopedShowDeadlinesPreferenceKey {
    final username = _normalizedPreferenceUsername;
    if (username.isEmpty) {
      return null;
    }
    return '$_showDeadlinesPreferenceKeyPrefix.${base64Url.encode(utf8.encode(username))}';
  }

  @override
  void initState() {
    super.initState();
    _preferencesFuture = SharedPreferences.getInstance();
    AccountHabits.shared.addListener(_habitChanged);
    _currentTime = toBnbuCampusClock(widget.now ?? DateTime.now());
    _visibleWeekStart = _startOfWeek(_currentTime);
    _startCurrentTimeTicker();
    _handleShellNavigationChanged();
    widget.taCourseController.addListener(_handleTaCoursesChanged);
    widget.shellController?.addListener(_handleShellNavigationChanged);
    unawaited(_restoreDeadlineVisibility());
    unawaited(_restoreWeekLayoutPreference());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = widget.controller;
      if (controller.timetable == null && !controller.isLoadingTimetable) {
        controller.ensureTimetableLoaded();
      }
      _handleShellNavigationChanged();
    });
  }

  @override
  void didUpdateWidget(covariant SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.taCourseController, widget.taCourseController)) {
      oldWidget.taCourseController.removeListener(_handleTaCoursesChanged);
      widget.taCourseController.addListener(_handleTaCoursesChanged);
    }
    if (!identical(oldWidget.shellController, widget.shellController)) {
      oldWidget.shellController?.removeListener(_handleShellNavigationChanged);
      widget.shellController?.addListener(_handleShellNavigationChanged);
      _handleShellNavigationChanged();
    }
  }

  @override
  void dispose() {
    AccountHabits.shared.removeListener(_habitChanged);
    widget.taCourseController.removeListener(_handleTaCoursesChanged);
    widget.shellController?.removeListener(_handleShellNavigationChanged);
    _currentTimeTicker?.cancel();
    _scrollController.dispose();
    _toolbarScrollController.dispose();
    _macAgendaScrollController.dispose();
    _weekGridHorizontalScrollController.dispose();
    super.dispose();
  }

  void _handleShellNavigationChanged() {
    final shellController = widget.shellController;
    final viewRequest = shellController?.scheduleViewRequest;
    if (shellController?.selectedTab == AppTab.schedule &&
        viewRequest != null &&
        viewRequest.id > _lastHandledScheduleViewRequestId) {
      _lastHandledScheduleViewRequestId = viewRequest.id;
      scheduleMicrotask(() {
        if (!mounted ||
            widget.shellController?.scheduleViewRequest?.id != viewRequest.id) {
          return;
        }
        setState(() {
          if (viewRequest.date != null) {
            _visibleWeekStart = _startOfWeek(viewRequest.date!);
          }
          if (viewRequest.view.isNotEmpty) {
            _weekLayoutPreferenceVersion++;
            _weekLayoutPreference = viewRequest.view == 'horizontal'
                ? _ScheduleWeekLayoutMode.grid
                : _ScheduleWeekLayoutMode.list;
            unawaited(_persistWeekLayoutPreference(_weekLayoutPreference!));
          }
          _shouldLocateAgendaDay = true;
        });
      });
    }
    final request = shellController?.scheduleCourseRequest;
    if (shellController == null ||
        shellController.selectedTab != AppTab.schedule ||
        request == null ||
        request.id <= _lastHandledScheduleCourseRequestId ||
        _scheduleCourseRequestQueued) {
      return;
    }
    _scheduleCourseRequestQueued = true;
    scheduleMicrotask(() {
      _scheduleCourseRequestQueued = false;
      if (!mounted) return;
      final latest = widget.shellController?.scheduleCourseRequest;
      if (latest == null ||
          latest.id <= _lastHandledScheduleCourseRequestId ||
          widget.shellController?.selectedTab != AppTab.schedule) {
        return;
      }
      _lastHandledScheduleCourseRequestId = latest.id;
      _prepareScheduleCourseRequest(latest);
    });
  }

  void _prepareScheduleCourseRequest(ScheduleCourseFocusRequest request) {
    final timetable = widget.controller.timetable;
    if (timetable == null) return;
    TimetableCourse? course;
    for (final candidate in timetable.courses) {
      final sameCode =
          request.course.code.isNotEmpty &&
          candidate.code == request.course.code;
      final sameName = candidate.name == request.course.name;
      if (sameCode || sameName) {
        course = candidate;
        break;
      }
    }
    if (course == null) return;
    TimetableMeeting? sourceMeeting;
    for (final candidate in course.meetings) {
      if (candidate.weekday == request.meeting.weekday &&
          candidate.startMinutes == request.meeting.startMinutes &&
          candidate.endMinutes == request.meeting.endMinutes) {
        sourceMeeting = candidate;
        break;
      }
    }
    if (sourceMeeting == null) return;
    final campusDate = toBnbuCampusClock(request.startsAt);
    final displayedMeeting = campusDate.weekday == sourceMeeting.weekday
        ? sourceMeeting
        : TimetableMeeting(
            weekday: campusDate.weekday,
            dayLabel:
                '${_weekdayShortLabelFromWeekday(campusDate.weekday)}（补${_weekdayShortLabelFromWeekday(sourceMeeting.weekday)}）',
            startLabel: sourceMeeting.startLabel,
            endLabel: sourceMeeting.endLabel,
            startMinutes: sourceMeeting.startMinutes,
            endMinutes: sourceMeeting.endMinutes,
            room: sourceMeeting.room,
          );
    final block = _MeetingBlock(
      color: CourseColorPalette.colorForCourse(
        course,
        timetable,
        context.bnbuTheme,
      ),
      course: course,
      meeting: displayedMeeting,
      taCourse: null,
    );
    setState(() {
      _visibleWeekStart = _startOfWeek(campusDate);
      _activeScheduleCourseRequest = request;
      _requestedMeetingBlock = block;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_focusAndOpenRequestedCourse(request.id));
    });
  }

  Future<void> _focusAndOpenRequestedCourse(int requestId) async {
    if (!mounted || _activeScheduleCourseRequest?.id != requestId) return;
    final targetContext = _requestedCourseCardKey.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.32,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted || _activeScheduleCourseRequest?.id != requestId) return;
    final block = _requestedMeetingBlock;
    if (block == null) return;
    await _showCourseDetail(block);
    if (mounted && _activeScheduleCourseRequest?.id == requestId) {
      setState(() {
        _activeScheduleCourseRequest = null;
        _requestedMeetingBlock = null;
      });
    }
  }

  bool _isRequestedMeeting(_MeetingBlock block) {
    final request = _activeScheduleCourseRequest;
    if (request == null) return false;
    final campusDate = toBnbuCampusClock(request.startsAt);
    final sameCourse = request.course.code.isNotEmpty
        ? block.course.code == request.course.code
        : block.course.name == request.course.name;
    return sameCourse &&
        block.meeting.weekday == campusDate.weekday &&
        block.meeting.startMinutes == request.meeting.startMinutes &&
        block.meeting.endMinutes == request.meeting.endMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return BnbuLoadingRegion(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final tokens = context.bnbuTheme;
          final timetable = widget.controller.timetable;
          final isLoading = widget.controller.isLoadingTimetable;
          final timetableError = widget.controller.timetableError;

          return Scaffold(
            backgroundColor: tokens.canvas,
            body: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _usesSplit =
                      _isMac ||
                      (Theme.of(context).platform == TargetPlatform.iOS &&
                          MediaQuery.orientationOf(context) ==
                              Orientation.landscape &&
                          constraints.maxWidth >=
                              BnbuBreakpoints.tabletWorkspace);
                  _configureToolbar(context, constraints.maxWidth);
                  if (_usesSplit && timetable != null) {
                    return _buildMacSplit(
                      context,
                      timetable,
                      timetableError,
                      isLoading,
                    );
                  }
                  // Scaffold supplies the measured floating navigation height
                  // as body padding. Keep the full viewport for time geometry;
                  // only add scroll clearance after it, never another hour row.
                  final bottomPadding = MediaQuery.paddingOf(context).bottom;
                  final bottomObstruction =
                      !BnbuBreakpoints.fromWidth(
                            constraints.maxWidth,
                          ).usesSideNavigation &&
                          CampusPrimaryNavigation.usesLiquidGlass(context) &&
                          bottomPadding >
                              MediaQuery.viewPaddingOf(context).bottom
                      ? bottomPadding
                      : 0.0;
                  return Stack(
                    children: [
                      RefreshIndicator.noSpinner(
                        onRefresh: _refreshAll,
                        child: CustomScrollView(
                          key: _scrollViewportKey,
                          controller: _scrollController,
                          physics: const ScheduleScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          slivers: [
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _ScheduleHeaderDelegate(
                                height: _pinnedHeaderExtent,
                                child: _buildScheduleHeader(
                                  context,
                                  timetable: timetable,
                                ),
                              ),
                            ),
                            if (timetableError != null && timetable != null)
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  tokens.space12,
                                  tokens.space12,
                                  tokens.space12,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: _buildErrorCard(
                                    context,
                                    timetableError,
                                  ),
                                ),
                              ),
                            if (timetable == null)
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  tokens.space12,
                                  tokens.space16,
                                  tokens.space12,
                                  tokens.space24,
                                ),
                                sliver: SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _buildEmptyState(
                                    context,
                                    isLoading: isLoading,
                                    errorMessage: timetableError,
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: KeyedSubtree(
                                    key: _weekBoardKey,
                                    child: _buildWeekBoard(
                                      context,
                                      timetable,
                                      viewportHeight: constraints.maxHeight,
                                    ),
                                  ),
                                ),
                              ),
                            if (timetable != null && bottomObstruction > 0)
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  key: const ValueKey(
                                    'schedule-bottom-scroll-clearance',
                                  ),
                                  height: bottomObstruction + tokens.space12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: _pinnedHeaderExtent - 2,
                        left: 0,
                        right: 0,
                        child: BnbuUpdateProgress(
                          key: const ValueKey('schedule-loading-progress'),
                          active: isLoading,
                          color: tokens.brandBlue,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMacSplit(
    BuildContext context,
    TimetableData timetable,
    String? error,
    bool loading,
  ) {
    return Column(
      children: [
        SizedBox(
          height: _pinnedHeaderExtent,
          child: _buildScheduleHeader(context, timetable: timetable),
        ),
        BnbuUpdateProgress(active: loading, color: context.bnbuTheme.brandBlue),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildErrorCard(context, error),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final agendaWidth = (constraints.maxWidth * 0.30).clamp(
                240.0,
                400.0,
              );
              return Row(
                key: const ValueKey('schedule-mac-split'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: RefreshIndicator.noSpinner(
                      onRefresh: _refreshAll,
                      child: Scrollbar(
                        controller: _scrollController,
                        child: SingleChildScrollView(
                          key: _scrollViewportKey,
                          controller: _scrollController,
                          physics: const ScheduleScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: KeyedSubtree(
                            key: _weekBoardKey,
                            child: _buildWeekBoard(
                              context,
                              timetable,
                              viewportHeight:
                                  constraints.maxHeight + _pinnedHeaderExtent,
                              layoutMode: _ScheduleWeekLayoutMode.grid,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: context.bnbuTheme.border,
                  ),
                  SizedBox(
                    width: agendaWidth,
                    child: RefreshIndicator.noSpinner(
                      onRefresh: _refreshAll,
                      child: Scrollbar(
                        controller: _macAgendaScrollController,
                        child: SingleChildScrollView(
                          key: const ValueKey('schedule-mac-agenda-scroll'),
                          controller: _macAgendaScrollController,
                          physics: const ScheduleScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: KeyedSubtree(
                            key: _macAgendaBoardKey,
                            child: _buildWeekBoard(
                              context,
                              timetable,
                              viewportHeight: constraints.maxHeight,
                              layoutMode: _ScheduleWeekLayoutMode.list,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  TextStyle _weekTitleStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
        color: Theme.of(context).brightness == Brightness.dark
            ? context.bnbuTheme.brandBlue
            : context.bnbuTheme.info,
        fontWeight: FontWeight.w600,
        fontSize: _compactToolbar ? _compactWeekFontSize : _regularWeekFontSize,
        height: _compactToolbar ? 1.2 : null,
        letterSpacing: _compactToolbar ? -0.3 : null,
      );

  void _configureToolbar(BuildContext context, double width) {
    _compactToolbar = !_usesSplit && width < 700;
    _compactWeekFontSize = _regularWeekFontSize;
    if (!_compactToolbar) {
      _compactToolbarOverflow = -1;
      _weekTitleHeight = _pinnedHeaderExtent = 44;
      return;
    }
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(_weekTitleStyle(context));
    final contentWidth = width - 2 * _compactToolbarInset;
    final painter = TextPainter(
      text: TextSpan(text: _compactWeekRangeLabel, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Reserve full-size touch targets first. Only the date
    // numerals may shrink slightly; keep system text scaling and scroll as a
    // fallback when even the minimum readable size cannot fit.
    final availableTextWidth = contentWidth - 6 * 44 - 2;
    while (painter.width.ceilToDouble() > availableTextWidth &&
        _compactWeekFontSize > _minimumWeekFontSize) {
      _compactWeekFontSize = math.max(
        _minimumWeekFontSize,
        _compactWeekFontSize - 0.25,
      );
      painter.text = TextSpan(
        text: _compactWeekRangeLabel,
        style: style.copyWith(fontSize: _compactWeekFontSize),
      );
      painter.layout();
    }
    final minimumWidth =
        6 * 44.0 + math.max(44.0, painter.width.ceilToDouble() + 2);
    _compactToolbarWidth = math.max(contentWidth, minimumWidth);
    final overflow = _compactToolbarWidth - contentWidth;
    if (_compactToolbarOverflow != overflow ||
        _compactToolbarDate != _compactWeekRangeLabel) {
      _compactToolbarOverflow = overflow;
      _compactToolbarDate = _compactWeekRangeLabel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_toolbarScrollController.hasClients) return;
        final position = _toolbarScrollController.position;
        // Start even the large-text scrolling fallback on the date, not at
        // the left edge of the wider content. Subsequent user scrolling stays free.
        _toolbarScrollController.jumpTo(
          (_compactToolbarOverflow / 2).clamp(0.0, position.maxScrollExtent),
        );
      });
    }
    _weekTitleHeight = math.max(44, painter.height.ceilToDouble() + 12);
    _pinnedHeaderExtent = _weekTitleHeight;
    painter.dispose();
  }

  Widget _buildScheduleHeader(
    BuildContext context, {
    required TimetableData? timetable,
  }) {
    final tokens = context.bnbuTheme;
    final viewToggle = _usesSplit && !_isMac
        ? const SizedBox.shrink()
        : _isMac
        ? IconButton(
            key: const ValueKey('schedule-refresh'),
            tooltip: context.l10n.text('刷新'),
            onPressed: widget.controller.isLoadingTimetable
                ? null
                : _refreshAll,
            icon: const Icon(LucideIcons.refreshCw300),
          )
        : _buildWeekLayoutToggle(context);
    final previousWeekAction = IconButton(
      key: const ValueKey('schedule-previous-week'),
      onPressed: () => _shiftWeek(-1),
      tooltip: context.l10n.text('上一周'),
      icon: const Icon(LucideIcons.chevronLeft300),
    );
    final nextWeekAction = IconButton(
      key: const ValueKey('schedule-next-week'),
      onPressed: () => _shiftWeek(1),
      tooltip: context.l10n.text('下一周'),
      icon: const Icon(LucideIcons.chevronRight300),
    );
    final weekAuxiliaryControls = <Widget>[
      _buildDeadlineActionButton(context),
      _buildLocateCurrentButton(timetable: timetable),
    ];
    final taAction = IconButton(
      key: const ValueKey('schedule-ta-action'),
      onPressed: _openTaCourseManager,
      tooltip: context.l10n.text('固定日程'),
      icon: _buildTaCourseIcon(),
    );
    final toolbar = DecoratedBox(
      key: const ValueKey('schedule-toolbar'),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;
          if (isWide) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: viewToggle),
                    Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        key: const ValueKey('schedule-wide-primary-controls'),
                        width: 300,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            previousWeekAction,
                            Expanded(child: _buildWeekTitle(context)),
                            nextWeekAction,
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [...weekAuxiliaryControls, taAction],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          Widget compactControl(Widget child) =>
              SizedBox(width: 44, height: _weekTitleHeight, child: child);
          final weekTitle = Expanded(
            child: SizedBox(
              key: const ValueKey('schedule-phone-week-title-region'),
              height: _weekTitleHeight,
              child: _buildWeekTitle(context),
            ),
          );
          const inset = EdgeInsets.symmetric(horizontal: _compactToolbarInset);
          if (_compactToolbar) {
            return Padding(
              padding: inset,
              child: SingleChildScrollView(
                key: const ValueKey('schedule-phone-toolbar-scroll'),
                controller: _toolbarScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _compactToolbarWidth,
                  height: _weekTitleHeight,
                  child: Row(
                    key: const ValueKey('schedule-phone-single-row-toolbar'),
                    children: [
                      compactControl(viewToggle),
                      compactControl(
                        _buildLocateCurrentButton(timetable: timetable),
                      ),
                      compactControl(previousWeekAction),
                      weekTitle,
                      compactControl(nextWeekAction),
                      compactControl(_buildDeadlineActionButton(context)),
                      compactControl(taAction),
                    ],
                  ),
                ),
              ),
            );
          }
          return Padding(
            padding: inset,
            child: SizedBox(
              height: _weekTitleHeight,
              child: Row(
                children: [
                  compactControl(viewToggle),
                  compactControl(
                    _buildLocateCurrentButton(timetable: timetable),
                  ),
                  compactControl(previousWeekAction),
                  weekTitle,
                  compactControl(nextWeekAction),
                  compactControl(_buildDeadlineActionButton(context)),
                  compactControl(taAction),
                ],
              ),
            ),
          );
        },
      ),
    );
    final styledToolbar = _compactToolbar
        ? IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                // d13f746^ inherited the app's 20px IconTheme for arrows.
                iconSize: 20,
                padding: const EdgeInsets.all(5),
                minimumSize: const Size.square(44),
              ),
            ),
            child: toolbar,
          )
        : toolbar;
    return styledToolbar;
  }

  _ScheduleWeekLayoutMode _effectiveWeekLayoutMode(BuildContext context) {
    final preference = _weekLayoutPreference;
    if (preference != null) return preference;
    return _ScheduleWeekLayoutMode.grid;
  }

  Widget _buildWeekLayoutToggle(BuildContext context) {
    final mode = _effectiveWeekLayoutMode(context);
    final isGrid = mode == _ScheduleWeekLayoutMode.grid;
    final label = isGrid ? '横表' : '竖表';
    return Semantics(
      button: true,
      label: context.l10n.text('切换课表视图'),
      value: context.l10n.text(label),
      child: IconButton(
        key: const ValueKey('schedule-view-toggle'),
        onPressed: () => _setWeekLayoutPreference(
          isGrid ? _ScheduleWeekLayoutMode.list : _ScheduleWeekLayoutMode.grid,
        ),
        tooltip: context.l10n.text('当前$label，切换为${isGrid ? '竖表' : '横表'}'),
        icon: _toolbarGlyph(
          isGrid ? LucideIcons.table2300 : LucideIcons.rows3300,
          isGrid ? 'HOR' : 'VER',
          'view',
          context.bnbuTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildLocateCurrentButton({required TimetableData? timetable}) {
    final tokens = context.bnbuTheme;
    return IconButton(
      key: const ValueKey('schedule-locate-action'),
      onPressed: timetable == null ? _goToCurrentWeek : _locateCurrentTime,
      tooltip: context.l10n.text('回到当前'),
      icon: _toolbarGlyph(
        LucideIcons.locateFixed300,
        'NOW',
        'locate',
        tokens.textPrimary,
      ),
    );
  }

  Widget _buildWeekTitle(BuildContext context) {
    final titleStyle = _weekTitleStyle(context);
    final label = BnbuText(
      _compactToolbar
          ? _compactWeekRangeLabel
          : _weekRangeLabel(_visibleWeekStart),
      key: const ValueKey('schedule-week-range-label'),
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      style: titleStyle,
    );
    return Align(
      alignment: Alignment.center,
      child: Semantics(
        button: true,
        label:
            '${context.l10n.text('选择所在周')}，${_weekRangeLabel(_visibleWeekStart)}',
        hint: context.l10n.text('打开日期选择器切换课表周次'),
        child: Tooltip(
          message:
              '${context.l10n.text('选择所在周')}，${_weekRangeLabel(_visibleWeekStart)}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('schedule-week-picker'),
              onTap: _pickWeek,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: _compactToolbar
                          ? label
                          : FittedBox(
                              key: const ValueKey('schedule-week-range-fit'),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: label,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startCurrentTimeTicker() {
    _currentTimeTicker?.cancel();
    if (widget.now != null) {
      return;
    }
    _currentTimeTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentTime = toBnbuCampusClock(DateTime.now());
      });
    });
  }

  Future<void> _refreshAll() {
    return Future.wait<void>([
      widget.controller.refreshTimeline(),
      widget.controller.refreshTimetable(),
    ]);
  }

  Future<void> _pickWeek() async {
    final pickedDate = await showFixedScheduleWeekPicker(
      context,
      initialWeek: _visibleWeekStart,
    );
    if (!mounted || pickedDate == null) {
      return;
    }
    _setVisibleWeek(_startOfWeek(pickedDate));
  }

  void _shiftWeek(int deltaWeeks) {
    if (deltaWeeks == 0) {
      return;
    }
    final calendarWeekStart = DateTime(
      _visibleWeekStart.year,
      _visibleWeekStart.month,
      _visibleWeekStart.day + 7 * deltaWeeks,
    );
    _setVisibleWeek(calendarWeekStart);
  }

  void _goToCurrentWeek() {
    _setVisibleWeek(_startOfWeek(toBnbuCampusClock(DateTime.now())));
  }

  void _locateCurrentTime() {
    setState(() {
      if (_usesSplit ||
          _effectiveWeekLayoutMode(context) == _ScheduleWeekLayoutMode.list) {
        _shouldLocateAgendaDay = true;
        if (_usesSplit) _shouldLocateCurrentTime = true;
      } else {
        _shouldLocateCurrentTime = true;
      }
    });
    _goToCurrentWeek();
  }

  void _setVisibleWeek(DateTime nextWeekStart) {
    final normalized = _startOfWeek(nextWeekStart);
    if (_isSameDate(normalized, _visibleWeekStart)) {
      return;
    }
    setState(() {
      _visibleWeekStart = normalized;
      _shouldLocateAgendaDay =
          _usesSplit ||
          _effectiveWeekLayoutMode(context) == _ScheduleWeekLayoutMode.list;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_weekGridHorizontalScrollController.hasClients) return;
      final position = _weekGridHorizontalScrollController.position;
      if (position.pixels != position.minScrollExtent) {
        position.jumpTo(position.minScrollExtent);
      }
    });
  }

  void _toggleDeadlineVisibility() {
    final nextValue = !_showDeadlines;
    _deadlineVisibilityVersion += 1;
    setState(() {
      _showDeadlines = nextValue;
    });
    unawaited(_persistDeadlineVisibility(nextValue));
  }

  void _setWeekLayoutPreference(_ScheduleWeekLayoutMode mode) {
    _weekLayoutPreferenceVersion += 1;
    setState(() {
      _weekLayoutPreference = mode;
      _shouldLocateAgendaDay = mode == _ScheduleWeekLayoutMode.list;
    });
    unawaited(_persistWeekLayoutPreference(mode));
  }

  Future<void> _openTaCourseManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            TaCourseManagerPage(controller: widget.taCourseController),
      ),
    );
  }

  void _habitChanged() {
    if (!mounted) return;
    unawaited(_restoreDeadlineVisibility());
    unawaited(_restoreWeekLayoutPreference());
  }

  Future<void> _restoreDeadlineVisibility() async {
    final restoreVersion = _deadlineVisibilityVersion;
    try {
      final preferences = await _preferencesFuture;
      var persistedValue = preferences.getBool(_showDeadlinesPreferenceKey);
      final legacyScopedKey = _legacyScopedShowDeadlinesPreferenceKey;
      if (persistedValue == null && legacyScopedKey != null) {
        persistedValue = preferences.getBool(legacyScopedKey);
        if (persistedValue != null) {
          await preferences.setBool(
            _showDeadlinesPreferenceKey,
            persistedValue,
          );
          await preferences.remove(legacyScopedKey);
        }
      }
      await preferences.remove(_legacyShowDeadlinesPreferenceKey);
      if (AccountHabits.shared.managed) {
        persistedValue = AccountHabits.shared.read(
          'schedule.show_deadlines',
          true,
        );
      }
      if (!mounted ||
          _deadlineVisibilityVersion != restoreVersion ||
          persistedValue == null ||
          persistedValue == _showDeadlines) {
        return;
      }
      setState(() {
        _showDeadlines = persistedValue!;
      });
    } catch (_) {}
  }

  Future<void> _persistDeadlineVisibility(bool value) async {
    try {
      if (AccountHabits.shared.managed) {
        await AccountHabits.shared.set('schedule.show_deadlines', value);
        return;
      }
      final preferences = await _preferencesFuture;
      await preferences.setBool(_showDeadlinesPreferenceKey, value);
    } catch (_) {}
  }

  Future<void> _restoreWeekLayoutPreference() async {
    final restoreVersion = _weekLayoutPreferenceVersion;
    try {
      final preferences = await _preferencesFuture;
      final persistedValue = AccountHabits.shared.managed
          ? AccountHabits.shared.read('schedule.week_layout', 'grid')
          : preferences.getString(_weekLayoutPreferenceKey);
      final mode = switch (persistedValue) {
        'grid' => _ScheduleWeekLayoutMode.grid,
        'list' => _ScheduleWeekLayoutMode.list,
        _ => null,
      };
      if (!mounted ||
          _weekLayoutPreferenceVersion != restoreVersion ||
          mode == null ||
          mode == _weekLayoutPreference) {
        return;
      }
      setState(() {
        _weekLayoutPreference = mode;
        _shouldLocateAgendaDay = mode == _ScheduleWeekLayoutMode.list;
      });
    } catch (_) {}
  }

  Future<void> _persistWeekLayoutPreference(
    _ScheduleWeekLayoutMode mode,
  ) async {
    try {
      if (AccountHabits.shared.managed) {
        await AccountHabits.shared.set('schedule.week_layout', mode.name);
        return;
      }
      final preferences = await _preferencesFuture;
      await preferences.setString(
        _weekLayoutPreferenceKey,
        mode == _ScheduleWeekLayoutMode.grid ? 'grid' : 'list',
      );
    } catch (_) {}
  }

  void _handleTaCoursesChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    final route = ModalRoute.of(context);
    final errorMessage = widget.taCourseController.errorMessage;
    if (errorMessage != null && (route?.isCurrent ?? true)) {
      _showSnackBar(errorMessage);
      widget.taCourseController.clearErrors();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: BnbuText(message)));
  }

  Widget _buildDeadlineActionButton(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Semantics(
      button: true,
      label: context.l10n.text('DDL显示开关'),
      value: context.l10n.text(_showDeadlines ? '开' : '关'),
      child: IconButton(
        key: const ValueKey('schedule-deadline-toggle'),
        onPressed: _toggleDeadlineVisibility,
        tooltip: context.l10n.text(_showDeadlines ? '隐藏 DDL' : '显示 DDL'),
        style: IconButton.styleFrom(
          minimumSize: Size.square(tokens.minInteractiveDimension),
          foregroundColor: _showDeadlines ? tokens.danger : tokens.textMuted,
        ),
        icon: _toolbarGlyph(
          LucideIcons.triangleAlert300,
          'DDL',
          'deadline',
          _showDeadlines ? tokens.danger : tokens.textMuted,
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    return BnbuNotice(
      message: message,
      kind: BnbuStatusKind.danger,
      icon: LucideIcons.circleAlert300,
      action: TextButton(
        onPressed: widget.controller.isLoadingTimetable
            ? null
            : widget.controller.refreshTimetable,
        child: const BnbuText('重试'),
      ),
    );
  }

  Widget _toolbarGlyph(
    IconData icon,
    String label,
    String name,
    Color color, {
    double labelScale = 1,
    double labelRightInset = 0,
  }) {
    return SizedBox.square(
      key: ValueKey('schedule-$name-icon'),
      dimension: 26,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(
              icon,
              key: ValueKey('schedule-$name-base-icon'),
              size: 18,
              color: color,
            ),
          ),
          Positioned(
            right: labelRightInset,
            bottom: 0,
            child: ExcludeSemantics(
              child: Text(
                label,
                key: ValueKey('schedule-$name-label'),
                // This is part of the fixed-size icon; its parent exposes the
                // full accessible action name. The date retains text scaling.
                textScaler: _compactToolbar ? TextScaler.noScaling : null,
                style: TextStyle(
                  color: color,
                  fontSize: 7 * labelScale,
                  height: 1,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaCourseIcon() => _toolbarGlyph(
    LucideIcons.calendarDays300,
    'TA',
    'ta',
    context.bnbuTheme.textPrimary,
    labelScale: 1.12,
    labelRightInset: 2,
  );

  Widget _buildEmptyState(
    BuildContext context, {
    required bool isLoading,
    String? errorMessage,
  }) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(top: tokens.space32),
      child: isLoading
          ? const BnbuLoadingState(title: '正在同步课表…')
          : errorMessage != null
          ? BnbuErrorState(
              title: '课表加载失败',
              message: errorMessage,
              action: FilledButton.icon(
                key: const ValueKey('schedule-retry-button'),
                onPressed: widget.controller.refreshTimetable,
                icon: const Icon(LucideIcons.refreshCw300, size: 18),
                label: const BnbuText('重试'),
              ),
            )
          : BnbuEmptyState(
              title: '还没有加载到课表',
              message: '下拉刷新后，会自动从 MIS 拉取当前学期课表。',
            ),
    );
  }

  List<ExamTimetableEntry> _examsForWeek(
    TimetableData timetable,
    DateTime weekStart,
  ) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = DateTime(start.year, start.month, start.day + 7);
    return timetable.exams
        .where((exam) => !exam.date.isBefore(start) && exam.date.isBefore(end))
        .toList(growable: false);
  }

  Widget _buildExamSection(
    BuildContext context,
    List<ExamTimetableEntry> exams, {
    required bool showDate,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('schedule-exam-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.clipboardCheck300, size: 18, color: tokens.danger),
            SizedBox(width: tokens.space8),
            BnbuText(
              '考试安排',
              style: theme.textTheme.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.space8),
        for (var index = 0; index < exams.length; index++) ...[
          _buildExamCard(context, exams[index], showDate: showDate),
          if (index != exams.length - 1) SizedBox(height: tokens.space8),
        ],
      ],
    );
  }

  Widget _buildExamCard(
    BuildContext context,
    ExamTimetableEntry exam, {
    required bool showDate,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final location = <String>[
      if (exam.room.isNotEmpty) exam.room,
      if (exam.seat.isNotEmpty) '座位 ${exam.seat}',
    ].join(' · ');
    final dateLabel = showDate
        ? '${context.l10n.formatMonthDay(exam.date)} '
              '${context.l10n.formatWeekday(exam.date)} · '
        : '';
    return BnbuSurfaceCard(
      key: ValueKey('schedule-exam-${exam.widgetKey}'),
      backgroundColor: tokens.surface,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.fromLTRB(
        tokens.space16,
        tokens.space12,
        tokens.space16,
        tokens.space12,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: tokens.danger),
            SizedBox(width: tokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BnbuText(
                    '$dateLabel${exam.timeLabel}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: tokens.danger,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: tokens.space4),
                  BnbuText(
                    exam.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (exam.courseCode.isNotEmpty &&
                      exam.courseCode != exam.displayName) ...[
                    SizedBox(height: tokens.space4),
                    BnbuText(
                      exam.courseCode,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                  if (location.isNotEmpty) ...[
                    SizedBox(height: tokens.space4),
                    BnbuText(
                      location,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                  if (exam.remark.isNotEmpty) ...[
                    SizedBox(height: tokens.space4),
                    BnbuText(
                      exam.remark,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseSummaryCard(
    BuildContext context,
    _MeetingBlock block, {
    required String keyPrefix,
    VoidCallback? onTap,
    bool showChevron = false,
    ValueChanged<List<String>>? onTeacherTap,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final accent = block.color;
    final location = block.meeting.room.isEmpty ? '--' : block.meeting.room;
    return Semantics(
      button: onTap != null,
      label: context.l10n.text('课程：${block.course.name}'),
      value: '${block.meeting.startLabel}-${block.meeting.endLabel}，$location',
      child: BnbuSurfaceCard(
        key: ValueKey(
          '$keyPrefix-course-${block.course.code}-'
          '${block.meeting.startMinutes}',
        ),
        onTap: onTap,
        backgroundColor: tokens.surface,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: ValueKey(
                  '$keyPrefix-accent-${block.course.code}-'
                  '${block.meeting.startMinutes}',
                ),
                width: 5,
                color: accent,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    tokens.space16,
                    tokens.space12,
                    tokens.space12,
                    tokens.space12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(LucideIcons.clock3300, size: 17, color: accent),
                          SizedBox(width: tokens.space8),
                          Expanded(
                            child: BnbuText(
                              '${block.meeting.startLabel} - '
                              '${block.meeting.endLabel}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          if (showChevron) ...[
                            Icon(
                              LucideIcons.arrowRight300,
                              color: tokens.textMuted,
                              size: 19,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: tokens.space12),
                      BnbuText(
                        block.course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.22,
                        ),
                      ),
                      SizedBox(height: tokens.space8),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.mapPin300,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                          SizedBox(width: tokens.space4),
                          Expanded(
                            child: BnbuText(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                          if (block.course.teacher.isNotEmpty &&
                              block.taCourse == null) ...[
                            SizedBox(width: tokens.space12),
                            Flexible(
                              child: _buildTeacherLink(
                                context,
                                block.course.teacher,
                                onTap: onTeacherTap,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherLink(
    BuildContext context,
    String rawNames, {
    ValueChanged<List<String>>? onTap,
  }) {
    final tokens = context.bnbuTheme;
    final names = _teacherNames(rawNames);
    if (names.isEmpty) return const SizedBox.shrink();
    final label = names.join(' · ');
    return Semantics(
      key: ValueKey('schedule-teacher-link-$rawNames'),
      button: true,
      link: true,
      label: context.l10n.text('打开教师档案：$label'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radius12),
          onTap: () {
            if (onTap != null) {
              onTap(names);
              return;
            }
            if (names.length == 1) {
              unawaited(_openTeacherProfile(names.single));
            } else {
              unawaited(_chooseTeacher(names));
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: BnbuText(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.brandBlue,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: tokens.brandBlue,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.space4),
                  Icon(
                    LucideIcons.contactRound300,
                    size: 16,
                    color: tokens.brandBlue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekBoard(
    BuildContext context,
    TimetableData timetable, {
    required double viewportHeight,
    _ScheduleWeekLayoutMode? layoutMode,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final swipeEnabled =
            !_isMac &&
            (constraints.maxWidth < 700 ||
                Theme.of(context).platform == TargetPlatform.iOS);
        final mode = layoutMode ?? _effectiveWeekLayoutMode(context);
        return ScheduleWeekPager(
          key: ValueKey(
            'week-pager-$_preferenceOwner-${mode.name}-$_usesSplit-${constraints.maxWidth}',
          ),
          week: _visibleWeekStart,
          swipeEnabled: swipeEnabled,
          horizontalController: mode == _ScheduleWeekLayoutMode.grid
              ? _weekGridHorizontalScrollController
              : null,
          onChanged: _setVisibleWeek,
          builder: (week, active) => _buildWeekBoardContents(
            context,
            timetable,
            viewportHeight: viewportHeight,
            layoutMode: layoutMode,
            weekStart: week,
            active: active,
            swipeEnabled: swipeEnabled,
          ),
        );
      },
    );
  }

  Widget _buildWeekBoardContents(
    BuildContext context,
    TimetableData timetable, {
    required double viewportHeight,
    required DateTime weekStart,
    required bool active,
    required bool swipeEnabled,
    _ScheduleWeekLayoutMode? layoutMode,
  }) {
    final tokens = context.bnbuTheme;
    final weekDates = _weekDatesForStart(weekStart);
    final weekDeadlines = _deadlinesForWeek(weekStart);
    final courseColors = CourseColorPalette.build(
      timetable,
      widget.taCourseController.entries,
      tokens,
    );
    final meetingBlocks = _buildMeetingBlocks(
      timetable,
      courseColors,
      tokens,
      visibleWeekStart: weekStart,
    );
    final visibleSlots = _buildVisibleSlots(
      _showDeadlines ? weekDeadlines : const [],
      meetings: meetingBlocks.map((block) => block.meeting),
    );
    final holidayNoticesByWeekday = <int, String>{};
    for (final day in weekDates) {
      final classDay = BnbuAcademicCalendar.classDayFor(timetable, day);
      if (!classDay.hasClasses && classDay.notice != null) {
        holidayNoticesByWeekday[day.weekday] = classDay.notice!;
      }
    }
    final weekExams = _examsForWeek(timetable, weekStart);
    final examsByWeekday = <int, List<ExamTimetableEntry>>{
      for (final day in weekDates)
        day.weekday: weekExams
            .where((exam) => _isSameDate(exam.date, day))
            .toList(growable: false),
    };
    final deadlinesByWeekday = <int, List<TimelineItem>>{
      for (final day in weekDates)
        day.weekday: _deadlinesOnDate(weekDeadlines, day),
    };
    final meetingsByWeekday = <int, List<_MeetingBlock>>{
      for (var weekday = 1; weekday <= 7; weekday++) weekday: <_MeetingBlock>[],
    };
    for (final block in meetingBlocks) {
      meetingsByWeekday[block.meeting.weekday]!.add(block);
    }
    return LayoutBuilder(
      key: ValueKey(
        layoutMode == _ScheduleWeekLayoutMode.list
            ? 'schedule-mac-agenda-board'
            : 'schedule-week-board',
      ),
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final isMobile = constraints.maxWidth < 700;
        final useAgendaFallback =
            (layoutMode ?? _effectiveWeekLayoutMode(context)) ==
            _ScheduleWeekLayoutMode.list;
        final visibleDays =
            useAgendaFallback || _usesSplit || constraints.maxWidth >= 760
            ? weekDates
            : _resolveVisibleDays(
                weekDates,
                meetingsByWeekday: meetingsByWeekday,
                deadlinesByWeekday: deadlinesByWeekday,
                holidayNoticesByWeekday: holidayNoticesByWeekday,
              );
        final columns = buildScheduleDayColumns(
          visibleDays,
          holidayNoticesByWeekday,
        );
        final columnWeight = columns.fold<double>(
          0,
          (sum, column) => sum + column.weight,
        );
        final dayIndexByWeekday = <int, int>{
          for (var index = 0; index < visibleDays.length; index++)
            visibleDays[index].weekday: index,
        };
        if (active && weekStart == _visibleWeekStart) {
          if (useAgendaFallback) {
            _scheduleLocateAgendaDayIfNeeded();
          } else {
            _scheduleLocateCurrentTimeIfNeeded();
          }
        }
        final gridTextScale = textScale.clamp(1.0, 2.0);
        final timeColumnWidth = useAgendaFallback
            ? 0.0
            : compact
            ? _compactTimeColumnWidth * gridTextScale
            : _regularTimeColumnWidth * gridTextScale;
        final rowHeight =
            (compact ? _compactRowHeight : _regularRowHeight) * gridTextScale;
        final headerBaseHeight = compact
            ? _compactHeaderBaseHeight
            : _regularHeaderBaseHeight;
        final deadlineGap =
            (compact ? _compactDeadlineGap : _regularDeadlineGap) *
            gridTextScale;
        final deadlineEventHeight = compact
            ? _compactDeadlineEventHeight * gridTextScale
            : _regularDeadlineEventHeight * gridTextScale;
        const nowLineHeight = 2.0;
        final headerHeight = headerBaseHeight * gridTextScale;
        final minimumDayColumnWidth = textScale >= 1.6 ? 116.0 : 92.0;
        final shouldScrollMobileGrid =
            !useAgendaFallback &&
            ((_isMac && constraints.maxWidth < 700) ||
                (isMobile && textScale >= 1.6));
        final gridContentWidth = shouldScrollMobileGrid
            ? math.max(
                constraints.maxWidth,
                timeColumnWidth + columnWeight * minimumDayColumnWidth,
              )
            : constraints.maxWidth;
        final dayColumnWidth =
            (gridContentWidth - timeColumnWidth).clamp(0.0, double.infinity) /
            columnWeight;
        final dayLefts = <int, double>{};
        final dayWidths = <int, double>{};
        final columnLefts = <ScheduleDayColumn, double>{};
        var columnLeft = 0.0;
        for (final column in columns) {
          columnLefts[column] = columnLeft;
          final width = dayColumnWidth * column.weight;
          for (var i = 0; i < column.dates.length; i++) {
            final index = dayIndexByWeekday[column.dates[i].weekday]!;
            dayLefts[index] = columnLeft + width * i / column.dates.length;
            dayWidths[index] = width / column.dates.length;
          }
          columnLeft += width;
        }
        final fitHeight = math.max(
          280.0,
          viewportHeight - _pinnedHeaderExtent - headerHeight,
        );
        final geometry = ScheduleGridGeometry(
          startMinutes: visibleSlots.first.startMinutes,
          endMinutes: visibleSlots.last.endMinutes,
          availableHeight: textScale > 1.25
              ? math.max(fitHeight, visibleSlots.length * rowHeight)
              : fitHeight,
          occupiedRanges: meetingBlocks.map(
            (block) => (
              startMinutes: block.meeting.startMinutes,
              endMinutes: block.meeting.endMinutes,
            ),
          ),
        );
        final totalHeight = useAgendaFallback ? 0.0 : geometry.height;
        final nowMarker = useAgendaFallback
            ? null
            : _buildCurrentTimeMarker(
                visibleDays,
                geometry: geometry,
                weekStart: weekStart,
                dayIndexByWeekday: dayIndexByWeekday,
                visibleSlots: visibleSlots,
                rowHeight: rowHeight,
                markerSize: nowLineHeight,
              );
        final todayIndex = visibleDays.indexWhere(
          (day) => _isSameDate(day, _currentTime),
        );
        final todayTone = _todayHighlightTone(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!useAgendaFallback && weekExams.isNotEmpty) ...[
              _buildExamSection(context, weekExams, showDate: true),
              SizedBox(height: tokens.space12),
            ],
            Column(
              children: [
                if (useAgendaFallback)
                  _buildAgendaWeekCard(
                    context,
                    visibleDays,
                    active: active,
                    weekStart: weekStart,
                    meetingsByWeekday: meetingsByWeekday,
                    deadlinesByWeekday: deadlinesByWeekday,
                    examsByWeekday: examsByWeekday,
                    holidayNoticesByWeekday: holidayNoticesByWeekday,
                    viewportHeight: viewportHeight,
                  )
                else
                  Semantics(
                    label: context.l10n.text('课表横表视图'),
                    child: SingleChildScrollView(
                      key: const ValueKey(
                        'schedule-week-grid-horizontal-scroll',
                      ),
                      controller: active
                          ? _weekGridHorizontalScrollController
                          : null,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: shouldScrollMobileGrid && !swipeEnabled
                          ? null
                          : const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: gridContentWidth,
                        child: Column(
                          children: [
                            SizedBox(
                              height: headerHeight,
                              child: Row(
                                children: [
                                  SizedBox(width: timeColumnWidth),
                                  for (final column in columns)
                                    _buildDayHeader(
                                      context,
                                      column.dates.first,
                                      endDate: column.dates.length > 1
                                          ? column.dates.last
                                          : null,
                                      width: dayColumnWidth * column.weight,
                                      compact: compact,
                                      hasCourses: column.dates.any(
                                        (day) =>
                                            meetingsByWeekday[day.weekday]
                                                ?.isNotEmpty ??
                                            false,
                                      ),
                                      hasDeadlines:
                                          _showDeadlines &&
                                          column.dates.any(
                                            (day) =>
                                                deadlinesByWeekday[day.weekday]
                                                    ?.isNotEmpty ??
                                                false,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              key: const ValueKey('schedule-grid-time-axis'),
                              height: totalHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Row(
                                      children: [
                                        SizedBox(width: timeColumnWidth),
                                        for (
                                          var day = 0;
                                          day < columns.length;
                                          day++
                                        )
                                          Container(
                                            width:
                                                dayColumnWidth *
                                                columns[day].weight,
                                            decoration: BoxDecoration(
                                              border: Border(
                                                left: BorderSide(
                                                  color: tokens.border
                                                      .withValues(alpha: 0.5),
                                                  width: 0.5,
                                                ),
                                                right: day == columns.length - 1
                                                    ? BorderSide(
                                                        color: tokens.border
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                        width: 0.5,
                                                      )
                                                    : BorderSide.none,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  for (
                                    var index = 0;
                                    index < visibleSlots.length;
                                    index++
                                  )
                                    if (index.isOdd)
                                      Positioned(
                                        left: timeColumnWidth,
                                        right: 0,
                                        top: geometry.offsets[index],
                                        height: geometry.rowHeight(index),
                                        child: Container(
                                          color: tokens.surfaceMuted.withValues(
                                            alpha: 0.16,
                                          ),
                                        ),
                                      ),
                                  if (todayIndex >= 0 && todayTone != null)
                                    Positioned(
                                      left:
                                          timeColumnWidth +
                                          dayLefts[todayIndex]!,
                                      top: 0,
                                      width: dayWidths[todayIndex]!,
                                      height: totalHeight,
                                      child: DecoratedBox(
                                        key: const ValueKey(
                                          'schedule-grid-today-highlight',
                                        ),
                                        decoration: BoxDecoration(
                                          color: todayTone.background,
                                        ),
                                      ),
                                    ),
                                  for (
                                    var index = 0;
                                    index <= visibleSlots.length;
                                    index++
                                  )
                                    Positioned(
                                      key: ValueKey(
                                        'schedule-grid-line-${geometry.startMinutes + index * 60}',
                                      ),
                                      left: 0,
                                      right: 0,
                                      top: index < visibleSlots.length
                                          ? geometry.offsets[index]
                                          : null,
                                      bottom: index == visibleSlots.length
                                          ? 0
                                          : null,
                                      child: Divider(
                                        height: 1,
                                        color: tokens.border.withValues(
                                          alpha: 0.5,
                                        ),
                                        thickness: 0.5,
                                      ),
                                    ),
                                  for (
                                    var index = 0;
                                    index < visibleSlots.length;
                                    index++
                                  )
                                    Positioned(
                                      key: ValueKey(
                                        'schedule-hour-${visibleSlots[index].startMinutes}',
                                      ),
                                      left: 0,
                                      top: geometry.offsets[index],
                                      width: timeColumnWidth,
                                      height: geometry.rowHeight(index),
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: compact ? 4 : 6,
                                          top: 6,
                                          bottom: 6,
                                        ),
                                        child: _buildTimeAxisLabel(
                                          context,
                                          visibleSlots[index],
                                          compact: compact,
                                        ),
                                      ),
                                    ),
                                  for (final column in columns)
                                    if (column.isHoliday)
                                      _buildHolidayBlock(
                                        context,
                                        geometry: geometry,
                                        label: column.holidayLabels.join(' / '),
                                        date: column.dates.first,
                                        endDate: column.dates.length > 1
                                            ? column.dates.last
                                            : null,
                                        dayIndex: 0,
                                        timeColumnWidth:
                                            timeColumnWidth +
                                            columnLefts[column]!,
                                        dayColumnWidth:
                                            dayColumnWidth * column.weight,
                                        height: totalHeight,
                                        rowHeight: rowHeight,
                                        compact: compact,
                                      ),
                                  Positioned(
                                    left: 0,
                                    bottom: 0,
                                    width: timeColumnWidth,
                                    child: Align(
                                      alignment: Alignment.bottomRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Text(
                                          '${visibleSlots.last.endMinutes ~/ 60}',
                                          key: const ValueKey(
                                            'schedule-end-hour',
                                          ),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: compact ? 9.5 : 10.5,
                                            height: 1.05,
                                            color: tokens.textMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (final block in meetingBlocks)
                                    if (dayIndexByWeekday[block.meeting.weekday]
                                        case final dayIndex?)
                                      _buildMeetingBlock(
                                        context,
                                        block,
                                        active: active,
                                        geometry: geometry,
                                        dayIndex: 0,
                                        timeColumnWidth:
                                            timeColumnWidth +
                                            dayLefts[dayIndex]!,
                                        dayColumnWidth: dayWidths[dayIndex]!,
                                        visibleSlots: visibleSlots,
                                        rowHeight: rowHeight,
                                        compact: compact,
                                      ),
                                  if (_showDeadlines)
                                    for (final block in _buildDeadlineBlocks(
                                      visibleDays,
                                      deadlinesByWeekday,
                                      geometry: geometry,
                                      visibleSlots: visibleSlots,
                                      totalHeight: totalHeight,
                                      height: deadlineEventHeight,
                                      minGap: deadlineGap,
                                    ))
                                      _buildDeadlineBlock(
                                        context,
                                        block,
                                        totalHeight: totalHeight,
                                        timeColumnWidth:
                                            timeColumnWidth +
                                            dayLefts[block.dayIndex]!,
                                        dayColumnWidth:
                                            dayWidths[block.dayIndex]!,
                                        compact: compact,
                                      ),
                                  if (nowMarker != null)
                                    _buildCurrentTimeLine(
                                      context,
                                      nowMarker,
                                      active: active,
                                      timeColumnWidth:
                                          timeColumnWidth +
                                          dayLefts[nowMarker.dayIndex]!,
                                      dayColumnWidth:
                                          dayWidths[nowMarker.dayIndex]!,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildAgendaWeekCard(
    BuildContext context,
    List<DateTime> visibleDays, {
    required bool active,
    required DateTime weekStart,
    required Map<int, List<_MeetingBlock>> meetingsByWeekday,
    required Map<int, List<TimelineItem>> deadlinesByWeekday,
    required Map<int, List<ExamTimetableEntry>> examsByWeekday,
    required Map<int, String> holidayNoticesByWeekday,
    required double viewportHeight,
  }) {
    final tokens = context.bnbuTheme;
    return Semantics(
      label: context.l10n.text('课表竖表视图'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: tokens.space24),
          for (var index = 0; index < visibleDays.length; index++) ...[
            KeyedSubtree(
              key: active && _isSameDate(visibleDays[index], _currentTime)
                  ? _currentAgendaDayKey
                  : null,
              child: _buildAgendaDaySection(
                context,
                visibleDays[index],
                active: active,
                meetings:
                    meetingsByWeekday[visibleDays[index].weekday] ?? const [],
                deadlines: _showDeadlines
                    ? deadlinesByWeekday[visibleDays[index].weekday] ?? const []
                    : const [],
                exams: examsByWeekday[visibleDays[index].weekday] ?? const [],
                holidayNotice:
                    holidayNoticesByWeekday[visibleDays[index].weekday],
              ),
            ),
            if (index != visibleDays.length - 1)
              SizedBox(height: tokens.space24),
          ],
          SizedBox(
            key: const ValueKey('schedule-list-trailing-space'),
            height: _isSameDate(_startOfWeek(_currentTime), weekStart)
                ? math.max(tokens.space24, viewportHeight * 0.62)
                : tokens.space24,
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaDaySection(
    BuildContext context,
    DateTime day, {
    required bool active,
    required List<_MeetingBlock> meetings,
    required List<TimelineItem> deadlines,
    required List<ExamTimetableEntry> exams,
    String? holidayNotice,
  }) {
    final tokens = context.bnbuTheme;
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    final isCurrentDay = _isSameDate(day, _currentTime);
    final todayTone = isCurrentDay ? _todayHighlightTone(context) : null;
    final sortedMeetings = List<_MeetingBlock>.from(meetings)
      ..sort(
        (left, right) =>
            left.meeting.startMinutes.compareTo(right.meeting.startMinutes),
      );
    final sortedDeadlines = List<TimelineItem>.from(deadlines)
      ..sort(
        (left, right) =>
            (left.sortTime ?? day).compareTo(right.sortTime ?? day),
      );
    final hasItems =
        holidayNotice != null ||
        sortedMeetings.isNotEmpty ||
        sortedDeadlines.isNotEmpty ||
        exams.isNotEmpty;

    return Container(
      key: ValueKey('schedule-list-day-$dateKey'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BnbuText(
                key: isCurrentDay
                    ? const ValueKey('schedule-list-today-title')
                    : null,
                '${_weekdayLabel(day)} ${_dateLabel(day)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color:
                      todayTone?.foreground ??
                      (isCurrentDay ? tokens.brandBlue : tokens.textPrimary),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space12),
          if (holidayNotice != null) ...[
            BnbuNotice(
              message: holidayNotice,
              kind: BnbuStatusKind.warning,
              icon: LucideIcons.calendarOff300,
            ),
            if (sortedMeetings.isNotEmpty ||
                sortedDeadlines.isNotEmpty ||
                exams.isNotEmpty)
              SizedBox(height: tokens.space12),
          ],
          if (exams.isNotEmpty) ...[
            _buildExamSection(context, exams, showDate: false),
            if (sortedMeetings.isNotEmpty || sortedDeadlines.isNotEmpty)
              SizedBox(height: tokens.space12),
          ],
          for (var index = 0; index < sortedMeetings.length; index++) ...[
            KeyedSubtree(
              key: active && _isRequestedMeeting(sortedMeetings[index])
                  ? _requestedCourseCardKey
                  : null,
              child: _buildCourseSummaryCard(
                context,
                sortedMeetings[index],
                keyPrefix: 'schedule-list-$dateKey',
                onTap: () => _showCourseDetail(sortedMeetings[index]),
                showChevron: true,
              ),
            ),
            if (index != sortedMeetings.length - 1 ||
                sortedDeadlines.isNotEmpty)
              SizedBox(height: tokens.space12),
          ],
          for (var index = 0; index < sortedDeadlines.length; index++) ...[
            _buildDeadlineSummaryCard(
              context,
              sortedDeadlines[index],
              cardKey: ValueKey(
                'schedule-list-$dateKey-deadline-${sortedDeadlines[index].id}',
              ),
              onTap: () => _showDeadlineDetail(sortedDeadlines[index]),
              showChevron: true,
            ),
            if (index != sortedDeadlines.length - 1)
              SizedBox(height: tokens.space12),
          ],
          if (!hasItems)
            BnbuText(
              '无安排',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildDeadlineSummaryCard(
    BuildContext context,
    TimelineItem item, {
    required Key cardKey,
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final accent = _deadlineAccentColor(item, tokens);
    return Semantics(
      button: true,
      label: 'DDL：${item.title}',
      value: context.l10n.text('截止时间 ${_deadlineLabel(item)}'),
      child: BnbuSurfaceCard(
        key: cardKey,
        onTap: onTap,
        backgroundColor: tokens.surface,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.zero,
        child: Row(
          children: [
            Container(width: 5, height: 116, color: accent),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  tokens.space16,
                  tokens.space12,
                  tokens.space12,
                  tokens.space12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.triangleAlert300,
                          size: 17,
                          color: accent,
                        ),
                        SizedBox(width: tokens.space8),
                        Expanded(
                          child: BnbuText(
                            _deadlineLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (showChevron)
                          Icon(
                            LucideIcons.arrowRight300,
                            color: tokens.textMuted,
                            size: 19,
                          ),
                      ],
                    ),
                    SizedBox(height: tokens.space12),
                    BnbuText(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.22,
                      ),
                    ),
                    SizedBox(height: tokens.space8),
                    BnbuText(
                      item.courseName.isEmpty ? 'DDL' : item.courseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    DateTime day, {
    DateTime? endDate,
    required double width,
    required bool compact,
    required bool hasCourses,
    required bool hasDeadlines,
  }) {
    final regularTone = _headerTone(
      context,
      hasCourses: hasCourses,
      hasDeadlines: hasDeadlines,
    );
    final today = DateTime(
      _currentTime.year,
      _currentTime.month,
      _currentTime.day,
    );
    final todayTone =
        (_isSameDate(day, today) ||
            (endDate != null &&
                !today.isBefore(day) &&
                !today.isAfter(endDate)))
        ? _todayHighlightTone(context)
        : null;
    final headerTone = todayTone == null
        ? regularTone
        : _HeaderTone(
            background: todayTone.background,
            border: todayTone.border,
            titleColor: todayTone.foreground,
            subtitleColor: Color.lerp(
              todayTone.foreground,
              context.bnbuTheme.textSecondary,
              0.28,
            )!,
          );
    final titleStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: headerTone.titleColor,
      fontWeight: FontWeight.w600,
      fontSize: compact ? 11 : 13,
      letterSpacing: 0,
    );
    final dateStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: headerTone.subtitleColor,
      fontSize: compact ? 10 : 11,
      letterSpacing: 0,
    );

    return SizedBox(
      width: width,
      child: Container(
        key: ValueKey(
          'schedule-day-header-${DateFormat('yyyy-MM-dd').format(day)}',
        ),
        padding: EdgeInsets.fromLTRB(
          compact ? 4 : 8,
          compact ? 3 : 8,
          compact ? 4 : 8,
          compact ? 3 : 8,
        ),
        decoration: BoxDecoration(
          color: todayTone?.background ?? Colors.transparent,
          border: Border(
            right: BorderSide(
              color: context.bnbuTheme.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
            bottom: BorderSide(
              color: context.bnbuTheme.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  endDate == null
                      ? _weekdayShortLabelFromWeekday(day.weekday)
                      : '${_weekdayShortLabelFromWeekday(day.weekday)}–${_weekdayShortLabelFromWeekday(endDate.weekday)}',
                  style: titleStyle?.copyWith(
                    color:
                        todayTone?.foreground ?? context.bnbuTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  endDate == null
                      ? _dateLabel(day)
                      : '${_dateLabel(day)}–${_dateLabel(endDate)}',
                  style: dateStyle?.copyWith(
                    color:
                        todayTone?.foreground ??
                        context.bnbuTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scheduleLocateCurrentTimeIfNeeded() {
    if (!_shouldLocateCurrentTime) {
      return;
    }
    _shouldLocateCurrentTime = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetContext =
          _currentTimeLineKey.currentContext ?? _weekBoardKey.currentContext;
      if (targetContext != null) {
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.32,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _scheduleLocateAgendaDayIfNeeded() {
    if (!_shouldLocateAgendaDay) {
      return;
    }
    _shouldLocateAgendaDay = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final currentWeekStart = _startOfWeek(_currentTime);
      final isCurrentWeek = _isSameDate(currentWeekStart, _visibleWeekStart);
      final targetContext = isCurrentWeek
          ? _currentAgendaDayKey.currentContext
          : (_usesSplit ? _macAgendaBoardKey : _weekBoardKey).currentContext;
      if (targetContext == null) {
        return;
      }
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      Scrollable.ensureVisible(
        targetContext,
        alignment: isCurrentWeek ? 0.32 : 0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildDeadlineBlock(
    BuildContext context,
    _DeadlineBlock block, {
    required double totalHeight,
    required double timeColumnWidth,
    required double dayColumnWidth,
    required bool compact,
  }) {
    final tokens = context.bnbuTheme;
    final markerSize = block.height;
    final hitSize = tokens.minInteractiveDimension;
    final hitTop = (block.top - (hitSize - markerSize) / 2)
        .clamp(0.0, math.max(0.0, totalHeight - hitSize))
        .toDouble();
    return Positioned(
      left: timeColumnWidth + (dayColumnWidth - hitSize) / 2,
      top: hitTop,
      width: hitSize,
      height: hitSize,
      child: Semantics(
        button: true,
        label: 'DDL：${block.item.title}',
        value: context.l10n.text('截止时间 ${_deadlineLabel(block.item)}'),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('schedule-deadline-hit-${block.item.id}'),
            customBorder: const CircleBorder(),
            onTap: () => _showDeadlineDetail(block.item),
            child: Stack(
              children: [
                Positioned(
                  left: (hitSize - markerSize) / 2,
                  top: block.top - hitTop,
                  width: markerSize,
                  height: markerSize,
                  child: KeyedSubtree(
                    key: ValueKey('schedule-deadline-${block.item.id}'),
                    child: _buildDeadlineCard(
                      context,
                      block.item,
                      compact: compact,
                      height: markerSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeadlineCard(
    BuildContext context,
    TimelineItem item, {
    required bool compact,
    required double height,
  }) {
    final tokens = context.bnbuTheme;
    final accentColor = _deadlineAccentColor(item, tokens);
    return Tooltip(
      message: '${item.title}\n${_deadlineLabel(item)}',
      child: Container(
        width: height,
        height: height,
        decoration: BoxDecoration(
          color: accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.28),
              blurRadius: compact ? 6 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          LucideIcons.triangleAlert300,
          size: compact ? 10 : 12,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTimeAxisLabel(
    BuildContext context,
    _SlotSpec slot, {
    required bool compact,
  }) {
    final tokens = context.bnbuTheme;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens.textMuted,
      height: 1.05,
      fontSize: compact ? 9.5 : 10.5,
      fontWeight: FontWeight.w700,
    );

    return Text(
      '${slot.startMinutes ~/ 60}',
      textAlign: TextAlign.right,
      style: textStyle?.copyWith(fontWeight: FontWeight.w400),
    );
  }

  Widget _buildMeetingBlock(
    BuildContext context,
    _MeetingBlock block, {
    required bool active,
    required ScheduleGridGeometry geometry,
    required int dayIndex,
    required double timeColumnWidth,
    required double dayColumnWidth,
    required List<_SlotSpec> visibleSlots,
    required double rowHeight,
    required bool compact,
  }) {
    final tokens = context.bnbuTheme;
    final color = block.color;
    final secondaryText = block.meeting.room.isEmpty
        ? (block.taCourse == null ? block.course.teacher : '')
        : block.meeting.room;
    final top = geometry.offsetFor(block.meeting.startMinutes.toDouble());
    final bottom = geometry.offsetFor(block.meeting.endMinutes.toDouble());
    final blockHeight = math.max(1.0, bottom - top);
    final hitHeight = math.max(blockHeight, tokens.minInteractiveDimension);
    final hitTop = (top - (hitHeight - blockHeight) / 2)
        .clamp(0.0, math.max(0.0, geometry.height - hitHeight))
        .toDouble();
    final width = dayColumnWidth;

    return Positioned(
      left: timeColumnWidth + dayIndex * dayColumnWidth,
      top: hitTop.toDouble(),
      width: width,
      height: hitHeight,
      child: Semantics(
        button: true,
        label: context.l10n.text('课程：${block.course.name}'),
        value:
            '${_weekdayLabelFromWeekday(block.meeting.weekday)} ${block.meeting.startLabel}-${block.meeting.endLabel}'
            '${secondaryText.isEmpty ? '' : '，$secondaryText'}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showCourseDetail(block),
            child: Stack(
              children: [
                Positioned(
                  top: top - hitTop,
                  left: 0,
                  right: 0,
                  height: blockHeight,
                  child: KeyedSubtree(
                    key: active && !_usesSplit && _isRequestedMeeting(block)
                        ? _requestedCourseCardKey
                        : null,
                    child: SizedBox(
                      height: blockHeight,
                      width: width,
                      child: Container(
                        key: ValueKey<String>(
                          'schedule-course-block-'
                          '${block.meeting.weekday}-'
                          '${block.meeting.startMinutes}-'
                          '${block.course.code}',
                        ),
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          border: Border.all(
                            color: color.withValues(alpha: 0.35),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 1.5,
                              color: color.withValues(alpha: 0.75),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  compact ? 4 : 7,
                                  compact ? 3 : 5,
                                  compact ? 4 : 7,
                                  compact ? 4 : 7,
                                ),
                                child: _buildMeetingTextContent(
                                  context,
                                  title: block.course.name,
                                  secondaryText:
                                      '${block.meeting.startLabel}–${block.meeting.endLabel}${secondaryText.isEmpty ? '' : '\n$secondaryText'}',
                                  compact: compact,
                                  accent: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTimeLine(
    BuildContext context,
    _CurrentTimeMarker marker, {
    required bool active,
    required double timeColumnWidth,
    required double dayColumnWidth,
  }) {
    return Positioned(
      left: timeColumnWidth,
      top: marker.top,
      width: dayColumnWidth,
      height: marker.size,
      child: IgnorePointer(
        child: Semantics(
          label: context.l10n.text(
            '当前时间 ${TaCourseEntry.formatMinutes(marker.minutes)}',
          ),
          child: ColoredBox(
            key: active ? _currentTimeLineKey : null,
            color: context.bnbuTheme.brandBlue,
          ),
        ),
      ),
    );
  }

  Widget _buildMeetingTextContent(
    BuildContext context, {
    required String title,
    required String secondaryText,
    required bool compact,
    required Color accent,
  }) {
    final tokens = context.bnbuTheme;
    final titleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      fontSize: compact ? 7.8 : 9.8,
      height: compact ? 1.1 : 1.15,
    );
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Color.lerp(accent, tokens.textPrimary, 0.4),
      fontSize: compact ? 6.8 : 8.8,
      height: 1.15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );

    if (secondaryText.isEmpty) {
      return BnbuText(
        title,
        maxLines: compact ? 8 : 8,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final gap = compact ? 2.0 : 4.0;

        final titlePainter = _textPainter(
          context: context,
          text: title,
          style: titleStyle,
          maxWidth: width,
        );
        final titleLineHeight = titlePainter.preferredLineHeight;
        if (height < titleLineHeight * 2) {
          return ClipRect(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: titleStyle,
            ),
          );
        }
        final secondaryPainter = _textPainter(
          context: context,
          text: secondaryText,
          style: secondaryStyle,
          maxWidth: width,
        );
        final secondaryLineHeight = secondaryPainter.preferredLineHeight;
        final secondaryLineCount = secondaryPainter.computeLineMetrics().length;
        final secondaryMaxLines =
            ((height - gap - titleLineHeight) / secondaryLineHeight)
                .floor()
                .clamp(1, 99);
        final displayedSecondaryLines = secondaryLineCount.clamp(
          1,
          secondaryMaxLines,
        );
        final displayedSecondaryHeight =
            displayedSecondaryLines * secondaryLineHeight;
        final remainingTitleHeight = (height - displayedSecondaryHeight - gap)
            .clamp(titleLineHeight, height);
        final titleMaxLines = (remainingTitleHeight / titleLineHeight)
            .floor()
            .clamp(1, 99);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: BnbuText(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
            SizedBox(height: gap),
            BnbuText(
              secondaryText,
              maxLines: displayedSecondaryLines,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: secondaryStyle,
            ),
          ],
        );
      },
    );
  }

  List<String> _teacherNames(String value) {
    return value
        .split(RegExp(r'\s*(?:;|；|，|、|&|/|\r?\n)\s*'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != 'TA课')
        .toSet()
        .toList(growable: false);
  }

  bool _openingTeacher = false;

  Future<void> _openTeacherProfile(
    String teacherName, {
    CampusDirectoryService? directoryService,
    Future<OfficialTeacherPage?>? prefetchedPage,
  }) async {
    if (_openingTeacher || !mounted) return;
    _openingTeacher = true;
    try {
      await openOfficialTeacherByName(
        context,
        controller: widget.controller,
        teacherName: teacherName,
        directoryService: directoryService ?? widget.directoryService,
        reviewService: widget.teacherReviewService,
        prefetchedPage: prefetchedPage,
      );
    } finally {
      _openingTeacher = false;
    }
  }

  Future<void> _chooseTeacher(List<String> names) async {
    final selected = await _selectTeacher(names);
    if (selected != null && mounted) await _openTeacherProfile(selected);
  }

  Future<String?> _selectTeacher(List<String> names) =>
      showBnbuAdaptiveModal<String>(
        context: context,
        useRootNavigator: true,
        dialogMaxWidth: 460,
        dialogMaxHeight: 560,
        semanticLabel: context.l10n.text('选择教师'),
        builder: (modalContext, presentation) => BnbuModalFrame(
          presentation: presentation,
          title: '选择教师',
          icon: LucideIcons.contactRound300,
          bodyPadding: EdgeInsets.zero,
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(
              vertical: modalContext.bnbuTheme.space8,
            ),
            children: [
              for (final name in names)
                ListTile(
                  minTileHeight: 48,
                  title: BnbuText(name),
                  trailing: const Icon(LucideIcons.arrowRight300, size: 18),
                  onTap: () => Navigator.of(modalContext).pop(name),
                ),
            ],
          ),
        ),
      );

  Future<void> _showCourseDetail(_MeetingBlock block) async {
    final course = block.course;
    final meeting = block.meeting;
    final taCourse = block.taCourse;

    // Prewarm only this opened course, using the existing shared public cache.
    final names = taCourse == null ? _teacherNames(course.teacher) : <String>[];
    final service = widget.directoryService ?? RemoteCampusDirectoryService();
    final prefetched = <String, Future<OfficialTeacherPage?>>{
      for (final name in names.take(8))
        name: Future.sync(() => service.loadTeachers(query: name, limit: 20))
            .then<OfficialTeacherPage?>(
              (page) => page,
              onError: (Object _) => null,
            ),
    };
    try {
      final selectedNames = await showBnbuAdaptiveModal<List<String>>(
        context: context,
        useRootNavigator: true,
        dialogMaxWidth: 760,
        dialogMaxHeight: 680,
        isScrollControlled: true,
        bottomSheetBackgroundColor: context.bnbuTheme.surface,
        semanticLabel: context.l10n.text('课程详情'),
        contentKey: const ValueKey('schedule-course-detail-modal'),
        builder: (modalContext, presentation) {
          final tokens = modalContext.bnbuTheme;
          return SizedBox(
            key: const ValueKey('schedule-course-detail-sheet'),
            width: double.infinity,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  tokens.space16,
                  tokens.space8,
                  tokens.space16,
                  tokens.space24 + MediaQuery.viewInsetsOf(modalContext).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...[
                      Row(
                        children: [
                          Expanded(
                            child: BnbuText(
                              '课程详情',
                              style: Theme.of(
                                modalContext,
                              ).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.text('关闭'),
                            onPressed: () => Navigator.of(modalContext).pop(),
                            icon: const Icon(LucideIcons.x300),
                          ),
                        ],
                      ),
                      SizedBox(height: tokens.space8),
                    ],
                    _buildCourseSummaryCard(
                      modalContext,
                      block,
                      keyPrefix: 'schedule-detail',
                      onTeacherTap: (names) =>
                          Navigator.of(modalContext).pop(names),
                    ),
                    SizedBox(height: tokens.space16),
                    _buildInfoRow(
                      modalContext,
                      '本次时间',
                      '${_weekdayLabelFromWeekday(meeting.weekday)} ${meeting.startLabel}-${meeting.endLabel}',
                    ),
                    if (taCourse?.isTa == true)
                      _buildInfoRow(
                        modalContext,
                        '所属课程',
                        '${course.name} · ${taCourse!.courseCode}',
                      ),
                    if (taCourse != null)
                      _buildInfoRow(
                        modalContext,
                        '重复方式',
                        _taCourseRepeatLabel(taCourse),
                      ),
                    _buildInfoRow(
                      modalContext,
                      '课程类型',
                      taCourse != null
                          ? taCourse.kindLabel
                          : (course.category.isEmpty ? '未提供' : course.category),
                    ),
                    if (taCourse == null)
                      _buildInfoRow(
                        modalContext,
                        '学分',
                        course.units.isEmpty ? '未提供' : course.units,
                      ),
                    if (taCourse == null)
                      _buildInfoRow(
                        modalContext,
                        '节次',
                        course.section.isEmpty ? '未提供' : course.section,
                      ),
                    _buildInfoRow(
                      modalContext,
                      '本周全部上课时间',
                      taCourse != null
                          ? meeting.timeLabel
                          : course.meetings
                                .map((item) => item.timeLabel)
                                .join('  /  '),
                    ),
                    if (course.remark.isNotEmpty)
                      _buildInfoRow(modalContext, '备注', course.remark),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (!mounted || selectedNames == null) return;
      final selected = selectedNames.length == 1
          ? selectedNames.single
          : await _selectTeacher(selectedNames);
      if (selected != null && mounted) {
        await _openTeacherProfile(
          selected,
          directoryService: service,
          prefetchedPage: prefetched[selected],
        );
      }
    } finally {
      if (widget.directoryService == null) service.dispose();
    }
  }

  Future<void> _showDeadlineDetail(TimelineItem item) async {
    final openIspace = await showBnbuAdaptiveModal<bool>(
      context: context,
      useRootNavigator: true,
      dialogMaxWidth: 640,
      dialogMaxHeight: 620,
      isScrollControlled: true,
      bottomSheetBackgroundColor: context.bnbuTheme.surface,
      semanticLabel: context.l10n.text('DDL详情'),
      contentKey: const ValueKey('schedule-deadline-detail-modal'),
      builder: (modalContext, presentation) {
        final tokens = modalContext.bnbuTheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              tokens.space16,
              tokens.space8,
              tokens.space16,
              tokens.space24 + MediaQuery.viewInsetsOf(modalContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...[
                  Row(
                    children: [
                      Expanded(
                        child: BnbuText(
                          'DDL详情',
                          style: Theme.of(modalContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.text('关闭'),
                        onPressed: () => Navigator.of(modalContext).pop(),
                        icon: const Icon(LucideIcons.x300),
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.space8),
                ],
                BnbuTimelineSummaryCard(
                  key: const ValueKey('schedule-detail-deadline-card'),
                  item: item,
                  deadlineLabel: _deadlineLabel(item),
                  statusLabel: item.isOverdue
                      ? '已逾期'
                      : (item.activityState.trim().isEmpty
                            ? '待完成'
                            : item.activityState.trim()),
                  accentColor: _deadlineAccentColor(item, tokens),
                  onTap: null,
                  showChevron: false,
                ),
                SizedBox(height: tokens.space16),
                _buildInfoRow(modalContext, '截止时间', _deadlineLabel(item)),
                _buildInfoRow(
                  modalContext,
                  '状态',
                  item.isOverdue ? '已逾期' : item.activityState,
                ),
                if (item.description.isNotEmpty)
                  _buildInfoRow(modalContext, '说明', item.description),
                SizedBox(height: tokens.space4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('schedule-deadline-open-ispace'),
                    onPressed: () => Navigator.of(modalContext).pop(true),
                    icon: const Icon(LucideIcons.arrowUpRight300),
                    label: const BnbuText('打开 iSpace'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (openIspace != true || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            TimelineDetailPage(controller: widget.controller, item: item),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tokens.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: tokens.space4),
          BnbuText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayBlock(
    BuildContext context, {
    required ScheduleGridGeometry geometry,
    required String label,
    required DateTime date,
    DateTime? endDate,
    required int dayIndex,
    required double timeColumnWidth,
    required double dayColumnWidth,
    required double height,
    required double rowHeight,
    required bool compact,
  }) {
    final tokens = context.bnbuTheme;
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final displayLabel = label == 'Reading Week 假期'
        ? 'Reading Week\n假期'
        : label;
    return Positioned(
      left: timeColumnWidth + dayIndex * dayColumnWidth,
      top: 0,
      width: dayColumnWidth,
      height: height,
      child: Semantics(
        label:
            '${_dateLabel(date)}${endDate == null ? '' : '–${_dateLabel(endDate)}'} $label',
        child: ScheduleHolidayPanel(
          key: ValueKey('schedule-holiday-block-$dateKey'),
          scrollController: _scrollController,
          viewportKey: _scrollViewportKey,
          pinnedHeaderExtent: _usesSplit ? 0 : _pinnedHeaderExtent,
          rowHeight: rowHeight,
          rowOffsets: geometry.offsets,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          backgroundColor: tokens.warningContainer.withValues(alpha: 0.92),
          borderColor: tokens.warning.withValues(alpha: 0.48),
          child: ExcludeSemantics(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 3 : tokens.space8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.calendarOff300,
                    size: compact ? 16 : 20,
                    color: tokens.warning,
                  ),
                  SizedBox(height: tokens.space8),
                  BnbuText(
                    displayLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_MeetingBlock> _buildMeetingBlocks(
    TimetableData timetable,
    Map<String, Color> courseColors,
    BnbuThemeExtension tokens, {
    required DateTime visibleWeekStart,
  }) {
    final blocks = <_MeetingBlock>[];
    for (final course in timetable.courses) {
      final seed = CourseColorPalette.courseSeed(course);
      final color =
          courseColors[seed] ?? CourseColorPalette.fallback(seed, tokens);
      for (final meeting in course.meetings) {
        for (var offset = 0; offset < 7; offset++) {
          final date = DateTime(
            visibleWeekStart.year,
            visibleWeekStart.month,
            visibleWeekStart.day + offset,
          );
          final classDay = BnbuAcademicCalendar.classDayFor(timetable, date);
          if (classDay.sourceWeekday != meeting.weekday) continue;
          final displayedMeeting = classDay.isMakeUpDay
              ? TimetableMeeting(
                  weekday: date.weekday,
                  dayLabel:
                      '${_weekdayShortLabelFromWeekday(date.weekday)}（补${_weekdayShortLabelFromWeekday(meeting.weekday)}）',
                  startLabel: meeting.startLabel,
                  endLabel: meeting.endLabel,
                  startMinutes: meeting.startMinutes,
                  endMinutes: meeting.endMinutes,
                  room: meeting.room,
                )
              : meeting;
          blocks.add(
            _MeetingBlock(
              color: color,
              course: course,
              meeting: displayedMeeting,
              taCourse: null,
            ),
          );
        }
      }
    }
    for (final taCourse in widget.taCourseController.entries) {
      if (!taCourse.appliesToWeek(visibleWeekStart) ||
          !taCourse.isVisibleIn(timetable)) {
        continue;
      }
      final seed = CourseColorPalette.taCourseSeed(taCourse);
      final color =
          courseColors[seed] ?? CourseColorPalette.fallback(seed, tokens);
      final meeting = TimetableMeeting(
        weekday: taCourse.weekday,
        dayLabel: _weekdayShortLabelFromWeekday(taCourse.weekday),
        startLabel: TaCourseEntry.formatMinutes(taCourse.startMinutes),
        endLabel: TaCourseEntry.formatMinutes(taCourse.endMinutes),
        startMinutes: taCourse.startMinutes,
        endMinutes: taCourse.endMinutes,
        room: taCourse.displayLocation,
      );
      blocks.add(
        _MeetingBlock(
          color: color,
          course: TimetableCourse(
            section: taCourse.isTa ? 'TA' : '日程',
            category: taCourse.kindLabel,
            code: taCourse.isTa
                ? taCourse.courseCode
                : 'schedule:${taCourse.id}',
            name: taCourse.displayTitle,
            teacher: taCourse.kindLabel,
            meetings: <TimetableMeeting>[meeting],
            rooms: taCourse.displayLocation.isEmpty
                ? const <String>[]
                : <String>[taCourse.displayLocation],
            units: '',
            remark: '',
          ),
          meeting: meeting,
          taCourse: taCourse,
        ),
      );
    }
    blocks.sort((left, right) {
      final weekdayCompare = left.meeting.weekday.compareTo(
        right.meeting.weekday,
      );
      if (weekdayCompare != 0) {
        return weekdayCompare;
      }
      return left.meeting.startMinutes.compareTo(right.meeting.startMinutes);
    });
    return blocks;
  }

  List<_DeadlineBlock> _buildDeadlineBlocks(
    List<DateTime> visibleDays,
    Map<int, List<TimelineItem>> deadlinesByWeekday, {
    required ScheduleGridGeometry geometry,
    required List<_SlotSpec> visibleSlots,
    required double totalHeight,
    required double height,
    required double minGap,
  }) {
    final blocks = <_DeadlineBlock>[];
    if (!_showDeadlines) {
      return blocks;
    }

    final maxTop = (totalHeight - height)
        .clamp(0.0, double.infinity)
        .toDouble();
    for (var dayIndex = 0; dayIndex < visibleDays.length; dayIndex++) {
      final items =
          deadlinesByWeekday[visibleDays[dayIndex].weekday] ?? const [];
      double lastBottom = -minGap;
      for (final item in items) {
        final due = item.sortTime?.toLocal();
        final dueMinutes = due == null
            ? visibleSlots.first.startMinutes.toDouble()
            : (due.hour * 60 + due.minute).toDouble();
        final desiredTop = geometry.offsetFor(dueMinutes).clamp(0.0, maxTop);
        final top = desiredTop < lastBottom + minGap
            ? (lastBottom + minGap).clamp(0.0, maxTop).toDouble()
            : desiredTop;
        blocks.add(
          _DeadlineBlock(
            item: item,
            dayIndex: dayIndex,
            top: top,
            height: height,
          ),
        );
        lastBottom = top + height;
      }
    }
    return blocks;
  }

  List<TimelineItem> _deadlinesForWeek(DateTime weekStart) {
    final start = _startOfWeek(weekStart);
    final end = start.add(const Duration(days: 7));
    final items = widget.controller.timelineItems.where((item) {
      final due = item.sortTime?.toLocal();
      return due != null && !due.isBefore(start) && due.isBefore(end);
    }).toList();
    items.sort((left, right) {
      final leftTime = left.sortTime ?? start;
      final rightTime = right.sortTime ?? start;
      return leftTime.compareTo(rightTime);
    });
    return items;
  }

  List<TimelineItem> _deadlinesOnDate(List<TimelineItem> items, DateTime day) {
    return items
        .where(
          (item) =>
              item.sortTime != null &&
              _isSameDate(item.sortTime!.toLocal(), day),
        )
        .toList();
  }

  List<DateTime> _weekDatesForStart(DateTime weekStart) {
    final start = _startOfWeek(weekStart);
    return List<DateTime>.generate(
      7,
      (index) => start.add(Duration(days: index)),
    );
  }

  List<DateTime> _resolveVisibleDays(
    List<DateTime> weekDates, {
    required Map<int, List<_MeetingBlock>> meetingsByWeekday,
    required Map<int, List<TimelineItem>> deadlinesByWeekday,
    required Map<int, String> holidayNoticesByWeekday,
  }) {
    bool hasVisibleEvents(int weekday) {
      final hasCourses = meetingsByWeekday[weekday]?.isNotEmpty ?? false;
      final hasDeadlines =
          _showDeadlines && (deadlinesByWeekday[weekday]?.isNotEmpty ?? false);
      final hasHoliday = holidayNoticesByWeekday.containsKey(weekday);
      return hasCourses || hasDeadlines || hasHoliday;
    }

    final hasSaturdayEvents = hasVisibleEvents(DateTime.saturday);
    final hasSundayEvents = hasVisibleEvents(DateTime.sunday);

    return weekDates.where((day) {
      if (day.weekday <= DateTime.friday) {
        return true;
      }
      if (day.weekday == DateTime.saturday) {
        return hasSaturdayEvents || hasSundayEvents;
      }
      return hasSundayEvents;
    }).toList();
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _weekRangeLabel(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 6));
    if (context.l10n.isEnglish) {
      return '${context.l10n.formatMonthDay(weekStart)} - '
          '${context.l10n.formatMonthDay(end)}';
    }
    return '${weekStart.month}/${weekStart.day} - ${end.month}/${end.day}';
  }

  String get _compactWeekRangeLabel {
    final end = _visibleWeekStart.add(const Duration(days: 6));
    return '${_visibleWeekStart.month}/${_visibleWeekStart.day}–${end.month}/${end.day}';
  }

  String _weekdayLabel(DateTime day) {
    return _weekdayLabelFromWeekday(day.weekday);
  }

  String _weekdayLabelFromWeekday(int weekday) {
    const labels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[weekday - 1];
  }

  String _weekdayShortLabelFromWeekday(int weekday) {
    const labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }

  String _dateLabel(DateTime day) {
    return '${day.month}/${day.day}';
  }

  List<_SlotSpec> _buildVisibleSlots(
    List<TimelineItem> weekDeadlines, {
    required Iterable<TimetableMeeting> meetings,
  }) {
    final latestDeadlineMinutes = weekDeadlines.fold<int>(
      _slots.last.endMinutes,
      (currentLatest, item) {
        final due = item.sortTime == null
            ? null
            : toBnbuCampusClock(item.sortTime!);
        if (due == null) {
          return currentLatest;
        }
        return due.hour * 60 + due.minute > currentLatest
            ? due.hour * 60 + due.minute
            : currentLatest;
      },
    );
    final latestMeetingMinutes = meetings.fold<int>(
      _slots.last.endMinutes,
      (currentLatest, entry) =>
          entry.endMinutes > currentLatest ? entry.endMinutes : currentLatest,
    );
    final latestVisibleMinutes = latestDeadlineMinutes > latestMeetingMinutes
        ? latestDeadlineMinutes
        : latestMeetingMinutes;

    final earliest = meetings.fold<int>(
      480,
      (value, entry) => math.min(value, entry.startMinutes),
    );
    final visibleSlots = <_SlotSpec>[
      for (var minute = (earliest ~/ 60) * 60; minute < 480; minute += 60)
        _SlotSpec(
          '${_formatMinutes(minute)} - ${_formatMinutes(minute + 60)}',
          minute,
          minute + 60,
        ),
      ..._slots,
    ];
    var nextStart = _slots.last.startMinutes + 60;
    while (nextStart < latestVisibleMinutes) {
      final nextEnd = nextStart + 60;
      visibleSlots.add(
        _SlotSpec(
          '${_formatMinutes(nextStart)} - ${_formatMinutes(nextEnd)}',
          nextStart,
          nextEnd,
        ),
      );
      nextStart += 60;
    }
    return visibleSlots;
  }

  _HeaderTone _headerTone(
    BuildContext context, {
    required bool hasCourses,
    required bool hasDeadlines,
  }) {
    final tokens = context.bnbuTheme;
    if (hasCourses && hasDeadlines) {
      final titleColor = Color.lerp(tokens.brandBlue, tokens.danger, 0.44)!;
      return _HeaderTone(
        background: Color.lerp(
          tokens.infoContainer,
          tokens.dangerContainer,
          0.36,
        )!,
        border: titleColor.withValues(alpha: 0.24),
        titleColor: titleColor,
        subtitleColor: Color.lerp(titleColor, tokens.textSecondary, 0.32)!,
      );
    }
    if (hasDeadlines) {
      return _HeaderTone(
        background: tokens.dangerContainer,
        border: tokens.danger.withValues(alpha: 0.24),
        titleColor: tokens.danger,
        subtitleColor: Color.lerp(tokens.danger, tokens.textSecondary, 0.36)!,
      );
    }
    if (hasCourses) {
      return _HeaderTone(
        background: tokens.infoContainer,
        border: tokens.brandBlue.withValues(alpha: 0.22),
        titleColor: tokens.brandBlue,
        subtitleColor: Color.lerp(
          tokens.brandBlue,
          tokens.textSecondary,
          0.36,
        )!,
      );
    }
    return _HeaderTone(
      background: Colors.transparent,
      border: tokens.border,
      titleColor: tokens.textPrimary,
      subtitleColor: tokens.textMuted,
    );
  }

  _TodayHighlightTone? _todayHighlightTone(BuildContext context) {
    final controller = BnbuLiquidGlassScope.maybeControllerOf(context);
    if (controller?.scheduleTodayHighlightEnabled == false) {
      return null;
    }
    final accent = controller?.scheduleTodayAccent ?? ScheduleTodayAccent.blue;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = switch (accent) {
      ScheduleTodayAccent.blue =>
        dark ? const Color(0xFF78B9FF) : const Color(0xFF075EA8),
      ScheduleTodayAccent.teal =>
        dark ? const Color(0xFF65D7C4) : const Color(0xFF087A6A),
      ScheduleTodayAccent.amber =>
        dark ? const Color(0xFFFFC85A) : const Color(0xFF8A5700),
      ScheduleTodayAccent.violet =>
        dark ? const Color(0xFFC2A3FF) : const Color(0xFF6741B0),
    };
    final background = switch (accent) {
      ScheduleTodayAccent.blue =>
        dark ? const Color(0xFF102D47) : const Color(0xFFE4F2FF),
      ScheduleTodayAccent.teal =>
        dark ? const Color(0xFF113630) : const Color(0xFFE1F7F2),
      ScheduleTodayAccent.amber =>
        dark ? const Color(0xFF3A2B0E) : const Color(0xFFFFF2CE),
      ScheduleTodayAccent.violet =>
        dark ? const Color(0xFF2B2042) : const Color(0xFFF0E8FF),
    };
    return _TodayHighlightTone(
      foreground: foreground,
      background: background.withValues(alpha: dark ? 0.82 : 0.9),
      border: foreground.withValues(alpha: dark ? 0.7 : 0.5),
    );
  }

  _CurrentTimeMarker? _buildCurrentTimeMarker(
    List<DateTime> visibleDays, {
    required ScheduleGridGeometry geometry,
    required DateTime weekStart,
    required Map<int, int> dayIndexByWeekday,
    required List<_SlotSpec> visibleSlots,
    required double rowHeight,
    required double markerSize,
  }) {
    if (!_isSameDate(weekStart, _startOfWeek(_currentTime))) {
      return null;
    }
    final dayIndex = dayIndexByWeekday[_currentTime.weekday];
    if (dayIndex == null || visibleDays.isEmpty) {
      return null;
    }
    final minutes = _currentTime.hour * 60 + _currentTime.minute;
    if (minutes < 8 * 60) return null;
    final top = geometry.offsetFor(minutes.toDouble()) - markerSize / 2;
    final maxTop = geometry.height - markerSize;
    return _CurrentTimeMarker(
      dayIndex: dayIndex,
      top: top.clamp(0.0, maxTop).toDouble(),
      size: markerSize,
      minutes: minutes,
    );
  }

  TextPainter _textPainter({
    required BuildContext context,
    required String text,
    required TextStyle? style,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter;
  }

  String _formatMinutes(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hour = safeMinutes ~/ 60;
    final minute = safeMinutes % 60;
    final minuteLabel = minute.toString().padLeft(2, '0');
    return '$hour:$minuteLabel';
  }

  String _deadlineLabel(TimelineItem item) {
    if (item.sortTime != null) {
      return context.l10n.formatMonthDayTime(item.sortTime!.toLocal());
    }
    if (item.formattedTime.isNotEmpty) {
      return item.formattedTime;
    }
    return item.courseName.isEmpty ? '无时间信息' : item.courseName;
  }

  String _taCourseRepeatLabel(TaCourseEntry entry) {
    if (entry.repeatType == TaCourseRepeatType.weekly) {
      return entry.activeWeekStarts == null
          ? '每周重复'
          : '已选 ${entry.activeWeekStarts!.length} 周';
    }
    final weekStart = entry.weekStart;
    if (weekStart == null) {
      return '单独一周';
    }
    return '${context.l10n.formatMonthDay(weekStart)} 所在周';
  }

  Color _deadlineAccentColor(TimelineItem item, BnbuThemeExtension tokens) {
    return item.isOverdue
        ? tokens.danger
        : Color.lerp(tokens.danger, tokens.warning, 0.18)!;
  }
}

class _ScheduleHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ScheduleHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _ScheduleHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _SlotSpec {
  const _SlotSpec(this.label, this.startMinutes, this.endMinutes);

  final String label;
  final int startMinutes;
  final int endMinutes;

  String get startLabel => _format(startMinutes);

  String get endLabel => _format(endMinutes);

  static String _format(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hour = safeMinutes ~/ 60;
    final minute = safeMinutes % 60;
    return '$hour:${minute.toString().padLeft(2, '0')}';
  }
}

class _MeetingBlock {
  const _MeetingBlock({
    required this.color,
    required this.course,
    required this.meeting,
    required this.taCourse,
  });

  final Color color;
  final TimetableCourse course;
  final TimetableMeeting meeting;
  final TaCourseEntry? taCourse;
}

class _CurrentTimeMarker {
  const _CurrentTimeMarker({
    required this.dayIndex,
    required this.top,
    required this.size,
    required this.minutes,
  });

  final int dayIndex;
  final double top;
  final double size;
  final int minutes;
}

class _DeadlineBlock {
  const _DeadlineBlock({
    required this.item,
    required this.dayIndex,
    required this.top,
    required this.height,
  });

  final TimelineItem item;
  final int dayIndex;
  final double top;
  final double height;
}

class _HeaderTone {
  const _HeaderTone({
    required this.background,
    required this.border,
    required this.titleColor,
    required this.subtitleColor,
  });

  final Color background;
  final Color border;
  final Color titleColor;
  final Color subtitleColor;
}

class _TodayHighlightTone {
  const _TodayHighlightTone({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}
