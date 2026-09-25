import 'dart:async';
import 'dart:convert';

import 'package:bnbu_me/models/cis_checkin.dart';
import 'package:bnbu_me/services/cis_checkin_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/cis_checkin_fixtures.dart';

http.Response jsonResponse(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response loginResponse() => jsonResponse({
  'success': true,
  'code': 200,
  'result': {'token': 'synthetic-cis-token'},
});

void main() {
  test(
    'response body deadline aborts a trickling read and limits retries',
    () async {
      final transport = _TricklingCisClient();
      final client = CisCheckinClient(
        client: transport,
        timeout: const Duration(milliseconds: 40),
        retryDelay: (_) async {},
      );
      addTearDown(client.dispose);
      await expectLater(
        client
            .fetchProjects(username: 's', password: 'p')
            .timeout(const Duration(seconds: 2)),
        throwsA(isA<CisCheckinException>()),
      );
      expect((transport.logins, transport.reads, transport.aborts), (1, 2, 2));
    },
  );

  test(
    'transient login failures never replay credentials automatically',
    () async {
      var calls = 0;
      final client = CisCheckinClient(
        retryDelay: (_) async {},
        client: MockClient((r) async {
          calls++;
          return http.Response('', 503);
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.fetchProjects(username: 's', password: 'p'),
        throwsA(isA<CisCheckinException>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'preload and foreground share reads; cache expires and manual refresh bypasses it',
    () async {
      var now = DateTime(2026, 9, 19);
      var reads = 0;
      final gate = Completer<void>();
      final client = CisCheckinClient(
        clock: () => now,
        client: MockClient((r) async {
          if (r.method == 'POST') return loginResponse();
          reads++;
          await gate.future;
          return jsonResponse(
            checkinEnvelope([checkinProjectJson(checked: reads)]),
          );
        }),
      );
      addTearDown(client.dispose);
      final a = client.fetchProjects(username: 's', password: 'p');
      final b = client.fetchProjects(username: 's', password: 'p');
      gate.complete();
      expect(identical(await a, await b), isTrue);
      expect(reads, 1);
      await client.fetchProjects(username: 's', password: 'p');
      expect(reads, 1);
      await client.fetchProjects(
        username: 's',
        password: 'p',
        forceRefresh: true,
      );
      expect(reads, 2);
      now = now.add(const Duration(minutes: 3));
      expect(client.cachedProjects()!.items.single.checkedCount, 2);
      await client.fetchProjects(username: 's', password: 'p');
      expect(reads, 3);
      now = now.add(const Duration(minutes: 31));
      expect(client.cachedProjects(), isNull);
      client.clearSession();
      expect(client.cachedProjects(), isNull);
    },
  );

  for (final failure in [503, 'timeout', 'network']) {
    test(
      'transient $failure retries read once without another login',
      () async {
        var reads = 0, logins = 0, delays = 0;
        final client = CisCheckinClient(
          retryDelay: (_) async {
            delays++;
          },
          client: MockClient((r) async {
            if (r.method == 'POST') {
              logins++;
              return loginResponse();
            }
            if (++reads == 1) {
              if (failure == 'timeout') throw TimeoutException('synthetic');
              if (failure == 'network') throw http.ClientException('synthetic');
              return http.Response('', failure as int);
            }
            return jsonResponse(checkinEnvelope([]));
          }),
        );
        addTearDown(client.dispose);
        await client.fetchProjects(username: 's', password: 'p');
        expect((reads, logins, delays), (2, 1, 1));
      },
    );
  }

  test(
    'persistent outage is bounded, retains cached data and permits later recovery',
    () async {
      var offline = false, reads = 0, logins = 0;
      final client = CisCheckinClient(
        retryDelay: (_) async {},
        client: MockClient((r) async {
          if (r.method == 'POST') {
            logins++;
            return loginResponse();
          }
          reads++;
          return offline
              ? http.Response('', 503)
              : jsonResponse(checkinEnvelope([checkinProjectJson()]));
        }),
      );
      addTearDown(client.dispose);
      await client.fetchProjects(username: 's', password: 'p');
      offline = true;
      await expectLater(
        client.fetchProjects(username: 's', password: 'p', forceRefresh: true),
        throwsA(isA<CisCheckinException>()),
      );
      expect(reads, 3);
      expect(client.cachedProjects()!.items, hasLength(1));
      offline = false;
      await client.fetchProjects(
        username: 's',
        password: 'p',
        forceRefresh: true,
      );
      expect((reads, logins), (4, 1));
    },
  );

  test('logout during retry prevents replay and cache publication', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    var reads = 0;
    final client = CisCheckinClient(
      retryDelay: (_) async {
        entered.complete();
        await gate.future;
      },
      client: MockClient((r) async {
        if (r.method == 'POST') return loginResponse();
        reads++;
        return http.Response('', 503);
      }),
    );
    addTearDown(client.dispose);
    final pending = expectLater(
      client.fetchProjects(username: 's', password: 'p'),
      throwsA(
        isA<CisCheckinException>().having(
          (e) => e.failure,
          'failure',
          CisCheckinFailure.sessionChanged,
        ),
      ),
    );
    await entered.future;
    client.clearSession();
    gate.complete();
    await pending;
    expect(reads, 1);
    expect(client.cachedProjects(), isNull);
  });

  test(
    'new account proceeds while an obsolete request is still pending',
    () async {
      final entered = Completer<void>(), gate = Completer<void>();
      var reads = 0;
      final client = CisCheckinClient(
        client: MockClient((r) async {
          if (r.method == 'POST') return loginResponse();
          if (++reads == 1) {
            entered.complete();
            await gate.future;
          }
          return jsonResponse(
            checkinEnvelope([checkinProjectJson(checked: reads)]),
          );
        }),
      );
      addTearDown(client.dispose);
      final old = expectLater(
        client.fetchProjects(username: 'old', password: 'p'),
        throwsA(isA<CisCheckinException>()),
      );
      await entered.future;
      client.clearSession();
      final fresh = await client
          .fetchProjects(username: 'new', password: 'p')
          .timeout(const Duration(seconds: 1));
      gate.complete();
      await old;
      expect(client.cachedProjects(), same(fresh));
      expect(fresh.items.single.checkedCount, 2);
    },
  );

  test(
    'record cache keys isolate projects and pages and stay bounded',
    () async {
      final client = CisCheckinClient(
        client: MockClient((r) async {
          if (r.method == 'POST') return loginResponse();
          return jsonResponse(
            checkinEnvelope([
              checkinRecordJson(id: r.url.queryParameters['projectId']!),
            ], page: int.parse(r.url.queryParameters['pageNo']!)),
          );
        }),
      );
      addTearDown(client.dispose);
      for (var i = 0; i < 25; i++) {
        await client.fetchRecords(
          username: 's',
          password: 'p',
          projectId: 'p$i',
        );
      }
      expect(client.cachedRecords(projectId: 'p0'), isNull);
      expect(client.cachedRecords(projectId: 'p24')!.items.single.id, 'p24');
      expect(client.cachedRecords(projectId: 'p24', page: 2), isNull);
      client.clearSession();
      expect(client.cachedRecords(projectId: 'p24'), isNull);
    },
  );

  test(
    'school counts and completion are independent, including 12/9 and 0/0',
    () {
      for (final (count, minimum, complete) in [
        (9, 10, false),
        (12, 9, true),
        (0, 0, true),
        (10, 10, false),
      ]) {
        final project = CisCheckinProject.fromJson(
          checkinProjectJson(
            checked: count,
            required: minimum,
            completed: complete,
          ),
        );
        expect(project.checkedCount, count);
        expect(project.requiredCount, minimum);
        expect(project.completed, complete);
      }
      expect(
        () => CisCheckinProject.fromJson({
          ...checkinProjectJson(),
          'studentFinishCheckin': null,
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'only explicitly settled records are visible, including unfinished results',
    () {
      for (final pending in [true, 1, null, 'false', 'counting']) {
        final row = checkinRecordJson(counting: pending);
        expect(CisCheckinRecord.isSettled(row), isFalse);
        expect(() => CisCheckinRecord.fromJson(row), throwsFormatException);
      }
      for (final settled in [false, 0]) {
        final record = CisCheckinRecord.fromJson(
          checkinRecordJson(counting: settled, completed: false),
        );
        expect(record.completed, isFalse);
        expect(record.checkedIn, isTrue);
        expect(record.checkedOut, isFalse);
        expect(record.sessions.single.checkoutAt, isNull);
      }
    },
  );

  test(
    'school local timestamps use Beijing time and never the device timezone',
    () {
      final instant = cisDate('2026-09-16 14:00:00')!;
      expect(instant, DateTime.utc(2026, 9, 16, 6));
      expect(cisCampusDate(instant).hour, 14);
      expect(cisDate('2026/09/16 14:00:00'), instant);
      expect(cisDate('2026-09-16T06:00:00Z'), instant);
      expect(cisDate(instant.millisecondsSinceEpoch), instant);
      expect(cisDate('2026-09-16'), DateTime.utc(2026, 9, 15, 16));
      expect(cisDate(null), isNull);
      expect(() => cisDate('not a date'), throwsFormatException);
    },
  );

  test('multiple sessions preserve original attendance timestamps', () {
    final row = checkinRecordJson();
    (row['projectItem'] as Map<String, dynamic>).addAll({
      'plusCount': 3,
      'beginPlus': '2026-09-16 18:00:00',
      'endPlus': '2026-09-16 19:00:00',
      'beginPlus3': '2026-09-16 20:00:00',
      'endPlus3': '2026-09-16 21:00:00',
    });
    row.addAll({
      'checkinTimePlus': '2026-09-16 17:59:00',
      'checkinFinishPlus': true,
      'checkoutTimePlus3': '2026-09-16 21:01:00',
      'checkoutFinishPlus3': true,
    });
    final record = CisCheckinRecord.fromJson(row);
    expect(record.sessions, hasLength(3));
    expect(cisCampusDate(record.sessions[1].checkinAt!).hour, 17);
    expect(record.sessions[1].checkoutAt, isNull);
    expect(record.sessions[2].checkedOut, isTrue);
  });

  test(
    'CIS uses only its own token, raw password, readonly student endpoints and source pagination',
    () async {
      final requests = <http.Request>[];
      final client = CisCheckinClient(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/auth/login') return loginResponse();
          if (request.url.path == '/api/user/authorityUser/list') {
            return jsonResponse(checkinEnvelope([checkinProjectJson()]));
          }
          return jsonResponse(
            checkinEnvelope([
              checkinRecordJson(counting: true),
              checkinRecordJson(counting: null),
              checkinRecordJson(id: 'settled-unfinished', completed: false),
            ], total: 40),
          );
        }),
      );
      addTearDown(client.dispose);
      await client.fetchProjects(
        username: 'synthetic-student',
        password: ' 学校 密碼 ',
      );
      final records = await client.fetchRecords(
        username: 'synthetic-student',
        password: ' 学校 密碼 ',
        projectId: 'project-1',
      );
      expect(records.items.single.id, 'settled-unfinished');
      expect(records.hasMore, isTrue);
      expect(records.hasUnknownStatistics, isTrue);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(jsonDecode(requests.first.body), {
        'username': 'synthetic-student',
        'password': ' 学校 密碼 ',
      });
      expect(requests.first.headers.containsKey('Authorization'), isFalse);
      for (final request in requests) {
        expect(request.url.origin, 'https://cis.bnbu.edu.cn');
        expect(request.followRedirects, isFalse);
        expect(
          request.url.queryParameters.containsKey('currentUserId'),
          isFalse,
        );
        expect(request.headers.containsKey('Cookie'), isFalse);
      }
      expect(requests.last.headers['Authorization'], 'synthetic-cis-token');
      expect(requests.last.url.queryParameters['projectId'], 'project-1');
      expect(
        requests.last.url.queryParameters['pageSize'],
        '${CisCheckinClient.pageSize}',
      );
    },
  );

  test(
    'expired token has only one reauthentication attempt per read',
    () async {
      var logins = 0;
      var reads = 0;
      final client = CisCheckinClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            logins++;
            return loginResponse();
          }
          reads++;
          return jsonResponse({
            'message': 'sensitive synthetic upstream error',
          }, status: 401);
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.fetchProjects(username: 's', password: 'p'),
        throwsA(
          isA<CisCheckinException>().having(
            (e) => e.failure,
            'failure',
            CisCheckinFailure.authentication,
          ),
        ),
      );
      expect(logins, 2);
      expect(reads, 2);
    },
  );

  for (final code in [403, 500, 302]) {
    test(
      'HTTP $code is not empty data or a reason to resend credentials',
      () async {
        var logins = 0;
        final client = CisCheckinClient(
          client: MockClient((r) async {
            if (r.method == 'POST') {
              logins++;
              return loginResponse();
            }
            return http.Response(
              'synthetic-secret-do-not-display',
              code,
              headers: {'location': 'https://untrusted.example/steal'},
            );
          }),
        );
        addTearDown(client.dispose);
        try {
          await client.fetchProjects(username: 's', password: 'p');
          fail('Expected safe failure');
        } on CisCheckinException catch (error) {
          expect(error.toString(), isNot(contains('synthetic-secret')));
          expect(error.message, isNot(contains('synthetic-secret')));
        }
        expect(logins, 1);
      },
    );
  }

  test(
    'network error retains CIS session, retry does not log in again',
    () async {
      var logins = 0;
      var offline = true;
      final client = CisCheckinClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            logins++;
            return loginResponse();
          }
          if (offline) throw http.ClientException('synthetic secret');
          return jsonResponse(checkinEnvelope([]));
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.fetchProjects(username: 's', password: 'p'),
        throwsA(isA<CisCheckinException>()),
      );
      offline = false;
      expect(
        (await client.fetchProjects(username: 's', password: 'p')).items,
        isEmpty,
      );
      expect(logins, 1);
    },
  );

  test(
    'concurrent reads share serialized login and a failed read does not poison queue',
    () async {
      var logins = 0;
      var requests = 0;
      final client = CisCheckinClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            logins++;
            return loginResponse();
          }
          requests++;
          if (requests == 1) return http.Response('not JSON', 200);
          return jsonResponse(checkinEnvelope([]));
        }),
      );
      addTearDown(client.dispose);
      final a = client.fetchProjects(username: 's', password: 'p');
      final b = client.fetchRecords(username: 's', password: 'p');
      await expectLater(a, throwsA(isA<CisCheckinException>()));
      expect((await b).items, isEmpty);
      expect(logins, 1);
    },
  );

  test(
    'logout invalidates in-flight login and queued work without publishing token',
    () async {
      final gate = Completer<void>();
      var logins = 0;
      final client = CisCheckinClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            logins++;
            await gate.future;
            return loginResponse();
          }
          return jsonResponse(checkinEnvelope([]));
        }),
      );
      addTearDown(client.dispose);
      final a = client.fetchProjects(username: 'a', password: 'a');
      final b = client.fetchProjects(username: 'a', password: 'a');
      final aCheck = expectLater(a, throwsA(isA<CisCheckinException>()));
      final bCheck = expectLater(b, throwsA(isA<CisCheckinException>()));
      await Future<void>.delayed(Duration.zero);
      client.clearSession();
      gate.complete();
      await Future.wait([aCheck, bCheck]);
      expect(logins, 1);
      await client.fetchProjects(username: 'b', password: 'b');
      expect(logins, 2);
    },
  );

  for (final result in [
    checkinEnvelope([], page: 2),
    {'result': '<html>login</html>'},
    checkinEnvelope([
      {'bad': 'row'},
    ]),
    {
      'code': 200,
      'result': {'data': [], 'pageNo': 1},
    },
    {
      'result': {'token': 'x' * (2 * 1024 * 1024)},
    },
  ]) {
    test('malformed or oversized data fails closed (${result.keys})', () async {
      final client = CisCheckinClient(
        client: MockClient(
          (r) async =>
              r.method == 'POST' ? loginResponse() : jsonResponse(result),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.fetchProjects(username: 's', password: 'p'),
        throwsA(
          isA<CisCheckinException>().having(
            (e) => e.failure,
            'failure',
            CisCheckinFailure.invalidData,
          ),
        ),
      );
    });
  }
}

class _TricklingCisClient extends http.BaseClient {
  int logins = 0, reads = 0, aborts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      logins++;
      return http.StreamedResponse(
        Stream.value(utf8.encode(loginResponse().body)),
        200,
      );
    }
    reads++;
    final body = StreamController<List<int>>();
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => body.add([32]),
    );
    body.onCancel = timer.cancel;
    unawaited(
      (request as http.AbortableRequest).abortTrigger!.then((_) async {
        aborts++;
        timer.cancel();
        if (!body.isClosed) {
          body.addError(http.RequestAbortedException(request.url));
          await body.close();
        }
      }),
    );
    return http.StreamedResponse(body.stream, 200);
  }
}
