import 'bnbu_loading.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/web_session_snapshot.dart';
import '../services/native_actions.dart';

const _leaveSubmissionHandlerName = 'bnbuLeaveSubmission';

/// A document is data, never a URL exempted from navigation policy.
@immutable
class NativeWebContent {
  const NativeWebContent.url(this.value) : isHtml = false;
  const NativeWebContent.html(this.value) : isHtml = true;

  final String value;
  final bool isHtml;

  bool isValidFor(WebSessionSnapshot session) {
    final uri = Uri.tryParse(isHtml ? session.baseUrl : value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    return !isHtml ||
        (uri.scheme == 'https' &&
            value.trim().isNotEmpty &&
            session.allowedOrigins.any(
              (origin) => urlsHaveSameOrigin(origin, session.baseUrl),
            ));
  }

  String documentFor(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    final origin =
        uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri.origin
        : '';
    final document = html_parser.parse(value);
    // noscript is critical: package:html keeps its content as raw text, so a
    // <noscript><meta http-equiv="refresh" ...></noscript> payload escapes the
    // selectors here yet becomes live markup once the WebView parses it with
    // scripting disabled, turning a passive document into navigation. Strip
    // noscript, script and link outright; base and a meta refresh could
    // likewise navigate or re-point where relative school resources resolve.
    for (final element in document.querySelectorAll(
      'script, noscript, link, base, meta[http-equiv]',
    )) {
      if (element.localName != 'meta' ||
          element.attributes['http-equiv']?.trim().toLowerCase() == 'refresh') {
        element.remove();
      }
    }
    final policy = dom.Element.tag('meta')
      ..attributes['http-equiv'] = 'Content-Security-Policy'
      ..attributes['content'] =
          "default-src 'none'; img-src data: $origin; "
          "media-src $origin; style-src 'unsafe-inline'; font-src data:; "
          "script-src 'none'; connect-src 'none'; frame-src 'none'; "
          "form-action 'none'; base-uri 'none'";
    document.head!.nodes.insert(0, policy);
    return document.outerHtml;
  }

  @override
  bool operator ==(Object other) =>
      other is NativeWebContent &&
      other.isHtml == isHtml &&
      other.value == value;
  @override
  int get hashCode => Object.hash(isHtml, value);
}

class _NativeLeaveSubmission {
  const _NativeLeaveSubmission({required this.nonce, required this.status});

  final String nonce;
  final String status;

  static final RegExp _noncePattern = RegExp(r'^[0-9a-f]{48}$');
  static const Set<String> _allowedStatuses = <String>{
    'submission_succeeded',
    'submission_failed',
    'submission_pending',
  };

  static _NativeLeaveSubmission? tryParse(Object? raw) {
    if (raw is! Map || raw.length != 2) {
      return null;
    }
    final keys = raw.keys.toSet();
    if (keys.length != 2 ||
        !keys.contains('nonce') ||
        !keys.contains('status')) {
      return null;
    }
    final nonce = raw['nonce'];
    final status = raw['status'];
    if (nonce is! String ||
        status is! String ||
        nonce.length != 48 ||
        !_noncePattern.hasMatch(nonce) ||
        !_allowedStatuses.contains(status)) {
      return null;
    }
    return _NativeLeaveSubmission(nonce: nonce, status: status);
  }
}

class NativeMirrorWebViewController {
  MethodChannel? _channel;
  Future<void> Function()? _desktopReload;
  Future<bool> Function()? _desktopGoBack;
  Future<void> Function()? _desktopClearSiteData;
  Future<String> Function()? _desktopVisibleText;
  Future<Object?> Function(String source)? _desktopEvaluateJavascript;

  void _attach(MethodChannel channel) {
    _channel = channel;
  }

  void _detach(MethodChannel channel) {
    if (identical(_channel, channel)) {
      _channel = null;
    }
  }

