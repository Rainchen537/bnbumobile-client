import '../../models/assistant_models.dart';

class AssistantLocalNavigation {
  const AssistantLocalNavigation(this.type, this.targetId);
  final AssistantActionType type;
  final String targetId;

  static AssistantLocalNavigation? parse(
    String message,
    Set<AssistantActionType> availableActions,
  ) {
    final text = message
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[。.!！]$'), '')
        .trim();
    final match =
        RegExp(r'^(?:请|請)?(?:打开|打開|进入|進入|带我去|帶我去)\s*(.+)$').firstMatch(text) ??
        RegExp(
          r'^(?:please )?(?:open|go to|take me to) (?:the )?(.+)$',
        ).firstMatch(text);
    if (match == null) return null;
    final target = match[1]!.trim().replaceAll(RegExp(r'\s+'), ' ');
    const campus = {
      '校历': 'academic_calendar',
      '校曆': 'academic_calendar',
      '官方校历': 'academic_calendar',
      '官方校曆': 'academic_calendar',
      '校历 pdf': 'academic_calendar',
      '官方校历 pdf': 'academic_calendar',
      'academic calendar': 'academic_calendar',
      'academic calendar pdf': 'academic_calendar',
      'official academic calendar': 'academic_calendar',
      'official academic calendar pdf': 'academic_calendar',
      '课程计划': 'class_schedule',
      '課程計劃': 'class_schedule',
      '官方课程计划': 'class_schedule',
      '官方课程计划 pdf': 'class_schedule',
      'class schedule pdf': 'class_schedule',
      'official class schedule pdf': 'class_schedule',
      '请假申请': 'leave',
      '請假申請': 'leave',
      'leave application': 'leave',
      'ecard': 'ecard',
      '我的ecard': 'ecard',
      'my ecard': 'ecard',
    };
    const tabs = {
      '首页': 'home',
      '首頁': 'home',
      'home': 'home',
      '邮箱': 'mail',
      '郵箱': 'mail',
      'mail': 'mail',
      'ispace': 'ispace',
      '课表': 'schedule',
      '課表': 'schedule',
      'timetable': 'schedule',
      '我的': 'user',
      'profile': 'user',
    };
    final campusId = campus[target];
    if (campusId != null &&
        availableActions.contains(AssistantActionType.openCampusPage)) {
      return AssistantLocalNavigation(
        AssistantActionType.openCampusPage,
        campusId,
      );
    }
    final tabId = tabs[target];
    if (tabId != null &&
        availableActions.contains(AssistantActionType.openAppTab)) {
      return AssistantLocalNavigation(AssistantActionType.openAppTab, tabId);
    }
    return null;
  }
}
