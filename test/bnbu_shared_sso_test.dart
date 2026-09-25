import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_sm/dart_sm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/services/bnbu_mis_client.dart';
import 'package:bnbu_me/services/moodle_api_client.dart';

void main() {
  for (final failure in [
    '503',
    'socket',
    'expired',
    'tls-interruption',
    'certificate',
  ]) {
    test(
      'iSpace Web $failure preserves or explicitly renews the same session',
      () async {
        final http = _MoodleWebHttp();
        final client = MoodleApiClient(webHttpClient: http);
        addTearDown(client.dispose);
        await client.prepareWebSession(
          username: 'student',
          password: 'test-only',
        );
        expect(http.passwordPosts, 1);
        http.failure = failure;
        final pending = client.prepareWebSession(
          username: 'student',
          password: 'test-only',
        );
        if (failure == 'expired') {
          await pending;
          expect(http.passwordPosts, 2);
        } else {
          await expectLater(pending, throwsA(isA<MoodleApiException>()));
          expect(http.passwordPosts, 1);
          http.failure = '';
          await client.prepareWebSession(
            username: 'student',
            password: 'test-only',
          );
          expect(http.passwordPosts, 1);
        }
      },
    );
  }
  for (final failProbe in [true, false]) {
    test(
      'MIS ${failProbe ? 'probe' : 'launch'} failure keeps the Portal SSO',
      () async {
        final http = _SchoolHttp();
        final client = BnbuMisClient(httpClient: http);
        addTearDown(client.dispose);
        await client.fetchPortalAccountProfile(
          username: 'student',
          password: 'test-only',
        );
        http.target = 'mis';
        await client.prepareOfficialWebSession(
          target: OfficialWebTarget.mis,
          username: 'student',
          password: 'test-only',
        );
        expect(http.passwordPosts, 1);
        if (!failProbe) {
          await client.invalidateOfficialWebSession(OfficialWebTarget.mis);
        }
        http.unavailable = true;
        await expectLater(
          client.prepareOfficialWebSession(
            target: OfficialWebTarget.mis,
            username: 'student',
            password: 'test-only',
          ),
          throwsA(isA<BnbuMisException>()),
        );
        expect(http.passwordPosts, 1);
        http.unavailable = false;
        await client.prepareOfficialWebSession(
          target: OfficialWebTarget.mis,
          username: 'student',
          password: 'test-only',
        );
        expect(http.passwordPosts, 1);
      },
    );
  }
  for (final failProbe in [true, false]) {
    test(
      'Portal ${failProbe ? 'probe' : 'launch'} 503 preserves shared SSO credentials',
      () async {
        final http = _SchoolHttp();
        final client = BnbuMisClient(httpClient: http);
        addTearDown(client.dispose);
        await client.fetchPortalAccountProfile(
          username: 'student',
          password: 'test-only',
        );
        expect(http.passwordPosts, 1);
        if (!failProbe) {
          await client.invalidateOfficialWebSession(OfficialWebTarget.portal);
        }
        http.unavailable = true;
        await expectLater(
          client.fetchPortalAccountProfile(
            username: 'student',
            password: 'test-only',
          ),
          throwsA(isA<BnbuMisException>()),
        );
        expect(
          http.passwordPosts,
          1,
          reason: 'A service outage does not prove SSO expiry',
        );
        http.unavailable = false;
        await client.fetchPortalAccountProfile(
          username: 'student',
          password: 'test-only',
        );
        expect(http.passwordPosts, 1);
      },
    );
  }
  test(
    'explicit SSO expiry rebuilds once and subsequent calls reuse it',
    () async {
      final http = _SchoolHttp();
      final client = BnbuMisClient(httpClient: http);
      addTearDown(client.dispose);
      await client.fetchPortalAccountProfile(
        username: 'student',
        password: 'test-only',
      );
      await client.invalidateOfficialWebSession(OfficialWebTarget.portal);
      http.expired = true;
      await client.fetchPortalAccountProfile(
        username: 'student',
        password: 'test-only',
      );
      await client.fetchPortalAccountProfile(
        username: 'student',
        password: 'test-only',
      );
      expect(http.passwordPosts, 2);
    },
  );
}

class _SchoolHttp implements HttpClient {
  final publicKey = SM2.generateKeyPair().publicKey;
  int passwordPosts = 0;
  bool unavailable = false;
  bool expired = false;
  String target = 'portal';
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (url.path.endsWith('/getSm2PubK')) {
      return _Request(_Response(jsonEncode({'data': publicKey.substring(2)})));
    }
    if (method == 'POST' && url.path.endsWith('/tencent/login')) {
      passwordPosts++;
      expired = false;
      return _Request(_Response('{"data":{"success":true}}'));
    }
    if (url.path.contains('/auth/sso/') ||
        url.host.startsWith('portal.') ||
        url.host.startsWith('mis.')) {
      if (unavailable) {
        return _Request(_Response('Unavailable', statusCode: 503));
      }
      if (expired) {
        return _Request(_Response('<form>统一认证登录 password login</form>'));
      }
      if (url.path.contains('/auth/sso/')) {
        return _Request(
          _Response(
            '',
            statusCode: 302,
            headers: {
              'location': target == 'mis'
                  ? 'https://mis.bnbu.edu.cn/mis/usr/index.do'
                  : 'https://portal.bnbu.edu.cn/wui/index.html',
            },
          ),
        );
      }
      if (url.path.endsWith('/getAccountList')) {
        return _Request(
          _Response(
            '{"status":"1","data":{"username":"Student","deptname":"Data Science"}}',
          ),
        );
      }
    }
    return _Request(_Response('<html>BNBU MIS</html>'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  _Headers([Map<String, String> values = const {}]) : values = Map.of(values);
  final Map<String, String> values;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  ContentType? get contentType => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.body, {
    this.statusCode = 200,
    Map<String, String> headers = const {},
  }) : headers = _Headers(headers);
  final String body;
  @override
  final int statusCode;
  @override
  final _Headers headers;
  @override
  List<Cookie> get cookies => [
    Cookie('session', 'synthetic')
      ..path = '/'
      ..secure = true,
  ];
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final _Headers headers = _Headers();
  @override
  final List<Cookie> cookies = [];
  @override
  bool followRedirects = true;
  @override
  void write(Object? value) {}
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MoodleWebHttp implements HttpClient {
  int passwordPosts = 0;
  String failure = '';
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (method == 'POST') {
      passwordPosts++;
      failure = '';
      return _Request(_MoodleResponse('Dashboard'));
    }
    if (url.path == '/my/') {
      if (failure == 'socket') throw const SocketException('offline');
      if (failure == 'tls-interruption') {
        throw const HandshakeException(
          'Connection terminated during handshake',
        );
      }
      if (failure == 'certificate') {
        throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
      }
      if (failure == '503') {
        return _Request(_MoodleResponse('Unavailable', statusCode: 503));
      }
      if (failure == 'expired') {
        return _Request(
          _MoodleResponse(
            '<form id="login"><input name="logintoken" value="renew-token"><input name="password"></form>',
          ),
        );
      }
      return _Request(_MoodleResponse('Dashboard'));
    }
    return _Request(
      _MoodleResponse('<input name="logintoken" value="test-login-token">'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MoodleResponse extends _Response {
  _MoodleResponse(super.body, {super.statusCode});
  @override
  List<Cookie> get cookies => [
    Cookie('MoodleSession', 'test-cookie')
      ..path = '/'
      ..secure = true,
  ];
}