  void _attachDesktop({
    required Future<void> Function() reload,
    required Future<bool> Function() goBack,
    required Future<void> Function() clearSiteData,
    required Future<String> Function() visibleText,
    required Future<Object?> Function(String source) evaluateJavascript,
  }) {
    _desktopReload = reload;
    _desktopGoBack = goBack;
    _desktopClearSiteData = clearSiteData;
    _desktopVisibleText = visibleText;
    _desktopEvaluateJavascript = evaluateJavascript;
  }

  void _detachDesktop() {
    _desktopReload = null;
    _desktopGoBack = null;
    _desktopClearSiteData = null;
    _desktopVisibleText = null;
    _desktopEvaluateJavascript = null;
  }

  Future<void> reload() async {
    final channel = _channel;
    if (channel != null) {
      await channel.invokeMethod<void>('reload');
      return;
    }
    await _desktopReload?.call();
  }

  Future<bool> goBack() async {
    final channel = _channel;
    if (channel != null) {
      return await channel.invokeMethod<bool>('goBack') ?? false;
    }
    return await _desktopGoBack?.call() ?? false;
  }

  Future<void> clearSiteData() async {
    final channel = _channel;
    if (channel != null) {
      await channel.invokeMethod<void>('clearSiteData');
      return;
    }
    await _desktopClearSiteData?.call();
  }

  Future<String> visibleText() async {
    final channel = _channel;
    Object? raw;
    if (channel != null) {
      raw = await channel.invokeMethod<Object?>('extractVisibleText');
    } else {
      raw = await _desktopVisibleText?.call();
    }
    if (raw is! String) {
      return '';
    }
    var text = raw;
    if (text.startsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) {
          text = decoded;
        }
      } catch (_) {
        // Some WebView implementations already return the decoded string.
      }
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<Object?> evaluateJavascript(String source) async {
    final channel = _channel;
    if (channel != null) {
      return channel.invokeMethod<Object?>('evaluateJavascript', source);
    }
    return _desktopEvaluateJavascript?.call(source);
  }

  Future<NativeLoginCodeActionResult> saveLoginCodeAndOpenWechat() async {
    final raw = await _channel?.invokeMethod<Object?>(
      'saveLoginCodeAndOpenWechat',
    );
    return NativeLoginCodeActionResult.tryParse(raw);
  }
}

class NativeLoginCodeActionResult {
  const NativeLoginCodeActionResult({
    required this.saved,
    required this.openedWechat,
  });

  final bool saved;
  final bool openedWechat;

  static NativeLoginCodeActionResult tryParse(Object? raw) {
    if (raw is Map) {
      return NativeLoginCodeActionResult(
        saved: raw['saved'] == true,
        openedWechat: raw['openedWechat'] == true,
      );
    }
    return const NativeLoginCodeActionResult(saved: false, openedWechat: false);
  }
}

class NativeMirrorWebView extends StatefulWidget {
  const NativeMirrorWebView({
    super.key,
    required this.content,
    required this.session,
    this.onRetry,
    this.onPageFinished,
    this.onPageFailed,
    this.onAuthenticationRequired,
    this.onSessionCookiesChanged,
    this.controller,
    this.participatesInSessionCleanup = true,
    this.persistentProfileName,
    this.observeLoginCodes = false,
    this.loginCodeObserverOrigin,
    this.observeLeaveSubmission = false,
    this.onLeaveSubmission,
    this.resourceOnlyDomains = const <String>[],
    this.upgradeInsecureResourceHosts = const <String>[],
    this.onLoginCodeDetected,
    this.onNavigationBlocked,
    this.errorTitle = '学校页面加载失败',
    this.errorMessage = '请检查网络后重新建立登录会话。',
    this.allowExternalHttpsNavigation = false,
    this.showLoadingIndicator = true,
    this.onDownloadRequested,
    this.onHtmlLinkTapped,
  });

  final NativeWebContent content;
  final ValueChanged<String>? onHtmlLinkTapped;
  final WebSessionSnapshot session;
  final VoidCallback? onRetry;

