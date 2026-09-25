import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/services/bnbu_mis_client.dart';
import 'package:dart_sm/dart_sm.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grade_report_parser_test.dart' show gradeReportFixture;

void main() {
  Future<void> read(BnbuMisClient client) async {
    final report = await client.fetchGradeReport(
      username: 'synthetic',
      password: ' test-only ',
    );
    expect(report.isAllAcademicYears, isTrue);
    expect(report.cumulativeGpa, 2.75);
  }

  test(
    'cold direct report, dynamic POST scope and shared MIS/Portal SSO',
    () async {
      final http = _SchoolHttp();
      final client = BnbuMisClient(httpClient: http);
      addTearDown(client.dispose);
      await read(client);
      expect(http.reportMethods, ['GET', 'POST']);
      expect(http.scopeBodies.single, {'id': 'scope +/&=all', 'button': 'Go'});
      expect(http.passwordPosts, 1);
      expect(
        http.paths.where((p) => p.contains('gradepublish')),
        everyElement(endsWith('/webReport.do')),
      );
      await client.prepareOfficialWebSession(
        target: OfficialWebTarget.portal,
        username: 'synthetic',
        password: ' test-only ',
      );
      await read(client);
      expect(http.passwordPosts, 1);
    },
  );
  test('already selected All needs no POST', () async {
    final http = _SchoolHttp()..alreadyAll = true;
    final client = BnbuMisClient(httpClient: http);
    addTearDown(client.dispose);
    await read(client);
    expect(http.reportMethods, ['GET']);
  });
  for (final method in ['GET', 'POST']) {
    for (final status in [200, 401, 403]) {
      test(
        '$method auth failure $status rebuilds once, re-reads dynamic scope',
        () async {
          final http = _SchoolHttp()
            ..failureMethod = method
            ..failureStatus = status
            ..failuresLeft = 1;
          final client = BnbuMisClient(httpClient: http);
          addTearDown(client.dispose);
          await read(client);
          expect(http.launches, 2);
          expect(http.passwordPosts, 1);
          expect(http.reportMethods.where((m) => m == 'GET'), hasLength(2));
          expect(http.scopeBodies.last['id'], 'renewed +/&=scope');
        },
      );
    }
    test('$method repeated expiration is bounded', () async {
      final http = _SchoolHttp()
        ..failureMethod = method
        ..failureStatus = 401
        ..failuresLeft = 10;
      final client = BnbuMisClient(httpClient: http);
      addTearDown(client.dispose);
      await expectLater(read(client), throwsA(isA<BnbuMisException>()));
      expect(http.launches, 2);
      expect(http.passwordPosts, 1);
    });
    test(
      '$method 503 login-like body does not rebuild or become empty',
      () async {
        final http = _SchoolHttp()
          ..failureMethod = method
          ..failureStatus = 503
          ..failuresLeft = 1;
        final client = BnbuMisClient(httpClient: http);
        addTearDown(client.dispose);
        await expectLater(
          read(client),
          throwsA(
            isA<BnbuMisException>().having(
              (e) => e.requiresReauthentication,
              'auth',
              false,
            ),
          ),
        );
        expect(http.launches, 1);
        expect(http.passwordPosts, 1);
        await read(client);
        expect(http.passwordPosts, 1);
      },
    );
    test('$method response exceeding 2 MiB is rejected', () async {
      final http = _SchoolHttp()..oversizeMethod = method;
      final client = BnbuMisClient(httpClient: http);
      addTearDown(client.dispose);
      await expectLater(read(client), throwsA(isA<BnbuMisException>()));
      expect(http.launches, 1);
    });
  }
  for (final invalid in ['year', 'missing', 'malformed']) {
    test('scope $invalid fails without falling back to current year', () async {
      final http = _SchoolHttp()..invalidScope = invalid;
      final client = BnbuMisClient(httpClient: http);
      addTearDown(client.dispose);
      await expectLater(read(client), throwsA(isA<BnbuMisException>()));
      expect(http.passwordPosts, 1);
      expect(http.launches, 1);
    });
  }
  test('report and existing consumers use the same serial queue', () async {
    final gate = Completer<void>();
    final http = _SchoolHttp()..reportGate = gate;
    final client = BnbuMisClient(httpClient: http);
    addTearDown(client.dispose);
    final report = read(client);
    await http.reportStarted.future;
    final portal = client.prepareOfficialWebSession(
      target: OfficialWebTarget.portal,
      username: 'synthetic',
      password: ' test-only ',
    );
    await Future<void>.delayed(Duration.zero);
    expect(http.paths.any((p) => p.contains('/wui/')), isFalse);
    gate.complete();
    await report;
    await portal;
    expect(http.passwordPosts, 1);
  });
}

