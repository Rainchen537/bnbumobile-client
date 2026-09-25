import '../state/account_habits.dart';
import 'bnbu_adaptive.dart';
import 'ispace_content_padding.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../pages/web_mirror_page.dart';
import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/course_grade_data.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_loading.dart';
import 'courseware_download_button.dart';
import 'moodle_activity_icon.dart';

enum _CourseView { sections, assignments, announcements, files, grades }

class IspaceCourseWorkspace extends StatefulWidget {
  const IspaceCourseWorkspace({
    super.key,
    required this.course,
    required this.sections,
    required this.controller,
    required this.loading,
    required this.onRefresh,
    required this.onOpenModule,
    this.error,
    this.showCourseHeading = true,
    this.displayName,
  });
  final CourseSummary course;
  final List<CourseContentSection> sections;
  final AppSessionController controller;
  final bool loading;
  final String? error;
  final bool showCourseHeading;
  final String? displayName;
  final Future<void> Function() onRefresh;
  final void Function(CourseModule) onOpenModule;
  @override
  State<IspaceCourseWorkspace> createState() => _IspaceCourseWorkspaceState();
}

class _IspaceCourseWorkspaceState extends State<IspaceCourseWorkspace> {
  late _CourseView _view = _CourseView.values.firstWhere(
    (v) =>
        v.name == AccountHabits.shared.read('ispace.course.view', 'sections'),
    orElse: () => _CourseView.sections,
  );
  bool _habitViewRestored = AccountHabits.shared.ready;
  @override
  void initState() {
    super.initState();
    AccountHabits.shared.addListener(_restoreHabitView);
  }

  void _restoreHabitView() {
    if (!mounted || _habitViewRestored || !AccountHabits.shared.ready) return;
    setState(() {
      _view = _CourseView.values.firstWhere(
        (v) =>
            v.name ==
            AccountHabits.shared.read('ispace.course.view', 'sections'),
        orElse: () => _CourseView.sections,
      );
      _habitViewRestored = true;
    });
  }

  @override
  void dispose() {
    AccountHabits.shared.removeListener(_restoreHabitView);
    super.dispose();
  }

