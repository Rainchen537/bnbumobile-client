import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/course_grade_data.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/services/moodle_api_client.dart';
import 'package:bnbu_me/models/quiz_attempt_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';

void main() {
  test(
    'Feedback items preserve question order and decode real choice syntax',
    () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          expect(request.bodyFields['wsfunction'], 'mod_feedback_get_items');
          expect(request.bodyFields['courseid'], '42');
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'position': 2,
                  'itemnumber': 2,
                  'name': 'What would you improve?',
                  'typ': 'textarea',
                  'required': false,
                  'presentation': '80|5',
                },
                {
                  'position': 1,
                  'itemnumber': 1,
                  'name': '<p>Rate the session?</p>',
                  'typ': 'multichoice',
                  'required': true,
                  'presentation': 'r>>>>>Very &amp; useful|Not useful<<<<<1',
                },
              ],
              'warnings': [],
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'test-token',
        profile: _profileFor(['mod_feedback_get_items']),
      );
      final content = await client.readAssistantModuleText(
        token: 'test-token',
        courseId: 42,
        instanceId: 7,
        moduleType: 'feedback',
      );
      expect(content, startsWith('1. Rate the session?\nRequired: yes'));
      expect(
        content,
        contains('Answer type: single choice\n1) Very & useful\n2) Not useful'),
      );
      expect(
        content,
        contains(
          '2. What would you improve?\nRequired: no\nAnswer type: free text',
        ),
      );
      expect(content, isNot(contains('>>>>>')));
    },
  );

  test(
    'Feedback access warnings cannot become an empty questionnaire',
    () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'items': [],
              'warnings': [
                {'warningcode': 'nopermission', 'message': 'private detail'},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'test-token',
        profile: _profileFor(['mod_feedback_get_items']),
      );
      await expectLater(
        client.readAssistantModuleText(
          token: 'test-token',
          courseId: 42,
          instanceId: 7,
          moduleType: 'feedback',
        ),
        throwsA(isA<MoodleApiException>()),
      );
    },
  );

  test(
    'Page content keeps requirements beyond the old summary limit',
    () async {
      final source = 'A long requirement ' * 1000 + 'FINAL REQUIREMENT';
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          expect(
            request.bodyFields['wsfunction'],
            'mod_page_get_pages_by_courses',
          );
          return http.Response(
            jsonEncode({
              'pages': [
                {'id': 7, 'content': '<p>$source</p>'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'test-token',
        profile: _profileFor(['mod_page_get_pages_by_courses']),
      );
      final value = await client.readAssistantModuleText(
        token: 'test-token',
        courseId: 42,
        instanceId: 7,
        moduleType: 'page',
      );
      expect(value, contains('FINAL REQUIREMENT'));
    },
  );

  test('missing content capability prevents any network request', () async {
    var calls = 0;
    final client = MoodleApiClient(
      baseUrl: 'https://ispace.example.edu',
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    client.cacheRuntimeProfileForTesting(
      token: 'test-token',
      profile: _profileFor([]),
    );
    await expectLater(
      client.readAssistantModuleText(
        token: 'test-token',
        courseId: 42,
        instanceId: 7,
        moduleType: 'feedback',
      ),
      throwsA(isA<MoodleApiException>()),
    );
    expect(calls, 0);
  });

  test(
    'file content rejects cross-origin URLs before sending a token',
    () async {
      var calls = 0;
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          calls++;
          return http.Response('unsafe', 200);
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'test-token',
        profile: _profileFor([
          'core_course_get_contents',
          'core_files_get_files',
        ]),
      );
      await expectLater(
        client.readAssistantFile(
          token: 'test-token',
          fileUrl: 'https://example.test/pluginfile.php/1/file.pdf',
        ),
        throwsA(isA<MoodleApiException>()),
      );
      expect(calls, 0);
    },
  );

  group('login error classification', () {
    test('captures the token-scoped runtime capability profile', () async {
      final requestedFunctions = <String>[];
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login/token.php')) {
            return http.Response('{"token":"runtime-token"}', 200);
          }
          requestedFunctions.add(request.bodyFields['wsfunction'] ?? '');
          return http.Response(
            jsonEncode({
              'fullname': 'Test Student',
              'userid': 42,
              'release': '4.1.3+ (Build: 20230526)',
              'version': '2022112803.06',
              'downloadfiles': 1,
              'uploadfiles': 1,
              'usermaxuploadfilesize': 1048576,
              'functions': [
                {
                  'name': 'core_course_get_contents',
                  'version': '2022112803.06',
                },
              ],
              'advancedfeatures': [
                {'name': 'enablecompletion', 'value': 1},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);

      final session = await client.loginWithPassword(
        username: 'student',
        password: 'secret',
      );

      expect(requestedFunctions, ['core_webservice_get_site_info']);
      expect(session.runtimeProfile.release, '4.1.3+ (Build: 20230526)');
      expect(session.runtimeProfile.version, '2022112803.06');
      expect(
        session.runtimeProfile.supportsFunction('core_course_get_contents'),
        isTrue,
      );
      expect(session.runtimeProfile.downloadFiles, isTrue);
      expect(session.runtimeProfile.uploadFiles, isTrue);
      expect(
        session.runtimeProfile.advancedFeatureEnabled('enablecompletion'),
        isTrue,
      );
    });

    test('classifies only invalidlogin as an authentication failure', () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((_) async {
          return http.Response(
            '{"error":"Invalid login","errorcode":"invalidlogin"}',
            200,
          );
        }),
      );
      addTearDown(client.dispose);

      expect(
        () => client.loginWithPassword(username: 'student', password: 'wrong'),
        throwsA(isA<MoodleAuthenticationException>()),
      );
    });

    test('keeps service failures distinct from invalid credentials', () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((_) async {
          return http.Response(
            '{"error":"Service unavailable","errorcode":"servicenotavailable"}',
            200,
          );
        }),
      );
      addTearDown(client.dispose);

      expect(
        () => client.loginWithPassword(username: 'student', password: 'secret'),
        throwsA(
          isA<MoodleApiException>()
              .having(
                (error) => error,
                'runtime type',
                isNot(isA<MoodleAuthenticationException>()),
              )
              .having(
                (error) => error.message,
                'message',
                'Service unavailable',
              ),
        ),
      );
    });

    test('explains an iSpace origin mismatch without exposing its code', () {
      final client = MoodleApiClient(
        baseUrl: 'https://legacy-ispace.example.edu',
        client: MockClient((_) async {
          return http.Response(
            '{"error":"Invalid url or port.",'
            '"errorcode":"requirecorrectaccess"}',
            200,
          );
        }),
      );
      addTearDown(client.dispose);

      expect(
        () => client.loginWithPassword(username: 'student', password: 'secret'),
        throwsA(
          isA<MoodleApiException>().having(
            (error) => error.message,
            'message',
            'iSpace 登录地址与学校当前站点不一致，请更新客户端后重试。',
          ),
        ),
      );
    });

    test('marks temporary HTTP failures as retryable', () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.loginWithPassword(username: 'student', password: 'secret'),
        throwsA(
          isA<MoodleApiException>().having(
            (error) => error.isRetryable,
            'isRetryable',
            isTrue,
          ),
        ),
      );
    });

    test(
      'iSpace handshake interruption is a retryable connection error',
      () async {
        final client = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((_) async {
            throw const HandshakeException(
              'Connection terminated during handshake',
            );
          }),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.loginWithPassword(username: 'student', password: 'test-only'),
          throwsA(
            isA<MoodleApiException>()
                .having((e) => e.isRetryable, 'retryable', isTrue)
                .having((e) => e.message, 'message', isNot(contains('证书'))),
          ),
        );
      },
    );

    test('reports a missing TLS issuer without weakening verification', () {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((_) async {
          throw const HandshakeException('missing issuer');
        }),
      );
      addTearDown(client.dispose);

      expect(
        () => client.loginWithPassword(username: 'student', password: 'secret'),
        throwsA(
          isA<MoodleApiException>()
              .having(
                (error) => error.message,
                'message',
                '学校服务器证书校验失败，已停止连接，请稍后重试或联系学校。',
              )
              .having((error) => error.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });
  });

  test('reads only bounded course contacts for teacher names', () async {
    late Map<String, String> requestFields;
    final client = MoodleApiClient(
      baseUrl: 'https://ispace.example.edu',
      client: MockClient((request) async {
        requestFields = request.bodyFields;
        return http.Response(
          '{"courses":[{"id":42,"contacts":['
          '{"id":1,"fullname":"Teacher Chen"},'
          '{"id":2,"fullname":"Teacher Chen"},'
          '{"id":3,"displayname":"Teacher Li"}]}]}',
          200,
        );
      }),
    );
    addTearDown(client.dispose);
    client.cacheRuntimeProfileForTesting(
      token: 'test-token',
      profile: _profileFor(const ['core_course_get_courses_by_field']),
    );

    final teachers = await client.fetchCourseTeacherNames(
      token: 'test-token',
      courseId: 42,
    );

    expect(requestFields['wsfunction'], 'core_course_get_courses_by_field');
    expect(requestFields['field'], 'id');
    expect(requestFields['value'], '42');
    expect(teachers, ['Teacher Chen', 'Teacher Li']);
  });

  test('rejects an unavailable function before any network request', () async {
    var requestCount = 0;
    final client = MoodleApiClient(
      baseUrl: 'https://ispace.example.edu',
      client: MockClient((_) async {
        requestCount++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    client.cacheRuntimeProfileForTesting(
      token: 'test-token',
      profile: _profileFor(const ['core_course_get_contents']),
    );

    await expectLater(
      client.fetchCourseTeacherNames(token: 'test-token', courseId: 42),
      throwsA(
        isA<MoodleFeatureUnavailableException>().having(
          (error) => error.functionName,
          'functionName',
          'core_course_get_courses_by_field',
        ),
      ),
    );
    expect(requestCount, 0);
  });

  test('rejects a runtime profile bound to another token', () async {
    var requestCount = 0;
    final client = MoodleApiClient(
      baseUrl: 'https://ispace.example.edu',
      client: MockClient((_) async {
        requestCount++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    client.cacheRuntimeProfileForTesting(
      token: 'first-token',
      profile: _profileFor(const ['core_course_get_courses_by_field']),
    );

    await expectLater(
      client.fetchCourseTeacherNames(token: 'second-token', courseId: 42),
      throwsA(isA<MoodleFeatureUnavailableException>()),
    );
    expect(requestCount, 0);
  });

  group('web cookie isolation', () {
    late MoodleApiClient client;

    setUp(() {
      client = MoodleApiClient(baseUrl: 'https://ispace.example.edu');
    });

    tearDown(() {
      client.dispose();
    });

    test('sends host-only cookies only to the exact host and path', () {
      final cookie = Cookie('MoodleSession', 'session-secret')..path = '/login';
      client.cacheWebCookieForTesting(
        cookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/login/verify.php'),
        ),
        'MoodleSession=session-secret',
      );
      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/my/'),
        ),
        isEmpty,
      );
      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://cdn.ispace.example.edu/login/verify.php'),
        ),
        isEmpty,
      );
    });

    test('preserves host-only scope and replaces same-identity cookies', () {
      final domainCookie = Cookie('MoodleSession', 'old')
        ..domain = 'ispace.example.edu'
        ..path = '/';
      client.cacheWebCookieForTesting(
        domainCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );
      final expiresAt = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final hostOnlyCookie = Cookie('MoodleSession', 'new')
        ..path = '/'
        ..secure = true
        ..expires = expiresAt;
      client.cacheWebCookieForTesting(
        hostOnlyCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/my/'),
        ),
        'MoodleSession=new',
      );
      final cookies = client.webSessionCookiesForTesting(
        Uri.parse('https://ispace.example.edu'),
      );
      expect(cookies, hasLength(1));
      expect(cookies.single.hostOnly, isTrue);
      expect(cookies.single.secure, isTrue);
      expect(cookies.single.expiresAt, expiresAt);
      expect(cookies.single.toMap()['hostOnly'], isTrue);
      expect(cookies.single.toMap()['secure'], isTrue);
      expect(
        cookies.single.toMap()['expiresAt'],
        expiresAt.millisecondsSinceEpoch,
      );
    });

    test('deduplicates cookies after narrowing them to the iSpace host', () {
      final parentCookie = Cookie('MoodleSession', 'parent-value')
        ..domain = 'example.edu'
        ..path = '/';
      client.cacheWebCookieForTesting(
        parentCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );
      client.cacheWebCookieForTesting(
        Cookie('MoodleSession', 'ispace-value')..path = '/',
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      final cookies = client.webSessionCookiesForTesting(
        Uri.parse('https://ispace.example.edu'),
      );

      expect(cookies, hasLength(1));
      expect(cookies.single.name, 'MoodleSession');
      expect(cookies.single.value, 'ispace-value');
      expect(cookies.single.domain, 'ispace.example.edu');
      expect(cookies.single.hostOnly, isTrue);
    });

    test('does not cache cookies from an invalidated web operation', () {
      final operationGeneration = client.webSessionGenerationForTesting;
      client.clearWebSession();

      client.cacheWebCookieForTesting(
        Cookie('MoodleSession', 'late-value')..path = '/',
        Uri.parse('https://ispace.example.edu/login/index.php'),
        expectedGeneration: operationGeneration,
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/my/'),
        ),
        isEmpty,
      );
    });

    test('allows trusted parent domains and rejects public suffixes', () {
      final publicSuffixClient = MoodleApiClient(
        baseUrl: 'https://school.example.com',
        cookieDomain: 'example.com',
      );
      addTearDown(publicSuffixClient.dispose);
      final parentCookie = Cookie('parent', 'allowed')
        ..domain = 'example.com'
        ..path = '/';
      publicSuffixClient.cacheWebCookieForTesting(
        parentCookie,
        Uri.parse('https://school.example.com/login/index.php'),
      );
      final publicSuffixCookie = Cookie('session', 'secret')
        ..domain = 'com'
        ..path = '/';
      publicSuffixClient.cacheWebCookieForTesting(
        publicSuffixCookie,
        Uri.parse('https://school.example.com/login/index.php'),
      );

      expect(
        publicSuffixClient.webCookieHeaderForTesting(
          Uri.parse('https://school.example.com/my/'),
        ),
        'parent=allowed',
      );
      final snapshotCookies = publicSuffixClient.webSessionCookiesForTesting(
        Uri.parse('https://school.example.com'),
      );
      expect(snapshotCookies, hasLength(1));
      expect(snapshotCookies.single.domain, 'school.example.com');
      expect(snapshotCookies.single.hostOnly, isTrue);
      expect(
        publicSuffixClient.webCookieHeaderForTesting(
          Uri.parse('https://attacker.com/collect'),
        ),
        isEmpty,
      );
    });

    test('does not send secure or expired cookies ineligible for target', () {
      final secureCookie = Cookie('secure', 'value')
        ..path = '/'
        ..secure = true;
      client.cacheWebCookieForTesting(
        secureCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );
      final expiredCookie = Cookie('expired', 'value')
        ..path = '/'
        ..maxAge = 0;
      client.cacheWebCookieForTesting(
        expiredCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('http://ispace.example.edu/my/'),
        ),
        isEmpty,
      );
      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/my/'),
        ),
        'secure=value',
      );
    });

    test('rejects cookies scoped to an unrelated domain', () {
      final cookie = Cookie('session', 'secret')
        ..domain = 'attacker.example'
        ..path = '/';
      client.cacheWebCookieForTesting(
        cookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://attacker.example/collect'),
        ),
        isEmpty,
      );
    });
  });

  group('plugin file token decoration', () {
    late MoodleApiClient client;

    setUp(() {
      client = MoodleApiClient(baseUrl: 'https://ispace.example.edu');
    });

    tearDown(() {
      client.dispose();
    });

    test('adds the token to same-origin plugin files', () {
      expect(
        client.decoratePluginFileUrlWithTokenForTesting(
          'https://ispace.example.edu/pluginfile.php/1/report.pdf',
          token: 'student-token',
        ),
        'https://ispace.example.edu/pluginfile.php/1/report.pdf?token=student-token',
      );
    });

    test('does not leak the token to an external origin', () {
      expect(
        client.decoratePluginFileUrlWithTokenForTesting(
          'https://attacker.example/pluginfile.php/leak',
          token: 'student-token',
        ),
        'https://attacker.example/pluginfile.php/leak',
      );
    });

    test('does not treat a different port as the same origin', () {
      expect(
        client.decoratePluginFileUrlWithTokenForTesting(
          'https://ispace.example.edu:444/pluginfile.php/leak',
          token: 'student-token',
        ),
        'https://ispace.example.edu:444/pluginfile.php/leak',
      );
    });
  });

  group('quiz attempt API', () {
    late Map<String, String> savedFields;
    late MoodleApiClient client;

    setUp(() {
      savedFields = {};
      client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          final fields = request.bodyFields;
          return switch (fields['wsfunction']) {
            'mod_quiz_get_quiz_access_information' => http.Response(
              '{"canattempt":true,"preventaccessreasons":[],"warnings":[]}',
              200,
            ),
            'mod_quiz_get_attempt_access_information' => http.Response(
              '{"isfinished":false,"ispreflightcheckrequired":false,'
              '"preventnewattemptreasons":[],"warnings":[]}',
              200,
            ),
            'mod_quiz_get_user_attempts' => http.Response(
              '{"attempts":[{"id":77,"quiz":89055,"state":"inprogress"}]}',
              200,
            ),
            'mod_quiz_get_attempt_data' => http.Response(
              jsonEncode({
                'attempt': {'id': 77, 'state': 'inprogress'},
                'nextpage': -1,
                'questions': [
                  {
                    'slot': 1,
                    'type': 'multichoice',
                    'html': '''
                      <div class="que multichoice">
                        <span class="qno">1</span>
                        <div class="qtext">Which value is correct?</div>
                        <input type="hidden" name="q123:1_:sequencecheck" value="4">
                        <label for="q123_1_answer0">Option A</label>
                        <input id="q123_1_answer0" type="radio" name="q123:1_answer" value="0">
                        <label for="q123_1_answer1">Option B</label>
                        <input id="q123_1_answer1" type="radio" name="q123:1_answer" value="1">
                      </div>
                    ''',
                  },
                ],
              }),
              200,
            ),
            'mod_quiz_save_attempt' => (() {
              savedFields = Map.of(fields);
              return http.Response('{"status":true,"warnings":[]}', 200);
            })(),
            _ => http.Response(
              '{"exception":"invalid_parameter_exception"}',
              200,
            ),
          };
        }),
      );
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_quiz_get_user_attempts',
          'mod_quiz_get_quiz_access_information',
          'mod_quiz_get_attempt_access_information',
          'mod_quiz_get_attempt_data',
          'mod_quiz_save_attempt',
        ]),
      );
      addTearDown(client.dispose);
    });

    test(
      'parses only allowed answer fields and injects live sequencecheck',
      () async {
        final snapshot = await client.fetchQuizAttempt(
          token: 'token',
          item: _quizItem,
        );

        expect(snapshot.attemptId, 77);
        expect(snapshot.questions.single.prompt, 'Which value is correct?');
        expect(
          snapshot.questions.single.fields.single.options.map(
            (option) => option.label,
          ),
          ['Option A', 'Option B'],
        );

        await client.saveQuizAttempt(
          token: 'token',
          snapshot: snapshot,
          answers: const [
            QuizAnswerDraft(slot: 1, fieldName: 'q123:1_answer', value: '1'),
          ],
        );

        expect(savedFields['data[0][name]'], 'q123:1_answer');
        expect(savedFields['data[0][value]'], '1');
        expect(savedFields['data[1][name]'], 'q123:1_:sequencecheck');
        expect(savedFields['data[1][value]'], '4');
      },
    );

    test('rejects provider-invented Moodle form fields before write', () async {
      final snapshot = await client.fetchQuizAttempt(
        token: 'token',
        item: _quizItem,
      );

      await expectLater(
        client.saveQuizAttempt(
          token: 'token',
          snapshot: snapshot,
          answers: const [
            QuizAnswerDraft(slot: 1, fieldName: 'q123:1_hacked', value: '1'),
          ],
        ),
        throwsA(isA<MoodleApiException>()),
      );
      expect(savedFields, isEmpty);
    });

    test(
      'does not infer start permission when Moodle access denies it',
      () async {
        var startCalls = 0;
        final deniedClient = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((request) async {
            return switch (request.bodyFields['wsfunction']) {
              'mod_quiz_get_quiz_access_information' => http.Response(
                '{"canattempt":false,'
                '"preventaccessreasons":["The quiz is not available"],'
                '"warnings":[]}',
                200,
              ),
              'mod_quiz_get_attempt_access_information' => http.Response(
                '{"isfinished":false,"ispreflightcheckrequired":false,'
                '"preventnewattemptreasons":[],"warnings":[]}',
                200,
              ),
              'mod_quiz_get_user_attempts' => http.Response(
                '{"attempts":[],"warnings":[]}',
                200,
              ),
              'mod_quiz_start_attempt' => (() {
                startCalls++;
                return http.Response('{"attempt":{}}', 200);
              })(),
              _ => http.Response('{"warnings":[]}', 200),
            };
          }),
        );
        addTearDown(deniedClient.dispose);
        deniedClient.cacheRuntimeProfileForTesting(
          token: 'token',
          profile: _profileFor(const [
            'mod_quiz_get_quiz_access_information',
            'mod_quiz_get_attempt_access_information',
            'mod_quiz_get_user_attempts',
            'mod_quiz_start_attempt',
          ]),
        );

        final snapshot = await deniedClient.fetchQuizAttempt(
          token: 'token',
          item: _quizItem,
        );

        expect(snapshot.canStart, isFalse);
        expect(snapshot.accessMessage, contains('not available'));
        await expectLater(
          deniedClient.startQuizAttempt(token: 'token', item: _quizItem),
          throwsA(isA<MoodleApiException>()),
        );
        expect(startCalls, 0);
      },
    );

    test('requires the iSpace page when quiz preflight is required', () async {
      final preflightClient = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'mod_quiz_get_quiz_access_information' => http.Response(
              '{"canattempt":true,"preventaccessreasons":[],"warnings":[]}',
              200,
            ),
            'mod_quiz_get_attempt_access_information' => http.Response(
              '{"isfinished":false,"ispreflightcheckrequired":true,'
              '"preventnewattemptreasons":[],"warnings":[]}',
              200,
            ),
            'mod_quiz_get_user_attempts' => http.Response(
              '{"attempts":[],"warnings":[]}',
              200,
            ),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(preflightClient.dispose);
      preflightClient.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_quiz_get_quiz_access_information',
          'mod_quiz_get_attempt_access_information',
          'mod_quiz_get_user_attempts',
        ]),
      );

      final snapshot = await preflightClient.fetchQuizAttempt(
        token: 'token',
        item: _quizItem,
      );

      expect(snapshot.canStart, isFalse);
      expect(snapshot.accessMessage, contains('iSpace 页面'));
    });

    test(
      'start attempt requires the new attempt to survive a fresh read',
      () async {
        var startCalls = 0;
        final startClient = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((request) async {
            return switch (request.bodyFields['wsfunction']) {
              'mod_quiz_get_quiz_access_information' => http.Response(
                '{"canattempt":true,"preventaccessreasons":[],"warnings":[]}',
                200,
              ),
              'mod_quiz_get_attempt_access_information' => http.Response(
                '{"isfinished":false,"ispreflightcheckrequired":false,'
                '"preventnewattemptreasons":[],"warnings":[]}',
                200,
              ),
              'mod_quiz_start_attempt' => (() {
                startCalls++;
                return http.Response(
                  '{"attempt":{"id":77,"quiz":89055,"state":"inprogress"},'
                  '"warnings":[]}',
                  200,
                );
              })(),
              'mod_quiz_get_user_attempts' => http.Response(
                '{"attempts":[{"id":77,"quiz":89055,'
                '"state":"inprogress"}],"warnings":[]}',
                200,
              ),
              'mod_quiz_get_attempt_data' => http.Response(
                '{"attempt":{"id":77,"state":"inprogress"},'
                '"questions":[],"nextpage":-1,"warnings":[]}',
                200,
              ),
              _ => http.Response('{"warnings":[]}', 200),
            };
          }),
        );
        addTearDown(startClient.dispose);
        startClient.cacheRuntimeProfileForTesting(
          token: 'token',
          profile: _profileFor(const [
            'mod_quiz_get_quiz_access_information',
            'mod_quiz_get_attempt_access_information',
            'mod_quiz_start_attempt',
            'mod_quiz_get_user_attempts',
            'mod_quiz_get_attempt_data',
          ]),
        );

        final snapshot = await startClient.startQuizAttempt(
          token: 'token',
          item: _quizItem,
        );

        expect(startCalls, 1);
        expect(snapshot.attemptId, 77);
        expect(snapshot.hasActiveAttempt, isTrue);
      },
    );

    test(
      'final submit verifies process state and a fresh attempt read',
      () async {
        Map<String, String>? processFields;
        final finishClient = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((request) async {
            return switch (request.bodyFields['wsfunction']) {
              'mod_quiz_get_quiz_access_information' => http.Response(
                '{"canattempt":true,"preventaccessreasons":[],"warnings":[]}',
                200,
              ),
              'mod_quiz_get_attempt_access_information' => http.Response(
                '{"isfinished":false,"ispreflightcheckrequired":false,'
                '"preventnewattemptreasons":[],"warnings":[]}',
                200,
              ),
              'mod_quiz_process_attempt' => (() {
                processFields = Map.of(request.bodyFields);
                return http.Response('{"state":"finished","warnings":[]}', 200);
              })(),
              'mod_quiz_get_user_attempts' => http.Response(
                '{"attempts":[{"id":77,"quiz":89055,'
                '"state":"finished"}],"warnings":[]}',
                200,
              ),
              _ => http.Response('{"warnings":[]}', 200),
            };
          }),
        );
        addTearDown(finishClient.dispose);
        finishClient.cacheRuntimeProfileForTesting(
          token: 'token',
          profile: _profileFor(const [
            'mod_quiz_get_quiz_access_information',
            'mod_quiz_get_attempt_access_information',
            'mod_quiz_process_attempt',
            'mod_quiz_get_user_attempts',
          ]),
        );
        const snapshot = QuizAttemptSnapshot(
          itemId: '501',
          quizId: 89055,
          attemptId: 77,
          state: 'inprogress',
          canStart: false,
          canSave: true,
          canFinish: true,
          questions: [
            QuizQuestionData(
              slot: 1,
              number: '1',
              type: 'multichoice',
              prompt: 'Question',
              status: '',
              sequenceCheckName: 'q1_:sequencecheck',
              sequenceCheck: '3',
              fields: [
                QuizAnswerField(
                  name: 'q1_answer',
                  kind: QuizAnswerFieldKind.choice,
                  label: '',
                  currentValues: [],
                  options: [QuizAnswerOption(value: '1', label: 'A')],
                ),
              ],
            ),
          ],
        );

        await finishClient.finishQuizAttempt(
          token: 'token',
          snapshot: snapshot,
          answers: const [
            QuizAnswerDraft(slot: 1, fieldName: 'q1_answer', value: '1'),
          ],
        );

        expect(processFields?['finishattempt'], '1');
        expect(processFields?['data[0][name]'], 'q1_answer');
        expect(processFields?['data[1][name]'], 'q1_:sequencecheck');
      },
    );
  });

  group('assignment submission state machine', () {
    test('saves a draft without claiming final submission', () async {
      var statusCalls = 0;
      Map<String, String>? saveFields;
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'mod_assign_get_assignments' => http.Response(
              jsonEncode(_assignmentList(submissionDrafts: true)),
              200,
            ),
            'mod_assign_get_submission_status' => (() {
              statusCalls++;
              return http.Response(
                jsonEncode(_assignmentStatus(status: 'draft')),
                200,
              );
            })(),
            'mod_assign_save_submission' => (() {
              saveFields = Map.of(request.bodyFields);
              return http.Response('[]', 200);
            })(),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_assign_get_assignments',
          'mod_assign_get_submission_status',
          'mod_assign_save_submission',
        ]),
      );

      final outcome = await client.submitAssignmentOnlineText(
        token: 'token',
        assignmentId: 77,
        text: '  My answer  ',
      );

      expect(outcome.status, 'draft');
      expect(outcome.draftSaved, isTrue);
      expect(outcome.finalSubmitted, isFalse);
      expect(statusCalls, 2);
      expect(saveFields?['plugindata[onlinetext_editor][text]'], 'My answer');
    });

    test(
      'final submission requires statement acceptance and verifies status',
      () async {
        var statusCalls = 0;
        var finalizeCalls = 0;
        final client = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((request) async {
            return switch (request.bodyFields['wsfunction']) {
              'mod_assign_get_assignments' => http.Response(
                jsonEncode(
                  _assignmentList(
                    submissionDrafts: true,
                    requiresStatement: true,
                  ),
                ),
                200,
              ),
              'mod_assign_get_submission_status' => (() {
                statusCalls++;
                return http.Response(
                  jsonEncode(
                    _assignmentStatus(
                      status: statusCalls >= 3 ? 'submitted' : 'draft',
                    ),
                  ),
                  200,
                );
              })(),
              'mod_assign_submit_for_grading' => (() {
                finalizeCalls++;
                return http.Response('[]', 200);
              })(),
              _ => http.Response('{"warnings":[]}', 200),
            };
          }),
        );
        addTearDown(client.dispose);
        client.cacheRuntimeProfileForTesting(
          token: 'token',
          profile: _profileFor(const [
            'mod_assign_get_assignments',
            'mod_assign_get_submission_status',
            'mod_assign_submit_for_grading',
          ]),
        );

        await expectLater(
          client.finalizeAssignment(
            token: 'token',
            assignmentId: 77,
            acceptSubmissionStatement: false,
          ),
          throwsA(isA<MoodleApiException>()),
        );
        expect(finalizeCalls, 0);

        final outcome = await client.finalizeAssignment(
          token: 'token',
          assignmentId: 77,
          acceptSubmissionStatement: true,
        );

        expect(finalizeCalls, 1);
        expect(outcome.finalSubmitted, isTrue);
        expect(outcome.status, 'submitted');
      },
    );

    test('fails closed for team submissions before mutation', () async {
      var saveCalls = 0;
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'mod_assign_get_assignments' => http.Response(
              jsonEncode(
                _assignmentList(submissionDrafts: true, teamSubmission: true),
              ),
              200,
            ),
            'mod_assign_get_submission_status' => http.Response(
              jsonEncode(_assignmentStatus(status: 'draft')),
              200,
            ),
            'mod_assign_save_submission' => (() {
              saveCalls++;
              return http.Response('[]', 200);
            })(),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_assign_get_assignments',
          'mod_assign_get_submission_status',
          'mod_assign_save_submission',
        ]),
      );

      await expectLater(
        client.submitAssignmentOnlineText(
          token: 'token',
          assignmentId: 77,
          text: 'Answer',
        ),
        throwsA(isA<MoodleApiException>()),
      );
      expect(saveCalls, 0);
    });

    test('treats Moodle save warnings as failure', () async {
      var statusCalls = 0;
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'mod_assign_get_assignments' => http.Response(
              jsonEncode(_assignmentList(submissionDrafts: true)),
              200,
            ),
            'mod_assign_get_submission_status' => (() {
              statusCalls++;
              return http.Response(
                jsonEncode(_assignmentStatus(status: 'draft')),
                200,
              );
            })(),
            'mod_assign_save_submission' => http.Response(
              '[{"warningcode":"couldnotsavesubmission"}]',
              200,
            ),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_assign_get_assignments',
          'mod_assign_get_submission_status',
          'mod_assign_save_submission',
        ]),
      );

      await expectLater(
        client.submitAssignmentOnlineText(
          token: 'token',
          assignmentId: 77,
          text: 'Answer',
        ),
        throwsA(isA<MoodleApiException>()),
      );
      expect(statusCalls, 1);
    });
  });

  group('typed module access', () {
    test(
      'grade report binds the response to the requested current user',
      () async {
        final client = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((request) async {
            expect(request.bodyFields['courseid'], '42');
            expect(request.bodyFields['userid'], '7');
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'usergrades': [
                    {
                      'userid': 999,
                      'gradeitems': [
                        {
                          'id': 1,
                          'itemname': 'Wrong user',
                          'gradeformatted': '0',
                        },
                      ],
                    },
                    {
                      'userid': 7,
                      'gradeitems': [
                        {
                          'id': 2,
                          'itemname': 'Current user quiz',
                          'itemmodule': 'quiz',
                          'cmid': 101,
                          'gradeformatted': '8.00',
                          'rangeformatted': '0–10',
                          'percentageformatted': '80%',
                          'gradeishidden': false,
                        },
                      ],
                    },
                  ],
                  'warnings': [],
                }),
              ),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }),
        );
        addTearDown(client.dispose);
        client.cacheRuntimeProfileForTesting(
          token: 'token',
          profile: _profileFor(const ['gradereport_user_get_grade_items']),
        );

        final grades = await client.fetchCourseGrades(
          token: 'token',
          courseId: 42,
          userId: 7,
        );

        expect(grades.items, hasLength(1));
        expect(grades.items.single.name, 'Current user quiz');
        expect(grades.items.single.gradeFormatted, '8.00');
      },
    );

    test('grade parser treats either upstream hidden flag as hidden', () {
      final item = CourseGradeItem.fromJson({
        'id': 1,
        'itemname': 'Hidden by date',
        'gradeishidden': false,
        'gradehiddenbydate': true,
        'gradeislocked': false,
        'locked': true,
      });

      expect(item.hidden, isTrue);
      expect(item.locked, isTrue);
    });

    test('choice exposes only server option ids and disabled state', () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'mod_choice_get_choice_options' => (() {
              expect(request.bodyFields['choiceid'], '88');
              return http.Response(
                jsonEncode({
                  'options': [
                    {
                      'id': 1,
                      'text': '<b>Option A</b>',
                      'maxanswers': 10,
                      'checked': 1,
                      'disabled': 0,
                    },
                    {
                      'id': 2,
                      'text': 'Option B',
                      'maxanswers': 10,
                      'checked': 0,
                      'disabled': 1,
                    },
                  ],
                  'warnings': [],
                }),
                200,
              );
            })(),
            'mod_choice_get_choices_by_courses' => http.Response(
              '{"choices":[{"id":88,"allowmultiple":0,'
              '"allowupdate":1}],"warnings":[]}',
              200,
            ),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_choice_get_choice_options',
          'mod_choice_get_choices_by_courses',
        ]),
      );

      final access = await client.fetchModuleAccess(
        token: 'token',
        moduleType: 'choice',
        instanceId: 88,
        courseId: 42,
      );

      expect(access.canRead, isTrue);
      expect(access.canWrite, isTrue);
      expect(access.choiceOptions.map((option) => option.id), [1, 2]);
      expect(access.choiceOptions.first.label, 'Option A');
      expect(access.choiceOptions.first.selected, isTrue);
      expect(access.choiceOptions.last.disabled, isTrue);
      expect(access.choiceAllowMultiple, isFalse);
      expect(access.choiceAllowUpdate, isTrue);
    });

    test('manual completion update is accepted only after read-back', () async {
      Map<String, String>? updateFields;
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'core_completion_update_activity_completion_status_manually' =>
              (() {
                updateFields = Map.of(request.bodyFields);
                return http.Response('{"status":true,"warnings":[]}', 200);
              })(),
            'core_completion_get_activities_completion_status' => http.Response(
              '{"statuses":[{"cmid":101,"state":1,"tracking":1}],'
              '"warnings":[]}',
              200,
            ),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'core_completion_update_activity_completion_status_manually',
          'core_completion_get_activities_completion_status',
        ]),
      );

      await client.updateManualCompletion(
        token: 'token',
        courseId: 42,
        courseModuleId: 101,
        userId: 7,
        completed: true,
      );

      expect(updateFields?['cmid'], '101');
      expect(updateFields?['completed'], '1');
    });

    test('manual completion rejects an unconfirmed read-back state', () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'core_completion_update_activity_completion_status_manually' =>
              http.Response('{"status":true,"warnings":[]}', 200),
            'core_completion_get_activities_completion_status' => http.Response(
              '{"statuses":[{"cmid":101,"state":0,"tracking":1}],'
              '"warnings":[]}',
              200,
            ),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'core_completion_update_activity_completion_status_manually',
          'core_completion_get_activities_completion_status',
        ]),
      );

      await expectLater(
        client.updateManualCompletion(
          token: 'token',
          courseId: 42,
          courseModuleId: 101,
          userId: 7,
          completed: true,
        ),
        throwsA(isA<MoodleApiException>()),
      );
    });

    test(
      'choice submission rechecks server option ids and verifies selection',
      () async {
        var optionCalls = 0;
        Map<String, String>? submitFields;
        final client = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((request) async {
            return switch (request.bodyFields['wsfunction']) {
              'mod_choice_get_choice_options' => (() {
                optionCalls++;
                return http.Response(
                  jsonEncode({
                    'options': [
                      {
                        'id': 11,
                        'text': 'Option A',
                        'maxanswers': 10,
                        'checked': optionCalls > 1 ? 1 : 0,
                        'disabled': optionCalls > 1 ? 1 : 0,
                      },
                      {
                        'id': 12,
                        'text': 'Option B',
                        'maxanswers': 10,
                        'checked': 0,
                        'disabled': 0,
                      },
                    ],
                    'warnings': [],
                  }),
                  200,
                );
              })(),
              'mod_choice_get_choices_by_courses' => http.Response(
                '{"choices":[{"id":88,"allowmultiple":0,'
                '"allowupdate":1}],"warnings":[]}',
                200,
              ),
              'mod_choice_submit_choice_response' => (() {
                submitFields = Map.of(request.bodyFields);
                return http.Response(
                  '{"answers":[{"id":91,"choiceid":88,"userid":7,'
                  '"optionid":11,"timemodified":1}],"warnings":[]}',
                  200,
                );
              })(),
              _ => http.Response('{"warnings":[]}', 200),
            };
          }),
        );
        addTearDown(client.dispose);
        client.cacheRuntimeProfileForTesting(
          token: 'token',
          profile: _profileFor(const [
            'mod_choice_get_choice_options',
            'mod_choice_get_choices_by_courses',
            'mod_choice_submit_choice_response',
          ]),
        );

        final result = await client.submitChoice(
          token: 'token',
          courseId: 42,
          choiceId: 88,
          optionIds: const [11],
        );

        expect(optionCalls, 2);
        expect(submitFields?['choiceid'], '88');
        expect(submitFields?['responses[0]'], '11');
        expect(
          result.choiceOptions.singleWhere((item) => item.id == 11).selected,
          isTrue,
        );
      },
    );

    test(
      'choice submission rejects option ids absent from fresh access',
      () async {
        var submitCalls = 0;
        final client = MoodleApiClient(
          baseUrl: 'https://ispace.example.edu',
          client: MockClient((request) async {
            return switch (request.bodyFields['wsfunction']) {
              'mod_choice_get_choice_options' => http.Response(
                '{"options":[{"id":11,"text":"Option A",'
                '"maxanswers":1,"checked":0,"disabled":0}],"warnings":[]}',
                200,
              ),
              'mod_choice_get_choices_by_courses' => http.Response(
                '{"choices":[{"id":88,"allowmultiple":0,'
                '"allowupdate":1}],"warnings":[]}',
                200,
              ),
              'mod_choice_submit_choice_response' => (() {
                submitCalls++;
                return http.Response('{"answers":[],"warnings":[]}', 200);
              })(),
              _ => http.Response('{"warnings":[]}', 200),
            };
          }),
        );
        addTearDown(client.dispose);
        client.cacheRuntimeProfileForTesting(
          token: 'token',
          profile: _profileFor(const [
            'mod_choice_get_choice_options',
            'mod_choice_get_choices_by_courses',
            'mod_choice_submit_choice_response',
          ]),
        );

        await expectLater(
          client.submitChoice(
            token: 'token',
            courseId: 42,
            choiceId: 88,
            optionIds: const [99],
          ),
          throwsA(isA<MoodleApiException>()),
        );
        expect(submitCalls, 0);
      },
    );

    test('choice submission rejects multiple ids for single choice', () async {
      var submitCalls = 0;
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient((request) async {
          return switch (request.bodyFields['wsfunction']) {
            'mod_choice_get_choice_options' => http.Response(
              '{"options":[{"id":11,"text":"Option A",'
              '"maxanswers":1,"checked":0,"disabled":0},'
              '{"id":12,"text":"Option B","maxanswers":1,'
              '"checked":0,"disabled":0}],"warnings":[]}',
              200,
            ),
            'mod_choice_get_choices_by_courses' => http.Response(
              '{"choices":[{"id":88,"allowmultiple":0,'
              '"allowupdate":1}],"warnings":[]}',
              200,
            ),
            'mod_choice_submit_choice_response' => (() {
              submitCalls++;
              return http.Response('{"answers":[],"warnings":[]}', 200);
            })(),
            _ => http.Response('{"warnings":[]}', 200),
          };
        }),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_choice_get_choice_options',
          'mod_choice_get_choices_by_courses',
          'mod_choice_submit_choice_response',
        ]),
      );

      await expectLater(
        client.submitChoice(
          token: 'token',
          courseId: 42,
          choiceId: 88,
          optionIds: const [11, 12],
        ),
        throwsA(isA<MoodleApiException>()),
      );
      expect(submitCalls, 0);
    });

    test('feedback write state follows access flags', () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient(
          (_) async => http.Response(
            '{"cancomplete":true,"cansubmit":true,"isopen":true,'
            '"isempty":false,"isalreadysubmitted":false,'
            '"isanonymous":true,"warnings":[]}',
            200,
          ),
        ),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_feedback_get_feedback_access_information',
        ]),
      );

      final access = await client.fetchModuleAccess(
        token: 'token',
        moduleType: 'feedback',
        instanceId: 99,
        courseId: 42,
      );

      expect(access.canRead, isTrue);
      expect(access.canWrite, isTrue);
      expect(access.statusMessage, contains('匿名'));
    });

    test('lesson access reasons disable native write capability', () async {
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example.edu',
        client: MockClient(
          (_) async => http.Response(
            '{"firstpageid":123,"preventaccessreasons":['
            '{"reason":"passwordprotected","message":"Password required"}'
            '],"warnings":[]}',
            200,
          ),
        ),
      );
      addTearDown(client.dispose);
      client.cacheRuntimeProfileForTesting(
        token: 'token',
        profile: _profileFor(const [
          'mod_lesson_get_lesson_access_information',
        ]),
      );

      final access = await client.fetchModuleAccess(
        token: 'token',
        moduleType: 'lesson',
        instanceId: 100,
        courseId: 42,
      );

      expect(access.canRead, isTrue);
      expect(access.canWrite, isFalse);
      expect(access.statusMessage, contains('Password required'));
    });
  });
}

