import '../widgets/bnbu_menu.dart';
import '../widgets/bnbu_adaptive.dart';
import 'dart:async';

import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../theme/app_theme.dart';

import '../config/app_config.dart';
import '../models/web_session_snapshot.dart';
import '../services/native_actions.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/native_mirror_webview.dart';

class DuoduoCampusWallPage extends StatefulWidget {
  const DuoduoCampusWallPage({super.key});

  @override
  State<DuoduoCampusWallPage> createState() => _DuoduoCampusWallPageState();
}

class _DuoduoCampusWallPageState extends State<DuoduoCampusWallPage>
    with WidgetsBindingObserver {
  final NativeMirrorWebViewController _webController =
      NativeMirrorWebViewController();
  final NativeActions _nativeActions = const NativeActions();
  bool _loginCodeReady = false;
  bool _openingWechat = false;
  bool _openingExternalLink = false;

  String get _baseUrl => AppConfig.normalizedHttpsBaseUrl(
    AppConfig.duoduoWebBaseUrl,
    settingName: 'DUODUO_WEB_BASE_URL',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openingWechat && mounted) {
      setState(() {
        _openingWechat = false;
      });
    }
  }

  /// A blocked main-frame navigation is never silent: the WebView cancels it,
  /// so this page decides where it goes. The 朵朵 page itself keeps its own
  /// configured origin; anything else leaves to the system browser only after
  /// the user sees the exact host.
  Future<void> _handleBlockedNavigation(String url) async {
    if (!mounted ||
        _openingExternalLink ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    final baseHost = Uri.parse(_baseUrl).host;
    final isDuoduo =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (uri.host == baseHost || uri.host.endsWith('.$baseHost'));
    if (isDuoduo) {
      // Same-site but outside the configured main-frame origin: it is a
      // resource surface, not a page this view may navigate to.
      BnbuToast.show(
        context,
        context.l10n.text('该朵朵页面暂不支持在应用内打开。'),
        kind: BnbuToastKind.warning,
      );
      return;
    }
    if (uri == null ||
        host.isEmpty ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(url)) {
      BnbuToast.show(
        context,
        context.l10n.text('该链接暂不支持在应用内打开。'),
        kind: BnbuToastKind.warning,
      );
      return;
    }
    _openingExternalLink = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const BnbuText('离开朵朵校园墙？'),
          content: BnbuText('将在系统浏览器打开 $host。该页面不受 BNBU.ME 控制。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const BnbuText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const BnbuText('打开'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await _nativeActions.openExternalUrl(uri.toString());
      } catch (_) {
        if (!mounted) return;
        BnbuToast.show(
          context,
          context.l10n.text('系统无法打开这个链接。'),
          kind: BnbuToastKind.warning,
        );
      }
    } finally {
      _openingExternalLink = false;
    }
  }

  Future<bool> _handleBack() async {
    if (await _webController.goBack()) {
      return false;
    }
    return true;
  }

  Future<void> _saveCodeAndOpenWechat() async {
    if (!_loginCodeReady || _openingWechat) {
      return;
    }
    setState(() {
      _openingWechat = true;
    });
    try {
      final result = await _webController.saveLoginCodeAndOpenWechat();
      if (!mounted) {
        return;
      }
      if (!result.openedWechat) {
        setState(() {
          _openingWechat = false;
        });
        final message = result.saved
            ? '小程序码已保存到相册，但未能打开微信。'
            : '未能保存小程序码或打开微信，请重试。';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: BnbuText(message)));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: BnbuText(
            result.saved
                ? '小程序码已保存。请在微信扫一扫中选择相册，授权后返回 BNBU.ME。'
                : '微信已打开，但小程序码未能保存，请返回后重试。',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _openingWechat = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('小程序码暂时无法处理，请刷新后重试。')));
    }
  }

  Future<void> _clearLoginData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('清除朵朵登录数据？'),
        content: const BnbuText('这只会清除朵朵校园墙在本机保存的网页登录状态，不影响学校账号。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const BnbuText('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _webController.clearSiteData();
    if (!mounted) {
      return;
    }
    setState(() {
      _loginCodeReady = false;
    });
    await _webController.reload();
  }

  Future<void> _openPrivacyPolicy() async {
    await _nativeActions.openExternalUrl(AppConfig.duoduoPrivacyPolicyUrl);
  }

  @override
  Widget build(BuildContext context) {
    final session = WebSessionSnapshot(
      baseUrl: _baseUrl,
      cookies: const [],
      allowedOrigins: <String>[_baseUrl],
      allowedDomains: const <String>[],
    );
    const resourceOnlyDomains = <String>['duoduo.link', 'img.uboxs.net'];
    const upgradeInsecureResourceHosts = <String>['img.uboxs.net'];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (await _handleBack() && context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(
            title: const BnbuText('朵朵校园墙'),
            actions: [
              IconButton(
                tooltip: context.l10n.text('刷新'),
                onPressed: _webController.reload,
                icon: const Icon(LucideIcons.refreshCw300),
              ),
              BnbuMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'privacy':
                      unawaited(_openPrivacyPolicy());
                    case 'clear':
                      unawaited(_clearLoginData());
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'privacy', child: BnbuText('朵朵隐私政策')),
                  PopupMenuItem(value: 'clear', child: BnbuText('清除朵朵登录数据')),
                ],
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            NativeMirrorWebView(
              controller: _webController,
              content: NativeWebContent.url(_baseUrl),
              session: session,
              participatesInSessionCleanup: false,
              persistentProfileName: 'handsbnbu_duoduo',
              observeLoginCodes: true,
              loginCodeObserverOrigin: _baseUrl,
              resourceOnlyDomains: resourceOnlyDomains,
              upgradeInsecureResourceHosts: upgradeInsecureResourceHosts,
              onLoginCodeDetected: () {
                if (mounted && !_loginCodeReady) {
                  setState(() {
                    _loginCodeReady = true;
                  });
                }
              },
              onRetry: _webController.reload,
              onNavigationBlocked: (url) {
                unawaited(_handleBlockedNavigation(url));
              },
              errorTitle: '朵朵校园墙加载失败',
              errorMessage: '请检查网络后重新加载。',
            ),
            if (_loginCodeReady)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: Card(
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BnbuText(
                                  '微信授权登录',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 2),
                                BnbuText(
                                  '先保存小程序码并打开微信，在扫一扫中从相册识别；授权后返回即可继续登录。',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            key: const ValueKey('duoduo-save-code-open-wechat'),
                            onPressed: _openingWechat
                                ? null
                                : _saveCodeAndOpenWechat,
                            icon: _openingWechat
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: BnbuActivityIndicator(),
                                  )
                                : const Icon(LucideIcons.logIn300),
                            label: const BnbuText('保存并打开微信'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
