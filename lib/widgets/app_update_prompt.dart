import 'bnbu_loading.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/app_update.dart';
import '../state/app_update_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';

class AppUpdatePromptListener extends StatefulWidget {
  const AppUpdatePromptListener({
    super.key,
    required this.controller,
    this.modalContextProvider,
  });

  final AppUpdateController controller;
  final BuildContext? Function()? modalContextProvider;

  @override
  State<AppUpdatePromptListener> createState() =>
      _AppUpdatePromptListenerState();
}

class _AppUpdatePromptListenerState extends State<AppUpdatePromptListener> {
  Object? _modalRequest;

  @override
  void didUpdateWidget(covariant AppUpdatePromptListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _modalRequest = null;
    }
  }

  void _tryShowPrompt() {
    final state = widget.controller.state;
    final release =
        widget.controller.requiredRelease ??
        (state is AppUpdateAvailable ? state.value : null);
    if (release == null ||
        (widget.controller.lastCheckWasManual &&
            !widget.controller.requiresUpdate) ||
        !widget.controller.shouldPromptAutomatically(release) ||
        _modalRequest != null) {
      return;
    }
    final request = Object();
    _modalRequest = request;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _modalRequest != request) return;
      final modalContext = widget.modalContextProvider?.call() ?? context;
      if (!modalContext.mounted) {
        if (_modalRequest == request) _modalRequest = null;
        return;
      }
      unawaited(
        showAppUpdateModal(
          modalContext,
          controller: widget.controller,
        ).whenComplete(() {
          if (_modalRequest == request) _modalRequest = null;
          unawaited(widget.controller.deferAutomaticPrompt(release));
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        _tryShowPrompt();
        return const SizedBox.shrink();
      },
    );
  }
}

