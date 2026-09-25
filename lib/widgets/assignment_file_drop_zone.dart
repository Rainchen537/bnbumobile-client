import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

class AssignmentFileDropZone extends StatefulWidget {
  const AssignmentFileDropZone({
    super.key,
    required this.enabled,
    required this.onFiles,
    required this.onPickFiles,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<List<DropItem>> onFiles;
  final VoidCallback onPickFiles;
  final Widget child;

  static bool get supportsNativeDrop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  State<AssignmentFileDropZone> createState() => _AssignmentFileDropZoneState();
}

class _AssignmentFileDropZoneState extends State<AssignmentFileDropZone> {
  bool _hovering = false;

  bool get _canReceive =>
      widget.enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  void _setHover(bool value) {
    if (_hovering == value) return;
    // desktop_drop can emit an exit while being disabled during layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setHover(value && _canReceive);
      });
    } else {
      setState(() => _hovering = value);
    }
  }

  @override
  void didUpdateWidget(AssignmentFileDropZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _hovering = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_canReceive) _hovering = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!AssignmentFileDropZone.supportsNativeDrop) return widget.child;
    // Native drops bypass Flutter hit testing; inactive or covered routes must
    // not stage files. Only this persistent bar, not the whole window, listens.
    final enabled =
        widget.enabled &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    final active = enabled && _hovering;
    final colors = context.bnbuTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropTarget(
          enable: enabled,
          onDragEntered: (_) => _setHover(_canReceive),
          onDragUpdated: (_) => _setHover(_canReceive),
          onDragExited: (_) => _setHover(false),
          onDragDone: (details) {
            _setHover(false);
            if (_canReceive) widget.onFiles(details.files);
          },
          child: Semantics(
            container: true,
            button: true,
            enabled: enabled,
            liveRegion: true,
            child: AnimatedContainer(
              key: const ValueKey('assignment-file-drop-zone'),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 160),
              decoration: BoxDecoration(
                color: active ? colors.surfaceMuted : colors.surface,
                borderRadius: BorderRadius.circular(10),
                // A constant border width keeps the content geometry stable.
                border: Border.all(
                  color: active ? colors.brandBlue : colors.border,
                  width: 2,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: enabled
                      ? () {
                          if (_canReceive) widget.onPickFiles();
                        }
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  focusColor: colors.brandBlue.withValues(alpha: .14),
                  hoverColor: colors.brandBlue.withValues(alpha: .05),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.upload300,
                          size: 28,
                          color: enabled
                              ? colors.brandBlue
                              : colors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        IndexedStack(
                          index: active ? 1 : 0,
                          alignment: Alignment.center,
                          children: [
                            for (final label in ['点击选择或拖入文件', '松手上传'])
                              BnbuText(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: enabled
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        widget.child,
      ],
    );
  }
}
