import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/app_session_controller.dart';
import '../state/root_shell_controller.dart';

class LiveActivityNavigationService {
  LiveActivityNavigationService({
    required AppSessionController sessionController,
    required RootShellController shellController,
    MethodChannel? channel,
    bool? supported,
  }) : _sessionController = sessionController,
       _shellController = shellController,
       _channel = channel ?? const MethodChannel(_channelName),
       _supported =
           supported ?? (!kIsWeb && isPlatformSupported(defaultTargetPlatform));

  static const _channelName = 'ispace/app_navigation';

  @visibleForTesting
  static bool isPlatformSupported(TargetPlatform platform) {
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  final AppSessionController _sessionController;
  final RootShellController _shellController;
  final MethodChannel _channel;
  final bool _supported;

  AppTab? _pendingTab;
  bool _started = false;
  bool _draining = false;
  bool _drainAgain = false;

  Future<void> start() async {
    if (!_supported || _started) return;
    _started = true;
    _sessionController.addListener(_handleSessionChanged);
    _channel.setMethodCallHandler(_handleNativeCall);
    await _drainNativeDestinations();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'navigationAvailable') {
      await _drainNativeDestinations();
    }
  }

  Future<void> _drainNativeDestinations() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        while (_started) {
          final destination = await _takePendingDestination();
          if (destination == null || destination.trim().isEmpty) break;
          acceptDestination(destination);
        }
      } while (_drainAgain && _started);
    } finally {
      _draining = false;
    }
  }

  Future<String?> _takePendingDestination() async {
    try {
      return await _channel.invokeMethod<String>('takePendingDestination');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @visibleForTesting
  void acceptDestination(String destination) {
    _pendingTab = destinationTab(destination);
    _openPendingTabIfPossible();
  }

  @visibleForTesting
  static AppTab destinationTab(String destination) {
    return switch (destination.trim().toLowerCase()) {
      'mail' => AppTab.mail,
      'ispace' => AppTab.ispace,
      'schedule' => AppTab.schedule,
      'user' => AppTab.user,
      _ => AppTab.home,
    };
  }

  void _handleSessionChanged() {
    _openPendingTabIfPossible();
  }

  void _openPendingTabIfPossible() {
    final tab = _pendingTab;
    if (tab == null || !_sessionController.isLoggedIn) return;
    _pendingTab = null;
    _shellController.selectTab(tab);
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _sessionController.removeListener(_handleSessionChanged);
    _channel.setMethodCallHandler(null);
  }
}
