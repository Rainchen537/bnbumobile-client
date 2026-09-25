import 'me_identity_page.dart';
import '../services/me_identity_service.dart';
import '../widgets/personalization_settings.dart';
import '../widgets/ecard_gender_settings_entry.dart';
import '../services/ecard_gender_store.dart';
import 'student_ecard_page.dart';
import '../services/desktop_download_service.dart';
import '../widgets/desktop_download_directory_tile.dart';
import '../widgets/bnbu_menu.dart';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/bnbu_loading.dart';
import '../widgets/statistics_consent_settings.dart';
import '../widgets/personal_sync_settings.dart';
import '../state/personal_sync_controller.dart';
import '../widgets/user_backdrop.dart';
import '../widgets/app_about_content.dart';
import '../models/portal_account_profile.dart';
import '../models/app_update.dart';
import '../services/app_update_policy_service.dart';
import '../services/deadline_reminder_service.dart';
import '../services/moodle_api_client.dart';
import '../state/app_session_controller.dart';
import '../state/app_language_controller.dart';
import '../state/app_protection_controller.dart';
import '../state/app_update_controller.dart';
import '../state/app_theme_mode_controller.dart';
import '../state/live_activity_preference_controller.dart';
import '../state/mail_radar_background_coordinator.dart';
import '../state/mail_radar_controller.dart';
import '../services/mail_radar_analyzer.dart';
import '../state/student_avatar_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_creation_form.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/app_update_prompt.dart';
import '../widgets/student_avatar_editor.dart';
import '../widgets/student_avatar_rive.dart';

bool get _supportsSelfUpdate {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
}

class UserPage extends StatefulWidget {
  const UserPage({
    super.key,
    required this.controller,
    this.appProtectionController,
    this.themeModeController,
    this.languageController,
    this.liveActivityController,
    this.mailRadarCoordinator,
    this.appUpdateController,
    this.onDisableAssistant,
    this.onClearAssistantHistory,
    this.personalSync,
    this.ecardGenderStore,
  });

  final AppSessionController controller;
  final AppProtectionController? appProtectionController;
  final AppThemeModeController? themeModeController;
  final AppLanguageController? languageController;
  final LiveActivityPreferenceController? liveActivityController;
  final MailRadarBackgroundCoordinator? mailRadarCoordinator;
  final AppUpdateController? appUpdateController;
  final Future<void> Function()? onDisableAssistant;
  final Future<void> Function()? onClearAssistantHistory;
  final PersonalSyncController? personalSync;
  final EcardGenderStore? ecardGenderStore;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  static const bool _studentAvatarVisible = false;
  bool _wideSettings = false;
  final _settingsNavigatorKey = GlobalKey<NavigatorState>();
  final List<MaterialPage<void>> _settingsPages = [];

