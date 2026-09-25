import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/academic_calendar.dart';
import '../models/fixed_schedule_weeks.dart';
import '../models/ta_course_entry.dart';
import '../theme/app_theme.dart';
import 'bnbu_creation_form.dart';

class FixedScheduleWeeksSelector extends StatefulWidget {
  const FixedScheduleWeeksSelector({
    super.key,
    required this.preferredHeight,
    required this.semester,
    required this.selected,
    required this.semesterWeeks,
    required this.teachingWeeks,
    required this.initialWeek,
    required this.pickWeek,
  });
  final double preferredHeight;
  final BnbuCalendarSemester? semester;
  final List<DateTime> selected;
  final List<DateTime> semesterWeeks;
  final List<DateTime>? teachingWeeks;
  final DateTime initialWeek;
  final Future<DateTime?> Function(BuildContext, DateTime) pickWeek;

  @override
  State<FixedScheduleWeeksSelector> createState() =>
      _FixedScheduleWeeksSelectorState();
}

class _FixedScheduleWeeksSelectorState
    extends State<FixedScheduleWeeksSelector> {
  late final Set<DateTime> _selected = widget.selected
      .map(TaCourseEntry.normalizeWeekStart)
      .toSet();
  late final Set<DateTime> _available = {...widget.semesterWeeks, ..._selected};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _addWeek() async {
    final picked = await widget.pickWeek(context, widget.initialWeek);
    if (!mounted || picked == null) return;
    final week = TaCourseEntry.normalizeWeekStart(picked);
    setState(() {
      _available.add(week);
      _selected.add(week);
    });
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _available.toList()..sort();
    final tokens = context.bnbuTheme;
    // Match the editor, with a bounded fallback for small / rotated screens.
    // Only the list scrolls; adding weeks cannot grow the containing sheet.
    final height = widget.preferredHeight.clamp(
      0.0,
      (MediaQuery.sizeOf(context).height * .70).clamp(0.0, 720.0),
    );
    return SizedBox(
      key: const ValueKey('fixed-weeks-panel'),
      height: height,
      child: ColoredBox(
        color: BnbuCreationStyle.background(context),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BnbuCreationHeader(
                  title: '选择适用周',
                  closeKey: const ValueKey('fixed-weeks-cancel'),
                  action: TextButton(
                    key: const ValueKey('fixed-weeks-save'),
                    style: _actionStyle(
                      context,
                      fontSize: 16,
                      horizontalPadding: 0,
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      List<DateTime>.unmodifiable(_selected.toList()..sort()),
                    ),
                    child: const BnbuText('完成'),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    child: CustomScrollView(
                      key: const ValueKey('fixed-weeks-list'),
                      controller: _scroll,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    key: const ValueKey('fixed-weeks-add'),
                                    onPressed: _addWeek,
                                    style: _actionStyle(context),
                                    icon: const Icon(
                                      LucideIcons.calendarPlus300,
                                      size: 18,
                                    ),
                                    label: const BnbuText('添加其他周'),
                                  ),
                                  if (widget.teachingWeeks != null)
                                    TextButton(
                                      key: const ValueKey(
                                        'fixed-weeks-default',
                                      ),
                                      style: _actionStyle(context),
                                      onPressed: () => setState(() {
                                        _selected
                                          ..clear()
                                          ..addAll(widget.teachingWeeks!);
                                        _available.addAll(_selected);
                                      }),
                                      child: const BnbuText('恢复教学周'),
                                    ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                                child: BnbuText(
                                  _selected.isEmpty
                                      ? '未选周将不显示、不提醒'
                                      : '已选 ${_selected.length} 周',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                              if (widget.teachingWeeks == null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    0,
                                    8,
                                    12,
                                  ),
                                  child: BnbuText(
                                    '当前学期校历不可用，请手动选择周',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SliverList.builder(
                          itemCount: weeks.length,
                          itemBuilder: (context, index) => Material(
                            color: BnbuCreationStyle.group(context),
                            borderRadius: BorderRadius.vertical(
                              top: index == 0
                                  ? const Radius.circular(14)
                                  : Radius.zero,
                              bottom: index == weeks.length - 1
                                  ? const Radius.circular(14)
                                  : Radius.zero,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                if (index > 0)
                                  Divider(
                                    height: .5,
                                    thickness: .5,
                                    indent: 16,
                                    color: tokens.border.withValues(alpha: .45),
                                  ),
                                _weekTile(context, weeks[index]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekTile(BuildContext context, DateTime week) {
    final tokens = context.bnbuTheme;
    final details = FixedScheduleWeekContext(week, widget.semester);
    final labels = [
      if (details.weekNumber != null)
        context.l10n.text('第 ${details.weekNumber} 周'),
      if (details.startsTeaching) context.l10n.text('教学开始周'),
      if (details.endsTeaching) context.l10n.text('教学结束周'),
      if (details.outsideTeachingTerm) context.l10n.text('教学期外'),
    ];
    final notes = [
      if (labels.isNotEmpty) labels.join(' · '),
      for (final item in details.observances)
        '${_shortRange(item.startsOn, item.endsOn)} ${_eventLabel(context, item.event)}',
    ];
    final end = DateTime(week.year, week.month, week.day + 6);
    return CheckboxListTile(
      key: ValueKey('fixed-weeks-${TaCourseEntry.weekDateKey(week)}'),
      value: _selected.contains(week),
      activeColor: tokens.brandBlue,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(
        '${week.year} · ${_shortRange(week, end)}',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: tokens.textPrimary,
        ),
      ),
      subtitle: notes.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                notes.join('\n'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: tokens.textSecondary,
                ),
              ),
            ),
      onChanged: (value) => setState(() {
        if (value == true) {
          _selected.add(week);
        } else {
          _selected.remove(week);
        }
      }),
    );
  }

  ButtonStyle _actionStyle(
    BuildContext context, {
    double fontSize = 14,
    double horizontalPadding = 8,
  }) => TextButton.styleFrom(
    minimumSize: const Size(44, 44),
    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
    foregroundColor: context.bnbuTheme.brandBlue,
    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
    ),
  );

  String _shortRange(DateTime start, DateTime end) {
    final from = '${start.month}/${start.day}';
    if (start == end) return from;
    final endYear = start.year == end.year ? '' : '${end.year}/';
    return '$from–$endYear${end.month}/${end.day}';
  }

  String _eventLabel(BuildContext context, BnbuCalendarEvent event) {
    if (event.kind == BnbuCalendarEventKind.readingWeek) return 'Reading Week';
    final name = event.notice.trim().isEmpty ? event.name : event.notice;
    // The calendar's bilingual display names use a spaced slash separator.
    // Unknown/custom names remain intact; dates always come from the calendar.
    final parts = name.split(' / ');
    return context.l10n.text(context.l10n.isEnglish ? parts.first : parts.last);
  }
}
