import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/apple_statistics_bridge.dart';
import 'app_protection_controller.dart';
import 'app_session_controller.dart';

/// Counts entry edges, not generic active/inactive callbacks or page changes.
class AppEntryTracker {
  bool foreground = true;
  bool unlocked = false;
  bool pending = true;
  void reset() => pending = true;
  void background() {
    foreground = false;
    pending = true;
  }

  void inactive() => foreground = false;
  void resume() => foreground = true;
  bool take({required bool enabled}) {
    if (!pending || !foreground || !unlocked || !enabled) return false;
    pending = false;
    return true;
  }
}

class AppStatisticsCoordinator with WidgetsBindingObserver {
  AppStatisticsCoordinator({
    required this.session,
    required this.protection,
    AppleStatisticsBridge? bridge,
  }) : _bridge = bridge ?? AppleStatisticsBridge();
  final AppSessionController session;
  final AppProtectionController protection;
  final AppleStatisticsBridge _bridge;
  final AppEntryTracker _entry = AppEntryTracker();
  Timer? _timer;
  String? _account;
  bool _disposed = false;
  bool _remindersWereEnabled = false;
  bool get _desktop => session.statistics.platform == TargetPlatform.macOS;

  void start() {
    if (!session.statistics.supported) return;
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_accountChanged);
    session.statistics.addListener(_changed);
    protection.addListener(_changed);
    _entry.foreground =
        !_desktop &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed);
    if (_desktop) {
      unawaited(
        _bridge
            .watchVisibility((visible) {
              if (_disposed) return;
              if (visible) {
                _entry.resume();
              } else {
                _entry.background();
              }
              _changed();
            })
            .catchError((Object _) {
              /* unavailable bridge must not count focus changes */
            }),
      );
    }
    _accountChanged();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_entry.foreground) unawaited(session.statistics.poll());
    });
  }

  void _accountChanged() {
    final username = session.isLoggedIn && !session.isLoggingOut
        ? session.username
        : null;
    if (_account == username) return;
    _account = username;
    _remindersWereEnabled = false;
    _entry.reset();
    unawaited(
      session.statistics.setAccount(username).catchError((Object _) {}),
    );
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    final remindersEnabled = session.statistics.remindersEnabled;
    final refresh = remindersEnabled && !_remindersWereEnabled;
    _remindersWereEnabled = remindersEnabled;
    if (refresh) {
      unawaited(
        session.refreshReminderStatisticsBindings().catchError((Object _) {}),
      );
    }
    _entry.unlocked = !protection.shouldShowGate && _account != null;
    if (_entry.take(enabled: session.statistics.appUsageEnabled)) {
      unawaited(
        session.statistics
            .recordEntry()
            .then((_) => session.statistics.poll())
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_desktop) {
      return; // Native main-window visibility; losing focus is not exit.
    }
    if (state == AppLifecycleState.paused) {
      _entry.background();
    } else if (state == AppLifecycleState.resumed) {
      _entry.resume();
      unawaited(session.statistics.poll());
    } else {
      _entry
          .inactive(); // Face ID/control center/system sheets never arm an entry.
    }
    _changed();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_accountChanged);
    session.statistics.removeListener(_changed);
    protection.removeListener(_changed);
    _bridge.dispose();
  }
}
