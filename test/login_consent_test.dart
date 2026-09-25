import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/login_page.dart';
import 'package:bnbu_me/pages/official_web_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/services/app_statistics_service.dart';
import 'package:bnbu_me/widgets/statistics_privacy_notice.dart';

import 'app_statistics_service_test.dart' show Store, Transport, Bridge;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('/System/Library/Fonts/STHeiti Light.ttc');
    if (await font.exists()) {
      for (final family in [
        'QA',
        'Roboto',
        'Ahem',
        '.SF Pro Text',
        '.SF Pro Display',
      ]) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.whereType<Map>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final checked in [false, true]) {
    testWidgets('Apple login includes statistics agreement checked=$checked', (
      tester,
    ) async {
      final disk = Store();
      final transport = Transport();
      final statistics = AppStatisticsService(
        store: disk,
        transport: transport,
        bridge: Bridge(),
        platform: TargetPlatform.iOS,
        versionLoader: () async => '1.2.4',
      );
      final controller = _LoginController(statisticsService: statistics);
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpLogin(tester, controller);
      expect(find.text(statisticsLoginSummary), findsOneWidget);
      await _capture(tester, 'login-statistics-notice');
      await _enterCredentials(tester);
      if (checked) {
        final toggle = find.byKey(
          const ValueKey('login-privacy-consent-toggle'),
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      if (!checked) {
        expect(find.text(statisticsPrivacyText), findsOneWidget);
        expect(disk.data, isEmpty);
        await _capture(tester, 'login-statistics-confirmation');
        await tester.tap(find.text('同意并登录'));
        await tester.pumpAndSettle();
      }
      expect(controller.loginCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        disk.data.values.single['consent_version'],
        statisticsConsentVersion,
      );
      expect(transport.calls, 0);
      expect(tester.takeException(), null);
    });
  }

  for (final width in [390.0, 900.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'privacy checkbox aligns with the form at $width dark=$dark',
        (tester) async {
          final controller = _LoginController();
          addTearDown(controller.dispose);
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await _pumpLogin(tester, controller, dark: dark);
          final checkbox = find.byKey(
            const ValueKey('login-privacy-checkbox-visual'),
          );
          final toggle = find.byKey(
            const ValueKey('login-privacy-consent-toggle'),
          );
          final button = find.byType(FilledButton);
          expect(tester.getTopLeft(checkbox).dx, tester.getTopLeft(button).dx);
          expect(tester.getSize(checkbox).width, closeTo(16.2, 0.01));
          expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
          expect(
            tester.getTopLeft(find.text('我已阅读并接受 ')).dx -
                tester.getTopRight(checkbox).dx,
            closeTo(8, 0.01),
          );
          expect(
            tester.widget<Checkbox>(find.byType(Checkbox)).side!.width,
            1.2,
          );
          await _capture(
            tester,
            'login-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('我已阅读并接受 '));
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
          expect(controller.loginCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'consent continues the pending sign in once and reaches the next page',
    (tester) async {
      final controller = _LoginController()..pending = Completer<void>();
      addTearDown(controller.dispose);
      await _pumpLogin(tester, controller);
      await _enterCredentials(tester);
      final submit = tester
          .widget<EditableText>(find.byType(EditableText).last)
          .onSubmitted!;
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(controller.loginCount, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      submit('');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await _capture(tester, 'login-consent-dialog');
      await tester.tap(find.text('同意并登录'));
      await tester.pumpAndSettle();
      expect(controller.loginCount, 1);
      expect(controller.usernameInput, 'student');
      expect(controller.passwordInput, ' 密码 päss  ');
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      submit('');
      await tester.pump();
      expect(controller.loginCount, 1);
      controller.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('fixture home'), findsOneWidget);
    },
  );

  testWidgets(
    'cancel and dismissal preserve credentials without consent or login',
    (tester) async {
      final controller = _LoginController();
      addTearDown(controller.dispose);
      await _pumpLogin(tester, controller);
      await _enterCredentials(tester);
      for (final cancelButton in [true, false]) {
        await tester.tap(find.text('登录'));
        await tester.pumpAndSettle();
        if (cancelButton) {
          await tester.tap(find.text('取消'));
        } else {
          await tester.tapAt(const Offset(2, 2));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(controller.loginCount, 0);
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).last)
              .controller!
              .text,
          ' 密码 päss  ',
        );
      }
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.loginCount, 1);
      expect(find.text('fixture home'), findsOneWidget);
    },
  );

  testWidgets('invalid form does not request consent or start login', (
    tester,
  ) async {
    final controller = _LoginController();
    addTearDown(controller.dispose);
    await _pumpLogin(tester, controller);
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.loginCount, 0);
  });

  testWidgets(
    'English keyboard submit opens readable consent and its in-app policy',
    (tester) async {
      final controller = _LoginController();
      addTearDown(controller.dispose);
      await _pumpLogin(tester, controller, locale: const Locale('en'));
      await _enterCredentials(tester);
      await tester.showKeyboard(find.byType(TextFormField).last);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Agree & Sign In'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('login-dialog-privacy-policy-link')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OfficialWebPage), findsOneWidget);
      expect(controller.loginCount, 0);
      Navigator.of(tester.element(find.byType(OfficialWebPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Agree & Sign In'));
      await tester.pumpAndSettle();
      expect(controller.loginCount, 1);
      expect(find.text('fixture home'), findsOneWidget);
    },
  );
}

Future<void> _pumpLogin(
  WidgetTester tester,
  _LoginController controller, {
  bool dark = false,
  Locale locale = const Locale('zh', 'CN'),
}) async {
  final theme = dark ? AppTheme.dark : AppTheme.light;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: BnbuLocalizations.supportedLocales,
      localizationsDelegates: const [
        BnbuLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'QA'),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'QA'),
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(
              theme.textTheme.labelLarge?.copyWith(fontFamily: 'QA'),
            ),
          ),
        ),
        dialogTheme: theme.dialogTheme.copyWith(
          titleTextStyle: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'QA',
          ),
          contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'QA',
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: theme.textButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(
              theme.textTheme.labelLarge?.copyWith(fontFamily: 'QA'),
            ),
          ),
        ),
      ),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('login-consent-preview'),
        child: child!,
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => controller.isLoggedIn
            ? const Scaffold(body: Text('fixture home'))
            : LoginPage(controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      AssetImage(
        dark
            ? 'assets/branding/new2.jpg'
            : 'assets/branding/login_hero_light.jpg',
      ),
      tester.element(find.byType(LoginPage)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterCredentials(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.first, 'student');
  await tester.enterText(fields.last, ' 密码 päss  ');
  await tester.ensureVisible(find.byType(FilledButton));
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('login-consent-preview')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/login-consent');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _LoginController extends AppSessionController {
  _LoginController({AppStatisticsService? statisticsService})
    : _statisticsOverride = statisticsService;
  final AppStatisticsService? _statisticsOverride;
  @override
  AppStatisticsService get statistics =>
      _statisticsOverride ?? super.statistics;
  int loginCount = 0;
  String? usernameInput;
  String? passwordInput;
  Completer<void>? pending;
  bool _loggedIn = false;
  @override
  bool get isLoggedIn => _loggedIn;
  @override
  Future<void> login({
    required String username,
    required String password,
    bool fromStorage = false,
    bool persistCredentials = true,
  }) async {
    loginCount++;
    usernameInput = username;
    passwordInput = password;
    if (pending != null) await pending!.future;
    _loggedIn = true;
    notifyListeners();
  }
}
