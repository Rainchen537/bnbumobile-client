import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bnbu_me/models/exam_timetable.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/theme/course_color_palette.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';
import 'package:bnbu_me/widgets/moodle_activity_icon.dart';
import 'package:bnbu_me/widgets/timeline_summary_card.dart';

import 'catalog_data.dart';
import 'current_cards.dart';

abstract final class CatalogCardInsets {
  static const rail = 5.0;
  static const left = 16.0;
  static const right = 12.0;
  static const top = 12.0;
  static const bottom = 12.0;
  static EdgeInsets content(double bottomInset) =>
      EdgeInsets.fromLTRB(left, top, right, bottomInset);
}

/// Proposed geometry is deliberately confined to this review executable.
class CatalogCardSample extends StatelessWidget {
  const CatalogCardSample({
    super.key,
    required this.entry,
    required this.fixture,
    required this.proposed,
    this.onOpen,
    this.titleLines = 2,
    this.bottomInset = CatalogCardInsets.bottom,
  });
  final CatalogEntry entry;
  final CatalogFixture fixture;
  final bool proposed;
  final VoidCallback? onOpen;
  final int titleLines;
  final double bottomInset;

  bool get isGrid => const {
    CatalogKind.gridCourse,
    CatalogKind.gridTa,
    CatalogKind.gridEvent,
    CatalogKind.gridDeadline,
  }.contains(entry.kind);

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final current = CurrentAcademicCards(
      context,
      onOpen ?? () {},
      measureScaledText: proposed,
    );
    final isEvent =
        entry.kind == CatalogKind.agendaEvent ||
        entry.kind == CatalogKind.gridEvent;
    final isTa =
        entry.kind == CatalogKind.agendaTa || entry.kind == CatalogKind.gridTa;
    final course = fixture.course(event: isEvent);
    final color = CourseColorPalette.fallback(course.code, tokens);
    final block = CatalogMeeting(
      course,
      fixture.meeting,
      color,
      taCourse: isTa || isEvent ? Object() : null,
    );
    final item = fixture.item;
    final ddlColor = item.isOverdue
        ? tokens.danger
        : Color.lerp(tokens.danger, tokens.warning, .18)!;
    final monthDay = fixture.due == null
        ? '无日期'
        : context.l10n.formatMonthDayTime(fixture.due!);
    final typeIcon = MoodleActivityIcon(
      moduleName: fixture.activity,
      size: 17,
      color:
          entry.kind == CatalogKind.deadlineDetail ||
              entry.kind == CatalogKind.agendaDeadline
          ? ddlColor
          : timelineSummaryAccentColor(item, tokens, now: CatalogFixture.now),
    );
    Widget timeline({required bool home, required bool detail}) => proposed
        ? _summary(
            context,
            color: detail || entry.kind == CatalogKind.agendaDeadline
                ? ddlColor
                : timelineSummaryAccentColor(
                    item,
                    tokens,
                    now: CatalogFixture.now,
                  ),
            icon: typeIcon,
            source: home ? 'iSpace' : null,
            contextLabel: item.courseName.isEmpty
                ? timelineActivityVisualFor(
                    moduleName: fixture.activity,
                    activityType: fixture.activity,
                  ).label
                : item.courseName,
            time: monthDay,
            title: item.title,
            footer: proposedCountdown(context, fixture),
            detail: detail,
            arrow: !detail,
          )
        : BnbuTimelineSummaryCard(
            item: item,
            deadlineLabel:
                entry.kind == CatalogKind.ispaceDeadline && fixture.due != null
                ? context.l10n.formatMediumDateTime(fixture.due!)
                : monthDay,
            statusLabel: detail
                ? (item.isOverdue ? '已逾期' : item.activityState)
                : currentCountdown(fixture, home: home),
            accentColor: detail
                ? ddlColor
                : timelineSummaryAccentColor(
                    item,
                    tokens,
                    now: CatalogFixture.now,
                  ),
            onTap: detail ? null : onOpen,
            showIspaceLabel: home,
            showChevron: !detail,
          );

