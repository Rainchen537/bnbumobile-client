import 'dart:async';

import 'package:flutter/widgets.dart';

import 'home_navigation_stack.dart';

/// One clock for the mounted ME Life consumers on the active navigation tab.
/// Bodies remain navigation-driven; this clock only revalidates visibility.
final _policyClock = _LandmarkPolicyClock();

class _LandmarkPolicyClock with WidgetsBindingObserver {
  final _checks = <Object, Future<void> Function()>{};
  Timer? _timer;
  bool _foreground = true;

  VoidCallback subscribe(Future<void> Function() check) {
    if (_checks.isEmpty) {
      WidgetsBinding.instance.addObserver(this);
      final state = WidgetsBinding.instance.lifecycleState;
      _foreground = state == null || state == AppLifecycleState.resumed;
    }
    final key = Object();
    _checks[key] = check;
    _start();
    return () {
      _checks.remove(key);
      if (_checks.isEmpty) {
        _timer?.cancel();
        _timer = null;
        WidgetsBinding.instance.removeObserver(this);
      }
    };
  }

  void _start() {
    if (_foreground && _checks.isNotEmpty) {
      _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    }
  }

  void _tick() {
    for (final entry in _checks.entries.toList()) {
      if (_checks.containsKey(entry.key)) unawaited(entry.value());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    _timer = null;
    if (_foreground) {
      _tick();
      _start();
    }
  }
}

mixin LandmarkPolicyPolling<T extends StatefulWidget> on State<T> {
  VoidCallback? _stopPolicyChecks;
  bool _hasObservedPolicy = false;

  Future<void> pollLandmarkPolicy();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active =
        TickerMode.valuesOf(context).enabled &&
        NavigationTabScope.isActiveOf(context);
    if (active && _stopPolicyChecks == null) {
      _stopPolicyChecks = _policyClock.subscribe(pollLandmarkPolicy);
      if (_hasObservedPolicy) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _stopPolicyChecks != null) {
            unawaited(pollLandmarkPolicy());
          }
        });
      }
      _hasObservedPolicy = true;
    } else if (!active) {
      _stopPolicyChecks?.call();
      _stopPolicyChecks = null;
    }
  }

  @override
  void dispose() {
    _stopPolicyChecks?.call();
    super.dispose();
  }
}
