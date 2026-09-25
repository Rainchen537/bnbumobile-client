import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/root_shell_controller.dart';
import '../theme/app_theme.dart';
import '../theme/campus_reference_theme.dart';
import 'bnbu_adaptive.dart';
import 'bnbu_liquid_glass.dart';

/// Visual order is separate from AppTab.index, which is used by existing
/// controllers, page storage and deep links.
const campusNavigationTabs = [
  AppTab.home,
  AppTab.mail,
  AppTab.ispace,
  AppTab.schedule,
  AppTab.user,
];

const _destinations = {
  AppTab.home: (label: '首页', icon: LucideIcons.house300),
  AppTab.mail: (label: '邮箱', icon: LucideIcons.mail300),
  AppTab.ispace: (label: 'iSpace', icon: LucideIcons.graduationCap300),
  AppTab.schedule: (label: '课表', icon: LucideIcons.calendarDays300),
  AppTab.user: (label: '我的', icon: LucideIcons.userRound300),
};

class CampusPrimaryNavigation extends StatelessWidget {
  const CampusPrimaryNavigation({
    super.key,
    required this.wide,
    required this.selectedTab,
    required this.onSelected,
  });

  final bool wide;
  final AppTab selectedTab;
  final ValueChanged<AppTab> onSelected;

  static bool usesLiquidGlass(BuildContext context) =>
      BnbuLiquidGlassScope.isEnabled(context) &&
      !MediaQuery.highContrastOf(context);

  @override
  Widget build(BuildContext context) {
    final colors = CampusReferenceTheme.of(context);
    final buttons = [
      for (final tab in campusNavigationTabs)
        _NavigationButton(
          tab: tab,
          wide: wide,
          selected: tab == selectedTab,
          onTap: () => onSelected(tab),
        ),
    ];
    if (!wide) {
      if (usesLiquidGlass(context)) {
        return _buildLiquidGlassNavigation(context, buttons);
      }
      return Material(
        key: const ValueKey('root-bottom-navigation'),
        color: colors.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.line)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              7,
              5,
              7,
              math.max(7, MediaQuery.viewPaddingOf(context).bottom),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final button in buttons) Expanded(child: button)],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      key: const ValueKey('root-side-navigation-panel'),
      width: BnbuBreakpoints.sideNavigationWidth,
      child: Material(
        key: const ValueKey('root-side-navigation'),
        color: colors.isDark ? CampusReferenceTheme.navy : colors.surface,
        shape: Border(right: BorderSide(color: colors.line)),
        child: SafeArea(
          right: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 40,
                  child: Center(
                    child: Image.asset(
                      'assets/branding/sidebar_logo.png',
                      key: const ValueKey('root-side-navigation-brand-logo'),
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      semanticLabel: 'BNBU.ME',
                    ),
                  ),
                ),
                const SizedBox(height: 42),
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(height: 11),
                  buttons[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidGlassNavigation(
    BuildContext context,
    List<Widget> buttons,
  ) {
    final colors = CampusReferenceTheme.of(context);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return SizedBox(
        key: const ValueKey('root-ios-liquid-glass-navigation'),
        height: 64 + MediaQuery.viewPaddingOf(context).bottom,
        child: SizedBox(
          key: const ValueKey('root-bottom-navigation'),
          child: BnbuNativeLiquidGlassTabBar(
            labels: [
              for (final tab in campusNavigationTabs)
                context.l10n.text(_destinations[tab]!.label),
            ],
            iconCodePoints: [
              for (final tab in campusNavigationTabs)
                _destinations[tab]!.icon.codePoint,
            ],
            selectedIndex: campusNavigationTabs.indexOf(selectedTab),
            tintColor: colors.blue,
            onDestinationSelected: (index) =>
                onSelected(campusNavigationTabs[index]),
          ),
        ),
      );
    }

    // Non-iOS previews cannot host UIKit; use the existing glass surface while
    // retaining the same destinations, hit targets and selection semantics.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: BnbuLiquidGlassSurface(
        key: const ValueKey('root-ios-liquid-glass-navigation'),
        borderRadius: BorderRadius.circular(38),
        tintColor: colors.blue,
        interactive: false,
        child: SizedBox(
          key: const ValueKey('root-bottom-navigation'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: Row(
              children: [for (final button in buttons) Expanded(child: button)],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.tab,
    required this.wide,
    required this.selected,
    required this.onTap,
  });
  final AppTab tab;
  final bool wide;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = CampusReferenceTheme.of(context);
    final destination = _destinations[tab]!;
    final label = context.l10n.text(destination.label);
    final darkRail = wide && colors.isDark;
    final color = darkRail
        ? (selected ? Colors.white : const Color(0xFFA8BBCE))
        : (selected ? colors.blue : colors.muted);
    final prefix = wide ? 'root-side-navigation' : 'root-bottom-navigation';
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('$prefix-destination-${destination.label}'),
        color: wide && selected
            ? (darkRail
                  ? const Color(0x17FFFFFF)
                  : colors.blue.withValues(alpha: .08))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(wide ? 10 : 7),
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onTap,
          borderRadius: BorderRadius.circular(wide ? 10 : 7),
          hoverColor: darkRail ? const Color(0x0BFFFFFF) : colors.hover,
          focusColor: darkRail
              ? const Color(0x24FFFFFF)
              : colors.blue.withValues(alpha: .12),
          splashColor: Colors.transparent,
          highlightColor: color.withValues(alpha: .10),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: wide ? 62 : 52),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 3,
                vertical: wide ? 9 : 5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    destination.icon,
                    key: ValueKey('$prefix-icon-${destination.label}'),
                    size: 20,
                    color: color,
                  ),
                  SizedBox(height: wide ? 6 : 4),
                  Text(
                    label,
                    key: ValueKey('$prefix-label-${destination.label}'),
                    textAlign: TextAlign.center,
                    style: colors.text(wide ? 11 : 10, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
