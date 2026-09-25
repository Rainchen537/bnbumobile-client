import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/cis_checkin.dart';
import '../theme/app_theme.dart';

Color _confirmedColor(BuildContext context) {
  final theme = context.bnbuTheme;
  return Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(theme.success, theme.textPrimary, .55)!
      : theme.success;
}

Color _uncompletedColor(BuildContext context) {
  final theme = context.bnbuTheme;
  return Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(theme.danger, theme.textPrimary, .35)!
      : theme.danger;
}

String checkinDate(BuildContext context, DateTime? date) => date == null
    ? context.l10n.text('学校未提供')
    : context.l10n.dateTimeFormatter().format(cisCampusDate(date));

class CisProjectCard extends StatelessWidget {
  const CisProjectCard({
    super.key,
    required this.project,
    this.onTap,
    this.selected = false,
  });
  final CisCheckinProject project;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = context.bnbuTheme;
    final stateColor = project.completed
        ? _confirmedColor(context)
        : theme.brandBlue;
    return Material(
      color: selected ? theme.selectedSurface : theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? theme.brandBlue : theme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${context.l10n.text('已打卡')} ${project.checkedCount} / '
                    '${context.l10n.text('要求次数')} ${project.requiredCount}',
                    style: TextStyle(fontSize: 14, color: theme.textPrimary),
                  ),
                  BnbuText(
                    project.completed ? '已完成' : '未完成',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: stateColor,
                    ),
                  ),
                ],
              ),
              if (project.requiredCount > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (project.checkedCount / project.requiredCount).clamp(
                    0,
                    1,
                  ),
                  minHeight: 3,
                  color: stateColor,
                  backgroundColor: theme.surfaceMuted,
                  semanticsLabel: context.l10n.text('打卡进度'),
                ),
              ],
              if (project.opensAt != null || project.closesAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${checkinDate(context, project.opensAt)} —\n'
                  '${checkinDate(context, project.closesAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CisRecordCard extends StatelessWidget {
  const CisRecordCard({super.key, required this.record});
  final CisCheckinRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = context.bnbuTheme;
    final title = !context.l10n.isEnglish && record.nameCn.isNotEmpty
        ? record.nameCn
        : record.name;
    return Material(
      color: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('cis-record-${record.id}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: theme.textSecondary,
        trailing: const Icon(LucideIcons.chevronDown300, size: 20),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.sessions.isNotEmpty)
                Text(
                  checkinDate(context, record.sessions.first.beginsAt),
                  style: TextStyle(fontSize: 13, color: theme.textSecondary),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _status(context, '签到', record.checkedIn),
                  _status(context, '签退', record.checkedOut),
                  BnbuText(
                    record.completed ? '已完成' : '未完成',
                    style: TextStyle(
                      color: record.completed
                          ? _confirmedColor(context)
                          : _uncompletedColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        children: [
          if (record.speaker.isNotEmpty) _line(context, '主讲人', record.speaker),
          if (record.location.isNotEmpty) _line(context, '地点', record.location),
          for (var i = 0; i < record.sessions.length; i++) ...[
            const Divider(height: 24),
            if (record.sessions.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${context.l10n.text('场次')} ${i + 1}'),
              ),
            _line(
              context,
              '活动时间',
              '${checkinDate(context, record.sessions[i].beginsAt)} — '
                  '${checkinDate(context, record.sessions[i].endsAt)}',
            ),
            _line(
              context,
              '签到时间',
              checkinDate(context, record.sessions[i].checkinAt),
            ),
            _line(
              context,
              '签退时间',
              checkinDate(context, record.sessions[i].checkoutAt),
            ),
          ],
        ],
      ),
    );
  }

  Widget _status(BuildContext context, String label, bool value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        value ? LucideIcons.check300 : LucideIcons.x300,
        size: 16,
        color: value ? _confirmedColor(context) : _uncompletedColor(context),
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          '${context.l10n.text(label)} · ${context.l10n.text(value ? '已完成' : '未完成')}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    ],
  );

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '${context.l10n.text(label)}  $value',
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: context.bnbuTheme.textSecondary,
        ),
      ),
    ),
  );
}
