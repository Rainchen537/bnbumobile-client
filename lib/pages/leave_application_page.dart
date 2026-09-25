import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/leave_application_form.dart';
import '../models/leave_course_timetable.dart';
import '../models/official_web_target.dart';
import '../models/web_session_snapshot.dart';
import '../services/leave_application_bridge.dart';
import '../services/official_url_policy.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/leave_application_editor.dart';
import '../widgets/leave_application_review.dart';
import '../widgets/leave_course_picker.dart';
import '../widgets/native_mirror_webview.dart';

/// Native inputs over the same school-owned Portal workflow document.
class LeaveApplicationPage extends StatefulWidget {
  const LeaveApplicationPage({
    super.key,
    required this.controller,
    this.onReturnHome,
  });
  final AppSessionController controller;
  final VoidCallback? onReturnHome;

  @override
  State<LeaveApplicationPage> createState() => _LeaveApplicationPageState();
}

class _LeaveApplicationPageState extends State<LeaveApplicationPage> {
  final _web = NativeMirrorWebViewController();
  Future<WebSessionSnapshot>? _session;
  LeaveApplicationBridge? _bridge;
  AppSessionLease? _lease;
  LeaveApplicationForm? _form;
  bool _busy = false;
  bool _expired = false;
  String? _error;
  String? _courseError;
  int _generation = 0;
  int _recoveries = 0;
  int _editorRevision = 0;
  int _readRevision = 0;
  bool _dirty = false;
  bool _writeBlocked = false;
  bool _submissionLocked = false;
  bool _submissionSucceeded = false;
  bool _successPresented = false;
  DialogRoute<void>? _successRoute;
  String? _schoolMessage;
  bool _documentFailed = false;
  String? _attachmentError;
  bool _uploadingAttachment = false;
  DialogRoute<bool>? _reviewRoute;
  ModalBottomSheetRoute<LeaveCourseChoice>? _courseRoute;

