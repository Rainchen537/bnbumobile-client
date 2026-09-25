import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/leave_course_timetable.dart';
import '../models/schedule_grid_geometry.dart';
import '../models/timetable_data.dart';
import '../theme/app_theme.dart';
import '../theme/course_color_palette.dart';

class LeaveCourseTimetable extends StatefulWidget {
  const LeaveCourseTimetable({
    super.key,
    required this.candidates,
    required this.selectedCourses,
    required this.onSelected,
    this.collapseOverlaps = false,
  });
  final List<Map<String, String>> candidates, selectedCourses;
  final ValueChanged<Map<String, String>> onSelected;
  final bool collapseOverlaps;

  @override
  State<LeaveCourseTimetable> createState() => _LeaveCourseTimetableState();
}

class _LeaveCourseTimetableState extends State<LeaveCourseTimetable> {
  List<_Slot>? _expanded;

  @override
  void didUpdateWidget(LeaveCourseTimetable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new school page/token invalidates every expanded presentation row.
    if (widget.collapseOverlaps ||
        !identical(oldWidget.candidates, widget.candidates)) {
      _expanded = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final slots = <_Slot>[];
    final other = <Map<String, String>>[];
    for (final row in widget.candidates) {
      final meetings = LeaveCourseTimetableData.meetings(row['time'] ?? '');
      for (final meeting in meetings.where((m) => m.weekday <= 5)) {
        slots.add(_Slot(row, meeting));
      }
      // Unknown time and weekend-only candidates must never silently vanish.
      if (meetings.isEmpty || meetings.every((m) => m.weekday > 5)) {
        other.add(row);
      }
    }
    slots.sort(
      (a, b) => a.meeting.startMinutes.compareTo(b.meeting.startMinutes),
    );
    final groups = <_SlotGroup>[];
    for (var day = 1; day <= 5; day++) {
      _SlotGroup? group;
      for (final slot in slots.where((s) => s.meeting.weekday == day)) {
        if (group == null || slot.meeting.startMinutes >= group.end) {
          group = _SlotGroup(slot);
          groups.add(group);
        } else {
          group.slots.add(slot);
          group.end = math.max(group.end, slot.meeting.endMinutes);
        }
      }
    }
    final start = slots.isEmpty
        ? 8 * 60
        : (slots.map((s) => s.meeting.startMinutes).reduce(math.min) ~/ 60) *
              60;
    final end = slots.isEmpty
        ? start
        : ((slots.map((s) => s.meeting.endMinutes).reduce(math.max) + 59) ~/
                  60) *
              60;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    // Keep even a short school meeting at least 44pt high and hit-testable.
    final shortest = groups.isEmpty
        ? 60
        : groups.map((g) => g.end - g.start).reduce(math.min);
    final ranges = slots
        .map(
          (s) => (
            startMinutes: s.meeting.startMinutes,
            endMinutes: s.meeting.endMinutes,
          ),
        )
        .toList();
    bool selected(Map<String, String> row) => widget.selectedCourses.any(
      (course) => LeaveCourseTimetableData.sameCourse(row, course),
    );
    Color color(Map<String, String> row) {
      // Stable across school pages without looking up any other course source.
      final seed = LeaveCourseTimetableData.colorSeed(row);
      return CourseColorPalette.fallback(seed, tokens);
    }

    if (_expanded case final expanded?) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = null),
              icon: const Icon(LucideIcons.chevronLeft300, size: 20),
              label: const BnbuText('返回课表'),
            ),
          ),
          Expanded(
            child: ListView.separated(
              key: const ValueKey('leave-overlap-options'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: expanded.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final row = expanded[index].row;
                return _CourseBlock(
                  key: ValueKey('leave-overlap-choice-${row['key']}'),
                  row: row,
                  selected: selected(row),
                  color: color(row),
                  onTap: () => widget.onSelected(row),
                );
              },
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final axis = 32.0 * scale;
        var column = math.max((constraints.maxWidth - axis) / 5, 44.0 * scale);
        for (final slot in slots) {
          final parts = _splitCourseCode(
            slot.row['code'] ?? '',
            column - 7,
            context,
          );
          if (parts != null) {
            for (final part in parts) {
              column = math.max(column, _courseCodeWidth(part, context) + 7);
            }
          }
        }
        final width = axis + column * 5;
        // Reserve two code lines plus two time lines only when needed.
        // Scale the shared axis, never grow one card over the following class.
        final wrapsCode = slots.any(
          (slot) =>
              _splitCourseCode(slot.row['code'] ?? '', column - 7, context) !=
              null,
        );
        final minimumHeight = wrapsCode
            ? 4 * (12 * scale * 1.15).ceilToDouble() + 12
            : 56 * scale;
        final hourHeight = math.max(64 * scale, minimumHeight * 60 / shortest);
        // Compress empty hours to readable time ticks, while keeping occupied
        // hours and short course hit targets at their established minimums.
        final viewportHeight = math.max(
          0.0,
          constraints.maxHeight - 50 * scale - 1,
        );
        final hours = (end - start) ~/ 60;
        final occupiedHours = List.generate(hours, (i) => start + i * 60)
            .where(
              (minute) => ranges.any(
                (range) =>
                    range.startMinutes < minute + 60 &&
                    range.endMinutes > minute,
              ),
            )
            .length;
        final emptyHours = hours - occupiedHours;
        final minimumEmptyWeight = math.min(.5, 18 * scale / hourHeight);
        final emptyWeight = emptyHours == 0
            ? .5
            : ((viewportHeight / hourHeight - occupiedHours) / emptyHours)
                  .clamp(minimumEmptyWeight, .5);
        final normalized = end == start
            ? null
            : ScheduleGridGeometry(
                startMinutes: start,
                endMinutes: end,
                availableHeight: 1,
                occupiedRanges: ranges,
                emptyHourWeight: emptyWeight,
              );
        final minimumGridHeight = normalized == null
            ? 0.0
            : hourHeight / normalized.normalRowHeight;
        final geometry = normalized == null
            ? null
            : ScheduleGridGeometry(
                startMinutes: start,
                endMinutes: end,
                availableHeight: minimumGridHeight,
                occupiedRanges: ranges,
                emptyHourWeight: emptyWeight,
              );
        double offset(int minute) =>
            geometry?.offsetFor(minute.toDouble()) ?? 0;
        final gridHeight = geometry?.height ?? 0;
        double left(int day) => axis + (day - 1) * column;
        return SingleChildScrollView(
          key: const ValueKey('leave-week-horizontal'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(width: axis),
                    for (var day = 1; day <= 5; day++)
                      SizedBox(
                        key: ValueKey('leave-weekday-$day'),
                        width: column,
                        height: 32 * scale,
                        child: Center(
                          child: Text(
                            context.l10n.isEnglish
                                ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][day - 1]
                                : context.l10n.text(
                                    ['周一', '周二', '周三', '周四', '周五'][day - 1],
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('leave-week-vertical'),
                    child: Column(
                      children: [
                        SizedBox(
                          height: gridHeight + 18 * scale,
                          child: Stack(
                            children: [
                              for (
                                var minute = start;
                                minute <= end;
                                minute += 60
                              ) ...[
                                Positioned(
                                  top: offset(minute),
                                  left: 0,
                                  width: axis - 4,
                                  child: Text(
                                    '${minute ~/ 60}',
                                    textAlign: TextAlign.end,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.15,
                                      letterSpacing: 0,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: offset(minute),
                                  left: axis,
                                  right: 0,
                                  child: Divider(
                                    height: 1,
                                    color: tokens.border,
                                  ),
                                ),
                              ],
                              for (var day = 1; day <= 5; day++)
                                Positioned(
                                  left: left(day),
                                  width: 1,
                                  top: 0,
                                  height: gridHeight,
                                  child: ColoredBox(color: tokens.border),
                                ),
                              for (final group in groups)
                                Positioned(
                                  left: left(group.weekday),
                                  top: offset(group.start),
                                  width: column,
                                  height:
                                      offset(group.end) - offset(group.start),
                                  child: group.slots.length > 1
                                      ? _OverlapBlock(
                                          key: ValueKey(
                                            'leave-overlap-${group.weekday}-${group.start}',
                                          ),
                                          slots: group.slots,
                                          selected: selected,
                                          color: color,
                                          onTap: () => setState(
                                            () => _expanded = group.slots,
                                          ),
                                        )
                                      : _CourseBlock(
                                          key: ValueKey(
                                            'leave-course-${group.slots.single.row['key']}-${group.weekday}-${group.start}',
                                          ),
                                          row: group.slots.single.row,
                                          selected: selected(
                                            group.slots.single.row,
                                          ),
                                          color: color(group.slots.single.row),
                                          time:
                                              '${group.slots.single.meeting.startLabel}–${group.slots.single.meeting.endLabel}',
                                          onTap: () => widget.onSelected(
                                            group.slots.single.row,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ),
                        if (other.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: BnbuText('其他时段课程'),
                            ),
                          ),
                          for (final row in other)
                            _CourseBlock(
                              key: ValueKey('leave-course-${row['key']}'),
                              row: row,
                              selected: selected(row),
                              color: color(row),
                              onTap: () => widget.onSelected(row),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Slot {
  _Slot(this.row, this.meeting);
  final Map<String, String> row;
  final TimetableMeeting meeting;
}

class _SlotGroup {
  _SlotGroup(_Slot slot)
    : slots = [slot],
      start = slot.meeting.startMinutes,
      end = slot.meeting.endMinutes,
      weekday = slot.meeting.weekday;
  final List<_Slot> slots;
  final int start, weekday;
  int end;
}

class _OverlapBlock extends StatelessWidget {
  const _OverlapBlock({
    super.key,
    required this.slots,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final List<_Slot> slots;
  final bool Function(Map<String, String>) selected;
  final Color Function(Map<String, String>) color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final count = slots.where((s) => selected(s.row)).length;
    final allSelected = count == slots.length;
    final tint = allSelected
        ? tokens.textSecondary
        : color(slots.firstWhere((s) => !selected(s.row)).row);
    return Semantics(
      button: true,
      label: '${context.l10n.text('重叠课程')} ${slots.length}',
      child: Tooltip(
        message: slots.map((s) => s.row['code']).join('\n'),
        child: Material(
          color: allSelected
              ? tokens.surfaceMuted
              : Color.alphaBlend(tint.withValues(alpha: .14), tokens.surface),
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: tint, width: 3)),
              ),
              padding: const EdgeInsets.all(4),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${slots.length}',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: allSelected
                            ? tokens.textSecondary
                            : tokens.textPrimary,
                      ),
                    ),
                    BnbuText(
                      allSelected ? '已选' : '门课',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    super.key,
    required this.row,
    required this.selected,
    required this.color,
    required this.onTap,
    this.time,
  });
  final Map<String, String> row;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final text = [
      row['code'],
      row['teacher'],
      row['type'],
      row['time'],
    ].whereType<String>().where((s) => s.isNotEmpty).join('\n');
    final accent = selected ? tokens.textSecondary : color;
    return Semantics(
      button: true,
      enabled: !selected,
      selected: selected,
      label: '$text${selected ? '\n${context.l10n.text('已选')}' : ''}',
      child: Tooltip(
        message: text,
        child: Material(
          color: selected
              ? tokens.surfaceMuted
              : Color.alphaBlend(color.withValues(alpha: .14), tokens.surface),
          child: InkWell(
            onTap: selected ? null : onTap,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: accent, width: 2),
                  top: BorderSide(
                    color: accent.withValues(alpha: .25),
                    width: .5,
                  ),
                  right: BorderSide(
                    color: accent.withValues(alpha: .25),
                    width: .5,
                  ),
                  bottom: BorderSide(
                    color: accent.withValues(alpha: .25),
                    width: .5,
                  ),
                ),
              ),
              padding: time == null
                  ? const EdgeInsets.all(12)
                  : const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: time == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['code'] ?? '',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [row['teacher'], row['type'], row['time']]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join('\n'),
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.textSecondary,
                          ),
                        ),
                        if (selected)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: BnbuText(
                              '已选',
                              style: TextStyle(color: tokens.textSecondary),
                            ),
                          ),
                      ],
                    )
                  : _CompactCourseContent(
                      title: row['code'] ?? '',
                      time: time!,
                      selected: selected,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

List<String>? _splitCourseCode(
  String value,
  double width,
  BuildContext context,
) {
  final match = RegExp(r'^([A-Za-z]+)([0-9]+)$').firstMatch(value.trim());
  if (match == null) return null;
  return _courseCodeWidth(value.trim(), context) > width
      ? [match[1]!, match[2]!]
      : null;
}

double _courseCodeWidth(String value, BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: DefaultTextStyle.of(context).style.copyWith(
        fontSize: 12,
        height: 1.15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _CompactCourseContent extends StatelessWidget {
  const _CompactCourseContent({
    required this.title,
    required this.time,
    required this.selected,
  });
  final String title, time;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 12,
      height: 1.15,
      color: selected ? tokens.textSecondary : tokens.textPrimary,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    double measure(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    String shortTime(String value) {
      final parts = value.split(':');
      final hour = int.tryParse(parts.first);
      if (hour == null || parts.length != 2) return value;
      return parts.last == '00' ? '$hour' : '$hour:${parts.last}';
    }

    final parts = time.split('–').map(shortTime).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final range = parts.join('–');
        final twoLines = !selected && measure(range) > constraints.maxWidth;
        final footer = selected
            ? context.l10n.text('已选')
            : twoLines
            ? parts.join('\n')
            : range;
        final lineHeight = (scaler.scale(12) * 1.15).ceilToDouble();
        final lines =
            ((constraints.maxHeight - (twoLines ? 2 : 1) * lineHeight - 2) /
                    lineHeight)
                .floor()
                .clamp(1, 4);
        // Wrap at word boundaries; don't split a long course word into fragments.
        final wrapped = <String>[];
        final cjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(title);
        final codeParts = _splitCourseCode(
          title,
          constraints.maxWidth,
          context,
        );
        if (codeParts != null) wrapped.addAll(codeParts);
        for (final word
            in codeParts == null ? title.split(RegExp(r'\s+')) : <String>[]) {
          if (wrapped.isEmpty) {
            wrapped.add(word);
          } else if (wrapped.length == lines ||
              measure('${wrapped.last} $word') <= constraints.maxWidth) {
            wrapped[wrapped.length - 1] += ' $word';
          } else {
            wrapped.add(word);
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: cjk
                    ? Text(
                        title,
                        maxLines: lines,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in wrapped)
                            Text(
                              line,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              footer,
              maxLines: twoLines ? 2 : 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                fontWeight: FontWeight.w400,
                color: tokens.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}
