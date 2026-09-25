import 'package:flutter/material.dart';

/// Keeps the home service history in the content pane across window changes.
class HomeNavigationStack extends StatefulWidget {
  const HomeNavigationStack({
    super.key,
    required this.child,
    required this.active,
    required this.onCanPopChanged,
  });
  final Widget child;
  final bool active;

  /// Reports full-page depth to the root shell, excluding transient popups.
  /// System back still dismisses all routes through [NavigatorPopHandler].
  final ValueChanged<bool> onCanPopChanged;

  @override
  State<HomeNavigationStack> createState() => _HomeNavigationStackState();
}

class _HomeNavigationStackState extends State<HomeNavigationStack> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _observer = _HomeRouteObserver(_changed);
  bool _lastCanPop = false;

  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canPop = _observer.hasPageAboveRoot;
      if (canPop == _lastCanPop) return;
      _lastCanPop = canPop;
      widget.onCanPopChanged(canPop);
    });
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    enabled: widget.active,
    onPopWithResult: (result) => _navigator.currentState!.maybePop(result),
    child: Navigator(
      key: _navigator,
      observers: [_observer],
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => widget.child),
    ),
  );
}

class _HomeRouteObserver extends NavigatorObserver {
  _HomeRouteObserver(this.changed);
  final VoidCallback changed;
  final _pages = <PageRoute<dynamic>>{};
  bool get hasPageAboveRoot => _pages.length > 1;

  // A dismissible popup is not a detail page. Keep root navigation geometry
  // stable regardless of which content entry point opens the popup.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute<dynamic>) _pages.add(route);
    changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _pages.remove(oldRoute);
    if (newRoute is PageRoute<dynamic>) _pages.add(newRoute);
    changed();
  }
}

/// Marks the visible root tab without discarding inactive navigation state.
class NavigationTabScope extends InheritedWidget {
  const NavigationTabScope({
    super.key,
    required this.active,
    required super.child,
  });
  final bool active;
  static bool isActiveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NavigationTabScope>()
          ?.active ??
      true;
  @override
  bool updateShouldNotify(NavigationTabScope oldWidget) =>
      active != oldWidget.active;
}