class _SchoolHttp implements HttpClient {
  final publicKey = SM2.generateKeyPair().publicKey;
  int passwordPosts = 0;
  int launches = 0;
  bool alreadyAll = false;
  String failureMethod = '';
  int failureStatus = 200;
  int failuresLeft = 0;
  String oversizeMethod = '';
  String invalidScope = '';
  Completer<void>? reportGate;
  final reportStarted = Completer<void>();
  final paths = <String>[];
  final reportMethods = <String>[];
  final scopeBodies = <Map<String, String>>[];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    paths.add(url.path);
    if (url.path.endsWith('/getSm2PubK')) {
      return _Request(_Response(jsonEncode({'data': publicKey.substring(2)})));
    }
    if (url.path.endsWith('/tencent/login')) {
      passwordPosts++;
      return _Request(_Response('{"data":{"success":true}}'));
    }
    if (url.path.contains('/auth/sso/')) {
      launches++;
      final target =
          url.queryParameters['service'] == AppConfig.bnbuMisServiceId
          ? 'https://mis.bnbu.edu.cn/mis/usr/index.do'
          : 'https://portal.bnbu.edu.cn/wui/index.html';
      return _Request(
        _Response('', statusCode: 302, headers: {'location': target}),
      );
    }
    if (url.path.endsWith('/webReport.do')) {
      reportMethods.add(method);
      if (!reportStarted.isCompleted) reportStarted.complete();
      await reportGate?.future;
      var source = gradeReportFixture();
      if (launches > 1) {
        source = source.replaceAll(
          'scope +/&amp;=all',
          'renewed +/&amp;=scope',
        );
      }
      final year = source
          .replaceAll(' selected', '')
          .replaceAll('value="opaque-year"', 'value="opaque-year" selected');
      _Response response;
      if (method == failureMethod && failuresLeft-- > 0) {
        response = _Response(
          '<form>统一认证登录 password login</form>',
          statusCode: failureStatus,
        );
      } else if (method == oversizeMethod) {
        response = _Response('x' * (2 * 1024 * 1024 + 1));
      } else if (invalidScope == 'missing') {
        response = _Response(
          source.replaceAll('All Academic Years', 'Other scope'),
        );
      } else if (method == 'POST' && invalidScope == 'malformed') {
        response = _Response('<html>unrecognized</html>');
      } else {
        response = _Response(
          (method == 'GET' && !alreadyAll || invalidScope == 'year')
              ? year
              : source,
        );
      }
      return _Request(
        response,
        onBody: method == 'POST'
            ? (body) {
                expect(url.scheme, 'https');
                expect(url.host, 'mis.bnbu.edu.cn');
                scopeBodies.add(Uri.splitQueryString(body));
              }
            : null,
      );
    }
    if (url.path.endsWith('/getAccountList')) {
      return _Request(
        _Response('{"status":"1","data":{"username":"Synthetic"}}'),
      );
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
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value.toString();
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
  _Request(this.response, {this.onBody});
  final _Response response;
  final void Function(String)? onBody;
  @override
  final _Headers headers = _Headers();
  @override
  final List<Cookie> cookies = [];
  @override
  bool followRedirects = true;
  @override
  void write(Object? value) {
    if (onBody != null) {
      expect(
        headers.value(HttpHeaders.contentTypeHeader),
        'application/x-www-form-urlencoded',
      );
    }
    onBody?.call(value.toString());
  }

  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