  /// Presentation-only hooks must independently guard the current document URL.
  final VoidCallback? onPageFinished;

  /// Called once after automatic recovery is exhausted, not on transient errors.
  final VoidCallback? onPageFailed;
  final VoidCallback? onAuthenticationRequired;
  final Future<void> Function(List<WebSessionCookie> cookies)?
  onSessionCookiesChanged;
  final NativeMirrorWebViewController? controller;
  final bool participatesInSessionCleanup;
  final String? persistentProfileName;
  final bool observeLoginCodes;
  final String? loginCodeObserverOrigin;
  final bool observeLeaveSubmission;
  final ValueChanged<Map<String, dynamic>>? onLeaveSubmission;
  final List<String> resourceOnlyDomains;
  final List<String> upgradeInsecureResourceHosts;
  final VoidCallback? onLoginCodeDetected;
  final ValueChanged<String>? onNavigationBlocked;
  final String errorTitle;
  final String errorMessage;
  final bool allowExternalHttpsNavigation;
  final bool showLoadingIndicator;
  final Future<void> Function(String url, String? filename, String? mimeType)?
  onDownloadRequested;

  static const String viewType = 'ispace/native_webview';

  @visibleForTesting
  static bool isDesktopAttachmentResponse(NavigationResponse navigation) {
    if (!navigation.isForMainFrame) return false;
    final response = navigation.response;
    final status = response?.statusCode ?? 200;
    if (response == null || status < 200 || status >= 300) return false;
    final headers = response.headers ?? const <String, String>{};
    final attachment = headers.entries.any(
      (entry) =>
          entry.key.toLowerCase() == 'content-disposition' &&
          entry.value.split(';').first.trim().toLowerCase() == 'attachment',
    );
    return attachment || !navigation.canShowMIMEType;
  }

  @visibleForTesting
  static bool allowsMainFrameUrl({
    required String url,
    required List<String> allowedOrigins,
    bool allowExternalHttpsNavigation = false,
  }) {
    if (allowedOrigins.any((origin) => urlsHaveSameOrigin(url, origin))) {
      return true;
    }
    if (!allowExternalHttpsNavigation) {
      return false;
    }
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  @override
  State<NativeMirrorWebView> createState() => _NativeMirrorWebViewState();
}

class _NativeMirrorWebViewState extends State<NativeMirrorWebView> {
  MethodChannel? _viewChannel;
  PlatformInAppWebViewController? _desktopController;
  late Future<void> _desktopCookiePreparation;
  bool _isLoading = true;
  bool _hasLoadedContent = false;
  bool _hasLoadError = false;
  bool _currentLoadFailed = false;
  bool _failureNotified = false;
  String? _rejectionReason;
  int _automaticRetryCount = 0;
  Timer? _loadErrorTimer;

  bool get _usesDesktopBrowser =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  void initState() {
    super.initState();
    _desktopCookiePreparation =
        _usesDesktopBrowser && widget.content.isValidFor(widget.session)
        ? _prepareDesktopCookies()
        : Future<void>.value();
  }

  @override
  void didUpdateWidget(covariant NativeMirrorWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_usesDesktopBrowser &&
        (oldWidget.content != widget.content ||
            oldWidget.session != widget.session)) {
      _automaticRetryCount = 0;
      _currentLoadFailed = false;
      _failureNotified = false;
      _hasLoadedContent = false;
      _desktopCookiePreparation = _prepareDesktopCookies();
    }
  }

  @override
  void dispose() {
    _loadErrorTimer?.cancel();
    final channel = _viewChannel;
    channel?.setMethodCallHandler(null);
    if (channel != null) {
      widget.controller?._detach(channel);
    }
    widget.controller?._detachDesktop();
    if (_usesDesktopBrowser && widget.session.useEphemeralSession) {
      unawaited(_deleteDesktopSessionCookies());
    }
    super.dispose();
  }

