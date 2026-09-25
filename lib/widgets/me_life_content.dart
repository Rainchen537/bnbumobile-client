import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/campus_landmark.dart';
import '../models/me_life_presentation.dart';
import '../services/native_actions.dart';
import '../theme/app_theme.dart';
import 'me_life_badge.dart';

/// Published facts and their evidence share one presentation across ME Life.
class LifeEvidenceDetails extends StatelessWidget {
  const LifeEvidenceDetails({
    super.key,
    required this.item,
    required this.catalog,
    this.nativeActions = const NativeActions(),
  });

  final CampusLandmark item;
  final LandmarkCatalog catalog;
  final NativeActions nativeActions;

  @override
  Widget build(BuildContext context) {
    if (item.facts.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = context.bnbuTheme;
    String text(LandmarkTranslations values) =>
        landmarkText(values, context, catalog.defaultLanguage);
    final sourceNumbers = {
      for (var i = 0; i < item.sources.length; i++) item.sources[i].id: i + 1,
    };
    final bodyStyle = TextStyle(
      fontSize: 13,
      height: 1.5,
      color: theme.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final fact in item.facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      text(fact.label),
                      if (fact.period?.isNotEmpty == true) fact.period!,
                    ].join(' · '),
                    style: bodyStyle.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SelectableText(
                    '${text(fact.value)} ${fact.sourceIds.map((id) => '[${sourceNumbers[id]}]').join(' ')}',
                    style: bodyStyle,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class LifeIconRow extends StatelessWidget {
  const LifeIconRow({
    super.key,
    required this.item,
    required this.language,
    this.scale = 1,
    this.detail = false,
  });
  final CampusLandmark item;
  final String language;
  final double scale;
  final bool detail;
  static IconData icon(String value) => switch (value) {
    'clock' => LucideIcons.clock300,
    'phone' => LucideIcons.phone300,
    'info' => LucideIcons.info300,
    'utensils' => LucideIcons.utensils300,
    'shopping-bag' => LucideIcons.shoppingBag300,
    'users' => LucideIcons.users300,
    'calendar' => LucideIcons.calendar300,
    _ => LucideIcons.mapPin300,
  };
  @override
  Widget build(BuildContext context) {
    final content = [
      for (final entry in item.iconRow)
        (
          entry: entry,
          text: landmarkText(
            switch (entry.source) {
              'location' => item.locations,
              'hours' => item.openingHours,
              _ => entry.texts,
            },
            context,
            language,
          ),
        ),
    ].where((v) => v.text.isNotEmpty).toList();
    if (content.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < content.length; i++) ...[
          if (i > 0) SizedBox(width: 10 * scale),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 2 * scale),
                  child: Icon(
                    icon(content[i].entry.icon),
                    size: (detail ? 13 : 12) * scale,
                    color: context.bnbuTheme.textSecondary,
                  ),
                ),
                SizedBox(width: 6 * scale),
                Expanded(
                  child: Text(
                    content[i].text,
                    maxLines: detail ? null : 1,
                    overflow: detail
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: (detail ? 13 : 12) * scale,
                      height: detail ? 1.4 : 1.2,
                      color: context.bnbuTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

List<Widget> lifeUnitBadges(
  BuildContext context,
  CampusLandmark item,
  LandmarkCatalog catalog, {
  bool detail = false,
  double scale = 1,
}) {
  final seen = <String>{};
  final bindings = [
    if (detail && item.tagSlots.topLeft != null) item.tagSlots.topLeft!,
    if (detail && item.tagSlots.bottomLeft != null) item.tagSlots.bottomLeft!,
    if (detail && item.tagSlots.scoreAfter != null) item.tagSlots.scoreAfter!,
    ...item.tagSlots.below,
  ];
  final result = <Widget>[];
  for (final b in bindings) {
    final tag = catalog.tag(b.tagId);
    final style = catalog.style(b.styleId);
    if (tag == null ||
        b.tagId == item.tagSlots.hidden ||
        (detail && !style.detailAllowed) ||
        !seen.add(b.tagId)) {
      continue;
    }
    result.add(
      LifeBadge(
        key: ValueKey('unit-tag-${b.tagId}'),
        text: landmarkText(tag.texts, context, catalog.defaultLanguage),
        style: style,
        scale: scale,
        truncate: false,
      ),
    );
  }
  // Plain historic tags remain readable until an operator migrates their bindings.
  if (bindings.isEmpty) {
    for (final tag in item.tags) {
      result.add(
        LifeBadge(
          text: tag,
          style: LifeStyle.fallback,
          scale: scale,
          truncate: false,
        ),
      );
    }
  }
  return result;
}

/// Layout measures actual tag widgets. Overflow tags are neither painted,
/// hit-tested nor exposed to accessibility until expanded; no partial tag clips.
class LifeTagStrip extends StatefulWidget {
  const LifeTagStrip({
    super.key,
    required this.children,
    this.expandable = false,
    this.spacing = 4,
  });
  final List<Widget> children;
  final bool expandable;
  final double spacing;
  @override
  State<LifeTagStrip> createState() => _LifeTagStripState();
}

class _LifeTagStripState extends State<LifeTagStrip> {
  bool expanded = false, hasOverflow = false;
  @override
  Widget build(BuildContext context) => _TagLayout(
    expanded: expanded,
    expandable: widget.expandable,
    spacing: widget.spacing,
    onOverflow: (value) {
      if (mounted && hasOverflow != value) setState(() => hasOverflow = value);
    },
    children: [
      ...widget.children,
      if (widget.expandable)
        SizedBox(
          width: 44,
          height: 44,
          child: hasOverflow
              ? IconButton(
                  tooltip: context.l10n.text(expanded ? '收起标签' : '展开标签'),
                  onPressed: () => setState(() => expanded = !expanded),
                  icon: Icon(
                    expanded
                        ? LucideIcons.chevronUp300
                        : LucideIcons.chevronDown300,
                    size: 17,
                  ),
                )
              : null,
        ),
    ],
  );
}

class _TagLayout extends MultiChildRenderObjectWidget {
  const _TagLayout({
    required super.children,
    required this.expanded,
    required this.expandable,
    required this.spacing,
    required this.onOverflow,
  });
  final ValueChanged<bool> onOverflow;
  final bool expanded, expandable;
  final double spacing;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _TagRender(expanded, expandable, spacing, onOverflow);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _TagRender renderObject,
  ) => renderObject.update(expanded, expandable, spacing, onOverflow);
}

class _TagParentData extends ContainerBoxParentData<RenderBox> {
  bool visible = false;
}

class _TagRender extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TagParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TagParentData> {
  _TagRender(this.expanded, this.expandable, this.spacing, this.onOverflow);
  ValueChanged<bool> onOverflow;
  bool? reportedOverflow;
  bool expanded, expandable;
  double spacing;
  void update(bool e, bool a, double s, ValueChanged<bool> callback) {
    onOverflow = callback;
    expanded = e;
    expandable = a;
    spacing = s;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TagParentData) {
      child.parentData = _TagParentData();
    }
  }

  @override
  void performLayout() {
    final all = getChildrenAsList();
    final tags = expandable ? all.take(all.length - 1).toList() : all;
    final control = expandable ? all.last : null;
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 10000.0;
    double natural = 0;
    for (final child in all) {
      (child.parentData! as _TagParentData).visible = false;
      child.layout(const BoxConstraints(), parentUsesSize: true);
    }
    for (final child in tags) {
      natural += child.size.width + (natural > 0 ? spacing : 0);
    }
    final overflow = natural > width;
    if (reportedOverflow != overflow) {
      reportedOverflow = overflow;
      WidgetsBinding.instance.addPostFrameCallback((_) => onOverflow(overflow));
    }
    double x = 0, y = 0, rowHeight = 0;
    if (expanded && overflow) {
      for (final child in all) {
        child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
        if (x > 0 && x + child.size.width > width) {
          y += rowHeight + spacing;
          x = 0;
          rowHeight = 0;
        }
        final p = child.parentData! as _TagParentData;
        p.visible = true;
        p.offset = Offset(x, y);
        x += child.size.width + spacing;
        rowHeight = rowHeight > child.size.height
            ? rowHeight
            : child.size.height;
      }
    } else {
      final available =
          width -
          (overflow && control != null ? control.size.width + spacing : 0);
      for (final child in tags) {
        if (x + child.size.width > available) break;
        final p = child.parentData! as _TagParentData;
        p.visible = true;
        p.offset = Offset(x, 0);
        x += child.size.width + spacing;
        rowHeight = rowHeight > child.size.height
            ? rowHeight
            : child.size.height;
      }
      if (overflow && control != null) {
        final p = control.parentData! as _TagParentData;
        p.visible = true;
        p.offset = Offset((width - control.size.width).clamp(0, width), 0);
        rowHeight = rowHeight > control.size.height
            ? rowHeight
            : control.size.height;
      }
      for (final child in all) {
        final p = child.parentData! as _TagParentData;
        if (p.visible) {
          p.offset = Offset(p.offset.dx, (rowHeight - child.size.height) / 2);
        }
      }
    }
    size = constraints.constrain(Size(width, y + rowHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in getChildrenAsList()) {
      final p = child.parentData! as _TagParentData;
      if (p.visible) context.paintChild(child, offset + p.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in getChildrenAsList().reversed) {
      final p = child.parentData! as _TagParentData;
      if (p.visible &&
          result.addWithPaintOffset(
            offset: p.offset,
            position: position,
            hitTest: (result, position) =>
                child.hitTest(result, position: position),
          )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final child in getChildrenAsList()) {
      if ((child.parentData! as _TagParentData).visible) visitor(child);
    }
  }
}
