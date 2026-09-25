import 'dart:async';
import 'dart:convert';

import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/services/leave_application_bridge.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'leave_course_picker_test.dart' show courseFixture;

class Lease implements AppSessionLease {
  @override
  String get owner => 'synthetic';
  @override
  bool isActive = true;
}

class Web extends NativeMirrorWebViewController {
  final operations = <String>[];
  Completer<Object?>? pending;
  @override
  Future<Object?> evaluateJavascript(String source) async {
    operations.add(source.contains('"operation":"attach"') ? 'attach' : 'read');
    return pending?.future ??
        jsonEncode(
          jsonEncode({
            'status': 'ready',
            'fields': {},
            'reasons': [],
            'courses': [],
          }),
        );
  }
}

class ScriptedWeb extends NativeMirrorWebViewController {
  ScriptedWeb(this.respond);
  final FutureOr<Object?> Function(Map<String, dynamic>) respond;
  final calls = <Map<String, dynamic>>[];

  @override
  Future<Object?> evaluateJavascript(String source) async {
    final match = RegExp(r'\((\{"origin":.*\})\);$').firstMatch(source)!;
    final request = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    calls.add(request);
    return jsonEncode(await respond(request));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('whole write budget expires without dispatching later fields', () async {
    final late = Completer<Object?>();
    final web = ScriptedWeb(
      (request) => switch (request['operation']) {
        'validate' => {'status': 'validated'},
        'write' => {'status': 'written'},
        'read' => late.future,
        _ => throw StateError('Unexpected operation'),
      },
    );
    final bridge = LeaveApplicationBridge(
      web: web,
      lease: Lease(),
      portal: Uri.parse('https://portal.example.edu'),
    );
    final result = await bridge.write(
      LeaveApplicationForm(fields: const {}),
      {'mobile': '12345', 'details': 'Do not dispatch'},
      timeout: const Duration(milliseconds: 350),
    );
    expect(result.status, 'timeout');
    late.complete({
      'status': 'ready',
      'fields': {
        'mobile': {'value': '12345'},
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(web.calls.where((c) => c['operation'] == 'write'), hasLength(1));
  });

  test(
    'expired budget never starts a write and receipt queries never resubmit',
    () async {
      var status = 'submission_failed';
      final web = ScriptedWeb(
        (request) => switch (request['operation']) {
          'acknowledge' => {'status': 'acknowledged'},
          'submit_confirmed' => {'status': 'submission_unconfirmed'},
          'submit_status' => {
            'status': status,
            'schoolMessage': 'Synthetic school reason',
          },
          _ => throw StateError('Unexpected operation'),
        },
      );
      final lease = Lease();
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: lease,
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect(
        (await bridge.write(LeaveApplicationForm(fields: const {}), {
          'details': 'Synthetic',
        }, timeout: Duration.zero)).status,
        'timeout',
      );
      expect(web.calls, isEmpty);
      await bridge.submitConfirmed('synthetic');
      expect(
        (await bridge.readSubmissionResult()).schoolMessage,
        'Synthetic school reason',
      );
      status =
          'unsupported'; // Navigation cannot replace the last verified result.
      expect((await bridge.readSubmissionResult()).status, 'submission_failed');
      expect(
        web.calls.where((c) => c['operation'] == 'submit_confirmed'),
        hasLength(1),
      );
      lease.isActive = false;
      expect((await bridge.readSubmissionResult()).status, 'stale');
    },
  );

  test(
    'school receipt survives navigation, is nonce-bound and accepted only once',
    () async {
      final lease = Lease();
      final web = ScriptedWeb(
        (request) => {
          'status': request['operation'] == 'acknowledge'
              ? 'acknowledged'
              : 'submission_unconfirmed',
        },
      );
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: lease,
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect(
        bridge.acceptSubmissionEvent({
          'nonce': 'bad',
          'status': 'submission_succeeded',
        }),
        isNull,
      );
      await bridge.submitConfirmed('review');
      final nonce = web.calls.first['nonce'];
      expect(
        bridge.acceptSubmissionEvent({
          'nonce': nonce,
          'status': 'submission_succeeded',
          'requestId': 123,
        }),
        isNull,
      );
      expect(
        bridge.acceptSubmissionEvent({'nonce': nonce, 'status': 'saved'}),
        isNull,
      );
      expect(
        bridge.acceptSubmissionEvent({
          'nonce': nonce,
          'status': 'submission_succeeded',
        })?.status,
        'submission_succeeded',
      );
      expect(
        bridge.acceptSubmissionEvent({
          'nonce': nonce,
          'status': 'submission_failed',
        }),
        isNull,
      );
      expect((await bridge.waitSubmission()).status, 'submission_succeeded');
      expect(web.calls.length, 2);
      lease.isActive = false;
      expect((await bridge.waitSubmission()).status, 'stale');
    },
  );
  test(
    'result polling is bounded and never dispatches a second submit',
    () async {
      final web = ScriptedWeb(
        (request) => {
          'status': request['operation'] == 'acknowledge'
              ? 'acknowledged'
              : 'submission_unconfirmed',
        },
      );
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      await bridge.submitConfirmed('review');
      expect(
        (await bridge.waitSubmission(
          timeout: const Duration(milliseconds: 10),
        )).status,
        'submission_unconfirmed',
      );
      expect(
        web.calls.where((r) => r['operation'] == 'submit_confirmed'),
        hasLength(1),
      );
      expect(
        (await bridge.submitConfirmed('review')).status,
        'submission_locked',
      );
    },
  );
  test(
    'native school confirmation cancels explicitly and consumes its handle',
    () async {
      final web = ScriptedWeb(
        (request) => switch (request['operation']) {
          'acknowledge' => {'status': 'acknowledged'},
          'submit_confirmed' => {
            'status': 'submission_confirmation',
            'confirmation': {
              'token': 'decision',
              'title': 'School',
              'message': 'Confirm?',
              'cancel': 'Cancel',
              'confirm': 'Confirm',
            },
          },
          'submit_decision' => {'status': 'submission_cancelled'},
          _ => throw StateError('Unexpected operation'),
        },
      );
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      final result = await bridge.submitConfirmed('review');
      expect(result.confirmation?.message, 'Confirm?');
      expect(
        (await bridge.resolveSubmission(result.confirmation!, false)).status,
        'submission_cancelled',
      );
      expect(
        (await bridge.resolveSubmission(result.confirmation!, true)).status,
        'submission_locked',
      );
      expect(web.calls.last['confirmed'], false);
    },
  );
  test(
    'custom confirmation preserves long bilingual school text without truncation',
    () {
      final message =
          'School summary\n学校课程确认\n${List.filled(200, 'DEMO1001').join(', ')}';
      final json = <String, dynamic>{
        'token': 'custom-decision',
        'title': 'Submit Confirmation',
        'message': message,
        'cancel': 'Back',
        'confirm': 'Confirm',
      };
      expect(LeaveSubmitConfirmation.fromJson(json).message, message);
      expect(
        () =>
            LeaveSubmitConfirmation.fromJson({...json, 'message': 'x' * 8001}),
        throwsFormatException,
      );
      expect(
        () => LeaveSubmitConfirmation.fromJson({...json, 'title': 'x' * 501}),
        throwsFormatException,
      );
    },
  );
  for (final outcome in [
    'submission_unconfirmed',
    'write_failed',
    'conflict',
  ]) {
    test('final confirmation is single-shot even after $outcome', () async {
      final web = ScriptedWeb(
        (request) => {
          'status': request['operation'] == 'acknowledge'
              ? 'acknowledged'
              : outcome,
        },
      );
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect((await bridge.submitConfirmed('review-1')).status, outcome);
      expect(
        (await bridge.submitConfirmed('review-2')).status,
        'submission_locked',
      );
      expect(web.calls.map((c) => c['operation']), [
        'acknowledge',
        'submit_confirmed',
      ]);
      expect(
        web.calls.every(
          (c) => c['confirmed'] == true && c['token'] == 'review-1',
        ),
        true,
      );
    });
  }
  test(
    'revoked lease between acknowledgement and submit stops submission',
    () async {
      final lease = Lease();
      final web = ScriptedWeb((request) {
        lease.isActive = false;
        return {'status': 'acknowledged'};
      });
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: lease,
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect((await bridge.submitConfirmed('review-1')).status, 'stale');
      expect(web.calls.map((c) => c['operation']), ['acknowledge']);
    },
  );
  test(
    'file bytes are bounded chunks; upload dispatch is never repeated',
    () async {
      var polls = 0;
      final web = ScriptedWeb(
        (request) => {
          'status': switch (request['operation']) {
            'upload_begin' || 'upload_chunk' => 'upload_buffering',
            'upload_dispatch' => 'upload_unconfirmed',
            'upload_status' => switch (++polls) {
              1 => 'busy',
              2 => 'loading',
              3 => 'upload_unconfirmed',
              _ => 'uploaded',
            },
            _ => throw StateError('Unexpected request'),
          },
        },
      );
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect(
        (await bridge.uploadAttachment(
          token: 't',
          name: 'synthetic.bin',
          size: 70000,
          bytes: Stream.value(List.filled(70000, 7)),
        )).status,
        'uploaded',
      );
      final chunks = web.calls.where((c) => c['operation'] == 'upload_chunk');
      expect(chunks.map((c) => c['offset']), [0, 65536]);
      expect(chunks.map((c) => base64Decode(c['data'] as String).length), [
        65536,
        4464,
      ]);
      expect(
        web.calls.where((c) => c['operation'] == 'upload_dispatch'),
        hasLength(1),
      );
    },
  );
  test('incomplete file stream aborts without dispatch or retry', () async {
    final web = ScriptedWeb(
      (r) => {
        'status': r['operation'] == 'upload_abort'
            ? 'cancelled'
            : 'upload_buffering',
      },
    );
    final bridge = LeaveApplicationBridge(
      web: web,
      lease: Lease(),
      portal: Uri.parse('https://portal.example.edu'),
    );
    expect(
      (await bridge.uploadAttachment(
        token: 't',
        name: 'synthetic.txt',
        size: 4,
        bytes: Stream.value([1, 2, 3]),
      )).status,
      'upload_not_sent',
    );
    expect(web.calls.map((c) => c['operation']), [
      'upload_begin',
      'upload_chunk',
      'upload_abort',
    ]);
  });
  test(
    'removal and recovery poll without repeating the school mutation',
    () async {
      var polls = 0;
      final web = ScriptedWeb(
        (request) => switch (request['operation']) {
          'course_remove' => {'status': 'loading'},
          'course_settle' => {'status': ++polls < 2 ? 'busy' : 'removed'},
          'course_cancel' => {'status': 'loading'},
          _ => throw StateError('Unexpected operation'),
        },
      );
      final lease = Lease();
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: lease,
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect(
        (await bridge.removeCourse('synthetic-row-token')).status,
        'removed',
      );
      expect(web.calls.first['token'], 'synthetic-row-token');
      expect((await bridge.recoverCourses()).status, 'removed');
      expect(
        web.calls.where((r) => r['operation'] == 'course_remove'),
        hasLength(1),
      );
      lease.isActive = false;
      final count = web.calls.length;
      expect((await bridge.removeCourse('another')).status, 'stale');
      expect((await bridge.recoverCourses()).status, 'stale');
      expect(web.calls.length, count);
    },
  );
  test(
    'course open/page poll reads only; select and cancel are never retried',
    () async {
      var reads = 0;
      final web = ScriptedWeb(
        (request) => switch (request['operation']) {
          'course_open' || 'course_page' => {'status': 'loading'},
          'course_read' =>
            ++reads == 1
                ? {'status': 'busy'}
                : {
                    'status': 'course_ready',
                    'picker': {
                      'token': 'synthetic-session:1',
                      'rowIndex': '4',
                      'page': 'Page 1 / 2',
                      'hasPrevious': false,
                      'hasNext': true,
                      'candidates': courseFixture().candidates,
                    },
                  },
          'course_choose' => {'status': 'write_failed'},
          'course_cancel' => {'status': 'cancelled'},
          'course_release' => {'status': 'released'},
          _ => throw StateError('Unexpected operation'),
        },
      );
      final lease = Lease();
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: lease,
        portal: Uri.parse('https://portal.example.edu'),
      );
      final opened = await bridge.openCourses('4');
      expect(opened.picker!.rowIndex, '4');
      final paged = await bridge.pageCourses(opened.picker!, true);
      expect(paged.picker, isNotNull);
      expect(
        (await bridge.chooseCourse(
          LeaveCourseChoice(paged.picker!, paged.picker!.candidates.first),
        )).status,
        'write_failed',
      );
      expect((await bridge.cancelCourses()).status, 'cancelled');
      expect((await bridge.releaseCourses()).status, 'released');
      expect(web.calls.map((c) => c['operation']), [
        'course_open',
        'course_read',
        'course_read',
        'course_page',
        'course_read',
        'course_choose',
        'course_cancel',
        'course_release',
      ]);
      lease.isActive = false;
      expect((await bridge.openCourses('4')).status, 'stale');
      expect(
        (await bridge.chooseCourse(
          LeaveCourseChoice(paged.picker!, paged.picker!.candidates.first),
        )).status,
        'stale',
      );
      expect(web.calls.length, 8);
    },
  );
  test(
    'slow course rendering beyond five seconds only polls the same opened browser',
    () async {
      var reads = 0;
      final web = ScriptedWeb((request) {
        if (request['operation'] == 'course_open') return {'status': 'loading'};
        expect(request['operation'], 'course_read');
        if (++reads <= 26) return {'status': 'loading'};
        return {
          'status': 'course_ready',
          'picker': {
            'token': 'synthetic-slow:1',
            'rowIndex': '4',
            'page': 'Page 1 / 1',
            'hasPrevious': false,
            'hasNext': false,
            'candidates': courseFixture().candidates,
          },
        };
      });
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect((await bridge.openCourses('4')).picker, isNotNull);
      expect(reads, 27);
      expect(
        web.calls.where((c) => c['operation'] == 'course_open'),
        hasLength(1),
      );
    },
  );
  test(
    'a stalled course read times out without reopening or replaying the operation',
    () async {
      final pending = Completer<Object?>();
      final web = ScriptedWeb((request) {
        if (request['operation'] == 'course_open') return {'status': 'loading'};
        return pending.future;
      });
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect((await bridge.openCourses('4')).status, 'unavailable');
      expect(web.calls.map((call) => call['operation']), [
        'course_open',
        'course_read',
      ]);
      bridge.close();
      pending.complete({'status': 'loading'});
      await Future<void>.delayed(Duration.zero);
      expect(web.calls, hasLength(2));
    },
  );
  test(
    'platform double JSON decoding, document binding and lease invalidation',
    () async {
      final lease = Lease(), web = Web();
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: lease,
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect((await bridge.attach()).status, 'ready');
      expect((await bridge.attach()).status, 'ready');
      expect(web.operations, ['attach', 'read']);
      lease.isActive = false;
      expect((await bridge.read()).status, 'stale');
      expect(web.operations.length, 2);
    },
  );
  test(
    'logout or disposal rejects a late response and clears access',
    () async {
      final lease = Lease(), web = Web()..pending = Completer<Object?>();
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: lease,
        portal: Uri.parse('https://portal.example.edu'),
      );
      final request = bridge.read();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      bridge.close();
      web.pending!.complete(
        jsonEncode({
          'status': 'ready',
          'fields': {},
          'reasons': [],
          'courses': [],
        }),
      );
      expect((await request).status, 'stale');
    },
  );

  test(
    'writes in dependency order and waits for each school readback',
    () async {
      final fields = <String, Object?>{};
      var busyReads = 0;
      final web = ScriptedWeb((request) {
        switch (request['operation']) {
          case 'validate':
            return {'status': 'validated'};
          case 'write':
            final changes = request['changes'] as Map<String, dynamic>;
            expect(changes, hasLength(1));
            final entry = changes.entries.single;
            fields[entry.key] = {'value': (entry.value as Map)['value']};
            busyReads = 1;
            return {'status': 'written'};
          case 'read':
            if (busyReads-- > 0) return {'status': 'busy'};
            return {
              'status': 'ready',
              'fields': fields,
              'reasons': [],
              'courses': [],
            };
          default:
            fail('unexpected operation');
        }
      });
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      final result = await bridge
          .write(LeaveApplicationForm(fields: const {}), {
            'details': 'Synthetic explanation',
            'endDate': '2026-09-17',
            'beginDate': '2026-09-16',
          });
      expect(result.status, 'written');
      expect(web.calls.map((c) => c['operation']), [
        'validate',
        'write',
        'read',
        'read',
        'write',
        'read',
        'read',
        'write',
        'read',
        'read',
      ]);
      expect(
        web.calls
            .where((c) => c['operation'] == 'write')
            .map((c) => (c['changes'] as Map).keys.single),
        ['beginDate', 'endDate', 'details'],
      );
    },
  );

  for (final failure in ['conflict', 'readonly', 'rejected', 'stale']) {
    test('whole patch $failure stops before any write', () async {
      final web = ScriptedWeb((_) => {'status': failure});
      final bridge = LeaveApplicationBridge(
        web: web,
        lease: Lease(),
        portal: Uri.parse('https://portal.example.edu'),
      );
      expect(
        (await bridge.write(LeaveApplicationForm(fields: const {}), {
          'details': 'Synthetic',
        })).status,
        failure,
      );
      expect(web.calls.map((c) => c['operation']), ['validate']);
    });
  }

  for (final writeFailure in [true, false]) {
    test(
      'partial write or unacknowledged value stops without replay ($writeFailure)',
      () async {
        final web = ScriptedWeb(
          (request) => switch (request['operation']) {
            'validate' => {'status': 'validated'},
            'write' => {'status': writeFailure ? 'write_failed' : 'written'},
            'read' => {
              'status': 'ready',
              'fields': <String, Object?>{},
              'reasons': [],
              'courses': [],
            },
            _ => throw StateError('unexpected operation'),
          },
        );
        final bridge = LeaveApplicationBridge(
          web: web,
          lease: Lease(),
          portal: Uri.parse('https://portal.example.edu'),
        );
        expect(
          (await bridge.write(LeaveApplicationForm(fields: const {}), {
            'mobile': '12345',
            'details': 'Do not write this later field',
          })).status,
          writeFailure ? 'write_failed' : 'conflict',
        );
        expect(web.calls.where((c) => c['operation'] == 'write'), hasLength(1));
      },
    );
  }
}
