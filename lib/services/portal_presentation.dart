import 'dart:convert';

import 'package:flutter/services.dart';

import '../l10n/bnbu_localizations.dart';

/// Bundled, presentation-only adapter for the school unified Portal.
///
/// It reflows the existing document for a phone viewport. It never reads form
/// values, cookies or storage, never creates a school control, and never
/// performs navigation, submission or a network request.
class PortalPresentation {
  PortalPresentation._(this._script, this._css);

  final String _script;
  final String _css;

  static Future<PortalPresentation> load() async {
    final assets = await Future.wait([
      rootBundle.loadString('assets/portal/layout.js', cache: false),
      rootBundle.loadString('assets/portal/layout.css', cache: false),
    ]);
    return PortalPresentation._(assets[0], assets[1]);
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
        'more': localizations?.text('更多') ?? 'More',
      })});';

  /// Section titles the adapter may re-label when it recognizes the Portal
  /// shell. Unknown structures are left with their school-provided text.
  static const _labels = <String, String>{
    'My Application': '我的申请',
    'My Favorites': '我的收藏',
    'Announcements': '通知公告',
    'My To-do': '我的待办',
    'My Schedule': '我的课表',
    'Quick Links': '快捷入口',
  };
}
