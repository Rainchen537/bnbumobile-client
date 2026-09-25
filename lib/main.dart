import 'services/me_identity_service.dart';
import 'services/sync/sync_scheduler.dart';
import 'services/page_backdrop_store.dart';
import 'state/account_habits.dart';
import 'services/academic_calendar_store.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/app_config.dart';
import 'state/personal_sync_coordinator.dart';
import 'pages/app_entry_page.dart';
import 'pages/study_window_app.dart';
import 'services/ai_assistant_service.dart';
import 'services/app_navigation_coordinator.dart';
import 'services/home_card_visibility_service.dart';
import 'services/live_activity_navigation_service.dart';
import 'services/assistant_context_coordinator.dart';
import 'services/student_avatar_rive_runtime.dart';
import 'services/study_window_manager.dart';
import 'services/small_u_acceptance_bridge.dart';
import 'services/widget_snapshot_service.dart';
import 'state/ai_assistant_controller.dart';
import 'state/app_language_controller.dart';
import 'state/app_protection_controller.dart';
import 'state/app_session_controller.dart';
import 'state/assistant_presentation_controller.dart';
import 'state/assistant_resource_library_controller.dart';
import 'state/app_update_controller.dart';
import 'models/app_update_policy.dart';
import 'state/app_statistics_coordinator.dart';
import 'state/app_theme_mode_controller.dart';
import 'state/mail_assistant_intent_controller.dart';
import 'state/mail_radar_background_coordinator.dart';
import 'state/mail_startup_coordinator.dart';
import 'state/live_activity_preference_controller.dart';
import 'state/root_shell_controller.dart';
import 'state/ta_course_controller.dart';
import 'state/study_mode_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/ai_assistant_overlay.dart';
import 'widgets/app_protection_gate.dart';
import 'widgets/app_update_prompt.dart';
import 'widgets/assistant_context_scope.dart';
import 'widgets/assistant_resource_library_scope.dart';
import 'widgets/bnbu_liquid_glass.dart';
import 'widgets/moodle_activity_icon.dart';
import 'widgets/rich_mail_editor.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerMoodleIconLicense();
  registerMailEditorLicenses();
  final acceptanceBridgeConfig = SmallUAcceptanceBridgeConfig.fromArguments(
    arguments,
  );
  if ((Platform.isMacOS || Platform.isWindows) &&
      AppConfig.studyModeEnabled &&
      acceptanceBridgeConfig == null) {
    final windowController = await WindowController.fromCurrentEngine();
    final studyDocuments = StudyWindowManager.decodeDocuments(
      windowController.arguments,
    );
    if (studyDocuments != null) {
      runApp(
        StudyWindowApp(
          windowController: windowController,
          documents: studyDocuments,
        ),
      );
      return;
    }
  }
  await PageBackdropStore.shared.loadLocal();
  unawaited(PageBackdropStore.shared.start());
  await StudentAvatarRiveRuntime.initialize();
  runApp(BnbuApp(acceptanceBridgeConfig: acceptanceBridgeConfig));
}

class BnbuApp extends StatefulWidget {
  const BnbuApp({
    super.key,
    this.acceptanceBridgeConfig,
    this.appUpdateController,
  });

  final SmallUAcceptanceBridgeConfig? acceptanceBridgeConfig;
  final AppUpdateController? appUpdateController;

  @override
  State<BnbuApp> createState() => _BnbuAppState();
}

