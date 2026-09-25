import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/state/app_update_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/app_update_prompt.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final release = AppUpdateRelease(
    platform: AppUpdatePlatform.android,
    version: '1.2.3',
    buildNumber: 2026082603,
    downloadUri: Uri.parse(
      'https://bnbu.yunwai.cloud/downloads/hands-bnbu-android.apk',
    ),
    releaseNotes: ['修复 Android 学校登录', '前往官网下载安装'],
  );

  testWidgets('automatic check offers later or official website', (
    tester,
  ) async {
    final driver = _PromptDriver(release);
    final controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(_TestApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-update-modal')), findsOneWidget);
    expect(find.text('1.2.3+2026082603'), findsOneWidget);
    expect(find.text('前往官网下载'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-later')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-update-open-website')));
    await tester.pumpAndSettle();
    expect(driver.openWebsiteCount, 1);
    expect(find.byKey(const ValueKey('app-update-modal')), findsNothing);
  });

  testWidgets('user can defer the update until a later launch', (tester) async {
    final driver = _PromptDriver(release);
    final controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(_TestApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-update-later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-update-modal')), findsNothing);
    expect(driver.openWebsiteCount, 0);
  });

  testWidgets('website failure retries the external browser without download', (
    tester,
  ) async {
    final driver = _PromptDriver(release, failFirstOpen: true);
    final controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(_TestApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-update-open-website')));
    await tester.pumpAndSettle();

    expect(find.text('无法打开官网，请重试'), findsOneWidget);
    expect(driver.openWebsiteCount, 1);

    await tester.tap(find.byKey(const ValueKey('app-update-retry')));
    await tester.pumpAndSettle();
    expect(driver.openWebsiteCount, 2);
    expect(find.byKey(const ValueKey('app-update-modal')), findsNothing);
  });

  testWidgets('root listener presents through the navigator overlay context', (
    tester,
  ) async {
    final driver = _PromptDriver(release);
    final controller = AppUpdateController(driverFactory: () async => driver);
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.light,
        home: const Scaffold(body: SizedBox.expand()),
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            AppUpdatePromptListener(
              controller: controller,
              modalContextProvider: () =>
                  navigatorKey.currentState?.overlay?.context,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-update-modal')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in <(String, Size, bool)>[
    ('small phone', const Size(375, 812), false),
    ('phone landscape', const Size(844, 390), true),
  ]) {
    testWidgets('update prompt adapts on ${scenario.$1}', (tester) async {
      tester.view.physicalSize = scenario.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = _PromptDriver(release);
      final controller = AppUpdateController(driverFactory: () async => driver);
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(_TestApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app-update-modal')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
        scenario.$3 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(390, 844),
    const Size(900, 900),
    const Size(1440, 900),
  ]) {
    testWidgets(
      'Android update progress, cancellation and installation at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final verifiedRelease = AppUpdateRelease(
          platform: AppUpdatePlatform.android,
          version: '1.2.4',
          buildNumber: 2026090901,
          downloadUri: release.downloadUri,
          artifactSha256: 'a' * 64,
          artifactSize: 100,
        );
        final driver = _PromptDriver(verifiedRelease, inApp: true);
        final controller = AppUpdateController(
          driverFactory: () async => driver,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await tester.pumpWidget(_TestApp(controller: controller));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('app-update-download')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('app-update-open-website')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('app-update-download')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('app-update-progress')),
              )
              .value,
          .5,
        );
        expect(find.text('50%'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('app-update-cancel')));
        await tester.pumpAndSettle();
        expect(driver.cancelCount, 1);
        expect(
          find.byKey(const ValueKey('app-update-download')),
          findsOneWidget,
        );
        driver._setState(
          AppUpdateAwaitingInstall(verifiedRelease, permissionRequired: true),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('app-update-install')));
        await tester.pumpAndSettle();
        expect(driver.permissionRequested, isTrue);
        expect(find.text('重新安装'), findsOneWidget);
        expect(find.byKey(const ValueKey('app-update-modal')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 1.6]) {
    testWidgets('long version labels reflow without clipping at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppUpdateController(
        driverFactory: () async => _PromptDriver(release),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      const installed = '1.2.3+2026082602';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppUpdateModal(
                  context,
                  controller: controller,
                  installedVersionLabel: installed,
                ),
                child: const Text('Open update'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open update'));
      await tester.pumpAndSettle();
      for (final label in [installed, release.versionLabel]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        final lines = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            )
            .map((box) => box.top)
            .toSet();
        if (paragraph.getMaxIntrinsicWidth(double.infinity) <=
            paragraph.size.width) {
          expect(lines.length, 1, reason: 'Use the available full line.');
        }
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      expect(
        tester.getBottomLeft(find.text(installed)).dy,
        lessThan(tester.getTopLeft(find.text(release.versionLabel)).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [
    const Locale('en'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets(
      'Android installer guidance is localized in $locale at large text size',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final driver = _PromptDriver(release);
        final controller = AppUpdateController(
          driverFactory: () async => driver,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: locale,
            supportedLocales: BnbuLocalizations.supportedLocales,
            localizationsDelegates: const [
              BnbuLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: AppUpdatePromptListener(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        driver._setState(
          AppUpdateAwaitingInstall(release, permissionRequired: true),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(BnbuLocalizations(locale).text('允许安装')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.controller});

  final AppUpdateController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Stack(
          children: [
            const SizedBox.expand(),
            AppUpdatePromptListener(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _PromptDriver extends AppUpdateDriver {
  _PromptDriver(this.release, {this.failFirstOpen = false, this.inApp = false});

  final AppUpdateRelease release;
  final bool failFirstOpen;
  final bool inApp;
  int cancelCount = 0;
  bool permissionRequested = false;
  AppUpdateState _state = const AppUpdateIdle();
  int openWebsiteCount = 0;

  @override
  bool get supportsInAppUpdate => inApp;

  @override
  Future<void> downloadAndInstall() async =>
      _setState(AppUpdateDownloading(release, 50));

  @override
  void cancelDownload() {
    cancelCount++;
    _setState(AppUpdateAvailable(release));
  }

  @override
  Future<void> installUpdate({bool requestPermission = false}) async {
    permissionRequested = requestPermission;
    _setState(AppUpdateAwaitingInstall(release, permissionRequired: false));
  }

  @override
  AppUpdateState get state => _state;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUpdateCheckOutcome> check() async {
    _setState(AppUpdateAvailable(release));
    return AppUpdateCheckOutcome.available;
  }

  @override
  Future<void> openDownloadPage() async {
    openWebsiteCount += 1;
    if (failFirstOpen && openWebsiteCount == 1) {
      _setState(
        AppUpdateFailed(
          StateError('browser unavailable'),
          value: release,
          retryAction: AppUpdateRetryAction.openWebsite,
        ),
      );
      return;
    }
    _setState(AppUpdateAvailable(release));
  }

  void _setState(AppUpdateState value) {
    _state = value;
    notifyListeners();
  }
}