    switch (entry.kind) {
      case CatalogKind.homeCourse:
        if (!proposed) {
          return current.home(
            context,
            cardKey: const ValueKey('home-next-course-card'),
            source: '下一节课',
            status: fixture.courseStatus,
            title: course.name,
            contextLabel: fixture.room.isEmpty ? '教室待确认' : fixture.room,
            time: '14:00 - 15:50',
            icon: fixture.courseStatus == '正在上课'
                ? LucideIcons.circlePlay500
                : LucideIcons.bookOpen300,
            accentColor: color,
            onTap: onOpen,
            semanticHint: '在课表中定位并打开课程详情',
          );
        }
        return _summary(
          context,
          color: color,
          icon: Icon(
            fixture.courseStatus == '正在上课'
                ? LucideIcons.circlePlay500
                : LucideIcons.bookOpen300,
            size: 17,
            color: color,
          ),
          source: '下一节课',
          contextLabel: fixture.room.isEmpty ? '教室待确认' : fixture.room,
          time: fixture.courseStatus,
          title: course.name,
          footer: '14:00 - 15:50',
          clock: true,
        );
      case CatalogKind.homeDeadline:
        return timeline(home: true, detail: false);
      case CatalogKind.ispaceDeadline:
        return timeline(home: false, detail: false);
      case CatalogKind.deadlineDetail:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (proposed || MediaQuery.sizeOf(context).width >= 700)
              _detailHeading(context, 'DDL详情'),
            timeline(home: false, detail: true),
            const SizedBox(height: 16),
            _info(context, '截止时间', monthDay),
            _info(context, '状态', item.isOverdue ? '已逾期' : '待完成'),
            if (!fixture.missingFields)
              _info(
                context,
                '说明',
                fixture.english
                    ? 'Upload the report and prototype files before the deadline.'
                    : '请在截止前上传调研报告与原型文件。',
              ),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(LucideIcons.arrowUpRight300),
              label: const BnbuText('打开 iSpace'),
            ),
          ],
        );
      case CatalogKind.homeEmpty:
        final loading = fixture.emptyState == '同步中';
        final loggedOut = fixture.emptyState == '未登录';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            current.home(
              context,
              cardKey: const ValueKey('home-empty-course'),
              source: '下一节课',
              status: loading ? '同步中' : '下一门课',
              title: loading
                  ? '正在同步课表…'
                  : loggedOut
                  ? '登录后查看下一门课'
                  : '暂无后续课程',
              contextLabel: fixture.emptyState == '失败' ? '同步失败' : '--',
              time: '--:--',
              icon: LucideIcons.bookOpen300,
              onTap: onOpen,
              semanticHint: '打开完整课表',
            ),
            const SizedBox(height: 12),
            current.home(
              context,
              cardKey: const ValueKey('home-empty-deadline'),
              source: 'iSpace',
              status: loading ? '同步中' : '下一个 DDL',
              title: loading
                  ? '正在同步 DDL…'
                  : loggedOut
                  ? '登录后查看下一个 DDL'
                  : '暂无待办 DDL',
              contextLabel: '--',
              time: '--:--',
              icon: LucideIcons.clipboardList300,
              onTap: null,
              semanticHint: '',
            ),
          ],
        );
      case CatalogKind.agendaCourse:
      case CatalogKind.agendaTa:
      case CatalogKind.agendaEvent:
      case CatalogKind.courseDetail:
        final detail = entry.kind == CatalogKind.courseDetail;
        final teacher = block.taCourse == null && course.teacher.isNotEmpty;
        final card = !proposed
            ? current.course(
                context,
                block,
                keyPrefix: 'catalog',
                onTap: detail ? null : onOpen,
                showChevron: !detail,
              )
            : _courseSummary(
                context,
                color: color,
                time: '14:00 - 15:50',
                title: course.name,
                location: fixture.room.isEmpty ? '--' : fixture.room,
                detail: detail,
                teacher: teacher ? course.teacher : null,
              );
        if (!detail) return card;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detailHeading(context, '课程详情'),
            card,
            const SizedBox(height: 16),
            _info(context, '本次时间', '周五 14:00–15:50'),
            _info(context, '课程类型', 'Major Required'),
            _info(context, '学分', '3'),
            _info(context, '节次', '1001'),
          ],
        );
      case CatalogKind.agendaDeadline:
        return proposed
            ? timeline(home: false, detail: false)
            : current.deadline(
                context,
                item,
                cardKey: const ValueKey('catalog-agenda-ddl'),
                onTap: onOpen,
                showChevron: true,
              );
      case CatalogKind.examWeek:
      case CatalogKind.examDay:
        final exam = ExamTimetableEntry(
          courseCode: 'COMP 3023',
          courseName: course.name,
          date: DateTime(2026, 9, 18),
          startMinutes: 840,
          endMinutes: 960,
          room: fixture.room,
          seat: fixture.missingFields ? '' : '018',
          remark: fixture.missingFields
              ? ''
              : fixture.textCase == CatalogTextCase.extreme
              ? 'Please bring your student ID and arrive 15 minutes early. Calculators without programmable functions are permitted. 请提前到场并携带学生证。'
              : (fixture.english ? 'Bring your student ID.' : '请携带学生证。'),
        );
        if (!proposed) {
          return current.exam(
            context,
            exam,
            showDate: entry.kind == CatalogKind.examWeek,
          );
        }
        return _shell(
          context,
          tokens.danger,
          Padding(
            padding: CatalogCardInsets.content(bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.kind == CatalogKind.examWeek ? '${context.l10n.formatMonthDay(exam.date)} ${context.l10n.formatWeekday(exam.date)} · ' : ''}${exam.timeLabel}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  exam.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(exam.courseCode),
                if (exam.room.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${exam.room} · ${context.l10n.text('座位')} ${exam.seat}',
                  ),
                ],
                if (exam.remark.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(exam.remark),
                ],
              ],
            ),
          ),
        );
      case CatalogKind.gridCourse:
      case CatalogKind.gridTa:
      case CatalogKind.gridEvent:
        return SizedBox(
          height: 168,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final height in [156.0, 70.0, 18.0]) ...[
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    child: SizedBox(
                      height: height,
                      child: Container(
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .08),
                          border: Border.all(
                            color: color.withValues(alpha: .35),
                            width: .5,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 1.5,
                              color: color.withValues(alpha: .75),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 3, 4, 4),
                                child: current.gridText(
                                  context,
                                  title: course.name,
                                  secondaryText:
                                      '14:00–15:50${fixture.room.isEmpty ? (isTa || isEvent ? '' : '\n${course.teacher}') : '\n${fixture.room}'}',
                                  compact: true,
                                  accent: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        );
      case CatalogKind.gridDeadline:
        return SizedBox(
          height: 64,
          child: Center(
            child: Tooltip(
              message: '${item.title}\n$monthDay',
              child: InkWell(
                onTap: onOpen,
                customBorder: const CircleBorder(),
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: ddlColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: ddlColor.withValues(alpha: .28),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.triangleAlert300,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case CatalogKind.courseRow:
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          onTap: onOpen,
          title: Text(
            course.name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          ),
          subtitle: fixture.missingFields
              ? null
              : const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('COMP 3023 · 1001'),
                ),
          trailing: Icon(
            LucideIcons.chevronRight300,
            size: 18,
            color: tokens.textMuted,
          ),
        );
      case CatalogKind.moduleRow:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 12,
          leading: MoodleActivityIcon(
            moduleName: fixture.activity,
            size: 20,
            color: tokens.brandBlue,
          ),
          title: Text(
            fixture.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          ),
          subtitle: fixture.due == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${context.l10n.text('截止时间')} · ${proposed ? monthDay : context.l10n.formatFullDateTime(fixture.due!)}',
                    style: TextStyle(fontSize: 12, color: tokens.textMuted),
                  ),
                ),
          trailing: Icon(
            LucideIcons.chevronRight300,
            size: 18,
            color: tokens.textMuted,
          ),
          onTap: onOpen,
        );
      case CatalogKind.manager:
        return Material(
          color: color.withValues(alpha: .04),
          child: InkWell(
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: .7),
                    width: 1.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${context.l10n.text('周五')}  14:00 - 15:50',
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        BnbuText(
                          'TA课 · 每周重复${fixture.room.isEmpty ? '' : ' · ${fixture.room}'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                        if (fixture.missingFields)
                          BnbuText(
                            '所属课程暂不可用',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.warning,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.text('课程操作'),
                    onPressed: onOpen,
                    icon: const Icon(LucideIcons.ellipsisVertical300),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }

  Widget _detailHeading(BuildContext context, String title) => Row(
    children: [
      Expanded(
        child: BnbuText(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      IconButton(
        tooltip: context.l10n.text('关闭'),
        onPressed: onOpen,
        icon: const Icon(LucideIcons.x300),
      ),
    ],
  );

  Widget _info(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BnbuText(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.bnbuTheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        BnbuText(value),
      ],
    ),
  );

  Widget _shell(
    BuildContext context,
    Color color,
    Widget child, {
    bool tappable = false,
  }) => BnbuSurfaceCard(
    borderRadius: BorderRadius.zero,
    padding: EdgeInsets.zero,
    onTap: tappable ? onOpen : null,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: CatalogCardInsets.rail,
            child: ColoredBox(color: color),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );

  // Courses retain their original field roles. Hit targets grow inward so
  // their visual contents remain on the same four corner insets as DDL cards.
  Widget _courseSummary(
    BuildContext context, {
    required Color color,
    required String time,
    required String title,
    required String location,
    required bool detail,
    String? teacher,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium!.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w600,
      height: 1.22,
    );
    final titleMeasure = TextPainter(
      text: TextSpan(
        text: List.filled(titleLines, 'Ag国').join('\n'),
        style: titleStyle,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final titleHeight = titleMeasure.height;
    titleMeasure.dispose();

    return _shell(
      context,
      color,
      Padding(
        padding: CatalogCardInsets.content(bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.clock3300, size: 17, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: BnbuText(
                    time,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (!detail) ...[
                  const SizedBox(width: 8),
                  Icon(
                    LucideIcons.arrowRight300,
                    size: 19,
                    color: tokens.textMuted,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: titleHeight),
              child: Text(
                title,
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.bottomLeft,
                heightFactor: 1,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      LucideIcons.mapPin300,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: BnbuText(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                    if (teacher != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomRight,
                          heightFactor: 1,
                          child: InkWell(
                            onTap: onOpen,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: 44,
                                minWidth: 44,
                              ),
                              child: Align(
                                alignment: Alignment.bottomRight,
                                heightFactor: 1,
                                widthFactor: 1,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        teacher,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: tokens.brandBlue,
                                              fontWeight: FontWeight.w700,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor: tokens.brandBlue,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      LucideIcons.contactRound300,
                                      size: 16,
                                      color: tokens.brandBlue,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      tappable: !detail,
    );
  }

  Widget _summary(
    BuildContext context, {
    required Color color,
    required Widget icon,
    String? source,
    String? contextLabel,
    required String time,
    required String title,
    required String footer,
    bool detail = false,
    bool arrow = true,
    bool clock = false,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.22,
    );
    final titleMeasure = TextPainter(
      text: TextSpan(
        text: List.filled(titleLines, 'Ag国').join('\n'),
        style: textStyle,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final titleAreaHeight = titleMeasure.height;
    titleMeasure.dispose();
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final timeWidget = BnbuText(
      time,
      style: theme.textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
    Widget sourceLine() => Row(
      children: [
        icon,
        const SizedBox(width: 8),
        if (source != null) ...[
          BnbuText(
            source,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (contextLabel != null)
          Expanded(
            child: Text(
              contextLabel,
              maxLines: large ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          const Spacer(),
      ],
    );
    final footerRow = Row(
      key: ValueKey('proposed-footer-${entry.id}'),
      children: [
        if (clock) ...[
          Icon(LucideIcons.clock3300, size: 16, color: tokens.textMuted),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: BnbuText(
            footer,
            maxLines: large ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (arrow) ...[
          const SizedBox(width: 8),
          Icon(LucideIcons.arrowRight300, size: 19, color: tokens.textMuted),
        ],
      ],
    );
    return _shell(
      context,
      color,
      Padding(
        padding: CatalogCardInsets.content(bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 116 - 12 - bottomInset),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (large) ...[
                    sourceLine(),
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerRight, child: timeWidget),
                  ] else
                    Row(
                      children: [
                        Expanded(child: sourceLine()),
                        const SizedBox(width: 8),
                        timeWidget,
                      ],
                    ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: detail ? 0 : titleAreaHeight,
                    ),
                    child: Text(
                      title,
                      maxLines: detail ? null : titleLines,
                      overflow: detail ? null : TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: 19),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: footerRow,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      tappable: !detail,
    );
  }
}

String currentCountdown(CatalogFixture fixture, {required bool home}) {
  final due = fixture.due;
  if (due == null) return '无日期';
  final diff = due.difference(CatalogFixture.now);
  if (diff <= Duration.zero) return home ? '已逾期 2 小时' : '已逾期';
  if (home) {
    if (diff.inHours < 1) return '仅剩 ${diff.inMinutes.clamp(1, 60)} 分钟';
    if (diff.inHours <= 24) return '仅剩 ${diff.inHours} 小时';
    return '剩余 ${diff.inDays} 天';
  }
  if (diff.inMinutes <= 0) return '已逾期';
  if (diff > const Duration(days: 2)) {
    return '${(diff.inMinutes / 1440).ceil()} 天';
  }
  return '${diff.inMinutes ~/ 60}h ${diff.inMinutes % 60}m';
}

String proposedCountdown(BuildContext context, CatalogFixture fixture) {
  final due = fixture.due;
  if (due == null) return context.l10n.text('无日期');
  final diff = due.difference(CatalogFixture.now);
  if (diff <= Duration.zero) return context.l10n.text('已逾期');
  final english = Localizations.localeOf(context).languageCode == 'en';
  if (diff <= const Duration(minutes: 1)) {
    return english ? 'Less than 1 min left' : '仅剩不到 1 分钟';
  }
  if (diff <= const Duration(hours: 24)) {
    final minutes = (diff.inSeconds / 60).ceil();
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final value = hours == 0
        ? (english ? '$rest min' : '$rest 分钟')
        : '${english ? '$hours hr' : '$hours 小时'}${rest == 0 ? '' : (english ? ' $rest min' : ' $rest 分钟')}';
    return english ? 'Only $value left' : '仅剩 $value';
  }
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  return english
      ? '$days d${hours == 0 ? '' : ' $hours hr'} left'
      : '剩余 $days 天${hours == 0 ? '' : ' $hours 小时'}';
}
