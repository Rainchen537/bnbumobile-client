import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CIS client stays centrally owned without widening other school-client allowlists',
    () {
      final constructors = RegExp(r'\bCisCheckinClient\s*\(');
      final violations = _libSources().entries
          .where(
            (entry) =>
                constructors.hasMatch(entry.value) &&
                entry.key != 'lib/services/cis_checkin_client.dart' &&
                entry.key != 'lib/state/app_session_controller.dart',
          )
          .map((entry) => entry.key);
      expect(violations, isEmpty);
    },
  );
  test('school session clients have one production owner', () {
    final sources = _libSources();
    final forbiddenConstructors = <String, RegExp>{
      'BnbuMisClient': RegExp(r'\bBnbuMisClient\s*\('),
      'MoodleApiClient': RegExp(r'\bMoodleApiClient\s*\('),
      'SecureCredentialStore': RegExp(r'\bSecureCredentialStore\s*\('),
    };
    final allowedFiles = <String>{
      'lib/state/app_session_controller.dart',
      'lib/services/bnbu_mis_client.dart',
      'lib/services/moodle_api_client.dart',
      'lib/services/credential_store.dart',
    };

    final violations = <String>[];
    for (final entry in sources.entries) {
      if (allowedFiles.contains(entry.key)) continue;
      for (final constructor in forbiddenConstructors.entries) {
        if (constructor.value.hasMatch(entry.value)) {
          violations.add('${entry.key}: ${constructor.key}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '学校登录客户端只能由 AppSessionController 持有；新功能必须依赖现有控制器。',
    );
  });

  test('only app roots may create an AppSessionController', () {
    final sources = _libSources();
    final constructor = RegExp(
      r'\bAppSessionController(?:\.studyWindow)?\s*\(',
    );
    final allowedFiles = <String>{
      'lib/main.dart',
      'lib/pages/study_window_app.dart',
      'lib/state/app_session_controller.dart',
    };

    final violations = sources.entries
        .where(
          (entry) =>
              !allowedFiles.contains(entry.key) &&
              constructor.hasMatch(entry.value),
        )
        .map((entry) => entry.key)
        .toList(growable: false);

    expect(violations, isEmpty, reason: '页面和功能模块不得创建第二套 AppSessionController。');
    expect(
      sources['lib/pages/study_window_app.dart'],
      contains('AppSessionController.studyWindow()'),
      reason: '桌面学业子窗口必须使用禁止 MIS/Portal 现场登录的受限作用域。',
    );
  });

  test(
    'raw school login calls stay behind AppSessionController and clients',
    () {
      final sources = _libSources();
      final rawOperations = RegExp(
        r'\b(loginWithPassword|fetchTimetable|fetchExamTimetable|'
        r'fetchPortalAccountProfile|fetchPortalAccountAvatar)\s*\(',
      );
      final allowedFiles = <String>{
        'lib/state/app_session_controller.dart',
        'lib/services/bnbu_mis_client.dart',
        'lib/services/moodle_api_client.dart',
      };

      final violations = sources.entries
          .where(
            (entry) =>
                !allowedFiles.contains(entry.key) &&
                rawOperations.hasMatch(entry.value),
          )
          .map((entry) => entry.key)
          .toList(growable: false);

      expect(violations, isEmpty, reason: '业务代码必须通过统一会话控制器读取学校系统。');
    },
  );
}

Map<String, String> _libSources() {
  final root = Directory.current;
  final lib = Directory('${root.path}/lib');
  final sources = <String, String>{};
  for (final entity in lib.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relative = entity.path
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    sources[relative] = entity.readAsStringSync();
  }
  return sources;
}
