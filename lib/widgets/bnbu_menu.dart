import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Inbox selection surface with native radio-group semantics and arrow keys.
class BnbuChoiceTile<T> extends StatelessWidget {
  const BnbuChoiceTile({
    super.key,
    this.controlKey,
    required this.value,
    required this.selected,
    required this.title,
    this.enabled = true,
    this.flat = false,
  });

  final Key? controlKey;
  final T value;
  final bool selected;
  final Widget title;
  final bool enabled;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Material(
      color: flat ? tokens.surface : tokens.surfaceMuted,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: flat
              ? null
              : Border(
                  bottom: BorderSide(
                    color: tokens.border.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: RadioListTile<T>(
            key: controlKey,
            value: value,
            enabled: enabled,
            selected: selected,
            minTileHeight: 48,
            minVerticalPadding: 8,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            controlAffinity: ListTileControlAffinity.trailing,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            selectedTileColor: flat
                ? Colors.transparent
                : tokens.selectedSurface,
            activeColor: tokens.brandBlue,
            title: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w400,
                color: selected ? tokens.brandBlue : tokens.textPrimary,
              ),
              child: title,
            ),
          ),
        ),
      ),
    );
  }
}

/// Multiple selections use the same surface while retaining native checkboxes.
class BnbuCheckTile extends StatelessWidget {
  const BnbuCheckTile({
    super.key,
    this.controlKey,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });
  final Key? controlKey;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Material(
      color: tokens.surfaceMuted,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: tokens.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: CheckboxListTile(
            key: controlKey,
            value: value,
            onChanged: onChanged,
            selected: value == true,
            minTileHeight: 48,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            controlAffinity: ListTileControlAffinity.trailing,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            selectedTileColor: tokens.selectedSurface,
            activeColor: tokens.brandBlue,
            title: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w400,
                color: value == true ? tokens.brandBlue : tokens.textPrimary,
              ),
              child: title,
            ),
            subtitle: subtitle == null
                ? null
                : DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: tokens.textSecondary,
                    ),
                    child: subtitle!,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Inbox-style menu surface shared by navigation, filters and commands.
/// Flutter retains route dismissal, focus traversal and keyboard selection.
class BnbuMenuButton<T> extends StatelessWidget {
  const BnbuMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onOpened,
    this.onCanceled,
    this.initialValue,
    this.child,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.padding = const EdgeInsets.all(8),
    this.menuPadding,
    this.constraints,
    this.color,
    this.surfaceTintColor,
    this.elevation,
    this.position = PopupMenuPosition.under,
    this.offset = Offset.zero,
    this.shape,
    this.style,
    this.focusNode,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final VoidCallback? onOpened;
  final VoidCallback? onCanceled;
  final T? initialValue;
  final Widget? child;
  final Widget? icon;
  final String? tooltip;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? menuPadding;
  final BoxConstraints? constraints;
  final Color? color;
  final Color? surfaceTintColor;
  final double? elevation;
  final PopupMenuPosition position;
  final Offset offset;
  final ShapeBorder? shape;
  final ButtonStyle? style;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final menu = PopupMenuButton<T>(
      initialValue: initialValue,
      onSelected: onSelected,
      onOpened: onOpened,
      onCanceled: onCanceled,
      tooltip: tooltip,
      enabled: enabled,
      padding: padding,
      menuPadding: menuPadding ?? EdgeInsets.zero,
      constraints:
          constraints ?? const BoxConstraints(minWidth: 224, maxWidth: 320),
      color: color ?? tokens.surfaceMuted,
      surfaceTintColor: surfaceTintColor ?? Colors.transparent,
      elevation: elevation ?? 8,
      position: position,
      offset: offset,
      shape:
          shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      style: style,
      icon: icon,
      itemBuilder: (context) => itemBuilder(context).map((entry) {
        if (entry is BnbuMenuItem<T> ||
            entry is! PopupMenuItem<T> ||
            (!entry.enabled && entry.height < 44)) {
          return entry;
        }
        // Complex font/color palettes keep their specialized interactive body.
        if (entry.value == null &&
            entry.child is! Text &&
            entry.child is! BnbuText) {
          return entry;
        }
        return BnbuMenuItem<T>(
          value: entry.value,
          enabled: entry.enabled,
          selected: entry is CheckedPopupMenuItem<T>
              ? entry.checked
              : initialValue != null && entry.value == initialValue,
          onTap: entry.onTap,
          child: entry.child ?? const SizedBox.shrink(),
        );
      }).toList(),
      child: child,
    );
    // PopupMenuRoute paints initialValue with Theme.highlightColor outside
    // the item. Keep its selected-item scrolling, but let our inset rounded
    // surface be the only persistent selection background. Hover, keyboard
    // focus and splash keep their independent native feedback.
    final surface = Theme(
      data: Theme.of(context).copyWith(highlightColor: Colors.transparent),
      child: menu,
    );
    return focusNode == null
        ? surface
        : Focus(focusNode: focusNode, child: surface);
  }
}

