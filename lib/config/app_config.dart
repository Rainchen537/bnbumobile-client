abstract final class AppConfig {
  /// CIS is a separate authenticated school origin; never use the app backend.
  static const String bnbuCheckinBaseUrl = 'https://cis.bnbu.edu.cn';

  /// Keeps the completed study workspace implementation available while its
  /// user-facing entry points are temporarily withdrawn from normal builds.
  static const bool studyModeEnabled = bool.fromEnvironment(
    'STUDY_MODE_ENABLED',
    defaultValue: false,
  );

  static const String ispaceBaseUrl = String.fromEnvironment(
    'ISPACE_BASE_URL',
    defaultValue: 'https://ispace.bnbu.edu.cn',
  );

  static const String ispaceCookieDomain = String.fromEnvironment(
    'ISPACE_COOKIE_DOMAIN',
    defaultValue: 'ispace.bnbu.edu.cn',
  );

  static const String bnbuSsoBaseUrl = String.fromEnvironment(
    'BNBU_SSO_BASE_URL',
    defaultValue: 'https://sso.bnbu.edu.cn',
  );

  static const String bnbuMisBaseUrl = String.fromEnvironment(
    'BNBU_MIS_BASE_URL',
    defaultValue: 'https://mis.bnbu.edu.cn',
  );

  static const String bnbuPortalBaseUrl = String.fromEnvironment(
    'BNBU_PORTAL_BASE_URL',
    defaultValue: 'https://portal.bnbu.edu.cn',
  );

  static String get bnbuLeaveApplicationUrl =>
      '${normalizedBaseUrl(bnbuPortalBaseUrl)}'
      '/spa/workflow/static4form/index.html?_rdm=1619145184951'
      '#/main/workflow/req?iscreate=1&workflowid=57&_key=65c91c';

  static const String bnbuCookieDomain = String.fromEnvironment(
    'BNBU_COOKIE_DOMAIN',
    defaultValue: 'bnbu.edu.cn',
  );

  static const String bnbuMisServiceId = String.fromEnvironment(
    'BNBU_MIS_SERVICE_ID',
    defaultValue: '3bvkl8pks1ki04nirus0g',
  );

  static const String bnbuPortalServiceId = String.fromEnvironment(
    'BNBU_PORTAL_SERVICE_ID',
    defaultValue: 'na3j8azrv30vamqac8yg',
  );

  static const String mailIncomingServer = String.fromEnvironment(
    'BNBU_MAIL_IMAP_HOST',
    defaultValue: 'imap.exmail.qq.com',
  );

  static const String mailOutgoingServer = String.fromEnvironment(
    'BNBU_MAIL_SMTP_HOST',
    defaultValue: 'smtp.exmail.qq.com',
  );

  static const String mailWebBaseUrl = String.fromEnvironment(
    'BNBU_MAIL_WEB_BASE_URL',
    defaultValue: 'https://mail.bnbu.edu.cn',
  );

  static const String syncServiceBaseUrl = String.fromEnvironment(
    'SYNC_SERVICE_BASE_URL',
    defaultValue: 'https://api.bnbu.yunwai.cloud',
  );

  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://bnbu.yunwai.cloud/app-privacy.html',
  );

  static Uri get pageBackdropManifestUrl => Uri.parse(
    '${normalizedHttpsBaseUrl(syncServiceBaseUrl, settingName: 'SYNC_SERVICE_BASE_URL')}/v1/public/page-backgrounds',
  );

  static const String updateBaseUrl = String.fromEnvironment(
    'UPDATE_BASE_URL',
    defaultValue: 'https://bnbu.yunwai.cloud/updates',
  );

  static const Map<String, String> desktopUpdateTrustedReleasePublicKeys = {
    'release-bd0db0d7a868e6633b4f944b':
        'nO9YRqnNG72cWkrpHz6iNzwM0Uc9UH9fB8mtaTIgLeQ=',
  };

  static Uri get desktopUpdateArchiveUrl => Uri.parse(
    '${normalizedHttpsBaseUrl(updateBaseUrl, settingName: 'UPDATE_BASE_URL')}'
    '/desktop/app-archive.json',
  );

  static Uri get androidUpdateManifestUrl => Uri.parse(
    '${normalizedHttpsBaseUrl(updateBaseUrl, settingName: 'UPDATE_BASE_URL')}'
    '/android/stable.json',
  );

  static Uri get latestVersionManifestUrl => Uri.parse(
    '${normalizedHttpsBaseUrl(updateBaseUrl, settingName: 'UPDATE_BASE_URL')}'
    '/latest.json',
  );

  static const String duoduoWebBaseUrl = String.fromEnvironment(
    'DUODUO_WEB_BASE_URL',
    defaultValue: 'https://www.duoduo.link',
  );

  static const String duoduoPrivacyPolicyUrl = String.fromEnvironment(
    'DUODUO_PRIVACY_POLICY_URL',
    defaultValue: 'https://static.duoduo.link/privacy.html',
  );

  static String normalizedBaseUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  static String normalizedHttpsBaseUrl(
    String value, {
    required String settingName,
  }) {
    final normalized = normalizedBaseUrl(value);
    final uri = Uri.tryParse(normalized);
    final schemeSeparator = normalized.indexOf('://');
    final authorityStart = schemeSeparator < 0
        ? normalized.length
        : schemeSeparator + 3;
    var authorityEnd = normalized.length;
    for (final delimiter in ['/', '?', '#']) {
      final index = normalized.indexOf(delimiter, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    }
    final rawAuthority = normalized.substring(authorityStart, authorityEnd);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        rawAuthority.contains('@') ||
        normalized.contains('?') ||
        normalized.contains('#') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(
        '$settingName 必须是没有用户信息、查询参数或片段的有效 HTTPS Base URL。',
      );
    }
    return normalized;
  }

  static String normalizedHttpsUrl(
    String value, {
    required String settingName,
  }) {
    final normalized = value.trim();
    final uri = Uri.tryParse(normalized);
    final schemeSeparator = normalized.indexOf('://');
    final authorityStart = schemeSeparator < 0
        ? normalized.length
        : schemeSeparator + 3;
    var authorityEnd = normalized.length;
    for (final delimiter in ['/', '?', '#']) {
      final index = normalized.indexOf(delimiter, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    }
    final rawAuthority = normalized.substring(authorityStart, authorityEnd);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        rawAuthority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException('$settingName 必须是没有用户信息、查询参数或片段的有效 HTTPS URL。');
    }
    return normalized;
  }

  static String normalizedMailHost(
    String value, {
    required String settingName,
  }) {
    final normalized = value.trim().toLowerCase();
    final uri = Uri.tryParse('https://$normalized');
    if (normalized.isEmpty ||
        uri == null ||
        uri.host != normalized ||
        uri.hasPort ||
        uri.path.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw FormatException('$settingName 必须是有效的邮件服务器主机名。');
    }
    return normalized;
  }

  static String normalizedCookieDomain(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.+'), '')
        .replaceFirst(RegExp(r'\.+$'), '');
  }
}