Future<void> showAppUpdateModal(
  BuildContext context, {
  required AppUpdateController controller,
  String? installedVersionLabel,
}) {
  if (controller.updateModalOpen) return Future.value();
  controller.updateModalOpen = true;
  final initialRelease = controller.state.release ?? controller.requiredRelease;
  var wasMandatory = controller.requiresUpdate;
  var closing = false;
  return showBnbuAdaptiveModal<void>(
    context: context,
    enableDrag: false,
    barrierDismissible: false,
    dialogMaxWidth: 520,
    dialogMaxHeight: 620,
    semanticLabel: context.l10n.text('软件更新'),
    contentKey: const ValueKey('app-update-modal'),
    builder: (modalContext, presentation) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = controller.state;
          final release = state.release ?? initialRelease;
          if (controller.requiresUpdate) wasMandatory = true;
          if (!closing &&
              (wasMandatory || state is AppUpdateUpToDate) &&
              !controller.requiresUpdate &&
              state is! AppUpdateChecking) {
            closing = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (modalContext.mounted) Navigator.of(modalContext).pop();
            });
          }
          return PopScope(
            canPop: !controller.requiresUpdate,
            child: BnbuModalFrame(
              showClose: !controller.requiresUpdate,
              presentation: presentation,
              title: controller.requiresUpdate ? '必须更新' : '软件更新',
              icon: LucideIcons.refreshCw300,
              bottomBar: _AppUpdateActions(
                controller: controller,
                state: state,
              ),
              child: SingleChildScrollView(
                child: _AppUpdateBody(
                  state: state,
                  release: release,
                  installedVersionLabel: installedVersionLabel,
                  canDownloadInApp: controller.canDownloadInApp,
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() {
    controller.updateModalOpen = false;
  });
}

class _AppUpdateBody extends StatelessWidget {
  const _AppUpdateBody({
    required this.state,
    required this.release,
    required this.installedVersionLabel,
    required this.canDownloadInApp,
  });

  final AppUpdateState state;
  final AppUpdateRelease? release;
  final String? installedVersionLabel;
  final bool canDownloadInApp;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final release = this.release;
    final notes =
        context.l10n.isEnglish && (release?.releaseNotesEn.isNotEmpty ?? false)
        ? release!.releaseNotesEn
        : release?.releaseNotes ?? const <String>[];
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (release != null)
            _VersionTransition(
              installedVersionLabel: installedVersionLabel,
              release: release,
            ),
          if (release != null && release.mandatoryReason.isNotEmpty) ...[
            SizedBox(height: tokens.space12),
            BnbuText(
              context.l10n.isEnglish && release.mandatoryReasonEn.isNotEmpty
                  ? release.mandatoryReasonEn
                  : release.mandatoryReason,
            ),
          ],
          if (release?.mandatoryAfter != null && !release!.mandatory) ...[
            SizedBox(height: tokens.space12),
            BnbuText(
              '${context.l10n.text('必须更新生效时间')} ${MaterialLocalizations.of(context).formatFullDate(release.mandatoryAfter!.toLocal())} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(release.mandatoryAfter!.toLocal()))}',
            ),
          ],
          if (release != null && notes.isNotEmpty) ...[
            SizedBox(height: tokens.space16),
            for (final note in notes)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.space8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Icon(
                        LucideIcons.circle300,
                        size: 6,
                        color: tokens.brandBlue,
                      ),
                    ),
                    SizedBox(width: tokens.space8),
                    Expanded(child: BnbuText(note)),
                  ],
                ),
              ),
          ],
          SizedBox(height: tokens.space16),
          switch (state) {
            AppUpdateChecking() => const _UpdateStatus(
              label: '正在检查更新',
              busy: true,
            ),
            AppUpdateAvailable() => _UpdateStatus(
              label: canDownloadInApp
                  ? '下载完成后将打开系统安装器，请确认安装'
                  : release?.platform == AppUpdatePlatform.ios
                  ? '请前往商店更新'
                  : '新版本将通过系统浏览器从官网下载安装',
              icon: canDownloadInApp
                  ? LucideIcons.download300
                  : LucideIcons.externalLink300,
            ),
            AppUpdateDownloading(:final progress) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _UpdateStatus(
                  label: '正在下载更新',
                  icon: LucideIcons.download300,
                ),
                SizedBox(height: tokens.space12),
                LinearProgressIndicator(
                  key: const ValueKey('app-update-progress'),
                  value: progress,
                  semanticsLabel: context.l10n.text('正在下载更新'),
                  semanticsValue: '${(progress * 100).round()}%',
                ),
                SizedBox(height: tokens.space8),
                Text('${(progress * 100).round()}%', textAlign: TextAlign.end),
              ],
            ),
            AppUpdateVerifying() => const _UpdateStatus(
              label: '正在校验安装包',
              busy: true,
            ),
            AppUpdateInstalling() => const _UpdateStatus(
              label: '正在准备安装',
              busy: true,
            ),
            AppUpdateAwaitingInstall(:final permissionRequired) =>
              _UpdateStatus(
                label: permissionRequired
                    ? '请允许 BNBU.ME 安装应用，返回后将继续安装'
                    : '请在系统页面确认安装，取消后可重新安装',
                icon: LucideIcons.download300,
              ),
            AppUpdateFailed(:final retryAction) => _UpdateStatus(
              label: switch (retryAction) {
                AppUpdateRetryAction.check => '检查更新失败，请重试',
                AppUpdateRetryAction.openWebsite => '无法打开官网，请重试',
                AppUpdateRetryAction.download => '更新下载或校验失败，请重试',
                AppUpdateRetryAction.install => '无法完成安装，请重试',
              },
              icon: LucideIcons.triangleAlert300,
            ),
            AppUpdateUpToDate() => const _UpdateStatus(
              label: '当前已是最新版本',
              icon: LucideIcons.badgeCheck300,
            ),
            AppUpdateIdle() ||
            AppUpdateUnsupported() => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

class _VersionTransition extends StatelessWidget {
  const _VersionTransition({
    required this.installedVersionLabel,
    required this.release,
  });