  int? _section;
  Future<CourseGradeSnapshot>? _grades;
  String _label(_CourseView view) => switch (view) {
    _CourseView.sections => '章节',
    _CourseView.assignments => '作业',
    _CourseView.announcements => '公告',
    _CourseView.files => '文件',
    _CourseView.grades => '成绩',
  };
  bool _matches(CourseModule m) => switch (_view) {
    _CourseView.sections => true,
    _CourseView.assignments => m.modName == 'assign',
    _CourseView.announcements => m.modName == 'forum',
    _CourseView.files => const {
      'resource',
      'folder',
      'page',
      'url',
      'book',
    }.contains(m.modName),
    _CourseView.grades => false,
  };
  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final sections = widget.sections
        .where((s) => s.visible && s.userVisible)
        .toList();
    final modules = [
      for (final section in sections)
        if (_view != _CourseView.sections ||
            _section == null ||
            section.id == _section)
          for (final m in section.modules)
            if (m.visible && m.userVisible && _matches(m)) (section, m),
    ];
    final reader = _view == _CourseView.grades
        ? _gradeView(context)
        : BnbuRefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (widget.loading && sections.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: BnbuInitialLoading(),
                  ),
                if (widget.error != null)
                  TextButton(
                    onPressed: widget.onRefresh,
                    child: BnbuText(widget.error!),
                  ),
                for (final section in sections.where(
                  (s) => s.modules.isEmpty && s.summary.isNotEmpty,
                )) ...[BnbuText(section.name), _sectionSummary(section)],
                for (var i = 0; i < modules.length; i++) ...[
                  if (i == 0 || modules[i].$1.id != modules[i - 1].$1.id)
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: BnbuText(
                        modules[i].$1.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  if ((i == 0 || modules[i].$1.id != modules[i - 1].$1.id) &&
                      modules[i].$1.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _sectionSummary(modules[i].$1),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 12,
                    leading: MoodleActivityIcon(
                      moduleName: modules[i].$2.modName,
                      size: 20,
                      color: tokens.brandBlue,
                    ),
                    title: BnbuText(
                      modules[i].$2.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    subtitle: _moduleDeadline(context, modules[i].$2),
                    trailing: Icon(
                      modules[i].$2.completionData?.state == 1
                          ? LucideIcons.circleCheck300
                          : LucideIcons.chevronRight300,
                      size: 18,
                      color: tokens.textMuted,
                    ),
                    onTap: () => widget.onOpenModule(modules[i].$2),
                  ),
                ],
                if (!widget.loading && modules.isEmpty && widget.error == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: BnbuText('暂无内容'),
                  ),
              ],
            ),
          );
    return IspaceContentPadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BnbuSecondaryHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showCourseHeading)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: BnbuText(
                              widget.displayName ?? widget.course.fullName,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(width: 12),
                          CoursewareDownloadButton(
                            controller: widget.controller,
                            course: widget.course,
                            enabled: !widget.loading,
                            iconOnly: constraints.maxWidth < 700,
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.zero,
                  child: Wrap(
                    children: [
                      for (final view in _CourseView.values)
                        TextButton(
                          onPressed: () => setState(() {
                            _view = view;
                            _habitViewRestored = true;
                            AccountHabits.shared
                                .set('ispace.course.view', view.name)
                                .catchError((Object _) {});
                            if (view == _CourseView.grades) {
                              _grades ??= widget.controller.loadCourseGrades(
                                widget.course.id,
                              );
                            }
                          }),
                          style: TextButton.styleFrom(
                            foregroundColor: _view == view
                                ? tokens.brandBlue
                                : tokens.textMuted,
                          ),
                          child: BnbuText(
                            _label(view),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: _view == view
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          BnbuUpdateProgress(active: widget.loading && sections.isNotEmpty),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 700 ||
                    _view != _CourseView.sections ||
                    sections.length < 2) {
                  return reader;
                }
                return Row(
                  children: [
                    SizedBox(
                      key: const ValueKey('ispace-course-sections'),
                      width: 270,
                      child: ListView(
                        children: [
                          ListTile(
                            title: const BnbuText('全部'),
                            selected: _section == null,
                            onTap: () => setState(() => _section = null),
                          ),
                          for (final s in sections)
                            ListTile(
                              title: BnbuText(s.name),
                              selected: _section == s.id,
                              onTap: () => setState(() => _section = s.id),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: reader),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget? _moduleDeadline(BuildContext context, CourseModule module) {
    final due = module.dates
        .where(
          (date) =>
              date.dataId.toLowerCase().contains('due') &&
              date.dateTime != null,
        )
        .firstOrNull;
    if (due == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${context.l10n.text('截止时间')} · ${context.l10n.formatFullDateTime(due.dateTime!.toLocal())}',
        style: TextStyle(fontSize: 12, color: context.bnbuTheme.textMuted),
      ),
    );
  }

  Widget _sectionSummary(CourseContentSection section) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      icon: const Icon(LucideIcons.externalLink300, size: 16),
      label: const BnbuText('章节说明'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebMirrorPage(
            controller: widget.controller,
            title: section.name,
            pathOrUrl:
                '/course/view.php?id=${widget.course.id}#section-${section.sectionNum}',
          ),
        ),
      ),
    ),
  );

  Widget _gradeView(BuildContext context) => FutureBuilder<CourseGradeSnapshot>(
    future: _grades,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const BnbuInitialLoading();
      }
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(
              () => _grades = widget.controller.loadCourseGrades(
                widget.course.id,
              ),
            ),
            child: const BnbuText('成绩暂不可用，重试'),
          ),
        );
      }
      final items = snapshot.data?.items.where((i) => !i.hidden).toList() ?? [];
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final item in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: BnbuText(item.name),
              trailing: BnbuText(item.gradeFormatted),
              subtitle: item.rangeFormatted.isEmpty
                  ? null
                  : BnbuText(item.rangeFormatted),
            ),
          if (items.isEmpty) const BnbuText('暂无可见成绩'),
        ],
      );
    },
  );
}
