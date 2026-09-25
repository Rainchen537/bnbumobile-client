import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/grade_report.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_component_library.dart';
import '../widgets/bnbu_loading.dart';

class GradeReportPage extends StatefulWidget {
  const GradeReportPage({super.key, required this.controller});

  final AppSessionController controller;

  @override
  State<GradeReportPage> createState() => _GradeReportPageState();
}

class _GradeReportPageState extends State<GradeReportPage> {
  AppSessionLease? _lease;
  GradeReport? _report;
  String? _semester;
  String? _error;
  bool _loading = false;
  int _generation = 0;

  bool get _current => mounted && _lease?.isActive == true;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _lease = widget.controller.captureSessionLease();
    widget.controller.addListener(_accountChanged);
    if (_current) _report = widget.controller.cachedGradeReport;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant GradeReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_accountChanged);
    _generation++;
    _report = null;
    _semester = null;
    _error = null;
    _loading = false;
    _attach();
  }

  void _accountChanged() {
    if (!mounted || _lease?.isActive == true) return;
    setState(() {
      _generation++;
      _report = null;
      _semester = null;
      _error = null;
      _loading = false;
    });
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (_loading || !_current) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.controller.loadGradeReport(
        forceRefresh: forceRefresh,
      );
      if (!_current || generation != _generation) return;
      setState(() {
        if (report.availability == GradeReportAvailability.unavailable &&
            _report?.availability == GradeReportAvailability.available) {
          _error = '学校成绩暂不可用';
          return;
        }
        _report = report;
        if (!report.semesters.any((item) => item.label == _semester)) {
          _semester = null;
        }
      });
    } catch (_) {
      if (_current && generation == _generation) {
        setState(() => _error = '绩点读取失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        if (_current) {
          setState(() => _loading = false);
        } else {
          _accountChanged();
        }
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= BnbuBreakpoints.tabletWorkspace;
      final semesters = _report?.semesters ?? const <GradeReportSemester>[];
      final hasData =
          _report?.availability == GradeReportAvailability.available;
      return Scaffold(
        backgroundColor: context.bnbuTheme.canvas,
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(
            title: const BnbuText('绩点'),
            actions: [
              if (_current && hasData && !wide && semesters.isNotEmpty)
                BnbuMenuButton<int>(
                  key: const ValueKey('grade-semester-filter'),
                  tooltip: context.l10n.text('学期'),
                  icon: const Icon(LucideIcons.listFilter300),
                  onSelected: (index) {
                    if (!_current) return;
                    final label = index < 0 ? null : semesters[index].label;
                    if (label != null &&
                        !_report!.semesters.any(
                          (item) => item.label == label,
                        )) {
                      return;
                    }
                    setState(() => _semester = label);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: -1, child: BnbuText('全部学期')),
                    for (var i = 0; i < semesters.length; i++)
                      PopupMenuItem(value: i, child: Text(semesters[i].label)),
                  ],
                ),
              if (_current)
                IconButton(
                  tooltip: context.l10n.text('刷新'),
                  onPressed: _loading ? null : () => _load(forceRefresh: true),
                  icon: const Icon(LucideIcons.refreshCw300),
                ),
            ],
          ),
        ),
        body: !_current
            ? const _GradeMessage(message: '登录状态已变化，请重新打开绩点')
            : SafeArea(
                top: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide && hasData && semesters.isNotEmpty) ...[
                      SizedBox(
                        width: (constraints.maxWidth * .28).clamp(250, 340),
                        child: ListView(
                          key: const ValueKey('grade-semester-sidebar'),
                          padding: const EdgeInsets.all(16),
                          children: [
                            _semesterChoice(null),
                            for (final semester in semesters)
                              _semesterChoice(semester.label),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(child: _content()),
                  ],
                ),
              ),
      );
    },
  );

  Widget _semesterChoice(String? label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: _semester == label
          ? context.bnbuTheme.selectedSurface
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        key: ValueKey('grade-semester-${label ?? 'all'}'),
        selected: _semester == label,
        title: label == null ? const BnbuText('全部学期') : Text(label),
        onTap: () => setState(() => _semester = label),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  Widget _content() {
    final report = _report;
    return BnbuLoadingRegion(
      child: Column(
        children: [
          BnbuUpdateProgress(active: _loading && report != null),
          Expanded(
            child: BnbuRefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: ListView(
                key: const ValueKey('grade-report-content'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                children: [
                  if (_error != null)
                    _GradeMessage(
                      message: _error!,
                      onRetry: _loading
                          ? null
                          : () => _load(forceRefresh: true),
                    ),
                  if (_loading && report == null)
                    const SizedBox(height: 200, child: BnbuInitialLoading()),
                  if (report?.availability == GradeReportAvailability.empty)
                    const _GradeMessage(message: '暂无成绩'),
                  if (report?.availability ==
                      GradeReportAvailability.unavailable)
                    _GradeMessage(
                      message: '学校成绩暂不可用',
                      onRetry: _loading
                          ? null
                          : () => _load(forceRefresh: true),
                    ),
                  if (report != null &&
                      report.availability ==
                          GradeReportAvailability.available) ...[
                    _GradeSurface(
                      key: const ValueKey('grade-cumulative-summary'),
                      child: _metrics(
                        '累计 GPA',
                        report.cumulativeGpa,
                        report.cumulativeUnitAttempted,
                        report.cumulativeUnitGained,
                      ),
                    ),
                    for (final semester in report.semesters)
                      if (_semester == null || semester.label == _semester)
                        _semesterSection(semester),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metrics(
    String label,
    double? gpa,
    double? attempted,
    double? gained,
  ) => Wrap(
    spacing: 32,
    runSpacing: 16,
    children: [
      _GradeMetric(
        label: label,
        value: gpa?.toStringAsFixed(2) ?? '—',
        prominent: true,
      ),
      _GradeMetric(label: '修读学分', value: _number(attempted)),
      _GradeMetric(label: '获得学分', value: _number(gained)),
    ],
  );

  Widget _semesterSection(GradeReportSemester semester) => Padding(
    key: ValueKey('grade-section-${semester.label}'),
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          semester.label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _GradeSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _metrics(
                '学期 GPA',
                semester.gpa,
                semester.unitAttempted,
                semester.unitGained,
              ),
              for (final distinction in semester.distinctions)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    distinction,
                    style: TextStyle(
                      color: context.bnbuTheme.brandBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: context.bnbuTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.bnbuTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < semester.courses.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _course(semester, index),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _course(GradeReportSemester semester, int index) {
    final course = semester.courses[index];
    return ExpansionTile(
      key: ValueKey('grade-course-${semester.label}-$index'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        course.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(course.code),
            Text('${context.l10n.text('等级')} ${_text(course.grade)}'),
            Text(
              '${context.l10n.text('修读学分')} ${_number(course.unitAttempted)}',
            ),
            Text('${context.l10n.text('获得学分')} ${_number(course.unitGained)}'),
          ],
        ),
      ),
      trailing: const Icon(LucideIcons.chevronDown300, size: 20),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _GradeMetric(label: '加权绩点', value: _number(course.gradePoint)),
              _GradeMetric(label: '成绩', value: _text(course.score)),
              _GradeMetric(label: '备注', value: _text(course.remarkCode)),
            ],
          ),
        ),
      ],
    );
  }
}

String _number(double? value) =>
    value == null ? '—' : value.toString().replaceFirst(RegExp(r'\.0$'), '');
String _text(String value) => value.trim().isEmpty ? '—' : value;

class _GradeSurface extends StatelessWidget {
  const _GradeSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.bnbuTheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.bnbuTheme.border),
    ),
    child: child,
  );
}

class _GradeMetric extends StatelessWidget {
  const _GradeMetric({
    required this.label,
    required this.value,
    this.prominent = false,
  });
  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      BnbuText(
        label,
        style: TextStyle(fontSize: 14, color: context.bnbuTheme.textSecondary),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: prominent ? 26 : 16,
          fontWeight: FontWeight.w600,
          color: context.bnbuTheme.textPrimary,
        ),
      ),
    ],
  );
}

class _GradeMessage extends StatelessWidget {
  const _GradeMessage({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: BnbuText(message, textAlign: TextAlign.center),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const BnbuText('重试')),
      ],
    ),
  );
}
