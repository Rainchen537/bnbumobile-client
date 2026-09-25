import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export '../l10n/bnbu_localizations.dart';

abstract final class BnbuColorTokens {
  static const brandBlue = Color(0xFF005BAC);
  static const inkBlack = Color(0xFF0B1119);

  static const lightCanvas = Color(0xFFF3F5F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceMuted = Color(0xFFEDF0F3);
  static const lightBorder = Color(0xFFDCE2E8);
  static const lightTextPrimary = Color(0xFF172735);
  static const lightTextSecondary = Color(0xFF5E6C7B);
  static const lightTextMuted = Color(0xFF637080);
  static const lightSearchFocus = Color(0xFF737373);
  static const darkSearchFocus = Color(0xFF9B9B9B);

  static const darkCanvas = Color(0xFF14171B);
  static const darkSurface = Color(0xFF1D2228);
  static const darkSurfaceMuted = Color(0xFF272D35);
  static const darkBorder = Color(0xFF39424C);
  static const darkTextPrimary = Color(0xFFEEF2F6);
  static const darkTextSecondary = Color(0xFFB4BFCC);
  static const darkTextMuted = Color(0xFF9EACBB);

  static const success = Color(0xFF147D4C);
  static const successContainer = Color(0xFFE4F6ED);
  static const warning = Color(0xFF9A6400);
  static const warningContainer = Color(0xFFFFF3D1);
  static const danger = Color(0xFFC62828);
  static const dangerContainer = Color(0xFFFFE3E3);
  static const info = Color(0xFF006B8F);
  static const infoContainer = Color(0xFFE0F5FC);

  static const darkSuccessContainer = Color(0xFF123728);
  static const darkWarningContainer = Color(0xFF3D2C0B);
  static const darkDangerContainer = Color(0xFF3F1718);
  static const darkInfoContainer = Color(0xFF102F3C);
}

abstract final class BnbuSpacingTokens {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class BnbuRadiusTokens {
  static const sm = 10.0;
  static const md = 12.0;
  static const lg = 20.0;
}

abstract final class BnbuSizeTokens {
  static const minInteractive = 48.0;
  static const compactTile = 72.0;
}

abstract final class BnbuTypographyTokens {
  static TextTheme textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      displaySmall: TextStyle(
        color: textPrimary,
        fontSize: 26,
        height: 1.16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineSmall: TextStyle(
        color: textPrimary,
        fontSize: 22,
        height: 1.18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        color: textPrimary,
        fontSize: 20,
        height: 1.22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleMedium: TextStyle(
        color: textPrimary,
        fontSize: 16,
        height: 1.28,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: textPrimary,
        fontSize: 15,
        height: 1.32,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: textPrimary,
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: textSecondary,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: textSecondary,
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        color: textPrimary,
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        color: textPrimary,
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        color: textSecondary,
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
  }
}

@immutable
class BnbuThemeExtension extends ThemeExtension<BnbuThemeExtension> {
  const BnbuThemeExtension({
    required this.brandBlue,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.info,
    required this.infoContainer,
    required this.space4,
    required this.space8,
    required this.space12,
    required this.space16,
    required this.space24,
    required this.space32,
    required this.radius12,
    required this.radius16,
    required this.radius24,
    required this.minInteractiveDimension,
  });

  static const light = BnbuThemeExtension(
    brandBlue: BnbuColorTokens.brandBlue,
    canvas: BnbuColorTokens.lightCanvas,
    surface: BnbuColorTokens.lightSurface,
    surfaceMuted: BnbuColorTokens.lightSurfaceMuted,
    border: BnbuColorTokens.lightBorder,
    textPrimary: BnbuColorTokens.lightTextPrimary,
    textSecondary: BnbuColorTokens.lightTextSecondary,
    textMuted: BnbuColorTokens.lightTextMuted,
    success: BnbuColorTokens.success,
    successContainer: BnbuColorTokens.successContainer,
    warning: BnbuColorTokens.warning,
    warningContainer: BnbuColorTokens.warningContainer,
    danger: BnbuColorTokens.danger,
    dangerContainer: BnbuColorTokens.dangerContainer,
    info: BnbuColorTokens.info,
    infoContainer: BnbuColorTokens.infoContainer,
    space4: BnbuSpacingTokens.xxs,
    space8: BnbuSpacingTokens.xs,
    space12: BnbuSpacingTokens.sm,
    space16: BnbuSpacingTokens.md,
    space24: BnbuSpacingTokens.lg,
    space32: BnbuSpacingTokens.xl,
    radius12: BnbuRadiusTokens.sm,
    radius16: BnbuRadiusTokens.md,
    radius24: BnbuRadiusTokens.lg,
    minInteractiveDimension: BnbuSizeTokens.minInteractive,
  );

  static const dark = BnbuThemeExtension(
    brandBlue: Color(0xFF78B6F5),
    canvas: BnbuColorTokens.darkCanvas,
    surface: BnbuColorTokens.darkSurface,
    surfaceMuted: BnbuColorTokens.darkSurfaceMuted,
    border: BnbuColorTokens.darkBorder,
    textPrimary: BnbuColorTokens.darkTextPrimary,
    textSecondary: BnbuColorTokens.darkTextSecondary,
    textMuted: BnbuColorTokens.darkTextMuted,
    success: BnbuColorTokens.success,
    successContainer: BnbuColorTokens.darkSuccessContainer,
    warning: BnbuColorTokens.warning,
    warningContainer: BnbuColorTokens.darkWarningContainer,
    danger: BnbuColorTokens.danger,
    dangerContainer: BnbuColorTokens.darkDangerContainer,
    info: BnbuColorTokens.info,
    infoContainer: BnbuColorTokens.darkInfoContainer,
    space4: BnbuSpacingTokens.xxs,
    space8: BnbuSpacingTokens.xs,
    space12: BnbuSpacingTokens.sm,
    space16: BnbuSpacingTokens.md,
    space24: BnbuSpacingTokens.lg,
    space32: BnbuSpacingTokens.xl,
    radius12: BnbuRadiusTokens.sm,
    radius16: BnbuRadiusTokens.md,
    radius24: BnbuRadiusTokens.lg,
    minInteractiveDimension: BnbuSizeTokens.minInteractive,
  );

  Color get selectedSurface =>
      Color.alphaBlend(brandBlue.withValues(alpha: 0.12), surface);

  final Color brandBlue;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color info;
  final Color infoContainer;
  final double space4;
  final double space8;
  final double space12;
  final double space16;
  final double space24;
  final double space32;
  final double radius12;
  final double radius16;
  final double radius24;
  final double minInteractiveDimension;

  @override
  BnbuThemeExtension copyWith({
    Color? brandBlue,
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? info,
    Color? infoContainer,
    double? space4,
    double? space8,
    double? space12,
    double? space16,
    double? space24,
    double? space32,
    double? radius12,
    double? radius16,
    double? radius24,
    double? minInteractiveDimension,
  }) {
    return BnbuThemeExtension(
      brandBlue: brandBlue ?? this.brandBlue,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      space4: space4 ?? this.space4,
      space8: space8 ?? this.space8,
      space12: space12 ?? this.space12,
      space16: space16 ?? this.space16,
      space24: space24 ?? this.space24,
      space32: space32 ?? this.space32,
      radius12: radius12 ?? this.radius12,
      radius16: radius16 ?? this.radius16,
      radius24: radius24 ?? this.radius24,
      minInteractiveDimension:
          minInteractiveDimension ?? this.minInteractiveDimension,
    );
  }

  @override
  BnbuThemeExtension lerp(
    covariant ThemeExtension<BnbuThemeExtension>? other,
    double t,
  ) {
    if (other is! BnbuThemeExtension) {
      return this;
    }
    return BnbuThemeExtension(
      brandBlue: Color.lerp(brandBlue, other.brandBlue, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      space4: ui.lerpDouble(space4, other.space4, t)!,
      space8: ui.lerpDouble(space8, other.space8, t)!,
      space12: ui.lerpDouble(space12, other.space12, t)!,
      space16: ui.lerpDouble(space16, other.space16, t)!,
      space24: ui.lerpDouble(space24, other.space24, t)!,
      space32: ui.lerpDouble(space32, other.space32, t)!,
      radius12: ui.lerpDouble(radius12, other.radius12, t)!,
      radius16: ui.lerpDouble(radius16, other.radius16, t)!,
      radius24: ui.lerpDouble(radius24, other.radius24, t)!,
      minInteractiveDimension: ui.lerpDouble(
        minInteractiveDimension,
        other.minInteractiveDimension,
        t,
      )!,
    );
  }
}

extension BnbuThemeContext on BuildContext {
  BnbuThemeExtension get bnbuTheme {
    return Theme.of(this).extension<BnbuThemeExtension>() ??
        BnbuThemeExtension.light;
  }
}

class AppTheme {
  const AppTheme._();

  static SystemUiOverlayStyle statusBarStyle(Brightness brightness) =>
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: brightness,
        statusBarIconBrightness: brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
      );

  static ThemeData get light =>
      _build(Brightness.light, BnbuThemeExtension.light);

  static ThemeData get dark => _build(Brightness.dark, BnbuThemeExtension.dark);

  static BnbuThemeExtension monochromeTokens(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return (dark ? BnbuThemeExtension.dark : BnbuThemeExtension.light).copyWith(
      brandBlue: dark ? const Color(0xFFF2F2ED) : const Color(0xFF171715),
      canvas: dark ? const Color(0xFF10100E) : const Color(0xFFF4F4F1),
      surface: dark ? const Color(0xFF191917) : Colors.white,
      surfaceMuted: dark ? const Color(0xFF252522) : const Color(0xFFECECE8),
      border: dark ? const Color(0xFF3B3B36) : const Color(0xFFD2D2CC),
      textPrimary: dark ? const Color(0xFFF3F3EF) : const Color(0xFF171715),
      textSecondary: dark ? const Color(0xFFB7B7AF) : const Color(0xFF60605B),
      textMuted: dark ? const Color(0xFF91918A) : const Color(0xFF797973),
      info: dark ? const Color(0xFFF3F3EF) : const Color(0xFF171715),
      infoContainer: dark ? const Color(0xFF30302C) : const Color(0xFFE5E5E0),
    );
  }

  /// Pure black and white tokens reserved for the 小U conversation surface.
  /// Other uses of the established monochrome theme keep their existing tone.
  static BnbuThemeExtension assistantMonochromeTokens(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return (dark ? BnbuThemeExtension.dark : BnbuThemeExtension.light).copyWith(
      brandBlue: dark ? Colors.white : Colors.black,
      canvas: dark ? Colors.black : Colors.white,
      surface: dark ? Colors.black : Colors.white,
      surfaceMuted: dark ? const Color(0xFF1C1C1C) : const Color(0xFFF2F2F2),
      border: dark ? const Color(0xFF383838) : const Color(0xFFD9D9D9),
      textPrimary: dark ? Colors.white : Colors.black,
      textSecondary: dark ? const Color(0xFFC8C8C8) : const Color(0xFF4D4D4D),
      textMuted: dark ? const Color(0xFF9B9B9B) : const Color(0xFF737373),
      info: dark ? Colors.white : Colors.black,
      infoContainer: dark ? const Color(0xFF292929) : const Color(0xFFEAEAEA),
    );
  }

  static ThemeData monochrome(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tokens = monochromeTokens(brightness);
    return _build(brightness, tokens).copyWith(
      colorScheme: _build(brightness, tokens).colorScheme.copyWith(
        primary: tokens.brandBlue,
        onPrimary: dark ? const Color(0xFF171715) : Colors.white,
        secondary: tokens.textSecondary,
        surface: tokens.surface,
        onSurface: tokens.textPrimary,
      ),
    );
  }

  static ThemeData assistantMonochrome(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tokens = assistantMonochromeTokens(brightness);
    return _build(brightness, tokens).copyWith(
      colorScheme: _build(brightness, tokens).colorScheme.copyWith(
        primary: tokens.brandBlue,
        onPrimary: dark ? Colors.black : Colors.white,
        secondary: tokens.textSecondary,
        surface: tokens.surface,
        onSurface: tokens.textPrimary,
      ),
    );
  }

  static ThemeData _build(Brightness brightness, BnbuThemeExtension tokens) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: BnbuColorTokens.brandBlue,
          brightness: brightness,
        ).copyWith(
          primary: tokens.brandBlue,
          onPrimary: brightness == Brightness.dark
              ? tokens.canvas
              : Colors.white,
          surface: tokens.surface,
          onSurface: tokens.textPrimary,
          error: tokens.danger,
          onError: Colors.white,
          errorContainer: tokens.dangerContainer,
          outline: tokens.border,
        );
    final textTheme = BnbuTypographyTokens.textTheme(
      tokens.textPrimary,
      tokens.textSecondary,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radius16),
    );
    final compactButtonSize = WidgetStatePropertyAll<Size>(
      Size.square(tokens.minInteractiveDimension),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      dividerTheme: DividerThemeData(color: tokens.border, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius16),
          side: BorderSide(color: tokens.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        barrierColor: Colors.black.withValues(alpha: 0.52),
        insetPadding: EdgeInsets.all(tokens.space24),
        actionsPadding: EdgeInsets.fromLTRB(
          tokens.space16,
          0,
          tokens.space16,
          tokens.space16,
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius24),
          side: BorderSide(color: tokens.border),
        ),
      ),
      iconTheme: IconThemeData(color: tokens.textPrimary, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: compactButtonSize,
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: WidgetStatePropertyAll(buttonShape),
          foregroundColor: WidgetStatePropertyAll(tokens.textPrimary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size.square(tokens.minInteractiveDimension),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: Size.square(tokens.minInteractiveDimension),
          elevation: 0,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size.square(tokens.minInteractiveDimension),
          side: BorderSide(color: tokens.border),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size.square(tokens.minInteractiveDimension),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface,
        labelStyle: textTheme.labelLarge?.copyWith(color: tokens.textSecondary),
        floatingLabelStyle: textTheme.labelLarge?.copyWith(
          color: tokens.brandBlue,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: tokens.danger,
          fontWeight: FontWeight.w700,
        ),
        prefixIconColor: tokens.textMuted,
        suffixIconColor: tokens.textMuted,
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.space16,
          vertical: tokens.space12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius16),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius16),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius16),
          borderSide: BorderSide(color: tokens.brandBlue, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? tokens.brandBlue : tokens.textMuted,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? tokens.brandBlue : tokens.textMuted,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.surface,
        indicatorColor: tokens.infoContainer,
        useIndicator: true,
        elevation: 0,
        selectedIconTheme: IconThemeData(color: tokens.brandBlue, size: 23),
        unselectedIconTheme: IconThemeData(color: tokens.textMuted, size: 23),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: tokens.brandBlue,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(7),
        radius: const Radius.circular(999),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered)
              ? tokens.textMuted.withValues(alpha: 0.62)
              : tokens.textMuted.withValues(alpha: 0.34);
        }),
      ),
    );
  }
}

/// CSS for App-generated iSpace descriptions; original website styles stay intact.
extension BnbuCssColor on Color {
  String get cssRgb =>
      '#${(toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Gives routes without an AppBar a status-bar owner after another route pops.
class BnbuSystemUiScope extends StatelessWidget {
  const BnbuSystemUiScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: AppTheme.statusBarStyle(Theme.of(context).brightness),
    child: child,
  );
}
