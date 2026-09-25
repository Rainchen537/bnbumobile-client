import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/pages/duoduo_campus_wall_page.dart';
import 'package:bnbu_me/pages/home_page.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/pages/login_page.dart';
import 'package:bnbu_me/pages/official_web_page.dart';
import 'package:bnbu_me/pages/leave_application_page.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';
import 'package:bnbu_me/pages/ta_course_manager_page.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/services/login_input_source_controller.dart';
import 'package:bnbu_me/services/home_card_visibility_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';
import 'package:bnbu_me/widgets/campus_primary_navigation.dart';
import 'package:bnbu_me/widgets/moodle_activity_icon.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('Login page renders account form', (WidgetTester tester) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginPage(controller: controller),
      ),
    );

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('非官方客户端'), findsOneWidget);
    expect(find.textContaining('问题反馈'), findsNothing);
    final loginBrand = find.byKey(const ValueKey('login-brand-logo'));
    expect(loginBrand, findsOneWidget);
    final loginBrandLoader = tester.widget<SvgPicture>(loginBrand).bytesLoader;
    expect(loginBrandLoader, isA<SvgAssetLoader>());
    expect(
      (loginBrandLoader as SvgAssetLoader).assetName,
      'assets/branding/bnbu.svg',
    );
  });

  testWidgets('Logout closes the account route after the root becomes login', (
    WidgetTester tester,
  ) async {
    final controller = _LogoutNavigationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => controller.isLoggedIn
              ? UserPage(controller: controller)
              : LoginPage(controller: controller),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('账户与安全'));
    await tester.tap(find.text('账户与安全'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('退出登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('账户与安全'), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(LoginPage))).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(900, 800),
    const Size(1440, 900),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('Login theme and bottom footer at $size dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = AppSessionController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: LoginPage(controller: controller),
          ),
        );
        await tester.pump();
        final footer = tester.getRect(
          find.byKey(const ValueKey('login-footer-note')),
        );
        expect(footer.bottom, closeTo(size.height - 16, 1));
        expect(
          footer.top,
          greaterThan(tester.getBottomRight(find.byType(FilledButton)).dy),
        );
        final hero = tester.widget<Image>(
          find.byKey(const ValueKey('login-hero-image')),
        );
        expect(
          (hero.image as AssetImage).assetName,
          dark
              ? 'assets/branding/new2.jpg'
              : 'assets/branding/login_hero_light.jpg',
        );
        final logo = tester.widget<SvgPicture>(
          find.byKey(const ValueKey('login-brand-logo')),
        );
        expect(
          logo.colorFilter,
          ColorFilter.mode(
            dark ? Colors.white : const Color(0xFF0167A4),
            BlendMode.srcIn,
          ),
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(
          button.style!.backgroundColor!.resolve({}),
          const Color(0xFF0167A4),
        );
        expect(find.byIcon(LucideIcons.userRound200), findsOneWidget);
        expect(find.byIcon(LucideIcons.lockKeyhole200), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Compact login scrolls above the keyboard with large text and safe area',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppSessionController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 47, bottom: 34),
              viewInsets: EdgeInsets.only(bottom: 300),
              textScaler: TextScaler.linear(1.5),
            ),
            child: LoginPage(controller: controller),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pump();
      expect(
        tester.getBottomRight(find.byType(FilledButton)).dy,
        lessThanOrEqualTo(544),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Login preserves the password while keeping an ASCII username', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginPage(controller: controller),
      ),
    );

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    for (var index = 0; index < 2; index += 1) {
      final field = tester.widget<EditableText>(
        find.descendant(
          of: fields.at(index),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.keyboardType, TextInputType.visiblePassword);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);

      const input = TextEditingValue(
        text: 'BNBU中文-123! ',
        selection: TextSelection.collapsed(offset: 12),
      );
      final formatted = (field.inputFormatters ?? const <TextInputFormatter>[])
          .fold<TextEditingValue>(
            input,
            (value, formatter) =>
                formatter.formatEditUpdate(TextEditingValue.empty, value),
          );
      expect(formatted.text, index == 0 ? 'BNBU-123! ' : 'BNBU中文-123! ');
    }
  });

  testWidgets('Login password can be shown and hidden without changing it', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginPage(controller: controller),
      ),
    );

    final passwordField = find.byType(TextFormField).at(1);
    EditableText editablePassword() => tester.widget<EditableText>(
      find.descendant(of: passwordField, matching: find.byType(EditableText)),
    );

    await tester.enterText(passwordField, '密碼-A1!');
    expect(editablePassword().controller.text, '密碼-A1!');
    expect(editablePassword().obscureText, isTrue);
    expect(find.byTooltip('显示密码'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('login-password-visibility-toggle')),
    );
    await tester.pump();
    expect(editablePassword().controller.text, '密碼-A1!');
    expect(editablePassword().obscureText, isFalse);
    expect(find.byTooltip('隐藏密码'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('login-password-visibility-toggle')),
    );
    await tester.pump();
    expect(editablePassword().controller.text, '密碼-A1!');
    expect(editablePassword().obscureText, isTrue);
    expect(find.byTooltip('显示密码'), findsOneWidget);
  });

  testWidgets(
    'macOS login fields activate and restore the English input source',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const channel = MethodChannel(LoginInputSourceController.channelName);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return true;
          });
      try {
        final controller = AppSessionController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: LoginPage(controller: controller),
          ),
        );

        await tester.tap(find.byType(TextFormField).first);
        await tester.pump();
        expect(calls, contains('activateEnglishKeyboard'));

        tester.binding.focusManager.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pump();
        expect(calls, contains('restorePreviousKeyboard'));
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );

  testWidgets('Duoduo campus wall page renders its controlled shell', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const DuoduoCampusWallPage()),
      );

      expect(find.byType(DuoduoCampusWallPage), findsOneWidget);
      expect(find.text('朵朵校园墙'), findsWidgets);
      expect(find.byTooltip('刷新'), findsOneWidget);
      expect(find.byType(NativeMirrorWebView), findsOneWidget);
      expect(find.text('在系统浏览器中继续'), findsNothing);
      expect(find.text('使用系统浏览器打开'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Login privacy notice stays concise and opens in app', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginPage(controller: controller),
      ),
    );

    expect(find.text('我已阅读并接受 '), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.textContaining('用于多设备服务和经授权的学校管理'), findsNothing);
    expect(find.textContaining('最近活跃时间'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(
      tester.getTopLeft(find.byType(Checkbox)).dy,
      greaterThan(tester.getTopLeft(find.text('登录')).dy),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('login-privacy-policy-link')))
          .height,
      greaterThanOrEqualTo(BnbuSizeTokens.minInteractive),
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('login-privacy-policy-link')),
      ),
      matchesSemantics(
        label: '隐私政策',
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isLink: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('login-privacy-policy-link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(OfficialWebPage), findsOneWidget);
    expect(find.text('隐私政策'), findsWidgets);
    final checkbox = tester.widget<Checkbox>(
      find.byType(Checkbox, skipOffstage: false),
    );
    expect(checkbox.value, isFalse);
  });

  testWidgets('Login requires privacy acceptance without enabling sharing', (
    WidgetTester tester,
  ) async {
    final controller = _RecordingLoginController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginPage(controller: controller),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'student');
    await tester.enterText(fields.at(1), 'secret');
    await tester.ensureVisible(find.text('登录'));
    await tester.tap(find.text('登录'));
    await tester.pump();

    expect(controller.loginCount, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('同意并登录'));
    await tester.pump();

    expect(controller.loginCount, 1);
  });

  testWidgets('Login handles large text and keyboard without overflow', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
            viewInsets: EdgeInsets.only(bottom: 240),
          ),
          child: LoginPage(controller: controller),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('Home uses one service matrix without a top app bar', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );

    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.textContaining('课程与截止时间一览'), findsNothing);
    expect(find.text('查看本周课程与 DDL'), findsNothing);
    expect(find.text('课程、作业与资源'), findsNothing);
    expect(find.byType(BnbuSurfaceCard), findsAtLeastNWidgets(2));
    expect(find.byType(BnbuStatusBadge), findsNothing);
    expect(find.text('近期任务'), findsNothing);
    expect(find.text('下一节课'), findsOneWidget);
    expect(find.text('iSpace'), findsWidgets);
    expect(find.byKey(const ValueKey('home-next-course-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-recent-task-card')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-next-course-card')))
          .height,
      closeTo(
        tester
            .getSize(find.byKey(const ValueKey('home-recent-task-card')))
            .height,
        0.01,
      ),
    );
    expect(
      find.byKey(const ValueKey('home-quick-access-panel')),
      findsOneWidget,
    );
    expect(find.text('校园服务'), findsNothing);
    expect(find.text('快捷入口'), findsNothing);
    expect(find.byType(BnbuCompactActionTile), findsNothing);
    for (final title in [
      '政教信息',
      '统一门户',
      'iSpace',
      '校园导航',
      '官方地图',
      'MIS 教务',
      '公开目录',
      '校历',
      '绩点',
      '请假申请',
      'eCard',
      '朵朵校园墙',
    ]) {
      expect(find.byKey(ValueKey('home-quick-action-$title')), findsOneWidget);
    }
    final orderedQuickActions = find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('home-quick-action-');
        })
        .evaluate()
        .map((element) => (element.widget.key! as ValueKey<String>).value)
        .toList(growable: false);
    expect(
      orderedQuickActions.sublist(orderedQuickActions.length - 6),
      <String>[
        'home-quick-action-校历',
        'home-quick-action-绩点',
        'home-quick-action-请假申请',
        'home-quick-action-打卡查看',
        'home-quick-action-eCard',
        'home-quick-action-朵朵校园墙',
      ],
    );
    expect(find.text('完整课表'), findsNothing);

    final shortcutSize = tester.getSize(
      find.byKey(const ValueKey('home-quick-action-统一门户')),
    );
    expect(
      shortcutSize.width,
      isNot(closeTo(shortcutSize.height, 0.01)),
      reason: '校园服务入口保持横向信息块',
    );
  });

  testWidgets('Home keeps status countdowns outside the task title row', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );

    final title = find.text('登录后查看下一门课');
    final status = find.text('下一门课');
    expect(title, findsOneWidget);
    expect(status, findsOneWidget);
    expect(tester.getTopLeft(status).dy, lessThan(tester.getTopLeft(title).dy));
  });

  testWidgets('Home hides only remotely disabled allowlisted service cards', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);
    const visibility = HomeCardVisibility(
      version: 3,
      cards: {HomeServiceCard.duoduo: false},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
          homeCardVisibilityService: const _FixedHomeCardVisibilityService(
            visibility,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('home-quick-action-朵朵校园墙')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-quick-action-iSpace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-quick-access-panel')),
      findsOneWidget,
    );
  });

  testWidgets('Home DDL uses the shared type card with iSpace label', (
    WidgetTester tester,
  ) async {
    final controller = _VisualIspaceController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('timeline-summary-type-icon-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('timeline-summary-ispace-label-1')),
      findsOneWidget,
    );
  });

  testWidgets('English home service titles wrap without truncation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );
    await tester.pump();

    for (final entry in <String, String>{
      '校历': 'Academic Calendar',
      '朵朵校园墙': 'Duoduo Campus Wall',
    }.entries) {
      final titleFinder = find.byKey(
        ValueKey('home-service-title-${entry.key}'),
      );
      expect(titleFinder, findsOneWidget);
      final title = tester.widget<Text>(titleFinder);
      expect(title.data, entry.value);
      expect(title.overflow, isNot(TextOverflow.ellipsis));

      final fittedBox = find.ancestor(
        of: titleFinder,
        matching: find.byType(FittedBox),
      );
      expect(fittedBox, findsNothing);
      final tileRect = tester.getRect(
        find.byKey(ValueKey('home-quick-action-${entry.key}')),
      );
      final textRect = tester.getRect(titleFinder);
      expect(textRect.left, greaterThanOrEqualTo(tileRect.left));
      expect(textRect.right, lessThanOrEqualTo(tileRect.right));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home MIS shortcut opens the controlled official web page', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );

    final shortcut = find.byKey(const ValueKey('home-quick-action-MIS 教务'));
    await tester.ensureVisible(shortcut);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(shortcut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(OfficialWebPage), findsOneWidget);
    expect(find.text('MIS 教务系统'), findsOneWidget);
  });

  testWidgets('Home leave application reuses the controlled Portal page', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );

    final shortcut = find.byKey(const ValueKey('home-quick-action-请假申请'));
    await tester.ensureVisible(shortcut);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(shortcut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final page = tester.widget<LeaveApplicationPage>(
      find.byType(LeaveApplicationPage),
    );
    expect(page.controller, same(controller));
  });

  testWidgets('Home eCard shortcut opens before the campus wall entry', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );

    final shortcut = find.byKey(const ValueKey('home-quick-action-eCard'));
    await tester.ensureVisible(shortcut);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(shortcut);
    await tester.pumpAndSettle();

    expect(find.byType(StudentEcardPage), findsOneWidget);
    expect(find.text('BNBU Campus Card'), findsOneWidget);
    expect(find.text('登录后查看 eCard'), findsOneWidget);
  });

  testWidgets('iPad keeps the eCard shortcut and opens the full page', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );

    final shortcut = find.byKey(const ValueKey('home-quick-action-eCard'));
    expect(shortcut, findsOneWidget);
    await tester.ensureVisible(shortcut);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();

    expect(find.byType(StudentEcardPage), findsOneWidget);
    expect(find.text('BNBU Campus Card'), findsOneWidget);
  });

  testWidgets('desktop home does not expose the eCard shortcut', (
    WidgetTester tester,
  ) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: HomePage(
          controller: controller,
          onGoToIspace: () {},
          onGoToSchedule: () {},
          onGoToUser: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('home-quick-action-eCard')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-quick-action-朵朵校园墙')),
      findsOneWidget,
    );
  });

  test('eCard is limited to Android and iOS device families', () {
    expect(StudentEcardPage.supportsPlatform(TargetPlatform.android), isTrue);
    expect(StudentEcardPage.supportsPlatform(TargetPlatform.iOS), isTrue);
    expect(StudentEcardPage.supportsPlatform(TargetPlatform.macOS), isFalse);
    expect(StudentEcardPage.supportsPlatform(TargetPlatform.windows), isFalse);
    expect(StudentEcardPage.supportsPlatform(TargetPlatform.linux), isFalse);
    expect(StudentEcardPage.supportsPlatform(TargetPlatform.fuchsia), isFalse);
  });

  testWidgets('User profile is glass and settings are grouped', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessionController = AppSessionController();
    final themeController = AppThemeModeController();
    addTearDown(sessionController.dispose);
    addTearDown(themeController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: UserPage(
          controller: sessionController,
          themeModeController: themeController,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BackdropFilter), findsOneWidget);
    final brandMark = find.byKey(const ValueKey('user-hero-brand-mark'));
    final profileCard = find.byKey(const ValueKey('user-profile-card'));
    expect(brandMark, findsOneWidget);
    expect(profileCard, findsOneWidget);
    expect(
      find.descendant(of: profileCard, matching: brandMark),
      findsOneWidget,
      reason: '学校标志应位于资料卡内部',
    );
    expect(
      find.descendant(
        of: brandMark,
        matching: find.byKey(const ValueKey('user-hero-brand-logo')),
      ),
      findsOneWidget,
    );
    final profileBrand = tester.widget<SvgPicture>(
      find.byKey(const ValueKey('user-hero-brand-logo')),
    );
    expect(profileBrand.bytesLoader, isA<SvgAssetLoader>());
    expect(
      (profileBrand.bytesLoader as SvgAssetLoader).assetName,
      'assets/user/user_logo.svg',
    );
    expect(
      tester.getCenter(brandMark).dx,
      greaterThan(tester.getCenter(profileCard).dx),
      reason: '学校标志应位于资料卡右上角',
    );
    final header = find.byKey(const ValueKey('user-mobile-identity-header'));
    final headerRect = tester.getRect(header);
    expect(headerRect.height, closeTo(844 * 0.38, 1));
    expect(tester.getTopLeft(profileCard).dy, greaterThan(120));
    expect(tester.getBottomRight(profileCard).dy, lessThan(headerRect.bottom));
    expect(tester.getSize(profileCard).height, lessThanOrEqualTo(170));
    expect(
      find.descendant(of: profileCard, matching: find.byType(Divider)),
      findsNothing,
    );
    expect(
      find.descendant(of: profileCard, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('user-profile-bubble-arcs')),
      findsNothing,
    );
    final accountGroup = find.byKey(const ValueKey('user-account-group'));
    final preferencesGroup = find.byKey(
      const ValueKey('user-preferences-group'),
    );
    expect(
      tester.getBottomRight(preferencesGroup).dy,
      lessThan(tester.getTopLeft(accountGroup).dy),
    );
    expect(
      find.descendant(of: accountGroup, matching: find.text('账户与安全')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preferencesGroup, matching: find.text('通知与同步')),
      findsOneWidget,
    );
    expect(find.byType(Divider), findsNothing);
    for (final label in ['通知与同步', '外观与语言', '关于应用', '账户与安全']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final subtitle in [
      '校园卡与 iSpace 数据维护',
      'DDL 提醒与使用状态共享',
      '跟随系统 · 简体中文',
      '版本、隐私与应用信息',
      '当前 iSpace 会话与退出登录',
    ]) {
      expect(find.text(subtitle), findsNothing);
    }
    expect(find.text('校园服务'), findsNothing);
    expect(find.text('校园卡'), findsNothing);
    expect(find.text('DDL 提醒'), findsNothing);
    expect(find.text('我的'), findsNothing);
    expect(find.byIcon(LucideIcons.palette300), findsNothing);
    expect(find.byIcon(LucideIcons.bell300), findsNothing);
    expect(find.byIcon(LucideIcons.shieldCheck300), findsNothing);
    expect(find.byIcon(LucideIcons.chevronRight300), findsNWidgets(5));
    expect(find.text('个性化'), findsOneWidget);

    await tester.tap(find.text('外观与语言'));
    await tester.pumpAndSettle();
    expect(find.text('显示主题'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('突出显示今天'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-today-highlight-toggle')),
      findsOneWidget,
    );
    for (final label in ['蓝色', '青绿', '琥珀', '紫色']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('选择后立即应用，并在下次启动时保留。'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('schedule-today-accent-violet')),
    );
    await tester.pumpAndSettle();
    expect(themeController.scheduleTodayAccent, ScheduleTodayAccent.violet);

    await tester.tap(
      find.byKey(const ValueKey('schedule-today-highlight-toggle')),
    );
    await tester.pumpAndSettle();
    expect(themeController.scheduleTodayHighlightEnabled, isFalse);
    expect(find.text('蓝色'), findsNothing);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(themeController.themeMode, ThemeMode.dark);
  });

  testWidgets(
    'fixed schedule manager uses an in-page add action without a FAB',
    (WidgetTester tester) async {
      final sessionController = AppSessionController();
      final taController = TaCourseController(
        sessionController: sessionController,
      );
      addTearDown(sessionController.dispose);
      addTearDown(taController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TaCourseManagerPage(controller: taController),
        ),
      );
      await tester.pump();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('固定日程'), findsOneWidget);
      expect(find.text('暂无固定日程'), findsOneWidget);
      expect(find.text('新建日程'), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus300), findsOneWidget);
      expect(find.textContaining('右下角'), findsNothing);
    },
  );

  testWidgets('User and iSpace visual pages handle dark large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const mediaQuery = MediaQueryData(
      size: Size(390, 844),
      textScaler: TextScaler.linear(2),
    );

    final userController = AppSessionController();
    addTearDown(userController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: mediaQuery,
          child: UserPage(controller: userController),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('user-account-group')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-preferences-group')),
      findsOneWidget,
    );
    expect(find.text('iSpace account center'), findsNothing);

    final ispaceController = _VisualIspaceController();
    addTearDown(ispaceController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: mediaQuery,
          child: IspacePage(controller: ispaceController, onGoToUserTab: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('ispace-top-bar-navigation-button')),
      findsOneWidget,
    );
    expect(find.text('iSpace · Dashboard'), findsNothing);
  });

  testWidgets('iSpace activity icon is bare and follows the card accent', (
    WidgetTester tester,
  ) async {
    final controller = _VisualIspaceController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: IspacePage(controller: controller, onGoToUserTab: () {}),
      ),
    );
    await tester.pump();

    final iconFinder = find.byKey(
      const ValueKey('timeline-summary-type-icon-1'),
    );
    expect(iconFinder, findsOneWidget);
    final assignmentIcon = tester.widget<MoodleActivityIcon>(iconFinder);
    expect(assignmentIcon.color, BnbuColorTokens.brandBlue);
    expect(assignmentIcon.size, 17);
    expect(
      find.byKey(const ValueKey('timeline-summary-ispace-label-1')),
      findsNothing,
    );
  });

  testWidgets(
    'Mac iSpace moves refresh into navigation without an empty AppBar',
    (tester) async {
      final controller = _VisualIspaceController();
      addTearDown(controller.dispose);
      addTearDown(tester.view.reset);
      for (final width in [900.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: IspacePage(controller: controller, onGoToUserTab: () {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        final refresh = find.byKey(const ValueKey('ispace-workspace-refresh'));
        expect(refresh, findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
            matching: refresh,
          ),
          findsOneWidget,
        );
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('iSpace has one primary toolbar and a desktop refresh', (
    tester,
  ) async {
    final controller = _VisualIspaceController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.reset);
    for (final width in [390.0, 1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IspacePage(controller: controller, onGoToUserTab: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const ValueKey('ispace-primary-dashboard')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ispace-workspace-refresh')),
        width >= 700 ? findsOneWidget : findsNothing,
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('iSpace course group expands without leaving the todo canvas', (
    tester,
  ) async {
    final controller = _VisualIspaceController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.reset);
    for (final width in [390.0, 768.0, 900.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IspacePage(
            key: ValueKey(width),
            controller: controller,
            onGoToUserTab: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 880) {
        await tester.tap(
          find.byKey(const ValueKey('ispace-top-bar-navigation-button')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(const ValueKey('ispace-courses-navigation-group')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ispace-timeline-filter-control')),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
        width >= 880 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('iSpace site-page leaves do not repeat their navigation title', (
    WidgetTester tester,
  ) async {
    final controller = _VisualIspaceController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: IspacePage(controller: controller, onGoToUserTab: () {}),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    for (final title in const ['站点博客', '站点徽章', '标签', '站点公告']) {
      await tester.tap(find.text(title));
      await tester.pump();
      expect(find.text(title), findsOneWidget, reason: '$title 只应保留在导航中');
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(title)),
        findsNothing,
      );
    }
  });

  testWidgets('wide iSpace navigation clears the Pad status bar', (
    WidgetTester tester,
  ) async {
    final controller = _VisualIspaceController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1024, 900),
            padding: EdgeInsets.only(top: 24),
            viewPadding: EdgeInsets.only(top: 24),
          ),
          child: IspacePage(controller: controller, onGoToUserTab: () {}),
        ),
      ),
    );
    await tester.pump();

    final navigationPane = find.byKey(
      const ValueKey('ispace-desktop-navigation-pane'),
    );
    final timelineNavigationItem = find.byKey(
      const ValueKey('ispace-timeline-navigation-item'),
    );
    expect(
      tester.getTopLeft(timelineNavigationItem).dy -
          tester.getTopLeft(navigationPane).dy,
      closeTo(24, 0.1),
    );
  });

  testWidgets('Bottom navigation renders the shared compact reference shell', (
    WidgetTester tester,
  ) async {
    var selected = AppTab.home;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) => CampusPrimaryNavigation(
              wide: false,
              selectedTab: selected,
              onSelected: (tab) => setState(() => selected = tab),
            ),
          ),
        ),
      ),
    );

    final navigationBar = find.byKey(const ValueKey('root-bottom-navigation'));
    expect(find.byType(NavigationBar), findsNothing);
    for (final label in ['首页', '邮箱', 'iSpace', '课表', '我的']) {
      expect(
        find.descendant(of: navigationBar, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(tester.getSize(navigationBar).height, greaterThanOrEqualTo(64));
    expect(
      tester
          .widget<Icon>(
            find.byKey(const ValueKey('root-bottom-navigation-icon-首页')),
          )
          .size,
      20,
    );
    await tester.tap(
      find.byKey(const ValueKey('root-bottom-navigation-destination-邮箱')),
    );
    await tester.pump();
    expect(selected, AppTab.mail);
  });
}

class _FixedHomeCardVisibilityService implements HomeCardVisibilityService {
  const _FixedHomeCardVisibilityService(this.visibility);

  final HomeCardVisibility visibility;

  @override
  Future<HomeCardVisibility> load() async => visibility;

  @override
  void dispose() {}
}

class _VisualIspaceController extends AppSessionController {
  @override
  bool get isLoggedIn => true;

  @override
  List<TimelineItem> get timelineItems => [
    TimelineItem(
      id: 1,
      title: '课程作业提交',
      activityState: '作业',
      activityType: 'assign',
      moduleName: 'assign',
      description: '',
      courseName: '移动应用开发',
      courseId: 1,
      instanceId: 1,
      url: '/mod/assign/view.php?id=1',
      sortTime: DateTime.now().add(const Duration(days: 1)),
      formattedTime: '',
      isOverdue: false,
    ),
  ];
}

class _RecordingLoginController extends AppSessionController {
  int loginCount = 0;

  @override
  Future<void> login({
    required String username,
    required String password,
    bool fromStorage = false,
    bool persistCredentials = true,
  }) async {
    loginCount++;
  }
}

class _LogoutNavigationController extends AppSessionController {
  bool _loggedIn = true;
  @override
  bool get isLoggedIn => _loggedIn;
  @override
  Future<void> logout() async {
    _loggedIn = false;
    notifyListeners();
    // The root can dispose UserPage before asynchronous cleanup completes.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}
