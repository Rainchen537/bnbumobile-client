import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/course_display_preferences.dart';
import '../models/course_summary.dart';
import '../state/course_display_preferences_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_creation_form.dart';
import 'bnbu_component_library.dart';
import 'course_display_name_editor.dart';

Color courseStripeColor(BuildContext context, int index) =>
    index.isEven ? context.bnbuTheme.surfaceMuted : context.bnbuTheme.surface;

Future<void> showCourseDisplayEditor(
  BuildContext context, {
  required CourseDisplayPreferencesController controller,
  required List<CourseSummary> courses,
}) => showBnbuCreationModal<void>(
  context: context,
  maxWidth: 620,
  maxHeight: 620,
  semanticLabel: context.l10n.text('管理课程'),
  builder: (context, _) => SizedBox(
    height: (MediaQuery.sizeOf(context).height * 0.76).clamp(0, 620),
    child: CourseDisplayEditor(controller: controller, courses: courses),
  ),
);

class CourseDisplayEditor extends StatefulWidget {
  const CourseDisplayEditor({
    super.key,
    required this.controller,
    required this.courses,
  });
  final CourseDisplayPreferencesController controller;
  final List<CourseSummary> courses;
  @override
  State<CourseDisplayEditor> createState() => _CourseDisplayEditorState();
}

class _CourseDisplayEditorState extends State<CourseDisplayEditor> {
  late final _baseline = widget.controller.value;
  late final String? _owner;
  late final int _generation;
  late final _courses = _baseline.arrange(widget.courses, includeHidden: true);
  final _schoolNames = CourseDisplayPreferences();
  late final _hidden = {..._baseline.hidden};
  bool _reordered = false;
  bool _saving = false;
  bool _closing = false;
  String? _error;
  CourseSummary? _failedRestore;

  @override
  void initState() {
    super.initState();
    _owner = widget.controller.owner;
    _generation = widget.controller.bindingGeneration;
    widget.controller.addListener(_ownerChanged);
  }

  void _ownerChanged() {
    if (!mounted || _closing) return;
    if (widget.controller.bindingGeneration != _generation) {
      _closing = true;
      final editorRoute = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final navigator = Navigator.of(context);
          navigator.popUntil((route) => route == editorRoute || route.isFirst);
          if (editorRoute?.isCurrent == true) navigator.pop();
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_ownerChanged);
    super.dispose();
  }

  String _listName(CourseSummary course) =>
      widget.controller.value.names[course.id] ??
      _schoolNames.label(course, short: true);

  Future<void> _rename(CourseSummary course) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => CourseDisplayNameEditor(
        controller: widget.controller,
        course: course,
        initialName: _listName(course),
      ),
    );
  }

  Future<void> _restoreName(CourseSummary course) async {
    if (_saving || _closing) return;
    setState(() {
      _saving = true;
      _error = null;
      _failedRestore = null;
    });
    try {
      await widget.controller.saveName(
        course.id,
        null,
        expectedGeneration: _generation,
      );
    } catch (_) {
      if (mounted && !_closing) {
        setState(() {
          _error = '未能保存，请重试';
          _failedRestore = course;
        });
      }
    } finally {
      if (mounted && !_closing) setState(() => _saving = false);
    }
  }

  void _move(int from, int to) => setState(() {
    _courses.insert(to, _courses.removeAt(from));
    _reordered = true;
  });

  Future<void> _save() async {
    if (_saving ||
        _closing ||
        widget.controller.owner != _owner ||
        widget.controller.bindingGeneration != _generation) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveDraft(
        CourseDisplayPreferences(
          // Names have their own autosave boundary. Do not replay stale names.
          names: _baseline.names,
          hidden: _hidden,
          order: _reordered
              ? [
                  ..._courses.map((c) => c.id),
                  ..._baseline.order.where(
                    (id) => !_courses.any((c) => c.id == id),
                  ),
                ]
              : _baseline.order,
        ),
        _baseline,
      );
      await widget.controller.ensureSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '未能保存，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      BnbuCreationHeader(
        title: '管理课程',
        closeEnabled: !_saving,
        action: TextButton(
          key: const ValueKey('course-display-save'),
          onPressed: _saving ? null : _save,
          child: BnbuText(_saving ? '保存中' : '保存'),
        ),
      ),
      Expanded(
        child: ReorderableListView.builder(
          key: const ValueKey('course-display-reorder-list'),
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _courses.length,
          onReorderItem: _saving ? (_, _) {} : _move,
          itemBuilder: (context, index) {
            final course = _courses[index];
            final hidden = _hidden.contains(course.id);
            return Material(
              key: ValueKey('course-display-editor-${course.id}'),
              color: courseStripeColor(context, index),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    enabled: !_saving,
                    child: Semantics(
                      label: context.l10n.text('拖动排序'),
                      child: const SizedBox(
                        width: 44,
                        height: 56,
                        child: Icon(LucideIcons.gripVertical300, size: 20),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _listName(course),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              color: hidden
                                  ? context.bnbuTheme.textMuted
                                  : context.bnbuTheme.textPrimary,
                            ),
                          ),
                          if (hidden)
                            const BnbuText(
                              '已隐藏',
                              style: TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  BnbuMenuButton<String>(
                    key: ValueKey('course-display-actions-${course.id}'),
                    enabled: !_saving,
                    tooltip: context.l10n.text('课程选项'),
                    icon: const Icon(LucideIcons.ellipsis300, size: 22),
                    onSelected: (action) {
                      switch (action) {
                        case 'rename':
                          _rename(course);
                        case 'restore-name':
                          _restoreName(course);
                        case 'hidden':
                          setState(() {
                            if (hidden) {
                              _hidden.remove(course.id);
                            } else {
                              _hidden.add(course.id);
                            }
                          });
                        case 'up':
                          _move(index, index - 1);
                        case 'down':
                          _move(index, index + 1);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: BnbuText('更改显示名称'),
                      ),
                      if (widget.controller.value.names.containsKey(course.id))
                        const PopupMenuItem(
                          value: 'restore-name',
                          child: BnbuText('恢复原名'),
                        ),
                      PopupMenuItem(
                        value: 'hidden',
                        child: BnbuText(hidden ? '恢复显示' : '隐藏课程'),
                      ),
                      if (index > 0)
                        const PopupMenuItem(value: 'up', child: BnbuText('上移')),
                      if (index < _courses.length - 1)
                        const PopupMenuItem(
                          value: 'down',
                          child: BnbuText('下移'),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            if (_error != null)
              BnbuText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_failedRestore != null)
              TextButton(
                onPressed: _saving ? null : () => _restoreName(_failedRestore!),
                child: const BnbuText('重试'),
              ),
            BnbuText(
              '课程名称自动保存；顺序和隐藏状态点击保存后同步。隐藏不会关闭 DDL 提醒。',
              style: TextStyle(
                fontSize: 12,
                color: context.bnbuTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
