import 'dart:async';

import '../widgets/bnbu_adaptive.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/official_web_target.dart';
import '../models/web_session_snapshot.dart';
import '../services/official_url_policy.dart';
import '../services/leave_application_presentation.dart';
import '../services/portal_presentation.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/native_mirror_webview.dart';
import '../widgets/bnbu_notice.dart' show BnbuToast, BnbuToastKind;
import 'web_mirror_page.dart';

enum OfficialWebPresentation { original, leaveApplication, portalLayout }

class OfficialWebPage extends StatefulWidget {
  const OfficialWebPage({
    super.key,
    required this.title,
    required this.url,
    this.controller,
    this.presentation = OfficialWebPresentation.original,
  });

  final String title;
  final String url;
  final AppSessionController? controller;
  final OfficialWebPresentation presentation;

  @override
  State<OfficialWebPage> createState() => _OfficialWebPageState();
}

class _OfficialWebPageState extends State<OfficialWebPage> {
  Future<_OfficialWebLoad>? _future;
  int _reloadSeed = 0;
  int _automaticRecoveryCount = 0;
  bool _isRecoveringAuthentication = false;
  bool _usePhoneLayout = true;
  final _webController = NativeMirrorWebViewController();
  Future<LeaveApplicationPresentation>? _leavePresentation;
  Future<PortalPresentation>? _portalPresentation;
  AppSessionLease? _pageLease;
  bool _openingLinkedPage = false;

  bool get _isLeave =>
      widget.presentation == OfficialWebPresentation.leaveApplication;

  /// The unified Portal is only reflowed when it is the page's own subject.
  /// Leave forms keep their dedicated adapter, and every other official page
  /// keeps the school's original rendering.
  bool get _usesPhoneLayout =>
      _isLeave || widget.presentation == OfficialWebPresentation.portalLayout;

  Future<void> _applyPresentation() async {
    if (!_usesPhoneLayout) return;
    final generation = _reloadSeed;
    try {
      final portal = Uri.parse(widget.url);
      final dark = Theme.of(context).brightness == Brightness.dark;
      final localizations = context.l10n;
      final source = _isLeave
          ? (await (_leavePresentation ??= LeaveApplicationPresentation.load()))
                .script(
                  portal: portal,
                  enabled: _usePhoneLayout,
                  dark: dark,
                  localizations: localizations,
                )
          : (await (_portalPresentation ??= PortalPresentation.load())).script(
              portal: portal,
              enabled: _usePhoneLayout,
              dark: dark,
              localizations: localizations,
            );
      if (!mounted || generation != _reloadSeed) return;
      await _webController.evaluateJavascript(source);
    } catch (_) {
      // Keep the original, fully usable page on unsupported pages/platforms.
      // Never log JavaScript output: the document may contain private data.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_usesPhoneLayout) unawaited(_applyPresentation());
  }

  @override
  void initState() {
    super.initState();
    _pageLease = widget.controller?.captureSessionLease();
    _future = _load();
  }

  Future<_OfficialWebLoad> _load() async {
    final uri = OfficialUrlPolicy.requireTrustedPageUrl(widget.url);
    final target = OfficialUrlPolicy.targetFor(uri);
    final WebSessionSnapshot session;
    if (target == null) {
      session = OfficialUrlPolicy.publicSessionFor(uri);
    } else {
      final controller = widget.controller;
      if (controller == null) {
        throw const FormatException('请先登录后再打开 Portal 或 MIS。');
      }
      session = await controller.prepareOfficialWebSession(target);
    }
    final initialUri = target == null
        ? uri
        : OfficialUrlPolicy.authenticatedEntryFor(target, uri);
    return _OfficialWebLoad(uri: initialUri, session: session, target: target);
  }

  Future<void> _reload({bool resetSession = false}) async {
    if (resetSession) {
      final uri = OfficialUrlPolicy.requireTrustedPageUrl(widget.url);
      final target = OfficialUrlPolicy.targetFor(uri);
      if (target != null) {
        await widget.controller?.resetOfficialWebSession(target);
      }
    }
    if (!mounted || (resetSession && !(_pageLease?.isActive ?? false))) return;
    final future = _load();
    setState(() {
      _future = future;
      _reloadSeed++;
    });
    try {
      await future;
    } catch (_) {
      // Error details are rendered by FutureBuilder.
    }
  }

  Future<void> _recoverAuthentication(String url) async {
    final target = OfficialUrlPolicy.targetFor(Uri.parse(widget.url));
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        _openingLinkedPage ||
        !(_pageLease?.isActive ?? false) ||
        target == null ||
        !OfficialUrlPolicy.isAuthenticationRedirectFor(url, target) ||
        _isRecoveringAuthentication ||
        _automaticRecoveryCount >= 2) {
      return;
    }
    _isRecoveringAuthentication = true;
    _automaticRecoveryCount++;
    try {
      await _reload(resetSession: true);
    } finally {
      _isRecoveringAuthentication = false;
    }
  }

