class WebSessionCookie {
  const WebSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    required this.httpOnly,
    this.sameSite,
    this.expiresAt,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final bool httpOnly;
  final String? sameSite;
  final DateTime? expiresAt;

  static WebSessionCookie? tryFromMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final name = value['name'];
    final cookieValue = value['value'];
    final domain = value['domain'];
    final path = value['path'];
    final hostOnly = value['hostOnly'];
    final secure = value['secure'];
    final httpOnly = value['httpOnly'];
    final sameSite = value['sameSite'];
    final expiresAt = value['expiresAt'];
    if (name is! String ||
        cookieValue is! String ||
        domain is! String ||
        path is! String ||
        hostOnly is! bool ||
        secure is! bool ||
        httpOnly is! bool ||
        (sameSite != null && sameSite is! String) ||
        (expiresAt != null && expiresAt is! num)) {
      return null;
    }
    final normalizedName = name.trim();
    final normalizedDomain = domain.trim().toLowerCase();
    final normalizedPath = path.trim();
    final normalizedSameSite = (sameSite as String?)?.trim().toLowerCase();
    if (normalizedName.isEmpty ||
        normalizedName.length > 256 ||
        cookieValue.length > 8192 ||
        normalizedDomain.isEmpty ||
        normalizedDomain.length > 253 ||
        normalizedPath.isEmpty ||
        normalizedPath.length > 2048 ||
        !normalizedPath.startsWith('/') ||
        normalizedPath.contains(';') ||
        _containsControl(normalizedName) ||
        _containsControl(cookieValue) ||
        _containsControl(normalizedDomain) ||
        _containsControl(normalizedPath) ||
        (normalizedSameSite != null &&
            normalizedSameSite != 'lax' &&
            normalizedSameSite != 'strict' &&
            normalizedSameSite != 'none')) {
      return null;
    }
    final expiry = expiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt(), isUtc: true);
    return WebSessionCookie(
      name: normalizedName,
      value: cookieValue,
      domain: normalizedDomain,
      path: normalizedPath,
      hostOnly: hostOnly,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: normalizedSameSite,
      expiresAt: expiry,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
      'hostOnly': hostOnly,
      'secure': secure,
      'httpOnly': httpOnly,
      'sameSite': sameSite,
      'expiresAt': expiresAt?.millisecondsSinceEpoch,
    };
  }

  static bool _containsControl(String value) {
    return value.codeUnits.any(
      (codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f,
    );
  }
}

class WebSessionSnapshot {
  WebSessionSnapshot({
    required this.baseUrl,
    required List<WebSessionCookie> cookies,
    List<String>? allowedOrigins,
    List<String> allowedDomains = const <String>[],
    this.useEphemeralSession = false,
  }) : cookies = List<WebSessionCookie>.unmodifiable(cookies),
       allowedOrigins = List<String>.unmodifiable(
         allowedOrigins ?? <String>[baseUrl],
       ),
       allowedDomains = List<String>.unmodifiable(allowedDomains);

  final String baseUrl;
  final List<WebSessionCookie> cookies;
  final List<String> allowedOrigins;
  final List<String> allowedDomains;
  final bool useEphemeralSession;
}
