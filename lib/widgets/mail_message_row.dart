import 'bnbu_loading.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/mail_models.dart';
import '../services/mail_address_parser.dart';
import '../services/mail_sender_avatar_service.dart';
import '../theme/app_theme.dart';
import 'mail_sender_avatar.dart';

class MailSelectionNotification extends Notification {
  MailSelectionNotification(this.active);
  final bool active;
}

/// Mail keeps its reference geometry and uses the shared semantic palette.
class MailSurfaceColors {
  MailSurfaceColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark,
      highContrast = MediaQuery.highContrastOf(context),
      tokens = context.bnbuTheme;
  final bool dark;
  final bool highContrast;
  final BnbuThemeExtension tokens;
  Color get background => tokens.surface;
  Color get search => tokens.surfaceMuted;
  Color get foreground => tokens.textPrimary;
  Color get secondary => highContrast ? tokens.textSecondary : tokens.textMuted;
  Color get control => tokens.textSecondary;
  Color get divider => tokens.border.withValues(alpha: 0.55);
  Color get accent => tokens.brandBlue;
  Color get menu => tokens.surfaceMuted;
  Color get selected => tokens.selectedSurface;
}

String mailDisplayName(String sender) {
  if (!sender.contains('@')) return sender.trim();
  try {
    final addresses = parseMailRecipientAddresses(sender);
    if (addresses.isEmpty) return sender.trim();
    final address = addresses.first;
    final name = address.personalName?.trim() ?? '';
    return name.isNotEmpty ? name : address.email.split('@').first;
  } on FormatException {
    // Inbound display text is not an outgoing-address validation request.
    return sender.trim();
  }
}

class MailRowTag {
  const MailRowTag(this.label, this.color);
  final String label;
  final Color color;
}

class MailSwipeAction {
  const MailSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
}

class MailMessageRow extends StatefulWidget {
  const MailMessageRow({
    super.key,
    required this.message,
    required this.timeLabel,
    required this.onTap,
    required this.avatarService,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.busy = false,
    this.tags = const [],
    this.subjectColor,
    this.swipeActions = const [],
    this.openSwipe,
    this.threadCount = 1,
  });
  final MailMessageSummary message;
  final String timeLabel;
  final MailSenderAvatarService? avatarService;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final bool busy;
  final List<MailRowTag> tags;
  final Color? subjectColor;
  final List<MailSwipeAction> swipeActions;
  final ValueNotifier<String?>? openSwipe;
  final int threadCount;
  @override
  State<MailMessageRow> createState() => _MailMessageRowState();
}

class _MailMessageRowState extends State<MailMessageRow> {
  double _offset = 0;
  bool _dragging = false;
  double get _actionExtent => widget.swipeActions.length * 72.0;
  @override
  void initState() {
    super.initState();
    widget.openSwipe?.addListener(_handleOpenRow);
  }

