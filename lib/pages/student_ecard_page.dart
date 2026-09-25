import '../widgets/bnbu_menu.dart';
import '../widgets/bnbu_adaptive.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../widgets/assistant_context_scope.dart';
import '../theme/app_theme.dart';
import '../widgets/student_code39_barcode.dart';

import '../models/portal_account_profile.dart';
import '../models/timetable_data.dart';
import '../models/ecard_gender_preferences.dart';
import '../services/ecard_gender_store.dart';
import '../services/ecard_brightness_controller.dart';
import '../services/ecard_wallet_service.dart';
import '../state/app_session_controller.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/ecard_wallet_consent.dart';

class StudentEcardPage extends StatefulWidget {
  const StudentEcardPage({
    super.key,
    required this.controller,
    required this.onGoToUser,
    this.brightnessController,
    this.walletFlow,
    this.genderStore,
  });

  final AppSessionController controller;
  final VoidCallback onGoToUser;
  final EcardBrightnessController? brightnessController;
  final EcardWalletFlow? walletFlow;
  final EcardGenderStore? genderStore;

  static bool supportsPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
  }

  @override
  State<StudentEcardPage> createState() => _StudentEcardPageState();
}

class _StudentEcardPageState extends State<StudentEcardPage>
    with WidgetsBindingObserver {
  VoidCallback? _releaseFloatingOverlay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _releaseFloatingOverlay ??=
        AssistantContextScope.maybePresentationControllerOf(
          context,
        )?.suppressFloatingOverlay();
  }

  late final EcardBrightnessController _brightnessController;
  late final EcardWalletFlow _walletFlow;
  AppSessionLease? _walletLease;
  DialogRoute<bool>? _walletConsentRoute;
  bool _walletAvailable = false;
  bool _walletBusy = false;
  late final EcardGenderStore _genderStore;
  AppSessionLease? _genderLease;
  EcardGenderPreferences _genderPreferences = const EcardGenderPreferences();
  bool _genderReady = false;
  int _genderLoad = 0;
  Future<void> _brightnessMutation = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _brightnessController =
        widget.brightnessController ?? PlatformEcardBrightnessController();
    _walletFlow = widget.walletFlow ?? EcardWalletFlow();
    _genderStore = widget.genderStore ?? EcardGenderStore.shared;
    _genderStore.addListener(_genderStoreChanged);
    widget.controller.addListener(_walletSessionChanged);
    _loadGenderPreferences();
    unawaited(_checkWalletAvailability());
    _queueBrightnessChange(bright: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.controller.isLoggedIn ||
          widget.controller.portalProfile != null ||
          widget.controller.isLoadingPortalProfile) {
        return;
      }
      unawaited(widget.controller.refreshPortalProfile());
    });
  }

  Future<void> _checkWalletAvailability() async {
    final available = await _walletFlow.platform.isAvailable();
    if (mounted) setState(() => _walletAvailable = available);
  }

  void _walletSessionChanged() {
    if (_walletLease != null && !_walletLease!.isActive) {
      _cancelWallet();
    }
    final current = widget.controller.captureSessionLease();
    if (_genderLease?.isActive != true ||
        current?.owner != _genderLease?.owner) {
      _loadGenderPreferences();
    }
  }

  void _genderStoreChanged() {
    if (!mounted) return;
    // Refresh local eCard editors. Wallet never exports gender preferences.
    _loadGenderPreferences();
  }

  void _loadGenderPreferences() {
    final generation = ++_genderLoad;
    _genderLease = widget.controller.captureSessionLease();
    _genderReady = false;
    _genderPreferences = const EcardGenderPreferences(visible: false);
    final lease = _genderLease;
    if (mounted) setState(() {});
    if (lease == null) return;
    unawaited(() async {
      try {
        final preferences = await _genderStore.read(lease.owner);
        if (!mounted || !lease.isActive || generation != _genderLoad) return;
        setState(() {
          _genderPreferences = preferences;
          _genderReady = true;
        });
      } catch (_) {
        if (!mounted || !lease.isActive || generation != _genderLoad) return;
        // Failed reads stay hidden; settings offer an explicit retry.
      }
    }());
  }

  StudentEcardData _displayData(StudentEcardData source) =>
      source.withGenderDisplay(
        _genderReady ? _genderPreferences.displayValue(source.gender) : null,
      );

  void _cancelWallet() {
    _walletFlow.cancel();
    final route = _walletConsentRoute;
    _walletConsentRoute = null;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route, false);
      });
    }
  }

  @override
  void didUpdateWidget(covariant StudentEcardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_walletSessionChanged);
      _cancelWallet();
      widget.controller.addListener(_walletSessionChanged);
      _loadGenderPreferences();
    }
  }

  Future<void> _addToWallet() async {
    if (_walletBusy) return;
    final controller = widget.controller;
    final lease = controller.captureSessionLease();
    if (lease == null) return;
    if (controller.isLoadingPortalProfile || controller.isLoadingPortalAvatar) {
      BnbuToast.show(context, context.l10n.text('请等待 eCard 资料加载完成'));
      return;
    }
    final data = StudentEcardData.fromController(controller);
    setState(() => _walletBusy = true);
    _walletLease = lease;
    try {
      final result = await _walletFlow.add(
        owner: lease.owner,
        card: data.walletCard(photo: controller.portalAvatarBytes),
        isCurrent: () =>
            mounted &&
            lease.isActive &&
            (ModalRoute.of(context)?.isCurrent == true ||
                _walletConsentRoute?.isCurrent == true),
        confirm: () async {
          if (!mounted || !lease.isActive) return false;
          final route = DialogRoute<bool>(
            context: context,
            builder: (_) => const EcardWalletConsentDialog(),
          );
          _walletConsentRoute = route;
          final accepted = await Navigator.of(
            context,
            rootNavigator: true,
          ).push(route);
          // Do not race the Flutter modal's dismissal with native presentation.
          await route.completed;
          if (identical(_walletConsentRoute, route)) _walletConsentRoute = null;
          return accepted == true;
        },
      );
      if (!mounted || !lease.isActive) return;
      if (result == EcardWalletResult.added) {
        BnbuToast.show(
          context,
          context.l10n.text('已添加到 Apple 钱包'),
          kind: BnbuToastKind.success,
        );
      } else if (result == EcardWalletResult.alreadyPresent) {
        BnbuToast.show(
          context,
          context.l10n.text('钱包中已有这张卡。更新条码需先在钱包移除旧卡，再重新添加。'),
        );
      }
    } on EcardWalletException catch (error) {
      if (!mounted || !lease.isActive) return;
      final message = switch (error.reason) {
        EcardWalletError.unavailable => '钱包签发服务尚未就绪，暂时无法添加',
        EcardWalletError.invalidCard => '无法生成钱包卡片，请刷新 eCard 后重试',
        EcardWalletError.network => '钱包请求未完成，请稍后重试',
        EcardWalletError.sessionChanged => '登录状态已变化，请重新打开 eCard',
        EcardWalletError.busy => '钱包正在处理中',
        EcardWalletError.layoutUnavailable => '钱包服务需要更新，请稍后重试',
      };
      BnbuToast.show(
        context,
        context.l10n.text(message),
        kind: BnbuToastKind.warning,
      );
    } finally {
      _walletLease = null;
      if (mounted) setState(() => _walletBusy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _queueBrightnessChange(bright: true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _queueBrightnessChange(bright: false);
    }
  }

  void _queueBrightnessChange({required bool bright}) {
    _brightnessMutation = _brightnessMutation.then((_) async {
      if (bright) {
        await _brightnessController.begin();
      } else {
        await _brightnessController.end();
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_walletSessionChanged);
    _genderLoad++;
    _genderStore.removeListener(_genderStoreChanged);
    _cancelWallet();
    _releaseFloatingOverlay?.call();
    WidgetsBinding.instance.removeObserver(this);
    _queueBrightnessChange(bright: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final data = _displayData(StudentEcardData.fromController(controller));
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: BnbuSecondaryAppBar(
            bar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              elevation: 0,
              toolbarHeight: 44,
              leadingWidth: 96,
              leading: Row(
                children: [
                  IconButton(
                    tooltip: context.l10n.text('返回'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const BnbuBackIcon(),
                  ),
                  IconButton(
                    key: const ValueKey('student-ecard-close'),
                    tooltip: context.l10n.text('关闭'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.x300),
                  ),
                ],
              ),
              actions: [
                BnbuMenuButton<String>(
                  tooltip: context.l10n.text('更多'),
                  icon: _walletBusy
                      ? const BnbuActivityIndicator(size: 20)
                      : const Icon(LucideIcons.ellipsis300),
                  onSelected: (value) {
                    if (value == 'wallet') {
                      unawaited(_addToWallet());
                    } else if (value == 'refresh') {
                      _loadGenderPreferences();
                      unawaited(controller.refreshPortalProfile());
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'refresh',
                      enabled: !_walletBusy,
                      child: BnbuText('刷新'),
                    ),
                    if (_walletAvailable && controller.isLoggedIn)
                      PopupMenuItem(
                        value: 'wallet',
                        enabled: !_walletBusy,
                        child: BnbuText(
                          _walletBusy ? '钱包正在处理中' : '添加到 Apple 钱包',
                        ),
                      ),
                  ],
                ),
              ],
              title: BnbuText(
                'BNBU Campus Card',
                style: TextStyle(
                  fontSize: BnbuHeaderMetrics.titleSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: controller.isLoggedIn
                ? StudentEcardView(
                    data: data,
                    avatarBytes: controller.portalAvatarBytes,
                    isLoadingAvatar:
                        controller.isLoadingPortalProfile ||
                        controller.isLoadingPortalAvatar,
                    onRefresh: _walletBusy
                        ? null
                        : controller.refreshPortalProfile,
                  )
                : _LoggedOutEcard(onGoToUser: widget.onGoToUser),
          ),
        );
      },
    );
  }
}

class StudentEcardData {
  const StudentEcardData({
    required this.fullName,
    required this.studentId,
    required this.department,
    required this.identity,
    required this.gender,
    this.residence = '',
    this.chineseName = '',
    this.englishName = '',
    this.showGender = true,
  });

  /// Display projection only: never mutate the controller's school records.
  StudentEcardData withGenderDisplay(String? value) => StudentEcardData(
    fullName: fullName,
    studentId: studentId,
    department: department,
    identity: identity,
    gender: value ?? '',
    showGender: value != null,
    residence: residence,
    chineseName: chineseName,
    englishName: englishName,
  );

  EcardWalletCard walletCard({Uint8List? photo}) => EcardWalletCard(
    fullName: fullName,
    chineseName: chineseName,
    englishName: englishName,
    studentId: studentId,
    department: department,
    identity: identity,
    photo: photo,
  );

  factory StudentEcardData.fromController(AppSessionController controller) {
    final timetable = controller.timetable;
    return StudentEcardData.fromSources(
      portal: controller.portalProfile,
      timetableProfile: timetable?.profile,
      timetableCourseCodes:
          timetable?.courses.map((course) => course.code) ?? const <String>[],
      sessionName: controller.session?.fullName.trim() ?? '',
      username: controller.username?.trim() ?? '',
    );
  }

  factory StudentEcardData.fromSources({
    PortalAccountProfile? portal,
    TimetableProfile? timetableProfile,
    Iterable<String> timetableCourseCodes = const <String>[],
    String sessionName = '',
    String username = '',
  }) {
    final portalName = portal?.fullName.trim() ?? '';
    final timetableName = timetableProfile?.name.trim() ?? '';
    final portalCollege = portal?.college.trim() ?? '';
    final portalDepartment = portal?.department.trim() ?? '';
    final timetableProgramme = timetableProfile?.programme.trim() ?? '';
    final timetableStudentId = timetableProfile?.studentId.trim() ?? '';
    return StudentEcardData(
      fullName: _firstNonEmpty([portalName, timetableName, sessionName, '学生']),
      chineseName: _firstNonEmpty(
        [
          portal?.chineseName ?? '',
          portalName,
          timetableName,
          sessionName,
        ].map(_chineseName),
      ),
      englishName: _firstNonEmpty(
        [
          portal?.englishName ?? '',
          portalName,
          timetableName,
          sessionName,
        ].map(_englishName),
      ),
      studentId: _firstNonEmpty([
        timetableStudentId,
        _studentIdFromUsername(username),
      ]),
      department: _collegeDisplayName(
        _firstNonEmpty([portalCollege, portalDepartment, timetableProgramme]),
      ),
      identity: _studentIdentity(
        portalIdentity: portal?.identity.trim() ?? '',
        studentLevel: portal?.studentLevel.trim() ?? '',
        timetableCourseCodes: timetableCourseCodes,
      ),
      gender: _displayGender(portal?.gender.trim() ?? ''),
      residence: portal?.residence.trim() ?? '',
    );
  }

  final String fullName;
  final String chineseName;
  final String englishName;
  final String studentId;
  final String department;
  final bool showGender;
  final String identity;
  final String gender;
  final String residence;

  String get barcodePayload =>
      StudentCode39Barcode.payloadForStudentId(studentId);

  static String _firstNonEmpty(Iterable<String> values) {
    return values
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '')
        .trim();
  }

  static String _studentIdFromUsername(String username) {
    final localPart = username.split('@').first.trim();
    return RegExp(r'^\d{6,20}$').hasMatch(localPart) ? localPart : '';
  }

  static String _displayGender(String value) {
    switch (value.trim().toLowerCase()) {
      case '男':
      case 'male':
      case 'm':
      case '0':
        return '男/MALE';
      case '女':
      case 'female':
      case 'f':
      case '1':
        return '女/FEMALE';
      default:
        return value.trim().isEmpty ? '--' : value.trim();
    }
  }

  static String _studentIdentity({
    required String portalIdentity,
    required String studentLevel,
    Iterable<String> timetableCourseCodes = const <String>[],
  }) {
    final source = '$studentLevel $portalIdentity'.trim().toLowerCase();
    final compact = source.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
    if (_containsPhrase(compact, const <String>[
          'researchpostgraduate',
          '研究型研究生',
          'rpgstudent',
          'mphil',
          'phd',
          '博士',
        ]) ||
        _containsToken(source, 'rpg')) {
      return 'BNBU Student RPG/STUDENT';
    }
    if (_containsPhrase(compact, const <String>[
          'taughtpostgraduate',
          '授课型研究生',
          'tpgstudent',
        ]) ||
        _containsToken(source, 'tpg')) {
      return 'BNBU Student TPG/STUDENT';
    }
    if (_containsPhrase(compact, const <String>[
          'undergraduate',
          '本科生',
          '本科',
          'ugstudent',
        ]) ||
        _containsToken(source, 'ug')) {
      return 'BNBU Student UG/STUDENT';
    }
    if (_containsPhrase(compact, const <String>[
          'postgraduate',
          'graduatestudent',
          '研究生',
          'pgstudent',
        ]) ||
        _containsToken(source, 'pg')) {
      return 'BNBU Student PG/STUDENT';
    }
    final courseLevel = _courseLevelFromCodes(timetableCourseCodes);
    if (courseLevel == 2) {
      return 'BNBU Student PG/STUDENT';
    }
    if (courseLevel == 1) {
      return 'BNBU Student UG/STUDENT';
    }
    return 'BNBU Student/STUDENT';
  }

  static int _courseLevelFromCodes(Iterable<String> courseCodes) {
    var hasUndergraduateCourse = false;
    for (final courseCode in courseCodes) {
      final normalized = courseCode.trim().toUpperCase().replaceAll(
        RegExp(r'[^A-Z0-9]'),
        '',
      );
      final match = RegExp(
        r'^[A-Z]{2,10}([0-9])[0-9]{3}[A-Z]?$',
      ).firstMatch(normalized);
      final level = int.tryParse(match?.group(1) ?? '');
      if (level == null) continue;
      if (level >= 7) {
        return 2;
      }
      if (level >= 1 && level <= 4) {
        hasUndergraduateCourse = true;
      }
    }
    return hasUndergraduateCourse ? 1 : 0;
  }

  static bool _containsPhrase(String source, Iterable<String> candidates) {
    return candidates.any(
      (candidate) => source.contains(
        candidate.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
          '',
        ),
      ),
    );
  }

  static bool _containsToken(String source, String token) {
    return RegExp(
      '(^|[^a-z0-9])${RegExp.escape(token)}([^a-z0-9]|\$)',
      caseSensitive: false,
    ).hasMatch(source);
  }

  static String _collegeDisplayName(String source) {
    final value = source.trim();
    if (value.isEmpty) return '--';
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
      ' ',
    );
    final compact = normalized.replaceAll(' ', '');
    const aliases = <String, List<String>>{
      'FST': <String>[
        'fst',
        'faculty of science and technology',
        '理工科技学院',
        'data science',
        '数据科学',
        'statistics',
        '统计',
        'computer science',
        '计算机',
        'mathematics',
        '数学',
        'environmental science',
        '环境科学',
        'food science',
        '食品科学',
        'life science',
        '生命科学',
      ],
      'FBM': <String>[
        'fbm',
        'faculty of business and management',
        '工商管理学院',
        'accounting',
        '会计',
        'finance',
        '金融',
        'economics',
        '经济',
        'marketing',
        '市场营销',
        'business management',
        '工商管理',
      ],
      'FHSS': <String>[
        'fhss',
        'faculty of humanities and social sciences',
        '人文社科学院',
        'translation',
        '翻译',
        'social work',
        '社会工作',
        'international relations',
        '国际关系',
      ],
      'SCC': <String>[
        'scc',
        'school of culture and creativity',
        '文化与创意学院',
        'cinema',
        '影视',
        'media arts',
        '媒体艺术',
        'culture and creativity',
        '文化创意',
      ],
      'SAI': <String>[
        'sai',
        'school of ai',
        '博雅智能学院',
        'artificial intelligence',
        '人工智能',
      ],
      'SGE': <String>['sge', 'school of general education', '通识教育学院'],
    };
    for (final entry in aliases.entries) {
      if (entry.value.any((alias) {
        final normalizedAlias = alias.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
          '',
        );
        return compact == normalizedAlias || compact.contains(normalizedAlias);
      })) {
        return entry.key;
      }
    }
    final acronym = RegExp(
      r'\b(FST|FBM|FHSS|SCC|SAI|SGE)\b',
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    return acronym?.toUpperCase() ?? '--';
  }
}

class StudentEcardView extends StatelessWidget {
  const StudentEcardView({
    super.key,
    required this.data,
    this.avatarBytes,
    this.isLoadingAvatar = false,
    this.onRefresh,
  });

  final StudentEcardData data;
  final Uint8List? avatarBytes;
  final bool isLoadingAvatar;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 380 ? 20.0 : 24.0;
        final barcodeWidth = (constraints.maxWidth - 2 * horizontalPadding)
            .clamp(0.0, 400.0);
        return SingleChildScrollView(
          key: const ValueKey('student-ecard-scroll-view'),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            26,
            horizontalPadding,
            14,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: _StudentPortrait(
                      avatarBytes: avatarBytes,
                      isLoading: isLoadingAvatar,
                      onRefresh: onRefresh,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (data.chineseName.isNotEmpty) ...[
                    BnbuText(
                      data.chineseName,
                      key: const ValueKey('student-ecard-chinese-name'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF292929),
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (data.englishName.isNotEmpty || data.chineseName.isEmpty)
                    BnbuText(
                      data.englishName.isNotEmpty
                          ? data.englishName
                          : data.fullName,
                      key: const ValueKey('student-ecard-name'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF292929),
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (data.studentId.isNotEmpty)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            key: const ValueKey('student-ecard-barcode'),
                            width: barcodeWidth,
                            height: 82,
                            child: StudentCode39Barcode(
                              payload: data.barcodePayload,
                              semanticsLabel: context.l10n.text(
                                '学号 Code 39 条码',
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            data.barcodePayload,
                            key: const ValueKey(
                              'student-ecard-barcode-payload',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF292929),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 108,
                      child: Center(
                        child: BnbuText(
                          '学号暂不可用',
                          style: TextStyle(color: tokens.textSecondary),
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  _EcardInfoRow(
                    icon: LucideIcons.usersRound300,
                    value: data.identity,
                  ),
                  const SizedBox(height: 8),
                  _EcardInfoRow(
                    icon: LucideIcons.network300,
                    value: data.department,
                    key: const ValueKey('student-ecard-department'),
                  ),
                  if (data.showGender) ...[
                    const SizedBox(height: 8),
                    _EcardInfoRow(
                      icon: LucideIcons.userRound300,
                      value: data.gender,
                      literal: true,
                      key: const ValueKey('student-ecard-gender'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _EcardInfoRow(
                    icon: LucideIcons.idCard300,
                    value: data.studentId.isEmpty ? '--' : data.studentId,
                    key: const ValueKey('student-ecard-student-id'),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFFE5E5E5), height: 1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudentPortrait extends StatelessWidget {
  const _StudentPortrait({
    required this.avatarBytes,
    required this.isLoading,
    required this.onRefresh,
  });

  final Uint8List? avatarBytes;
  final bool isLoading;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return SizedBox(
      key: const ValueKey('student-ecard-portrait'),
      width: 140,
      height: 154,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: ColoredBox(
              color: Colors.white,
              child: SizedBox.expand(
                child: avatarBytes == null
                    ? Icon(
                        LucideIcons.userRound300,
                        size: 54,
                        color: tokens.textMuted,
                      )
                    : Image.memory(
                        avatarBytes!,
                        fit: BoxFit.cover,
                        cacheWidth: 512,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Icon(
                          LucideIcons.userRound300,
                          size: 54,
                          color: tokens.textMuted,
                        ),
                      ),
              ),
            ),
          ),
          if (isLoading)
            const SizedBox.square(dimension: 28, child: BnbuActivityIndicator())
          else if (avatarBytes == null && onRefresh != null)
            Positioned(
              right: 4,
              bottom: 4,
              child: IconButton.filled(
                key: const ValueKey('student-ecard-refresh-photo'),
                tooltip: context.l10n.text('重新加载照片'),
                onPressed: () => unawaited(onRefresh!()),
                icon: const Icon(LucideIcons.refreshCw300, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

class _EcardInfoRow extends StatelessWidget {
  const _EcardInfoRow({
    super.key,
    required this.icon,
    required this.value,
    this.literal = false,
  });

  final IconData icon;
  final String value;
  final bool literal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF626262)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            literal ? value : context.l10n.text(value),
            style: TextStyle(
              color: const Color(0xFF626262),
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

String _chineseName(String value) => RegExp(
  r'[\u3400-\u9fff]+(?:[·•][\u3400-\u9fff]+)*',
).allMatches(value).map((m) => m.group(0)!).join('');
String _englishName(String value) => RegExp(
  r"[A-Za-z]+(?:[ .’'\-]+[A-Za-z]+)*",
).allMatches(value).map((m) => m.group(0)!.trim()).join(' ');

class _LoggedOutEcard extends StatelessWidget {
  const _LoggedOutEcard({required this.onGoToUser});

  final VoidCallback onGoToUser;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        key: const ValueKey('student-ecard-login'),
        onPressed: () {
          Navigator.of(context).maybePop();
          onGoToUser();
        },
        icon: const Icon(LucideIcons.logIn300),
        label: const BnbuText('登录后查看 eCard'),
      ),
    );
  }
}
