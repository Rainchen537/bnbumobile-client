import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/leave_application_form.dart';
import '../services/leave_application_bridge.dart';
import '../theme/app_theme.dart';
import 'bnbu_creation_form.dart';
import 'bnbu_menu.dart';
import 'leave_time_picker.dart';

/// Flutter-owned inputs; school integration belongs to the page's live lease.
class LeaveApplicationEditor extends StatefulWidget {
  const LeaveApplicationEditor({
    super.key,
    required this.form,
    required this.busy,
    this.writeBlocked = false,
    this.submissionLocked = false,
    this.submissionSucceeded = false,
    required this.onOpenSchool,
    this.onDirtyChanged,
    this.onSelectCourse,
    this.onRemoveCourse,
    this.onRecoverCourses,
    this.courseError,
    this.onAddAttachment,
    this.onRemoveAttachment,
    this.onReadAttachments,
    this.attachmentError,
    this.uploadingAttachment = false,
  });
  final LeaveApplicationForm form;
  final bool busy;
  final bool writeBlocked;
  final bool submissionLocked;
  final bool submissionSucceeded;
  final Future<void> Function(LeaveSchoolSection, Map<String, String>)
  onOpenSchool;
  final ValueChanged<bool>? onDirtyChanged;
  final Future<void> Function(String?, Map<String, String>)? onSelectCourse;
  final Future<void> Function(Map<String, String>)? onRemoveCourse;
  final Future<void> Function()? onRecoverCourses;
  final String? courseError;
  final Future<void> Function()? onAddAttachment;
  final Future<void> Function(LeaveSchoolAttachment)? onRemoveAttachment;
  final Future<void> Function()? onReadAttachments;
  final String? attachmentError;
  final bool uploadingAttachment;

  @override
  State<LeaveApplicationEditor> createState() => _LeaveApplicationEditorState();
}

class _LeaveApplicationEditorState extends State<LeaveApplicationEditor> {
  // A safety lock disables editing without claiming work is still running.
  bool get _disabled =>
      widget.busy || widget.writeBlocked || widget.submissionLocked;

  String get _submitLabel {
    if (widget.submissionSucceeded) return '申请已提交';
    if (widget.submissionLocked) {
      return widget.busy ? '正在提交至学校' : '提交结果待确认';
    }
    if (widget.busy) return '正在同步学校表单';
    if (widget.writeBlocked) return '请先核对学校表单';
    return '核对并提交';
  }

  final _inputs = <String, TextEditingController>{};
  final _draft = <String, String>{};
  bool _identityExpanded = true;
  DialogRoute<TimeOfDay>? _timeRoute;
  DialogRoute<bool>? _removeRoute;
  static const _textKeys = ['mobile', 'familyPhone', 'details'];

  @override
  void initState() {
    super.initState();
    for (final key in _textKeys) {
      _inputs[key] = TextEditingController(text: widget.form.field(key).value);
    }
  }

