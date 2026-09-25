import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/services/moodle_api_client.dart';

void main() {
  MoodleApiClient clientFor(
    Object response, {
    bool download = true,
    bool function = true,
    void Function(http.Request)? onRequest,
  }) {
    final client = MoodleApiClient(
      baseUrl: 'https://ispace.example.edu',
      client: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(jsonEncode(response), 200);
      }),
    );
    client.cacheRuntimeProfileForTesting(
      token: 'test-token',
      profile: MoodleRuntimeProfile(
        release: 'test',
        version: 'test',
        downloadFiles: download,
        uploadFiles: false,
        advancedFeatures: const {},
        userMaxUploadFileSize: 0,
        functionVersions: {
          if (function) 'mod_page_get_pages_by_courses': 'test',
        },
      ),
    );
    addTearDown(client.dispose);
    return client;
  }

  test('returns only allowed instances in the selected course', () async {
    final client = clientFor(
      {
        'pages': [
          {
            'id': 7,
            'course': 42,
            'content': '<a href="/pluginfile.php/1/a.pptx">A</a>',
          },
          {'id': 8, 'course': 42, 'content': 'not selected'},
          {'id': 9, 'course': 43, 'content': 'other course'},
        ],
      },
      onRequest: (request) {
        expect(
          request.bodyFields['wsfunction'],
          'mod_page_get_pages_by_courses',
        );
        expect(request.bodyFields['courseids[0]'], '42');
      },
    );
    final pages = await client.fetchCoursewarePageHtml(
      token: 'test-token',
      courseId: 42,
      allowedInstances: {7, 9},
    );
    expect(pages.keys, [7]);
    expect(pages[7], contains('a.pptx'));
  });

  for (final gate in ['download', 'function']) {
    test('denied $gate capability performs no HTTP request', () async {
      var requests = 0;
      final client = clientFor(
        {},
        download: gate != 'download',
        function: gate != 'function',
        onRequest: (_) => requests++,
      );
      await expectLater(
        client.fetchCoursewarePageHtml(
          token: 'test-token',
          courseId: 42,
          allowedInstances: {7},
        ),
        throwsA(isA<MoodleApiException>()),
      );
      expect(requests, 0);
    });
  }
  test('empty instance selection needs no HTTP request', () async {
    final client = clientFor({}, onRequest: (_) => fail('Unexpected request'));
    expect(
      await client.fetchCoursewarePageHtml(
        token: 'test-token',
        courseId: 42,
        allowedInstances: {},
      ),
      isEmpty,
    );
  });
  test('rejects missing page structure and oversized HTML', () async {
    for (final response in [
      {},
      {
        'pages': [
          {'id': 7, 'course': 42, 'content': 'x' * (1024 * 1024 + 1)},
        ],
      },
    ]) {
      final client = clientFor(response);
      await expectLater(
        client.fetchCoursewarePageHtml(
          token: 'test-token',
          courseId: 42,
          allowedInstances: {7},
        ),
        throwsA(isA<MoodleApiException>()),
      );
    }
  });
}