  void _handleBlockedNavigation(String url) {
    if (_openingLinkedPage ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        !(_pageLease?.isActive ?? false)) {
      return;
    }
    final controller = widget.controller;
    if (controller == null || !controller.canOpenOfficialSchoolSession) return;
    final currentTarget = OfficialUrlPolicy.targetFor(Uri.parse(widget.url));
    final destination = OfficialUrlPolicy.schoolDestinationFor(url);
    final target = destination == null
        ? null
        : OfficialUrlPolicy.targetFor(destination);
    if (destination != null &&
        (OfficialUrlPolicy.isIspaceUrl(destination) ||
            target != currentTarget)) {
      _openingLinkedPage = true;
      final page = OfficialUrlPolicy.isIspaceUrl(destination)
          ? WebMirrorPage(
              controller: controller,
              title: 'iSpace',
              pathOrUrl: destination.toString(),
            )
          : OfficialWebPage(
              controller: controller,
              title: target == OfficialWebTarget.mis ? 'MIS' : '统一门户',
              url: destination.toString(),
            );
      unawaited(
        Navigator.of(context)
            .push<void>(MaterialPageRoute<void>(builder: (_) => page))
            .whenComplete(() {
              _openingLinkedPage = false;
            }),
      );
      return;
    }
    if (currentTarget != null &&
        OfficialUrlPolicy.isAuthenticationRedirectFor(url, currentTarget)) {
      unawaited(_recoverAuthentication(url));
      return;
    }
    BnbuToast.show(
      context,
      context.l10n.text('该链接暂不支持在应用内打开。'),
      kind: BnbuToastKind.warning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: BnbuSecondaryAppBar(
        bar: AppBar(
          title: BnbuText(widget.title),
          actions: [
            if (_usesPhoneLayout)
              IconButton(
                tooltip: context.l10n.text(_usePhoneLayout ? '查看原版' : '手机排版'),
                icon: Icon(
                  _usePhoneLayout
                      ? LucideIcons.panelsTopLeft300
                      : LucideIcons.smartphone300,
                ),
                onPressed: () {
                  setState(() => _usePhoneLayout = !_usePhoneLayout);
                  unawaited(_applyPresentation());
                },
              ),
            IconButton(
              onPressed: () {
                _automaticRecoveryCount = 0;
                _reload();
              },
              tooltip: context.l10n.text('刷新'),
              icon: const Icon(LucideIcons.refreshCw300),
            ),
          ],
        ),
      ),
      body: FutureBuilder<_OfficialWebLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(tokens.space24),
                child: const BnbuLoadingState(title: '正在加载学校页面'),
              ),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _OfficialWebError(error: snapshot.error, onRetry: _reload);
          }
          final load = snapshot.data!;
          final generation = _reloadSeed;
          return NativeMirrorWebView(
            key: ValueKey('${load.uri}#$_reloadSeed'),
            content: NativeWebContent.url(load.uri.toString()),
            controller: _usesPhoneLayout ? _webController : null,
            onPageFinished: _usesPhoneLayout
                ? () => unawaited(_applyPresentation())
                : null,
            session: load.session,
            onRetry: _reload,
            onNavigationBlocked: (url) {
              if (generation == _reloadSeed) _handleBlockedNavigation(url);
            },
            onSessionCookiesChanged: load.target == null
                ? null
                : (cookies) => widget.controller!.reconcileOfficialWebSession(
                    load.target!,
                    cookies,
                  ),
          );
        },
      ),
    );
  }
}

class _OfficialWebLoad {
  const _OfficialWebLoad({
    required this.uri,
    required this.session,
    required this.target,
  });

  final Uri uri;
  final WebSessionSnapshot session;
  final OfficialWebTarget? target;
}

class _OfficialWebError extends StatelessWidget {
  const _OfficialWebError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final message = switch (error) {
      FormatException error => error.message.toString(),
      _ => '学校页面加载失败，请检查网络后重试。',
    };
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.space24),
        child: BnbuErrorState(
          title: '学校页面加载失败',
          message: message,
          action: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw300),
            label: const BnbuText('重试'),
          ),
        ),
      ),
    );
  }
}
