import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';

void main() {
  test('cookie wire map preserves security attributes and expiry', () {
    final expiresAt = DateTime.utc(2027, 1, 2, 3, 4, 5);
    final cookie = WebSessionCookie(
      name: 'session',
      value: 'opaque-value',
      domain: 'mis.bnbu.edu.cn',
      path: '/',
      hostOnly: true,
      secure: true,
      httpOnly: true,
      sameSite: 'lax',
      expiresAt: expiresAt,
    );

    expect(cookie.toMap(), <String, Object?>{
      'name': 'session',
      'value': 'opaque-value',
      'domain': 'mis.bnbu.edu.cn',
      'path': '/',
      'hostOnly': true,
      'secure': true,
      'httpOnly': true,
      'sameSite': 'lax',
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    });
  });

  test('session collections are immutable snapshots', () {
    final sourceCookies = <WebSessionCookie>[
      const WebSessionCookie(
        name: 'session',
        value: 'opaque-value',
        domain: 'portal.bnbu.edu.cn',
        path: '/',
        hostOnly: true,
        secure: true,
        httpOnly: true,
      ),
    ];
    final sourceOrigins = <String>['https://portal.bnbu.edu.cn'];
    final sourceDomains = <String>['bnbu.edu.cn'];
    final snapshot = WebSessionSnapshot(
      baseUrl: 'https://portal.bnbu.edu.cn',
      cookies: sourceCookies,
      allowedOrigins: sourceOrigins,
      allowedDomains: sourceDomains,
      useEphemeralSession: true,
    );

    sourceCookies.clear();
    sourceOrigins.clear();
    sourceDomains.clear();

    expect(snapshot.cookies, hasLength(1));
    expect(snapshot.allowedOrigins, <String>['https://portal.bnbu.edu.cn']);
    expect(snapshot.allowedDomains, <String>['bnbu.edu.cn']);
    expect(() => snapshot.cookies.clear(), throwsUnsupportedError);
    expect(() => snapshot.allowedOrigins.clear(), throwsUnsupportedError);
    expect(() => snapshot.allowedDomains.clear(), throwsUnsupportedError);
  });

  test('native cookie maps are parsed with bounded security attributes', () {
    final expiresAt = DateTime.utc(2027, 1, 2, 3, 4, 5);
    final cookie = WebSessionCookie.tryFromMap(<String, Object?>{
      'name': 'session',
      'value': 'rotated-value',
      'domain': 'MIS.BNBU.EDU.CN',
      'path': '/mis',
      'hostOnly': true,
      'secure': true,
      'httpOnly': true,
      'sameSite': 'Lax',
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    });

    expect(cookie, isNotNull);
    expect(cookie!.domain, 'mis.bnbu.edu.cn');
    expect(cookie.path, '/mis');
    expect(cookie.sameSite, 'lax');
    expect(cookie.expiresAt, expiresAt);
  });

  test('native cookie maps reject controls and invalid paths', () {
    expect(
      WebSessionCookie.tryFromMap(<String, Object?>{
        'name': 'session\nInjected',
        'value': 'opaque',
        'domain': 'mis.bnbu.edu.cn',
        'path': '/',
        'hostOnly': true,
        'secure': true,
        'httpOnly': true,
      }),
      isNull,
    );
    expect(
      WebSessionCookie.tryFromMap(<String, Object?>{
        'name': 'session',
        'value': 'opaque',
        'domain': 'mis.bnbu.edu.cn',
        'path': 'mis',
        'hostOnly': true,
        'secure': true,
        'httpOnly': true,
      }),
      isNull,
    );
  });

  test('allowed origins default to the session base URL', () {
    final snapshot = WebSessionSnapshot(
      baseUrl: 'https://mis.bnbu.edu.cn',
      cookies: const <WebSessionCookie>[],
    );

    expect(snapshot.allowedOrigins, <String>['https://mis.bnbu.edu.cn']);
    expect(snapshot.allowedDomains, isEmpty);
    expect(snapshot.useEphemeralSession, isFalse);
  });
}
