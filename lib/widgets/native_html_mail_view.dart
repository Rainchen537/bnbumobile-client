import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/mail_html_theme.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

@visibleForTesting
NavigationActionPolicy desktopHtmlMailNavigationPolicy(
  NavigationAction action,
) {
  final isActivatedMainFrameLink =
      action.isForMainFrame &&
      action.navigationType == NavigationType.LINK_ACTIVATED;
  return isActivatedMainFrameLink
      ? NavigationActionPolicy.CANCEL
      : NavigationActionPolicy.ALLOW;
}

class NativeHtmlMailView extends StatefulWidget {
  const NativeHtmlMailView({
    super.key,
    required this.htmlContent,
    this.baseUrl,
    this.fallbackText = '',
    this.onCollapsedChanged,
    this.originalStyle = false,
  });

  static const String viewType = 'ispace/native_webview';

  final String htmlContent;
  final bool originalStyle;
  final String? baseUrl;
  final String fallbackText;
  final ValueChanged<bool>? onCollapsedChanged;

  @override
  State<NativeHtmlMailView> createState() => _NativeHtmlMailViewState();
}

class _NativeHtmlMailViewState extends State<NativeHtmlMailView> {
  MethodChannel? _viewChannel;
  final Set<int> _dragPointers = {};
  double _verticalDrag = 0;
  bool _scrolledPastHeader = false;
  bool _headerCollapsed = false;

