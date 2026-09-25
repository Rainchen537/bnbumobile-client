import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/bnbu_loading.dart';
import '../widgets/statistics_privacy_notice.dart';
import '../widgets/mail_connection_panel.dart';
import '../state/app_session_controller.dart';
import '../state/app_language_controller.dart';
import '../state/app_protection_controller.dart';
import '../state/app_update_controller.dart';
import '../state/app_theme_mode_controller.dart';
import '../state/mail_assistant_intent_controller.dart';
import '../state/mail_radar_background_coordinator.dart';
import '../services/mail_service.dart';
import '../state/live_activity_preference_controller.dart';
import '../state/root_shell_controller.dart';
import '../state/ta_course_controller.dart';
import '../services/ai_assistant_service.dart';
import '../services/home_card_visibility_service.dart';
import 'login_page.dart';
import '../state/personal_sync_coordinator.dart';
import 'root_shell_page.dart';

class AppEntryPage extends StatefulWidget {
  const AppEntryPage({
    super.key,
    required this.controller,
    required this.appProtectionController,
    required this.shellController,
    required this.taCourseController,
    required this.mailIntentController,
    required this.themeModeController,
    required this.languageController,
    required this.liveActivityController,
    required this.appUpdateController,
    required this.onDisableAssistant,
    required this.onClearAssistantHistory,
    this.mailRadarAssistantService,
    this.mailRadarCoordinator,
    this.mailService,
    this.homeCardVisibilityService,
    this.personalSync,
  });

  final AppSessionController controller;
  final AppProtectionController appProtectionController;
  final RootShellController shellController;
  final TaCourseController taCourseController;
  final MailAssistantIntentController mailIntentController;
  final AppThemeModeController themeModeController;
  final AppLanguageController languageController;
  final LiveActivityPreferenceController liveActivityController;
  final AppUpdateController appUpdateController;
  final Future<void> Function() onDisableAssistant;
  final Future<void> Function() onClearAssistantHistory;
  final AiAssistantService? mailRadarAssistantService;
  final MailRadarBackgroundCoordinator? mailRadarCoordinator;
  final MailService? mailService;
  final HomeCardVisibilityService? homeCardVisibilityService;
  final PersonalSyncCoordinator? personalSync;

  @override
  State<AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<AppEntryPage>
    with WidgetsBindingObserver {
  Timer? _heartbeatTimer;
  String? _shellOwner;
  bool _initialSessionRestoreFinished = false;

  @override
  void initState() {
    super.initState();
    _shellOwner = _normalizedLoggedInOwner;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleSessionChanged);
    unawaited(_restoreInitialSession());
    _startHeartbeatTimer();
  }

  @override
  void didUpdateWidget(covariant AppEntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleSessionChanged);
      widget.controller.addListener(_handleSessionChanged);
      _shellOwner = _normalizedLoggedInOwner;
      widget.shellController.reset();
      _initialSessionRestoreFinished = false;
      unawaited(_restoreInitialSession());
    }
  }

  Future<void> _restoreInitialSession() async {
    final restoringController = widget.controller;
    await restoringController.restoreSessionIfPossible();
    if (!mounted || !identical(restoringController, widget.controller)) {
      return;
    }
    setState(() {
      _initialSessionRestoreFinished = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.restoreSessionIfPossible());
      _startHeartbeatTimer();
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    unawaited(widget.controller.sendUsageHeartbeat());
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(widget.controller.sendUsageHeartbeat());
    });
  }

  void _handleSessionChanged() {
    final owner = _normalizedLoggedInOwner;
    if (owner == null || owner != _shellOwner) {
      widget.shellController.reset();
    }
    _shellOwner = owner;
  }

  String? get _normalizedLoggedInOwner {
    if (!widget.controller.isLoggedIn) {
      return null;
    }
    final value = widget.controller.username?.trim().toLowerCase() ?? '';
    return value.isEmpty ? null : value;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleSessionChanged);
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.appProtectionController,
      ]),
      builder: (context, _) {
        if (!_initialSessionRestoreFinished) {
          return const _InitialSessionRestorePage();
        }
        if (widget.controller.isLoggedIn) {
          return StatisticsLoginGate(
            service: widget.controller.statistics,
            ready: !widget.appProtectionController.shouldShowGate,
            child: MailConnectionGate(
              controller: widget.controller.mailAccess,
              ready: !widget.appProtectionController.shouldShowGate,
              child: RootShellPage(
                personalSync: widget.personalSync,
                controller: widget.controller,
                appProtectionController: widget.appProtectionController,
                shellController: widget.shellController,
                taCourseController: widget.taCourseController,
                mailIntentController: widget.mailIntentController,
                themeModeController: widget.themeModeController,
                languageController: widget.languageController,
                liveActivityController: widget.liveActivityController,
                appUpdateController: widget.appUpdateController,
                onDisableAssistant: widget.onDisableAssistant,
                onClearAssistantHistory: widget.onClearAssistantHistory,
                mailRadarAssistantService: widget.mailRadarAssistantService,
                mailRadarCoordinator: widget.mailRadarCoordinator,
                mailService: widget.mailService,
                homeCardVisibilityService: widget.homeCardVisibilityService,
              ),
            ),
          );
        }
        return LoginPage(controller: widget.controller);
      },
    );
  }
}

class _InitialSessionRestorePage extends StatelessWidget {
  const _InitialSessionRestorePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: BnbuActivityIndicator()));
  }
}
