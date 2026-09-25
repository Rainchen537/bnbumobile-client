import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/leave_application_form.dart';
import '../services/leave_application_bridge.dart';
import '../theme/app_theme.dart';
import 'bnbu_loading.dart';
import 'leave_course_timetable.dart';

/// Keep an explicit route so an expired school document can remove its picker.
ModalBottomSheetRoute<LeaveCourseChoice> leaveCoursePickerRoute({
  required BuildContext context,
  required WidgetBuilder builder,
}) => ModalBottomSheetRoute<LeaveCourseChoice>(
  builder: builder,
  capturedThemes: InheritedTheme.capture(
    from: context,
    to: Navigator.of(context).context,
  ),
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 900),
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  settings: const RouteSettings(name: 'leave-course-picker'),
);

/// Shows only rows read from the school's live course browser. Row selection
/// returns an ephemeral handle; the page owns validation and school writeback.
class LeaveCoursePicker extends StatefulWidget {
  const LeaveCoursePicker({
    super.key,
    required this.initial,
    required this.onPage,
    this.onRetry,
    this.selectedCourses = const [],
    this.onSelect,
    this.onReconcile,
  });
  final LeaveCoursePickerSnapshot initial;
  final Future<LeaveBridgeResult> Function(LeaveCoursePickerSnapshot, bool)
  onPage;
  final Future<LeaveBridgeResult> Function()? onRetry;
  final Future<LeaveBridgeResult> Function(LeaveCourseChoice)? onSelect;
  final Future<LeaveBridgeResult> Function(LeaveCourseChoice)? onReconcile;

  /// School-confirmed rows from the current form, never optimistic selections.
  final List<Map<String, String>> selectedCourses;

  @override
  State<LeaveCoursePicker> createState() => _LeaveCoursePickerState();
}

class _LeaveCoursePickerState extends State<LeaveCoursePicker> {
  late var _snapshot = widget.initial;
  late var _selectedCourses = widget.selectedCourses;
  bool _busy = false;
  bool _failed = false;
  bool _selectionUnconfirmed = false;
  bool _selectionSaved = false;
  LeaveCourseChoice? _pendingChoice;

  Future<void> _select(Map<String, String> row) async {
    if (_busy || _failed) return;
    final choice = LeaveCourseChoice(_snapshot, row);
    if (widget.onSelect == null) {
      Navigator.pop(context, choice);
      return;
    }
    _pendingChoice = choice;
    await _resolveSelection(() => widget.onSelect!(choice));
  }

  Future<void> _resolveSelection(
    Future<LeaveBridgeResult> Function() readback,
  ) async {
    setState(() => _busy = true);
    LeaveBridgeResult result;
    try {
      result = await readback();
    } catch (_) {
      result = const LeaveBridgeResult('unavailable');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = result.picker == null;
      _selectionUnconfirmed = result.form == null;
      _selectionSaved = result.form != null && result.picker == null;
      if (result.form != null) _pendingChoice = null;
      if (result.form != null) _selectedCourses = result.form!.courses;
      if (result.picker != null) _snapshot = result.picker!;
    });
  }

  Future<void> _page(bool next) async {
    if (_busy || _failed) return;
    setState(() => _busy = true);
    LeaveBridgeResult result;
    try {
      result = await widget.onPage(_snapshot, next);
    } catch (_) {
      result = const LeaveBridgeResult('unavailable');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = result.picker == null;
      if (result.picker != null) _snapshot = result.picker!;
    });
  }

  Future<void> _retry() async {
    if (_busy) return;
    final pending = _pendingChoice;
    if (_selectionUnconfirmed &&
        pending != null &&
        widget.onReconcile != null) {
      await _resolveSelection(() => widget.onReconcile!(pending));
      return;
    }
    if (widget.onRetry == null) return;
    setState(() => _busy = true);
    LeaveBridgeResult result;
    try {
      result = await widget.onRetry!();
    } catch (_) {
      result = const LeaveBridgeResult('unavailable');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = result.picker == null;
      if (result.picker != null) {
        _snapshot = result.picker!;
        _selectionSaved = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.bnbuTheme;
    final candidates = _snapshot.candidates;
    final showPager = _snapshot.hasPrevious || _snapshot.hasNext;
    final canReconcile =
        _selectionUnconfirmed &&
        _pendingChoice != null &&
        widget.onReconcile != null;
    return PopScope(
      canPop: !_busy,
      child: Material(
        color: theme.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: SizedBox(
            key: const ValueKey('leave-course-picker-content'),
            width: 900,
            height:
                MediaQuery.sizeOf(context).height * .9 -
                MediaQuery.paddingOf(context).bottom,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: BnbuText(
                          '选择课程与教师',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: theme.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.text('取消'),
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(LucideIcons.x300, size: 24),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AbsorbPointer(
                          absorbing: _busy || _failed,
                          child: ExcludeSemantics(
                            excluding: _busy || _failed,
                            child: Opacity(
                              opacity: _busy || _failed ? .65 : 1,
                              child: candidates.isEmpty
                                  ? Center(
                                      child: BnbuText(_busy ? '正在加载' : '暂无数据'),
                                    )
                                  : LeaveCourseTimetable(
                                      candidates: candidates,
                                      selectedCourses: _selectedCourses,
                                      collapseOverlaps: _busy,
                                      onSelected: _select,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: BnbuUpdateProgress(active: _busy),
                      ),
                      if (_failed)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Material(
                            color: theme.surface,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: BnbuText(
                                      _selectionSaved
                                          ? '课程已加入，请重新读取。'
                                          : _selectionUnconfirmed
                                          ? '选课尚未确认，请重新读取。'
                                          : '课程读取失败，请重试。',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: theme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (canReconcile ||
                                      (!_selectionUnconfirmed &&
                                          widget.onRetry != null))
                                    TextButton(
                                      onPressed: _busy ? null : _retry,
                                      child: const BnbuText('重新读取课程'),
                                    )
                                  else
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const BnbuText('返回表单'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (showPager) const Divider(height: 1),
                if (showPager)
                  Row(
                    children: [
                      IconButton(
                        tooltip: context.l10n.text('上一页'),
                        onPressed: _busy || _failed || !_snapshot.hasPrevious
                            ? null
                            : () => _page(false),
                        icon: const Icon(LucideIcons.chevronLeft300),
                      ),
                      Expanded(
                        child: Text(
                          _snapshot.page,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.text('下一页'),
                        onPressed: _busy || _failed || !_snapshot.hasNext
                            ? null
                            : () => _page(true),
                        icon: const Icon(LucideIcons.chevronRight300),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
