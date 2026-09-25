import '../services/me_identity_service.dart';
import '../services/sync/sync_scheduler.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/mail_radar_models.dart';
import '../services/ai_assistant_service.dart';
import '../services/mail_radar_analyzer.dart';
import '../services/mail_service.dart';
import '../services/mail_source_service.dart';
import '../services/mail_service_factory.dart';
import 'app_session_controller.dart';
import 'app_language_controller.dart';
import 'mail_radar_controller.dart';

/// Keeps consented mail-radar analysis alive independently from the mail page.
///
/// IMAP IDLE is the primary trigger while the process can run. A two-minute
/// scan remains as a reconnect/fallback path. iOS background fetch may call
/// [performSystemRefresh], but scheduling remains controlled by the OS.
class MailRadarBackgroundCoordinator extends ChangeNotifier {
  MailRadarBackgroundCoordinator({
    required this.sessionController,
    required this.assistantService,
    this.languageController,
    MailService? mailService,
    this.pollInterval = const Duration(minutes: 2),
  }) : mailService = mailService ?? createMailService();

  static const _backgroundChannel = MethodChannel(
    'ispace/mail_radar_background',
  );

  final AppSessionController sessionController;
  final AiAssistantService assistantService;
  final AppLanguageController? languageController;
  final MailService mailService;
  final Duration pollInterval;

  MailRadarController? _controller;
  void Function()? _cancelPoll;
  StreamSubscription<void>? _inboxSubscription;
  Future<MailRadarController?>? _initialization;
  int _sessionGeneration = 0;
  bool _started = false;
  bool _activated = false;
  bool _monitoringStarted = false;
  bool _disposed = false;
  bool _isFeatureAvailable = false;
  bool _availabilityKnown = false;
  bool _isCheckingFeatureAvailability = false;
  String? _featureAvailabilityError;
  Future<bool>? _availabilityRefresh;

  MailRadarController? get controller => _controller;
  bool get isFeatureAvailable => _isFeatureAvailable;
  bool get availabilityKnown => _availabilityKnown;
  bool get isCheckingFeatureAvailability => _isCheckingFeatureAvailability;
  String? get featureAvailabilityError => _featureAvailabilityError;

  /// The mailbox may render radar controls only while both the account-level
  /// permission and the account's explicit range choice are active.
  bool get isEffectivelyEnabled =>
      _isFeatureAvailable &&
      _controller?.hasConsent == true &&
      _controller?.enabled == true &&
      (_controller?.analyzer is! MailSourceRadarAnalyzer ||
          (_controller!.analyzer as MailSourceRadarAnalyzer).hasSourceConsent);

  void start() {
    if (_started || _disposed) return;
    _started = true;
    sessionController.addListener(_handleSessionChanged);
    MeIdentityService.shared.addListener(_handleSessionChanged);
    languageController?.addListener(_handleLanguageChanged);
    if (Platform.isIOS) {
      _backgroundChannel.setMethodCallHandler(_handleNativeCall);
    }
    unawaited(ensureReady());
  }

  Future<MailRadarController?> ensureReady() {
    if (_disposed ||
        !sessionController.isLoggedIn ||
        (assistantService is RemoteAiAssistantService &&
            !MeIdentityService.shared.isBound(sessionController.username))) {
      return Future<MailRadarController?>.value(null);
    }
    final existing = _controller;
    final username = sessionController.username?.trim().toLowerCase() ?? '';
    if (existing != null &&
        existing.username.trim().toLowerCase() == username) {
      return Future<MailRadarController?>.value(existing);
    }
    final active = _initialization;
    if (active != null) return active;
    final generation = _sessionGeneration;
    final initialization = _initialize(generation);
    _initialization = initialization;
    return initialization.whenComplete(() {
      if (identical(_initialization, initialization)) _initialization = null;
    });
  }

  Future<void> activateAfterConsent() async {
    final controller = await ensureReady();
    if (controller?.hasConsent == true && controller?.enabled == true) {
      await _activateIfConsented();
    }
  }

  /// Resolves the state that the settings page presents without treating a
  /// transient capability request failure as an administrator denial.
  Future<MailRadarController?> prepareForSettings() async {
    if (!await refreshFeatureAvailability()) return null;
    final controller = await ensureReady();
    await controller?.refreshPreferences();
    if (controller?.hasConsent == true && controller?.enabled == true) {
      await _activateIfConsented();
    }
    return controller;
  }

