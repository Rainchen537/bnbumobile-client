import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

enum BnbuToastKind { success, warning, danger, info }

abstract final class BnbuToast {
  static final Map<OverlayState, _BnbuNoticeSession> _sessions = {};

  static void show(
    BuildContext context,
    String message, {
    BnbuToastKind kind = BnbuToastKind.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || message.trim().isEmpty) return;

    showInOverlay(
      overlay,
      message,
      kind: kind,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showInOverlay(
    OverlayState overlay,
    String message, {
    BnbuToastKind kind = BnbuToastKind.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (message.trim().isEmpty) return;

    _sessions.remove(overlay)?.removeImmediately();
    late final _BnbuNoticeSession session;
    final key = GlobalKey<_BnbuNoticeCardState>();
    final entry = OverlayEntry(
      builder: (overlayContext) => _BnbuNoticePositioned(
        child: _BnbuNoticeCard(
          key: key,
          message: message.trim(),
          kind: kind,
          duration: duration,
          actionLabel: actionLabel,
          onAction: onAction,
          onDismissed: () {
            if (identical(_sessions[overlay], session)) {
              _sessions.remove(overlay);
            }
            session.removeImmediately();
          },
        ),
      ),
    );
    session = _BnbuNoticeSession(entry: entry, cardKey: key);
    _sessions[overlay] = session;
    overlay.insert(entry);
  }

  static void hide(BuildContext context, {bool immediately = false}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (immediately) {
      _sessions.remove(overlay)?.removeImmediately();
    } else {
      _sessions[overlay]?.dismiss();
    }
  }
}

/// Compatibility adapter for existing app notifications while retaining the
/// familiar ScaffoldMessenger call shape at each business call site.
abstract final class ScaffoldMessenger {
  static BnbuNoticeMessenger of(BuildContext context) =>
      BnbuNoticeMessenger(context);

  static BnbuNoticeMessenger? maybeOf(BuildContext context) =>
      Overlay.maybeOf(context, rootOverlay: true) == null
      ? null
      : BnbuNoticeMessenger(context);
}

class BnbuNoticeMessenger {
  const BnbuNoticeMessenger(this.context);

  final BuildContext context;

  void hideCurrentSnackBar() => BnbuToast.hide(context);

  void showSnackBar(SnackBar snackBar) {
    final message = _plainText(snackBar.content);
    final action = snackBar.action;
    BnbuToast.show(
      context,
      message,
      kind: _kindFor(message),
      duration: snackBar.duration,
      actionLabel: action?.label,
      onAction: action?.onPressed,
    );
  }

  static String _plainText(Widget content) {
    if (content is BnbuText) {
      return content.data;
    }
    if (content is Text) {
      return content.data ?? content.textSpan?.toPlainText() ?? '';
    }
    if (content is RichText) {
      return content.text.toPlainText();
    }
    if (content is Row) {
      return content.children
          .map(_plainText)
          .where((value) => value.isNotEmpty)
          .join(' ');
    }
    if (content is Column) {
      return content.children
          .map(_plainText)
          .where((value) => value.isNotEmpty)
          .join(' ');
    }
    return '操作状态已更新';
  }

  static BnbuToastKind _kindFor(String message) {
    if (_containsAny(message, const [
      '失败',
      '错误',
      '无法',
      '不可用',
      '无效',
      '失效',
      '过期',
    ])) {
      return BnbuToastKind.danger;
    }
    if (_containsAny(message, const ['请', '需要', '暂时', '没有', '不能'])) {
      return BnbuToastKind.warning;
    }
    if (_containsAny(message, const ['已', '成功', '完成', '保存'])) {
      return BnbuToastKind.success;
    }
    return BnbuToastKind.info;
  }

  static bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);
}

class _BnbuNoticeSession {
  _BnbuNoticeSession({required this.entry, required this.cardKey});

  final OverlayEntry entry;
  final GlobalKey<_BnbuNoticeCardState> cardKey;
  bool _removed = false;

  void dismiss() => cardKey.currentState?.dismiss();

  void removeImmediately() {
    if (_removed) return;
    _removed = true;
    entry.remove();
  }
}

class _BnbuNoticePositioned extends StatelessWidget {
  const _BnbuNoticePositioned({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 600;
    return Positioned(
      top: media.padding.top + 12,
      left: compact ? 12 : null,
      right: compact ? 12 : 20,
      width: compact ? null : 360,
      child: child,
    );
  }
}

class _BnbuNoticeCard extends StatefulWidget {
  const _BnbuNoticeCard({
    super.key,
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final BnbuToastKind kind;
  final Duration duration;
  final VoidCallback onDismissed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_BnbuNoticeCard> createState() => _BnbuNoticeCardState();
}

class _BnbuNoticeCardState extends State<_BnbuNoticeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _controller = AnimationController(
      vsync: this,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      reverseDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 150),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curve;
    _offset = Tween<Offset>(
      begin: const Offset(0, -0.32),
      end: Offset.zero,
    ).animate(curve);
    _controller.forward();
    _timer = Timer(widget.duration, dismiss);
  }

  Future<void> dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final appearance = switch (widget.kind) {
      BnbuToastKind.success => (
        foreground: tokens.success,
        background: tokens.successContainer,
        icon: LucideIcons.circleCheck300,
      ),
      BnbuToastKind.warning => (
        foreground: tokens.warning,
        background: tokens.warningContainer,
        icon: LucideIcons.triangleAlert300,
      ),
      BnbuToastKind.danger => (
        foreground: tokens.danger,
        background: tokens.dangerContainer,
        icon: LucideIcons.circleAlert300,
      ),
      BnbuToastKind.info => (
        foreground: tokens.info,
        background: tokens.infoContainer,
        icon: LucideIcons.info300,
      ),
    };
    return SlideTransition(
      position: _offset,
      child: FadeTransition(
        opacity: _opacity,
        child: Semantics(
          liveRegion: true,
          label: widget.message,
          child: DecoratedBox(
            key: const ValueKey('bnbu-notice'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radius16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radius16),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(tokens.radius16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      constraints: const BoxConstraints(minHeight: 64),
                      color: appearance.foreground,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: appearance.background,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          appearance.icon,
                          size: 17,
                          color: appearance.foreground,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: ExcludeSemantics(
                          child: BnbuText(
                            widget.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.actionLabel case final label?)
                      TextButton(
                        onPressed: () {
                          widget.onAction?.call();
                          dismiss();
                        },
                        child: BnbuText(label),
                      ),
                    IconButton(
                      tooltip: context.l10n.text('关闭通知'),
                      onPressed: dismiss,
                      icon: const Icon(LucideIcons.x300, size: 16),
                    ),
                    const SizedBox(width: 4),
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
