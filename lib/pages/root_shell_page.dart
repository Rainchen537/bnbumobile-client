import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/assistant_models.dart';
import '../services/ai_assistant_service.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/home_card_visibility_service.dart';
import '../services/mail_service.dart';
import '../state/app_language_controller.dart';
import '../state/app_protection_controller.dart';
import '../state/app_session_controller.dart';
import '../state/app_theme_mode_controller.dart';
import '../state/app_update_controller.dart';
import '../state/live_activity_preference_controller.dart';
import '../state/mail_assistant_intent_controller.dart';
import '../state/mail_radar_background_coordinator.dart';
import '../state/root_shell_controller.dart';
import '../services/page_backdrop_store.dart';
import '../state/ta_course_controller.dart';
import '../theme/campus_reference_theme.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/campus_primary_navigation.dart';
import '../widgets/home_navigation_stack.dart';
import '../widgets/mail_message_row.dart';
import 'home_page.dart';
import 'ispace_page.dart';
import 'mail_page.dart';
import 'schedule_page.dart';
import 'user_page.dart';
import '../state/personal_sync_coordinator.dart';

typedef RootShellPageOverrideBuilder = Widget? Function(AppTab tab);

class RootShellPage extends StatefulWidget {
  const RootShellPage({
    super.key,
    required this.controller,
    this.appProtectionController,
    required this.shellController,
    required this.taCourseController,
    required this.mailIntentController,
    this.themeModeController,
    this.languageController,
    this.liveActivityController,
    this.appUpdateController,
    this.onDisableAssistant,
    this.onClearAssistantHistory,
    this.pageOverrideBuilder,
    this.mailRadarAssistantService,
    this.mailRadarCoordinator,
    this.mailService,
    this.homeCardVisibilityService,
    this.personalSync,
  });

  final AppSessionController controller;
  final AppProtectionController? appProtectionController;
  final RootShellController shellController;
  final TaCourseController taCourseController;
  final MailAssistantIntentController mailIntentController;
  final AppThemeModeController? themeModeController;
  final AppLanguageController? languageController;
  final LiveActivityPreferenceController? liveActivityController;
  final AppUpdateController? appUpdateController;
  final Future<void> Function()? onDisableAssistant;
  final Future<void> Function()? onClearAssistantHistory;
  final RootShellPageOverrideBuilder? pageOverrideBuilder;
  final AiAssistantService? mailRadarAssistantService;
  final MailRadarBackgroundCoordinator? mailRadarCoordinator;
  final MailService? mailService;
  final HomeCardVisibilityService? homeCardVisibilityService;
  final PersonalSyncCoordinator? personalSync;

  @override
  State<RootShellPage> createState() => _RootShellPageState();
}

class _RootShellPageState extends State<RootShellPage> {
  bool _mailSelecting = false;
  bool _homeCanPop = false;
  bool _scheduleCanPop = false;
  bool _ispaceCanPop = false;
  late final List<Widget?> _pages;
  final _pageStackKey = GlobalKey(debugLabel: 'root-page-stack');
  final _shellFocus = FocusNode(debugLabel: 'root-shortcuts');
  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;

  @override
  void initState() {
    super.initState();
    _pages = List<Widget?>.filled(AppTab.values.length, null);
    _loadPage(widget.shellController.selectedTab);
    widget.shellController.addListener(_handleShellChanged);
  }

