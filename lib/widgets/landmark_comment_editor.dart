import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

/// Shared visual shell. Submission, identity and immediate rating stay with
/// the community controller; closing this surface never submits a comment.
class LandmarkCommentEditor extends StatelessWidget {
  const LandmarkCommentEditor({
    super.key,
    required this.title,
    required this.controller,
    required this.anonymous,
    required this.anonymousName,
    required this.onIdentityChanged,
    required this.onClose,
    required this.onSubmit,
    required this.sending,
    required this.editing,
    this.photo,
    this.stars,
    this.showRating = true,
    this.onRate,
    this.onDelete,
    this.replyName,
    this.replyBody,
    this.failure,
  });
  final String title, anonymousName;
  final String? replyName, replyBody, failure;
  final TextEditingController controller;
  final bool anonymous, sending, editing;
  final Future<Widget>? photo;
  final int? stars;
  final bool showRating;
  final ValueChanged<bool>? onIdentityChanged;
  final ValueChanged<int>? onRate;
  final VoidCallback? onClose, onSubmit, onDelete;
  static const blue = Color(0xff25a5e8);

  @override
  Widget build(BuildContext context) {
    final theme = context.bnbuTheme;
    final replying = replyName != null;
    final inputColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xfff5f6f7)
        : theme.canvas;
    final muted = theme.textMuted;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final toolStyle = TextButton.styleFrom(
      foregroundColor: muted,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(44, 44),
      textStyle: const TextStyle(fontSize: 12),
    );
    final toolbar = Material(
      color: theme.surface,
      child: SafeArea(
        top: false,
        bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (editing && onDelete != null)
                TextButton(
                  style: toolStyle,
                  onPressed: onDelete,
                  child: const BnbuText('删除'),
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: anonymous
                        ? anonymousName
                        : context.l10n.text('公开显示iSpace姓名与头像'),
                    child: MergeSemantics(
                      child: InkWell(
                        key: const ValueKey('me-comment-identity'),
                        onTap: onIdentityChanged == null
                            ? null
                            : () => onIdentityChanged!(!anonymous),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 44,
                              child: Center(
                                child: SizedBox.square(
                                  key: const ValueKey(
                                    'me-comment-anonymous-visual',
                                  ),
                                  dimension: Checkbox.width * .9,
                                  child: Transform.scale(
                                    scale: .9,
                                    child: Checkbox(
                                      key: const ValueKey(
                                        'me-comment-anonymous',
                                      ),
                                      value: anonymous,
                                      onChanged: onIdentityChanged == null
                                          ? null
                                          : (value) => onIdentityChanged!(
                                              value ?? false,
                                            ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      side: BorderSide(
                                        color: muted,
                                        width: 1.2,
                                      ),
                                      activeColor: theme.brandBlue,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              child: BnbuText(
                                '匿名发布',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  child: TextButton(
                    key: const ValueKey('me-comment-submit'),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(60, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2),
                      ),
                      textStyle: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(fontSize: 14),
                    ),
                    onPressed: value.text.trim().isEmpty ? null : onSubmit,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 28),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: value.text.trim().isEmpty || onSubmit == null
                            ? muted.withValues(alpha: .35)
                            : blue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: BnbuText(
                        sending
                            ? '正在保存'
                            : editing
                            ? '保存'
                            : '发布',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!replying) const SizedBox(height: 25),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Material(
                        color: theme.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                        child: SafeArea(
                          top: false,
                          bottom: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!replying) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    48,
                                    40,
                                    48,
                                    0,
                                  ),
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      color: theme.textPrimary,
                                    ),
                                  ),
                                ),
                                if (showRating) ...[
                                  const SizedBox(height: 20),
                                  Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var i = 1; i <= 5; i++)
                                          Semantics(
                                            button: true,
                                            selected: stars == i,
                                            label:
                                                '$i ${context.l10n.text('星')}',
                                            child: InkWell(
                                              key: ValueKey(
                                                'me-editor-rating-$i',
                                              ),
                                              onTap: onRate == null
                                                  ? null
                                                  : () => onRate!(i),
                                              child: SizedBox(
                                                width: 41,
                                                height: 44,
                                                child: Icon(
                                                  Icons.star_rounded,
                                                  size: 34,
                                                  color: i <= (stars ?? 0)
                                                      ? blue
                                                      : muted.withValues(
                                                          alpha: .35,
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 28),
                              ] else
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    22,
                                    48,
                                    12,
                                  ),
                                  child: Text(
                                    '${context.l10n.text('回复')}「$replyName」：${replyBody ?? ''}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: muted,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: SizedBox(
                                  height: 80 * scale.clamp(1, 2),
                                  child: TextField(
                                    key: const ValueKey('me-comment-input'),
                                    controller: controller,
                                    autofocus: true,
                                    enabled: !sending,
                                    expands: true,
                                    minLines: null,
                                    maxLines: null,
                                    maxLength: 2000,
                                    maxLengthEnforcement: MaxLengthEnforcement
                                        .truncateAfterCompositionEnds,
                                    textAlignVertical: TextAlignVertical.top,
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.4,
                                      color: theme.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: true,
                                      fillColor: inputColor,
                                      contentPadding: const EdgeInsets.all(6),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      disabledBorder: InputBorder.none,
                                      counterText: '',
                                      hintText: context.l10n.text(
                                        replying ? '回复内容' : '写下你的评论',
                                      ),
                                      hintStyle: TextStyle(
                                        color: muted.withValues(alpha: .5),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (failure != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    6,
                                    16,
                                    0,
                                  ),
                                  child: BnbuText(
                                    failure!,
                                    style: TextStyle(
                                      color: theme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Divider(
                                height: 1,
                                thickness: .5,
                                color: theme.border,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!replying)
                        Positioned(
                          top: -25,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              key: const ValueKey('me-editor-place-photo'),
                              width: 52,
                              height: 52,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: theme.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: photo == null
                                    ? Icon(
                                        LucideIcons.building2300,
                                        color: muted,
                                      )
                                    : FutureBuilder<Widget>(
                                        future: photo,
                                        builder: (context, snapshot) =>
                                            snapshot.data ??
                                            ColoredBox(color: inputColor),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 0,
                        right: 2,
                        child: IconButton(
                          onPressed: onClose,
                          tooltip: context.l10n.text('关闭'),
                          icon: Icon(LucideIcons.x300, size: 20, color: muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          toolbar,
        ],
      ),
    );
  }
}
