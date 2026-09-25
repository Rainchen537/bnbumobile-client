import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

/// Shared by teacher and campus landmark reviews. Inputs remain integer 1–5;
/// averages may contain fractional values and display one decimal place.
class StudentReviewRating extends StatelessWidget {
  const StudentReviewRating({super.key, required this.value, this.size = 16});
  final double value;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${context.l10n.text('评分')} ${value.toStringAsFixed(1)} / 5',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w500,
              color: context.bnbuTheme.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            LucideIcons.star300,
            size: size,
            color: context.bnbuTheme.warning,
          ),
        ],
      ),
    ),
  );
}

class StudentReviewAction extends StatelessWidget {
  const StudentReviewAction({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(LucideIcons.pencil300, size: 16),
    label: BnbuText(label),
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    ),
  );
}

class StudentReviewRow extends StatelessWidget {
  const StudentReviewRow({
    super.key,
    this.rating,
    required this.comment,
    required this.updatedAt,
    this.isMine = false,
    this.hidden = false,
    this.hiddenReason = '',
    this.onEdit,
    this.editKey,
    this.details,
    this.badges = const [],
  });
  final int? rating;
  final String comment, hiddenReason;
  final DateTime updatedAt;
  final bool isMine, hidden;
  final VoidCallback? onEdit;
  final Key? editKey;
  final Widget? details;
  final List<Widget> badges;
  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: isMine
            ? BorderDirectional(
                start: BorderSide(color: tokens.brandBlue, width: 2),
              )
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    BnbuText(
                      isMine ? '我的评价' : '匿名同学',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isMine ? tokens.brandBlue : tokens.textPrimary,
                      ),
                    ),
                    ...badges,
                    if (hidden)
                      BnbuText(
                        '管理员已隐藏',
                        style: TextStyle(fontSize: 12, color: tokens.warning),
                      ),
                  ],
                ),
              ),
              if (rating != null) ...[
                const SizedBox(width: 12),
                StudentReviewRating(value: rating!.toDouble()),
              ],
            ],
          ),
          if (details != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: details!),
          if (comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                comment,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.55,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          if (hidden && hiddenReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                hiddenReason,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.formatMediumDate(updatedAt.toLocal()),
                  style: TextStyle(fontSize: 12, color: tokens.textMuted),
                ),
              ),
              if (isMine)
                StudentReviewAction(
                  key: editKey,
                  label: '编辑',
                  onPressed: onEdit,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class StudentReviewRatingPicker extends StatelessWidget {
  const StudentReviewRatingPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'student-review-rating',
  });
  final int value;
  final ValueChanged<int>? onChanged;
  final String keyPrefix;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    children: [
      for (var i = 1; i <= 5; i++)
        IconButton(
          key: ValueKey('$keyPrefix-$i'),
          tooltip: '$i / 5',
          isSelected: i <= value,
          onPressed: onChanged == null ? null : () => onChanged!(i),
          icon: Icon(
            LucideIcons.star300,
            color: i <= value
                ? context.bnbuTheme.warning
                : context.bnbuTheme.textMuted,
            size: 28,
          ),
        ),
    ],
  );
}