  Widget _settingsNavigation(Widget overview) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => _settingsNavigatorKey.currentState?.maybePop(),
    child: Navigator(
      key: _settingsNavigatorKey,
      pages: [
        MaterialPage<void>(
          key: const ValueKey('settings-overview'),
          child: overview,
        ),
        ..._settingsPages,
      ],
      onDidRemovePage: (page) {
        if (_settingsPages.contains(page) && mounted) {
          setState(() => _settingsPages.remove(page));
        }
      },
    ),
  );

  late final AppThemeModeController _themeModeController =
      widget.themeModeController ?? AppThemeModeController();
  late final bool _ownsThemeModeController = widget.themeModeController == null;
  late final AppLanguageController _languageController =
      widget.languageController ?? AppLanguageController();
  late final bool _ownsLanguageController = widget.languageController == null;
  late final LiveActivityPreferenceController _liveActivityController =
      widget.liveActivityController ?? LiveActivityPreferenceController();
  late final bool _ownsLiveActivityController =
      widget.liveActivityController == null;
  PackageInfo? _packageInfo;
  String _versionLabel = '--';
  String? _identityOwner;
  bool _isLoadingVersion = true;
  late final StudentAvatarController _avatarController =
      StudentAvatarController();

  String get _shortVersionLabel {
    final version = _packageInfo?.version.trim() ?? '';
    return version.isEmpty ? _versionLabel : displayedProductVersion(version);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncAvatarOwner);
    _syncAvatarOwner();
    if (_ownsThemeModeController) {
      unawaited(_themeModeController.restore());
    }
    if (_ownsLanguageController) {
      unawaited(
        _languageController.restore(
          preferredLocales: WidgetsBinding.instance.platformDispatcher.locales,
        ),
      );
    }
    if (_ownsLiveActivityController) {
      unawaited(_liveActivityController.restore());
    }
    _loadVersionInfo();
    _ensureIdentityProfile();
  }

  @override
  void didUpdateWidget(UserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncAvatarOwner);
      widget.controller.addListener(_syncAvatarOwner);
      _syncAvatarOwner();
      _ensureIdentityProfile();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncAvatarOwner);
    _avatarController.dispose();
    if (_ownsThemeModeController) {
      _themeModeController.dispose();
    }
    if (_ownsLanguageController) {
      _languageController.dispose();
    }
    if (_ownsLiveActivityController) {
      _liveActivityController.dispose();
    }
    super.dispose();
  }

  void _syncAvatarOwner() {
    unawaited(_avatarController.switchOwner(widget.controller.username));
    final owner = widget.controller.isLoggedIn
        ? widget.controller.username
        : null;
    if (owner != _identityOwner) {
      _identityOwner = owner;
      if (owner != null) _ensureIdentityProfile();
    }
  }

  void _ensureIdentityProfile() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.ensureIdentityProfileLoaded());
    });
  }

  Future<void> _openAvatarEditor() {
    return showStudentAvatarEditor(context, _avatarController);
  }

  Future<void> _loadVersionInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = displayedProductVersion(packageInfo.version.trim());
      final buildNumber = packageInfo.buildNumber.trim();
      final label = buildNumber.isEmpty ? version : '$version+$buildNumber';
      if (!mounted) {
        return;
      }
      setState(() {
        _packageInfo = packageInfo;
        _versionLabel = label.isEmpty ? '--' : label;
        _isLoadingVersion = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingVersion = false;
      });
    }
  }

  Future<void> _handleDeadlineReminderToggle(bool enabled) async {
    final controller = widget.controller;
    final message = await controller.setDeadlineReminderEnabled(enabled);
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: BnbuText(
          message ??
              (enabled
                  ? 'DDL 通知已开启，将智能安排 ${controller.deadlineReminderPreferences.reminderCount} 次提醒。'
                  : 'DDL 通知已关闭，已排程的 DDL 通知已清除。'),
        ),
      ),
    );
  }

  Future<void> _handleCourseReminderToggle(bool enabled) async {
    final controller = widget.controller;
    final message = await controller.setCourseReminderEnabled(enabled);
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: BnbuText(
          message ??
              (enabled
                  ? '课表通知已开启，将在上课前 ${_courseLeadLabel(controller.courseReminderLeadMinutes)}提醒。'
                  : '课表通知已关闭，已排程的课程通知已清除。'),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final controller = widget.controller;
    if (controller.isBusy) {
      return;
    }

    // Capture the navigator before logout disposes the signed-in root.
    final navigator = Navigator.of(context);
    await controller.logout();
    if (navigator.mounted && !controller.isLoggedIn) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _handleDisableAssistant() async {
    final onDisableAssistant = widget.onDisableAssistant;
    if (onDisableAssistant == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('停用小U？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const BnbuText('停用'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await onDisableAssistant();
    }
  }

  Future<void> _handleClearAssistantHistory() async {
    final onClearAssistantHistory = widget.onClearAssistantHistory;
    if (onClearAssistantHistory == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('清空小U历史？'),
        content: const BnbuText('本机与已同步的小U问答都会被清空。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const BnbuText('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await onClearAssistantHistory();
    }
  }

  void _openSettingsPage({
    required String title,
    required List<Widget> children,
    bool separateSections = false,
  }) {
    if (!_wideSettings && _settingsPages.isEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _SettingsDetailPage(
            title: title,
            separateSections: separateSections,
            children: children,
          ),
        ),
      );
      return;
    }
    setState(() {
      _settingsPages.add(
        MaterialPage<void>(
          key: UniqueKey(),
          child: _SettingsDetailPage(
            title: title,
            separateSections: separateSections,
            children: children,
          ),
        ),
      );
    });
  }

  void _showVersionSheet() {
    final packageInfo = _packageInfo;
    showBnbuAdaptiveModal<void>(
      context: context,
      dialogMaxWidth: 480,
      dialogMaxHeight: 520,
      bottomSheetBackgroundColor: Colors.transparent,
      semanticLabel: context.l10n.text('版本信息'),
      contentKey: const ValueKey('user-version-info-modal'),
      builder: (modalContext, presentation) {
        final tokens = modalContext.bnbuTheme;
        final content = Padding(
          padding: EdgeInsets.all(tokens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: BnbuText(
                      '版本信息',
                      style: Theme.of(modalContext).textTheme.titleMedium
                          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (presentation.isDialog)
                    IconButton(
                      tooltip: context.l10n.text('关闭'),
                      onPressed: () => Navigator.of(modalContext).pop(),
                      icon: const Icon(LucideIcons.x300),
                    ),
                ],
              ),
              SizedBox(height: tokens.space8),
              _InfoRow(label: '应用名称', value: packageInfo?.appName ?? '不可用'),
              SizedBox(height: tokens.space12),
              _InfoRow(label: '包名', value: packageInfo?.packageName ?? '不可用'),
              SizedBox(height: tokens.space12),
              _InfoRow(label: '版本', value: _versionLabel),
            ],
          ),
        );
        if (presentation.isDialog) {
          return content;
        }
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.space16,
              0,
              tokens.space16,
              tokens.space16,
            ),
            child: _SettingsGroup(children: [content]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        _avatarController,
        _themeModeController,
        _languageController,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        final session = controller.session;
        final username = controller.username?.trim();
        final portalProfile = controller.portalProfile;

        final tokens = context.bnbuTheme;
        final statusNotices = <Widget>[
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: BnbuNotice(
                message: controller.error!,
                kind: BnbuStatusKind.danger,
              ),
            ),
        ];
        final overviewEntries = <Widget>[
          if (widget.mailRadarCoordinator != null ||
              DesktopDownloadService.supported)
            _ActionTile(
              key: const ValueKey('general-settings-entry'),
              title: '通用设置',
              onTap: () => _openSettingsPage(
                title: '通用设置',
                children: [
                  if (widget.mailRadarCoordinator != null)
                    _MailRadarSettings(
                      coordinator: widget.mailRadarCoordinator!,
                    ),
                  if (DesktopDownloadService.supported)
                    const DesktopDownloadDirectoryTile(
                      purpose: DesktopDownloadPurpose.single,
                    ),
                ],
              ),
            ),
          _ActionTile(
            title: '通知与同步',
            onTap: () => _openSettingsPage(
              title: '通知与同步',
              separateSections: true,
              children: [
                _NotificationContentSettings(
                  key: const ValueKey('notification-content-settings'),
                  controller: controller,
                  onCourseChanged: _handleCourseReminderToggle,
                  onDeadlineChanged: _handleDeadlineReminderToggle,
                ),
                if (widget.personalSync != null)
                  Column(
                    children: [
                      ListTile(
                        title: const BnbuText('多端同步设置'),
                        onTap: () {
                          final owner = controller.username;
                          if (owner != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MeIdentityPage(
                                  owner: owner,
                                  mailCredentials:
                                      controller.loadMailAccessCredentials,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      ListenableBuilder(
                        listenable: MeIdentityService.shared,
                        builder: (context, _) =>
                            MeIdentityService.shared.syncEnabled(
                              controller.username,
                            )
                            ? PersonalSyncSettings(
                                controller: widget.personalSync!,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                if (controller.statistics.supported)
                  StatisticsConsentSettings(service: controller.statistics),
                if (Theme.of(context).platform == TargetPlatform.iOS)
                  _LiveActivitySettings(
                    key: const ValueKey('ios-live-activity-settings'),
                    controller: _liveActivityController,
                  ),
              ],
            ),
          ),
          _ActionTile(
            title: '外观与语言',
            value: _themeModeLabel(_themeModeController.themeMode),
            stackValueOnCompact: context.l10n.isEnglish,
            onTap: () => _openSettingsPage(
              title: '外观与语言',
              separateSections: true,
              children: [
                _ThemeModeSelector(controller: _themeModeController),
                if (Theme.of(context).platform == TargetPlatform.iOS)
                  _LiquidGlassToggle(
                    key: const ValueKey('ios-liquid-glass-setting'),
                    controller: _themeModeController,
                  ),
                _ScheduleTodayHighlightSettings(
                  key: const ValueKey('schedule-today-highlight-settings'),
                  controller: _themeModeController,
                ),
                AnimatedBuilder(
                  key: const ValueKey('appearance-language-setting'),
                  animation: _languageController,
                  builder: (context, _) => _ActionTile(
                    title: '语言',
                    value: _languageModeLabel(_languageController.mode),
                    onTap: () => _openSettingsPage(
                      title: '语言',
                      children: [
                        _LanguageSelector(controller: _languageController),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ActionTile(
            title: '个性化',
            onTap: () => _openSettingsPage(
              title: '个性化',
              children: [
                PersonalizationSettings(controller: widget.controller),
              ],
            ),
          ),
          _ActionTile(
            title: '关于应用',
            value: _shortVersionLabel,
            onTap: () => _openSettingsPage(
              title: '关于应用',
              children: [
                AppAboutContent(versionLabel: _versionLabel),
                _ActionTile(
                  title: '版本信息',
                  value: _versionLabel,
                  isValueLoading: _isLoadingVersion,
                  onTap: _showVersionSheet,
                ),
                if (_supportsSelfUpdate && widget.appUpdateController != null)
                  _AppUpdateTile(
                    controller: widget.appUpdateController!,
                    installedVersionLabel: _versionLabel,
                  ),
              ],
            ),
          ),
          _ActionTile(
            title: '账户与安全',
            onTap: () => _openSettingsPage(
              title: '账户与安全',
              children: [
                _ActionTile(
                  title: 'ME 账户',
                  onTap: () {
                    final owner = controller.username;
                    if (owner == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MeIdentityPage(
                          owner: owner,
                          mailCredentials: controller.loadMailAccessCredentials,
                        ),
                      ),
                    );
                  },
                ),

                if (StudentEcardPage.supportsPlatform(
                  Theme.of(context).platform,
                ))
                  _ActionTile(
                    key: const ValueKey('personal-profile-display-setting'),
                    title: '个人资料显示',
                    onTap: () => _openSettingsPage(
                      title: '个人资料显示',
                      children: [
                        EcardGenderSettingsEntry(
                          controller: controller,
                          store: widget.ecardGenderStore,
                        ),
                      ],
                    ),
                  ),
                if (LocalBiometricAuthenticator.supportsPlatform(
                      Theme.of(context).platform,
                    ) &&
                    widget.appProtectionController != null)
                  _BiometricProtectionToggle(
                    key: const ValueKey('biometric-protection-setting'),
                    controller: widget.appProtectionController!,
                  ),
                if (widget.onClearAssistantHistory != null)
                  _ActionTile(
                    key: const ValueKey('clear-assistant-history-setting'),
                    title: '清空小U历史',
                    onTap: _handleClearAssistantHistory,
                    isDanger: true,
                  ),
                if (widget.onDisableAssistant != null)
                  _ActionTile(
                    title: '停用小U',
                    onTap: _handleDisableAssistant,
                    isDanger: true,
                  ),
                _ActionTile(
                  title: '退出登录',
                  onTap: controller.isBusy ? null : _handleLogout,
                  isDanger: true,
                ),
              ],
            ),
          ),
        ];
        final actionPanel = _SettingsOverview(
          account: overviewEntries.last,
          about: overviewEntries[overviewEntries.length - 2],
          preferences: overviewEntries
              .take(overviewEntries.length - 2)
              .toList(),
        );
        return Scaffold(
          backgroundColor: tokens.canvas,
          body: LayoutBuilder(
            builder: (context, constraints) {
              _wideSettings =
                  constraints.maxWidth >= BnbuBreakpoints.tabletWorkspace;
              if (_wideSettings) {
                final identityWidth = (constraints.maxWidth * 0.38)
                    .clamp(340.0, 430.0)
                    .toDouble();
                return Row(
                  key: const ValueKey('user-desktop-split-layout'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: identityWidth,
                      child: _DesktopUserHero(
                        session: session,
                        username: username,
                        portalProfile: portalProfile,
                        majorName: controller.studentMajor,
                        isLoadingPortalProfile:
                            controller.isLoadingPortalProfile,
                        avatarController: _avatarController,
                        onEditAvatar: _openAvatarEditor,
                        showAvatar: _studentAvatarVisible,
                      ),
                    ),
                    Expanded(
                      child: _settingsNavigation(
                        SafeArea(
                          minimum: EdgeInsets.only(
                            top: tokens.space32,
                            bottom: tokens.space24,
                          ),
                          child: ListView(
                            physics: const ClampingScrollPhysics(),
                            padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.of(context).padding.bottom +
                                  tokens.space24,
                            ),
                            children: [
                              ...statusNotices,
                              SizedBox(
                                height: statusNotices.isEmpty
                                    ? tokens.space8
                                    : tokens.space24,
                              ),
                              actionPanel,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              final mediaQuery = MediaQuery.of(context);
              final headerHeight = (mediaQuery.size.height * 0.38)
                  .clamp(300.0, 390.0)
                  .toDouble();
              return _settingsNavigation(
                KeyedSubtree(
                  key: const ValueKey('user-mobile-settings-mode'),
                  child: ListView(
                    key: const ValueKey('user-mobile-scroll-view'),
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      Stack(
                        key: const ValueKey('user-mobile-identity-header'),
                        children: [
                          const Positioned.fill(child: _MobileUserBackdrop()),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: headerHeight,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(height: mediaQuery.padding.top + 64),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: tokens.space16,
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 460,
                                      ),
                                      child: _AcrylicProfileCard(
                                        session: session,
                                        username: username,
                                        portalProfile: portalProfile,
                                        majorName: controller.studentMajor,
                                        isLoadingPortalProfile:
                                            controller.isLoadingPortalProfile,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ],
                      ),
                      ColoredBox(
                        key: const ValueKey('user-mobile-settings-surface'),
                        color: tokens.canvas,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: 36,
                            bottom: mediaQuery.padding.bottom + tokens.space24,
                          ),
                          child: Column(
                            children: [...statusNotices, actionPanel],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
  }

  String _languageModeLabel(AppLanguageMode mode) {
    return switch (mode) {
      AppLanguageMode.system => _languageModeLabel(
        AppLanguageController.modeForLocale(
          AppLanguageController.resolveSystemLocale(
            WidgetsBinding.instance.platformDispatcher.locales,
          ),
        ),
      ),
      AppLanguageMode.chinese => '简体中文',
      AppLanguageMode.traditionalChinese => '繁體中文',
      AppLanguageMode.english => 'English',
    };
  }
}

class _DesktopUserHero extends StatelessWidget {
  const _DesktopUserHero({
    required this.session,
    required this.username,
    required this.portalProfile,
    required this.majorName,
    required this.isLoadingPortalProfile,
    required this.avatarController,
    required this.onEditAvatar,
    required this.showAvatar,
  });

  final AuthSession? session;
  final String? username;
  final PortalAccountProfile? portalProfile;
  final String majorName;
  final bool isLoadingPortalProfile;
  final StudentAvatarController avatarController;
  final VoidCallback onEditAvatar;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Stack(
      key: const ValueKey('user-desktop-identity-panel'),
      fit: StackFit.expand,
      children: [
        const UserBackdrop(),
        if (Theme.of(context).brightness == Brightness.dark)
          ColoredBox(
            key: const ValueKey('user-desktop-background-overlay'),
            color: const Color(0xFF0B1724).withValues(alpha: 0.24),
          ),
        SafeArea(
          minimum: EdgeInsets.all(tokens.space24),
          child: Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Column(
              children: [
                _AcrylicProfileCard(
                  session: session,
                  username: username,
                  portalProfile: portalProfile,
                  majorName: majorName,
                  isLoadingPortalProfile: isLoadingPortalProfile,
                  onTap: showAvatar ? avatarController.toggleReveal : null,
                ),
                SizedBox(height: tokens.space16),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: showAvatar && avatarController.isRevealed
                        ? StudentAvatarStage(
                            key: const ValueKey('user-desktop-avatar-stage'),
                            profile: avatarController.profile,
                            onEdit: onEditAvatar,
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('user-desktop-avatar-hidden'),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileUserBackdrop extends StatelessWidget {
  const _MobileUserBackdrop();

  @override
  Widget build(BuildContext context) {
    final canvas = context.bnbuTheme.canvas;
    return Stack(
      fit: StackFit.expand,
      children: [
        const UserBackdrop(
          key: ValueKey('user-mobile-background'),
          alignment: Alignment.topCenter,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                canvas.withValues(alpha: 0.32),
                canvas,
              ],
              stops: const [0, 0.72, 0.9, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _AcrylicProfileCard extends StatelessWidget {
  const _AcrylicProfileCard({
    required this.session,
    required this.username,
    required this.portalProfile,
    required this.majorName,
    required this.isLoadingPortalProfile,
    this.onTap,
  });

  final AuthSession? session;
  final String? username;
  final PortalAccountProfile? portalProfile;
  final String majorName;
  final bool isLoadingPortalProfile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fullName = portalProfile?.fullName.trim();
    final displayName = (fullName != null && fullName.isNotEmpty)
        ? fullName
        : (session?.fullName.trim().isNotEmpty ?? false)
        ? session!.fullName.trim()
        : '学生';
    final emailAddress = _resolveStudentEmail(username);
    final majorLine = majorName.isEmpty ? '--' : majorName;
    final emailLine = emailAddress.isEmpty ? '--' : emailAddress;

    final tokens = context.bnbuTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final radius = BorderRadius.circular(20);
    final card = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: highContrast ? 0 : 6,
          sigmaY: highContrast ? 0 : 6,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: highContrast ? tokens.surface : null,
            gradient: highContrast
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            const Color(0xFF0B1724).withValues(alpha: 0.28),
                            const Color(0xFF0B1724).withValues(alpha: 0.20),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.24),
                            Colors.white.withValues(alpha: 0.16),
                          ],
                  ),
            borderRadius: radius,
            border: Border.all(
              color: highContrast
                  ? tokens.border
                  : Colors.white.withValues(alpha: isDark ? 0.22 : 0.34),
              width: 0.7,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 112, maxWidth: 424),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: BnbuText(
                          displayName,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: tokens.textPrimary,
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                height: 1.2,
                              ),
                        ),
                      ),
                      if (isLoadingPortalProfile)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 6),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: BnbuActivityIndicator(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                      SizedBox(
                        key: const ValueKey('user-hero-brand-mark'),
                        width: 30,
                        height: 30,
                        child: SvgPicture.asset(
                          'assets/user/user_logo.svg',
                          key: const ValueKey('user-hero-brand-logo'),
                          fit: BoxFit.contain,
                          colorFilter: ColorFilter.mode(
                            isDark ? Colors.white : tokens.brandBlue,
                            BlendMode.srcIn,
                          ),
                          semanticsLabel: '北京师范大学-香港浸会大学联合国际学院',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _IdentityMetadata(
                    key: const ValueKey('user-profile-major'),
                    label: '专业',
                    value: majorLine,
                  ),
                  const SizedBox(height: 8),
                  _IdentityMetadata(
                    key: const ValueKey('user-profile-email'),
                    label: '邮箱',
                    value: emailLine,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      key: const ValueKey('user-profile-card'),
      container: true,
      button: onTap != null,
      label: context.l10n.text('学生身份，$displayName，专业 $majorLine，邮箱 $emailLine'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: radius, onTap: onTap, child: card),
      ),
    );
  }

  String _resolveStudentEmail(String? username) {
    final normalized = (username ?? '').trim().split('@').first.toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    return '$normalized@mail.bnbu.edu.cn';
  }
}

class _IdentityMetadata extends StatelessWidget {
  const _IdentityMetadata({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final labelWidget = BnbuText(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: tokens.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.65,
      ),
    );
    final valueWidget = BnbuText(
      value,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: tokens.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, const SizedBox(height: 2), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: context.l10n.isEnglish ? 40 : 30,
              child: labelWidget,
            ),
            const SizedBox(width: 12),
            Expanded(child: valueWidget),
          ],
        );
      },
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.bnbuTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SettingsOverview extends StatelessWidget {
  const _SettingsOverview({
    required this.account,
    required this.about,
    required this.preferences,
  });

  final Widget account;
  final Widget about;
  final List<Widget> preferences;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              _SettingsGroup(
                key: const ValueKey('user-preferences-group'),
                children: preferences,
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                key: const ValueKey('user-account-group'),
                children: [account, about],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({
    required this.title,
    required this.children,
    this.separateSections = false,
  });

  final String title;
  final List<Widget> children;
  final bool separateSections;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    final sections = separateSections
        ? children.map((child) => [child])
        : [children];
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          titleSmall: theme.textTheme.titleSmall?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          titleMedium: theme.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
          titleLarge: theme.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          labelLarge: theme.textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          minTileHeight: 56,
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: tokens.canvas,
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(
            title: BnbuText(
              title,
              maxLines: 2,
              softWrap: true,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: BnbuHeaderMetrics.titleSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            centerTitle: true,
            toolbarHeight: MediaQuery.textScalerOf(context).scale(17) > 22
                ? MediaQuery.textScalerOf(context).scale(17) * 2.4 + 12
                : 56,
            backgroundColor: tokens.canvas,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            shape: const Border(),
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const BnbuBackIcon(),
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              for (final section in sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _SettingsGroup(children: section),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MailRadarSettings extends StatefulWidget {
  const _MailRadarSettings({required this.coordinator});

  final MailRadarBackgroundCoordinator coordinator;

  @override
  State<_MailRadarSettings> createState() => _MailRadarSettingsState();
}

class _MailRadarSettingsState extends State<_MailRadarSettings> {
  MailRadarController? _controller;
  bool _preparing = true;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (mounted) setState(() => _preparing = true);
    final controller = await widget.coordinator.prepareForSettings();
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _preparing = false;
    });
  }

  Future<void> _selectRange(int days) async {
    if (_changing) return;
    final coordinator = widget.coordinator;
    if (coordinator.isCheckingFeatureAvailability || _preparing) return;
    if (days > 0 && !coordinator.availabilityKnown) {
      BnbuToast.show(
        context,
        coordinator.featureAvailabilityError ?? '暂时无法确认邮件雷达权限，请稍后重试。',
        kind: BnbuToastKind.warning,
      );
      return;
    }
    if (days > 0 && !coordinator.isFeatureAvailable) {
      if (days > 0) {
        BnbuToast.show(context, '管理员暂未开放此权限', kind: BnbuToastKind.warning);
      }
      return;
    }

    final controller = _controller ?? await coordinator.prepareForSettings();
    if (!mounted || controller == null) {
      if (mounted) {
        BnbuToast.show(
          context,
          '邮件雷达暂时无法准备，请稍后重试。',
          kind: BnbuToastKind.warning,
        );
      }
      return;
    }
    final source = controller.analyzer is MailSourceRadarAnalyzer
        ? controller.analyzer as MailSourceRadarAnalyzer
        : null;
    Map<String, dynamic>? sourcePolicy;
    if (days > 0 && source != null) {
      try {
        sourcePolicy = await source.policy(controller.username);
      } catch (_) {
        if (mounted) {
          BnbuToast.show(
            context,
            '邮件信息源配置暂时无法读取。',
            kind: BnbuToastKind.warning,
          );
        }
        return;
      }
      if (!mounted) return;
    }
    final sourceConsent = sourcePolicy?['consent'];
    if (days > 0 &&
        (!controller.hasConsent ||
            (source != null &&
                (sourceConsent is! Map ||
                    sourceConsent['enabled'] != true ||
                    sourceConsent['current'] != true)))) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const BnbuText('启用邮件雷达'),
          content: BnbuText(
            sourcePolicy == null
                ? '小U将分析所选范围内的邮件正文与允许的附件，并同步加密后的分析结果。范围设置会同步到同一账号的其他设备。'
                : '开启后，后台将收集近${sourcePolicy['source_days']}天收件箱中的邮件正文及可提取附件文字，保存${sourcePolicy['retention_days']}天；验证码、密码和访问凭证等私密内容会被排除。后台管理员可查看已上传正文。TypeSafe JEV进行分类，已配置AI服务提取雷达结果和校园活动候选。符合条件的活动信息经核验后可向其他用户展示。你的雷达只领取实际出现在你邮箱中的邮件，自动领取按任务倍率计费，主动加入按100%计费。同一邮件首次领取后不重复扣除。关闭后停止后续采集和分析。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const BnbuText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const BnbuText('同意'),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
    }

    setState(() => _changing = true);
    try {
      if (source != null && sourcePolicy != null) {
        final settingsVersion = await source.choose(
          controller.username,
          days,
          sourcePolicy,
        );
        await controller.acceptSourceRangeChoice(days, settingsVersion);
      } else {
        await controller.setRangeChoice(days);
      }
      await coordinator.activateAfterConsent();
      if (mounted && controller.error != null) {
        BnbuToast.show(
          context,
          context.l10n.text(controller.error!),
          kind: BnbuToastKind.warning,
        );
      }
    } catch (_) {
      if (mounted) {
        BnbuToast.show(
          context,
          '邮件雷达设置保存失败，请稍后重试。',
          kind: BnbuToastKind.warning,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _controller = coordinator.controller ?? controller;
          _changing = false;
        });
      }
    }
  }

  Future<void> _choose(int selectedDays) async {
    final value = await showBnbuAdaptiveModal<int>(
      context: context,
      dialogMaxWidth: 420,
      dialogMaxHeight: 360,
      bottomSheetBackgroundColor: Colors.transparent,
      semanticLabel: context.l10n.text('邮件雷达'),
      builder: (modalContext, presentation) => BnbuModalFrame(
        presentation: presentation,
        title: '邮件雷达',
        showDividers: false,
        titleStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        bodyPadding: EdgeInsets.zero,
        child: RadioGroup<int>(
          groupValue: selectedDays,
          onChanged: (value) => Navigator.of(modalContext).pop(value),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final days in const [0, 7, 30, 60])
                BnbuChoiceTile<int>(
                  controlKey: ValueKey('mail-radar-range-$days'),
                  value: days,
                  selected: days == selectedDays,
                  title: BnbuText(days == 0 ? '不使用' : '$days 天'),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null && mounted) await _selectRange(value);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.coordinator,
    builder: (context, _) {
      final coordinator = widget.coordinator;
      final checking = _preparing || coordinator.isCheckingFeatureAvailability;
      final controller = _controller ?? coordinator.controller;
      final selected = coordinator.isEffectivelyEnabled && controller != null
          ? controller.lookbackDays
          : 0;
      final locked =
          coordinator.availabilityKnown && !coordinator.isFeatureAvailable;
      return Column(
        children: [
          _ActionTile(
            key: const ValueKey('mail-radar-range-selector'),
            title: '邮件雷达',
            value: checking || _changing
                ? '正在加载'
                : selected == 0
                ? '不使用'
                : '$selected 天',
            onTap: checking || _changing
                ? null
                : () => _choose(locked ? 0 : selected),
          ),
          if (coordinator.featureAvailabilityError != null)
            TextButton(
              key: const ValueKey('mail-radar-permission-retry'),
              onPressed: checking ? null : _prepare,
              child: const BnbuText('重新检查权限'),
            ),
        ],
      );
    },
  );
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.controller});

  final AppThemeModeController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(0, tokens.space12, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: BnbuText(
                '显示主题',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: tokens.textSecondary,
                ),
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: controller.themeMode,
              onChanged: (value) {
                if (value != null) {
                  unawaited(controller.setThemeMode(value));
                }
              },
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    BnbuChoiceTile<ThemeMode>(
                      flat: true,
                      value: mode,
                      selected: mode == controller.themeMode,
                      title: BnbuText(_themeModeLabel(mode)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.controller});

  final AppLanguageController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => RadioGroup<AppLanguageMode>(
        groupValue: controller.mode,
        onChanged: (value) {
          if (value == null || value == controller.mode) return;
          unawaited(_changeLanguage(context, value));
        },
        child: Column(
          children: [
            for (final mode in AppLanguageMode.values.where(
              (mode) => mode != AppLanguageMode.system,
            ))
              BnbuChoiceTile<AppLanguageMode>(
                controlKey: ValueKey('app-language-${mode.name}'),
                value: mode,
                selected: mode == controller.mode,
                title: Text(_label(context, mode)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeLanguage(
    BuildContext context,
    AppLanguageMode mode,
  ) async {
    await controller.setMode(mode);
    if (!context.mounted) return;
    BnbuToast.show(context, _successMessage(mode), kind: BnbuToastKind.success);
  }

  String _successMessage(AppLanguageMode mode) {
    return switch (mode) {
      AppLanguageMode.system => 'Successfully switched to English',
      AppLanguageMode.chinese => '已成功切换简体中文',
      AppLanguageMode.traditionalChinese => '已成功切換繁體中文',
      AppLanguageMode.english => 'Successfully switched to English',
    };
  }

  String _label(BuildContext context, AppLanguageMode mode) {
    return switch (mode) {
      AppLanguageMode.system => 'English',
      AppLanguageMode.chinese => '简体中文',
      AppLanguageMode.traditionalChinese => '繁體中文',
      AppLanguageMode.english => 'English',
    };
  }
}

class _AppUpdateTile extends StatelessWidget {
  const _AppUpdateTile({
    required this.controller,
    required this.installedVersionLabel,
  });

  final AppUpdateController controller;
  final String installedVersionLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _ActionTile(
        key: const ValueKey('app-update-check-tile'),
        title: '检查更新',
        value: controller.statusLabel,
        isBusy: controller.isBusy && controller.state.release == null,
        onTap: () => _check(context),
      ),
    );
  }

  Future<void> _check(BuildContext context) async {
    final outcome = await controller.checkForUpdates();
    if (!context.mounted) return;
    switch (outcome) {
      case AppUpdateCheckOutcome.available:
        await showAppUpdateModal(
          context,
          controller: controller,
          installedVersionLabel: installedVersionLabel,
        );
      case AppUpdateCheckOutcome.upToDate:
        BnbuToast.show(context, '当前已是最新版本');
      case AppUpdateCheckOutcome.failed:
        BnbuToast.show(context, '检查更新失败', kind: BnbuToastKind.danger);
      case AppUpdateCheckOutcome.unsupported:
        BnbuToast.show(context, '当前平台不支持官网更新检查', kind: BnbuToastKind.warning);
    }
  }
}

class _LiquidGlassToggle extends StatelessWidget {
  const _LiquidGlassToggle({super.key, required this.controller});

  final AppThemeModeController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _ActionTile(
        title: '液态玻璃',
        switchValue: controller.liquidGlassEnabled,
        onSwitchChanged: (value) async {
          final applied = await controller.setLiquidGlassEnabled(value);
          if (!context.mounted || applied) {
            return;
          }
          BnbuToast.show(context, '系统暂不支持液态玻璃', kind: BnbuToastKind.warning);
        },
      ),
    );
  }
}

class _ScheduleTodayHighlightSettings extends StatelessWidget {
  const _ScheduleTodayHighlightSettings({super.key, required this.controller});

  final AppThemeModeController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.space16,
          tokens.space8,
          tokens.space16,
          tokens.space12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: BnbuText(
                    '突出显示今天',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Switch.adaptive(
                  key: const ValueKey('schedule-today-highlight-toggle'),
                  value: controller.scheduleTodayHighlightEnabled,
                  onChanged: (value) => unawaited(
                    controller.setScheduleTodayHighlightEnabled(value),
                  ),
                ),
              ],
            ),
            if (controller.scheduleTodayHighlightEnabled) ...[
              SizedBox(height: tokens.space8),
              Wrap(
                spacing: tokens.space8,
                runSpacing: tokens.space8,
                children: [
                  for (final accent in ScheduleTodayAccent.values)
                    _TodayAccentChoice(
                      controller: controller,
                      accent: accent,
                      selected: controller.scheduleTodayAccent == accent,
                      dark: dark,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayAccentChoice extends StatelessWidget {
  const _TodayAccentChoice({
    required this.controller,
    required this.accent,
    required this.selected,
    required this.dark,
  });

  final AppThemeModeController controller;
  final ScheduleTodayAccent accent;
  final bool selected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final color = switch (accent) {
      ScheduleTodayAccent.blue =>
        dark ? const Color(0xFF78B9FF) : const Color(0xFF075EA8),
      ScheduleTodayAccent.teal =>
        dark ? const Color(0xFF65D7C4) : const Color(0xFF087A6A),
      ScheduleTodayAccent.amber =>
        dark ? const Color(0xFFFFC85A) : const Color(0xFF8A5700),
      ScheduleTodayAccent.violet =>
        dark ? const Color(0xFFC2A3FF) : const Color(0xFF6741B0),
    };
    final label = switch (accent) {
      ScheduleTodayAccent.blue => '蓝色',
      ScheduleTodayAccent.teal => '青绿',
      ScheduleTodayAccent.amber => '琥珀',
      ScheduleTodayAccent.violet => '紫色',
    };
    return Semantics(
      selected: selected,
      label: context.l10n.text('今天强调色$label'),
      child: ChoiceChip(
        key: ValueKey('schedule-today-accent-${accent.name}'),
        selected: selected,
        onSelected: (_) => unawaited(controller.setScheduleTodayAccent(accent)),
        avatar: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        label: BnbuText(label),
        labelStyle: TextStyle(
          color: selected ? tokens.textPrimary : tokens.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _BiometricProtectionToggle extends StatelessWidget {
  const _BiometricProtectionToggle({super.key, required this.controller});

  final AppProtectionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _ActionTile(
        title: controller.settingLabel,
        switchValue: controller.enabled,
        isValueLoading: controller.isRestoring,
        isBusy: controller.isAuthenticating,
        onSwitchChanged: (value) async {
          final message = await controller.setEnabled(value);
          if (!context.mounted) return;
          if (message != null) {
            BnbuToast.show(
              context,
              context.l10n.text(message),
              kind: BnbuToastKind.warning,
            );
            return;
          }
          BnbuToast.show(
            context,
            context.l10n.text(
              '${controller.settingLabel}已${value ? '开启' : '关闭'}',
            ),
          );
        },
      ),
    );
  }
}

class _LiveActivitySettings extends StatelessWidget {
  const _LiveActivitySettings({super.key, required this.controller});

  static const _customOption = -1;

  final LiveActivityPreferenceController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        children: [
          _ActionTile(
            key: const ValueKey('ios-live-activity-enabled'),
            title: '灵动岛与锁屏提醒',
            switchValue: controller.enabled,
            onSwitchChanged: (value) {
              unawaited(controller.setEnabled(value));
            },
          ),
          if (controller.enabled) ...[
            _ActionTile(
              key: const ValueKey('ios-live-activity-course-enabled'),
              title: '课表上岛',
              switchValue: controller.courseEnabled,
              onSwitchChanged: (value) {
                unawaited(controller.setCourseEnabled(value));
              },
            ),
            if (controller.courseEnabled) ...[
              _ActionTile(
                key: const ValueKey('ios-live-activity-class-lead'),
                title: '上课提前时间',
                value: _classLeadLabel(controller.classLeadMinutes),
                onTap: () => _selectClassLead(context),
              ),
              _ActionTile(
                key: const ValueKey('ios-live-activity-course-dismiss-delay'),
                title: '上课后关闭',
                value: '${controller.courseDismissAfterStartMinutes} 分钟',
                onTap: () => _selectCourseDismissDelay(context),
              ),
            ],
            _ActionTile(
              key: const ValueKey('ios-live-activity-deadline-enabled'),
              title: 'DDL 上岛',
              switchValue: controller.deadlineEnabled,
              onSwitchChanged: (value) {
                unawaited(controller.setDeadlineEnabled(value));
              },
            ),
            if (controller.deadlineEnabled) ...[
              _ActionTile(
                key: const ValueKey('ios-live-activity-deadline-lead'),
                title: 'DDL 提前时间',
                value: _deadlineLeadLabel(controller.deadlineLeadMinutes),
                onTap: () => _selectDeadlineLead(context),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _selectClassLead(BuildContext context) async {
    var value = await _showLeadTimeSelector(
      context: context,
      title: '上课提前时间',
      options: LiveActivityPreferenceController.classLeadMinuteOptions,
      selected: controller.classLeadMinutes,
      labelFor: (value) => '提前 $value 分钟',
    );
    if (value == _customOption && context.mounted) {
      value = await _showCustomLeadTimeInput(
        context: context,
        title: '自定义上课提前时间',
        unit: '分钟',
        initialText: '${controller.classLeadMinutes}',
        minimum: LiveActivityPreferenceController.minimumCustomClassLeadMinutes
            .toDouble(),
        maximum: LiveActivityPreferenceController.maximumCustomClassLeadMinutes
            .toDouble(),
        rangeLabel:
            '${LiveActivityPreferenceController.minimumCustomClassLeadMinutes}–${LiveActivityPreferenceController.maximumCustomClassLeadMinutes}',
        allowDecimal: false,
        resultBuilder: (value) => value.round(),
      );
    }
    if (value != null) {
      await controller.setClassLeadMinutes(value);
    }
  }

  Future<void> _selectDeadlineLead(BuildContext context) async {
    var value = await _showLeadTimeSelector(
      context: context,
      title: 'DDL 提前时间',
      options: LiveActivityPreferenceController.deadlineLeadMinuteOptions,
      selected: controller.deadlineLeadMinutes,
      labelFor: _deadlineLeadLabel,
    );
    if (value == _customOption && context.mounted) {
      value = await _showCustomDeadlineLeadInput(
        context: context,
        initialMinutes: controller.deadlineLeadMinutes,
      );
    }
    if (value != null) {
      await controller.setDeadlineLeadMinutes(value);
    }
  }

  Future<void> _selectCourseDismissDelay(BuildContext context) async {
    final value = await _showCustomLeadTimeInput(
      context: context,
      title: '上课后关闭',
      unit: '分钟',
      initialText: '${controller.courseDismissAfterStartMinutes}',
      minimum: LiveActivityPreferenceController
          .minimumCourseDismissAfterStartMinutes
          .toDouble(),
      maximum: LiveActivityPreferenceController
          .maximumCourseDismissAfterStartMinutes
          .toDouble(),
      rangeLabel: '0–20',
      allowDecimal: false,
      resultBuilder: (value) => value.round(),
    );
    if (value != null) {
      await controller.setCourseDismissAfterStartMinutes(value);
    }
  }

  Future<int?> _showLeadTimeSelector({
    required BuildContext context,
    required String title,
    required List<int> options,
    required int selected,
    required String Function(int value) labelFor,
  }) {
    final choices = <int>[0, ...options, _customOption];
    final selectedChoice = choices.contains(selected)
        ? selected
        : _customOption;
    return showBnbuAdaptiveModal<int>(
      context: context,
      dialogMaxWidth: 420,
      dialogMaxHeight: 420,
      bottomSheetBackgroundColor: Colors.transparent,
      semanticLabel: title,
      contentKey: ValueKey('ios-live-activity-${title.hashCode}-modal'),
      builder: (modalContext, presentation) => BnbuModalFrame(
        showDividers: false,
        titleStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        presentation: presentation,
        title: title,
        bodyPadding: EdgeInsets.zero,
        child: RadioGroup<int>(
          groupValue: selectedChoice,
          onChanged: (value) {
            if (value != null) {
              Navigator.of(modalContext).pop(value);
            }
          },
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in choices)
                BnbuChoiceTile<int>(
                  controlKey: ValueKey('ios-live-activity-option-$option'),
                  value: option,
                  selected: option == selectedChoice,
                  title: BnbuText(switch (option) {
                    0 => '不提醒',
                    _customOption => '自定义',
                    _ => labelFor(option),
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _showCustomDeadlineLeadInput({
    required BuildContext context,
    required int initialMinutes,
  }) {
    return showBnbuCreationModal<int>(
      context: context,
      maxWidth: 460,
      maxHeight: 330,
      semanticLabel: context.l10n.text('自定义 DDL 提前时间'),
      contentKey: const ValueKey(
        'ios-live-activity-custom-deadline-time-modal',
      ),
      builder: (modalContext, presentation) =>
          _LiveActivityCustomDeadlineTimeInput(
            presentation: presentation,
            initialMinutes: initialMinutes,
          ),
    );
  }

  Future<int?> _showCustomLeadTimeInput({
    required BuildContext context,
    required String title,
    required String unit,
    required String initialText,
    required double minimum,
    required double maximum,
    required String rangeLabel,
    required bool allowDecimal,
    required int Function(double value) resultBuilder,
  }) {
    return showBnbuCreationModal<int>(
      context: context,
      maxWidth: 420,
      maxHeight: 300,
      semanticLabel: title,
      contentKey: const ValueKey('ios-live-activity-custom-time-modal'),
      builder: (modalContext, presentation) => _LiveActivityCustomTimeInput(
        presentation: presentation,
        title: title,
        unit: unit,
        initialText: initialText,
        minimum: minimum,
        maximum: maximum,
        rangeLabel: rangeLabel,
        allowDecimal: allowDecimal,
        resultBuilder: resultBuilder,
      ),
    );
  }

  String _classLeadLabel(int value) {
    return value == 0 ? '不提醒' : '提前 $value 分钟';
  }

  String _deadlineLeadLabel(int value) {
    if (value == 0) return '不提醒';
    final hours = value ~/ 60;
    final minutes = value % 60;
    if (hours == 0) return '提前 $minutes 分钟';
    if (minutes == 0) return '提前 $hours 小时';
    return '提前 $hours 小时 $minutes 分钟';
  }
}

class _LiveActivityCustomTimeInput extends StatefulWidget {
  const _LiveActivityCustomTimeInput({
    required this.presentation,
    required this.title,
    required this.unit,
    required this.initialText,
    required this.minimum,
    required this.maximum,
    required this.rangeLabel,
    required this.allowDecimal,
    required this.resultBuilder,
  });

  final BnbuAdaptiveModalPresentation presentation;
  final String title;
  final String unit;
  final String initialText;
  final double minimum;
  final double maximum;
  final String rangeLabel;
  final bool allowDecimal;
  final int Function(double value) resultBuilder;

  @override
  State<_LiveActivityCustomTimeInput> createState() =>
      _LiveActivityCustomTimeInputState();
}

class _LiveActivityCustomTimeInputState
    extends State<_LiveActivityCustomTimeInput> {
  late final TextEditingController _textController = TextEditingController(
    text: widget.initialText,
  );
  String? _errorText;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_textController.text);
    if (value == null || value < widget.minimum || value > widget.maximum) {
      setState(() {
        _errorText = '请输入 ${widget.rangeLabel} ${widget.unit}';
      });
      return;
    }
    Navigator.of(context).pop(widget.resultBuilder(value));
  }

  @override
  Widget build(BuildContext context) {
    final frame = BnbuCreationForm(
      title: widget.title,
      avoidKeyboard: false,
      action: BnbuCreationAction(
        key: const ValueKey('ios-live-activity-custom-time-save'),
        label: '保存',
        onPressed: _submit,
      ),
      child: BnbuCreationGroup(
        children: [
          TextField(
            key: const ValueKey('ios-live-activity-custom-time-input'),
            controller: _textController,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: widget.allowDecimal,
            ),
            inputFormatters: widget.allowDecimal
                ? null
                : [FilteringTextInputFormatter.digitsOnly],
            style: BnbuCreationStyle.fieldText(context),
            decoration: BnbuCreationStyle.input(
              context,
              hint: widget.unit,
              suffixText: widget.unit,
              errorText: _errorText,
              helperText: '${widget.rangeLabel} ${widget.unit}',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
    return _LiveActivityKeyboardSafeModal(
      presentation: widget.presentation,
      child: frame,
    );
  }
}

class _LiveActivityCustomDeadlineTimeInput extends StatefulWidget {
  const _LiveActivityCustomDeadlineTimeInput({
    required this.presentation,
    required this.initialMinutes,
  });

  final BnbuAdaptiveModalPresentation presentation;
  final int initialMinutes;

  @override
  State<_LiveActivityCustomDeadlineTimeInput> createState() =>
      _LiveActivityCustomDeadlineTimeInputState();
}

class _LiveActivityCustomDeadlineTimeInputState
    extends State<_LiveActivityCustomDeadlineTimeInput> {
  late final TextEditingController _hoursController = TextEditingController(
    text: widget.initialMinutes > 0 ? '${widget.initialMinutes ~/ 60}' : '0',
  );
  late final TextEditingController _minutesController = TextEditingController(
    text: widget.initialMinutes > 0 ? '${widget.initialMinutes % 60}' : '5',
  );
  String? _errorText;

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _submit() {
    final hours = int.tryParse(_hoursController.text);
    final minutes = int.tryParse(_minutesController.text);
    final totalMinutes = hours == null || minutes == null
        ? null
        : hours * 60 + minutes;
    if (hours == null ||
        minutes == null ||
        hours < 0 ||
        hours > 48 ||
        minutes < 0 ||
        minutes > 59 ||
        totalMinutes! <
            LiveActivityPreferenceController.minimumCustomDeadlineLeadMinutes ||
        totalMinutes > 2880) {
      setState(() {
        _errorText = '请输入 30 分钟至 48 小时';
      });
      return;
    }
    Navigator.of(context).pop(totalMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final frame = BnbuCreationForm(
      title: '自定义 DDL 提前时间',
      avoidKeyboard: false,
      action: BnbuCreationAction(
        key: const ValueKey('ios-live-activity-custom-deadline-time-save'),
        label: '保存',
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BnbuCreationGroup(
            children: [
              TextField(
                key: const ValueKey(
                  'ios-live-activity-custom-deadline-hours-input',
                ),
                controller: _hoursController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: BnbuCreationStyle.fieldText(context),
                decoration: BnbuCreationStyle.input(
                  context,
                  hint: '小时',
                  suffixText: 'h',
                ),
                onSubmitted: (_) => _submit(),
              ),
              TextField(
                key: const ValueKey(
                  'ios-live-activity-custom-deadline-minutes-input',
                ),
                controller: _minutesController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: BnbuCreationStyle.fieldText(context),
                decoration: BnbuCreationStyle.input(
                  context,
                  hint: '分钟',
                  suffixText: 'min',
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: BnbuText(
                _errorText!,
                style: TextStyle(fontSize: 13, color: context.bnbuTheme.danger),
              ),
            ),
        ],
      ),
    );
    return _LiveActivityKeyboardSafeModal(
      presentation: widget.presentation,
      child: frame,
    );
  }
}

class _LiveActivityKeyboardSafeModal extends StatelessWidget {
  const _LiveActivityKeyboardSafeModal({
    required this.presentation,
    required this.child,
  });

  final BnbuAdaptiveModalPresentation presentation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (presentation.isDialog) return child;
    return AnimatedPadding(
      key: const ValueKey('ios-live-activity-keyboard-safe-modal'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(
          context,
        ).bottom.clamp(0.0, double.infinity),
      ),
      child: child,
    );
  }
}

class _DeadlineReminderToggle extends StatelessWidget {
  const _DeadlineReminderToggle({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final AppSessionController controller;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _ActionTile(
        title: 'DDL 通知',
        switchValue: controller.isDeadlineReminderEnabled,
        isValueLoading: controller.isLoadingDeadlineReminderPreference,
        isBusy: controller.isUpdatingDeadlineReminder,
        onSwitchChanged: onChanged,
      ),
    );
  }
}

class _CourseReminderToggle extends StatelessWidget {
  const _CourseReminderToggle({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final AppSessionController controller;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _ActionTile(
        title: '课表通知',
        switchValue: controller.isCourseReminderEnabled,
        isValueLoading: controller.isLoadingCourseReminderPreference,
        isBusy: controller.isUpdatingCourseReminder,
        onSwitchChanged: onChanged,
      ),
    );
  }
}

class _NotificationContentSettings extends StatelessWidget {
  const _NotificationContentSettings({
    super.key,
    required this.controller,
    required this.onCourseChanged,
    required this.onDeadlineChanged,
  });

  final AppSessionController controller;
  final ValueChanged<bool> onCourseChanged;
  final ValueChanged<bool> onDeadlineChanged;

  static const _customOption = -1;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          children: [
            _CourseReminderToggle(
              key: const ValueKey('course-reminder-toggle'),
              controller: controller,
              onChanged: onCourseChanged,
            ),
            if (controller.isCourseReminderEnabled) ...[
              _ActionTile(
                key: const ValueKey('course-reminder-lead'),
                title: '课表通知时间',
                value: _courseLeadLabel(controller.courseReminderLeadMinutes),
                onTap: () => _selectCourseLead(context),
              ),
            ],
            _DeadlineReminderToggle(
              key: const ValueKey('deadline-reminder-toggle'),
              controller: controller,
              onChanged: onDeadlineChanged,
            ),
            if (controller.isDeadlineReminderEnabled) ...[
              _ActionTile(
                key: const ValueKey('deadline-reminder-lead'),
                title: 'DDL 通知设置',
                value: _deadlineReminderSettingsLabel(
                  context,
                  controller.deadlineReminderPreferences,
                ),
                onTap: () => _selectDeadlineLead(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectCourseLead(BuildContext context) async {
    var value = await _showLeadTimeSelector(
      context: context,
      title: '课表通知时间',
      options: DeadlineReminderService.courseLeadMinuteOptions,
      selected: controller.courseReminderLeadMinutes,
      labelFor: _courseLeadLabel,
    );
    if (value == _customOption && context.mounted) {
      value = await showBnbuCreationModal<int>(
        context: context,
        maxWidth: 420,
        maxHeight: 300,
        semanticLabel: context.l10n.text('自定义课表通知时间'),
        contentKey: const ValueKey('course-reminder-custom-time-modal'),
        builder: (modalContext, presentation) => _LiveActivityCustomTimeInput(
          presentation: presentation,
          title: '自定义课表通知时间',
          unit: '分钟',
          initialText: '${controller.courseReminderLeadMinutes}',
          minimum: DeadlineReminderService.minimumCourseLeadMinutes.toDouble(),
          maximum: DeadlineReminderService.maximumCourseLeadMinutes.toDouble(),
          rangeLabel:
              '${DeadlineReminderService.minimumCourseLeadMinutes}–${DeadlineReminderService.maximumCourseLeadMinutes}',
          allowDecimal: false,
          resultBuilder: (value) => value.round(),
        ),
      );
    }
    if (value == null) return;
    final message = await controller.setCourseReminderLeadMinutes(value);
    if (!context.mounted || message == null) return;
    BnbuToast.show(context, message, kind: BnbuToastKind.warning);
  }

  Future<void> _selectDeadlineLead(BuildContext context) async {
    final value = await showBnbuCreationModal<DeadlineReminderPreferences>(
      context: context,
      maxWidth: 520,
      maxHeight: 680,
      semanticLabel: context.l10n.text('DDL 通知设置'),
      contentKey: const ValueKey('deadline-reminder-settings-modal'),
      builder: (modalContext, presentation) => _DeadlineReminderSettingsEditor(
        presentation: presentation,
        initial: controller.deadlineReminderPreferences,
      ),
    );
    if (value == null) return;
    final message = await controller.setDeadlineReminderPreferences(value);
    if (!context.mounted || message == null) return;
    BnbuToast.show(context, message, kind: BnbuToastKind.warning);
  }

  Future<int?> _showLeadTimeSelector({
    required BuildContext context,
    required String title,
    required List<int> options,
    required int selected,
    required String Function(int value) labelFor,
  }) {
    final choices = <int>[...options, _customOption];
    final selectedChoice = choices.contains(selected)
        ? selected
        : _customOption;
    return showBnbuAdaptiveModal<int>(
      context: context,
      dialogMaxWidth: 420,
      dialogMaxHeight: 420,
      bottomSheetBackgroundColor: Colors.transparent,
      semanticLabel: context.l10n.text(title),
      contentKey: ValueKey('notification-${title.hashCode}-modal'),
      builder: (modalContext, presentation) => BnbuModalFrame(
        showDividers: false,
        titleStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        presentation: presentation,
        title: title,
        bodyPadding: EdgeInsets.zero,
        child: RadioGroup<int>(
          groupValue: selectedChoice,
          onChanged: (value) {
            if (value != null) Navigator.of(modalContext).pop(value);
          },
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in choices)
                BnbuChoiceTile<int>(
                  controlKey: ValueKey('notification-lead-option-$option'),
                  value: option,
                  selected: option == selectedChoice,
                  title: BnbuText(
                    option == _customOption ? '自定义' : labelFor(option),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _courseLeadLabel(int value) => '$value 分钟';

String _deadlineLeadLabel(int value) {
  final hours = value ~/ 60;
  final minutes = value % 60;
  if (hours == 0) return '$minutes 分钟';
  if (minutes == 0) return '$hours 小时';
  return '$hours 小时 $minutes 分钟';
}

String _deadlineReminderSettingsLabel(
  BuildContext context,
  DeadlineReminderPreferences value,
) {
  if (value.mode == DeadlineReminderMode.smart) {
    return context.l10n.text('智能提醒 · ${value.reminderCount} 次');
  }
  return value.fixedLeadMinutes
      .map((lead) => context.l10n.text(_deadlineLeadLabel(lead)))
      .join(context.l10n.isEnglish ? ', ' : '、');
}

class _DeadlineReminderSettingsEditor extends StatefulWidget {
  const _DeadlineReminderSettingsEditor({
    required this.presentation,
    required this.initial,
  });

  final BnbuAdaptiveModalPresentation presentation;
  final DeadlineReminderPreferences initial;

  @override
  State<_DeadlineReminderSettingsEditor> createState() =>
      _DeadlineReminderSettingsEditorState();
}

class _DeadlineReminderSettingsEditorState
    extends State<_DeadlineReminderSettingsEditor> {
  late DeadlineReminderMode _mode = widget.initial.mode;
  late int _reminderCount = widget.initial.reminderCount;
  late final Set<int> _fixedLeads = widget.initial.fixedLeadMinutes.toSet();
  late int _quietStartMinutes = widget.initial.quietStartMinutes;
  late int _quietEndMinutes = widget.initial.quietEndMinutes;
  final TextEditingController _hoursController = TextEditingController(
    text: '0',
  );
  final TextEditingController _minutesController = TextEditingController(
    text: '30',
  );
  bool _showCustomInput = false;
  String? _errorText;

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _toggleFixedLead(int value, bool selected) {
    setState(() {
      _errorText = null;
      if (selected) {
        if (_fixedLeads.length >= 3) {
          _errorText = '每个 DDL 最多提醒 3 次';
          return;
        }
        _fixedLeads.add(value);
      } else {
        _fixedLeads.remove(value);
      }
    });
  }

  void _addCustomLead() {
    final hours = int.tryParse(_hoursController.text);
    final minutes = int.tryParse(_minutesController.text);
    final total = hours == null || minutes == null
        ? null
        : hours * 60 + minutes;
    if (hours == null ||
        minutes == null ||
        hours < 0 ||
        hours > 48 ||
        minutes < 0 ||
        minutes > 59 ||
        total! < DeadlineReminderService.minimumDeadlineLeadMinutes ||
        total > DeadlineReminderService.maximumDeadlineLeadMinutes) {
      setState(() => _errorText = '请输入 30 分钟至 48 小时');
      return;
    }
    if (_fixedLeads.contains(total)) {
      setState(() => _errorText = '这个提醒时间已经添加');
      return;
    }
    if (_fixedLeads.length >= 3) {
      setState(() => _errorText = '每个 DDL 最多提醒 3 次');
      return;
    }
    setState(() {
      _fixedLeads.add(total);
      _showCustomInput = false;
      _errorText = null;
    });
  }

  Future<void> _pickQuietTime({required bool start}) async {
    final initialMinutes = start ? _quietStartMinutes : _quietEndMinutes;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinutes ~/ 60,
        minute: initialMinutes % 60,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (start) {
        _quietStartMinutes = value.hour * 60 + value.minute;
      } else {
        _quietEndMinutes = value.hour * 60 + value.minute;
      }
      _errorText = null;
    });
  }

  Future<void> _showSmartReminderExplanation() async {
    await showBnbuAdaptiveModal<void>(
      context: context,
      dialogMaxWidth: 480,
      dialogMaxHeight: 620,
      useRootNavigator: true,
      bottomSheetBackgroundColor: Colors.transparent,
      semanticLabel: context.l10n.text('智能提醒如何工作'),
      contentKey: const ValueKey('deadline-smart-explanation-modal'),
      builder: (modalContext, presentation) => BnbuModalFrame(
        showDividers: false,
        titleStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        presentation: presentation,
        title: '智能提醒如何工作',
        bottomBar: Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('deadline-smart-explanation-close'),
            onPressed: () => Navigator.of(modalContext).pop(),
            child: const BnbuText('知道了'),
          ),
        ),
        child: ListView(
          shrinkWrap: true,
          children: const [
            _DeadlineReminderExplanationItem(
              title: '默认三次提醒',
              body: '通常在截止前约 24 小时、8 小时和 2 小时提醒，也可以改为 1—3 次。',
            ),
            _DeadlineReminderExplanationItem(
              title: '自动避开免打扰',
              body: '默认免打扰为 00:00—06:00。落在这段时间的提醒会提前到免打扰开始前 10 分钟。',
            ),
            _DeadlineReminderExplanationItem(
              title: '睡前统一提醒',
              body: '免打扰期间至结束后 1 小时内到期的 DDL，会在免打扰前统一提醒；多项会合成一条。',
            ),
            _DeadlineReminderExplanationItem(
              title: '避免连续打扰',
              body: '调整后相距不足 2 小时的提醒会合并，汇总不会额外增加提醒次数。',
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_quietStartMinutes == _quietEndMinutes) {
      setState(() => _errorText = '免打扰开始和结束时间不能相同');
      return;
    }
    if (_mode == DeadlineReminderMode.fixed && _fixedLeads.isEmpty) {
      setState(() => _errorText = '请至少选择一个提醒时间');
      return;
    }
    final fixedLeads = _fixedLeads.toList()
      ..sort((left, right) => right.compareTo(left));
    Navigator.of(context).pop(
      DeadlineReminderPreferences(
        mode: _mode,
        reminderCount: _mode == DeadlineReminderMode.smart
            ? _reminderCount
            : fixedLeads.length,
        fixedLeadMinutes: fixedLeads,
        quietStartMinutes: _quietStartMinutes,
        quietEndMinutes: _quietEndMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final customLeads =
        _fixedLeads
            .where(
              (value) => !DeadlineReminderService.deadlineLeadMinuteOptions
                  .contains(value),
            )
            .toList()
          ..sort((left, right) => right.compareTo(left));
    Widget leadRow(int lead, {bool custom = false}) => Semantics(
      selected: _fixedLeads.contains(lead),
      child: BnbuCreationRow(
        key: ValueKey(
          custom ? 'deadline-custom-lead-$lead' : 'deadline-fixed-lead-$lead',
        ),
        label: _deadlineLeadLabel(lead),
        onTap: () => _toggleFixedLead(lead, !_fixedLeads.contains(lead)),
        value: custom
            ? IconButton(
                tooltip: context.l10n.text('删除'),
                onPressed: () => _toggleFixedLead(lead, false),
                icon: const Icon(LucideIcons.x300, size: 18),
              )
            : _fixedLeads.contains(lead)
            ? Icon(LucideIcons.check300, size: 18, color: tokens.brandBlue)
            : const SizedBox.shrink(),
      ),
    );
    Widget quietRow(bool start) => BnbuCreationRow(
      key: ValueKey(start ? 'deadline-quiet-start' : 'deadline-quiet-end'),
      label: start ? '开始时间' : '结束时间',
      onTap: () => _pickQuietTime(start: start),
      value: Text(
        _formatMinutesOfDay(start ? _quietStartMinutes : _quietEndMinutes),
        style: TextStyle(fontSize: 15, color: tokens.textSecondary),
      ),
    );
    final frame = BnbuCreationForm(
      title: 'DDL 通知设置',
      avoidKeyboard: false,
      action: BnbuCreationAction(
        key: const ValueKey('deadline-reminder-settings-save'),
        label: '保存',
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoSlidingSegmentedControl<DeadlineReminderMode>(
            key: const ValueKey('deadline-reminder-mode'),
            groupValue: _mode,
            backgroundColor: tokens.textMuted.withValues(alpha: .14),
            thumbColor: BnbuCreationStyle.group(context),
            children: const {
              DeadlineReminderMode.smart: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: BnbuText('智能提醒'),
              ),
              DeadlineReminderMode.fixed: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: BnbuText('固定提醒'),
              ),
            },
            onValueChanged: (value) {
              if (value != null) {
                setState(() {
                  _mode = value;
                  _errorText = null;
                });
              }
            },
          ),
          const SizedBox(height: 24),
          if (_mode == DeadlineReminderMode.smart)
            BnbuCreationGroup(
              children: [
                BnbuCreationRow(
                  label: '提醒次数',
                  value: CupertinoSlidingSegmentedControl<int>(
                    groupValue: _reminderCount,
                    backgroundColor: tokens.textMuted.withValues(alpha: .12),
                    thumbColor: BnbuCreationStyle.group(context),
                    children: {
                      for (final count in [1, 2, 3])
                        count: SizedBox(
                          key: ValueKey('deadline-reminder-count-$count'),
                          height: 36,
                          child: Center(
                            child: BnbuText(
                              '$count 次',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                    },
                    onValueChanged: (value) {
                      if (value != null) setState(() => _reminderCount = value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BnbuText(
                      switch (_reminderCount) {
                        1 => '约提前 2 小时',
                        2 => '约提前 24 小时、2 小时',
                        _ => '约提前 24 小时、8 小时、2 小时',
                      },
                      style: TextStyle(
                        fontSize: 14,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('deadline-smart-explanation'),
                      onPressed: _showSmartReminderExplanation,
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size(0, 44),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(LucideIcons.info300, size: 18),
                      label: const BnbuText('了解提醒逻辑'),
                    ),
                  ),
                ),
              ],
            )
          else
            BnbuCreationGroup(
              children: [
                for (final lead
                    in DeadlineReminderService.deadlineLeadMinuteOptions)
                  leadRow(lead),
                for (final lead in customLeads) leadRow(lead, custom: true),
                BnbuCreationRow(
                  key: const ValueKey('deadline-reminder-add-custom'),
                  label: '自定义时间',
                  onTap: () => setState(() {
                    _showCustomInput = !_showCustomInput;
                    _errorText = null;
                  }),
                  value: Icon(
                    _showCustomInput
                        ? LucideIcons.chevronUp300
                        : LucideIcons.plus300,
                    size: 18,
                  ),
                ),
                if (_showCustomInput) ...[
                  TextField(
                    key: const ValueKey('deadline-custom-hours-input'),
                    controller: _hoursController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: BnbuCreationStyle.fieldText(context),
                    decoration: BnbuCreationStyle.input(
                      context,
                      hint: '小时',
                      suffixText: 'h',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('deadline-custom-minutes-input'),
                    controller: _minutesController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: BnbuCreationStyle.fieldText(context),
                    decoration: BnbuCreationStyle.input(
                      context,
                      hint: '分钟',
                      suffixText: 'min',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: BnbuText(
                            '30 分钟—48 小时',
                            style: TextStyle(
                              fontSize: 13,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                        BnbuCreationAction(
                          key: const ValueKey('deadline-custom-add'),
                          label: '添加',
                          onPressed: _addCustomLead,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: BnbuText(
              '免打扰',
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            ),
          ),
          BnbuCreationGroup(children: [quietRow(true), quietRow(false)]),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: BnbuText(
                _errorText!,
                style: TextStyle(fontSize: 13, color: tokens.danger),
              ),
            ),
        ],
      ),
    );
    return _LiveActivityKeyboardSafeModal(
      presentation: widget.presentation,
      child: frame,
    );
  }
}

class _DeadlineReminderExplanationItem extends StatelessWidget {
  const _DeadlineReminderExplanationItem({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          BnbuText(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.bnbuTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMinutesOfDay(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.title,
    this.value,
    this.switchValue,
    this.isValueLoading = false,
    this.isBusy = false,
    this.isDanger = false,
    this.stackValueOnCompact = false,
    this.onTap,
    this.onSwitchChanged,
  });

  final String title;
  final String? value;
  final bool? switchValue;
  final bool isValueLoading;
  final bool isBusy;
  final bool isDanger;
  final bool stackValueOnCompact;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onSwitchChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final enabled = onTap != null || onSwitchChanged != null;
    final tapHandler = onSwitchChanged != null && switchValue != null
        ? () => onSwitchChanged!(!switchValue!)
        : onTap;
    final valueBelowTitle =
        value != null &&
        ((stackValueOnCompact && MediaQuery.sizeOf(context).width < 500) ||
            MediaQuery.textScalerOf(context).scale(16) > 22);
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: isDanger ? tokens.danger : tokens.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w400,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isBusy ? null : tapHandler,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BnbuText(
                        title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: !enabled
                              ? tokens.textMuted
                              : isDanger
                              ? tokens.danger
                              : tokens.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                      if (valueBelowTitle) ...[
                        const SizedBox(height: 4),
                        BnbuText(value!, style: valueStyle),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isBusy || isValueLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: BnbuActivityIndicator(color: tokens.textSecondary),
                  )
                else if (switchValue != null)
                  Switch.adaptive(
                    value: switchValue!,
                    onChanged: isBusy || isValueLoading
                        ? null
                        : onSwitchChanged,
                  )
                else if (value != null && !valueBelowTitle)
                  Expanded(
                    child: BnbuText(
                      value!,
                      textAlign: TextAlign.right,
                      style: valueStyle,
                    ),
                  ),
                if (enabled && switchValue == null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronRight300,
                    color: tokens.textMuted,
                    size: 17,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: BnbuText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: tokens.textMuted),
          ),
        ),
        SizedBox(width: tokens.space12),
        Expanded(
          child: BnbuText(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