class BnbuMenuItem<T> extends PopupMenuItem<T> {
  BnbuMenuItem({
    super.key,
    super.value,
    super.enabled,
    super.onTap,
    required Widget child,
    bool selected = false,
    bool destructive = false,
    IconData? icon,
    Widget? trailing,
  }) : super(
         height: 48,
         padding: EdgeInsets.zero,
         child: Builder(
           builder: (context) {
             final tokens = context.bnbuTheme;
             final foreground = !enabled
                 ? tokens.textMuted
                 : destructive
                 ? tokens.danger
                 : selected
                 ? tokens.brandBlue
                 : tokens.textPrimary;
             return Semantics(
               selected: selected,
               child: Container(
                 decoration: BoxDecoration(
                   border: Border(
                     bottom: BorderSide(
                       width: 0.5,
                       color: tokens.border.withValues(alpha: 0.5),
                     ),
                   ),
                 ),
                 child: Container(
                   constraints: const BoxConstraints(minHeight: 40),
                   margin: const EdgeInsets.symmetric(
                     horizontal: 5,
                     vertical: 4,
                   ),
                   padding: const EdgeInsets.symmetric(
                     horizontal: 12,
                     vertical: 8,
                   ),
                   decoration: BoxDecoration(
                     color: selected ? tokens.selectedSurface : null,
                     borderRadius: BorderRadius.circular(5),
                   ),
                   child: DefaultTextStyle.merge(
                     style: TextStyle(
                       fontSize: 17,
                       height: 1.4,
                       fontWeight: FontWeight.w400,
                       color: enabled ? foreground : tokens.textMuted,
                     ),
                     child: IconTheme.merge(
                       data: IconThemeData(size: 20, color: foreground),
                       child: Row(
                         children: [
                           if (icon != null) ...[
                             Icon(icon),
                             const SizedBox(width: 11),
                           ],
                           Expanded(child: child),
                           if (trailing != null) ...[
                             const SizedBox(width: 12),
                             trailing,
                           ],
                         ],
                       ),
                     ),
                   ),
                 ),
               ),
             );
           },
         ),
       );
}

/// The same option surface inside a form, preserving FormField validation.
class BnbuDropdownFormField<T> extends FormField<T> {
  BnbuDropdownFormField({
    super.key,
    super.initialValue,
    super.validator,
    super.onSaved,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    InputDecoration decoration = const InputDecoration(),
  }) : super(
         builder: (state) {
           final matches = items.where((item) => item.value == state.value);
           return InputDecorator(
             decoration: decoration.copyWith(errorText: state.errorText),
             child: BnbuMenuButton<T>(
               initialValue: state.value,
               enabled: onChanged != null,
               onSelected: (value) {
                 state.didChange(value);
                 onChanged?.call(value);
               },
               itemBuilder: (_) => [
                 for (final item in items)
                   BnbuMenuItem<T>(
                     value: item.value,
                     enabled: item.enabled,
                     selected: item.value == state.value,
                     onTap: item.onTap,
                     child: item.child,
                   ),
               ],
               child: ConstrainedBox(
                 constraints: const BoxConstraints(minHeight: 44),
                 child: Row(
                   children: [
                     Expanded(
                       child: matches.isEmpty
                           ? const SizedBox.shrink()
                           : matches.first.child,
                     ),
                     const Icon(LucideIcons.chevronDown300, size: 20),
                   ],
                 ),
               ),
             ),
           );
         },
       );
}