  void _markLoadStarted() {
    _loadErrorTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _hasLoadError = false;
      _currentLoadFailed = false;
      _failureNotified = false;
    });
  }

  void _markLoadFinished() {
    if (_currentLoadFailed || !mounted) {
      return;
    }
    _loadErrorTimer?.cancel();
    setState(() {
      _isLoading = false;
      _hasLoadedContent = true;
      _hasLoadError = false;
      _automaticRetryCount = 0;
    });
  }

  void _scheduleLoadError() {
    if (_currentLoadFailed) {
      return;
    }
    _currentLoadFailed = true;
    _loadErrorTimer?.cancel();
    if (_automaticRetryCount < 2) {
      final delay = _automaticRetryCount == 0
          ? const Duration(milliseconds: 350)
          : const Duration(milliseconds: 900);
      _automaticRetryCount++;
      _loadErrorTimer = Timer(delay, () {
        unawaited(_retryCurrentLoad());
      });
      return;
    }
    _loadErrorTimer = Timer(
      const Duration(milliseconds: 500),
      _showLoadErrorImmediately,
    );
  }

  Future<void> _retryCurrentLoad() async {
    if (!mounted) {
      return;
    }
    try {
      final channel = _viewChannel;
      if (channel != null) {
        await channel.invokeMethod<void>('reload');
        return;
      }
      final controller = _desktopController;
      if (controller != null) {
        await _reloadDesktop(controller);
        return;
      }
      _showLoadErrorImmediately();
    } catch (_) {
      _showLoadErrorImmediately();
    }
  }

  void _showLoadErrorImmediately() {
    _loadErrorTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _hasLoadError = true;
    });
    _notifyPageFailed();
  }

  void _notifyPageFailed() {
    if (!mounted || _failureNotified) return;
    _failureNotified = true;
    widget.onPageFailed?.call();
  }

  void _publishLeaveSubmission(Object? raw) {
    if (!widget.observeLeaveSubmission || !mounted) {
      return;
    }
    final receipt = _NativeLeaveSubmission.tryParse(raw);
    if (receipt != null) {
      widget.onLeaveSubmission?.call(<String, dynamic>{
        'nonce': receipt.nonce,
        'status': receipt.status,
      });
    }
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    if (!mounted) {
      return null;
    }
    switch (call.method) {
      case 'pageStarted':
        _markLoadStarted();
      case 'pageFinished':
        _markLoadFinished();
        if (!_currentLoadFailed) widget.onPageFinished?.call();
      case 'pageError':
        _scheduleLoadError();
      case 'loadRejected':
        _currentLoadFailed = true;
        final reason = call.arguments;
        _rejectionReason = reason is String ? reason : 'invalid_content';
        _showLoadErrorImmediately();
      case 'htmlLinkActivated':
        final url = call.arguments;
        if (url is String) _openHtmlLink(url);
      case 'authenticationRequired':
        widget.onAuthenticationRequired?.call();
      case 'sessionCookiesChanged':
        final rawCookies = call.arguments;
        if (rawCookies is List && widget.onSessionCookiesChanged != null) {
          final cookies = rawCookies
              .map(WebSessionCookie.tryFromMap)
              .whereType<WebSessionCookie>()
              .toList(growable: false);
          if (cookies.isNotEmpty) {
            await widget.onSessionCookiesChanged!(cookies);
          }
        }
      case 'loginCodeDetected':
        widget.onLoginCodeDetected?.call();
      case 'leaveSubmission':
        _publishLeaveSubmission(call.arguments);
      case 'navigationBlocked':
        final url = call.arguments;
        if (url is String && url.isNotEmpty) {
          widget.onNavigationBlocked?.call(url);
        }
    }
    return null;
  }

  void _handlePlatformViewCreated(int viewId) {
    final channel = MethodChannel('ispace/native_webview/$viewId');
    _viewChannel = channel;
    widget.controller?._attach(channel);
    channel.setMethodCallHandler(_handleNativeEvent);
    // Initialization can fail before the PlatformView-created callback attaches
    // the Dart handler. Read back the latched reason instead of losing it.
    unawaited(
      channel
          .invokeMethod<String>('getLoadFailure')
          .then((reason) {
            if (mounted && identical(_viewChannel, channel) && reason != null) {
              _handleNativeEvent(MethodCall('loadRejected', reason));
            }
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _prepareDesktopCookies() async {
    final manager = PlatformCookieManager(
      const PlatformCookieManagerCreationParams(),
    );
    for (final cookie in widget.session.cookies) {
      final host = cookie.domain.replaceFirst(RegExp(r'^\.'), '');
      final scheme = cookie.secure ? 'https' : 'http';
      final cookieUrl = WebUri('$scheme://$host${cookie.path}');
      await manager.setCookie(
        url: cookieUrl,
        name: cookie.name,
        value: cookie.value,
        path: cookie.path,
        domain: cookie.hostOnly ? null : cookie.domain,
        expiresDate: cookie.expiresAt?.millisecondsSinceEpoch,
        isSecure: cookie.secure,
        isHttpOnly: cookie.httpOnly,
        sameSite: _desktopSameSite(cookie.sameSite),
      );
    }
  }

  Future<void> _deleteDesktopSessionCookies() async {
    final manager = PlatformCookieManager(
      const PlatformCookieManagerCreationParams(),
    );
    for (final cookie in widget.session.cookies) {
      final host = cookie.domain.replaceFirst(RegExp(r'^\.'), '');
      final scheme = cookie.secure ? 'https' : 'http';
      await manager.deleteCookie(
        url: WebUri('$scheme://$host${cookie.path}'),
        name: cookie.name,
        path: cookie.path,
        domain: cookie.hostOnly ? null : cookie.domain,
      );
    }
  }

  Future<void> _clearDesktopSiteData() async {
    final controller = _desktopController;
    if (controller != null) {
      try {
        await controller.clearAllCache();
      } on UnimplementedError {
        // WebView2 does not currently expose the shared cache-clearing method.
        // Scoped authentication cookies are still removed below.
      }
    }
    await _deleteDesktopSessionCookies();
  }

  Future<bool> _goBackInDesktopBrowser() async {
    final controller = _desktopController;
    if (controller == null || !await controller.canGoBack()) {
      return false;
    }
    await controller.goBack();
    return true;
  }

  Future<void> _publishDesktopCookies(
    PlatformInAppWebViewController controller,
    WebUri? url,
  ) async {
    if (url == null || widget.onSessionCookiesChanged == null) {
      return;
    }
    final currentUrl = url.toString();
    if (!_isAllowedMainFrameUrl(currentUrl)) {
      return;
    }
    final cookies = await PlatformCookieManager(
      const PlatformCookieManagerCreationParams(),
    ).getCookies(url: url, webViewController: controller);
    final host = url.host.toLowerCase();
    final published = cookies
        .map((cookie) {
          final domain = (cookie.domain ?? host).trim().toLowerCase();
          final normalizedDomain = domain.replaceFirst(RegExp(r'^\.'), '');
          if (host != normalizedDomain &&
              !host.endsWith('.$normalizedDomain')) {
            return null;
          }
          final value = cookie.value;
          if (value is! String) {
            return null;
          }
          return WebSessionCookie(
            name: cookie.name,
            value: value,
            domain: domain,
            path: cookie.path ?? '/',
            hostOnly: cookie.domain == null || cookie.domain!.isEmpty,
            secure: cookie.isSecure ?? url.scheme == 'https',
            httpOnly: cookie.isHttpOnly ?? false,
            sameSite: cookie.sameSite?.toValue().toLowerCase(),
            expiresAt: cookie.expiresDate == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    cookie.expiresDate!,
                    isUtc: true,
                  ),
          );
        })
        .whereType<WebSessionCookie>()
        .toList(growable: false);
    if (published.isNotEmpty) {
      await widget.onSessionCookiesChanged!(published);
    }
  }

  bool _isAllowedMainFrameUrl(String url) {
    return NativeMirrorWebView.allowsMainFrameUrl(
      url: url,
      allowedOrigins: widget.session.allowedOrigins,
      allowExternalHttpsNavigation: widget.allowExternalHttpsNavigation,
    );
  }

  void _openHtmlLink(String url) {
    if (mounted &&
        widget.content.isHtml &&
        NativeMirrorWebView.allowsMainFrameUrl(
          url: url,
          allowedOrigins: const [],
          allowExternalHttpsNavigation: true,
        )) {
      widget.onHtmlLinkTapped?.call(url);
    }
  }

  Future<void> _reloadDesktop(PlatformInAppWebViewController controller) {
    if (!widget.content.isHtml) return controller.reload();
    return controller.loadData(
      data: widget.content.documentFor(widget.session.baseUrl),
      baseUrl: WebUri(widget.session.baseUrl),
      mimeType: 'text/html',
      encoding: 'utf-8',
    );
  }

  Widget _buildDesktopBrowser() {
    return FutureBuilder<void>(
      future: _desktopCookiePreparation,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final preparation = _desktopCookiePreparation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (identical(preparation, _desktopCookiePreparation)) {
              _notifyPageFailed();
            }
          });
          return _buildErrorPanel();
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: BnbuActivityIndicator());
        }
        return _DesktopInAppWebView(
          key: ValueKey(
            'desktop-in-app-browser-${widget.content.hashCode}-'
            '${identityHashCode(widget.session)}',
          ),
          params: PlatformInAppWebViewWidgetCreationParams(
            controllerFromPlatform: (controller) => controller,
            initialUrlRequest: widget.content.isHtml
                ? null
                : URLRequest(url: WebUri(widget.content.value)),
            initialData: widget.content.isHtml
                ? InAppWebViewInitialData(
                    data: widget.content.documentFor(widget.session.baseUrl),
                    baseUrl: WebUri(widget.session.baseUrl),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  )
                : null,
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: !widget.content.isHtml,
              domStorageEnabled: !widget.content.isHtml,
              javaScriptCanOpenWindowsAutomatically: false,
              thirdPartyCookiesEnabled: false,
              useShouldOverrideUrlLoading: true,
              // macOS upstream skips text attachments and can also emit a
              // duplicate event when navigation-response handling is enabled.
              useOnDownloadStart:
                  widget.onDownloadRequested != null &&
                  defaultTargetPlatform != TargetPlatform.macOS,
              useOnNavigationResponse:
                  widget.onDownloadRequested != null &&
                  defaultTargetPlatform == TargetPlatform.macOS,
              supportZoom: true,
              isInspectable: false,
              cacheEnabled: !widget.session.useEphemeralSession,
            ),
            onWebViewCreated: (controller) {
              final platformController =
                  controller as PlatformInAppWebViewController;
              _desktopController = platformController;
              if (!widget.content.isHtml &&
                  widget.observeLeaveSubmission &&
                  widget.onLeaveSubmission != null) {
                platformController.addJavaScriptHandler(
                  handlerName: _leaveSubmissionHandlerName,
                  callback: (arguments) {
                    // Keep the app-owned bridge name uniform and let its JS
                    // Promise resolve, but version 1.3.0+1 exposes only
                    // List<dynamic>, without origin or isMainFrame metadata.
                    // This is deliberately a sink, never a receipt channel.
                    if (arguments.length == 1) {
                      _NativeLeaveSubmission.tryParse(arguments.single);
                    }
                    return null;
                  },
                );
              }
              widget.controller?._attachDesktop(
                reload: () => _reloadDesktop(platformController),
                goBack: _goBackInDesktopBrowser,
                clearSiteData: _clearDesktopSiteData,
                visibleText: () async {
                  final raw = await platformController.evaluateJavascript(
                    source: '(document.body && document.body.innerText) || ""',
                  );
                  return raw?.toString() ?? '';
                },
                evaluateJavascript: (source) =>
                    platformController.evaluateJavascript(source: source),
              );
            },
            onLoadStart: (_, __) {
              _markLoadStarted();
            },
            onLoadStop: (controller, url) async {
              _markLoadFinished();
              if (mounted && !_currentLoadFailed) widget.onPageFinished?.call();
              await _publishDesktopCookies(
                controller as PlatformInAppWebViewController,
                url,
              );
            },
            onReceivedError: (_, request, error) {
              if (request.isForMainFrame == false ||
                  error.type == WebResourceErrorType.CANCELLED ||
                  !mounted) {
                return;
              }
              _scheduleLoadError();
            },
            onNavigationResponse: (_, navigation) async {
              if (defaultTargetPlatform == TargetPlatform.macOS &&
                  mounted &&
                  widget.onDownloadRequested != null &&
                  NativeMirrorWebView.isDesktopAttachmentResponse(navigation)) {
                final response = navigation.response!;
                final url = response.url?.toString();
                if (url == null || !_isAllowedMainFrameUrl(url)) {
                  return NavigationResponseAction.CANCEL;
                }
                _markLoadFinished();
                // Release WebKit's policy callback before downloading bytes.
                unawaited(
                  widget
                      .onDownloadRequested!(
                        url,
                        response.suggestedFilename,
                        response.mimeType,
                      )
                      .catchError((Object _) {
                        _scheduleLoadError();
                      }),
                );
                return NavigationResponseAction.CANCEL;
              }
              return NavigationResponseAction.ALLOW;
            },
            onDownloadStartRequest: (_, request) async {
              if (!mounted || widget.onDownloadRequested == null) return;
              final url = request.url.toString();
              if (!_isAllowedMainFrameUrl(url)) return;
              _markLoadFinished();
              await widget.onDownloadRequested!(
                url,
                request.suggestedFilename,
                request.mimeType,
              );
            },
            shouldOverrideUrlLoading: (_, navigationAction) async {
              if (navigationAction.isForMainFrame == false) {
                return NavigationActionPolicy.ALLOW;
              }
              final url = navigationAction.request.url?.toString();
              if (widget.content.isHtml) {
                if (url != null &&
                    (navigationAction.hasGesture == true ||
                        navigationAction.navigationType ==
                            NavigationType.LINK_ACTIVATED)) {
                  _openHtmlLink(url);
                  return NavigationActionPolicy.CANCEL;
                }
                return url == 'about:blank' ||
                        (url != null &&
                            urlsHaveSameOrigin(url, widget.session.baseUrl))
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              }
              if (url != null && _isAllowedMainFrameUrl(url)) {
                return NavigationActionPolicy.ALLOW;
              }
              if (url != null) {
                widget.onNavigationBlocked?.call(url);
              }
              return NavigationActionPolicy.CANCEL;
            },
            onCreateWindow: (controller, action) async {
              final url = action.request.url?.toString();
              if (widget.content.isHtml) {
                if (url != null &&
                    (action.hasGesture == true ||
                        action.navigationType ==
                            NavigationType.LINK_ACTIVATED)) {
                  _openHtmlLink(url);
                }
                return false;
              }
              if (mounted &&
                  url != null &&
                  (action.hasGesture == true ||
                      action.navigationType == NavigationType.LINK_ACTIVATED)) {
                if (!_isAllowedMainFrameUrl(url)) {
                  widget.onNavigationBlocked?.call(url);
                  return false;
                }
                // A clicked teacher target=_blank link stays in this controlled
                // view. Build a fresh request: never copy school headers/body.
                await (controller as PlatformInAppWebViewController).loadUrl(
                  urlRequest: URLRequest(url: WebUri(url)),
                );
              }
              return false;
            },
          ),
        );
      },
    );
  }

  Widget _buildErrorPanel({String? rejectionReason}) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.cloudOff300,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              BnbuText(widget.errorTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              BnbuText(
                switch (rejectionReason ?? _rejectionReason) {
                  'initial_url' => '页面地址无法加载。',
                  'cookie_setup' => '网页登录会话准备失败，请重试。',
                  'content_rules' => '网页内容规则初始化失败，请重试。',
                  'invalid_content' => '页面内容无法加载。',
                  _ => widget.errorMessage,
                },
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(LucideIcons.refreshCw300),
                  label: const BnbuText('重新加载'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.content.isValidFor(widget.session)) {
      return _buildErrorPanel(
        rejectionReason: widget.content.isHtml
            ? 'invalid_content'
            : 'initial_url',
      );
    }
    final creationParams = <String, dynamic>{
      'contentType': widget.content.isHtml ? 'html' : 'url',
      if (widget.content.isHtml)
        'htmlContent': widget.content.documentFor(widget.session.baseUrl)
      else
        'initialUrl': widget.content.value,
      'baseUrl': widget.session.baseUrl,
      'cookies': widget.session.cookies
          .map((cookie) => cookie.toMap())
          .toList(),
      'allowedOrigins': widget.session.allowedOrigins,
      'allowedDomains': widget.session.allowedDomains,
      'useEphemeralSession': widget.session.useEphemeralSession,
      'participatesInSessionCleanup': widget.participatesInSessionCleanup,
      if (widget.persistentProfileName != null)
        'persistentProfileName': widget.persistentProfileName,
      'observeLoginCodes': !widget.content.isHtml && widget.observeLoginCodes,
      if (widget.loginCodeObserverOrigin != null)
        'loginCodeObserverOrigin': widget.loginCodeObserverOrigin,
      if (defaultTargetPlatform == TargetPlatform.iOS)
        'observeLeaveSubmission':
            !widget.content.isHtml &&
            widget.observeLeaveSubmission &&
            widget.onLeaveSubmission != null,
      'resourceOnlyDomains': widget.resourceOnlyDomains,
      'upgradeInsecureResourceHosts': widget.upgradeInsecureResourceHosts,
      'allowExternalHttpsNavigation':
          !widget.content.isHtml && widget.allowExternalHttpsNavigation,
    };

    final Widget platformView;
    if (defaultTargetPlatform == TargetPlatform.android) {
      platformView = AndroidView(
        viewType: NativeMirrorWebView.viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _handlePlatformViewCreated,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platformView = UiKitView(
        viewType: NativeMirrorWebView.viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _handlePlatformViewCreated,
      );
    } else if (_usesDesktopBrowser) {
      platformView = _buildDesktopBrowser();
    } else {
      return _buildErrorPanel();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        platformView,
        if (widget.showLoadingIndicator && _isLoading && !_hasLoadError)
          _hasLoadedContent
              ? const Align(
                  alignment: Alignment.topCenter,
                  child: BnbuUpdateProgress(active: true),
                )
              : const Center(child: BnbuActivityIndicator()),
        if (_hasLoadError) _buildErrorPanel(),
      ],
    );
  }
}

class _DesktopInAppWebView extends StatefulWidget {
  const _DesktopInAppWebView({super.key, required this.params});

  final PlatformInAppWebViewWidgetCreationParams params;

  @override
  State<_DesktopInAppWebView> createState() => _DesktopInAppWebViewState();
}

class _DesktopInAppWebViewState extends State<_DesktopInAppWebView> {
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

HTTPCookieSameSitePolicy? _desktopSameSite(String? value) {
  return switch (value?.toLowerCase()) {
    'lax' => HTTPCookieSameSitePolicy.LAX,
    'strict' => HTTPCookieSameSitePolicy.STRICT,
    'none' => HTTPCookieSameSitePolicy.NONE,
    _ => null,
  };
}
