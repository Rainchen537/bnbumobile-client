import 'bnbu_adaptive.dart';
import 'bnbu_loading.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';

/// The grouped creation surface shared with the fixed-schedule editor.
abstract final class BnbuCreationStyle {
  static Color background(BuildContext context) => context.bnbuTheme.canvas;
  static Color group(BuildContext context) => context.bnbuTheme.surface;

  static TextStyle fieldText(BuildContext context) => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: context.bnbuTheme.textPrimary,
  );

  static InputDecoration input(
    BuildContext context, {
    String? hint,
    String? errorText,
    String? helperText,
    String? suffixText,
  }) => InputDecoration(
    hintText: hint == null ? null : context.l10n.text(hint),
    hintStyle: TextStyle(color: context.bnbuTheme.textMuted, fontSize: 16),
    errorText: errorText == null ? null : context.l10n.text(errorText),
    helperText: helperText == null ? null : context.l10n.text(helperText),
    suffixText: suffixText == null ? null : context.l10n.text(suffixText),
    counterText: '',
    filled: false,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}

Future<T?> showBnbuCreationModal<T>({
  required BuildContext context,
  required BnbuAdaptiveModalBuilder builder,
  double maxWidth = 640,
  double maxHeight = 720,
  String? semanticLabel,
  Key? contentKey,
  BorderRadius? bottomSheetBorderRadius,
}) => showBnbuAdaptiveModal<T>(
  context: context,
  builder: builder,
  dialogMaxWidth: maxWidth,
  dialogMaxHeight: maxHeight,
  borderRadius: BorderRadius.circular(20),
  bottomSheetBorderRadius: bottomSheetBorderRadius,
  bottomSheetBackgroundColor: BnbuCreationStyle.background(context),
  dialogBackgroundColor: BnbuCreationStyle.background(context),
  semanticLabel: semanticLabel,
  contentKey: contentKey,
);

class BnbuCreationHeader extends StatelessWidget {
  const BnbuCreationHeader({
    super.key,
    this.preserveReferenceGeometry = false,
    this.titleFontSize,
    this.subtitleFontSize,
    required this.title,
    required this.action,
    this.onClose,
    this.closeEnabled = true,
    this.closeKey,
    this.subtitle,
  });

  final bool preserveReferenceGeometry;
  final double? titleFontSize;
  final double? subtitleFontSize;
  final String title;
  final Widget action;
  final VoidCallback? onClose;
  final bool closeEnabled;
  final Key? closeKey;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuSecondaryHeader(
      referenceScale: preserveReferenceGeometry ? 0.65 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: preserveReferenceGeometry ? 48 : 56,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      key: closeKey,
                      tooltip: context.l10n.text('关闭'),
                      onPressed: !closeEnabled
                          ? null
                          : onClose ?? () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        LucideIcons.x300,
                        size: preserveReferenceGeometry
                            ? 20
                            : BnbuHeaderMetrics.iconSize,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: BnbuText(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize:
                            titleFontSize ??
                            (preserveReferenceGeometry
                                ? 17
                                : BnbuHeaderMetrics.titleSize),
                        fontWeight: FontWeight.w500,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
                // Equal side slots keep the title at the complete surface's
                // center. A long action wraps and contributes to row height.
                SizedBox(
                  width: 84,
                  child: Align(alignment: Alignment.centerRight, child: action),
                ),
              ],
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: subtitleFontSize ?? 12,
                fontWeight: FontWeight.w400,
                color: tokens.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class BnbuCreationAction extends StatelessWidget {
  const BnbuCreationAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.fontSize = BnbuHeaderMetrics.actionSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double fontSize;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: busy ? null : onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: context.bnbuTheme.brandBlue,
      textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
    ),
    child: busy
        ? const SizedBox.square(dimension: 16, child: BnbuActivityIndicator())
        : BnbuText(label),
  );
}

/// Keeps the header outside the scrollable body so its entire surface remains
/// available for the platform bottom sheet's downward dismissal gesture.
class BnbuCreationForm extends StatelessWidget {
  const BnbuCreationForm({
    super.key,
    this.preserveReferenceGeometry = false,
    required this.title,
    required this.action,
    required this.child,
    this.onClose,
    this.closeEnabled = true,
    this.avoidKeyboard = true,
  });

  final bool preserveReferenceGeometry;
  final String title;
  final Widget action;
  final Widget child;
  final VoidCallback? onClose;
  final bool closeEnabled;
  final bool avoidKeyboard;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BnbuCreationStyle.background(context),
    child: Padding(
      padding: EdgeInsets.only(
        bottom: avoidKeyboard
            ? MediaQuery.viewInsetsOf(context).bottom.clamp(0, double.infinity)
            : 0,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BnbuCreationHeader(
                preserveReferenceGeometry: preserveReferenceGeometry,
                title: title,
                action: action,
                onClose: onClose,
                closeEnabled: closeEnabled,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BnbuCreationGroup extends StatelessWidget {
  const BnbuCreationGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BnbuCreationSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: .5,
              thickness: .5,
              indent: 16,
              color: context.bnbuTheme.border.withValues(alpha: .45),
            ),
          children[i],
        ],
      ],
    ),
  );
}

class BnbuCreationSurface extends StatelessWidget {
  const BnbuCreationSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: BnbuCreationStyle.group(context),
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// Owns text until the closing animation has removed the editor from the tree.
class BnbuTextCreationEditor extends StatefulWidget {
  const BnbuTextCreationEditor({
    super.key,
    this.preserveReferenceGeometry = false,
    required this.title,
    required this.actionLabel,
    required this.hint,
    required this.avoidKeyboard,
    this.initialText = '',
    this.fieldKey,
    this.minLines = 1,
    this.maxLines = 1,
    this.autofocus = false,
    this.keyboardType,
  });
  final bool preserveReferenceGeometry;
  final String title;
  final String actionLabel;
  final String hint;
  final String initialText;
  final Key? fieldKey;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final bool avoidKeyboard;
  final TextInputType? keyboardType;

  @override
  State<BnbuTextCreationEditor> createState() => _BnbuTextCreationEditorState();
}

class _BnbuTextCreationEditorState extends State<BnbuTextCreationEditor> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) => BnbuCreationForm(
    preserveReferenceGeometry: widget.preserveReferenceGeometry,
    title: widget.title,
    action: BnbuCreationAction(label: widget.actionLabel, onPressed: _submit),
    avoidKeyboard: widget.avoidKeyboard,
    child: BnbuCreationGroup(
      children: [
        TextField(
          key: widget.fieldKey,
          controller: _controller,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          style: BnbuCreationStyle.fieldText(context),
          decoration: BnbuCreationStyle.input(context, hint: widget.hint),
          onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
        ),
      ],
    ),
  );
}

class BnbuCreationRow extends StatelessWidget {
  const BnbuCreationRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });
  final String label;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            Expanded(
              child: BnbuText(
                label,
                style: BnbuCreationStyle.fieldText(context),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
          ],
        ),
      ),
    ),
  );
}
