import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/leave_application_form.dart';
import '../state/app_session_controller.dart';
import '../widgets/native_mirror_webview.dart';

enum LeaveSchoolSection { courses, attachment, review }

class LeaveBridgeResult {
  const LeaveBridgeResult(
    this.status, [
    this.form,
    this.picker,
    this.confirmation,
    this.schoolMessage,
  ]);
  final String status;
  final LeaveApplicationForm? form;
  final LeaveCoursePickerSnapshot? picker;
  final LeaveSubmitConfirmation? confirmation;

  /// School's user-facing receipt only. Kept in this page's memory, not logged.
  final String? schoolMessage;
}

class LeaveSubmitConfirmation {
  LeaveSubmitConfirmation.fromJson(Map<String, dynamic> json)
    : token = _text(json, 'token'),
      title = _text(json, 'title'),
      message = _text(json, 'message'),
      cancel = _text(json, 'cancel'),
      confirm = _text(json, 'confirm');
  final String token, title, message, cancel, confirm;
  static String _text(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String ||
        value.isEmpty ||
        value.length > (key == 'message' ? 8000 : 500)) {
      throw const FormatException('Unsupported school confirmation');
    }
    return value;
  }
}

/// A single live document and central session lease. No credential ownership.
class LeaveApplicationBridge {
  LeaveApplicationBridge({
    required this.web,
    required this.lease,
    required this.portal,
  });

  final NativeMirrorWebViewController web;
  final AppSessionLease lease;
  final Uri portal;
  final String _nonce = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  Future<String>? _source;
  bool _closed = false;
  bool _attached = false;
  bool _submissionAttempted = false;
  final _receipt = Completer<LeaveBridgeResult>();
  final _consumedDecisions = <String>{};
  LeaveBridgeResult? _received;

  /// Opt-in, origin/frame-filtered native callback. Never accept school data.
  LeaveBridgeResult? acceptSubmissionEvent(Map<String, dynamic> event) {
    if (!active ||
        !_submissionAttempted ||
        _received != null ||
        event.length != 2 ||
        event['nonce'] != _nonce ||
        !const {
          'submission_succeeded',
          'submission_failed',
          'submission_pending',
        }.contains(event['status'])) {
      return null;
    }
    final result = LeaveBridgeResult(event['status'] as String);
    _received = result;
    _receipt.complete(result);
    return result;
  }

  bool get active => !_closed && lease.isActive;
  void close() {
    _closed = true;
    _received = null;
  }

  Future<LeaveBridgeResult> attach({Duration? timeout}) async {
    final result = await _call(
      _attached ? 'read' : 'attach',
      const {},
      timeout,
    );
    if (result.form != null) _attached = true;
    return result;
  }

  Future<LeaveBridgeResult> read({Duration? timeout}) =>
      _call('read', const {}, timeout);

  /// Only polls the existing document; never dispatches or acknowledges again.
  Future<LeaveBridgeResult> readSubmissionResult() async {
    if (!active) return const LeaveBridgeResult('stale');
    if (!_submissionAttempted) {
      return const LeaveBridgeResult('submission_locked');
    }
    final result = await _call(
      'submit_status',
      const {},
      const Duration(seconds: 2),
    );
    if (!active) return const LeaveBridgeResult('stale');
    return _received ?? result;
  }

  Future<LeaveBridgeResult> submitConfirmed(String token) async {
    if (_submissionAttempted) {
      return const LeaveBridgeResult('submission_locked');
    }
    _submissionAttempted = true;
    final watch = Stopwatch()..start();
    final acknowledgement = await _call('acknowledge', {
      'token': token,
      'confirmed': true,
    });
    if (acknowledgement.status != 'acknowledged') return acknowledgement;
    final result = await _call('submit_confirmed', {
      'token': token,
      'confirmed': true,
    }, const Duration(seconds: 15) - watch.elapsed);
    if (result.status == 'submission_unavailable') _submissionAttempted = false;
    return _received ?? result;
  }

  Future<LeaveBridgeResult> resolveSubmission(
    LeaveSubmitConfirmation confirmation,
    bool confirmed,
  ) async {
    if (!_submissionAttempted || !_consumedDecisions.add(confirmation.token)) {
      return const LeaveBridgeResult('submission_locked');
    }
    final result = await _call('submit_decision', {
      'token': confirmation.token,
      'confirmed': confirmed,
    });
    if (result.status == 'submission_cancelled') _submissionAttempted = false;
    return _received ?? result;
  }

