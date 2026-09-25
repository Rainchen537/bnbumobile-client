import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/login_page.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/state/app_language_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language preference restores and persists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppLanguageController();
    addTearDown(controller.dispose);

    await controller.restore(preferredLocales: const [Locale('zh', 'CN')]);
    expect(controller.mode, AppLanguageMode.chinese);
    expect(controller.locale, const Locale('zh', 'CN'));

    await controller.setMode(AppLanguageMode.english);
    expect(controller.locale, const Locale('en'));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(AppLanguageController.preferenceKey),
      AppLanguageMode.english.name,
    );
  });

  test(
    'legacy system preference migrates to a concrete device language',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppLanguageController.preferenceKey: AppLanguageMode.system.name,
      });
      final controller = AppLanguageController();
      addTearDown(controller.dispose);

      await controller.restore(preferredLocales: const [Locale('zh', 'HK')]);

      expect(controller.mode, AppLanguageMode.traditionalChinese);
      expect(controller.locale, const Locale('zh', 'TW'));
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(AppLanguageController.preferenceKey),
        AppLanguageMode.traditionalChinese.name,
      );
    },
  );

  test('Traditional Chinese preference resolves to a Taiwan locale', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppLanguageController();
    addTearDown(controller.dispose);

    await controller.setMode(AppLanguageMode.traditionalChinese);

    expect(controller.locale, const Locale('zh', 'TW'));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(AppLanguageController.preferenceKey),
      AppLanguageMode.traditionalChinese.name,
    );
  });

  test('unsupported device languages fall back to English', () {
    expect(
      basicLocaleListResolution(const <Locale>[
        Locale('fr'),
      ], BnbuLocalizations.supportedLocales),
      const Locale('en'),
    );
  });

  test('date labels follow the selected app language and available space', () {
    final value = DateTime(2026, 8, 31, 14, 5);
    const english = BnbuLocalizations(Locale('en'));
    const simplified = BnbuLocalizations(Locale('zh', 'CN'));
    const traditional = BnbuLocalizations(Locale('zh', 'TW'));

    expect(english.formatMonth(value), 'AUG');
    expect(english.formatMonthDay(value), 'Aug 31');
    expect(english.formatMonthDayTime(value), 'Aug 31, 14:05');
    expect(english.formatMediumDate(value), 'Aug 31, 2026');
    expect(english.formatFullDate(value), 'August 31, 2026');
    expect(english.formatMediumDateTime(value), 'Aug 31, 2026, 14:05');
    expect(english.formatFullDateTime(value), 'August 31, 2026, 14:05');
    expect(english.formatWeekday(value), 'Monday');
    expect(english.formatMonthDayWithWeekday(value), 'Monday, August 31');
    expect(english.text('Aug 31 所在周'), 'Week of Aug 31');
    expect(english.text('5–120 分钟'), '5–120 minutes');
    expect(english.text('请输入 5–120 分钟'), 'Enter 5–120 minutes');

    for (final chinese in <BnbuLocalizations>[simplified, traditional]) {
      expect(chinese.formatMonth(value), '08');
      expect(chinese.formatMonthDay(value), '8月31日');
      expect(chinese.formatMonthDayTime(value), '8月31日 14:05');
      expect(chinese.formatMediumDate(value), '2026年8月31日');
      expect(chinese.formatFullDateTime(value), '2026年8月31日 14:05');
      expect(chinese.formatWeekday(value), '周一');
      expect(chinese.formatMonthDayWithWeekday(value), '8月31日 周一');
    }
  });

  test('system language follows only the device primary language', () {
    expect(
      AppLanguageController.resolveSystemLocale(const [Locale('zh', 'CN')]),
      const Locale('zh', 'CN'),
    );
    expect(
      AppLanguageController.resolveSystemLocale(const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ]),
      const Locale('zh', 'CN'),
    );
    expect(
      AppLanguageController.resolveSystemLocale(const [Locale('zh', 'TW')]),
      const Locale('zh', 'TW'),
    );
    expect(
      AppLanguageController.resolveSystemLocale(const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]),
      const Locale('zh', 'TW'),
    );
    expect(
      AppLanguageController.resolveSystemLocale(const [
        Locale('fr'),
        Locale('zh', 'CN'),
      ]),
      const Locale('en'),
    );
    expect(
      AppLanguageController.resolveSystemLocale(const []),
      const Locale('en'),
    );
  });

  test('resolved interface language tags can be shared with Watch', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppLanguageController();
    addTearDown(controller.dispose);

    expect(
      controller.resolveInterfaceLanguageTag(const [Locale('zh', 'HK')]),
      'zh-Hant',
    );
    expect(controller.resolveInterfaceLanguageTag(const [Locale('ja')]), 'en');

    await controller.setMode(AppLanguageMode.chinese);
    expect(
      controller.resolveInterfaceLanguageTag(const [Locale('en')]),
      'zh-Hans',
    );
    await controller.setMode(AppLanguageMode.english);
    expect(
      controller.resolveInterfaceLanguageTag(const [Locale('zh', 'TW')]),
      'en',
    );
  });

  test('system Traditional Chinese resolves to the Hant locale', () {
    expect(
      basicLocaleListResolution(const <Locale>[
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ], BnbuLocalizations.supportedLocales),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
  });

  testWidgets('English locale translates shared interface text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              BnbuText('通知与同步'),
              BnbuText('课表通知时间'),
              BnbuText('DDL 通知时间'),
              BnbuText('DDL 通知设置'),
              BnbuText('智能提醒 · 3 次'),
              BnbuText('约提前 24 小时、8 小时、2 小时'),
              BnbuText('翻译'),
              BnbuText('该教师可能未被学校收录'),
              BnbuText(
                '小U会分析所选时间范围内的邮件主题、正文和安全附件，生成摘要、优先级、截止时间与下一步行动；与当前界面语言不同的邮件会翻译为当前界面语言，已包含完整当前语言内容的邮件不会重复翻译。',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Notifications & Sync'), findsOneWidget);
    expect(find.text('Class Notification Time'), findsOneWidget);
    expect(find.text('Deadline Notification Time'), findsOneWidget);
    expect(find.text('Deadline Notification Settings'), findsOneWidget);
    expect(find.text('Smart · 3 reminders'), findsOneWidget);
    expect(find.text('About 24, 8, and 2 hours before'), findsOneWidget);
    expect(find.text('Translation'), findsOneWidget);
    expect(
      find.text('This instructor may not be listed in the school directory'),
      findsOneWidget,
    );
    expect(
      find.textContaining('translated into the selected app language'),
      findsOneWidget,
    );
    expect(find.text('通知与同步'), findsNothing);
  });

  testWidgets('English navigation names the schedule Timetable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              BnbuText('首页'),
              BnbuText('邮箱'),
              Text('iSpace'),
              BnbuText('课表'),
              BnbuText('我的'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('iSpace'), findsOneWidget);
    expect(find.text('Timetable'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Schedule'), findsNothing);
  });

  testWidgets('Traditional Chinese converts shared interface text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh', 'TW'),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              BnbuText('首页'),
              BnbuText('课表'),
              BnbuText('通知与同步'),
              BnbuText('该教师可能未被学校收录'),
              BnbuText('显示密码'),
              BnbuText('隐藏密码'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('首頁'), findsOneWidget);
    expect(find.text('課表'), findsOneWidget);
    expect(find.text('通知與同步'), findsOneWidget);
    expect(find.text('該教師可能未被學校收錄'), findsOneWidget);
    expect(find.text('顯示密碼'), findsOneWidget);
    expect(find.text('隱藏密碼'), findsOneWidget);
  });

  testWidgets('login form follows the selected language', (
    WidgetTester tester,
  ) async {
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
        home: LoginPage(controller: controller),
      ),
    );

    expect(find.text('User Id'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('language can be changed from the Me settings', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppLanguageController.preferenceKey: AppLanguageMode.english.name,
    });
    final languageController = AppLanguageController();
    final sessionController = AppSessionController();
    addTearDown(languageController.dispose);
    addTearDown(sessionController.dispose);
    await languageController.restore();

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: languageController,
        builder: (context, _) => MaterialApp(
          locale: languageController.locale,
          supportedLocales: BnbuLocalizations.supportedLocales,
          localizationsDelegates: const [
            BnbuLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          home: UserPage(
            controller: sessionController,
            languageController: languageController,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Appearance & Language'), findsOneWidget);
    await tester.tap(find.text('Appearance & Language'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Language'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('app-language-system')), findsNothing);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('app-language-traditionalChinese')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(languageController.mode, AppLanguageMode.traditionalChinese);
    expect(languageController.locale, const Locale('zh', 'TW'));
    expect(find.text('已成功切換繁體中文'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('bnbu-notice'))),
      matchesSemantics(label: '已成功切換繁體中文', isLiveRegion: true),
    );
    expect(find.byKey(const ValueKey('app-language-system')), findsNothing);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('繁體中文'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-language-english')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(languageController.mode, AppLanguageMode.english);
    expect(languageController.locale, const Locale('en'));
    expect(find.text('Successfully switched to English'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('bnbu-notice'))),
      matchesSemantics(
        label: 'Successfully switched to English',
        isLiveRegion: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('app-language-chinese')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(languageController.mode, AppLanguageMode.chinese);
    expect(languageController.locale, const Locale('zh', 'CN'));
    expect(find.text('已成功切换简体中文'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('bnbu-notice'))),
      matchesSemantics(label: '已成功切换简体中文', isLiveRegion: true),
    );

    await tester.tap(
      find.byKey(const ValueKey('app-language-traditionalChinese')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(languageController.mode, AppLanguageMode.traditionalChinese);
    expect(languageController.locale, const Locale('zh', 'TW'));
    expect(find.text('已成功切換繁體中文'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('bnbu-notice'))),
      matchesSemantics(label: '已成功切換繁體中文', isLiveRegion: true),
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(AppLanguageController.preferenceKey),
      AppLanguageMode.traditionalChinese.name,
    );

    Navigator.of(
      tester.element(
        find.byKey(const ValueKey('app-language-traditionalChinese')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('appearance-language-setting')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('appearance-language-setting')),
        matching: find.text('繁體中文'),
      ),
      findsOneWidget,
      reason: '返回外观与语言页后，应立即显示刚刚选择的语言',
    );
    semantics.dispose();
  });

  testWidgets('compact English Me settings keep complete labels', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppLanguageController.preferenceKey: AppLanguageMode.english.name,
    });
    final languageController = AppLanguageController();
    final sessionController = AppSessionController();
    addTearDown(languageController.dispose);
    addTearDown(sessionController.dispose);
    await languageController.restore();

    await tester.pumpWidget(
      MaterialApp(
        locale: languageController.locale,
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: UserPage(
          controller: sessionController,
          languageController: languageController,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in <String>[
      'Notifications & Sync',
      'Appearance & Language',
      'About',
      'Account & Security',
      'Follow System',
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$label must remain fully visible at compact phone width',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
