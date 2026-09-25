import '../state/account_habits.dart';
import 'web_mirror_page.dart';
import 'ispace_course_module_navigation.dart';
import '../widgets/bnbu_menu.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/bnbu_loading.dart';
import '../widgets/ispace_course_workspace.dart';
import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../state/course_display_preferences_controller.dart';
import '../widgets/course_display_editor.dart';
import '../models/timeline_item.dart';
import '../state/app_session_controller.dart';
import '../state/root_shell_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/timeline_summary_card.dart';
import 'timeline_detail_page.dart';

enum TimelineDateFilter {
  all,
  overdue,
  next7Days,
  next30Days,
  next3Months,
  next6Months,
}

enum TimelineSortMode { byDates, byCourses }

enum IspaceSection {
  dashboard,
  sitePagesMyCourses,
  sitePagesBlogs,
  sitePagesBadges,
  sitePagesTags,
  sitePagesAnnouncements,
  myCourses,
}

class IspacePage extends StatefulWidget {
  const IspacePage({
    super.key,
    required this.controller,
    required this.onGoToUserTab,
    this.shellController,
    this.onCanPopChanged,
    this.courseDisplayPreferences,
  });

  final AppSessionController controller;
  final VoidCallback onGoToUserTab;
  final RootShellController? shellController;
  final ValueChanged<bool>? onCanPopChanged;
  final CourseDisplayPreferencesController? courseDisplayPreferences;

  @override
  State<IspacePage> createState() => _IspacePageState();
}

class _IspacePageState extends State<IspacePage> with WidgetsBindingObserver {
  static const String _dateFilterPreferenceKey = 'ispace.dashboard.date_filter';
  static const String _sortModePreferenceKey = 'ispace.dashboard.sort_mode';
  late final Future<SharedPreferences> _preferencesFuture;
  late final _courseDisplay =
      widget.courseDisplayPreferences ?? CourseDisplayPreferencesController();
  Timer? _courseSyncTimer;

  IspaceSection _section = IspaceSection.dashboard;
  TimelineDateFilter _dateFilter = TimelineDateFilter.all;
  TimelineSortMode _sortMode = TimelineSortMode.byDates;
  bool _sitePagesExpanded = false;
  bool _coursesExpanded = true;
  bool _navigationExpanded = true;
  final _contentNavigator = GlobalKey<NavigatorState>();
  late final _contentObserver = _IspaceRouteObserver(_reportNavigation);
  bool _canPop = false;
  bool _hasPopup = false;
  bool _drawerOpen = false;

