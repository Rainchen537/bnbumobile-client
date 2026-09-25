import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/course_display_preferences.dart';
import '../models/course_summary.dart';
import '../state/course_display_preferences_controller.dart';
import '../theme/app_theme.dart';

/// Names save independently of the surrounding order/visibility draft.
class CourseDisplayNameEditor extends StatefulWidget {
  const CourseDisplayNameEditor({
    super.key,
    required this.controller,
    required this.course,
    required this.initialName,
  });

  final CourseDisplayPreferencesController controller;
  final CourseSummary course;
  final String initialName;

  @override
  State<CourseDisplayNameEditor> createState() =>
      _CourseDisplayNameEditorState();
}

class _CourseDisplayNameEditorState extends State<CourseDisplayNameEditor> {
  late final TextEditingController _input;
  late final int _generation;
  late final _schoolName = CourseDisplayPreferences().label(
    widget.course,
    short: true,
  );
  late final String? _initialAlias;
  late TextEditingValue _lastInput;
  Timer? _debounce;
  Future<bool>? _saving;
  int _revision = 0;
  int _savedRevision = 0;
  String? _error;
  bool _closing = false;
  bool _allowPop = false;
  bool get _current =>
      mounted && widget.controller.bindingGeneration == _generation;
  bool get _composing =>
      _input.value.composing.isValid && !_input.value.composing.isCollapsed;

  @override
  void initState() {
    super.initState();
    // Eager snapshots: lazy initializers could capture a different login after
    // the debounce, or mistake the first edit for the original input value.
    _generation = widget.controller.bindingGeneration;
    _initialAlias = widget.controller.value.names[widget.course.id];
    _input = TextEditingController(text: widget.initialName);
    _lastInput = _input.value;
    _input.addListener(_changed);
  }

  void _changed() {
    // Selection/IME changes may complete composition without changing text.
    final next = _input.value;
    final textChanged = next.text != _lastInput.text;
    final compositionChanged = next.composing != _lastInput.composing;
    _lastInput = next;
    if (!textChanged && !compositionChanged) return;
    _debounce?.cancel();
    if (textChanged) _revision++;
    setState(() => _error = null);
    if (!_composing) {
      _debounce = Timer(const Duration(milliseconds: 400), _flush);
    }
  }

  Future<bool> _flush() {
    _debounce?.cancel();
    return _saving ??= _saveLatest().whenComplete(() {
      _saving = null;
      if (mounted) setState(() {});
    });
  }

  Future<bool> _saveLatest() async {
    while (_current && _savedRevision != _revision) {
      if (_composing) return false;
      final revision = _revision;
      final name = _input.text.trim();
      if (name.isNotEmpty && !CourseDisplayPreferences.isValidName(name)) {
        setState(() => _error = '课程名称最多150个字符，不能包含换行或控制字符');
        return false;
      }
      // Opening or re-confirming the school label never freezes it as an alias.
      final alias = name == widget.initialName.trim()
          ? _initialAlias
          : name.isEmpty || name == _schoolName.trim()
          ? null
          : name;
      setState(() => _error = null);
      try {
        await widget.controller.saveName(
          widget.course.id,
          alias,
          expectedGeneration: _generation,
        );
        if (!_current) return false;
        setState(() => _savedRevision = revision);
      } catch (_) {
        if (_current) setState(() => _error = '未能保存，请重试');
        return false;
      }
    }
    return _current;
  }

  Future<void> _close() async {
    if (_closing || !_current) return;
    _closing = true;
    final saved = await _flush();
    if (!mounted || !_current) return;
    _closing = false;
    if (saved) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.removeListener(_changed);
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AlertDialog(
      scrollable: true,
      title: const BnbuText('课程显示名称'),
      content: SizedBox(
        width: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('course-display-name'),
              controller: _input,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              maxLength: CourseDisplayPreferences.maxNameLength,
              // The protocol counts Unicode code points, not UTF-16 units or
              // grapheme clusters. Validate explicitly without cutting an IME.
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: _schoolName,
                counterText:
                    '${_input.text.runes.length}/${CourseDisplayPreferences.maxNameLength}',
                errorText: _error == null ? null : context.l10n.text(_error!),
                errorMaxLines: 4,
              ),
              onFieldSubmitted: (_) => unawaited(_close()),
            ),
            if (_error == null && _revision > 0)
              Semantics(
                liveRegion: true,
                child: BnbuText(
                  _savedRevision == _revision ? '已保存到本机' : '保存中',
                  style: TextStyle(color: context.bnbuTheme.textMuted),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (_error == '未能保存，请重试')
          TextButton(
            onPressed: () => unawaited(_flush()),
            child: const BnbuText('重试'),
          ),
        TextButton(
          key: const ValueKey('course-display-name-done'),
          onPressed: () => unawaited(_close()),
          child: const BnbuText('完成'),
        ),
      ],
    ),
  );
}