  /// Reads only; a timer/channel timeout cannot replay a submit or confirmation.
  Future<LeaveBridgeResult> waitSubmission({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (active && _submissionAttempted) {
      if (_received != null) return _received!;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final result = await Future.any([_call('submit_status'), _receipt.future])
          .timeout(
            remaining,
            onTimeout: () => const LeaveBridgeResult('submission_unconfirmed'),
          );
      if (!active) return const LeaveBridgeResult('stale');
      if (_received != null) return _received!;
      if (result.confirmation != null ||
          const {
            'submission_succeeded',
            'submission_failed',
            'submission_pending',
          }.contains(result.status)) {
        return result;
      }
      if (!const {
        'submission_unconfirmed',
        'loading',
        'busy',
      }.contains(result.status)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return LeaveBridgeResult(active ? 'submission_unconfirmed' : 'stale');
  }

  Future<LeaveBridgeResult> removeAttachment(String token, String key) => _call(
    'attachment_remove',
    {'token': token, 'key': key, 'confirmed': true},
  );

  Future<LeaveBridgeResult> uploadAttachment({
    required String token,
    required String name,
    required int size,
    required Stream<List<int>> bytes,
  }) async {
    var result = await _call('upload_begin', {
      'token': token,
      'name': name,
      'size': size,
    });
    if (result.status != 'upload_buffering') return result;
    var offset = 0;
    var dispatched = false;
    try {
      await for (final block in bytes.timeout(const Duration(seconds: 15))) {
        if (!active || offset + block.length > size) {
          throw const FormatException();
        }
        for (var start = 0; start < block.length; start += 65536) {
          final chunk = block.sublist(start, min(start + 65536, block.length));
          result = await _call('upload_chunk', {
            'offset': offset,
            'data': base64Encode(chunk),
          });
          if (result.status != 'upload_buffering') {
            throw const FormatException();
          }
          offset += chunk.length;
        }
      }
      if (offset != size) throw const FormatException();
      dispatched = true;
      result = await _call('upload_dispatch');
      if (result.status != 'upload_unconfirmed') return result;
      for (var attempt = 0; attempt < 50; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        result = await _call('upload_status');
        if (![
          'upload_unconfirmed',
          'busy',
          'loading',
        ].contains(result.status)) {
          return result;
        }
      }
      return const LeaveBridgeResult('upload_unconfirmed');
    } catch (_) {
      final aborted = await _call('upload_abort');
      if (!dispatched && aborted.status == 'cancelled') {
        return const LeaveBridgeResult('upload_not_sent');
      }
      return const LeaveBridgeResult('upload_unconfirmed');
    }
  }

  Future<LeaveBridgeResult> readUploadStatus() => _call('upload_status');
  Future<LeaveBridgeResult> retryCourseRead() => _waitCourses();
  Future<LeaveBridgeResult> focus(LeaveSchoolSection section) =>
      _call('focus', {'section': section.name});

  Future<LeaveBridgeResult> openCourses(String? rowIndex) async {
    final result = await _call('course_open', {'rowIndex': rowIndex});
    return result.status == 'loading' ? _waitCourses() : result;
  }

  Future<LeaveBridgeResult> _waitCourses([
    String operation = 'course_read',
  ]) async {
    // School modal/data render in separate turns and can take over 5 seconds
    // on mobile. Bound the whole wait, including the platform-channel reads;
    // a timeout leaves the original operation pending, never replays it.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    for (var attempt = 0; attempt < 75; attempt++) {
      if (!active) return const LeaveBridgeResult('stale');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final result = await _call(operation).timeout(
        remaining,
        onTimeout: () => const LeaveBridgeResult('unavailable'),
      );
      if (!['loading', 'busy'].contains(result.status)) return result;
    }
    return const LeaveBridgeResult('unavailable');
  }

  Future<LeaveBridgeResult> pageCourses(
    LeaveCoursePickerSnapshot snapshot,
    bool next,
  ) async {
    final result = await _call('course_page', {
      'token': snapshot.token,
      'direction': next ? 'next' : 'prev',
    });
    return result.status == 'loading' ? _waitCourses() : result;
  }

  Future<LeaveBridgeResult> cancelCourses() async {
    final result = await _call('course_cancel');
    return ['loading', 'busy'].contains(result.status)
        ? _waitCourses('course_settle')
        : result;
  }

  Future<LeaveBridgeResult> removeCourse(String token) async {
    final result = await _call('course_remove', {'token': token});
    return result.status == 'loading' ? _waitCourses('course_settle') : result;
  }

  /// Only reads/reconciles the existing operation, never repeats an add/delete.
  Future<LeaveBridgeResult> recoverCourses() => cancelCourses();
  Future<LeaveBridgeResult> releaseCourses() => _call('course_release');

  Future<LeaveBridgeResult> chooseCourse(LeaveCourseChoice choice) => _call(
    'course_choose',
    {'token': choice.snapshot.token, 'key': choice.candidate['key']},
  );
  Future<LeaveBridgeResult> write(
    LeaveApplicationForm baseline,
    Map<String, String> values, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final watch = Stopwatch()..start();
    Duration remaining() => timeout - watch.elapsed;
    Future<LeaveBridgeResult> call(String op, Map<String, Object?> args) =>
        _call(op, args, remaining());
    final changes = values.map(
      (key, value) =>
          MapEntry(key, {'before': baseline.field(key).value, 'value': value}),
    );
    final validation = await call('validate', {'changes': changes});
    if (validation.status != 'validated') return validation;
    // Match individual school field edits instead of firing dependent date
    // calculations together. A partial failure always stops for manual review.
    for (final key in [
      'beginDate',
      'beginTime',
      'endDate',
      'endTime',
      'mobile',
      'familyPhone',
      'reason',
      'details',
    ]) {
      if (!changes.containsKey(key)) continue;
      final result = await call('write', {
        'changes': {key: changes[key]},
      });
      if (result.status != 'written') return result;
      LeaveBridgeResult state = const LeaveBridgeResult('busy');
      for (var attempt = 0; attempt < 25; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        state = await read(timeout: remaining());
        if (state.status != 'busy' && state.status != 'loading') break;
      }
      if (state.form == null) return state;
      if (state.form!.field(key).value != values[key]) {
        return const LeaveBridgeResult('conflict');
      }
    }
    return const LeaveBridgeResult('written');
  }

  Future<LeaveBridgeResult> _call(
    String operation, [
    Map<String, Object?> arguments = const {},
    Duration? timeout,
  ]) async {
    if (!active) return const LeaveBridgeResult('stale');
    final watch = Stopwatch()..start();
    final budget = timeout == null || timeout > const Duration(seconds: 15)
        ? const Duration(seconds: 15)
        : timeout;
    Duration remaining() {
      final left = budget - watch.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException('School bridge timeout');
      }
      return left;
    }

    try {
      final source = await (_source ??= rootBundle.loadString(
        'assets/leave_application/bridge.js',
      )).timeout(remaining());
      if (!active) return const LeaveBridgeResult('stale');
      final evaluationBudget =
          remaining(); // Expired calls must not write later.
      final expiresAt = DateTime.now()
          .add(evaluationBudget)
          .millisecondsSinceEpoch;
      Object? raw = await web
          .evaluateJavascript(
            '$source(${jsonEncode({'origin': portal.origin, 'nonce': _nonce, 'operation': operation, ...arguments, 'expiresAt': expiresAt})});',
          )
          .timeout(evaluationBudget);
      if (!active) return const LeaveBridgeResult('stale');
      // Android may JSON-encode the already serialized result once more.
      for (var i = 0; i < 2 && raw is String; i++) {
        if (raw.length > 128 * 1024) {
          return const LeaveBridgeResult('unsupported');
        }
        raw = jsonDecode(raw);
      }
      if (raw is! Map<String, dynamic>) {
        return const LeaveBridgeResult('loading');
      }
      final status = raw['status'] as String? ?? 'unsupported';
      final result = LeaveBridgeResult(
        status,
        status == 'ready' ? LeaveApplicationForm.fromJson(raw) : null,
        status == 'course_ready'
            ? LeaveCoursePickerSnapshot.fromJson(
                raw['picker'] as Map<String, dynamic>,
              )
            : null,
        status == 'submission_confirmation'
            ? LeaveSubmitConfirmation.fromJson(
                raw['confirmation'] as Map<String, dynamic>,
              )
            : null,
        const {
                  'submission_succeeded',
                  'submission_failed',
                  'submission_pending',
                }.contains(status) &&
                raw['schoolMessage'] is String &&
                (raw['schoolMessage'] as String).length <= 1200
            ? raw['schoolMessage'] as String
            : null,
      );
      if (_submissionAttempted &&
          const {
            'submission_succeeded',
            'submission_failed',
            'submission_pending',
          }.contains(status) &&
          (_received == null || _received!.status == status)) {
        if (_received?.schoolMessage == null || result.schoolMessage != null) {
          _received = result;
        }
        if (!_receipt.isCompleted) _receipt.complete(LeaveBridgeResult(status));
      }
      return result;
    } on TimeoutException {
      return const LeaveBridgeResult('timeout');
    } catch (_) {
      return LeaveBridgeResult(
        [
              'write',
              'course_choose',
              'course_open',
              'course_remove',
              'course_cancel',
              'course_settle',
              'acknowledge',
              'submit_confirmed',
              'submit_decision',
              'upload_dispatch',
              'attachment_remove',
            ].contains(operation)
            ? 'write_failed'
            : 'unsupported',
      );
    }
  }
}
