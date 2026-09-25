/// The allowlist for account habits. Additions require a ledger entry and matching server validation.
class AccountHabit {
  static const choices = <String, List<String>>{
    'ispace.dashboard.date_filter': [
      'all',
      'overdue',
      'next7Days',
      'next30Days',
      'next3Months',
      'next6Months',
    ],
    'ispace.dashboard.sort_mode': ['byDates', 'byCourses'],
    'ispace.course.view': [
      'sections',
      'assignments',
      'announcements',
      'files',
      'grades',
    ],
    'schedule.week_layout': ['grid', 'list'],
    'mail.sort_order': ['newestFirst', 'oldestFirst'],
    'mail.compose.signature': ['none', 'bnbu-me'],
    'app.appearance.theme_mode': ['system', 'light', 'dark'],
    'app.appearance.language_mode': [
      'chinese',
      'traditionalChinese',
      'english',
    ],
    'app.appearance.schedule_today_accent': ['blue', 'teal', 'amber', 'violet'],
  };
  static const flags = <String>{
    'schedule.show_deadlines',
    'mail.unread_only',
    'app.appearance.ios_liquid_glass_enabled',
    'app.appearance.schedule_today_highlight_enabled',
  };
  static void validate(String key, Object? value) {
    if (choices.containsKey(key)) {
      if (value is String && choices[key]!.contains(value)) return;
    } else if (flags.contains(key)) {
      if (value is bool) return;
    } else if (key == 'course_reminders.lead_minutes') {
      if (value is int && value >= 5 && value <= 120) return;
    } else if (key == 'study.organization_prompt') {
      if (value is String &&
          value.length <= 8000 &&
          !value.contains('\u0000')) {
        return;
      }
    } else if (key == 'deadline_reminders.policy') {
      if (value is Map &&
          value.keys.toSet().difference({
            'mode',
            'count',
            'leads',
            'quietStart',
            'quietEnd',
          }).isEmpty &&
          {'smart', 'fixed'}.contains(value['mode']) &&
          value['count'] is int &&
          value['count'] >= 1 &&
          value['count'] <= 3 &&
          value['leads'] is List &&
          (value['leads'] as List).isNotEmpty &&
          (value['leads'] as List).length <= 3 &&
          (value['leads'] as List).every(
            (v) => v is int && v >= 30 && v <= 2880,
          ) &&
          [
            'quietStart',
            'quietEnd',
          ].every((k) => value[k] is int && value[k] >= 0 && value[k] < 1440)) {
        return;
      }
    } else if (key == 'mail.radar.rules') {
      if (value is List &&
          value.length <= 100 &&
          value.every(
            (v) =>
                v is Map &&
                v.length == 3 &&
                v['sender'] is String &&
                (v['sender'] as String).length <= 320 &&
                v['category'] is String &&
                {
                  'direct',
                  'deadline',
                  'action',
                  'event',
                  'notice',
                  'system',
                  'lowPriority',
                }.contains(v['category']) &&
                v['enabled'] is bool,
          )) {
        return;
      }
    }
    throw FormatException('Invalid account habit: $key');
  }

  static Map<String, dynamic> validateSnapshot(Object? raw) {
    if (raw is! Map || raw.length > 40) {
      throw const FormatException('Invalid habits');
    }
    final values = raw.cast<String, dynamic>();
    for (final e in values.entries) {
      if (e.value is! Map ||
          (e.value as Map).length != 2 ||
          !{'explicit', 'legacy'}.contains(e.value['source'])) {
        throw const FormatException('Invalid habit source');
      }
      validate(e.key, e.value['value']);
    }
    return values;
  }
}