  void _reportNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = _contentObserver.hasPageAboveRoot;
      final popup = _contentObserver.hasPopup;
      final changed = next != _canPop;
      if (changed || popup != _hasPopup) {
        setState(() {
          _canPop = next;
          _hasPopup = popup;
        });
        if (changed) widget.onCanPopChanged?.call(next);
      }
    });
  }

  void _resetDetailNavigation() => _contentNavigator.currentState?.popUntil(
    (route) => route.isFirst || route.settings.name == 'ispace-section',
  );
  BuildContext get _navigationContext =>
      _contentNavigator.currentState?.overlay?.context ?? context;

  String? _courseOwner;
  CourseSummary? _activeCourse;
  bool _isLoadingActiveCourse = false;
  String? _activeCourseError;
  List<CourseContentSection> _activeCourseSections = const [];
  final Map<IspaceSection, int> _webMirrorReloadSeeds = <IspaceSection, int>{};

  @override
  void initState() {
    super.initState();
    _preferencesFuture = SharedPreferences.getInstance();
    AccountHabits.shared.addListener(_habitChanged);
    _courseOwner = widget.controller.username;
    widget.controller.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_courseDisplay.bind(widget.controller.username));
    _startCourseSync();
    unawaited(_restoreDashboardPreferences());
  }

  void _onSessionChanged() {
    if (_courseOwner == widget.controller.username) return;
    _courseOwner = widget.controller.username;
    unawaited(_courseDisplay.bind(_courseOwner));
    _resetDetailNavigation();
    if (mounted) {
      setState(() {
        _activeCourse = null;
        _activeCourseSections = const [];
        _activeCourseError = null;
        _isLoadingActiveCourse = false;
      });
    }
  }

  @override
  void dispose() {
    AccountHabits.shared.removeListener(_habitChanged);
    _courseSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.courseDisplayPreferences == null) _courseDisplay.dispose();
    widget.controller.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _startCourseSync() {
    _courseSyncTimer?.cancel();
    _courseSyncTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_courseDisplay.synchronize()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startCourseSync();
      unawaited(_courseDisplay.synchronize());
    } else {
      _courseSyncTimer?.cancel();
    }
  }

  Future<void> _manageCourses() => showCourseDisplayEditor(
    context,
    controller: _courseDisplay,
    courses: widget.controller.courses,
  );

  @override
  Widget build(BuildContext context) {
    return BnbuLoadingRegion(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.controller,
          widget.shellController,
          _courseDisplay,
        ]),
        builder: (context, _) {
          final tokens = context.bnbuTheme;
          return LayoutBuilder(
            builder: (context, constraints) {
              final supportsPersistentNavigation =
                  constraints.maxWidth >= BnbuBreakpoints.tabletWorkspace;
              final hasPersistentNavigation =
                  supportsPersistentNavigation && _navigationExpanded;
              final isWideLayout =
                  BnbuBreakpoints.fromWidth(constraints.maxWidth) !=
                  BnbuWindowClass.compact;
              final content = widget.controller.isLoggedIn
                  ? _buildLoggedInBody(
                      context,
                      showTimelineNavigationButton: true,
                      showDesktopTimelineRefresh:
                          isWideLayout && !hasPersistentNavigation,
                      useDesktopTopBar: supportsPersistentNavigation,
                    )
                  : _buildNeedLogin(context);
              final workspace = Column(
                children: [
                  if (_section != IspaceSection.dashboard ||
                      !widget.controller.isLoggedIn)
                    SafeArea(
                      bottom: false,
                      child: BnbuSecondaryHeader(
                        key: const ValueKey('ispace-section-header'),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: BnbuHeaderMetrics.height,
                          ),
                          child: Row(
                            children: [
                              if (!supportsPersistentNavigation &&
                                  _section != IspaceSection.dashboard)
                                IconButton(
                                  key: const ValueKey('ispace-section-back'),
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  tooltip: MaterialLocalizations.of(
                                    context,
                                  ).backButtonTooltip,
                                  icon: const Icon(LucideIcons.chevronLeft300),
                                  onPressed: () => _contentNavigator
                                      .currentState
                                      ?.maybePop(),
                                ),
                              _buildNavigationButton(
                                context,
                                persistentLayout: supportsPersistentNavigation,
                              ),
                              if (_section == IspaceSection.myCourses ||
                                  _section == IspaceSection.sitePagesMyCourses)
                                Expanded(
                                  child: BnbuText(
                                    '课程',
                                    style: BnbuHeaderMetrics.titleStyle
                                        .copyWith(color: tokens.textPrimary),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _section == IspaceSection.dashboard
                        ? content
                        : MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            child: content,
                          ),
                  ),
                ],
              );
              final contentNavigation = NavigatorPopHandler<Object?>(
                enabled:
                    !_drawerOpen &&
                    (widget.shellController == null ||
                        widget.shellController!.selectedTab == AppTab.ispace),
                onPopWithResult: (_) =>
                    _contentNavigator.currentState?.maybePop(),
                child: Navigator(
                  key: _contentNavigator,
                  observers: [_contentObserver],
                  pages: [
                    MaterialPage<void>(
                      key: const ValueKey('ispace-workspace-root'),
                      child: Material(
                        color: tokens.canvas,
                        child: _section == IspaceSection.dashboard
                            ? workspace
                            : Column(
                                children: [
                                  Expanded(
                                    child: _buildDashboardBody(
                                      context,
                                      showNavigationButton: true,
                                      showDesktopRefresh:
                                          isWideLayout &&
                                          !hasPersistentNavigation,
                                      useDesktopTopBar:
                                          supportsPersistentNavigation,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (_section != IspaceSection.dashboard)
                      MaterialPage<void>(
                        key: const ValueKey('ispace-section'),
                        name: 'ispace-section',
                        child: Material(color: tokens.canvas, child: workspace),
                      ),
                  ],
                  onDidRemovePage: (page) {
                    if (page.key == const ValueKey('ispace-section') &&
                        _section != IspaceSection.dashboard &&
                        mounted) {
                      setState(() {
                        _section = IspaceSection.dashboard;
                        _activeCourse = null;
                        _activeCourseSections = const [];
                      });
                    }
                  },
                ),
              );
              return Scaffold(
                backgroundColor: tokens.canvas,
                drawer: supportsPersistentNavigation
                    ? null
                    : _buildDrawer(context),
                drawerEnableOpenDragGesture:
                    _section == IspaceSection.dashboard &&
                    !_canPop &&
                    !_hasPopup,
                onDrawerChanged: (open) => setState(() => _drawerOpen = open),
                body: hasPersistentNavigation
                    ? Row(
                        children: [
                          SizedBox(
                            key: const ValueKey(
                              'ispace-desktop-navigation-pane',
                            ),
                            width: 240,
                            child: Material(
                              color: tokens.surface.withValues(alpha: 0.86),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(color: tokens.border),
                                  ),
                                ),
                                child: SafeArea(
                                  bottom: false,
                                  child: _buildIspaceNavigation(
                                    context,
                                    closeDrawer: false,
                                    showRefresh: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(child: contentNavigation),
                        ],
                      )
                    : contentNavigation,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNeedLogin(BuildContext context) {
    final tokens = context.bnbuTheme;
    return SafeArea(
      minimum: EdgeInsets.all(tokens.space16),
      child: Center(
        child: BnbuEmptyState(
          title: '请先登录 iSpace',
          action: FilledButton(
            onPressed: widget.onGoToUserTab,
            child: const BnbuText('去我的登录'),
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedInBody(
    BuildContext context, {
    required bool showTimelineNavigationButton,
    required bool showDesktopTimelineRefresh,
    required bool useDesktopTopBar,
  }) {
    switch (_section) {
      case IspaceSection.dashboard:
        return _buildDashboardBody(
          context,
          showNavigationButton: showTimelineNavigationButton,
          showDesktopRefresh: showDesktopTimelineRefresh,
          useDesktopTopBar: useDesktopTopBar,
        );
      case IspaceSection.sitePagesMyCourses:
        return _buildSitePagesMyCoursesBody(context);
      case IspaceSection.sitePagesBlogs:
        return _buildSitePagesWebMirrorBody(
          context,
          pathOrUrl: '/blog/index.php',
        );
      case IspaceSection.sitePagesBadges:
        return _buildSitePagesWebMirrorBody(
          context,
          pathOrUrl: '/badges/view.php?type=1',
        );
      case IspaceSection.sitePagesTags:
        return _buildSitePagesWebMirrorBody(
          context,
          pathOrUrl: '/tag/search.php',
        );
      case IspaceSection.sitePagesAnnouncements:
        return _buildSiteAnnouncementsBody(context);
      case IspaceSection.myCourses:
        return _buildCoursesBody(context);
    }
  }

  Widget _buildDashboardBody(
    BuildContext context, {
    required bool showNavigationButton,
    required bool showDesktopRefresh,
    required bool useDesktopTopBar,
  }) {
    final tokens = context.bnbuTheme;
    final filtered = _filteredTimeline(widget.controller.timelineItems);
    final entries = _sortMode == TimelineSortMode.byCourses
        ? _buildCourseEntries(filtered)
        : _buildDateEntries(filtered);

    return Column(
      children: [
        SafeArea(
          bottom: false,
          minimum: EdgeInsets.fromLTRB(
            0,
            useDesktopTopBar ? 0 : BnbuTopBarMetrics.compactTopInset,
            useDesktopTopBar ? 0 : tokens.space16,
            0,
          ),
          child: Column(
            children: [
              _buildControlPanel(
                context,
                showNavigationButton: showNavigationButton,
                showDesktopRefresh: showDesktopRefresh,
                useDesktopStyle: useDesktopTopBar,
              ),
              if (widget.controller.error != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.only(
                    left: useDesktopTopBar ? 0 : tokens.space16,
                  ),
                  child: _buildErrorBox(context, widget.controller.error!),
                ),
              ],
              Padding(
                padding: EdgeInsets.only(
                  left: useDesktopTopBar ? 0 : tokens.space16,
                ),
                child: BnbuUpdateProgress(
                  active:
                      widget.controller.isLoadingTimeline && entries.isNotEmpty,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: BnbuRefreshIndicator(
            onRefresh: widget.controller.refreshTimeline,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  sliver: entries.isEmpty
                      ? SliverToBoxAdapter(
                          child: widget.controller.isLoadingTimeline
                              ? const Padding(
                                  padding: EdgeInsets.all(48),
                                  child: BnbuInitialLoading(),
                                )
                              : _buildEmptyState(context),
                        )
                      : SliverList.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry is _TimelineHeader) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 4,
                                ),
                                child: BnbuSectionHeader(title: entry.title),
                              );
                            }
                            final item = (entry as _TimelineEvent).item;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildTimelineCard(context, item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoursesBody(
    BuildContext context, {
    String heroTitle = '我的课程',
    String? heroSubtitle,
  }) {
    final activeCourse = _activeCourse;
    if (activeCourse != null) {
      return _buildActiveCourseBody(
        context,
        course: activeCourse,
        parentTitle: heroTitle,
      );
    }

    final courses = _courseDisplay.value.arrange(widget.controller.courses);
    return BnbuRefreshIndicator(
      key: const ValueKey('ispace-my-courses-content'),
      onRefresh: widget.controller.refreshCourses,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: BnbuText(
                  heroTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _courseDisplay.ready ? _manageCourses : null,
                child: const BnbuText('管理课程'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BnbuUpdateProgress(
            active: widget.controller.isLoadingCourses && courses.isNotEmpty,
          ),
          if (widget.controller.error != null) ...[
            const SizedBox(height: 12),
            _buildErrorBox(context, widget.controller.error!),
          ],
          const SizedBox(height: 12),
          if (courses.isEmpty)
            widget.controller.isLoadingCourses
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: BnbuInitialLoading(),
                  )
                : _buildEmptyState(
                    context,
                    title: '暂无课程数据',
                    subtitle: '下拉刷新或稍后重试',
                  )
          else
            for (var index = 0; index < courses.length; index++)
              Material(
                color: courseStripeColor(context, index),
                child: _buildCourseCard(context, courses[index]),
              ),
        ],
      ),
    );
  }

  Widget _buildSitePagesMyCoursesBody(BuildContext context) {
    return _buildCoursesBody(
      context,
      heroTitle: '站点课程',
      heroSubtitle: '与 iSpace 站点课程保持一致',
    );
  }

  Widget _buildSitePagesWebMirrorBody(
    BuildContext context, {
    required String pathOrUrl,
  }) {
    final section = _section;
    final reloadSeed = _webMirrorReloadSeeds[section] ?? 0;
    return SafeArea(
      bottom: false,
      child: MirrorWebViewPanel(
        key: ValueKey('$section#$reloadSeed'),
        controller: widget.controller,
        pathOrUrl: pathOrUrl,
      ),
    );
  }

  Widget _buildSiteAnnouncementsBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => _openSiteAnnouncementForum(context),
          icon: const Icon(LucideIcons.messagesSquare300),
          label: const BnbuText('打开论坛详情'),
        ),
      ],
    );
  }

  Widget _buildNavigationButton(
    BuildContext context, {
    required bool persistentLayout,
  }) => Builder(
    builder: (scaffoldContext) => IconButton(
      key: const ValueKey('ispace-top-bar-navigation-button'),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: () {
        if (persistentLayout) {
          setState(() => _navigationExpanded = !_navigationExpanded);
        } else {
          Scaffold.of(scaffoldContext).openDrawer();
        }
      },
      tooltip: context.l10n.text('iSpace 导航'),
      icon: const Icon(LucideIcons.menu300, size: BnbuTopBarMetrics.iconSize),
    ),
  );

  Widget _buildControlPanel(
    BuildContext context, {
    required bool showNavigationButton,
    required bool showDesktopRefresh,
    required bool useDesktopStyle,
  }) {
    final tokens = context.bnbuTheme;
    final navigationButton = _buildNavigationButton(
      context,
      persistentLayout: useDesktopStyle,
    );
    final leadingInset =
        tokens.space16 -
        (BnbuTopBarMetrics.controlExtent - BnbuTopBarMetrics.iconSize) / 2;
    // Reserve the old filter position while keeping the whole navigation
    // target inside its parent, including taps along its left edge.
    final navigationGap =
        tokens.space4 +
        (useDesktopStyle ? tokens.space12 : tokens.space16 + tokens.space8) -
        leadingInset;
    final controls = SizedBox(
      height: BnbuTopBarMetrics.controlExtent,
      child: Row(
        children: [
          if (showNavigationButton) ...[
            navigationButton,
            SizedBox(width: navigationGap),
          ],
          Expanded(child: _buildFilterSelector(context)),
          SizedBox(width: tokens.space8),
          Expanded(child: _buildSortSelector(context)),
          if (showDesktopRefresh) ...[
            SizedBox(width: tokens.space8),
            IconButton(
              key: const ValueKey('ispace-workspace-refresh'),
              onPressed: widget.controller.isBusy
                  ? null
                  : widget.controller.refreshTimeline,
              tooltip: context.l10n.text('刷新'),
              icon: const Icon(
                LucideIcons.refreshCw300,
                size: BnbuTopBarMetrics.iconSize,
              ),
            ),
          ],
        ],
      ),
    );
    if (useDesktopStyle) {
      return DecoratedBox(
        key: const ValueKey('ispace-desktop-top-bar'),
        decoration: BoxDecoration(
          color: tokens.surface.withValues(alpha: 0.82),
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(leadingInset, 0, tokens.space16, 0),
          child: controls,
        ),
      );
    }
    return Padding(
      key: const ValueKey('ispace-compact-top-bar'),
      padding: EdgeInsets.fromLTRB(
        leadingInset,
        tokens.space8,
        tokens.space8,
        tokens.space8,
      ),
      child: controls,
    );
  }

  Widget _buildFilterSelector(BuildContext context) {
    return BnbuMenuButton<TimelineDateFilter>(
      key: const ValueKey('ispace-timeline-filter-control'),
      initialValue: _dateFilter,
      onSelected: _updateDateFilter,
      itemBuilder: (context) => TimelineDateFilter.values
          .map(
            (item) => PopupMenuItem<TimelineDateFilter>(
              value: item,
              child: BnbuText(_dateFilterLabel(item)),
            ),
          )
          .toList(),
      child: _selectorChip(
        context: context,
        icon: LucideIcons.funnel300,
        text: _dateFilterLabel(_dateFilter),
      ),
    );
  }

  Widget _buildSortSelector(BuildContext context) {
    return BnbuMenuButton<TimelineSortMode>(
      key: const ValueKey('ispace-timeline-sort-control'),
      initialValue: _sortMode,
      onSelected: _updateSortMode,
      itemBuilder: (context) => TimelineSortMode.values
          .map(
            (item) => PopupMenuItem<TimelineSortMode>(
              value: item,
              child: BnbuText(_sortModeLabel(item)),
            ),
          )
          .toList(),
      child: _selectorChip(
        context: context,
        icon: LucideIcons.arrowUpDown300,
        text: _sortModeLabel(_sortMode),
      ),
    );
  }

  Widget _selectorChip({
    required BuildContext context,
    required IconData icon,
    required String text,
  }) {
    final tokens = context.bnbuTheme;
    return Container(
      constraints: BoxConstraints(minHeight: tokens.minInteractiveDimension),
      padding: EdgeInsets.symmetric(horizontal: tokens.space12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.brandBlue),
          SizedBox(width: tokens.space8),
          Expanded(
            child: BnbuText(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: tokens.textPrimary),
            ),
          ),
          Icon(LucideIcons.chevronDown300, size: 18, color: tokens.textMuted),
        ],
      ),
    );
  }

  Widget _buildCourseCard(BuildContext context, CourseSummary course) {
    final tokens = context.bnbuTheme;
    return ListTile(
      key: ValueKey('ispace-course-${course.id}'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      onTap: () => _openCourseInline(course),
      title: BnbuText(
        _courseDisplay.value.label(course),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
      subtitle: course.shortName.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: BnbuText(course.shortName),
            ),
      trailing: Icon(
        LucideIcons.chevronRight300,
        size: 18,
        color: tokens.textMuted,
      ),
    );
  }

  Widget _buildActiveCourseBody(
    BuildContext context, {
    required CourseSummary course,
    required String parentTitle,
  }) => IspaceCourseWorkspace(
    key: ValueKey('ispace-course-workspace-${course.id}'),
    course: course,
    sections: _activeCourseSections,
    controller: widget.controller,
    loading: _isLoadingActiveCourse,
    error: _activeCourseError,
    onRefresh: _reloadActiveCourse,
    onOpenModule: (module) => _openCourseModule(context, course, module),
  );

  Widget _buildErrorBox(BuildContext context, String message) {
    return BnbuNotice(message: message, kind: BnbuStatusKind.danger);
  }

  Widget _buildEmptyState(
    BuildContext context, {
    String title = '暂无进行中的课程',
    String subtitle = '当前筛选条件下没有数据',
  }) {
    return BnbuEmptyState(title: title, message: subtitle);
  }

  Widget _buildTimelineCard(BuildContext context, TimelineItem item) {
    final tokens = context.bnbuTheme;
    final now = DateTime.now();
    final dueHint = _timelineDueHint(item, now: now);
    return BnbuTimelineSummaryCard(
      key: ValueKey('ispace-timeline-card-${item.id}'),
      item: item,
      deadlineLabel: item.displayTime(context.l10n.dateTimeFormatter()),
      statusLabel: dueHint,
      accentColor: timelineSummaryAccentColor(item, tokens, now: now),
      onTap: () => _openTimelineDetail(context, item),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Drawer(
      key: const ValueKey('ispace-navigation-drawer'),
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(tokens.radius24),
          bottomRight: Radius.circular(tokens.radius24),
        ),
      ),
      child: SafeArea(
        child: _buildIspaceNavigation(context, closeDrawer: true),
      ),
    );
  }

  Widget _buildIspaceNavigation(
    BuildContext context, {
    required bool closeDrawer,
    bool showRefresh = false,
  }) {
    final courses = _courseDisplay.value.arrange(widget.controller.courses);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (closeDrawer) SizedBox(height: context.bnbuTheme.space8),
        KeyedSubtree(
          key: const ValueKey('ispace-timeline-navigation-item'),
          child: _drawerLevel1Tile(
            context,
            title: '待办',
            trailing: showRefresh
                ? IconButton(
                    key: const ValueKey('ispace-workspace-refresh'),
                    tooltip: context.l10n.text('刷新'),
                    onPressed: _refreshCurrentSection,
                    icon: const Icon(LucideIcons.refreshCw300, size: 18),
                  )
                : null,
            icon: LucideIcons.layoutDashboard300,
            selected: _section == IspaceSection.dashboard,
            onTap: () => _setSection(
              context,
              IspaceSection.dashboard,
              closeDrawer: closeDrawer,
            ),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('ispace-courses-navigation-group'),
            shape: const Border(),
            collapsedShape: const Border(),
            initiallyExpanded: _coursesExpanded,
            onExpansionChanged: (value) {
              setState(() => _coursesExpanded = value);
            },
            tilePadding: const EdgeInsets.only(left: 16, right: 12),
            leading: const Icon(LucideIcons.bookOpen300, size: 20),
            title: const BnbuText('课程'),
            childrenPadding: const EdgeInsets.only(bottom: 4),
            children: [
              ListTile(
                key: const ValueKey('ispace-manage-courses'),
                contentPadding: const EdgeInsets.only(left: 24, right: 12),
                title: const BnbuText('管理课程', style: TextStyle(fontSize: 14)),
                subtitle: _courseDisplay.localSaveFailed
                    ? const BnbuText('本机保存失败，请重试')
                    : _courseDisplay.hasPending
                    ? const BnbuText('已保存在本机，等待同步')
                    : _courseDisplay.syncUnavailable
                    ? const BnbuText('暂时无法同步')
                    : null,
                trailing: const Icon(
                  LucideIcons.slidersHorizontal300,
                  size: 18,
                ),
                onTap: !_courseDisplay.ready
                    ? null
                    : () async {
                        if (closeDrawer) Navigator.of(context).pop();
                        await _manageCourses();
                        unawaited(_courseDisplay.synchronize());
                      },
              ),
              for (var index = 0; index < courses.length; index++)
                Material(
                  key: ValueKey(
                    'ispace-navigation-course-${courses[index].id}',
                  ),
                  color: courseStripeColor(context, index),
                  child: _drawerLeafTile(
                    context,
                    title: _courseDisplay.value.label(
                      courses[index],
                      short: true,
                    ),
                    level: 2,
                    selected:
                        _section == IspaceSection.myCourses &&
                        _activeCourse?.id == courses[index].id,
                    onTap: () => _openCourseInline(
                      courses[index],
                      closeDrawer: closeDrawer,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            initiallyExpanded: _sitePagesExpanded,
            onExpansionChanged: (value) {
              setState(() {
                _sitePagesExpanded = value;
              });
            },
            tilePadding: const EdgeInsets.only(left: 16, right: 12),
            leading: const Icon(LucideIcons.globe300, size: 20),
            title: const BnbuText('更多'),
            childrenPadding: const EdgeInsets.only(bottom: 4),
            children: [
              _drawerLeafTile(
                context,
                title: '站点博客',
                level: 2,
                selected: _section == IspaceSection.sitePagesBlogs,
                onTap: () => _setSection(
                  context,
                  IspaceSection.sitePagesBlogs,
                  closeDrawer: closeDrawer,
                ),
              ),
              _drawerLeafTile(
                context,
                title: '站点徽章',
                level: 2,
                selected: _section == IspaceSection.sitePagesBadges,
                onTap: () => _setSection(
                  context,
                  IspaceSection.sitePagesBadges,
                  closeDrawer: closeDrawer,
                ),
              ),
              _drawerLeafTile(
                context,
                title: '标签',
                level: 2,
                selected: _section == IspaceSection.sitePagesTags,
                onTap: () => _setSection(
                  context,
                  IspaceSection.sitePagesTags,
                  closeDrawer: closeDrawer,
                ),
              ),
              _drawerLeafTile(
                context,
                title: '站点公告',
                level: 2,
                selected: _section == IspaceSection.sitePagesAnnouncements,
                onTap: () => _setSection(
                  context,
                  IspaceSection.sitePagesAnnouncements,
                  closeDrawer: closeDrawer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _drawerLevel1Tile(
    BuildContext context, {
    required String title,
    required IconData icon,
    Widget? trailing,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final tokens = context.bnbuTheme;
    return ListTile(
      minTileHeight: tokens.minInteractiveDimension,
      trailing: trailing,
      leading: Icon(icon, size: 20, color: selected ? tokens.brandBlue : null),
      selected: selected,
      selectedTileColor: tokens.surfaceMuted,
      title: BnbuText(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }

  Widget _drawerLeafTile(
    BuildContext context, {
    required String title,
    required int level,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final tokens = context.bnbuTheme;
    final leftPadding = level <= 2 ? tokens.space24 : tokens.space32;
    return ListTile(
      minTileHeight: tokens.minInteractiveDimension,
      dense: true,
      contentPadding: EdgeInsets.only(left: leftPadding, right: tokens.space12),
      selected: selected,
      selectedTileColor: tokens.surfaceMuted,
      title: BnbuText(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }

  void _setSection(
    BuildContext context,
    IspaceSection section, {
    required bool closeDrawer,
  }) {
    if (closeDrawer) {
      Navigator.of(context).pop();
    }
    _resetDetailNavigation();
    if (_section == section) {
      return;
    }
    setState(() {
      _section = section;
    });
  }

  Future<void> _openTimelineDetail(
    BuildContext context,
    TimelineItem item,
  ) async {
    await Navigator.of(_navigationContext).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TimelineDetailPage(controller: widget.controller, item: item),
      ),
    );
  }

  Future<void> _openCourseModule(
    BuildContext context,
    CourseSummary course,
    CourseModule module,
  ) => openIspaceCourseModule(
    context: _navigationContext,
    controller: widget.controller,
    course: course,
    module: module,
    sections: _activeCourseSections,
  );

  Future<void> _openSiteAnnouncementForum(BuildContext context) async {
    final pseudoItem = TimelineItem(
      id: -78,
      title: '站点公告',
      activityState: '论坛',
      activityType: 'forum',
      moduleName: 'forum',
      description: '站点新闻与公告',
      courseName: 'BNBU Information Space',
      courseId: 1,
      instanceId: 78,
      url: '${widget.controller.baseUrl}/mod/forum/view.php?id=78',
      sortTime: null,
      formattedTime: '',
      isOverdue: false,
    );
    await _openTimelineDetail(context, pseudoItem);
  }

  Future<void> _openCourseInline(
    CourseSummary course, {
    bool closeDrawer = false,
  }) async {
    if (closeDrawer) {
      Navigator.of(context).pop();
    }

    _resetDetailNavigation();
    setState(() {
      _section = IspaceSection.myCourses;
      _coursesExpanded = true;
      _activeCourse = course;
      _isLoadingActiveCourse = true;
      _activeCourseError = null;
      _activeCourseSections = const [];
    });

    await _loadActiveCourseSections(course.id);
  }

  Future<void> _loadActiveCourseSections(int courseId) async {
    final owner = _courseOwner;
    try {
      final sections = await widget.controller.loadCourseContents(courseId);
      if (!mounted) {
        return;
      }
      if (_courseOwner != owner ||
          _activeCourse == null ||
          _activeCourse!.id != courseId) {
        return;
      }
      setState(() {
        _activeCourseSections = sections;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_courseOwner != owner ||
          _activeCourse == null ||
          _activeCourse!.id != courseId) {
        return;
      }
      setState(() {
        _activeCourseError = '课程内容加载失败，请稍后重试。';
      });
    } finally {
      if (mounted &&
          _courseOwner == owner &&
          _activeCourse != null &&
          _activeCourse!.id == courseId) {
        setState(() {
          _isLoadingActiveCourse = false;
        });
      }
    }
  }

  Future<void> _reloadActiveCourse() async {
    final active = _activeCourse;
    if (active == null) {
      await widget.controller.refreshCourses();
      return;
    }
    setState(() {
      _isLoadingActiveCourse = true;
      _activeCourseError = null;
    });
    await _loadActiveCourseSections(active.id);
  }

  void _reloadMirrorSection(IspaceSection section) {
    setState(() {
      final current = _webMirrorReloadSeeds[section] ?? 0;
      _webMirrorReloadSeeds[section] = current + 1;
    });
  }

  void _refreshCurrentSection() {
    switch (_section) {
      case IspaceSection.dashboard:
        widget.controller.refreshTimeline();
        return;
      case IspaceSection.sitePagesMyCourses:
        _reloadActiveCourse();
        return;
      case IspaceSection.sitePagesBlogs:
        _reloadMirrorSection(IspaceSection.sitePagesBlogs);
        return;
      case IspaceSection.sitePagesBadges:
        _reloadMirrorSection(IspaceSection.sitePagesBadges);
        return;
      case IspaceSection.sitePagesTags:
        _reloadMirrorSection(IspaceSection.sitePagesTags);
        return;
      case IspaceSection.sitePagesAnnouncements:
        return;
      case IspaceSection.myCourses:
        _reloadActiveCourse();
        return;
    }
  }

  List<TimelineItem> _filteredTimeline(List<TimelineItem> source) {
    final now = DateTime.now();
    final filtered = source
        .where((item) => _matchesDateFilter(item, now))
        .toList();

    if (_sortMode == TimelineSortMode.byCourses) {
      filtered.sort((a, b) {
        final courseCompare = _courseLabel(a).compareTo(_courseLabel(b));
        if (courseCompare != 0) {
          return courseCompare;
        }
        final aTime = a.sortTime?.millisecondsSinceEpoch ?? 0;
        final bTime = b.sortTime?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
      return filtered;
    }

    filtered.sort((a, b) {
      return _timeSortValue(a).compareTo(_timeSortValue(b));
    });
    return filtered;
  }

  bool _matchesDateFilter(TimelineItem item, DateTime now) {
    final time = item.sortTime;
    switch (_dateFilter) {
      case TimelineDateFilter.all:
        return true;
      case TimelineDateFilter.overdue:
        if (item.isOverdue) {
          return true;
        }
        if (time == null) {
          return false;
        }
        return time.isBefore(now);
      case TimelineDateFilter.next7Days:
        return _isBetween(time, now, now.add(const Duration(days: 7)));
      case TimelineDateFilter.next30Days:
        return _isBetween(time, now, now.add(const Duration(days: 30)));
      case TimelineDateFilter.next3Months:
        return _isBetween(
          time,
          now,
          DateTime(now.year, now.month + 3, now.day),
        );
      case TimelineDateFilter.next6Months:
        return _isBetween(
          time,
          now,
          DateTime(now.year, now.month + 6, now.day),
        );
    }
  }

  bool _isBetween(DateTime? target, DateTime start, DateTime end) {
    if (target == null) {
      return false;
    }
    return !target.isBefore(start) && !target.isAfter(end);
  }

  List<_TimelineEntry> _buildCourseEntries(List<TimelineItem> items) {
    final entries = <_TimelineEntry>[];
    String? currentCourse;
    for (final item in items) {
      final course = _courseLabel(item);
      if (currentCourse != course) {
        entries.add(_TimelineHeader(course));
        currentCourse = course;
      }
      entries.add(_TimelineEvent(item));
    }
    return entries;
  }

  List<_TimelineEntry> _buildDateEntries(List<TimelineItem> items) {
    final entries = <_TimelineEntry>[];
    String? currentDay;
    for (final item in items) {
      final day = _dayLabel(item.sortTime);
      if (currentDay != day) {
        entries.add(_TimelineHeader(day));
        currentDay = day;
      }
      entries.add(_TimelineEvent(item));
    }
    return entries;
  }

  String _courseLabel(TimelineItem item) {
    if (item.courseName.trim().isEmpty) {
      return '未知课程';
    }
    return item.courseName.trim();
  }

  String _dayLabel(DateTime? dateTime) {
    if (dateTime == null) {
      return '无日期';
    }
    return context.l10n.formatFullDate(dateTime.toLocal());
  }

  int _timeSortValue(TimelineItem item) {
    final millis = item.sortTime?.millisecondsSinceEpoch;
    if (millis == null || millis <= 0) {
      return 253402300799000; // 9999-12-31
    }
    return millis;
  }

  void _habitChanged() {
    if (mounted) unawaited(_restoreDashboardPreferences());
  }

  Future<void> _restoreDashboardPreferences() async {
    final preferences = await _preferencesFuture;
    final dateFilterName = AccountHabits.shared.managed
        ? AccountHabits.shared.read(_dateFilterPreferenceKey, 'all')
        : preferences.getString(_dateFilterPreferenceKey);
    final sortModeName = AccountHabits.shared.managed
        ? AccountHabits.shared.read(_sortModePreferenceKey, 'byDates')
        : preferences.getString(_sortModePreferenceKey);

    TimelineDateFilter? restoredDateFilter;
    for (final candidate in TimelineDateFilter.values) {
      if (candidate.name == dateFilterName) {
        restoredDateFilter = candidate;
        break;
      }
    }

    TimelineSortMode? restoredSortMode;
    for (final candidate in TimelineSortMode.values) {
      if (candidate.name == sortModeName) {
        restoredSortMode = candidate;
        break;
      }
    }

    if (!mounted || (restoredDateFilter == null && restoredSortMode == null)) {
      return;
    }

    setState(() {
      if (restoredDateFilter != null) {
        _dateFilter = restoredDateFilter;
      }
      if (restoredSortMode != null) {
        _sortMode = restoredSortMode;
      }
    });
  }

  Future<void> _persistDashboardPreferences() async {
    if (AccountHabits.shared.managed) return;
    final preferences = await _preferencesFuture;
    await preferences.setString(_dateFilterPreferenceKey, _dateFilter.name);
    await preferences.setString(_sortModePreferenceKey, _sortMode.name);
  }

  void _updateDateFilter(TimelineDateFilter value) {
    if (_dateFilter == value) {
      return;
    }
    setState(() => _dateFilter = value);
    unawaited(
      AccountHabits.shared
          .set(_dateFilterPreferenceKey, value.name)
          .catchError((Object _) {}),
    );
    unawaited(_persistDashboardPreferences());
  }

  void _updateSortMode(TimelineSortMode value) {
    if (_sortMode == value) {
      return;
    }
    setState(() => _sortMode = value);
    unawaited(
      AccountHabits.shared
          .set(_sortModePreferenceKey, value.name)
          .catchError((Object _) {}),
    );
    unawaited(_persistDashboardPreferences());
  }

  String _timelineDueHint(TimelineItem item, {required DateTime now}) {
    final due = item.sortTime;
    if (due == null) {
      return '无日期';
    }
    if (item.isOverdue || !due.isAfter(now)) {
      return '已逾期';
    }
    final diff = due.difference(now);
    final totalMinutes = diff.inMinutes;
    if (totalMinutes <= 0) {
      return '已逾期';
    }
    if (diff > const Duration(days: 2)) {
      final daysLeft = (totalMinutes / (24 * 60)).ceil();
      return '$daysLeft 天';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  String _dateFilterLabel(TimelineDateFilter filter) {
    switch (filter) {
      case TimelineDateFilter.all:
        return '全部';
      case TimelineDateFilter.overdue:
        return '已逾期';
      case TimelineDateFilter.next7Days:
        return '未来 7 天';
      case TimelineDateFilter.next30Days:
        return '未来 30 天';
      case TimelineDateFilter.next3Months:
        return '未来 3 个月';
      case TimelineDateFilter.next6Months:
        return '未来 6 个月';
    }
  }

  String _sortModeLabel(TimelineSortMode mode) {
    switch (mode) {
      case TimelineSortMode.byDates:
        return '按日期排序';
      case TimelineSortMode.byCourses:
        return '按课程排序';
    }
  }
}

sealed class _TimelineEntry {
  const _TimelineEntry();
}

class _TimelineHeader extends _TimelineEntry {
  const _TimelineHeader(this.title);
  final String title;
}

class _TimelineEvent extends _TimelineEntry {
  const _TimelineEvent(this.item);
  final TimelineItem item;
}

class _IspaceRouteObserver extends NavigatorObserver {
  _IspaceRouteObserver(this.changed);
  final VoidCallback changed;
  final _routes = <Route<dynamic>>[];
  bool get hasPageAboveRoot =>
      _routes.whereType<PageRoute<dynamic>>().length > 1;
  bool get hasPopup => _routes.any((route) => route is PopupRoute<dynamic>);

  // Transient menus are dismissible routes, but are not detail pages. Keep
  // system back handling in Navigator while reporting only page depth to tabs.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    changed();
  }
}