  void _dismissCoursePicker() {
    final success = _successRoute;
    _successRoute = null;
    if (success != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (success.isActive) success.navigator?.removeRoute(success);
      });
    }
    final review = _reviewRoute;
    _reviewRoute = null;
    if (review != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (review.isActive) review.navigator?.removeRoute(review);
      });
    }
    final route = _courseRoute;
    _courseRoute = null;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  Uri get _target => OfficialUrlPolicy.requireTrustedPageUrl(
    AppConfig.bnbuLeaveApplicationUrl,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_checkSession);
    _prepare();
  }

  void _prepare() {
    _dismissCoursePicker();
    _bridge?.close();
    _generation++;
    _form = null;
    _dirty = false;
    _writeBlocked = false;
    _submissionLocked = false;
    _submissionSucceeded = false;
    _successPresented = false;
    _schoolMessage = null;
    _documentFailed = false;
    _attachmentError = null;
    _uploadingAttachment = false;
    _error = null;
    _courseError = null;
    _lease = widget.controller.captureSessionLease();
    _expired = _lease == null;
    if (_expired) {
      _session = null;
      return;
    }
    _bridge = LeaveApplicationBridge(
      web: _web,
      lease: _lease!,
      portal: _target,
    );
    _session = widget.controller.prepareOfficialWebSession(
      OfficialWebTarget.portal,
    );
  }

  void _checkSession() {
    if (!mounted || _expired || _lease?.isActive == true) return;
    _dismissCoursePicker();
    _bridge?.close();
    setState(() {
      _generation++;
      _form = null;
      _expired = true;
      _schoolMessage = null;
      _busy = false;
      _error = null;
      _courseError = null;
      _attachmentError = null;
      _uploadingAttachment = false;
    });
  }

  @override
  void didUpdateWidget(LeaveApplicationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_checkSession);
      widget.controller.addListener(_checkSession);
      _prepare();
    }
  }

  @override
  void dispose() {
    _dismissCoursePicker();
    _generation++;
    _bridge?.close();
    widget.controller.removeListener(_checkSession);
    _form = null;
    _schoolMessage = null;
    super.dispose();
  }

  bool _current(int generation) =>
      mounted && generation == _generation && _lease?.isActive == true;

  Future<void> _read({bool attach = false}) async {
    if (_submissionLocked || _documentFailed) return;
    final readRevision = ++_readRevision;
    final generation = _generation;
    final bridge = _bridge;
    if (bridge == null || !_current(generation)) return;
    final watch = Stopwatch()..start();
    // SPA fields may load after the main frame. Reads are bounded; writes are
    // never retried, and no additional SSO client is created.
    for (var attempt = 0; attempt < 25; attempt++) {
      final remaining = const Duration(seconds: 20) - watch.elapsed;
      if (remaining <= Duration.zero) break;
      final result = attach
          ? await bridge.attach(timeout: remaining)
          : await bridge.read(timeout: remaining);
      if (!_current(generation) || readRevision != _readRevision) return;
      if (result.form != null) {
        setState(() {
          _form = result.form;
          _error = null;
        });
        return;
      }
      if (!['loading', 'busy'].contains(result.status)) {
        // Keep an existing draft visible, but do not write against a form
        // whose latest school state could not be verified.
        if (_form != null) setState(() => _writeBlocked = true);
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!_current(generation)) return;
    }
    if (_current(generation) && readRevision == _readRevision) {
      setState(() => _error = '暂时无法读取申请资料，请检查网络后重新读取。');
    }
  }

  void _documentLoadFailed(int generation) {
    if (!_current(generation)) return;
    // Once success is verified, a school redirect/load failure must not
    // dismiss the app-owned acknowledgement or undo that receipt.
    if (_submissionSucceeded) return;
    _bridge?.close();
    _dismissCoursePicker();
    if (_submissionLocked) return;
    _readRevision++;
    setState(() {
      _documentFailed = true;
      _writeBlocked = _form != null;
      _error = '暂时无法读取申请资料，请检查网络后重新读取。';
    });
  }

  Future<void> _recover(int documentGeneration) async {
    if (!_current(documentGeneration) ||
        _recoveries >= 2 ||
        _expired ||
        _submissionLocked ||
        (_documentFailed && _form != null) ||
        _busy) {
      return;
    }
    _recoveries++;
    final generation = _generation;
    _bridge?.close();
    setState(() {
      _busy = true;
      _form = null;
    });
    try {
      await widget.controller.resetOfficialWebSession(OfficialWebTarget.portal);
      if (!_current(generation)) return;
      setState(() {
        _busy = false;
        _prepare();
      });
    } catch (_) {
      if (!_current(generation)) return;
      setState(() {
        _busy = false;
        _error = '学校页面加载失败，请检查网络后重试。';
      });
    }
  }

  Future<void> _uploadAttachment() async {
    final bridge = _bridge;
    if (_busy ||
        _writeBlocked ||
        bridge == null ||
        _form == null ||
        _attachmentError != null) {
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      // The uploader may have mounted after the first form read.
      await _read();
      if (!_current(generation) || _documentFailed) return;
      if (_error != null || _form?.completion.canUpload != true) {
        setState(() => _attachmentError = '暂时无法确认学校附件控件，请重新读取。');
        return;
      }
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: true,
      );
      if (!_current(generation) || picked == null || picked.files.length != 1) {
        return;
      }
      final file = picked.files.single;
      // Picking can outlive the five-minute handle. Refresh without flushing
      // or discarding native drafts before handing the file to the school.
      await _read();
      if (!_current(generation) || _documentFailed) return;
      final completion = _form?.completion;
      if (_error != null || completion == null || !completion.canUpload) {
        setState(() => _attachmentError = '暂时无法确认学校附件控件，请重新读取。');
        return;
      }
      if (file.size <= 0 || file.size > completion.maxBytes) {
        setState(() => _attachmentError = '附件为空或超过学校允许的大小。');
        return;
      }
      setState(() => _uploadingAttachment = true);
      // Streams are read only for the selected file; no copy into app storage.
      final result = await bridge.uploadAttachment(
        token: completion.token,
        name: file.name,
        size: file.size,
        bytes: file.readStream ?? file.xFile.openRead(),
      );
      if (!_current(generation)) return;
      if (result.status != 'uploaded') {
        setState(
          () => _attachmentError = result.status == 'upload_not_sent'
              ? '所选文件未能读取，尚未上传。请重新选择附件。'
              : '附件上传尚未得到学校确认，请核对状态；不会自动重传。',
        );
      }
      await _read();
    } catch (_) {
      if (_current(generation)) {
        setState(() => _attachmentError = '无法读取或上传所选附件，请核对状态。');
      }
    } finally {
      if (_current(generation)) {
        setState(() {
          _busy = false;
          _uploadingAttachment = false;
        });
      }
    }
  }

  Future<void> _readAttachments() async {
    if (_busy || _writeBlocked || _bridge == null) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final result = await _bridge!.readUploadStatus();
      if (!_current(generation)) return;
      await _read();
      if (!_current(generation)) return;
      if (_error == null &&
          (result.status == 'uploaded' ||
              (result.status == 'upload_idle' &&
                  _form?.completion.canUpload == true))) {
        setState(() => _attachmentError = null);
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _removeAttachment(LeaveSchoolAttachment file) async {
    if (_busy ||
        _writeBlocked ||
        _bridge == null ||
        _form == null ||
        _attachmentError != null) {
      return;
    }
    final generation = _generation;
    final baseline = _form!;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('移除此申请中的附件？'),
        content: Text(file.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const BnbuText('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const BnbuText('移除'),
          ),
        ],
      ),
    );
    _reviewRoute = route;
    setState(() => _busy = true);
    try {
      final confirmed = await Navigator.of(context).push(route);
      if (_reviewRoute == route) _reviewRoute = null;
      if (!_current(generation) ||
          confirmed != true ||
          !identical(baseline, _form)) {
        return;
      }
      final result = await _bridge!.removeAttachment(
        baseline.completion.token,
        file.key,
      );
      if (!_current(generation)) return;
      await _read();
      if (!_current(generation)) return;
      if (result.status != 'written' ||
          _form?.completion.files.length !=
              baseline.completion.files.length - 1) {
        setState(() => _attachmentError = '学校未确认附件移除，请核对状态；不会自动重试。');
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _openSection(
    LeaveSchoolSection section,
    Map<String, String> changes, {
    String? rowIndex,
  }) async {
    if (_busy || _expired || _bridge == null || _writeBlocked) {
      return;
    }
    if (_courseError != null) {
      setState(() => _error = '请先重新读取课程，核对学校状态后再提交。');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final generation = _generation;
    final bridge = _bridge!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (section == LeaveSchoolSection.review &&
          _form != null &&
          await _showMissingRequired(_form!, changes)) {
        return;
      }
      if (!_current(generation) || _documentFailed) return;
      // Course selection must not flush incomplete date/reason/phone drafts.
      // Keeping this editor instance also preserves those drafts on readback.
      if (section == LeaveSchoolSection.review && changes.isNotEmpty) {
        final baseline = _form;
        if (baseline == null) return;
        final result = await bridge.write(baseline, changes);
        if (!_current(generation)) return;
        if (result.status != 'written') {
          setState(() {
            _writeBlocked = true;
            _error = '学校尚未确认更改，请重新读取表单核对；不会自动重试或提交。';
          });
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!_current(generation)) return;
        await _read();
        if (!_current(generation)) return;
        if (_error != null ||
            changes.entries.any(
              (entry) => _form?.field(entry.key).value != entry.value,
            )) {
          setState(() {
            _writeBlocked = true;
            _error = '学校尚未确认更改，请重新读取表单核对；不会自动重试或提交。';
          });
          return;
        }
      }
      if (!_current(generation)) return;
      if (section == LeaveSchoolSection.review) {
        await _reviewAndSubmit(generation, bridge);
        return;
      }
      if (section == LeaveSchoolSection.courses) {
        final opened = await bridge.openCourses(rowIndex);
        if (!mounted || !_current(generation) || _documentFailed) return;
        if (opened.picker != null) {
          final route = leaveCoursePickerRoute(
            context: context,
            builder: (_) => LeaveCoursePicker(
              initial: opened.picker!,
              selectedCourses: _form?.courses ?? const [],
              onSelect: rowIndex == null
                  ? (choice) =>
                        _chooseCourseAndContinue(generation, bridge, choice)
                  : null,
              onReconcile: rowIndex == null
                  ? (choice) =>
                        _confirmCourseAndContinue(generation, bridge, choice)
                  : null,
              onPage: (snapshot, next) =>
                  _documentFailed || !_current(generation)
                  ? Future.value(const LeaveBridgeResult('stale'))
                  : bridge.pageCourses(snapshot, next),
              onRetry: () => _documentFailed || !_current(generation)
                  ? Future.value(const LeaveBridgeResult('stale'))
                  : bridge.retryCourseRead(),
            ),
          );
          _courseRoute = route;
          final choice = await Navigator.of(context).push(route);
          if (_courseRoute == route) _courseRoute = null;
          if (!_current(generation) || _documentFailed) return;
          final result = choice == null
              ? await bridge.cancelCourses()
              : await bridge.chooseCourse(choice);
          if (!_current(generation)) return;
          if (choice == null && result.status == 'cancelled') {
            final read = await bridge.read();
            if (!_current(generation)) return;
            if (read.form != null) {
              setState(() => _form = read.form);
              return;
            }
          }
          if (choice != null && result.status == 'written') {
            final form = await _readSelectedCourse(generation, bridge, choice);
            if (!_current(generation)) return;
            if (form != null) {
              setState(() => _form = form);
              return;
            }
          }
          setState(() {
            _courseError = '学校尚未确认课程操作，请重新读取；不会重复添加、移除或提交。';
          });
          return;
        }
        // A read/open failure never automatically switches to the school UI
        // or replays an uncertain write. Recovery is explicit and bounded.
        setState(() => _courseError = '暂时无法读取学校课程，请重试。');
        return;
      }
      // All supported sections have app-owned controls. Unknown/unavailable
      // operations must stay in the native form, never expose the school UI.
      setState(() => _error = '此操作暂不可用，请重新读取表单。');
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<LeaveApplicationForm?> _readSelectedCourse(
    int generation,
    LeaveApplicationBridge bridge,
    LeaveCourseChoice choice,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    // 75 x 200ms covers the documented 15s window; 25 attempts only waited 5s.
    // Only read after dispatch. No timeout path clicks the candidate again.
    for (var attempt = 0; attempt < 75; attempt++) {
      if (!_current(generation) || _documentFailed) return null;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final remaining = deadline.difference(DateTime.now());
      if (!_current(generation) ||
          _documentFailed ||
          remaining <= Duration.zero) {
        return null;
      }
      final read = await bridge.read(timeout: remaining);
      if (!_current(generation) || _documentFailed) return null;
      if (read.form?.courses.any(
            (row) =>
                row['index'] == choice.snapshot.rowIndex &&
                LeaveCourseTimetableData.sameCourse(row, choice.candidate),
          ) ==
          true) {
        return read.form;
      }
      if (!['ready', 'loading', 'busy'].contains(read.status)) return null;
    }
    return null;
  }

  Future<LeaveBridgeResult> _chooseCourseAndContinue(
    int generation,
    LeaveApplicationBridge bridge,
    LeaveCourseChoice choice,
  ) async {
    if (!_current(generation) || _documentFailed || _courseError != null) {
      return const LeaveBridgeResult('stale');
    }
    final result = await bridge.chooseCourse(choice);
    if (!_current(generation) || _documentFailed) {
      return const LeaveBridgeResult('stale');
    }
    if (result.status == 'written') {
      return _confirmCourseAndContinue(generation, bridge, choice);
    }
    setState(() => _courseError = '学校尚未确认课程操作，请重新读取；不会重复添加、移除或提交。');
    return const LeaveBridgeResult('selection_unconfirmed');
  }

  /// Shared by initial readback and explicit read-only recovery in the grid.
  Future<LeaveBridgeResult> _confirmCourseAndContinue(
    int generation,
    LeaveApplicationBridge bridge,
    LeaveCourseChoice choice,
  ) async {
    final form = await _readSelectedCourse(generation, bridge, choice);
    if (!_current(generation) || _documentFailed) {
      return const LeaveBridgeResult('stale');
    }
    if (form == null) {
      setState(() => _courseError = '学校尚未确认课程操作，请重新读取；不会重复添加、移除或提交。');
      return const LeaveBridgeResult('selection_unconfirmed');
    }
    setState(() {
      _form = form;
      _courseError = null;
    });
    var next = await bridge.openCourses(null);
    final pageDeadline = DateTime.now().add(const Duration(seconds: 15));
    for (var page = 0; page < 20; page++) {
      if (!_current(generation) ||
          _documentFailed ||
          next.picker == null ||
          !next.picker!.hasNext ||
          next.picker!.page == choice.snapshot.page ||
          DateTime.now().isAfter(pageDeadline)) {
        break;
      }
      next = await bridge.pageCourses(next.picker!, true);
    }
    if (!_current(generation) || _documentFailed) {
      return const LeaveBridgeResult('stale');
    }
    return LeaveBridgeResult(next.status, form, next.picker);
  }

  Future<bool> _showMissingRequired(
    LeaveApplicationForm form, [
    Map<String, String> changes = const {},
  ]) async {
    final missing = form.missingRequired(changes);
    if (missing.isEmpty) return false;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('请先填写学校要求的必填内容。'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final label in missing)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: BnbuText(label),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const BnbuText('返回修改'),
          ),
        ],
      ),
    );
    _reviewRoute = route;
    await Navigator.of(context).push(route);
    if (_reviewRoute == route) _reviewRoute = null;
    return true;
  }

  Future<void> _reviewAndSubmit(
    int generation,
    LeaveApplicationBridge bridge,
  ) async {
    await _read();
    if (!mounted || !_current(generation) || _documentFailed) return;
    if (_writeBlocked || _error != null) return;
    final baseline = _form;
    if (baseline != null && await _showMissingRequired(baseline)) return;
    if (!mounted || !_current(generation) || _documentFailed) return;
    if (baseline == null ||
        !baseline.completion.canSubmit ||
        _attachmentError != null) {
      setState(() => _error = '学校须知、附件或提交控件尚未确认，暂不能提交。');
      return;
    }
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LeaveApplicationReview(form: baseline),
    );
    _reviewRoute = route;
    final confirmed = await Navigator.of(context).push(route);
    if (_reviewRoute == route) _reviewRoute = null;
    if (!_current(generation) ||
        _documentFailed ||
        confirmed != true ||
        !identical(baseline, _form)) {
      return;
    }
    setState(() {
      _submissionLocked = true;
      _writeBlocked = true;
      _dirty = false;
    });
    var result = await bridge.submitConfirmed(baseline.completion.token);
    if (!_current(generation)) return;
    if (_needsSubmissionRead(result)) {
      result = await bridge.waitSubmission();
    }
    if (!mounted || !_current(generation)) return;
    await _handleSubmissionResult(generation, bridge, result);
  }

  bool _needsSubmissionRead(LeaveBridgeResult result) => const {
    'submission_unconfirmed',
    'timeout',
    'write_failed',
    'loading',
    'busy',
  }.contains(result.status);

  Future<void> _handleSubmissionResult(
    int generation,
    LeaveApplicationBridge bridge,
    LeaveBridgeResult result,
  ) async {
    final handled = <String>{};
    while (result.confirmation != null) {
      if (!mounted || !_current(generation)) return;
      final confirmation = result.confirmation!;
      // The school may chain its custom summary and ordinary confirmation.
      // Each stage needs a fresh user choice; never loop on a replayed token.
      if (handled.length >= 2 || !handled.add(confirmation.token)) {
        result = const LeaveBridgeResult('submission_unconfirmed');
        break;
      }
      final schoolRoute = DialogRoute<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(confirmation.title),
          content: SingleChildScrollView(child: Text(confirmation.message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(confirmation.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmation.confirm),
            ),
          ],
        ),
      );
      _reviewRoute = schoolRoute;
      final decision = await Navigator.of(context).push(schoolRoute);
      if (_reviewRoute == schoolRoute) _reviewRoute = null;
      if (!_current(generation) || decision == null) return;
      result = await bridge.resolveSubmission(confirmation, decision);
      if (_needsSubmissionRead(result)) {
        result = await bridge.waitSubmission();
      }
      if (!_current(generation)) return;
    }
    if (const {
      'submission_cancelled',
      'submission_unavailable',
    }.contains(result.status)) {
      setState(() {
        _submissionLocked = false;
        _writeBlocked = false;
      });
      await _read();
      if (!_current(generation)) return;
      // A known pre-send cancel permits recovery, not a claim that a failed
      // read has restored a writable school form.
      if (_writeBlocked || _error != null) return;
    }
    // Fetch the designated school message while this same document survives.
    // A navigation/timeout cannot erase a verified native receipt.
    if (const {
      'submission_succeeded',
      'submission_failed',
      'submission_pending',
    }.contains(result.status)) {
      final detail = await bridge.readSubmissionResult();
      if (!_current(generation)) return;
      if (detail.status == result.status) result = detail;
    }
    _showSubmissionResult(result);
  }

  Future<void> _refreshSubmissionResult() async {
    if (_busy || !_submissionLocked || _expired || _bridge == null) return;
    final generation = _generation;
    final bridge = _bridge!;
    setState(() => _busy = true);
    try {
      final result = await bridge.readSubmissionResult();
      if (!_current(generation)) return;
      await _handleSubmissionResult(generation, bridge, result);
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  void _showSubmissionResult(LeaveBridgeResult result) {
    setState(() {
      if (_submissionSucceeded && result.status != 'submission_succeeded') {
        return;
      }
      _submissionSucceeded = result.status == 'submission_succeeded';
      if (result.schoolMessage != null) _schoolMessage = result.schoolMessage;
      _error = switch (result.status) {
        'submission_succeeded' => '学校已确认申请提交成功，请等待审批。',
        'submission_failed' => '学校返回提交失败，申请未确认成功。请核对填写内容；不会自动重复提交。',
        'submission_pending' => '学校返回了后续处理要求，当前尚不能确认申请成功。为避免重复申请，已停止重试。',
        'submission_cancelled' => '已取消学校提交确认，可以继续修改。',
        'submission_unavailable' => '学校提交回执暂不可用，本次未触发提交，请稍后重试。',
        _ => '学校未确认提交结果。为避免重复申请，已停止重试；当前不能确认申请成功。',
      };
    });
    if (_submissionSucceeded && !_successPresented) {
      _successPresented = true;
      final generation = _generation;
      // Receipt callbacks and their detail reads can both report success.
      // Present once, after any school-confirmation route has settled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_current(generation)) return;
        final navigator = Navigator.of(context);
        final route = DialogRoute<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const BnbuText('申请提交成功'),
              content: const BnbuText('请等待审批。'),
              actions: [
                FilledButton(
                  onPressed: () {
                    if (!_current(generation)) return;
                    final success = _successRoute;
                    _successRoute = null;
                    if (success == null) return;
                    navigator.removeRoute(success);
                    setState(() {
                      _dirty = false;
                      _busy = false;
                    });
                    widget.onReturnHome?.call();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_current(generation)) {
                        navigator.popUntil((route) => route.isFirst);
                      }
                    });
                  },
                  child: const BnbuText('返回'),
                ),
              ],
            ),
          ),
        );
        _successRoute = route;
        unawaited(navigator.push(route));
      });
    }
  }

  Future<void> _removeCourse(Map<String, String> row) async {
    final token = row['token'];
    if (_busy ||
        _expired ||
        _writeBlocked ||
        _courseError != null ||
        _bridge == null ||
        token == null ||
        token.isEmpty) {
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final result = await _bridge!.removeCourse(token);
      if (!_current(generation)) return;
      if (result.status == 'removed') {
        final read = await _bridge!.read();
        if (!_current(generation)) return;
        if (read.form != null &&
            !read.form!.courses.any((r) => r['index'] == row['index'])) {
          setState(() => _form = read.form);
          return;
        }
      }
      setState(() => _courseError = '学校尚未确认课程操作，请重新读取；不会重复添加、移除或提交。');
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _recoverCourses() async {
    if (_busy || _expired || _writeBlocked || _bridge == null) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final result = await _bridge!.recoverCourses();
      if (!_current(generation)) return;
      if (!['cancelled', 'removed'].contains(result.status)) {
        setState(() => _courseError = '课程操作仍待学校确认，请稍后重新读取；不会重复操作。');
        return;
      }
      final read = await _bridge!.read();
      if (!_current(generation) || read.form == null) return;
      setState(() {
        _form = read.form;
        _courseError = null;
      });
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _reloadForm() async {
    if (_busy || _expired || _submissionLocked || _bridge == null) return;
    final generation = _generation;
    if (_documentFailed) {
      // A failed initial load has no draft or school mutation to replay.
      // Recreate only its hidden document using the same prepared session.
      if (_form == null && _courseError == null) {
        _bridge!.close();
        setState(() {
          _generation++;
          _readRevision++;
          _documentFailed = false;
          _error = null;
          _bridge = LeaveApplicationBridge(
            web: _web,
            lease: _lease!,
            portal: _target,
          );
        });
      } else {
        setState(() => _error = '连接已中断，当前填写已保留。请重新打开请假申请后核对学校状态。');
      }
      return;
    }
    if (!await _confirmDiscard() || !_current(generation) || _busy) return;
    setState(() => _busy = true);
    try {
      // Reconcile an existing operation first. Never reload the document,
      // discard an uncertain school mutation, or replay it during recovery.
      if (_form != null || _courseError != null) {
        final settled = await _bridge!.recoverCourses();
        if (!_current(generation)) return;
        if (!['cancelled', 'removed'].contains(settled.status)) {
          setState(() => _error = '课程操作仍待学校确认，请稍后重新读取；不会重复操作。');
          return;
        }
      }
      await _read(attach: true);
      if (!_current(generation)) return;
      if (_error == null && _form != null) {
        setState(() {
          _dirty = false;
          _writeBlocked = false;
          _courseError = null;
          _editorRevision++;
        });
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const BnbuText('放弃未同步的填写？'),
            content: const BnbuText('尚未写入学校表单的内容将被清除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const BnbuText('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const BnbuText('放弃'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        if (await _confirmDiscard() && mounted) {
          setState(() => _dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
      child: Scaffold(
        backgroundColor: tokens.canvas,
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(
            title: const BnbuText('请假申请'),
            actions: [
              if (!_expired && !_submissionLocked)
                TextButton(
                  onPressed: _busy || _form == null ? null : _reloadForm,
                  child: const BnbuText('重新读取表单'),
                ),
            ],
          ),
        ),
        body: _expired
            ? const Center(child: BnbuText('登录状态已变化，请重新打开请假申请。'))
            : FutureBuilder<WebSessionSnapshot>(
                future: _session,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: BnbuLoadingState(title: '正在连接学校系统'),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Center(
                      child: BnbuErrorState(
                        title: '学校页面加载失败',
                        message: '学校页面加载失败，请检查网络后重试。',
                        action: TextButton(
                          onPressed: () => setState(_prepare),
                          child: const BnbuText('重试'),
                        ),
                      ),
                    );
                  }
                  final generation = _generation;
                  return Column(
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: BnbuText(_error!),
                        ),
                      if (_schoolMessage?.isNotEmpty == true)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SelectableText(_schoolMessage!),
                          ),
                        ),
                      if (_submissionLocked && !_busy && !_submissionSucceeded)
                        TextButton.icon(
                          onPressed: _refreshSubmissionResult,
                          icon: const Icon(LucideIcons.refreshCw300),
                          label: const BnbuText('查询学校提交结果'),
                        ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ExcludeSemantics(
                              child: IgnorePointer(
                                child: NativeMirrorWebView(
                                  key: ValueKey('leave-document-$_generation'),
                                  content: NativeWebContent.url(
                                    OfficialUrlPolicy.authenticatedEntryFor(
                                      OfficialWebTarget.portal,
                                      _target,
                                    ).toString(),
                                  ),
                                  session: snapshot.data!,
                                  controller: _web,
                                  observeLeaveSubmission: true,
                                  onLeaveSubmission: (event) {
                                    if (!_current(generation)) return;
                                    final result = _bridge
                                        ?.acceptSubmissionEvent(event);
                                    if (result != null) {
                                      _showSubmissionResult(result);
                                      // A receipt can arrive after automatic waiting
                                      // ended. Also fetch its bounded display text.
                                      final bridge = _bridge!;
                                      unawaited(
                                        bridge.readSubmissionResult().then((
                                          detail,
                                        ) {
                                          if (_current(generation) &&
                                              detail.status == result.status) {
                                            _showSubmissionResult(detail);
                                          }
                                        }),
                                      );
                                    }
                                  },
                                  onPageFinished: () {
                                    if (_current(generation)) {
                                      unawaited(_read(attach: true));
                                    }
                                  },
                                  onPageFailed: () =>
                                      _documentLoadFailed(generation),
                                  onAuthenticationRequired: () =>
                                      _recover(generation),
                                  onRetry: () => _recover(generation),
                                  onSessionCookiesChanged: (cookies) async {
                                    if (_current(generation)) {
                                      await widget.controller
                                          .reconcileOfficialWebSession(
                                            OfficialWebTarget.portal,
                                            cookies,
                                          );
                                    }
                                  },
                                ),
                              ),
                            ),
                            if (_form != null)
                              ColoredBox(
                                color: tokens.canvas,
                                child: LeaveApplicationEditor(
                                  key: ValueKey(_editorRevision),
                                  form: _form!,
                                  busy: _busy,
                                  writeBlocked: _writeBlocked,
                                  submissionLocked: _submissionLocked,
                                  submissionSucceeded: _submissionSucceeded,
                                  onOpenSchool: _openSection,
                                  courseError: _courseError,
                                  onRemoveCourse: _removeCourse,
                                  onRecoverCourses: _recoverCourses,
                                  onAddAttachment: _uploadAttachment,
                                  onRemoveAttachment: _removeAttachment,
                                  onReadAttachments: _readAttachments,
                                  attachmentError: _attachmentError,
                                  uploadingAttachment: _uploadingAttachment,
                                  onSelectCourse: (index, changes) =>
                                      _openSection(
                                        LeaveSchoolSection.courses,
                                        changes,
                                        rowIndex: index,
                                      ),
                                  onDirtyChanged: (dirty) =>
                                      setState(() => _dirty = dirty),
                                ),
                              ),
                            if (_form == null)
                              ColoredBox(
                                color: tokens.canvas,
                                child: Center(
                                  child: _error == null
                                      ? const BnbuLoadingState(
                                          title: '正在读取学校表单',
                                        )
                                      : TextButton.icon(
                                          onPressed: _busy ? null : _reloadForm,
                                          icon: const Icon(
                                            LucideIcons.refreshCw300,
                                          ),
                                          label: const BnbuText('重新读取申请资料'),
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