Map<String, dynamic> _assignmentList({
  required bool submissionDrafts,
  bool requiresStatement = false,
  bool teamSubmission = false,
}) => {
  'courses': [
    {
      'id': 42,
      'fullname': 'Course',
      'shortname': 'COURSE',
      'timemodified': 0,
      'assignments': [
        {
          'id': 77,
          'cmid': 101,
          'course': 42,
          'name': 'Assignment',
          'nosubmissions': 0,
          'submissiondrafts': submissionDrafts ? 1 : 0,
          'teamsubmission': teamSubmission ? 1 : 0,
          'requireallteammemberssubmit': 0,
          'requiresubmissionstatement': requiresStatement ? 1 : 0,
          'preventsubmissionnotingroup': 0,
          'timelimit': 0,
          'configs': [
            {
              'plugin': 'onlinetext',
              'subtype': 'assignsubmission',
              'name': 'enabled',
              'value': '1',
            },
          ],
        },
      ],
    },
  ],
  'warnings': [],
};

Map<String, dynamic> _assignmentStatus({required String status}) => {
  'lastattempt': {
    'submissionsenabled': true,
    'locked': false,
    'canedit': true,
    'caneditowner': true,
    'cansubmit': true,
    'submission': {'id': 1, 'status': status, 'plugins': []},
  },
  'warnings': [],
};

MoodleRuntimeProfile _profileFor(Iterable<String> functions) =>
    MoodleRuntimeProfile(
      release: 'test',
      version: 'test',
      functionVersions: {for (final function in functions) function: 'test'},
      downloadFiles: true,
      uploadFiles: true,
      advancedFeatures: const {'enablecompletion': 1},
      userMaxUploadFileSize: 1048576,
    );

final _quizItem = TimelineItem(
  id: 501,
  title: 'Post-tutorial Quiz',
  activityState: 'Quiz is due',
  activityType: 'quiz',
  moduleName: 'quiz',
  description: '',
  courseName: 'Tutorial',
  courseId: 42,
  instanceId: 89055,
  url: 'https://ispace.example.edu/mod/quiz/view.php?id=12',
  sortTime: null,
  formattedTime: '',
  isOverdue: false,
);
