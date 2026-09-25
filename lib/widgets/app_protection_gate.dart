import 'bnbu_loading.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/app_protection_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive.dart';

class AppProtectionGate extends StatelessWidget {
  const AppProtectionGate({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppProtectionController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final protected = controller.shouldShowGate;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              key: const ValueKey('app-protection-content'),
              offstage: protected,
              child: TickerMode(
                enabled: !protected,
                child: IgnorePointer(ignoring: protected, child: child),
              ),
            ),
            if (protected) _AppProtectionLockScreen(controller: controller),
          ],
        );
      },
    );
  }
}

class _AppProtectionLockScreen extends StatelessWidget {
  const _AppProtectionLockScreen({required this.controller});

  final AppProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final iconOnlyUnlock = theme.platform == TargetPlatform.iOS;
    final busy = controller.isRestoring || controller.isAuthenticating;
    // Enlarge the app-owned iPhone presentation, not the system auth prompt.
    // Biometric type and authentication behavior remain controller-owned.
    final compactIos =
        iconOnlyUnlock &&
        MediaQuery.sizeOf(context).width <= BnbuBreakpoints.compactMax;
    final emblem = Icon(
      controller.availableType == DeviceBiometricType.touchId
          ? LucideIcons.fingerprint300
          : LucideIcons.scanFace300,
      size: compactIos ? 42 : 34,
      color: tokens.brandBlue,
    );
    return ColoredBox(
      key: const ValueKey('app-protection-lock-screen'),
      color: tokens.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: const ValueKey('app-protection-emblem'),
                    width: compactIos ? 88 : 72,
                    height: compactIos ? 88 : 72,
                    decoration: BoxDecoration(
                      color: tokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(tokens.radius24),
                      border: Border.all(color: tokens.border),
                    ),
                    alignment: Alignment.center,
                    child: iconOnlyUnlock
                        ? SizedBox.expand(
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                tokens.radius24,
                              ),
                              child: IconButton(
                                key: const ValueKey(
                                  'app-protection-unlock-icon',
                                ),
                                tooltip: context.l10n.text(
                                  controller.unlockLabel,
                                ),
                                onPressed: busy
                                    ? null
                                    : () =>
                                          unawaited(controller.authenticate()),
                                icon: emblem,
                              ),
                            ),
                          )
                        : emblem,
                  ),
                  SizedBox(height: tokens.space24),
                  BnbuText(
                    'BNBU.ME',
                    textAlign: TextAlign.center,
                    style: compactIos
                        ? theme.textTheme.headlineSmall?.copyWith(fontSize: 26)
                        : theme.textTheme.headlineSmall,
                  ),
                  if (controller.message != null) ...[
                    SizedBox(height: tokens.space12),
                    BnbuText(
                      controller.message!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (busy || !iconOnlyUnlock) SizedBox(height: tokens.space24),
                  if (busy)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: BnbuActivityIndicator(color: tokens.brandBlue),
                    )
                  else if (!iconOnlyUnlock)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => unawaited(controller.authenticate()),
                        icon: Icon(
                          controller.availableType ==
                                  DeviceBiometricType.touchId
                              ? LucideIcons.fingerprint300
                              : LucideIcons.scanFace300,
                        ),
                        label: BnbuText(controller.unlockLabel),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
