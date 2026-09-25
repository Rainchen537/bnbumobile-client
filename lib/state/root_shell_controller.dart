import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assistant_models.dart';
import '../models/timetable_data.dart';

enum AppTab { home, mail, ispace, schedule, user }

class ScheduleCourseFocusRequest {
  const ScheduleCourseFocusRequest({
    required this.id,
    required this.course,
    required this.meeting,
    required this.startsAt,
  });

  final int id;
  final TimetableCourse course;
  final TimetableMeeting meeting;
  final DateTime startsAt;
}

class RootShellController extends ChangeNotifier {
  RootShellController({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _navigationExpandedPreferenceKey =
      'shell.navigation_expanded.v1';

  final Future<SharedPreferences> Function() _preferencesLoader;
  AppTab _selectedTab = AppTab.home;
  bool _navigationExpanded = true;
  int _scheduleCourseRequestSequence = 0;
  ScheduleCourseFocusRequest? _scheduleCourseRequest;
  ({int id, DateTime? date, String view})? scheduleViewRequest;

  AppTab get selectedTab => _selectedTab;
  int get selectedIndex => _selectedTab.index;
  bool get navigationExpanded => _navigationExpanded;
  ScheduleCourseFocusRequest? get scheduleCourseRequest =>
      _scheduleCourseRequest;

  Future<void> restoreNavigationPreference() async {
    try {
      final preferences = await _preferencesLoader();
      final restored = preferences.getBool(_navigationExpandedPreferenceKey);
      if (restored != null && restored != _navigationExpanded) {
        _navigationExpanded = restored;
        notifyListeners();
      }
    } catch (_) {
      // A cosmetic desktop preference must never block the app shell.
    }
  }

  void toggleNavigationExpanded() {
    setNavigationExpanded(!_navigationExpanded);
  }

  void setNavigationExpanded(bool value) {
    if (value == _navigationExpanded) {
      return;
    }
    _navigationExpanded = value;
    notifyListeners();
    unawaited(_persistNavigationPreference());
  }

  Future<void> _persistNavigationPreference() async {
    try {
      final preferences = await _preferencesLoader();
      await preferences.setBool(
        _navigationExpandedPreferenceKey,
        _navigationExpanded,
      );
    } catch (_) {
      // The in-memory collapse state remains usable if persistence fails.
    }
  }

  void selectTab(AppTab tab) {
    if (_selectedTab == tab) {
      return;
    }
    _selectedTab = tab;
    notifyListeners();
  }

  void selectIndex(int index) {
    if (index < 0 || index >= AppTab.values.length) {
      return;
    }
    selectTab(AppTab.values[index]);
  }

  void openScheduleCourse({
    required TimetableCourse course,
    required TimetableMeeting meeting,
    required DateTime startsAt,
  }) {
    _scheduleCourseRequestSequence += 1;
    _scheduleCourseRequest = ScheduleCourseFocusRequest(
      id: _scheduleCourseRequestSequence,
      course: course,
      meeting: meeting,
      startsAt: startsAt,
    );
    _selectedTab = AppTab.schedule;
    notifyListeners();
  }

  void openScheduleView({DateTime? date, String view = ''}) {
    if (!{'', 'horizontal', 'vertical'}.contains(view)) {
      throw ArgumentError.value(view);
    }
    _scheduleCourseRequest = null;
    scheduleViewRequest = (
      id: ++_scheduleCourseRequestSequence,
      date: date,
      view: view,
    );
    _selectedTab = AppTab.schedule;
    notifyListeners();
  }

  void reset() {
    scheduleViewRequest = null;
    _scheduleCourseRequest = null;
    selectTab(AppTab.home);
  }

  AssistantCurrentPageContext currentPageContext() {
    return switch (_selectedTab) {
      AppTab.home => const AssistantCurrentPageContext(
        pageType: 'home',
        title: '首页',
      ),
      AppTab.mail => const AssistantCurrentPageContext(
        pageType: 'mail',
        title: '邮箱',
      ),
      AppTab.ispace => const AssistantCurrentPageContext(
        pageType: 'ispace',
        title: 'iSpace',
      ),
      AppTab.schedule => const AssistantCurrentPageContext(
        pageType: 'schedule',
        title: '课表',
      ),
      AppTab.user => const AssistantCurrentPageContext(
        pageType: 'user',
        title: '我的',
      ),
    };
  }
}