  @override
  void didUpdateWidget(LeaveApplicationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.form, widget.form)) {
      _draft.removeWhere((key, value) => widget.form.field(key).value == value);
      for (final key in _textKeys) {
        if (!_draft.containsKey(key)) {
          _inputs[key]!.text = widget.form.field(key).value;
        }
      }
    }
  }

  @override
  void dispose() {
    final route = _timeRoute;
    // A school-session change disposes this editor. Do not leave its picker
    // visible over the next account's page or accept its late result.
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    final removal = _removeRoute;
    if (removal != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (removal.isActive) removal.navigator?.removeRoute(removal);
      });
    }
    for (final input in _inputs.values) {
      input.dispose();
    }
    _draft.clear();
    super.dispose();
  }

  String _value(String key) => _draft[key] ?? widget.form.field(key).value;
  void _change(String key, String value) {
    setState(() {
      if (value == widget.form.field(key).value) {
        _draft.remove(key);
      } else {
        _draft[key] = value;
      }
    });
    widget.onDirtyChanged?.call(_draft.isNotEmpty);
  }

  Future<void> _open(LeaveSchoolSection section) =>
      widget.onOpenSchool(section, Map.of(_draft));

  Future<void> _course(String? index) async {
    if (_disabled || widget.courseError != null) return;
    await widget.onSelectCourse?.call(index, Map.of(_draft));
  }

  Future<void> _removeCourse(Map<String, String> row) async {
    if (_disabled || widget.courseError != null || _removeRoute != null) {
      return;
    }
    final baseline = widget.form;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('移除此课程？'),
        content: Text(
          [row['code'], row['teacher']].whereType<String>().join('\n'),
        ),
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
    _removeRoute = route;
    final confirmed = await Navigator.of(context).push(route);
    if (_removeRoute == route) _removeRoute = null;
    if (!mounted ||
        confirmed != true ||
        _disabled ||
        widget.courseError != null ||
        !identical(baseline, widget.form)) {
      return;
    }
    await widget.onRemoveCourse?.call(row);
  }

  Future<void> _date(String key) async {
    final current = DateTime.tryParse(_value(key));
    final anchor = current ?? DateTime.now();
    // Picker navigation range, not an invented school eligibility rule.
    final selected = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: DateTime(anchor.year - 5),
      lastDate: DateTime(anchor.year + 5, 12, 31),
    );
    if (!mounted || selected == null) return;
    _change(
      key,
      '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _time(String key) async {
    if (_timeRoute != null || _disabled || !widget.form.field(key).editable) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final baseline = _value(key);
    final parts = _value(key).split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts.first) : null;
    final m = parts.length == 2 ? int.tryParse(parts.last) : null;
    final initial =
        h != null && h >= 0 && h < 24 && m != null && m >= 0 && m < 60
        ? TimeOfDay(hour: h, minute: m)
        : TimeOfDay.now();
    final route = DialogRoute<TimeOfDay>(
      context: context,
      builder: (_) => LeaveTimePicker(
        title: key == 'beginTime' ? '开始时间' : '结束时间',
        initialTime: initial,
      ),
    );
    _timeRoute = route;
    final selected = await Navigator.of(context).push(route);
    if (_timeRoute == route) _timeRoute = null;
    if (!mounted ||
        selected == null ||
        _disabled ||
        !widget.form.field(key).editable ||
        _value(key) != baseline) {
      return;
    }
    _change(
      key,
      '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: BnbuText(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: context.bnbuTheme.textSecondary,
      ),
    ),
  );

  Widget _info(String key, String label) => BnbuCreationRow(
    label: label,
    value: Text(
      widget.form.field(key).display.isEmpty
          ? '—'
          : widget.form.field(key).display,
      textAlign: TextAlign.end,
      style: BnbuCreationStyle.fieldText(context),
    ),
  );

  Widget _identityValue(String key) => Text(
    widget.form.field(key).display.isEmpty
        ? '—'
        : widget.form.field(key).display,
    textAlign: TextAlign.end,
    style: BnbuCreationStyle.fieldText(context),
  );

  Widget _applicantRow(String key, String label, Widget value) => Padding(
    key: ValueKey('leave-identity-$key'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: BnbuText(
              label,
              textAlign: TextAlign.start,
              style: BnbuCreationStyle.fieldText(
                context,
              ).copyWith(color: context.bnbuTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: value),
        ],
      ),
    ),
  );

  Widget _identity(String key, String label, {bool wide = false}) => !wide
      ? _applicantRow(key, label, _identityValue(key))
      : Padding(
          key: ValueKey('leave-identity-$key'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BnbuText(
                  label,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.bnbuTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: _identityValue(key),
                ),
              ],
            ),
          ),
        );

  Widget _pair(Widget first, Widget second) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      Expanded(child: second),
    ],
  );

  Widget _applicant(bool wide) => BnbuCreationGroup(
    children: [
      ExpansionTile(
        key: const ValueKey('leave-applicant'),
        title: const BnbuText('申请人资料', textAlign: TextAlign.start),
        trailing: SizedBox(
          width: 40,
          child: Icon(
            _identityExpanded
                ? LucideIcons.chevronUp300
                : LucideIcons.chevronDown300,
            size: 24,
          ),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        onExpansionChanged: (value) =>
            setState(() => _identityExpanded = value),
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        children: wide
            ? [
                _pair(
                  _identity('chineseName', '中文姓名', wide: true),
                  _identity('englishName', '英文姓名', wide: true),
                ),
                _identity('studentNo', '学号', wide: true),
                _pair(
                  _identity('faculty', '学院', wide: true),
                  _identity('programme', '专业', wide: true),
                ),
              ]
            : [
                _identity('chineseName', '中文姓名'),
                _identity('englishName', '英文姓名'),
                _identity('studentNo', '学号'),
                _identity('faculty', '学院'),
                _identity('programme', '专业'),
              ],
      ),
      if (wide)
        _pair(_input('mobile', '手机号码'), _input('familyPhone', '家人联系电话'))
      else ...[
        _applicantRow(
          'mobile',
          _label('手机号码', widget.form.field('mobile').required),
          _input('mobile', '手机号码', inline: true),
        ),
        _applicantRow(
          'familyPhone',
          _label('家人联系电话', widget.form.field('familyPhone').required),
          _input('familyPhone', '家人联系电话', inline: true),
        ),
      ],
    ],
  );

  String _label(String label, bool required) =>
      '${context.l10n.text(label)}${required ? ' *' : ''}';

  Widget _input(
    String key,
    String label, {
    bool multiline = false,
    bool inline = false,
  }) => TextField(
    key: ValueKey('leave-$key'),
    controller: _inputs[key],
    readOnly: _disabled || !widget.form.field(key).editable,
    onChanged: (value) => _change(key, value),
    minLines: multiline ? 4 : 1,
    maxLines: multiline ? 8 : 1,
    maxLength: widget.form.field(key).maxLength,
    keyboardType: multiline ? TextInputType.multiline : TextInputType.phone,
    textAlign: multiline ? TextAlign.start : TextAlign.end,
    style: BnbuCreationStyle.fieldText(context),
    decoration: BnbuCreationStyle.input(context).copyWith(
      labelText: inline ? null : _label(label, widget.form.field(key).required),
      hintText: inline ? context.l10n.text(label) : null,
      contentPadding: inline ? const EdgeInsets.symmetric(vertical: 8) : null,
      counterText: inline ? '' : null,
      floatingLabelBehavior: inline
          ? FloatingLabelBehavior.never
          : FloatingLabelBehavior.always,
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: context.bnbuTheme.brandBlue),
      ),
    ),
  );

  Widget _picker(String key, String label, bool date) => BnbuCreationRow(
    label: _label(label, widget.form.field(key).required),
    onTap: _disabled || !widget.form.field(key).editable
        ? null
        : () => date ? _date(key) : _time(key),
    value: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            _value(key).isEmpty ? context.l10n.text('选择') : _value(key),
            style: TextStyle(fontSize: 16, color: context.bnbuTheme.brandBlue),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(LucideIcons.chevronRight300, size: 18),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            BnbuCreationGroup(
              children: [
                _info('semester', '学期'),
                _info('openingStart', '申请开放时间'),
                _info('openingEnd', '申请截止时间'),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) =>
                  _applicant(constraints.maxWidth >= 668),
            ),
            const SizedBox(height: 24),
            _heading('请假详情'),
            BnbuCreationGroup(
              children: [
                _picker('beginDate', '开始日期', true),
                _picker('beginTime', '开始时间', false),
                _picker('endDate', '结束日期', true),
                _picker('endTime', '结束时间', false),
                if (!_draft.keys.any(
                  (k) => k.endsWith('Date') || k.endsWith('Time'),
                ))
                  _info('days', '学校核算天数')
                else
                  const BnbuCreationRow(
                    label: '学校核算天数',
                    value: BnbuText('待学校核算'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            BnbuCreationGroup(
              children: [
                BnbuCreationRow(
                  label: _label('请假类型', widget.form.field('reason').required),
                  value: BnbuMenuButton<String>(
                    key: const ValueKey('leave-reason'),
                    initialValue: _value('reason'),
                    tooltip: context.l10n.text('请假类型'),
                    enabled:
                        !_disabled &&
                        widget.form.field('reason').editable &&
                        widget.form.reasons.isNotEmpty,
                    onSelected: (value) => _change('reason', value),
                    itemBuilder: (_) => [
                      for (final reason in widget.form.reasons)
                        BnbuMenuItem<String>(
                          value: reason.value,
                          selected: reason.value == _value('reason'),
                          child: Text(reason.label),
                        ),
                    ],
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.form.reasons
                                      .where((r) => r.value == _value('reason'))
                                      .firstOrNull
                                      ?.label ??
                                  context.l10n.text('选择'),
                              textAlign: TextAlign.end,
                              style: BnbuCreationStyle.fieldText(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(LucideIcons.chevronDown300, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                _input('details', '请假原因（英文）', multiline: true),
              ],
            ),
            const SizedBox(height: 24),
            _heading(_label('涉及课程与教师', widget.form.completion.coursesRequired)),
            if (widget.courseError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BnbuText(widget.courseError!),
                    TextButton.icon(
                      onPressed: _disabled ? null : widget.onRecoverCourses,
                      icon: const Icon(LucideIcons.refreshCw300, size: 18),
                      label: const BnbuText('重新读取课程'),
                    ),
                  ],
                ),
              ),
            BnbuCreationGroup(
              children: [
                for (final row in widget.form.courses)
                  ListTile(
                    onTap:
                        _disabled ||
                            widget.courseError != null ||
                            widget.onSelectCourse == null
                        ? null
                        : () => _course(row['index']),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: context.l10n.text('更换课程'),
                          onPressed:
                              _disabled ||
                                  widget.courseError != null ||
                                  widget.onSelectCourse == null
                              ? null
                              : () => _course(row['index']),
                          icon: const Icon(LucideIcons.pencil300, size: 18),
                        ),
                        IconButton(
                          tooltip: context.l10n.text('移除课程'),
                          onPressed:
                              _disabled ||
                                  widget.courseError != null ||
                                  widget.onRemoveCourse == null
                              ? null
                              : () => _removeCourse(row),
                          icon: const Icon(LucideIcons.trash2300, size: 18),
                        ),
                      ],
                    ),
                    title: Text(
                      [row['code'], row['title']]
                          .whereType<String>()
                          .where((v) => v.isNotEmpty)
                          .join(' · '),
                    ),
                    subtitle: Text(
                      [row['section'], row['teacher'], row['type'], row['time']]
                          .whereType<String>()
                          .where((v) => v.isNotEmpty)
                          .join(' · '),
                    ),
                  ),
                ListTile(
                  leading: const Icon(LucideIcons.bookOpen300),
                  title: const BnbuText('选择课程与教师'),
                  trailing: const Icon(LucideIcons.chevronRight300, size: 18),
                  onTap:
                      _disabled ||
                          widget.courseError != null ||
                          widget.onSelectCourse == null
                      ? null
                      : () => _course(null),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _heading(_label('证明材料', widget.form.completion.attachmentRequired)),
            BnbuCreationGroup(
              children: [
                for (final file in widget.form.completion.files)
                  ListTile(
                    leading: const Icon(LucideIcons.file300),
                    title: Text(file.name),
                    subtitle: const BnbuText('已上传至学校'),
                    trailing: IconButton(
                      tooltip: context.l10n.text('移除附件'),
                      icon: const Icon(LucideIcons.trash2300, size: 18),
                      onPressed: _disabled || widget.attachmentError != null
                          ? null
                          : () => widget.onRemoveAttachment?.call(file),
                    ),
                  ),
                if (widget.attachmentError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: BnbuText(widget.attachmentError!),
                  ),
                ListTile(
                  leading: const Icon(LucideIcons.paperclip300),
                  title: BnbuText(
                    widget.uploadingAttachment ? '正在上传附件' : '选择附件并上传至学校',
                  ),
                  onTap: _disabled || widget.attachmentError != null
                      ? null
                      : widget.onAddAttachment,
                ),
                if (widget.attachmentError != null)
                  TextButton(
                    onPressed: _disabled ? null : widget.onReadAttachments,
                    child: const BnbuText('重新读取附件状态'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton(
                onPressed: _disabled || widget.attachmentError != null
                    ? null
                    : () => _open(LeaveSchoolSection.review),
                child: BnbuText(_submitLabel, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
