import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiveActivityPreferenceController extends ChangeNotifier {
  LiveActivityPreferenceController({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const enabledPreferenceKey =
      'app.notifications.ios_live_activity_enabled';
  static const courseEnabledPreferenceKey =
      'app.notifications.ios_live_activity_course_enabled';
  static const deadlineEnabledPreferenceKey =
      'app.notifications.ios_live_activity_deadline_enabled';
  static const classLeadMinutesPreferenceKey =
      'app.notifications.ios_live_activity_class_lead_minutes';
  static const courseDismissAfterStartMinutesPreferenceKey =
      'app.notifications.ios_live_activity_course_dismiss_after_start_minutes';
  static const deadlineLeadMinutesPreferenceKey =
      'app.notifications.ios_live_activity_deadline_lead_minutes';
  static const legacyDeadlineLeadHoursPreferenceKey =
      'app.notifications.ios_live_activity_deadline_lead_hours';

  static const classLeadMinuteOptions = <int>[5, 10, 15, 30, 60, 120];
  static const deadlineLeadMinuteOptions = <int>[
    30,
    60,
    120,
    360,
    720,
    1440,
    2880,
  ];
  static const minimumCustomClassLeadMinutes = 5;
  static const maximumCustomClassLeadMinutes = 120;
  static const minimumCourseDismissAfterStartMinutes = 0;
  static const maximumCourseDismissAfterStartMinutes = 20;
  static const minimumCustomDeadlineLeadMinutes = 30;
  static const maximumCustomDeadlineLeadMinutes = 2880;

  final Future<SharedPreferences> Function() _preferencesLoader;

  bool _enabled = true;
  bool _courseEnabled = true;
  bool _deadlineEnabled = false;
  int _classLeadMinutes = 15;
  int _courseDismissAfterStartMinutes = 5;
  int _deadlineLeadMinutes = 720;
  int _generation = 0;
  Future<void> _pendingWrite = Future<void>.value();

  bool get enabled => _enabled;
  bool get courseEnabled => _courseEnabled;
  bool get deadlineEnabled => _deadlineEnabled;
  int get classLeadMinutes => _classLeadMinutes;
  int get courseDismissAfterStartMinutes => _courseDismissAfterStartMinutes;
  int get deadlineLeadMinutes => _deadlineLeadMinutes;

  Map<String, Object> toJson() => <String, Object>{
    'enabled': enabled,
    'courseEnabled': courseEnabled,
    'deadlineEnabled': deadlineEnabled,
    'classLeadMinutes': classLeadMinutes,
    'courseDismissAfterStartMinutes': courseDismissAfterStartMinutes,
    'deadlineLeadMinutes': deadlineLeadMinutes,
  };

  Future<void> restore() async {
    final generation = _generation;
    final preferences = await _preferencesLoader();
    if (generation != _generation) return;

    final restoredEnabled = preferences.getBool(enabledPreferenceKey) ?? true;
    var restoredClassLead = _validatedClassLead(
      preferences.getInt(classLeadMinutesPreferenceKey),
    );
    final restoredCourseDismissAfterStart = _validatedCourseDismissAfterStart(
      preferences.getInt(courseDismissAfterStartMinutesPreferenceKey),
    );
    final deadlineMinutes = preferences.getInt(
      deadlineLeadMinutesPreferenceKey,
    );
    final legacyDeadlineHours = preferences.getInt(
      legacyDeadlineLeadHoursPreferenceKey,
    );
    var restoredDeadlineLead = _validatedDeadlineLead(
      deadlineMinutes ??
          (legacyDeadlineHours == null ? null : legacyDeadlineHours * 60),
    );
    final storedCourseEnabled = preferences.getBool(courseEnabledPreferenceKey);
    final storedDeadlineEnabled = preferences.getBool(
      deadlineEnabledPreferenceKey,
    );
    final restoredCourseEnabled = storedCourseEnabled ?? restoredClassLead > 0;
    final hasStoredDeadlinePreference =
        deadlineMinutes != null || legacyDeadlineHours != null;
    final restoredDeadlineEnabled =
        storedDeadlineEnabled ??
        (hasStoredDeadlinePreference && restoredDeadlineLead > 0);
    if (restoredCourseEnabled && restoredClassLead == 0) {
      restoredClassLead = 15;
    }
    if (restoredDeadlineEnabled && restoredDeadlineLead == 0) {
      restoredDeadlineLead = 720;
    }
    if (_enabled == restoredEnabled &&
        _courseEnabled == restoredCourseEnabled &&
        _deadlineEnabled == restoredDeadlineEnabled &&
        _classLeadMinutes == restoredClassLead &&
        _courseDismissAfterStartMinutes == restoredCourseDismissAfterStart &&
        _deadlineLeadMinutes == restoredDeadlineLead) {
      return;
    }
    _enabled = restoredEnabled;
    _courseEnabled = restoredCourseEnabled;
    _deadlineEnabled = restoredDeadlineEnabled;
    _classLeadMinutes = restoredClassLead;
    _courseDismissAfterStartMinutes = restoredCourseDismissAfterStart;
    _deadlineLeadMinutes = restoredDeadlineLead;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) {
    _generation++;
    if (_enabled != value) {
      _enabled = value;
      notifyListeners();
    }
    return _write((preferences) async {
      await preferences.setBool(enabledPreferenceKey, value);
    });
  }

  Future<void> setCourseEnabled(bool value) {
    _generation++;
    final restoredLead = value && _classLeadMinutes == 0
        ? 15
        : _classLeadMinutes;
    if (_courseEnabled != value || _classLeadMinutes != restoredLead) {
      _courseEnabled = value;
      _classLeadMinutes = restoredLead;
      notifyListeners();
    }
    return _write((preferences) async {
      await preferences.setBool(courseEnabledPreferenceKey, value);
      await preferences.setInt(classLeadMinutesPreferenceKey, restoredLead);
    });
  }

  Future<void> setDeadlineEnabled(bool value) {
    _generation++;
    final restoredLead = value && _deadlineLeadMinutes == 0
        ? 720
        : _deadlineLeadMinutes;
    if (_deadlineEnabled != value || _deadlineLeadMinutes != restoredLead) {
      _deadlineEnabled = value;
      _deadlineLeadMinutes = restoredLead;
      notifyListeners();
    }
    return _write((preferences) async {
      await preferences.setBool(deadlineEnabledPreferenceKey, value);
      await preferences.setInt(deadlineLeadMinutesPreferenceKey, restoredLead);
    });
  }

  Future<void> setClassLeadMinutes(int value) {
    final validated = _validatedClassLead(value);
    final contentEnabled = validated > 0;
    _generation++;
    if (_classLeadMinutes != validated || _courseEnabled != contentEnabled) {
      _classLeadMinutes = validated;
      _courseEnabled = contentEnabled;
      notifyListeners();
    }
    return _write((preferences) async {
      await preferences.setInt(classLeadMinutesPreferenceKey, validated);
      await preferences.setBool(courseEnabledPreferenceKey, contentEnabled);
    });
  }

  Future<void> setDeadlineLeadMinutes(int value) {
    final validated = _validatedDeadlineLead(value);
    final contentEnabled = validated > 0;
    _generation++;
    if (_deadlineLeadMinutes != validated ||
        _deadlineEnabled != contentEnabled) {
      _deadlineLeadMinutes = validated;
      _deadlineEnabled = contentEnabled;
      notifyListeners();
    }
    return _write((preferences) async {
      await preferences.setInt(deadlineLeadMinutesPreferenceKey, validated);
      await preferences.setBool(deadlineEnabledPreferenceKey, contentEnabled);
    });
  }

  Future<void> setCourseDismissAfterStartMinutes(int value) {
    final validated = _validatedCourseDismissAfterStart(value);
    _generation++;
    if (_courseDismissAfterStartMinutes != validated) {
      _courseDismissAfterStartMinutes = validated;
      notifyListeners();
    }
    return _write((preferences) async {
      await preferences.setInt(
        courseDismissAfterStartMinutesPreferenceKey,
        validated,
      );
    });
  }

  Future<void> _write(
    Future<void> Function(SharedPreferences preferences) action,
  ) {
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      final preferences = await _preferencesLoader();
      await action(preferences);
    });
    return _pendingWrite;
  }

  static int _validatedClassLead(int? value) {
    if (value == 0) return 0;
    if (value != null && value > 0 && value < minimumCustomClassLeadMinutes) {
      return minimumCustomClassLeadMinutes;
    }
    if (value != null &&
        value >= minimumCustomClassLeadMinutes &&
        value <= maximumCustomClassLeadMinutes) {
      return value;
    }
    return 15;
  }

  static int _validatedDeadlineLead(int? value) {
    if (value == 0 ||
        (value != null &&
            value >= minimumCustomDeadlineLeadMinutes &&
            value <= maximumCustomDeadlineLeadMinutes)) {
      return value!;
    }
    return 720;
  }

  static int _validatedCourseDismissAfterStart(int? value) {
    if (value != null &&
        value >= minimumCourseDismissAfterStartMinutes &&
        value <= maximumCourseDismissAfterStartMinutes) {
      return value;
    }
    return 5;
  }
}