  Future<MailRadarController?> _initialize(int generation) async {
    final username = sessionController.username?.trim() ?? '';
    if (!await refreshFeatureAvailability()) {
      return null;
    }
    final credentials = await sessionController.loadMailAccessCredentials();
    if (_disposed ||
        generation != _sessionGeneration ||
        username.isEmpty ||
        credentials == null ||
        assistantService is! AiAssistantMailRadarService) {
      return null;
    }
    final controller = MailRadarController(
      username: username,
      credentials: credentials,
      mailService: mailService,
      analyzer: assistantService is MailSourceService
          ? MailSourceRadarAnalyzer(
              assistantService: assistantService,
              radarService: assistantService as AiAssistantMailRadarService,
              source: assistantService as MailSourceService,
              targetLanguageTagProvider: _targetLanguageTag,
            )
          : LightMailRadarAnalyzer(
              assistantService: assistantService,
              radarService: assistantService as AiAssistantMailRadarService,
              targetLanguageTagProvider: _targetLanguageTag,
            ),
      targetLanguageTagProvider: _targetLanguageTag,
      syncService: assistantService is AiAssistantMailRadarSyncService
          ? assistantService as AiAssistantMailRadarSyncService
          : null,
      onRemoteAccessUnavailable: _markFeatureUnavailable,
    );
    await controller.initialize();
    if (_disposed || generation != _sessionGeneration || !_isFeatureAvailable) {
      controller.dispose();
      return null;
    }
    _controller = controller;
    _startFallbackPolling();
    controller.addListener(_handleRadarChanged);
    final monitor = _monitor;
    if (monitor != null) {
      _inboxSubscription = monitor.inboxChanges.listen((_) {
        unawaited(_scanIfAllowed());
      });
    }
    notifyListeners();
    await _activateIfConsented();
    return controller;
  }

  void _handleSessionChanged() {
    final controller = _controller;
    final access = sessionController.mailAccess;
    final credentials = access.credentials;
    final username = sessionController.username?.trim().toLowerCase() ?? '';
    if (!sessionController.isLoggedIn ||
        (assistantService is RemoteAiAssistantService &&
            !MeIdentityService.shared.isBound(username)) ||
        (controller != null &&
            access.owner != null &&
            (credentials == null ||
                credentials.password != controller.credentials.password)) ||
        (controller != null &&
            controller.username.trim().toLowerCase() != username)) {
      _sessionGeneration++;
      unawaited(_restartForCurrentSession());
      return;
    }
    if (sessionController.isLoggedIn) unawaited(ensureReady());
  }

  void _handleLanguageChanged() {
    final controller = _controller;
    if (controller?.hasConsent == true && controller?.enabled == true) {
      unawaited(controller!.scan());
    }
  }

  String _targetLanguageTag() =>
      languageController?.resolveInterfaceLanguageTag(
        PlatformDispatcher.instance.locales,
      ) ??
      mailRadarDefaultTargetLanguageTag;

  Future<void> _restartForCurrentSession() async {
    await _resetRuntime();
    final initialization = _initialization;
    if (initialization != null) {
      try {
        await initialization;
      } catch (_) {
        // A superseded initialization is expected to stop at generation check.
      }
    }
    if (!_disposed && sessionController.isLoggedIn) await ensureReady();
  }

  void _handleRadarChanged() {
    final controller = _controller;
    if (controller?.hasConsent == true && controller?.enabled == true) {
      if (!_activated) unawaited(_activateIfConsented());
      notifyListeners();
      return;
    }
    if (_activated) unawaited(_deactivateMonitoring());
    notifyListeners();
  }

  Future<void> _activateIfConsented() async {
    final controller = _controller;
    if (controller?.hasConsent != true ||
        controller?.enabled != true ||
        !_isFeatureAvailable ||
        _disposed ||
        _activated) {
      return;
    }
    _activated = true;
    _startFallbackPolling();
    await _ensureInboxMonitoring();
    await _scanIfAllowed();
  }

  void _startFallbackPolling() {
    _cancelPoll?.call();
    if (pollInterval <= Duration.zero) return;
    _cancelPoll = SyncScheduler.shared.register(
      key: this,
      interval: pollInterval,
      background: true,
      run: () async {
        await _refresh();
      },
    );
  }

  Future<bool> _refresh() async {
    if (!await refreshFeatureAvailability()) return false;
    final controller = await ensureReady();
    await controller?.refreshPreferences();
    if (_disposed) return false;
    await _ensureInboxMonitoring();
    return _scanIfAllowed();
  }

  Future<bool> refreshFeatureAvailability() {
    final active = _availabilityRefresh;
    if (active != null) return active;
    final refresh = _refreshFeatureAvailability();
    _availabilityRefresh = refresh;
    return refresh.whenComplete(() {
      if (identical(_availabilityRefresh, refresh)) {
        _availabilityRefresh = null;
      }
    });
  }

