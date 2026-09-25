import '../config/app_config.dart';
import '../models/official_web_target.dart';
import '../models/web_session_snapshot.dart';

abstract final class OfficialUrlPolicy {
  static final Uri _ispaceOrigin = _configuredOrigin(
    AppConfig.ispaceBaseUrl,
    settingName: 'ISPACE_BASE_URL',
  );
  static final Uri _ssoOrigin = _configuredOrigin(
    AppConfig.bnbuSsoBaseUrl,
    settingName: 'BNBU_SSO_BASE_URL',
  );
  static final Uri _misOrigin = _configuredOrigin(
    AppConfig.bnbuMisBaseUrl,
    settingName: 'BNBU_MIS_BASE_URL',
  );
  static final Uri _portalOrigin = _configuredOrigin(
    AppConfig.bnbuPortalBaseUrl,
    settingName: 'BNBU_PORTAL_BASE_URL',
  );
  static final Uri _privacyOrigin = _originOf(
    AppConfig.normalizedHttpsUrl(
      AppConfig.privacyPolicyUrl,
      settingName: 'PRIVACY_POLICY_URL',
    ),
  );

  static Uri requireBnbuUrl(String rawUrl) {
    final uri = _parseHttpsUrl(rawUrl);
    if (targetFor(uri) != null || _isBnbuHost(uri.host, uri.port)) {
      return uri;
    }
    throw const FormatException('只能在应用内打开 BNBU 官方 HTTPS 页面。');
  }

  static Uri requireTrustedPageUrl(String rawUrl) {
    try {
      return requireBnbuUrl(rawUrl);
    } on FormatException {
      final uri = _parseHttpsUrl(rawUrl);
      if (_sameOrigin(uri, _privacyOrigin)) {
        return uri;
      }
      throw const FormatException('该页面不在应用内网页允许列表中。');
    }
  }

  static OfficialWebTarget? targetFor(Uri uri) {
    if (_sameOrigin(uri, _misOrigin)) {
      return OfficialWebTarget.mis;
    }
    if (_sameOrigin(uri, _portalOrigin)) {
      return OfficialWebTarget.portal;
    }
    return null;
  }

  static bool isIspaceUrl(Uri uri) => _sameOrigin(uri, _ispaceOrigin);

  /// Route to an existing session owner; never widen the source WebView policy.
  /// SSO entry links select a registered destination, not a ticket to replay.
  static Uri? schoolDestinationFor(String rawUrl) {
    final Uri uri;
    try {
      uri = _parseHttpsUrl(rawUrl);
    } on FormatException {
      return null;
    }
    if (targetFor(uri) != null || isIspaceUrl(uri)) return uri;
    if (!_sameOrigin(uri, _ssoOrigin)) return null;
    final services = uri.queryParametersAll['service'];
    for (final (service, destination) in [
      (AppConfig.bnbuMisServiceId, _misOrigin),
      (AppConfig.bnbuPortalServiceId, _portalOrigin),
    ]) {
      if (uri.path == '/auth/sso/ssoLogin' &&
          services?.length == 1 &&
          services!.single == service) {
        return destination;
      }
      if (uri.path == '/auth/sso/login/$service' &&
          (services == null ||
              (services.length == 1 && services.single == service))) {
        return destination;
      }
    }
    return null;
  }

  static bool isAuthenticationRedirectFor(
    String rawUrl,
    OfficialWebTarget target,
  ) {
    final Uri uri;
    try {
      uri = _parseHttpsUrl(rawUrl);
    } on FormatException {
      return false;
    }
    if (!_sameOrigin(uri, _ssoOrigin)) return false;
    if ((uri.path == '/' ||
            uri.path == '/login' ||
            uri.path.startsWith('/login/') ||
            uri.path == '/auth/login') &&
        !uri.queryParameters.containsKey('service')) {
      return true;
    }
    final destination = schoolDestinationFor(rawUrl);
    return destination != null && targetFor(destination) == target;
  }

  static Uri authenticatedEntryFor(OfficialWebTarget target, Uri requestedUri) {
    final expectedOrigin = switch (target) {
      OfficialWebTarget.mis => _misOrigin,
      OfficialWebTarget.portal => _portalOrigin,
    };
    if (!_sameOrigin(requestedUri, expectedOrigin)) {
      throw const FormatException('认证页面与学校系统来源不匹配。');
    }
    final isOriginRoot =
        (requestedUri.path.isEmpty || requestedUri.path == '/') &&
        !requestedUri.hasQuery &&
        !requestedUri.hasFragment;
    if (!isOriginRoot) {
      return requestedUri;
    }
    return expectedOrigin.resolve(switch (target) {
      OfficialWebTarget.mis => '/mis/usr/index.do',
      OfficialWebTarget.portal => '/wui/index.html',
    });
  }

  static WebSessionSnapshot publicSessionFor(Uri uri) {
    final origin = _originOf(uri.toString()).toString();
    final isBnbu = _isBnbuHost(uri.host, uri.port);
    return WebSessionSnapshot(
      baseUrl: origin,
      cookies: const <WebSessionCookie>[],
      allowedOrigins: <String>[origin],
      allowedDomains: isBnbu ? const <String>['bnbu.edu.cn'] : const <String>[],
      useEphemeralSession: true,
    );
  }

  static Uri _configuredOrigin(String value, {required String settingName}) {
    return _originOf(
      AppConfig.normalizedHttpsBaseUrl(value, settingName: settingName),
    );
  }

  static Uri _parseHttpsUrl(String rawUrl) {
    final normalized = rawUrl.trim();
    final uri = Uri.tryParse(normalized);
    if (normalized.isEmpty ||
        normalized.length > 4096 ||
        uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('只能在应用内打开有效的 HTTPS 页面。');
    }
    return uri;
  }

  static Uri _originOf(String value) {
    final uri = Uri.parse(value);
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
    );
  }

  static bool _isBnbuHost(String host, int port) {
    final normalizedHost = host.toLowerCase();
    return port == 443 &&
        (normalizedHost == 'bnbu.edu.cn' ||
            normalizedHost.endsWith('.bnbu.edu.cn'));
  }

  static bool _sameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.port == right.port;
  }
}
