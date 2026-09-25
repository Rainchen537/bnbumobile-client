import 'dart:convert';

import 'package:flutter/services.dart';

import '../l10n/bnbu_localizations.dart';

/// Bundled, presentation-only adapter. Never transports school form values.
class LeaveApplicationPresentation {
  LeaveApplicationPresentation._(this._script, this._css);

  final String _script;
  final String _css;

  static Future<LeaveApplicationPresentation> load() async {
    final assets = await Future.wait([
      rootBundle.loadString('assets/leave_application/layout.js', cache: false),
      rootBundle.loadString(
        'assets/leave_application/layout.css',
        cache: false,
      ),
    ]);
    return LeaveApplicationPresentation._(assets[0], assets[1]);
  }

  String script({
    required Uri portal,
    required bool enabled,
    required bool dark,
    BnbuLocalizations? localizations,
  }) =>
      '$_script(${jsonEncode({
        'origin': portal.origin,
        'enabled': enabled,
        'dark': dark,
        'css': _css,
        'labels': localizations == null || localizations.isEnglish ? const <String, String>{} : {for (final entry in _labels.entries) entry.key: localizations.text(entry.value)},
        'expand': localizations?.text('展开') ?? 'Expand',
        'collapse': localizations?.text('收起') ?? 'Collapse',
      })});';

  static const _labels = {
    'Leave Application': '请假申请',
    'Semester': '学期',
    'Application Opening Period': '申请开放时间',
    'Applicant': '申请人资料',
    'Chinese Name': '中文姓名',
    'English Name': '英文姓名',
    'Student No.': '学号',
    'School/Faculty': '学院',
    'Programme': '专业',
    'Application Time': '申请时间',
    'Mobile Phone No.': '手机号码',
    'Family Contact No.': '家人联系电话',
    'Details of leave application': '请假详情',
    'Last Begin Date of Leave': '上次请假开始日期',
    'Last Begin Time of Leave': '上次请假开始时间',
    'Last End Date of Leave': '上次请假结束日期',
    'Last End Time of Leave': '上次请假结束时间',
    'Begin Dates of Leave': '开始日期',
    'Begin Date of Leave': '开始日期',
    'Begin Time of Leave': '开始时间',
    'End Date of Leave': '结束日期',
    'End Time of Leave': '结束时间',
    'Total calendar day(s)': '请假天数',
    'Reason': '请假类型',
    'Reason Details': '请假原因',
    'Attachment': '证明材料',
    'Courses and teachers': '涉及课程与教师',
    'Comments of approval': '审批意见',
  };
}
