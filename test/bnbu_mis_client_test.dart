import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/services/bnbu_mis_client.dart';

void main() {
  test('MIS reports explicit certificate verification failure', () async {
    final client = BnbuMisClient(httpClient: _HandshakeHttpClient());
    addTearDown(client.dispose);

    await expectLater(
      client.fetchTimetable(username: 'student', password: 'password'),
      throwsA(
        isA<BnbuMisException>().having(
          (error) => error.message,
          'message',
          contains('证书校验失败'),
        ),
      ),
    );
  });

  test(
    'MIS handshake interruption is retryable and is not a certificate verdict',
    () async {
      final client = BnbuMisClient(
        httpClient: _HandshakeHttpClient(
          const HandshakeException('Connection terminated during handshake'),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.fetchTimetable(username: 'student', password: 'test-only'),
        throwsA(
          isA<BnbuMisException>()
              .having((e) => e.message, 'message', isNot(contains('证书')))
              .having((e) => e.isRetryable, 'retryable', isTrue)
              .having(
                (e) => e.requiresReauthentication,
                'reauthentication',
                isFalse,
              ),
        ),
      );
    },
  );

  group('MIS exam timetable discovery', () {
    late BnbuMisClient client;

    setUp(() {
      client = BnbuMisClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('discovers the authenticated Exam Timetable link', () {
      final uri = client.examTimetableUriForTesting(
        pageUri: Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
        body: '''
          <a href="/mis/student/exam/timetable.do">Exam Timetable</a>
        ''',
      );

      expect(
        uri,
        Uri.parse('https://mis.bnbu.edu.cn/mis/student/exam/timetable.do'),
      );
    });

    test('accepts a same-origin onclick target with the Chinese label', () {
      final uri = client.examTimetableUriForTesting(
        pageUri: Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
        body: '''
          <a onclick="openPage('/mis/student/exam/list.do')">考试安排</a>
        ''',
      );

      expect(
        uri,
        Uri.parse('https://mis.bnbu.edu.cn/mis/student/exam/list.do'),
      );
    });

    test('rejects an exam link outside the exact MIS origin', () {
      final uri = client.examTimetableUriForTesting(
        pageUri: Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
        body: '''
          <a href="https://mis.bnbu.edu.cn.evil.example/exam.do">
            Exam Timetable
          </a>
        ''',
      );

      expect(uri, isNull);
    });

    test('keeps exam discovery on the exact HTTPS port', () {
      final rejected = client.examTimetableUriForTesting(
        pageUri: Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
        body: '''
          <a href="https://mis.bnbu.edu.cn:8443/mis/student/exam/list.do">
            Exam Timetable
          </a>
        ''',
      );
      final accepted = client.examTimetableUriForTesting(
        pageUri: Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
        body: '''
          <a href="https://mis.bnbu.edu.cn:443/mis/student/exam/list.do">
            Exam Timetable
          </a>
        ''',
      );

      expect(rejected, isNull);
      expect(accepted?.path, '/mis/student/exam/list.do');
      expect(accepted?.port, 443);
    });

    test('does not misclassify a failed MIS index as an empty exam page', () {
      expect(client.examTimetableIndexErrorForTesting(200), isNull);

      final unavailable = client.examTimetableIndexErrorForTesting(503);
      expect(unavailable, isNotNull);
      expect(unavailable?.isRetryable, isTrue);
      expect(unavailable?.requiresReauthentication, isFalse);

      final unauthorized = client.examTimetableIndexErrorForTesting(401);
      expect(unauthorized, isNotNull);
      expect(unauthorized?.requiresReauthentication, isTrue);

      final forbidden = client.examTimetableIndexErrorForTesting(403);
      expect(forbidden, isNotNull);
      expect(forbidden?.requiresReauthentication, isTrue);

      final expiredPage = client.examTimetablePageErrorForTesting(401);
      expect(expiredPage, isNotNull);
      expect(expiredPage?.requiresReauthentication, isTrue);
    });
  });

  group('MIS session response recovery', () {
    late BnbuMisClient client;

    setUp(() {
      client = BnbuMisClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('recognizes redirected SSO and login HTML as expired sessions', () {
      expect(
        client.timetableResponseNeedsSessionRebuildForTesting(
          uri: Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
          body: '<html><title>统一身份认证</title></html>',
        ),
        isTrue,
      );
      expect(
        client.timetableResponseNeedsSessionRebuildForTesting(
          uri: Uri.parse(
            'https://mis.bnbu.edu.cn/mis/student/tts/timetable_min.do',
          ),
          body:
              '<form action="/auth/pwd/tencent/login"><input type="password"></form>',
        ),
        isTrue,
      );
      for (final body in <String>[
        '<html>登录超时，请先登录</html>',
        '<script>window.alert("会话已过期")</script>',
        '<html>Session expired</html>',
      ]) {
        expect(
          client.timetableResponseNeedsSessionRebuildForTesting(
            uri: Uri.parse(
              'https://mis.bnbu.edu.cn/mis/student/tts/timetable_min.do',
            ),
            body: body,
          ),
          isTrue,
        );
      }
    });

    test('does not rebuild an authenticated MIS timetable response', () {
      expect(
        client.timetableResponseNeedsSessionRebuildForTesting(
          uri: Uri.parse(
            'https://mis.bnbu.edu.cn/mis/student/tts/timetable_min.do',
          ),
          body: '<table><tr><td>COMP1001</td><td>C Language</td></tr></table>',
        ),
        isFalse,
      );
    });
  });

  group('Portal authentication validation', () {
    late BnbuMisClient client;

    setUp(() {
      client = BnbuMisClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('requires an authenticated account response', () {
      expect(
        client.portalAccountResponseIsAuthenticatedForTesting(
          const <String, dynamic>{
            'status': '1',
            'data': <String, dynamic>{'lastname': 'Student'},
          },
        ),
        isTrue,
      );
      expect(
        client.portalAccountResponseIsAuthenticatedForTesting(
          const <String, dynamic>{'status': '0', 'data': <String, dynamic>{}},
        ),
        isFalse,
      );
      expect(
        client.portalAccountResponseIsAuthenticatedForTesting(
          const <String, dynamic>{'status': '1', 'data': <String, dynamic>{}},
        ),
        isFalse,
      );
    });

    test('keeps student portraits on the exact Portal origin', () {
      expect(
        client.portalAvatarUriForTesting(
          '/weaver/weaver.file.FileDownload?fileid=123',
        ),
        Uri.parse(
          'https://portal.bnbu.edu.cn/weaver/weaver.file.FileDownload?fileid=123',
        ),
      );
      expect(
        client.portalAvatarUriForTesting(
          'http://portal.bnbu.edu.cn/images/student.jpg',
        ),
        Uri.parse('https://portal.bnbu.edu.cn:443/images/student.jpg'),
      );
      expect(
        client.portalAvatarUriForTesting(
          'https://portal.bnbu.edu.cn.evil.example/student.jpg',
        ),
        isNull,
      );
      expect(
        client.portalAvatarUriForTesting(
          'https://student:password@portal.bnbu.edu.cn/student.jpg',
        ),
        isNull,
      );
    });
  });

  group('MIS redirect credential isolation', () {
    late BnbuMisClient client;

    setUp(() {
      client = BnbuMisClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('rejects cross-origin redirects that preserve a request body', () {
      expect(
        () => client.redirectRequestForTesting(
          method: 'POST',
          currentUri: Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
          targetUri: Uri.parse('https://attacker.example/collect'),
          statusCode: HttpStatus.temporaryRedirect,
          body: '{"password":"secret"}',
          headers: const <String, String>{
            HttpHeaders.contentTypeHeader: 'application/json',
          },
        ),
        throwsA(isA<BnbuMisException>()),
      );
    });

    test('rejects cross-origin 308 redirects that preserve a body', () {
      expect(
        () => client.redirectRequestForTesting(
          method: 'POST',
          currentUri: Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
          targetUri: Uri.parse('https://attacker.example/collect'),
          statusCode: HttpStatus.permanentRedirect,
          body: '{"password":"secret"}',
        ),
        throwsA(isA<BnbuMisException>()),
      );
    });

    test('keeps request bodies on same-origin 307 redirects', () {
      final redirect = client.redirectRequestForTesting(
        method: 'POST',
        currentUri: Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
        targetUri: Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
        statusCode: HttpStatus.temporaryRedirect,
        body: '{"step":1}',
        headers: const <String, String>{
          HttpHeaders.contentTypeHeader: 'application/json',
        },
      );

      expect(redirect.method, 'POST');
      expect(redirect.body, '{"step":1}');
      expect(
        redirect.headers[HttpHeaders.contentTypeHeader],
        'application/json',
      );
    });

    test('drops sensitive headers after a safe cross-origin POST redirect', () {
      final redirect = client.redirectRequestForTesting(
        method: 'POST',
        currentUri: Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
        targetUri: Uri.parse('https://mis.bnbu.edu.cn/home'),
        statusCode: HttpStatus.found,
        body: 'ticket=temporary',
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer secret',
          HttpHeaders.cookieHeader: 'session=secret',
          HttpHeaders.refererHeader: 'https://sso.bnbu.edu.cn/auth/login',
          HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
          HttpHeaders.acceptHeader: 'text/html',
          'Origin': 'https://sso.bnbu.edu.cn',
        },
      );

      expect(redirect.method, 'GET');
      expect(redirect.body, isNull);
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.authorizationHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.cookieHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.refererHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.contentTypeHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('origin')),
      );
      expect(redirect.headers[HttpHeaders.acceptHeader], 'text/html');
    });

    test('allows only configured HTTPS school origins', () {
      for (final value in <String>[
        'https://sso.bnbu.edu.cn/auth/login',
        'https://mis.bnbu.edu.cn/mis/usr/index.do',
        'https://portal.bnbu.edu.cn/wui/index.html',
      ]) {
        expect(client.isTrustedRequestUriForTesting(Uri.parse(value)), isTrue);
      }
      for (final value in <String>[
        'http://sso.bnbu.edu.cn/auth/login',
        'https://www.bnbu.edu.cn/',
        'https://sso.bnbu.edu.cn.evil.example/auth/login',
        'https://user@sso.bnbu.edu.cn/auth/login',
        'https://sso.bnbu.edu.cn:444/auth/login',
      ]) {
        expect(client.isTrustedRequestUriForTesting(Uri.parse(value)), isFalse);
      }
    });
  });

  group('MIS cookie isolation', () {
    late BnbuMisClient client;

    setUp(() {
      client = BnbuMisClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('honors host-only, path, and secure cookie scope', () {
      final cookie = Cookie('session', 'secret')
        ..path = '/auth'
        ..secure = true;
      client.storeCookieForTesting(
        cookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );

      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
        ),
        'session=secret',
      );
      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sso.bnbu.edu.cn/profile'),
        ),
        isEmpty,
      );
      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sub.sso.bnbu.edu.cn/auth/continue'),
        ),
        isEmpty,
      );
      expect(
        client.cookieHeaderForTesting(
          Uri.parse('http://sso.bnbu.edu.cn/auth/continue'),
        ),
        isEmpty,
      );
    });

    test('rejects a cookie scoped to an unrelated domain', () {
      final cookie = Cookie('session', 'secret')
        ..domain = 'attacker.example'
        ..path = '/';
      client.storeCookieForTesting(
        cookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );

      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://attacker.example/collect'),
        ),
        isEmpty,
      );
    });

    test('allows the trusted parent domain and rejects public suffixes', () {
      final parentCookie = Cookie('parent', 'allowed')
        ..domain = 'bnbu.edu.cn'
        ..path = '/';
      client.storeCookieForTesting(
        parentCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );
      final publicSuffixCookie = Cookie('suffix', 'secret')
        ..domain = 'cn'
        ..path = '/';
      client.storeCookieForTesting(
        publicSuffixCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );

      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
        ),
        'parent=allowed',
      );
      expect(
        client.cookieHeaderForTesting(Uri.parse('https://portal.bnbu.edu.cn/')),
        'parent=allowed',
      );
    });

    test('narrows exported cookies to the target host', () {
      final parentCookie = Cookie('parent', 'opaque-parent')
        ..domain = 'bnbu.edu.cn'
        ..path = '/'
        ..secure = true
        ..httpOnly = true
        ..sameSite = SameSite.lax
        ..expires = DateTime.now().add(const Duration(days: 1));
      client.storeCookieForTesting(
        parentCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );
      client.storeCookieForTesting(
        Cookie('sso-only', 'opaque-sso')..path = '/',
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );
      final authPathCookie = Cookie('auth-path', 'opaque-auth')
        ..domain = 'bnbu.edu.cn'
        ..path = '/auth';
      client.storeCookieForTesting(
        authPathCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );
      client.storeCookieForTesting(
        Cookie('portal-only', 'opaque-portal')..path = '/',
        Uri.parse('https://portal.bnbu.edu.cn/wui/index.html'),
      );

      final snapshot = client.officialWebSessionForTesting(
        OfficialWebTarget.mis,
      );

      expect(
        client.hasTargetHostCookieForTesting(OfficialWebTarget.mis),
        isFalse,
        reason: 'SSO parent cookies alone must not be treated as a MIS session',
      );
      expect(snapshot.baseUrl, 'https://mis.bnbu.edu.cn');
      expect(snapshot.allowedOrigins, <String>['https://mis.bnbu.edu.cn']);
      expect(snapshot.allowedDomains, isEmpty);
      expect(snapshot.useEphemeralSession, isTrue);
      expect(snapshot.cookies, hasLength(1));
      final exported = snapshot.cookies.single;
      expect(exported.name, 'parent');
      expect(exported.value, 'opaque-parent');
      expect(exported.domain, 'mis.bnbu.edu.cn');
      expect(exported.hostOnly, isTrue);
      expect(exported.secure, isTrue);
      expect(exported.httpOnly, isTrue);
      expect(exported.sameSite, 'lax');
      expect(exported.expiresAt, isNotNull);
    });

    test('deduplicates cookies after narrowing them to the target host', () {
      final parentCookie = Cookie('session', 'parent-value')
        ..domain = 'bnbu.edu.cn'
        ..path = '/';
      client.storeCookieForTesting(
        parentCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );
      client.storeCookieForTesting(
        Cookie('session', 'portal-value')..path = '/',
        Uri.parse('https://portal.bnbu.edu.cn/wui/index.html'),
      );

      expect(
        client.hasTargetHostCookieForTesting(OfficialWebTarget.portal),
        isTrue,
      );
      final snapshot = client.officialWebSessionForTesting(
        OfficialWebTarget.portal,
      );

      expect(snapshot.cookies, hasLength(1));
      expect(snapshot.cookies.single.name, 'session');
      expect(snapshot.cookies.single.value, 'portal-value');
      expect(snapshot.cookies.single.domain, 'portal.bnbu.edu.cn');
      expect(snapshot.cookies.single.hostOnly, isTrue);
    });

    test('invalidates only the requested official system session', () async {
      final parentCookie = Cookie('sso', 'shared')
        ..domain = 'bnbu.edu.cn'
        ..path = '/'
        ..secure = true;
      client.storeCookieForTesting(
        parentCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );
      client.storeCookieForTesting(
        Cookie('mis-session', 'mis-old')
          ..path = '/mis'
          ..secure = true,
        Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
      );
      client.storeCookieForTesting(
        Cookie('portal-session', 'portal-current')
          ..path = '/'
          ..secure = true,
        Uri.parse('https://portal.bnbu.edu.cn/wui/index.html'),
      );

      await client.invalidateOfficialWebSession(OfficialWebTarget.mis);

      final misCookies = client.cookieHeaderForTesting(
        Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
      );
      final portalCookies = client.cookieHeaderForTesting(
        Uri.parse('https://portal.bnbu.edu.cn/wui/index.html'),
      );
      expect(misCookies, contains('sso=shared'));
      expect(misCookies, isNot(contains('mis-session=mis-old')));
      expect(portalCookies, contains('sso=shared'));
      expect(portalCookies, contains('portal-session=portal-current'));
    });

    test(
      'reconciles rotated MIS cookies without duplicating parent SSO',
      () async {
        final parentCookie = Cookie('sso', 'shared')
          ..domain = 'bnbu.edu.cn'
          ..path = '/'
          ..secure = true;
        client.storeCookieForTesting(
          parentCookie,
          Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
        );
        client.storeCookieForTesting(
          Cookie('mis-session', 'mis-old')
            ..path = '/mis'
            ..secure = true
            ..httpOnly = true,
          Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
        );

        await client.reconcileOfficialWebSession(
          target: OfficialWebTarget.mis,
          cookies: const <WebSessionCookie>[
            WebSessionCookie(
              name: 'sso',
              value: 'webview-copy',
              domain: 'mis.bnbu.edu.cn',
              path: '/',
              hostOnly: true,
              secure: true,
              httpOnly: true,
            ),
            WebSessionCookie(
              name: 'mis-session',
              value: 'mis-rotated',
              domain: 'mis.bnbu.edu.cn',
              path: '/mis',
              hostOnly: true,
              secure: true,
              httpOnly: true,
            ),
          ],
        );

        final ssoCookies = client.cookieHeaderForTesting(
          Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
        );
        final misCookies = client.cookieHeaderForTesting(
          Uri.parse('https://mis.bnbu.edu.cn/mis/usr/index.do'),
        );
        expect(ssoCookies, 'sso=shared');
        expect(misCookies, contains('sso=shared'));
        expect(misCookies, contains('mis-session=mis-rotated'));
        expect(misCookies, isNot(contains('sso=webview-copy')));
        expect(misCookies, isNot(contains('mis-session=mis-old')));
      },
    );
  });
}

class _HandshakeHttpClient implements HttpClient {
  _HandshakeHttpClient([
    this.error = const HandshakeException('missing issuer'),
  ]);
  final HandshakeException error;
  @override
  set connectionTimeout(Duration? value) {}

  @override
  set idleTimeout(Duration value) {}

  @override
  set maxConnectionsPerHost(int? value) {}

  @override
  set userAgent(String? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return Future<HttpClientRequest>.error(error);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
