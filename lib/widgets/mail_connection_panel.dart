import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/bnbu_localizations.dart';
import '../state/mail_access_controller.dart';
import 'bnbu_loading.dart';

class MailConnectionGate extends StatelessWidget {
  const MailConnectionGate({
    super.key,
    required this.controller,
    required this.ready,
    required this.child,
  });
  final MailAccessController controller;
  final bool ready;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ready && controller.shouldPrompt
        ? Scaffold(
            body: SafeArea(
              child: MailConnectionPanel(
                key: ValueKey(controller.owner),
                controller: controller,
                allowSkip: true,
              ),
            ),
          )
        : child,
  );
}

/// One form for the post-login repair and the mailbox's reconnect entry.
class MailConnectionPanel extends StatefulWidget {
  const MailConnectionPanel({
    super.key,
    required this.controller,
    this.allowSkip = false,
  });
  final MailAccessController controller;
  final bool allowSkip;
  @override
  State<MailConnectionPanel> createState() => _MailConnectionPanelState();
}

class _MailConnectionPanelState extends State<MailConnectionPanel> {
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (widget.controller.busy || _password.text.isEmpty) return;
    await widget.controller.connect(_password.text);
    if (mounted && widget.controller.status == MailAccessStatus.connected) {
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final access = widget.controller;
      final l10n = BnbuLocalizations.of(context);
      final textTheme = Theme.of(context).textTheme;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(LucideIcons.mail300, size: 32),
                const SizedBox(height: 20),
                Text(l10n.text('接入学校邮箱'), style: textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(l10n.text('iSpace 已登录。邮箱密码可以不同，也可以稍后在邮箱页接入。')),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('mail-connection-password'),
                  controller: _password,
                  obscureText: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  enabled: !access.busy,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _connect(),
                  decoration: InputDecoration(
                    labelText: l10n.text('邮箱密码'),
                    suffixIcon: IconButton(
                      tooltip: l10n.text(_obscure ? '显示密码' : '隐藏密码'),
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? LucideIcons.eye300 : LucideIcons.eyeOff300,
                      ),
                    ),
                  ),
                ),
                if (access.error != null) ...[
                  const SizedBox(height: 12),
                  Text(l10n.text(access.error!), style: textTheme.bodyMedium),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('mail-connection-submit'),
                  onPressed: access.busy || _password.text.isEmpty
                      ? null
                      : _connect,
                  child: access.busy
                      ? const BnbuActivityIndicator()
                      : Text(l10n.text('验证并接入')),
                ),
                if (access.status == MailAccessStatus.unavailable ||
                    access.status == MailAccessStatus.pending)
                  TextButton(
                    onPressed: access.busy
                        ? null
                        : () => access.ensureVerified(retry: true),
                    child: Text(l10n.text('重试连接')),
                  ),
                if (widget.allowSkip)
                  TextButton(
                    key: const ValueKey('mail-connection-skip'),
                    onPressed: access.skip,
                    child: Text(l10n.text('暂不接入邮箱')),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
