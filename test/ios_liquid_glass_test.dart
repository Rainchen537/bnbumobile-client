import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'compact navigation restores liquid glass and follows the persisted switch',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessionController = AppSessionController();
      final shellController = RootShellController();
      final mailIntentController = MailAssistantIntentController();
      final themeController = AppThemeModeController(
        liquidGlassSupportLoader: () async => true,
      );
      final taCourseController = TaCourseController(
        sessionController: sessionController,
      );
      addTearDown(sessionController.dispose);
      addTearDown(shellController.dispose);
      addTearDown(mailIntentController.dispose);
      addTearDown(themeController.dispose);
      addTearDown(taCourseController.dispose);

      await themeController.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => BnbuLiquidGlassScope(
            controller: themeController,
            child: child ?? const SizedBox.shrink(),
          ),
          home: RootShellPage(
            controller: sessionController,
            shellController: shellController,
            taCourseController: taCourseController,
            mailIntentController: mailIntentController,
            themeModeController: themeController,
            pageOverrideBuilder: (tab) =>
                SizedBox(key: ValueKey('liquid-glass-page-${tab.name}')),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('root-ios-liquid-glass-navigation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ios-liquid-glass-flutter-fallback')),
        findsOneWidget,
      );
      for (final label in ['首页', '邮箱', 'iSpace', '课表', '我的']) {
        expect(
          find.byKey(ValueKey('root-bottom-navigation-destination-$label')),
          findsOneWidget,
        );
      }
      expect(
        tester
            .getSize(find.byKey(const ValueKey('root-bottom-navigation')))
            .height,
        greaterThanOrEqualTo(64),
      );
      await tester.tap(
        find.byKey(const ValueKey('root-bottom-navigation-destination-邮箱')),
      );
      await tester.pumpAndSettle();
      expect(shellController.selectedIndex, 1);
      expect(
        tester
            .widget<Scaffold>(
              find.byKey(const ValueKey('root-compact-scaffold')),
            )
            .extendBody,
        isTrue,
      );

      await themeController.setLiquidGlassEnabled(false);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('root-ios-liquid-glass-navigation')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('root-bottom-navigation')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Scaffold>(
              find.byKey(const ValueKey('root-compact-scaffold')),
            )
            .extendBody,
        isFalse,
      );
    },
  );

  testWidgets(
    'iPhone home scrolls the campus wall above the floating glass navigation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessionController = AppSessionController();
      final shellController = RootShellController();
      final mailIntentController = MailAssistantIntentController();
      final themeController = AppThemeModeController(
        liquidGlassSupportLoader: () async => true,
      );
      final taCourseController = TaCourseController(
        sessionController: sessionController,
      );
      addTearDown(sessionController.dispose);
      addTearDown(shellController.dispose);
      addTearDown(mailIntentController.dispose);
      addTearDown(themeController.dispose);
      addTearDown(taCourseController.dispose);

      await themeController.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => BnbuLiquidGlassScope(
            controller: themeController,
            child: child ?? const SizedBox.shrink(),
          ),
          home: RootShellPage(
            controller: sessionController,
            shellController: shellController,
            taCourseController: taCourseController,
            mailIntentController: mailIntentController,
            themeModeController: themeController,
          ),
        ),
      );
      await tester.pump();

      final campusWall = find.byKey(const ValueKey('home-quick-action-朵朵校园墙'));
      final homeScrollView = find.descendant(
        of: find.byType(RootShellPage),
        matching: find.byKey(const ValueKey('home-scroll-view')),
      );
      await tester.fling(homeScrollView, const Offset(0, -1800), 3000);
      await tester.pumpAndSettle();

      final navigation = tester.getRect(
        find.byKey(const ValueKey('root-bottom-navigation')),
      );
      final campusWallRect = tester.getRect(campusWall);
      expect(campusWallRect.bottom, lessThanOrEqualTo(navigation.top));
    },
  );

  testWidgets('iPhone appearance page lets the user disable liquid glass', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sessionController = AppSessionController();
    final themeController = AppThemeModeController(
      liquidGlassSupportLoader: () async => true,
    );
    addTearDown(sessionController.dispose);
    addTearDown(themeController.dispose);

    await themeController.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => BnbuLiquidGlassScope(
          controller: themeController,
          child: child ?? const SizedBox.shrink(),
        ),
        home: UserPage(
          controller: sessionController,
          themeModeController: themeController,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('外观与语言'));
    await tester.pumpAndSettle();

    final setting = find.byKey(const ValueKey('ios-liquid-glass-setting'));
    expect(setting, findsOneWidget);
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: setting, matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );

    await tester.tap(
      find.descendant(of: setting, matching: find.byType(Switch)),
    );
    await tester.pump();

    expect(themeController.liquidGlassEnabled, isFalse);
  });

  testWidgets('high contrast replaces blur with an opaque glass fallback', (
    WidgetTester tester,
  ) async {
    final themeController = AppThemeModeController(
      liquidGlassSupportLoader: () async => true,
    );
    addTearDown(themeController.dispose);

    await themeController.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => BnbuLiquidGlassScope(
          controller: themeController,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const MediaQuery(
          data: MediaQueryData(highContrast: true),
          child: Scaffold(
            body: BnbuLiquidGlassSurface(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              child: SizedBox(width: 200, height: 80),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('ios-liquid-glass-high-contrast-fallback')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('older iOS reports unsupported instead of enabling fallback', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessionController = AppSessionController();
    final themeController = AppThemeModeController(
      liquidGlassSupportLoader: () async => false,
    );
    addTearDown(sessionController.dispose);
    addTearDown(themeController.dispose);
    await themeController.restore();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => BnbuLiquidGlassScope(
          controller: themeController,
          child: child ?? const SizedBox.shrink(),
        ),
        home: UserPage(
          controller: sessionController,
          themeModeController: themeController,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('外观与语言'));
    await tester.pumpAndSettle();

    final setting = find.byKey(const ValueKey('ios-liquid-glass-setting'));
    final toggle = find.descendant(of: setting, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();

    expect(themeController.liquidGlassEnabled, isFalse);
    expect(find.text('系统暂不支持液态玻璃'), findsOneWidget);
  });
}
