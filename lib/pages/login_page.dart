import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../config/app_config.dart';
import '../services/login_input_source_controller.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/statistics_privacy_notice.dart';
import 'official_web_page.dart';

const _loginBlue = Color(0xFF0167A4);

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.controller,
    this.inputSourceController = const LoginInputSourceController(),
  });

  final AppSessionController controller;
  final LoginInputSourceController inputSourceController;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  static final _asciiUsernameFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[\x20-\x7E]'),
  );

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _englishInputSourceActive = false;
  bool _acceptedPrivacyPolicy = false;
  bool _loginInProgress = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usernameController.addListener(_clearError);
    _passwordController.addListener(_clearError);
    _usernameFocusNode.addListener(_handleCredentialFocusChange);
    _passwordFocusNode.addListener(_handleCredentialFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameFocusNode.removeListener(_handleCredentialFocusChange);
    _passwordFocusNode.removeListener(_handleCredentialFocusChange);
    if (_englishInputSourceActive) {
      unawaited(widget.inputSourceController.restorePreviousKeyboard());
    }
    _usernameController.removeListener(_clearError);
    _passwordController.removeListener(_clearError);
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleCredentialFocusChange();
      return;
    }
    if (_englishInputSourceActive) {
      _englishInputSourceActive = false;
      unawaited(widget.inputSourceController.restorePreviousKeyboard());
    }
  }

  void _handleCredentialFocusChange() {
    final hasCredentialFocus =
        _usernameFocusNode.hasFocus || _passwordFocusNode.hasFocus;
    if (hasCredentialFocus) {
      if (_englishInputSourceActive) {
        return;
      }
      _englishInputSourceActive = true;
      unawaited(widget.inputSourceController.activateEnglishKeyboard());
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _usernameFocusNode.hasFocus ||
          _passwordFocusNode.hasFocus ||
          !_englishInputSourceActive) {
        return;
      }
      _englishInputSourceActive = false;
      unawaited(widget.inputSourceController.restorePreviousKeyboard());
    });
  }

  void _clearError() {
    if (widget.controller.error != null) {
      widget.controller.clearError();
    }
  }

  Future<void> _handleLogin() async {
    if (_loginInProgress || widget.controller.isBusy) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _loginInProgress = true);
    FocusScope.of(context).unfocus();
    try {
      if (!_acceptedPrivacyPolicy) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: const ValueKey('login-privacy-consent-dialog'),
            title: const BnbuText('隐私政策'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BnbuText('是否同意隐私政策并继续登录？'),
                  if (widget.controller.statistics.supported) ...[
                    const SizedBox(height: 12),
                    const BnbuText(statisticsLoginSummary),
                    const SizedBox(height: 12),
                    const BnbuText(statisticsPrivacyText),
                  ],
                  TextButton(
                    key: const ValueKey('login-dialog-privacy-policy-link'),
                    onPressed: _openPrivacyPolicy,
                    child: const BnbuText('阅读隐私政策'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const BnbuText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const BnbuText('同意并登录'),
              ),
            ],
          ),
        );
        if (!mounted || accepted != true) return;
        setState(() => _acceptedPrivacyPolicy = true);
      }
      if (!mounted || widget.controller.isBusy) return;
      // The visible login notice covers this purpose. Record no events before auth.
      // Persistence failure must not prevent school login; the restored-login gate
      // will ask again while collection remains disabled.
      try {
        await widget.controller.statistics.acceptLoginPrivacy(
          _usernameController.text.trim(),
        );
      } catch (_) {
        /* Fail closed for statistics, not for school authentication. */
      }
      if (!mounted || widget.controller.isBusy) return;
      await widget.controller.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
    } finally {
      if (mounted) setState(() => _loginInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        final busy = widget.controller.isBusy || _loginInProgress;
        final restoring =
            widget.controller.isRestoringSession &&
            !widget.controller.isLoggedIn;

        return Scaffold(
          backgroundColor: tokens.canvas,
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (constraints.maxWidth >= 900 &&
                      constraints.maxHeight >= 600)
                    _buildWideLayout(
                      context,
                      constraints: constraints,
                      bottomInset: bottomInset,
                      busy: busy,
                    )
                  else
                    _buildCompactLayout(
                      context,
                      constraints: constraints,
                      bottomInset: bottomInset,
                      busy: busy,
                    ),
                  if (restoring) const _RestoreOverlay(),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCompactLayout(
    BuildContext context, {
    required BoxConstraints constraints,
    required double bottomInset,
    required bool busy,
  }) {
    final tokens = context.bnbuTheme;
    final heroHeight = (constraints.maxHeight * 0.31)
        .clamp(200.0, 280.0)
        .toDouble();
    final bottomPadding = MediaQuery.paddingOf(context).bottom + tokens.space16;
    return Stack(
      children: [
        _LoginHero(height: heroHeight),
        SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - bottomInset),
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  SizedBox(height: heroHeight - tokens.space24),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        tokens.space16,
                        tokens.space32,
                        tokens.space16,
                        bottomPadding,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.canvas,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(tokens.radius24),
                          topRight: Radius.circular(tokens.radius24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildForm(context, busy: busy),
                          SizedBox(height: tokens.space24),
                          const Spacer(),
                          _buildFooterNote(context),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout(
    BuildContext context, {
    required BoxConstraints constraints,
    required double bottomInset,
    required bool busy,
  }) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('login-wide-layout'),
      children: [
        Expanded(
          flex: 11,
          child: ClipRect(child: _LoginHero(height: constraints.maxHeight)),
        ),
        Expanded(
          flex: 9,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, panelConstraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    tokens.space32,
                    tokens.space32,
                    tokens.space32,
                    bottomInset + tokens.space16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0,
                        panelConstraints.maxHeight -
                            bottomInset -
                            tokens.space32 -
                            tokens.space16,
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 480,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    BnbuText(
                                      '连接你的校园生活',
                                      style: theme.textTheme.displaySmall
                                          ?.copyWith(
                                            color: tokens.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.8,
                                          ),
                                    ),
                                    SizedBox(height: tokens.space32),
                                    _buildForm(context, busy: busy),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: tokens.space24),
                          _buildFooterNote(context),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context, {required bool busy}) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final error = widget.controller.error;

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _usernameController,
              focusNode: _usernameFocusNode,
              enabled: !busy,
              autofillHints: const [AutofillHints.username],
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              inputFormatters: [_asciiUsernameFormatter],
              textInputAction: TextInputAction.next,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                labelStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: tokens.textSecondary,
                ),
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: tokens.textMuted,
                ),
                labelText: context.l10n.text('User Id'),
                hintText: context.l10n.text('Enter your BNBU account'),
                prefixIcon: const Icon(LucideIcons.userRound200),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.l10n.text('Please enter your user ID');
                }
                return null;
              },
            ),
            SizedBox(height: tokens.space16),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              enabled: !busy,
              autofillHints: const [AutofillHints.password],
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onFieldSubmitted: (_) => _handleLogin(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                labelStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: tokens.textSecondary,
                ),
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: tokens.textMuted,
                ),
                labelText: context.l10n.text('Password'),
                hintText: context.l10n.text('Enter your iSpace password'),
                prefixIcon: const Icon(LucideIcons.lockKeyhole200),
                suffixIcon: IconButton(
                  key: const ValueKey('login-password-visibility-toggle'),
                  tooltip: context.l10n.text(
                    _obscurePassword ? '显示密码' : '隐藏密码',
                  ),
                  onPressed: busy
                      ? null
                      : () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                  icon: Icon(
                    _obscurePassword
                        ? LucideIcons.eye200
                        : LucideIcons.eyeOff200,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.l10n.text('Please enter your password');
                }
                return null;
              },
            ),
            if (error != null) ...[
              SizedBox(height: tokens.space16),
              BnbuNotice(
                message: error,
                kind: BnbuStatusKind.danger,
                icon: LucideIcons.circleAlert300,
              ),
            ],
            SizedBox(height: tokens.space24),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _loginBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy ? null : _handleLogin,
                child: widget.controller.isLoggingIn
                    ? SizedBox.square(
                        dimension: 22,
                        child: BnbuActivityIndicator(color: Colors.white),
                      )
                    : const BnbuText(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
              ),
            ),
            SizedBox(height: tokens.space8),
            if (widget.controller.statistics.supported) ...[
              const BnbuText(statisticsLoginSummary),
              TextButton(
                key: const ValueKey('login-statistics-policy-link'),
                onPressed: busy
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const BnbuText('使用与提醒统计'),
                          content: const SingleChildScrollView(
                            child: BnbuText(statisticsPrivacyText),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const BnbuText('知道了'),
                            ),
                          ],
                        ),
                      ),
                child: const BnbuText('统计隐私说明'),
              ),
            ],
            _PrivacyConsentRow(
              accepted: _acceptedPrivacyPolicy,
              enabled: !busy,
              onChanged: (value) {
                setState(() {
                  _acceptedPrivacyPolicy = value ?? false;
                });
              },
              onOpenPrivacyPolicy: _openPrivacyPolicy,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPrivacyPolicy() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const OfficialWebPage(
          title: '隐私政策',
          url: AppConfig.privacyPolicyUrl,
        ),
      ),
    );
  }

  Widget _buildFooterNote(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space8),
      key: const ValueKey('login-footer-note'),
      child: BnbuText(
        '非官方客户端',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(height: 1.5, color: tokens.textMuted),
      ),
    );
  }
}

