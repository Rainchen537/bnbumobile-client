// Review-only copies of the private builders at d9e8218.
// Geometry and typography are retained; data and navigation are synthetic.
// Home tone lookup is replaced by its resolved color argument.
// Public Timeline cards are imported directly by the catalog.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bnbu_me/models/exam_timetable.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';

class CatalogMeeting {
  const CatalogMeeting(this.course, this.meeting, this.color, {this.taCourse});
  final TimetableCourse course;
  final TimetableMeeting meeting;
  final Color color;
  final Object? taCourse;
}

class CurrentAcademicCards {
  const CurrentAcademicCards(
    this.context,
    this.onTeacher, {
    this.measureScaledText = false,
  });
  final bool measureScaledText;
  final BuildContext context;
  final VoidCallback onTeacher;
  String _deadlineLabel(TimelineItem item) => item.sortTime == null
      ? (item.formattedTime.isEmpty ? '无时间信息' : item.formattedTime)
      : context.l10n.formatMonthDayTime(item.sortTime!.toLocal());
  Color _deadlineAccentColor(TimelineItem item, BnbuThemeExtension tokens) =>
      item.isOverdue
      ? tokens.danger
      : Color.lerp(tokens.danger, tokens.warning, .18)!;
  Widget _buildTeacherLink(BuildContext context, String names) => InkWell(
    onTap: onTeacher,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: BnbuText(
                names,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.bnbuTheme.brandBlue,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: context.bnbuTheme.brandBlue,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.contactRound300,
              size: 16,
              color: context.bnbuTheme.brandBlue,
            ),
          ],
        ),
      ),
    ),
  );
  Widget home(
    BuildContext context, {
    required Key cardKey,
    required String source,
    required String status,
    required String title,
    required String contextLabel,
    required String time,
    required IconData icon,
    Color? accentColor,
    required VoidCallback? onTap,
    required String semanticHint,
  }) {
    final tokens = context.bnbuTheme;
    final foreground = accentColor ?? tokens.brandBlue;
    final theme = Theme.of(context);
    final useStackedMeta = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      button: onTap != null,
      hint: semanticHint,
      child: BnbuSurfaceCard(
        key: cardKey,
        onTap: onTap,
        backgroundColor: tokens.surface,
        borderRadius: BorderRadius.zero,
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 116),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 5,
                child: ColoredBox(
                  key: cardKey == const ValueKey('home-next-course-card')
                      ? const ValueKey('home-course-accent')
                      : null,
                  color: foreground,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  tokens.space16 + 5,
                  tokens.space12,
                  tokens.space12,
                  tokens.space12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (useStackedMeta) ...[
                      Row(
                        children: [
                          Icon(icon, size: 17, color: foreground),
                          SizedBox(width: tokens.space8),
                          Expanded(
                            child: BnbuText(
                              source,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.space8),
                          BnbuText(
                            status,
                            key: ValueKey('home-primary-status-$status'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: tokens.space4),
                      BnbuText(
                        contextLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else
                      Row(
                        children: [
                          Icon(icon, size: 17, color: foreground),
                          SizedBox(width: tokens.space8),
                          BnbuText(
                            source,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: tokens.space4),
                          BnbuText(
                            '·',
                            style: TextStyle(color: tokens.textMuted),
                          ),
                          SizedBox(width: tokens.space4),
                          Expanded(
                            child: BnbuText(
                              contextLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.space8),
                          BnbuText(
                            status,
                            key: ValueKey('home-primary-status-$status'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: tokens.space12),
                    BnbuText(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.22,
                      ),
                    ),
                    SizedBox(height: tokens.space12),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.clock3300,
                          size: 16,
                          color: tokens.textMuted,
                        ),
                        SizedBox(width: tokens.space4),
                        Expanded(
                          child: BnbuText(
                            time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            LucideIcons.arrowRight300,
                            color: tokens.textMuted,
                            size: 19,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget course(
    BuildContext context,
    CatalogMeeting block, {
    required String keyPrefix,
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final accent = block.color;
    final location = block.meeting.room.isEmpty ? '--' : block.meeting.room;
    return Semantics(
      button: onTap != null,
      label: context.l10n.text('课程：${block.course.name}'),
      value: '${block.meeting.startLabel}-${block.meeting.endLabel}，$location',
      child: BnbuSurfaceCard(
        key: ValueKey(
          '$keyPrefix-course-${block.course.code}-'
          '${block.meeting.startMinutes}',
        ),
        onTap: onTap,
        backgroundColor: tokens.surface,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: ValueKey(
                  '$keyPrefix-accent-${block.course.code}-'
                  '${block.meeting.startMinutes}',
                ),
                width: 5,
                color: accent,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    tokens.space16,
                    tokens.space12,
                    tokens.space12,
                    tokens.space12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(LucideIcons.clock3300, size: 17, color: accent),
                          SizedBox(width: tokens.space8),
                          Expanded(
                            child: BnbuText(
                              '${block.meeting.startLabel} - '
                              '${block.meeting.endLabel}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          if (showChevron) ...[
                            Icon(
                              LucideIcons.arrowRight300,
                              color: tokens.textMuted,
                              size: 19,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: tokens.space12),
                      BnbuText(
                        block.course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.22,
                        ),
                      ),
                      SizedBox(height: tokens.space8),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.mapPin300,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                          SizedBox(width: tokens.space4),
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
                          if (block.course.teacher.isNotEmpty &&
                              block.taCourse == null) ...[
                            SizedBox(width: tokens.space12),
                            Flexible(
                              child: _buildTeacherLink(
                                context,
                                block.course.teacher,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget deadline(
    BuildContext context,
    TimelineItem item, {
    required Key cardKey,
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final accent = _deadlineAccentColor(item, tokens);
    return Semantics(
      button: true,
      label: 'DDL：${item.title}',
      value: context.l10n.text('截止时间 ${_deadlineLabel(item)}'),
      child: BnbuSurfaceCard(
        key: cardKey,
        onTap: onTap,
        backgroundColor: tokens.surface,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.zero,
        child: Row(
          children: [
            Container(width: 5, height: 116, color: accent),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  tokens.space16,
                  tokens.space12,
                  tokens.space12,
                  tokens.space12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.triangleAlert300,
                          size: 17,
                          color: accent,
                        ),
                        SizedBox(width: tokens.space8),
                        Expanded(
                          child: BnbuText(
                            _deadlineLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (showChevron)
                          Icon(
                            LucideIcons.arrowRight300,
                            color: tokens.textMuted,
                            size: 19,
                          ),
                      ],
                    ),
                    SizedBox(height: tokens.space12),
                    BnbuText(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.22,
                      ),
                    ),
                    SizedBox(height: tokens.space8),
                    BnbuText(
                      item.courseName.isEmpty ? 'DDL' : item.courseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget exam(
    BuildContext context,
    ExamTimetableEntry exam, {
    required bool showDate,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final location = <String>[
      if (exam.room.isNotEmpty) exam.room,
      if (exam.seat.isNotEmpty) '座位 ${exam.seat}',
    ].join(' · ');
    final dateLabel = showDate
        ? '${context.l10n.formatMonthDay(exam.date)} '
              '${context.l10n.formatWeekday(exam.date)} · '
        : '';
    return BnbuSurfaceCard(
      key: ValueKey('schedule-exam-${exam.widgetKey}'),
      backgroundColor: tokens.surface,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.fromLTRB(
        tokens.space16,
        tokens.space12,
        tokens.space16,
        tokens.space12,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: tokens.danger),
            SizedBox(width: tokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BnbuText(
                    '$dateLabel${exam.timeLabel}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: tokens.danger,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: tokens.space4),
                  BnbuText(
                    exam.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (exam.courseCode.isNotEmpty &&
                      exam.courseCode != exam.displayName) ...[
                    SizedBox(height: tokens.space4),
                    BnbuText(
                      exam.courseCode,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                  if (location.isNotEmpty) ...[
                    SizedBox(height: tokens.space4),
                    BnbuText(
                      location,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                  if (exam.remark.isNotEmpty) ...[
                    SizedBox(height: tokens.space4),
                    BnbuText(
                      exam.remark,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget gridText(
    BuildContext context, {
    required String title,
    required String secondaryText,
    required bool compact,
    required Color accent,
  }) {
    final tokens = context.bnbuTheme;
    final titleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      fontSize: compact ? 7.8 : 9.8,
      height: compact ? 1.1 : 1.15,
    );
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Color.lerp(accent, tokens.textPrimary, 0.4),
      fontSize: compact ? 6.8 : 8.8,
      height: 1.15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );

    if (secondaryText.isEmpty) {
      return BnbuText(
        title,
        maxLines: compact ? 8 : 8,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final gap = compact ? 2.0 : 4.0;

        final titlePainter = _textPainter(
          context: context,
          text: title,
          style: titleStyle,
          maxWidth: width,
        );
        final titleLineHeight = titlePainter.preferredLineHeight;
        if (height < titleLineHeight * 2) {
          return ClipRect(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: titleStyle,
            ),
          );
        }
        final secondaryPainter = _textPainter(
          context: context,
          text: secondaryText,
          style: secondaryStyle,
          maxWidth: width,
        );
        final secondaryLineHeight = secondaryPainter.preferredLineHeight;
        final secondaryLineCount = secondaryPainter.computeLineMetrics().length;
        final secondaryMaxLines =
            ((height - gap - titleLineHeight) / secondaryLineHeight)
                .floor()
                .clamp(1, 99);
        final displayedSecondaryLines = secondaryLineCount.clamp(
          1,
          secondaryMaxLines,
        );
        final displayedSecondaryHeight =
            displayedSecondaryLines * secondaryLineHeight;
        final remainingTitleHeight = (height - displayedSecondaryHeight - gap)
            .clamp(titleLineHeight, height);
        final titleMaxLines = (remainingTitleHeight / titleLineHeight)
            .floor()
            .clamp(1, 99);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: BnbuText(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
            SizedBox(height: gap),
            BnbuText(
              secondaryText,
              maxLines: displayedSecondaryLines,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: secondaryStyle,
            ),
          ],
        );
      },
    );
  }

  TextPainter _textPainter({
    required BuildContext context,
    required String text,
    required TextStyle? style,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: measureScaledText
          ? MediaQuery.textScalerOf(context)
          : TextScaler.noScaling,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter;
  }
}