class _BnbuAppState extends State<BnbuApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppSessionController _controller = AppSessionController();
  late final AppLanguageController _languageController =
      AppLanguageController();
  late final AppProtectionController _appProtectionController =
      AppProtectionController(
        localizedAuthenticationReason: () {
          final locale = _languageController.resolveLocale(
            WidgetsBinding.instance.platformDispatcher.locales,
          );
          return BnbuLocalizations(
            locale,
          ).text(AppProtectionController.defaultAuthenticationReason);
        },
      );
  late final AppUpdateController _appUpdateController =
      widget.appUpdateController ?? AppUpdateController();
  late final bool _ownsAppUpdateController = widget.appUpdateController == null;
  late final RootShellController _shellController = RootShellController();
  late final AppThemeModeController _themeModeController =
      AppThemeModeController();
  late final MailAssistantIntentController _mailIntentController =
      MailAssistantIntentController();
  late final LiveActivityPreferenceController _liveActivityController =
      LiveActivityPreferenceController();
  late final LiveActivityNavigationService _liveActivityNavigationService =
      LiveActivityNavigationService(
        sessionController: _controller,
        shellController: _shellController,
      );
  late final TaCourseController _taCourseController = TaCourseController(
    sessionController: _controller,
  );
  late final PersonalSyncCoordinator _personalSync = PersonalSyncCoordinator(
    session: _controller,
    schedules: _taCourseController,
  );
  late final WidgetSnapshotCoordinator _widgetSnapshotCoordinator =
      WidgetSnapshotCoordinator(
        sessionController: _controller,
        taCourseController: _taCourseController,
        liveActivityController: _liveActivityController,
        languageController: _languageController,
      );
  late final AiAssistantService _assistantService = RemoteAiAssistantService(
    // A normal device deliberately keeps the shared per-host cap at six. The
    // signed acceptance build raises only its transport cap so one Mac can
    // represent independent student devices during an 80-client burst.
    maxConnectionsPerHost: widget.acceptanceBridgeConfig == null
        ? null
        : smallUAcceptanceMaxConcurrentTurns,
  );
  late final HomeCardVisibilityService _homeCardVisibilityService =
      RemoteHomeCardVisibilityService();
  late final MailStartupCoordinator _mailStartupCoordinator =
      MailStartupCoordinator(sessionController: _controller);
  late final MailRadarBackgroundCoordinator _mailRadarCoordinator =
      MailRadarBackgroundCoordinator(
        sessionController: _controller,
        assistantService: _assistantService,
        languageController: _languageController,
      );
  late final AssistantContextCoordinator _contextCoordinator =
      AssistantContextCoordinator();
  late final AiAssistantController _assistantController = AiAssistantController(
    sessionController: _controller,
    service: _assistantService,
    coordinator: _contextCoordinator,
    translateReceipt: (text) => BnbuLocalizations(
      _languageController.locale ??
          AppLanguageController.resolveSystemLocale(
            WidgetsBinding.instance.platformDispatcher.locales,
          ),
    ).text(text),
    mailRadarReader: (args) async {
      final radar = await _mailRadarCoordinator.ensureReady();
      if (!_mailRadarCoordinator.isFeatureAvailable || radar == null) {
        throw StateError('邮件雷达不可用。');
      }
      return radar.queryTasks(args);
    },
    taCourseController: _taCourseController,
  );
  late final AssistantResourceLibraryController _resourceLibraryController =
      AssistantResourceLibraryController(sessionController: _controller);
  late final AssistantPresentationController _assistantPresentationController =
      AssistantPresentationController();
  late final StudyModeController _studyModeController = StudyModeController();
  late final AppNavigationCoordinator _navigationCoordinator =
      AppNavigationCoordinator(
        navigatorKey: _navigatorKey,
        sessionController: _controller,
        assistantController: _assistantController,
        assistantPresentationController: _assistantPresentationController,
        taCourseController: _taCourseController,
        rootShellController: _shellController,
        mailIntentController: _mailIntentController,
      );
  SmallUAcceptanceBridge? _acceptanceBridge;
  Timer? _calendarRefreshTimer;
  bool _updateWasLoggedIn = false;
  int _updateTab = 0;
  void _updateLoginChanged() {
    final meOwner = _controller.isLoggedIn ? _controller.username : null;
    MeIdentityService.shared.setActiveOwner(meOwner);
    if (meOwner != null) {
      unawaited(
        MeIdentityService.shared.refresh(meOwner).catchError((Object _) {}),
      );
    }
    final loggedIn = _controller.isLoggedIn;
    if (loggedIn && !_updateWasLoggedIn) {
      unawaited(_appUpdateController.trigger(UpdateTrigger.login));
    }
    _updateWasLoggedIn = loggedIn;
  }

  void _updateNavigationChanged() {
    final tab = _shellController.selectedIndex;
    if (tab != _updateTab) {
      unawaited(_appUpdateController.trigger(UpdateTrigger.navigation));
    }
    _updateTab = tab;
  }

  late final _statisticsCoordinator = AppStatisticsCoordinator(
    session: _controller,
    protection: _appProtectionController,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statisticsCoordinator.start();
    _personalSync.setForeground(true);
    AccountHabits.shared.addListener(_accountHabitsChanged);
    unawaited(_installHabitWindowBridge());
    unawaited(_themeModeController.restore());
    unawaited(_restoreLanguageAndInitializeProtection());
    unawaited(_appUpdateController.initialize());
    _controller.addListener(_updateLoginChanged);
    _shellController.addListener(_updateNavigationChanged);
    unawaited(_shellController.restoreNavigationPreference());
    unawaited(_resourceLibraryController.initialize());
    unawaited(_liveActivityController.restore());
    unawaited(_liveActivityNavigationService.start());
    unawaited(AcademicCalendarStore.shared.refresh());
    _calendarRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(AcademicCalendarStore.shared.refresh());
      }
    });
    _widgetSnapshotCoordinator.start();
    _mailStartupCoordinator.start();
    _assistantController.startBackgroundSync();
    _mailRadarCoordinator.start();
    if (widget.acceptanceBridgeConfig != null) {
      unawaited(_startAcceptanceBridge());
    }
  }

  WindowController? _habitWindow;
  Future<void> _installHabitWindowBridge() async {
    if (!AppConfig.studyModeEnabled ||
        !(Platform.isMacOS || Platform.isWindows)) {
      return;
    }
    final window = await WindowController.fromCurrentEngine();
    if (!mounted) return;
    _habitWindow = window;
    await window.setWindowMethodHandler((call) async {
      if (call.method != 'habits.read' && call.method != 'habits.write') {
        return null;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final habits = AccountHabits.shared;
      if (!habits.isFor(args['owner'] as String?)) return null;
      if (call.method == 'habits.write') {
        await habits.set(args['key'] as String, args['value']);
      }
      if (!habits.isFor(args['owner'] as String?)) return null;
      return {'owner': habits.owner, 'values': habits.snapshot};
    });
  }

  Future<void> _broadcastHabitChange() async {
    if (_habitWindow == null) return;
    for (final window in await WindowController.getAll()) {
      if (window.windowId == _habitWindow!.windowId) continue;
      try {
        await window.invokeMethod<void>('habits.changed');
      } catch (_) {}
    }
  }

  String? _lastReminderHabits;
  void _accountHabitsChanged() {
    final habits = AccountHabits.shared;
    unawaited(_broadcastHabitChange());
    if (!habits.ready) return;
    unawaited(_themeModeController.restore());
    unawaited(
      _languageController.restore(
        preferredLocales: WidgetsBinding.instance.platformDispatcher.locales,
      ),
    );
    final reminders =
        '${habits.owner}:${habits.read<Object?>('deadline_reminders.policy', null)}:${habits.read<Object?>('course_reminders.lead_minutes', null)}';
    if (reminders != _lastReminderHabits) {
      _lastReminderHabits = reminders;
      unawaited(_controller.refreshAccountReminderHabits());
    }
  }

  Future<void> _restoreLanguageAndInitializeProtection() async {
    await _languageController.restore(
      preferredLocales: WidgetsBinding.instance.platformDispatcher.locales,
    );
    if (!mounted) return;
    await _appProtectionController.initialize();
  }

  Future<void> _startAcceptanceBridge() async {
    final config = widget.acceptanceBridgeConfig;
    if (!mounted || config == null || _acceptanceBridge != null) return;
    final runtime = SmallUAcceptanceRuntime(
      assistantController: _assistantController,
      sessionController: _controller,
      openAssistant: _navigationCoordinator.openAssistant,
      isAssistantPresented: () =>
          _assistantPresentationController.isAssistantPresented,
    );
    final bridge = SmallUAcceptanceBridge(
      config: config,
      turnHandler: runtime.runTurn,
      statusHandler: runtime.status,
      auditHandler: runtime.auditSnapshot,
    );
    _acceptanceBridge = bridge;
    try {
      await bridge.start();
    } catch (error) {
      if (identical(_acceptanceBridge, bridge)) {
        _acceptanceBridge = null;
      }
      try {
        await File('${config.discoveryFile.path}.error').writeAsString(
          jsonEncode({
            'error': 'bridge_start_failed',
            'message': error is SmallUAcceptanceException
                ? error.message
                : error.toString(),
          }),
          flush: true,
        );
      } catch (_) {
        // The visible controller error remains the final fallback.
      }
      _assistantController.reportError('小U验收桥启动失败。');
    }
  }

  @override
  void dispose() {
    AccountHabits.shared.removeListener(_accountHabitsChanged);
    unawaited(_habitWindow?.setWindowMethodHandler(null));
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_updateLoginChanged);
    _shellController.removeListener(_updateNavigationChanged);
    _statisticsCoordinator.dispose();
    _personalSync.dispose();
    _calendarRefreshTimer?.cancel();
    final acceptanceBridge = _acceptanceBridge;
    _acceptanceBridge = null;
    if (acceptanceBridge != null) {
      unawaited(acceptanceBridge.close());
    }
    _navigationCoordinator.dispose();
    _widgetSnapshotCoordinator.dispose();
    _mailStartupCoordinator.dispose();
    _mailRadarCoordinator.dispose();
    _assistantPresentationController.dispose();
    _studyModeController.dispose();
    _assistantController.dispose();
    _resourceLibraryController.dispose();
    _assistantService.dispose();
    _homeCardVisibilityService.dispose();
    _contextCoordinator.dispose();
    _taCourseController.dispose();
    _mailIntentController.dispose();
    _liveActivityController.dispose();
    _liveActivityNavigationService.dispose();
    _shellController.dispose();
    _themeModeController.dispose();
    _languageController.dispose();
    _appProtectionController.dispose();
    if (_ownsAppUpdateController) {
      _appUpdateController.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SyncScheduler.shared.setForeground(state == AppLifecycleState.resumed);
    _personalSync.setForeground(state == AppLifecycleState.resumed);
    _appUpdateController.setForeground(state == AppLifecycleState.resumed);
    _mailStartupCoordinator.setForeground(state == AppLifecycleState.resumed);
    _assistantController.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      unawaited(_mailRadarCoordinator.performSystemRefresh());
      unawaited(AcademicCalendarStore.shared.refresh());
      _widgetSnapshotCoordinator.refresh();
      unawaited(_appProtectionController.handleResumed());
      unawaited(_appUpdateController.trigger(UpdateTrigger.resume));
      return;
    }
    _appProtectionController.lockForBackground();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _widgetSnapshotCoordinator.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_themeModeController, _languageController]),
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        onGenerateTitle: (context) => context.l10n.text('BNBU.ME'),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeModeController.themeMode,
        locale: _languageController.locale,
        localeListResolutionCallback: (locales, supportedLocales) =>
            _languageController.resolveLocale(locales),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AppEntryPage(
          personalSync: _personalSync,
          controller: _controller,
          appProtectionController: _appProtectionController,
          shellController: _shellController,
          taCourseController: _taCourseController,
          mailIntentController: _mailIntentController,
          themeModeController: _themeModeController,
          languageController: _languageController,
          liveActivityController: _liveActivityController,
          appUpdateController: _appUpdateController,
          onDisableAssistant: _assistantController.disableAssistant,
          onClearAssistantHistory: _assistantController.clearHistory,
          mailRadarAssistantService: _assistantService,
          mailRadarCoordinator: _mailRadarCoordinator,
          mailService: _mailStartupCoordinator.mailService,
          homeCardVisibilityService: _homeCardVisibilityService,
        ),
        builder: (context, child) {
          return BnbuSystemUiScope(
            child: BnbuLiquidGlassScope(
              controller: _themeModeController,
              child: AppProtectionGate(
                controller: _appProtectionController,
                child: AssistantResourceLibraryScope(
                  controller: _resourceLibraryController,
                  child: AssistantContextScope(
                    coordinator: _contextCoordinator,
                    assistantController: _assistantController,
                    presentationController: _assistantPresentationController,
                    studyModeController: _studyModeController,
                    openAssistant: _navigationCoordinator.openAssistant,
                    openAssistantWithMailReference:
                        _navigationCoordinator.openAssistantWithMailReference,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: child ?? const SizedBox.shrink(),
                        ),
                        AiAssistantOverlay(
                          shellController: _shellController,
                          sessionController: _controller,
                          presentationController:
                              _assistantPresentationController,
                          navigationCoordinator: _navigationCoordinator,
                          studyModeController: _studyModeController,
                        ),
                        AppUpdatePromptListener(
                          controller: _appUpdateController,
                          modalContextProvider: () =>
                              _navigatorKey.currentState?.overlay?.context,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