  @override
  void didUpdateWidget(covariant RootShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shellController, widget.shellController)) {
      oldWidget.shellController.removeListener(_handleShellChanged);
      widget.shellController.addListener(_handleShellChanged);
      _loadPage(widget.shellController.selectedTab);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = AssistantContextScope.maybeOf(context);
    if (coordinator == null || identical(coordinator, _contextCoordinator)) {
      return;
    }
    _contextRegistration?.dispose();
    _contextCoordinator = coordinator;
    _contextRegistration = coordinator.register(
      AssistantContextContribution(currentPage: _currentPageContext),
    );
  }

  @override
  void dispose() {
    widget.shellController.removeListener(_handleShellChanged);
    _shellFocus.dispose();
    _contextRegistration?.dispose();
    super.dispose();
  }

  AssistantCurrentPageContext _currentPageContext() =>
      widget.shellController.currentPageContext();

  void _loadPage(AppTab tab) {
    final index = tab.index;
    if (_pages[index] != null) return;
    _pages[index] =
        widget.pageOverrideBuilder?.call(tab) ??
        switch (tab) {
          AppTab.home => HomePage(
            controller: widget.controller,
            onGoToIspace: () => _selectTab(AppTab.ispace),
            onGoToSchedule: () => _selectTab(AppTab.schedule),
            onGoToUser: () => _selectTab(AppTab.user),
            onOpenCourse: (occurrence) =>
                widget.shellController.openScheduleCourse(
                  course: occurrence.course,
                  meeting: occurrence.meeting,
                  startsAt: occurrence.startsAt,
                ),
            homeCardVisibilityService: widget.homeCardVisibilityService,
          ),
          AppTab.mail => MailPage(
            controller: widget.controller,
            assistantIntentController: widget.mailIntentController,
            radarAssistantService: widget.mailRadarAssistantService,
            radarCoordinator: widget.mailRadarCoordinator,
            mailService: widget.mailService,
          ),
          AppTab.ispace => IspacePage(
            courseDisplayPreferences: widget.personalSync?.courses,
            shellController: widget.shellController,
            onCanPopChanged: (value) {
              if (mounted) setState(() => _ispaceCanPop = value);
            },
            controller: widget.controller,
            onGoToUserTab: () => _selectTab(AppTab.user),
          ),
          AppTab.schedule => SchedulePage(
            controller: widget.controller,
            taCourseController: widget.taCourseController,
            shellController: widget.shellController,
          ),
          AppTab.user => UserPage(
            personalSync: widget.personalSync?.controller,
            controller: widget.controller,
            mailRadarCoordinator: widget.mailRadarCoordinator,
            appProtectionController: widget.appProtectionController,
            themeModeController: widget.themeModeController,
            languageController: widget.languageController,
            liveActivityController: widget.liveActivityController,
            appUpdateController: widget.appUpdateController,
            onDisableAssistant: widget.onDisableAssistant,
            onClearAssistantHistory: widget.onClearAssistantHistory,
          ),
        };
  }

  void _selectTab(AppTab tab) => widget.shellController.selectTab(tab);

  AppTab? _lastBackdropTab;
  void _handleShellChanged() {
    final tab = widget.shellController.selectedTab;
    if (_lastBackdropTab != tab) _shellFocus.requestFocus();
    if (tab == AppTab.user && _lastBackdropTab != tab) {
      unawaited(PageBackdropStore.shared.checkForUpdate());
    }
    _lastBackdropTab = tab;
    setState(() => _loadPage(widget.shellController.selectedTab));
  }

  Widget _tabNavigation(AppTab tab) {
    if ((tab == AppTab.home || tab == AppTab.schedule) &&
        _pages[tab.index] != null) {
      return HomeNavigationStack(
        key: ValueKey(
          tab == AppTab.home
              ? 'home-navigation-stack'
              : 'schedule-navigation-stack',
        ),
        active: widget.shellController.selectedTab == tab,
        onCanPopChanged: (value) {
          if (!mounted) return;
          setState(() {
            if (tab == AppTab.home) {
              _homeCanPop = value;
            } else {
              _scheduleCanPop = value;
            }
          });
        },
        child: _pages[tab.index]!,
      );
    }
    return _pages[tab.index] ?? const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    _loadPage(widget.shellController.selectedTab);
    final colors = CampusReferenceTheme.of(context);
    final pageStack = NotificationListener<MailSelectionNotification>(
      onNotification: (notification) {
        if (_mailSelecting != notification.active) {
          setState(() => _mailSelecting = notification.active);
        }
        return true;
      },
      child: IndexedStack(
        key: _pageStackKey,
        index: widget.shellController.selectedIndex,
        children: [
          for (final tab in AppTab.values)
            NavigationTabScope(
              active: widget.shellController.selectedTab == tab,
              child: _tabNavigation(tab),
            ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        for (var index = 0; index < campusNavigationTabs.length; index++) ...{
          SingleActivator(_tabShortcutKeys[index], meta: true): () =>
              widget.shellController.selectTab(campusNavigationTabs[index]),
          SingleActivator(_tabShortcutKeys[index], control: true): () =>
              widget.shellController.selectTab(campusNavigationTabs[index]),
        },
      },
      child: Focus(
        focusNode: _shellFocus,
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = BnbuBreakpoints.fromWidth(constraints.maxWidth);
            if (!windowClass.usesSideNavigation) {
              final hideNavigation =
                  (_mailSelecting &&
                      widget.shellController.selectedTab == AppTab.mail) ||
                  (_homeCanPop &&
                      widget.shellController.selectedTab == AppTab.home) ||
                  (_ispaceCanPop &&
                      widget.shellController.selectedTab == AppTab.ispace) ||
                  (_scheduleCanPop &&
                      widget.shellController.selectedTab == AppTab.schedule);
              return Scaffold(
                key: const ValueKey('root-compact-scaffold'),
                extendBody:
                    !hideNavigation &&
                    CampusPrimaryNavigation.usesLiquidGlass(context),
                backgroundColor: colors.canvas,
                body: pageStack,
                bottomNavigationBar: hideNavigation
                    ? null
                    : CampusPrimaryNavigation(
                        wide: false,
                        selectedTab: widget.shellController.selectedTab,
                        onSelected: _selectTab,
                      ),
              );
            }
            return Scaffold(
              backgroundColor: colors.canvas,
              body: SafeArea(
                bottom: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CampusPrimaryNavigation(
                      wide: true,
                      selectedTab: widget.shellController.selectedTab,
                      onSelected: _selectTab,
                    ),
                    Expanded(child: pageStack),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static const List<LogicalKeyboardKey> _tabShortcutKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];
}