class _PrivacyConsentRow extends StatelessWidget {
  const _PrivacyConsentRow({
    required this.accepted,
    required this.enabled,
    required this.onChanged,
    required this.onOpenPrivacyPolicy,
  });

  final bool accepted;
  final bool enabled;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onOpenPrivacyPolicy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: tokens.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MergeSemantics(
          child: InkWell(
            key: const ValueKey('login-privacy-consent-toggle'),
            onTap: enabled ? () => onChanged(!accepted) : null,
            canRequestFocus: false,
            excludeFromSemantics: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: tokens.minInteractiveDimension,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    key: const ValueKey('login-privacy-checkbox-visual'),
                    dimension: Checkbox.width * 0.9,
                    child: Transform.scale(
                      scale: 0.9,
                      child: Checkbox(
                        value: accepted,
                        onChanged: enabled ? onChanged : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: tokens.textMuted, width: 1.2),
                        semanticLabel: context.l10n.text('接受隐私政策'),
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.space8),
                  Flexible(child: BnbuText('我已阅读并接受 ', style: textStyle)),
                ],
              ),
            ),
          ),
        ),
        Semantics(
          key: const ValueKey('login-privacy-policy-link'),
          link: true,
          enabled: enabled,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: tokens.minInteractiveDimension,
              minHeight: tokens.minInteractiveDimension,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? onOpenPrivacyPolicy : null,
                borderRadius: BorderRadius.circular(tokens.radius12),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: tokens.space4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: BnbuText(
                      '隐私政策',
                      style: textStyle?.copyWith(
                        color: tokens.brandBlue,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.underline,
                        decorationColor: tokens.brandBlue,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            isDark
                ? 'assets/branding/new2.jpg'
                : 'assets/branding/login_hero_light.jpg',
            key: const ValueKey('login-hero-image'),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isDark
                      ? Colors.black.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.75),
                  isDark
                      ? Colors.black.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.50),
                  isDark
                      ? Colors.black.withValues(alpha: 0.30)
                      : Colors.transparent,
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment(0, isDark ? -0.58 : -0.86),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      ExcludeSemantics(
                        child: Transform.translate(
                          offset: const Offset(0, 4),
                          child: ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: 4,
                              sigmaY: 4,
                            ),
                            child: SvgPicture.asset(
                              'assets/branding/bnbu.svg',
                              height: 80,
                              fit: BoxFit.contain,
                              colorFilter: ColorFilter.mode(
                                Colors.black.withValues(alpha: 0.28),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SvgPicture.asset(
                        'assets/branding/bnbu.svg',
                        key: const ValueKey('login-brand-logo'),
                        height: 80,
                        fit: BoxFit.contain,
                        colorFilter: ColorFilter.mode(
                          isDark ? Colors.white : _loginBlue,
                          BlendMode.srcIn,
                        ),
                        semanticsLabel: context.l10n.text(
                          '北京师范大学-香港浸会大学联合国际学院',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestoreOverlay extends StatelessWidget {
  const _RestoreOverlay();

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Positioned.fill(
      child: ColoredBox(
        color: tokens.textPrimary.withValues(alpha: 0.24),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(tokens.space24),
            child: const BnbuLoadingState(title: 'Restoring previous session'),
          ),
        ),
      ),
    );
  }
}
