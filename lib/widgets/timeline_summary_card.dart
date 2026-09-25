import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/timeline_item.dart';
import '../theme/app_theme.dart';
import 'bnbu_components.dart';
import 'moodle_activity_icon.dart';

class TimelineActivityVisual {
  const TimelineActivityVisual({
    required this.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final String key;
  final IconData icon;
  final String label;
  final Color color;
}

TimelineActivityVisual timelineActivityVisualFor({
  required String moduleName,
  required String activityType,
}) {
  final normalized = moodleActivityTypeKey(moduleName, activityType);
  return switch (normalized) {
    'assign' => const TimelineActivityVisual(
      key: 'assign',
      icon: LucideIcons.upload300,
      label: '作业',
      color: Color(0xFFDB2777),
    ),
    'quiz' => const TimelineActivityVisual(
      key: 'quiz',
      icon: LucideIcons.circleCheck300,
      label: '测验',
      color: Color(0xFFDB2777),
    ),
    'forum' => const TimelineActivityVisual(
      key: 'forum',
      icon: LucideIcons.messageCircle300,
      label: '论坛',
      color: Color(0xFFEA580C),
    ),
    'resource' => const TimelineActivityVisual(
      key: 'resource',
      icon: LucideIcons.fileText300,
      label: '资源',
      color: Color(0xFF2563EB),
    ),
    'folder' => const TimelineActivityVisual(
      key: 'folder',
      icon: LucideIcons.folder300,
      label: '文件夹',
      color: Color(0xFFB45309),
    ),
    'choice' => const TimelineActivityVisual(
      key: 'choice',
      icon: LucideIcons.vote300,
      label: '投票',
      color: Color(0xFF166534),
    ),
    'mediasite' => const TimelineActivityVisual(
      key: 'mediasite',
      icon: LucideIcons.video300,
      label: '视频',
      color: Color(0xFF6D28D9),
    ),
    'page' => const TimelineActivityVisual(
      key: 'page',
      icon: LucideIcons.fileText300,
      label: '页面',
      color: Color(0xFF334155),
    ),
    'url' => const TimelineActivityVisual(
      key: 'url',
      icon: LucideIcons.link300,
      label: '链接',
      color: Color(0xFF0F766E),
    ),
    'book' => const TimelineActivityVisual(
      key: 'book',
      icon: LucideIcons.bookOpen300,
      label: '图书',
      color: Color(0xFF2563EB),
    ),
    'feedback' => const TimelineActivityVisual(
      key: 'feedback',
      icon: LucideIcons.messageSquare300,
      label: '反馈',
      color: Color(0xFF166534),
    ),
    'lesson' => const TimelineActivityVisual(
      key: 'lesson',
      icon: LucideIcons.presentation300,
      label: '互动课程',
      color: Color(0xFF2563EB),
    ),
    'workshop' => const TimelineActivityVisual(
      key: 'workshop',
      icon: LucideIcons.users300,
      label: '工作坊',
      color: Color(0xFFDB2777),
    ),
    'survey' => const TimelineActivityVisual(
      key: 'survey',
      icon: LucideIcons.clipboardList300,
      label: '调查',
      color: Color(0xFF166534),
    ),
    'wiki' => const TimelineActivityVisual(
      key: 'wiki',
      icon: LucideIcons.notebookPen300,
      label: '协作页面',
      color: Color(0xFFEA580C),
    ),
    'glossary' => const TimelineActivityVisual(
      key: 'glossary',
      icon: LucideIcons.bookA300,
      label: '词汇表',
      color: Color(0xFFEA580C),
    ),
    'scorm' => const TimelineActivityVisual(
      key: 'scorm',
      icon: LucideIcons.package300,
      label: '学习包',
      color: Color(0xFF2563EB),
    ),
    'imscp' => const TimelineActivityVisual(
      key: 'imscp',
      icon: LucideIcons.package300,
      label: '内容包',
      color: Color(0xFF2563EB),
    ),
    'data' => const TimelineActivityVisual(
      key: 'data',
      icon: LucideIcons.database300,
      label: '数据库',
      color: Color(0xFFEA580C),
    ),
    'lti' => const TimelineActivityVisual(
      key: 'lti',
      icon: LucideIcons.externalLink300,
      label: '外部工具',
      color: Color(0xFF2563EB),
    ),
    'label' => const TimelineActivityVisual(
      key: 'label',
      icon: LucideIcons.text300,
      label: '文本与媒体',
      color: Color(0xFF334155),
    ),
    _ => TimelineActivityVisual(
      key: normalized.isEmpty ? 'generic' : normalized,
      icon: LucideIcons.grid2X2300,
      label: activityType.trim().isEmpty ? '活动' : activityType.trim(),
      color: const Color(0xFF166534),
    ),
  };
}

/// Shared deadline state colors for the home and iSpace summaries.
Color timelineSummaryAccentColor(
  TimelineItem item,
  BnbuThemeExtension tokens, {
  required DateTime now,
}) => item.isOverdue || (item.sortTime != null && item.sortTime!.isBefore(now))
    ? tokens.danger
    : tokens.brandBlue;

class BnbuTimelineSummaryCard extends StatelessWidget {
  static const double typeIconSize = 17;

  const BnbuTimelineSummaryCard({
    super.key,
    required this.item,
    required this.deadlineLabel,
    required this.statusLabel,
    required this.accentColor,
    required this.onTap,
    this.showIspaceLabel = false,
    this.showChevron = true,
    this.semanticHint = '打开 iSpace 活动详情',
  });

  final TimelineItem item;
  final String deadlineLabel;
  final String statusLabel;
  final Color accentColor;
  final VoidCallback? onTap;
  final bool showIspaceLabel;
  final bool showChevron;
  final String semanticHint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final visual = timelineActivityVisualFor(
      moduleName: item.moduleName,
      activityType: item.activityType,
    );
    final contextLabel = item.courseName.trim().isEmpty
        ? visual.label
        : item.courseName.trim();
    final useStackedMeta = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final timeWidth =
            (constraints.maxWidth -
                    tokens.space16 -
                    5 -
                    tokens.space12 -
                    typeIconSize -
                    tokens.space8 * 2)
                .clamp(0.0, double.infinity);
        Widget deadline() => ConstrainedBox(
          key: ValueKey('timeline-summary-time-${item.id}'),
          constraints: BoxConstraints(maxWidth: timeWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: BnbuText(
              deadlineLabel,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelMedium?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
        return Semantics(
          button: onTap != null,
          label: '${visual.label}：${item.title}',
          value: context.l10n.text(
            '$statusLabel，截止时间 $deadlineLabel，$contextLabel',
          ),
          hint: onTap == null ? null : semanticHint,
          child: BnbuSurfaceCard(
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
                    child: ColoredBox(color: accentColor),
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
                              MoodleActivityIcon(
                                key: ValueKey(
                                  'timeline-summary-type-icon-${item.id}',
                                ),
                                moduleName: item.moduleName,
                                activityType: item.activityType,
                                size: typeIconSize,
                                color: accentColor,
                              ),
                              SizedBox(width: tokens.space8),
                              Expanded(
                                child: BnbuText(
                                  showIspaceLabel ? 'iSpace' : visual.label,
                                  key: showIspaceLabel
                                      ? ValueKey(
                                          'timeline-summary-ispace-label-${item.id}',
                                        )
                                      : null,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: accentColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              SizedBox(width: tokens.space8),
                              deadline(),
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
                              MoodleActivityIcon(
                                key: ValueKey(
                                  'timeline-summary-type-icon-${item.id}',
                                ),
                                moduleName: item.moduleName,
                                activityType: item.activityType,
                                size: typeIconSize,
                                color: accentColor,
                              ),
                              SizedBox(width: tokens.space8),
                              if (showIspaceLabel) ...[
                                BnbuText(
                                  'iSpace',
                                  key: ValueKey(
                                    'timeline-summary-ispace-label-${item.id}',
                                  ),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: accentColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: tokens.space4),
                                BnbuText(
                                  '·',
                                  style: TextStyle(color: tokens.textMuted),
                                ),
                                SizedBox(width: tokens.space4),
                              ],
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
                              deadline(),
                            ],
                          ),
                        SizedBox(height: tokens.space8),
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
                        Row(
                          children: [
                            Expanded(
                              child: BnbuText(
                                statusLabel,
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
                            if (showChevron && onTap != null)
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
      },
    );
  }
}