  @override
  void didUpdateWidget(MailMessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openSwipe != widget.openSwipe) {
      oldWidget.openSwipe?.removeListener(_handleOpenRow);
      widget.openSwipe?.addListener(_handleOpenRow);
    }
    if (widget.selectionMode ||
        widget.message.identityKey != oldWidget.message.identityKey) {
      _offset = 0;
    }
  }

  void _handleOpenRow() {
    if (widget.openSwipe?.value != widget.message.identityKey &&
        _offset != 0 &&
        mounted) {
      setState(() => _offset = 0);
    }
  }

  @override
  void dispose() {
    widget.openSwipe?.removeListener(_handleOpenRow);
    super.dispose();
  }

  void _close() {
    if (widget.openSwipe?.value == widget.message.identityKey) {
      widget.openSwipe?.value = null;
    }
    if (mounted) setState(() => _offset = 0);
  }

  Widget _previewLine(
    MailSurfaceColors colors,
    String preview,
  ) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        for (final tag in widget.tags.take(2))
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.30,
              ),
              child: Text(
                context.l10n.text(tag.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 1.4, color: tag.color),
              ),
            ),
          ),
        Expanded(
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w400,
              color: colors.secondary,
            ),
          ),
        ),
        if (widget.busy)
          const SizedBox.square(dimension: 12, child: BnbuActivityIndicator()),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = MailSurfaceColors(context);
    final message = widget.message;
    final preview = message.readablePreview;
    final canSwipe =
        !widget.selectionMode && !widget.busy && widget.swipeActions.isNotEmpty;
    final separatorInset = widget.selectionMode ? 104.0 : 64.0;
    final row = Material(
      color: colors.background,
      child: InkWell(
        onTap: widget.busy
            ? null
            : () {
                if (_offset != 0) {
                  _close();
                } else {
                  widget.onTap();
                }
              },
        onLongPress: widget.busy ? null : widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.selectionMode) ...[
                SizedBox(
                  width: 24,
                  height: 64,
                  child: Icon(
                    widget.selected
                        ? LucideIcons.circleCheck300
                        : LucideIcons.circle300,
                    color: widget.selected ? colors.accent : colors.secondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
              ],
              SizedBox.square(
                key: ValueKey('mail-avatar-${message.uid}'),
                dimension: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MailSenderAvatar(
                      sender: message.correspondent,
                      diameter: 40,
                      senderAvatarService: widget.avatarService,
                    ),
                    if (!message.isSeen)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          key: ValueKey('mail-unread-indicator-${message.uid}'),
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.accent,
                            border: Border.all(
                              color: colors.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  mailDisplayName(message.correspondent),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    height: 1.3,
                                    fontWeight: message.isSeen
                                        ? FontWeight.w400
                                        : FontWeight.w500,
                                    color: colors.foreground,
                                  ),
                                ),
                              ),
                              if (message.hasAttachments)
                                Padding(
                                  padding: const EdgeInsets.only(left: 3),
                                  child: Icon(
                                    LucideIcons.paperclip300,
                                    size: 14,
                                    color: colors.secondary,
                                  ),
                                ),
                              if (message.isFlagged)
                                Padding(
                                  padding: const EdgeInsets.only(left: 3),
                                  child: Icon(
                                    LucideIcons.star300,
                                    size: 14,
                                    color: colors.accent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.timeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: colors.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w400,
                              color: widget.subjectColor ?? colors.foreground,
                            ),
                          ),
                        ),
                        if (widget.threadCount > 1)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '${widget.threadCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.secondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height:
                          20 * MediaQuery.textScalerOf(context).scale(14) / 14,
                      child: _previewLine(colors, preview),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      selected: widget.selectionMode ? widget.selected : null,
      child: Column(
        children: [
          ClipRect(
            child: Stack(
              children: [
                if (_offset != 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: _actionExtent,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final action in widget.swipeActions)
                              Expanded(
                                child: Material(
                                  color: action.color,
                                  child: InkWell(
                                    onTap: action.onPressed == null
                                        ? null
                                        : () {
                                            _close();
                                            action.onPressed!();
                                          },
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          action.icon,
                                          size: 22,
                                          color: action.onPressed == null
                                              ? Colors.white38
                                              : Colors.white,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          context.l10n.text(action.label),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onHorizontalDragStart: canSwipe
                      ? (_) {
                          widget.openSwipe?.value = message.identityKey;
                          setState(() => _dragging = true);
                        }
                      : null,
                  onHorizontalDragUpdate: canSwipe
                      ? (event) => setState(() {
                          _offset = (_offset + event.delta.dx).clamp(
                            -_actionExtent,
                            0,
                          );
                        })
                      : null,
                  onHorizontalDragEnd: canSwipe
                      ? (event) => setState(() {
                          _dragging = false;
                          final velocity = event.primaryVelocity ?? 0;
                          _offset =
                              velocity < -250 ||
                                  velocity < 250 && _offset < -_actionExtent / 3
                              ? -_actionExtent
                              : 0;
                        })
                      : null,
                  onHorizontalDragCancel: canSwipe
                      ? () {
                          setState(() => _dragging = false);
                          _close();
                        }
                      : null,
                  child: AnimatedContainer(
                    duration:
                        _dragging || MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(_offset, 0, 0),
                    child: row,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: separatorInset, right: 14),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
        ],
      ),
    );
  }
}