  void _handlePointerDown(PointerDownEvent event) {
    _dragPointers.add(event.pointer);
    _verticalDrag = 0;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_dragPointers.length != 1 || !_dragPointers.contains(event.pointer)) {
      return;
    }
    final dy = event.delta.dy;
    if (dy == 0) return;
    _verticalDrag = _verticalDrag * dy < 0 ? dy : _verticalDrag + dy;
    _updateAndroidHeader();
  }

  void _handlePointerUp(PointerUpEvent event) {
    _dragPointers.remove(event.pointer);
    // Keep the direction through the fling that follows this drag.
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _dragPointers.remove(event.pointer);
    _verticalDrag = 0;
  }

  void _updateAndroidHeader() {
    if (_headerCollapsed == _scrolledPastHeader) return;
    // Resizing WebView as the sender header collapses can clamp scrollY to
    // zero. Only a deliberate reverse drag may expand it again, including
    // when the short body is already at zero and cannot emit another scroll.
    if (_scrolledPastHeader ? _verticalDrag >= -18 : _verticalDrag <= 18) {
      return;
    }
    _headerCollapsed = _scrolledPastHeader;
    widget.onCollapsedChanged?.call(_headerCollapsed);
  }

  bool get _usesDesktopBrowser =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  bool get _originalStyle => widget.originalStyle;
  (String, bool, bool)? _themeCacheKey;
  String? _themeCache;
  String _themedHtml(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final key = (widget.htmlContent, dark, _originalStyle);
    if (_themeCacheKey != key) {
      _themeCache = buildMailHtml(
        widget.htmlContent,
        dark: dark,
        original: _originalStyle,
      );
      _themeCacheKey = key;
    }
    return _themeCache!;
  }

  @override
  void dispose() {
    _viewChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _handlePlatformViewCreated(int viewId) {
    if (!mounted) return;
    _scrolledPastHeader = false;
    _verticalDrag = 0;
    _dragPointers.clear();
    _viewChannel?.setMethodCallHandler(null);
    final channel = MethodChannel(
      'ispace/native_webview/$viewId',
      const StandardMethodCodec(),
    );
    _viewChannel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'mailScrollStateChanged') return;
      final arguments = call.arguments;
      if (arguments is! Map) return;
      final collapsed = arguments['collapsed'];
      if (collapsed is bool && mounted) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          _scrolledPastHeader = collapsed;
          _updateAndroidHeader();
        } else {
          widget.onCollapsedChanged?.call(collapsed);
        }
      }
    });
  }

  Widget _buildDesktopBrowser(BuildContext context) {
    final rawBaseUrl = widget.baseUrl?.trim();
    final baseUri = rawBaseUrl == null || rawBaseUrl.isEmpty
        ? WebUri('about:blank')
        : WebUri(rawBaseUrl);
    return _DesktopHtmlWebView(
      key: ValueKey((
        Theme.of(context).brightness,
        _originalStyle,
        widget.htmlContent,
      )),
      params: PlatformInAppWebViewWidgetCreationParams(
        initialData: InAppWebViewInitialData(
          data: _themedHtml(context),
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: baseUri,
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: false,
          javaScriptCanOpenWindowsAutomatically: false,
          thirdPartyCookiesEnabled: false,
          domStorageEnabled: false,
          databaseEnabled: false,
          cacheEnabled: false,
          useShouldOverrideUrlLoading: true,
          supportZoom: true,
          isInspectable: false,
        ),
        onScrollChanged: (_, __, y) {
          widget.onCollapsedChanged?.call(y > 18);
        },
        shouldOverrideUrlLoading: (_, navigationAction) async {
          final policy = desktopHtmlMailNavigationPolicy(navigationAction);
          final uri = Uri.tryParse(
            navigationAction.request.url?.toString() ?? '',
          );
          if (policy == NavigationActionPolicy.CANCEL &&
              uri != null &&
              (uri.scheme == 'https' || uri.scheme == 'http')) {
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          }
          return policy;
        },
        onCreateWindow: (_, __) async => false,
      ),
    );
  }

  String _fallbackText() {
    if (widget.fallbackText.trim().isNotEmpty) {
      return widget.fallbackText.trim();
    }
    final withBreaks = widget.htmlContent
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</(p|div|li|tr|section|article|h[1-6])>',
            caseSensitive: false,
          ),
          '\n',
        );
    final document = html_parser.parse(withBreaks);
    for (final element in document.querySelectorAll(
      'script,style,head,title,meta,link',
    )) {
      element.remove();
    }
    return (document.body?.text ?? '')
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Widget _buildReadableFallback(BuildContext context) {
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 32),
        child: BnbuText(
          _fallbackText(),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _buildContent(context);

  Widget _buildContent(BuildContext context) {
    final creationParams = <String, dynamic>{
      'htmlContent': _themedHtml(context),
      'isMailContent': true,
      'mailDarkMode':
          !_originalStyle && Theme.of(context).brightness == Brightness.dark,
      if (widget.baseUrl != null && widget.baseUrl!.trim().isNotEmpty)
        'baseUrl': widget.baseUrl,
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: AndroidView(
          key: ValueKey(
            'mail-html-${Theme.of(context).brightness}-$_originalStyle-${widget.htmlContent.hashCode}',
          ),
          viewType: NativeHtmlMailView.viewType,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _handlePlatformViewCreated,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        key: ValueKey(
          'mail-html-${Theme.of(context).brightness}-$_originalStyle-${widget.htmlContent.hashCode}',
        ),
        viewType: NativeHtmlMailView.viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _handlePlatformViewCreated,
      );
    }
    if (_usesDesktopBrowser) {
      return _buildDesktopBrowser(context);
    }
    return _buildReadableFallback(context);
  }
}

class _DesktopHtmlWebView extends StatefulWidget {
  const _DesktopHtmlWebView({super.key, required this.params});

  final PlatformInAppWebViewWidgetCreationParams params;

  @override
  State<_DesktopHtmlWebView> createState() => _DesktopHtmlWebViewState();
}

class _DesktopHtmlWebViewState extends State<_DesktopHtmlWebView> {
  late final PlatformInAppWebViewWidget _platform = PlatformInAppWebViewWidget(
    widget.params,
  );

  @override
  Widget build(BuildContext context) => _platform.build(context);

  @override
  void dispose() {
    _platform.dispose();
    super.dispose();
  }
}
