import 'bnbu_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/ta_course_entry.dart';
import '../models/academic_calendar.dart';
import '../models/fixed_schedule_weeks.dart';
import '../models/campus_time.dart';
import '../models/timetable_data.dart';
import '../theme/app_theme.dart';
import '../theme/course_color_palette.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_creation_form.dart';
import 'fixed_schedule_weeks_selector.dart';

Color fixedScheduleFormBackground(BuildContext context) =>
    BnbuCreationStyle.background(context);

/// Shared by manual creation and the assistant's editable handoff.
class FixedScheduleEditor extends StatefulWidget {
  const FixedScheduleEditor({
    super.key,
    this.initialEntry,
    this.timetable,
    this.isNew = false,
    this.showCloseButton = true,
  });
  final TaCourseEntry? initialEntry;
  final TimetableData? timetable;
  final bool isNew;
  final bool showCloseButton;
  @override
  State<FixedScheduleEditor> createState() => _FixedScheduleEditorState();
}

class _FixedScheduleEditorState extends State<FixedScheduleEditor> {
  final _form = GlobalKey<FormState>();
  final _surface = GlobalKey();
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late FixedScheduleKind _kind;
  late int _weekday;
  late TaCourseRepeatType _repeat;
  DateTime? _week;
  List<DateTime>? _activeWeeks;
  late bool _useTeachingDefaults;
  TimetableCourse? _course;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _title = TextEditingController(text: entry?.title ?? '');
    _location = TextEditingController(text: entry?.location ?? '');
    _start = TextEditingController(
      text: TaCourseEntry.formatMinutes(entry?.startMinutes ?? 540),
    );
    _end = TextEditingController(
      text: TaCourseEntry.formatMinutes(entry?.endMinutes ?? 590),
    );
    _kind = entry?.kind ?? FixedScheduleKind.schedule;
    _weekday = entry?.weekday ?? DateTime.monday;
    _repeat = entry?.repeatType ?? TaCourseRepeatType.weekly;
    _week = entry?.weekStart;
    _useTeachingDefaults =
        (entry == null || widget.isNew) && entry?.activeWeekStarts == null;
    _activeWeeks =
        entry?.activeWeekStarts ??
        (_useTeachingDefaults
            ? FixedScheduleWeeks.teachingWeeks(widget.timetable, _weekday) ?? []
            : null);
    _course = entry?.resolveCourse(widget.timetable);
  }

  @override
  void dispose() {
    for (final controller in [_title, _location, _start, _end]) {
      controller.dispose();
    }
    super.dispose();
  }

  Color get _groupColor => BnbuCreationStyle.group(context);

  Widget _group(List<Widget> rows) => BnbuCreationGroup(children: rows);

  Widget _textEntry(
    TextEditingController controller,
    String label,
    Key key, {
    bool required = false,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: TextFormField(
      key: key,
      controller: controller,
      maxLength: 160,
      style: BnbuCreationStyle.fieldText(context),
      decoration: BnbuCreationStyle.input(context, hint: label),
      validator: required
          ? (value) => value == null || value.trim().isEmpty
                ? context.l10n.text('请输入日程名称')
                : null
          : null,
    ),
  );

  Widget _row(String label, Widget value, {VoidCallback? onTap, Key? key}) =>
      InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: [
                Expanded(
                  child: BnbuText(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: context.bnbuTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: value),
              ],
            ),
          ),
        ),
      );

  Widget _navigationRow(
    String label,
    String value,
    VoidCallback onTap, {
    Key? key,
  }) => _row(
    label,
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: BnbuText(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: context.bnbuTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          LucideIcons.chevronRight300,
          size: 16,
          color: context.bnbuTheme.textMuted,
        ),
      ],
    ),
    onTap: onTap,
    key: key,
  );

  Widget _menuRow<T>(
    String label,
    T selected,
    Map<T, String> options,
    ValueChanged<T> onChanged, {
    Key? key,
  }) => _row(
    label,
    BnbuMenuButton<T>(
      key: key,
      initialValue: selected,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final entry in options.entries)
          BnbuMenuItem<T>(
            value: entry.key,
            selected: entry.key == selected,
            child: BnbuText(entry.value),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: BnbuText(
                options[selected] ?? '',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronDown300,
              size: 16,
              color: context.bnbuTheme.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _timeRow(
    String label,
    TextEditingController controller, {
    required bool end,
  }) => _row(
    label,
    Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 88,
        child: TextFormField(
          key: ValueKey(end ? 'fixed-schedule-end' : 'fixed-schedule-start'),
          controller: controller,
          keyboardType: TextInputType.datetime,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: context.bnbuTheme.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.bnbuTheme.textMuted.withValues(alpha: .1),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (value) => _parseTime(value, end: end) == null
              ? context.l10n.text('请输入有效时间')
              : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuCreationForm(
      key: _surface,
      title: widget.initialEntry == null || widget.isNew ? '新建固定日程' : '编辑固定日程',
      avoidKeyboard: ModalRoute.of(context) is! DialogRoute,
      action: BnbuCreationAction(
        key: const ValueKey('ta-course-editor-save'),
        label: '保存',
        onPressed: _save,
      ),
      child: Form(
        key: _form,
        child: Column(
          key: const ValueKey('ta-course-editor-content'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoSlidingSegmentedControl<FixedScheduleKind>(
              groupValue: _kind,
              backgroundColor: tokens.textMuted.withValues(alpha: .14),
              thumbColor: _groupColor,
              children: {
                FixedScheduleKind.schedule: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: BnbuText(
                    '日程',
                    key: const ValueKey('fixed-schedule-kind-schedule'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                FixedScheduleKind.ta: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: BnbuText(
                    'TA课',
                    key: const ValueKey('fixed-schedule-kind-ta'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value != null) {
                  setState(() {
                    _kind = value;
                    _error = null;
                  });
                }
              },
            ),
            const SizedBox(height: 24),
            _group([
              _menuRow(
                '重复',
                _repeat,
                {
                  TaCourseRepeatType.weekly: '每周',
                  TaCourseRepeatType.singleWeek: '单独一周',
                },
                (value) => setState(() => _repeat = value),
                key: const ValueKey('fixed-schedule-repeat'),
              ),
              if (_repeat == TaCourseRepeatType.singleWeek)
                _navigationRow(
                  '适用周',
                  _week == null ? '选择所在周' : fixedScheduleWeekLabel(_week!),
                  _pickWeek,
                  key: const ValueKey('fixed-schedule-week'),
                ),
              if (_repeat == TaCourseRepeatType.weekly)
                _navigationRow(
                  '适用周',
                  _activeWeeks == null
                      ? '每周（未限定）'
                      : '已选 ${_activeWeeks!.length} 周',
                  _pickWeeks,
                  key: const ValueKey('fixed-schedule-weeks'),
                ),
            ]),
            const SizedBox(height: 24),
            _group([
              if (_kind == FixedScheduleKind.ta)
                _navigationRow(
                  '所属课程',
                  _course?.name ?? '选择课程',
                  _pickCourse,
                  key: const ValueKey('fixed-schedule-course'),
                )
              else
                _textEntry(
                  _title,
                  '名称',
                  const ValueKey('fixed-schedule-title'),
                  required: true,
                ),
              _textEntry(
                _location,
                '地点',
                const ValueKey('fixed-schedule-location'),
              ),
            ]),
            const SizedBox(height: 24),
            _group([
              _menuRow(
                '星期',
                _weekday,
                {1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日'},
                (value) => setState(() {
                  _weekday = value;
                  if (_useTeachingDefaults) {
                    _activeWeeks =
                        FixedScheduleWeeks.teachingWeeks(
                          widget.timetable,
                          value,
                        ) ??
                        [];
                  }
                }),
                key: const ValueKey('fixed-schedule-weekday'),
              ),
              _timeRow('开始时间', _start, end: false),
              _timeRow('结束时间', _end, end: true),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: BnbuText(
                  _error!,
                  style: TextStyle(color: tokens.danger, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCourse() async {
    final timetable = widget.timetable;
    final course = await showBnbuAdaptiveModal<TimetableCourse>(
      context: context,
      borderRadius: BorderRadius.zero,
      bottomSheetBackgroundColor: context.bnbuTheme.surface,
      dialogMaxWidth: 520,
      semanticLabel: context.l10n.text('选择课程'),
      builder: (context, presentation) => BnbuModalFrame(
        presentation: presentation,
        title: '选择课程',
        child: ListView(
          shrinkWrap: true,
          children: [
            if (timetable == null || timetable.courses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: BnbuText('暂无可关联课程'),
              ),
            if (timetable != null)
              for (final item in timetable.courses)
                ListTile(
                  key: ValueKey('fixed-schedule-course-${item.code}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Container(
                    width: 2,
                    height: 30,
                    color: CourseColorPalette.colorForCourse(
                      item,
                      timetable,
                      context.bnbuTheme,
                    ),
                  ),
                  title: BnbuText(
                    item.name,
                    style: const TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(
                    item.code,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: _course == item
                      ? const Icon(LucideIcons.check300, size: 18)
                      : null,
                  onTap: () => Navigator.pop(context, item),
                ),
          ],
        ),
      ),
    );
    if (mounted && course != null) {
      setState(() {
        _course = course;
        _error = null;
      });
    }
  }

  Future<void> _pickWeek() async {
    final selected = await showFixedScheduleWeekPicker(
      context,
      initialWeek: _week ?? toBnbuCampusClock(DateTime.now()),
    );
    if (mounted && selected != null) setState(() => _week = selected);
  }

  Future<void> _pickWeeks() async {
    final teaching = FixedScheduleWeeks.teachingWeeks(
      widget.timetable,
      _weekday,
    );
    final surface = _surface.currentContext?.findRenderObject();
    final preferredHeight = surface is RenderBox ? surface.size.height : 620.0;
    FocusScope.of(context).unfocus();
    final selected = await showBnbuCreationModal<List<DateTime>>(
      context: context,
      maxWidth: 560,
      semanticLabel: context.l10n.text('选择适用周'),
      builder: (context, presentation) => FixedScheduleWeeksSelector(
        preferredHeight: preferredHeight,
        semester: widget.timetable == null
            ? null
            : BnbuAcademicCalendar.semesterFor(widget.timetable!),
        selected: _activeWeeks ?? teaching ?? [],
        teachingWeeks: teaching,
        semesterWeeks: FixedScheduleWeeks.semesterWeeks(widget.timetable),
        initialWeek:
            _activeWeeks?.firstOrNull ??
            _week ??
            toBnbuCampusClock(DateTime.now()),
        pickWeek: (context, week) =>
            showFixedScheduleWeekPicker(context, initialWeek: week),
      ),
    );
    if (mounted && selected != null) {
      setState(() {
        _activeWeeks = selected;
        _useTeachingDefaults = false;
      });
    }
  }

  static int? _parseTime(String? input, {required bool end}) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(input?.trim() ?? '');
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (minute > 59 || hour > 24 || hour == 24 && (!end || minute != 0)) {
      return null;
    }
    return hour * 60 + minute;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final start = _parseTime(_start.text, end: false)!;
    final end = _parseTime(_end.text, end: true)!;
    String? error;
    if (end <= start) error = '结束时间必须晚于开始时间';
    if (_repeat == TaCourseRepeatType.singleWeek && _week == null) {
      error = '请选择适用周';
    }
    if (_kind == FixedScheduleKind.ta && _course == null) error = '请选择所属课程';
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final isTa = _kind == FixedScheduleKind.ta;
    Navigator.pop(
      context,
      TaCourseEntry(
        id: widget.initialEntry?.id ?? TaCourseEntry.createId(),
        revision: widget.initialEntry?.revision ?? 0,
        title: isTa ? _course!.name : _title.text.trim(),
        location: _location.text.trim(),
        weekday: _weekday,
        startMinutes: start,
        endMinutes: end,
        repeatType: _repeat,
        activeWeekStarts: _repeat == TaCourseRepeatType.weekly
            ? _activeWeeks
            : null,
        weekStart: _repeat == TaCourseRepeatType.singleWeek
            ? TaCourseEntry.normalizeWeekStart(_week!)
            : null,
        kind: _kind,
        courseKey: isTa
            ? TaCourseEntry.bindingKey(widget.timetable!, _course!)
            : '',
        courseCode: isTa ? _course!.code : '',
        semesterId: isTa ? widget.timetable!.selectedSemesterId : '',
      ),
    );
  }
}

String fixedScheduleWeekLabel(DateTime week) {
  final start = TaCourseEntry.normalizeWeekStart(week);
  final end = DateTime(start.year, start.month, start.day + 6);
  return '${start.month}/${start.day} – ${end.month}/${end.day}';
}

Future<DateTime?> showFixedScheduleWeekPicker(
  BuildContext context, {
  required DateTime initialWeek,
}) => showBnbuAdaptiveModal<DateTime>(
  context: context,
  // Cover the root navigation without changing the nested page history or
  // reclaiming the bottom bar height for the timetable behind this picker.
  useRootNavigator: true,
  borderRadius: BorderRadius.zero,
  dialogMaxWidth: 480,
  semanticLabel: context.l10n.text('选择所在周'),
  builder: (context, presentation) => BnbuModalFrame(
    presentation: presentation,
    title: '选择所在周',
    child: _WeekGrid(initialWeek: initialWeek),
  ),
);

class _WeekGrid extends StatefulWidget {
  const _WeekGrid({required this.initialWeek});
  final DateTime initialWeek;
  @override
  State<_WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<_WeekGrid> {
  late DateTime _month;
  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialWeek.year, widget.initialWeek.month);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final first = TaCourseEntry.normalizeWeekStart(_month);
    final selected = TaCourseEntry.normalizeWeekStart(widget.initialWeek);
    final today = TaCourseEntry.normalizeWeekStart(
      toBnbuCampusClock(DateTime.now()),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: context.l10n.text('上个月'),
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              icon: const Icon(LucideIcons.chevronLeft300, size: 20),
            ),
            Expanded(
              child: Text(
                '${_month.year} / ${_month.month}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              tooltip: context.l10n.text('下个月'),
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
              icon: const Icon(LucideIcons.chevronRight300, size: 20),
            ),
          ],
        ),
        Row(
          children: [
            for (final label in [
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat',
              'Sun',
            ])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < 6; row++)
          Builder(
            builder: (context) {
              final week = DateTime(
                first.year,
                first.month,
                first.day + row * 7,
              );
              final isSelected = week == selected;
              return Semantics(
                button: true,
                selected: isSelected,
                label: fixedScheduleWeekLabel(week),
                child: InkWell(
                  key: ValueKey(
                    'fixed-schedule-week-${week.year}-${week.month}-${week.day}',
                  ),
                  onTap: () => Navigator.pop(context, week),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        for (var day = 0; day < 7; day++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final date = DateTime(
                                  week.year,
                                  week.month,
                                  week.day + day,
                                );
                                return Text(
                                  '${date.day}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected || week == today
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? tokens.brandBlue
                                        : date.month == _month.month
                                        ? tokens.textPrimary
                                        : tokens.textMuted,
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
