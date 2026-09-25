import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/course_archive_service.dart';

void main() {
  late Directory temp;
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('course_fetch_test_'),
  );
  tearDown(() => temp.delete(recursive: true));
  Future<int> fetch(
    _Client client, {
    int budget = 100,
    bool Function()? active,
  }) => SecureCourseArchiveFileFetcher(client: client).fetch(
    url: Uri.parse('https://ispace.example.edu/pluginfile.php/1/slides.pdf'),
    origin: Uri.parse('https://ispace.example.edu'),
    cookieHeader: 'MoodleSession=test',
    destination: File('${temp.path}/file'),
    remainingBytes: budget,
    sessionIsActive: active ?? () => true,
  );

  test(
    'follows same-origin redirect with cookies and writes exact file bytes',
    () async {
      final client = _Client([
        _Response(
          [],
          status: 302,
          headers: {'location': '/pluginfile.php/2/slides.pdf'},
        ),
        _Response([1, 2, 3]),
      ]);
      expect(await fetch(client), 3);
      expect(client.urls.last.path, '/pluginfile.php/2/slides.pdf');
      expect(client.requests.every((r) => !r.followRedirects), isTrue);
      expect(
        client.requests.map((r) => r.headers.value('cookie')),
        everyElement('MoodleSession=test'),
      );
      expect(await File('${temp.path}/file').readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'foreign redirect is blocked before any cookie reaches foreign origin',
    () async {
      final client = _Client([
        _Response(
          [],
          status: 302,
          headers: {'location': 'https://evil.example/file.pdf'},
        ),
      ]);
      await expectLater(fetch(client), throwsA(isA<CourseArchiveException>()));
      expect(client.urls.length, 1);
      expect(await File('${temp.path}/file').exists(), isFalse);
    },
  );

  for (final mime in ['text/html', 'application/xhtml+xml']) {
    test(
      'rejects $mime rather than saving an error page as courseware',
      () async {
        final client = _Client([
          _Response(
            utf8.encode('<html>Denied</html>'),
            headers: {'content-type': mime},
          ),
        ]);
        await expectLater(
          fetch(client),
          throwsA(isA<CourseArchiveException>()),
        );
        expect(await File('${temp.path}/file').exists(), isFalse);
      },
    );
  }
  test('detects disguised login HTML in an octet-stream response', () async {
    final client = _Client([
      _Response(utf8.encode('<form><input type="password"></form>')),
    ]);
    await expectLater(fetch(client), throwsA(isA<CourseArchiveException>()));
  });
  test('HTML error pages do not falsely instruct the user to log in', () async {
    for (final login in [true, false]) {
      final client = _Client([
        _Response(
          utf8.encode(
            login
                ? '<form><input type="password"></form>'
                : '<html>Page content</html>',
          ),
          headers: {'content-type': 'text/html'},
        ),
      ]);
      await expectLater(
        fetch(client),
        throwsA(
          isA<CourseArchiveException>().having(
            (e) => e.message,
            'safe reason',
            login ? contains('登录状态已失效') : isNot(contains('登录')),
          ),
        ),
      );
    }
  });
  test('bounds both declared and streamed payload sizes', () async {
    for (final declared in [10, -1]) {
      final client = _Client([
        _Response(List.filled(10, 1), declaredLength: declared),
      ]);
      await expectLater(
        fetch(client, budget: 5),
        throwsA(isA<CourseArchiveException>()),
      );
    }
  });
  test('inactive account sends no request', () async {
    final client = _Client([]);
    await expectLater(
      fetch(client, active: () => false),
      throwsA(isA<CourseArchiveException>()),
    );
    expect(client.urls, isEmpty);
  });
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
  ContentType? get contentType => values['content-type'] == null
      ? null
      : ContentType.parse(values['content-type']!);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.bytes, {
    this.status = 200,
    Map<String, String> headers = const {},
    this.declaredLength,
  }) : headers = _Headers(headers);
  final List<int> bytes;
  final int status;
  final int? declaredLength;
  @override
  final _Headers headers;
  @override
  int get statusCode => status;
  @override
  int get contentLength => declaredLength ?? bytes.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([bytes]).listen(
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
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.responses);
  final List<_Response> responses;
  final List<Uri> urls = [];
  final List<_Request> requests = [];
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    final request = _Request(responses.removeAt(0));
    requests.add(request);
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