  final String? installedVersionLabel;
  final AppUpdateRelease release;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final installed = installedVersionLabel?.trim();
    final installedStyle = Theme.of(context).textTheme.titleSmall;
    final releaseStyle = installedStyle?.copyWith(
      color: tokens.brandBlue,
      fontWeight: FontWeight.w700,
    );
    final releaseText = BnbuText(
      release.versionLabel,
      textAlign: TextAlign.center,
      style: releaseStyle,
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space16,
        vertical: tokens.space12,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: Border.all(color: tokens.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (installed == null || installed.isEmpty) return releaseText;
          double labelWidth(String label, TextStyle? style) {
            final painter = TextPainter(
              text: TextSpan(
                text: label,
                style: DefaultTextStyle.of(context).style.merge(style),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              locale: Localizations.maybeLocaleOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          final columnWidth = (constraints.maxWidth - 18) / 2;
          final stack =
              labelWidth(installed, installedStyle) > columnWidth ||
              labelWidth(release.versionLabel, releaseStyle) > columnWidth;
          final installedText = BnbuText(
            installed,
            textAlign: TextAlign.center,
            style: installedStyle,
          );
          final arrow = Icon(
            stack ? LucideIcons.arrowDown300 : LucideIcons.arrowRight300,
            size: 18,
            color: tokens.textSecondary,
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                installedText,
                SizedBox(height: tokens.space8),
                arrow,
                SizedBox(height: tokens.space8),
                releaseText,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: installedText),
              arrow,
              Expanded(child: releaseText),
            ],
          );
        },
      ),
    );
  }
}

class _UpdateStatus extends StatelessWidget {
  const _UpdateStatus({required this.label, this.icon, this.busy = false});

  final String label;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Row(
      children: [
        if (busy)
          const SizedBox(width: 20, height: 20, child: BnbuActivityIndicator())
        else
          Icon(icon ?? LucideIcons.info300, size: 20, color: tokens.brandBlue),
        SizedBox(width: tokens.space12),
        Expanded(child: BnbuText(label)),
      ],
    );
  }
}

class _AppUpdateActions extends StatelessWidget {
  const _AppUpdateActions({required this.controller, required this.state});

  final AppUpdateController controller;
  final AppUpdateState state;

  @override
  Widget build(BuildContext context) {
    final actions = switch (state) {
      AppUpdateAvailable() => [
        if (!controller.requiresUpdate)
          TextButton(
            key: const ValueKey('app-update-later'),
            onPressed: () => Navigator.of(context).pop(),
            child: const BnbuText('稍后'),
          ),
        if (controller.canDownloadInApp)
          FilledButton.icon(
            key: const ValueKey('app-update-download'),
            onPressed: () => unawaited(controller.downloadAndInstall()),
            icon: const Icon(LucideIcons.download300, size: 18),
            label: const BnbuText('下载并安装'),
          )
        else
          FilledButton.icon(
            key: const ValueKey('app-update-open-website'),
            onPressed: () => unawaited(_openWebsite(context)),
            icon: const Icon(LucideIcons.externalLink300, size: 18),
            label: BnbuText(controller.usesStore ? '前往商店更新' : '前往官网下载'),
          ),
      ],
      AppUpdateDownloading() => [
        TextButton(
          key: const ValueKey('app-update-cancel'),
          onPressed: controller.cancelDownload,
          child: const BnbuText('取消下载'),
        ),
      ],
      AppUpdateAwaitingInstall(:final permissionRequired) => [
        if (!controller.requiresUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const BnbuText('稍后'),
          ),
        FilledButton.icon(
          key: const ValueKey('app-update-install'),
          onPressed: () => unawaited(
            controller.installUpdate(requestPermission: permissionRequired),
          ),
          icon: const Icon(LucideIcons.download300, size: 18),
          label: BnbuText(permissionRequired ? '允许安装' : '重新安装'),
        ),
      ],
      AppUpdateFailed(:final retryAction) => [
        FilledButton.icon(
          key: const ValueKey('app-update-retry'),
          onPressed: () => unawaited(switch (retryAction) {
            AppUpdateRetryAction.check => _check(),
            AppUpdateRetryAction.openWebsite => _openWebsite(context),
            AppUpdateRetryAction.download => controller.downloadAndInstall(),
            AppUpdateRetryAction.install => controller.installUpdate(),
          }),
          icon: const Icon(LucideIcons.rotateCw300, size: 18),
          label: const BnbuText('重试'),
        ),
      ],
      _ => <Widget>[],
    };
    if (actions.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...actions,
          if (controller.requiresUpdate)
            TextButton(
              onPressed: () => unawaited(_check()),
              child: const BnbuText('重新检查'),
            ),
        ],
      ),
    );
  }

  Future<void> _check() async {
    await controller.checkForUpdates();
  }

  Future<void> _openWebsite(BuildContext context) async {
    final opened = await controller.openDownloadPage();
    if (opened && context.mounted && !controller.requiresUpdate) {
      Navigator.of(context).pop();
    }
  }
}
