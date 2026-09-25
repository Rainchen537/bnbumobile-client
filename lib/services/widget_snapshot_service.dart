import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/widget_snapshot.dart';
import '../state/app_session_controller.dart';
import '../state/app_language_controller.dart';
import '../state/live_activity_preference_controller.dart';
import '../state/ta_course_controller.dart';

abstract interface class WidgetSnapshotGateway {
  Future<void> update(String json);

  Future<void> updateInterfaceLanguage(String languageTag);

  Future<void> clear();
}

class NativeWidgetSnapshotGateway implements WidgetSnapshotGateway {
  const NativeWidgetSnapshotGateway();

  static const MethodChannel _channel = MethodChannel('ispace/widget_snapshot');

  bool get _isSupported => Platform.isIOS || Platform.isMacOS;

  @override
  Future<void> update(String json) async {
    if (!_isSupported) return;
    await _channel.invokeMethod<void>('updateWidgetSnapshot', <String, Object>{
      'json': json,
    });
  }

  @override
  Future<void> updateInterfaceLanguage(String languageTag) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>(
        'updateWatchInterfaceLanguage',
        <String, Object>{'languageTag': languageTag},
      );
    } on MissingPluginException {
      // Other Flutter targets intentionally do not provide WatchConnectivity.
    } on PlatformException {
      // Keep the app usable when the paired Watch is temporarily unavailable.
    }
  }

  @override
  Future<void> clear() async {
    if (!_isSupported) return;
    await _channel.invokeMethod<void>('clearWidgetSnapshot');
  }
}

class WidgetSnapshotCoordinator {
  WidgetSnapshotCoordinator({
    required AppSessionController sessionController,
    required TaCourseController taCourseController,
    required LiveActivityPreferenceController liveActivityController,
    AppLanguageController? languageController,
    WidgetSnapshotGateway gateway = const NativeWidgetSnapshotGateway(),
    DateTime Function()? now,
    Duration debounceDuration = const Duration(milliseconds: 300),
    Duration retryDuration = const Duration(seconds: 30),
  }) : _sessionController = sessionController,
       _taCourseController = taCourseController,
       _liveActivityController = liveActivityController,
       _languageController = languageController,
       _gateway = gateway,
       _now = now ?? DateTime.now,
       _debounceDuration = debounceDuration,
       _retryDuration = retryDuration;

  final AppSessionController _sessionController;
  final TaCourseController _taCourseController;
  final LiveActivityPreferenceController _liveActivityController;
  final AppLanguageController? _languageController;
  final WidgetSnapshotGateway _gateway;
  final DateTime Function() _now;
  final Duration _debounceDuration;
  final Duration _retryDuration;

  Timer? _debounce;
  String? _lastPayload;
  String? _lastInterfaceLanguage;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _sessionController.addListener(_scheduleSync);
    _taCourseController.addListener(_scheduleSync);
    _liveActivityController.addListener(_scheduleSync);
    _languageController?.addListener(_scheduleSync);
    _scheduleSync();
  }

  void refresh() => _scheduleSync();

  void _scheduleSync([Duration? delay]) {
    if (_disposed || _sessionController.isRestoringSession) return;
    _debounce?.cancel();
    _debounce = Timer(delay ?? _debounceDuration, () {
      unawaited(_syncSafely());
    });
  }

  Future<void> _syncSafely() async {
    try {
      await _sync();
    } on MissingPluginException {
      debugPrint('Widget snapshot bridge unavailable.');
      _scheduleSync(_retryDuration);
    } on PlatformException catch (error) {
      debugPrint('Widget snapshot sync failed: ${error.code}');
      _scheduleSync(_retryDuration);
    }
  }

  Future<void> _sync() async {
    if (_disposed || _sessionController.isRestoringSession) return;
    final interfaceLanguage =
        _languageController?.resolveInterfaceLanguageTag(
          WidgetsBinding.instance.platformDispatcher.locales,
        ) ??
        AppLanguageController.interfaceLanguageTagForLocale(
          AppLanguageController.resolveSystemLocale(
            WidgetsBinding.instance.platformDispatcher.locales,
          ),
        );
    if (interfaceLanguage != _lastInterfaceLanguage) {
      await _gateway.updateInterfaceLanguage(interfaceLanguage);
      if (_disposed) return;
      _lastInterfaceLanguage = interfaceLanguage;
    }
    if (!_sessionController.isLoggedIn) {
      await _gateway.clear();
      _lastPayload = null;
      return;
    }

    final timetable = _sessionController.timetable;
    final timelineItems = _sessionController.timelineItems;
    final snapshot = buildBnbuWidgetSnapshot(
      timetable: timetable,
      timelineItems: timelineItems,
      taCourses: _taCourseController.entries,
      now: _now(),
      interfaceLanguage: interfaceLanguage,
    );
    final payloadData = snapshot.toJson();
    payloadData['liveActivity'] = _liveActivityController.toJson();
    final payload = jsonEncode(payloadData);
    if (payload == _lastPayload) return;
    await _gateway.update(payload);
    _lastPayload = payload;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    if (_started) {
      _sessionController.removeListener(_scheduleSync);
      _taCourseController.removeListener(_scheduleSync);
      _liveActivityController.removeListener(_scheduleSync);
      _languageController?.removeListener(_scheduleSync);
    }
  }
}