  Future<bool> _refreshFeatureAvailability() async {
    final username = sessionController.username?.trim() ?? '';
    var available = false;
    var checkSucceeded = false;
    String? failure;
    final previousAvailable = _isFeatureAvailable;
    final previousKnown = _availabilityKnown;
    final previousError = _featureAvailabilityError;
    if (!_isCheckingFeatureAvailability) {
      _isCheckingFeatureAvailability = true;
      notifyListeners();
    }
    if (!_disposed && sessionController.isLoggedIn && username.isNotEmpty) {
      try {
        available =
            await assistantService.isEnabled(username) &&
            (assistantService is MailSourceService ||
                (await assistantService.loadCapabilities(
                  username,
                )).mailRadarEnabled);
        checkSucceeded = true;
      } catch (_) {
        failure = '暂时无法确认邮件雷达权限，请稍后重试。';
        // A known grant remains usable during a transient network failure. The
        // settings surface distinguishes this state from an explicit denial.
        available = _availabilityKnown ? _isFeatureAvailable : false;
      }
    }
    if (!_disposed && !sessionController.isLoggedIn) {
      checkSucceeded = true;
    }
    _availabilityKnown = checkSucceeded;
    _isFeatureAvailable = available;
    _featureAvailabilityError = failure;
    _isCheckingFeatureAvailability = false;
    if (!available && _activated) {
      await _deactivateMonitoring();
    }
    if (available && !previousAvailable) {
      await _activateIfConsented();
    }
    final changed =
        previousAvailable != _isFeatureAvailable ||
        previousKnown != _availabilityKnown ||
        previousError != _featureAvailabilityError;
    if ((changed || _isCheckingFeatureAvailability) && !_disposed) {
      notifyListeners();
    }
    return available;
  }

  void _markFeatureUnavailable() {
    if (_disposed) return;
    final changed = !_availabilityKnown || _isFeatureAvailable;
    _availabilityKnown = true;
    _isFeatureAvailable = false;
    _featureAvailabilityError = null;
    _isCheckingFeatureAvailability = false;
    if (_activated) unawaited(_deactivateMonitoring());
    if (changed) notifyListeners();
  }

  Future<void> _ensureInboxMonitoring() async {
    if (_monitoringStarted || _disposed) return;
    final monitor = _monitor;
    final controller = _controller;
    if (monitor == null ||
        controller?.hasConsent != true ||
        controller?.enabled != true) {
      return;
    }
    try {
      await monitor.startInboxMonitoring(credentials: controller!.credentials);
      _monitoringStarted = true;
    } catch (_) {
      // A later fallback tick retries IDLE; scanning can still reconnect itself.
    }
  }

  Future<bool> _scanIfAllowed() async {
    if (!_isFeatureAvailable) return false;
    final controller = await ensureReady();
    if (controller?.hasConsent != true || controller?.enabled != true) {
      return false;
    }
    final username = controller!.username.trim();
    if (username.isEmpty) return false;
    try {
      if (!await assistantService.isEnabled(username)) return false;
      final before = controller.analyzedCount;
      await controller.scan();
      return controller.analyzedCount > before;
    } catch (_) {
      return false;
    }
  }

  Future<bool> performSystemRefresh() => _refresh();

  Future<void> _deactivateMonitoring() async {
    // Keep settings polling alive so another device can enable the account.
    _activated = false;
    _monitoringStarted = false;
    await _monitor?.stopInboxMonitoring();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'performRefresh') return performSystemRefresh();
    throw MissingPluginException('Unknown mail radar background call.');
  }

  Future<void> _resetRuntime() async {
    _cancelPoll?.call();
    _cancelPoll = null;
    _activated = false;
    _monitoringStarted = false;
    await _inboxSubscription?.cancel();
    _inboxSubscription = null;
    await _monitor?.stopInboxMonitoring();
    final controller = _controller;
    _controller = null;
    _isFeatureAvailable = false;
    _availabilityKnown = false;
    _featureAvailabilityError = null;
    _isCheckingFeatureAvailability = false;
    if (controller != null) {
      controller.removeListener(_handleRadarChanged);
      controller.dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    sessionController.removeListener(_handleSessionChanged);
    MeIdentityService.shared.removeListener(_handleSessionChanged);
    languageController?.removeListener(_handleLanguageChanged);
    _cancelPoll?.call();
    unawaited(_inboxSubscription?.cancel());
    unawaited(_monitor?.stopInboxMonitoring());
    unawaited(mailService.close());
    if (Platform.isIOS) _backgroundChannel.setMethodCallHandler(null);
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_handleRadarChanged);
      controller.dispose();
    }
    super.dispose();
  }

  MailInboxMonitor? get _monitor =>
      mailService is MailInboxMonitor ? mailService as MailInboxMonitor : null;
}
