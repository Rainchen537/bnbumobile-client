import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Primary navigation and home service entries from campus_ui_demo revision 03.
/// The original home date, course, and deadline surfaces use AppTheme.
class CampusReferenceTheme {
  const CampusReferenceTheme(this.brightness);

  final Brightness brightness;
  bool get isDark => brightness == Brightness.dark;

  static const navy = Color(0xFF132F4C);
  static const onNavy = Color(0xFFB9CDE0);
  BnbuThemeExtension get _tokens =>
      isDark ? BnbuThemeExtension.dark : BnbuThemeExtension.light;
  Color get canvas => _tokens.canvas;
  Color get surface => _tokens.surface;
  Color get ink => _tokens.textPrimary;
  Color get muted => _tokens.textSecondary;
  Color get line => _tokens.border;
  Color get blue => _tokens.brandBlue;
  Color get rust => isDark ? const Color(0xFFF3B591) : const Color(0xFFAC502C);
  Color get teal => isDark ? const Color(0xFF9CD5BC) : const Color(0xFF237663);
  Color get hover => _tokens.surfaceMuted;

  static CampusReferenceTheme of(BuildContext context) =>
      CampusReferenceTheme(Theme.of(context).brightness);

  TextStyle text(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.55,
    bool number = false,
    double? spacing,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? ink,
    fontFamily: number ? 'Helvetica Neue' : null,
    fontFeatures: number ? const [FontFeature.tabularFigures()] : null,
    letterSpacing: spacing ?? (number ? -size * .03 : 0),
  );
}
