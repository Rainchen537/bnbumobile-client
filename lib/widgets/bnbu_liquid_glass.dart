import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../state/app_theme_mode_controller.dart';
import '../theme/app_theme.dart';

/// Makes the persisted iPhone appearance preference available to shared
/// navigation and modal chrome without coupling feature pages to app startup.
class BnbuLiquidGlassScope extends InheritedNotifier<AppThemeModeController> {
  const BnbuLiquidGlassScope({
    super.key,
    required AppThemeModeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeModeController? maybeControllerOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BnbuLiquidGlassScope>()
        ?.notifier;
  }

  static bool isEnabled(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.iOS &&
        (maybeControllerOf(context)?.liquidGlassEnabled ?? false);
  }
}

/// A functional-layer surface for iPhone navigation and transient controls.
///
/// iOS uses the native UIKit material registered by the Runner. Widget tests
/// and non-iOS preview environments use a visually equivalent Flutter fallback.
/// The content layer deliberately remains outside this widget.
class BnbuLiquidGlassSurface extends StatelessWidget {
  const BnbuLiquidGlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tintColor,
    this.interactive = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tintColor;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    if (!BnbuLiquidGlassScope.isEnabled(context)) {
      return child;
    }

    final mediaQuery = MediaQuery.maybeOf(context);
    final highContrast = mediaQuery?.highContrast ?? false;
    final tokens = context.bnbuTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedTint = tintColor ?? tokens.brandBlue;
    final borderColor = Colors.white.withValues(alpha: isDark ? 0.24 : 0.62);
    final solidFallback = isDark
        ? const Color(0xFF142433)
        : const Color(0xFFF4F8FC);

    if (highContrast) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          key: const ValueKey('ios-liquid-glass-high-contrast-fallback'),
          decoration: BoxDecoration(
            color: solidFallback,
            borderRadius: borderRadius,
            border: Border.all(color: tokens.border),
          ),
          child: child,
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: Platform.isIOS && !kIsWeb
                ? UiKitView(
                    key: const ValueKey('ios-native-liquid-glass'),
                    viewType: 'ispace/liquid_glass',
                    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                    creationParams: <String, Object>{
                      'cornerRadius': borderRadius.topLeft.x,
                      'interactive': interactive,
                      'tintColor': resolvedTint.toARGB32(),
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  )
                : _FlutterLiquidGlassFallback(
                    tintColor: resolvedTint,
                    borderRadius: borderRadius,
                    isDark: isDark,
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(color: borderColor),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDark ? 0.08 : 0.22),
                  Colors.transparent,
                  resolvedTint.withValues(alpha: isDark ? 0.07 : 0.035),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Hosts UIKit's real `UITabBar` so iOS owns the Liquid Glass selection,
/// interaction, and transition behavior instead of approximating it in Dart.
class BnbuNativeLiquidGlassTabBar extends StatefulWidget {
  const BnbuNativeLiquidGlassTabBar({
    super.key,
    required this.labels,
    required this.iconCodePoints,
    required this.selectedIndex,
    required this.tintColor,
    required this.onDestinationSelected,
  });

  final List<String> labels;
  final List<int> iconCodePoints;
  final int selectedIndex;
  final Color tintColor;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<BnbuNativeLiquidGlassTabBar> createState() =>
      _BnbuNativeLiquidGlassTabBarState();
}

class _BnbuNativeLiquidGlassTabBarState
    extends State<BnbuNativeLiquidGlassTabBar> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant BnbuNativeLiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _syncSelectedIndex();
    }
    if (!listEquals(oldWidget.labels, widget.labels)) {
      _syncLabels();
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      key: const ValueKey('ios-native-liquid-glass-tab-bar'),
      viewType: 'ispace/native_tab_bar',
      hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      creationParams: <String, Object>{
        'labels': widget.labels,
        'iconCodePoints': widget.iconCodePoints,
        'selectedIndex': widget.selectedIndex,
        'tintColor': widget.tintColor.toARGB32(),
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _handlePlatformViewCreated,
    );
  }

  void _handlePlatformViewCreated(int viewId) {
    final channel = MethodChannel('ispace/native_tab_bar/$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeCall);
    _syncSelectedIndex();
    _syncLabels();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'selectedIndexChanged') {
      throw MissingPluginException('Unsupported native tab bar call');
    }
    final index = call.arguments;
    if (index is int &&
        index >= 0 &&
        index < widget.labels.length &&
        index != widget.selectedIndex) {
      widget.onDestinationSelected(index);
    }
  }

  void _syncSelectedIndex() {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    unawaited(
      channel.invokeMethod<void>('setSelectedIndex', widget.selectedIndex),
    );
  }

  void _syncLabels() {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    unawaited(channel.invokeMethod<void>('setLabels', widget.labels));
  }
}

class _FlutterLiquidGlassFallback extends StatelessWidget {
  const _FlutterLiquidGlassFallback({
    required this.tintColor,
    required this.borderRadius,
    required this.isDark,
  });

  final Color tintColor;
  final BorderRadius borderRadius;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        key: const ValueKey('ios-liquid-glass-flutter-fallback'),
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: ColoredBox(
          color: (isDark ? const Color(0xFF102234) : Colors.white).withValues(
            alpha: isDark ? 0.46 : 0.52,
          ),
        ),
      ),
    );
  }
}
