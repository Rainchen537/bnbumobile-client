import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bnbu_me/state/app_protection_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/app_protection_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _preview = bool.fromEnvironment('APP_PROTECTION_PREVIEWS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!_preview) return;
    final font = ByteData.sublistView(
      await File('/System/Library/Fonts/SFNS.ttf').readAsBytes(),
    );
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(family)..addFont(Future.value(font))).load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
          rootBundle.load(
            'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
          ),
        ))
        .load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppProtectionController.enabledPreferenceKey: true,
    });
  });

  Future<void> pumpGate(
    WidgetTester tester,
    AppProtectionController controller, {
    double width = 402,
    double scale = 1,
    TargetPlatform platform = TargetPlatform.iOS,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh', 'CN'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: (brightness == Brightness.light ? AppTheme.light : AppTheme.dark)
            .copyWith(platform: platform),
        locale: locale,
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('app-protection-preview'),
          child: AppProtectionGate(
            controller: controller,
            child: const Text('protected content'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in [320.0, 375.0, 402.0, 430.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('iPhone $width $brightness enlarges and centers Face ID', (
        tester,
      ) async {
        final controller = AppProtectionController();
        addTearDown(controller.dispose);
        await pumpGate(
          tester,
          controller,
          width: width,
          brightness: brightness,
        );

        expect(
          tester.getSize(find.byKey(const ValueKey('app-protection-emblem'))),
          const Size(88, 88),
        );
        expect(
          tester.widget<Icon>(find.byIcon(LucideIcons.scanFace300)).size,
          42,
        );
        expect(tester.widget<Text>(find.text('BNBU.ME')).style!.fontSize, 26);
        expect(
          tester.getCenter(find.text('BNBU.ME')).dx,
          closeTo(width / 2, .01),
        );
        expect(
          tester.getCenter(find.byIcon(LucideIcons.scanFace300)).dx,
          closeTo(width / 2, .01),
        );
        expect(find.text('protected content'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (platform, width) in [
    (TargetPlatform.iOS, 768.0),
    (TargetPlatform.android, 402.0),
    (TargetPlatform.macOS, 1280.0),
  ]) {
    testWidgets('$platform $width retains existing sizes', (tester) async {
      final controller = AppProtectionController();
      addTearDown(controller.dispose);
      await pumpGate(tester, controller, platform: platform, width: width);
      expect(
        tester.getSize(find.byKey(const ValueKey('app-protection-emblem'))),
        const Size(72, 72),
      );
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.scanFace300)).size,
        34,
      );
      expect(tester.widget<Text>(find.text('BNBU.ME')).style!.fontSize, 22);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in BnbuLocalizations.supportedLocales) {
    testWidgets('large text and retry remain accessible in $locale', (
      tester,
    ) async {
      final authenticator = _PendingAuthenticator();
      final controller = AppProtectionController(authenticator: authenticator);
      addTearDown(controller.dispose);
      final initialized = controller.initialize();
      await pumpGate(tester, controller, width: 320, scale: 2, locale: locale);
      expect(controller.isAuthenticating, isTrue);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.widget<Text>(find.text('BNBU.ME')).style!.fontSize, 26);

      authenticator.pending.complete(BiometricAuthenticationResult.cancelled);
      await initialized;
      await tester.pump();
      expect(controller.isLocked, isTrue);
      expect(find.text('protected content'), findsNothing);
      final button = find.byKey(const ValueKey('app-protection-unlock-icon'));
      expect(button, findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
      final iconButton = tester.widget<IconButton>(button);
      final context = tester.element(button);
      expect(iconButton.tooltip, context.l10n.text(controller.unlockLabel));
      expect(
        find.text(context.l10n.text(controller.unlockLabel)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      authenticator.pending = Completer<BiometricAuthenticationResult>();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(controller.isAuthenticating, isTrue);
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      await tester.tap(button);
      await tester.pump();
      expect(authenticator.calls, 2);
      expect(find.text('protected content'), findsNothing);
      authenticator.pending.complete(BiometricAuthenticationResult.success);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('app-protection-lock-screen')),
        findsNothing,
      );
      expect(find.text('protected content'), findsOneWidget);
      expect(authenticator.calls, 2);
    });
  }

  for (final (width, type) in [
    (402.0, DeviceBiometricType.faceId),
    (820.0, DeviceBiometricType.touchId),
    (1194.0, DeviceBiometricType.touchId),
    (820.0, DeviceBiometricType.faceId),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('$width $type $brightness uses one accessible retry icon', (
        tester,
      ) async {
        final authenticator = _PendingAuthenticator(type: type);
        final controller = AppProtectionController(
          authenticator: authenticator,
        );
        addTearDown(controller.dispose);
        final initialized = controller.initialize();
        await pumpGate(
          tester,
          controller,
          width: width,
          brightness: brightness,
        );
        final button = find.byKey(const ValueKey('app-protection-unlock-icon'));
        expect(tester.widget<IconButton>(button).onPressed, isNull);
        authenticator.pending.complete(BiometricAuthenticationResult.failure);
        await initialized;
        await tester.pump();

        final icon = type == DeviceBiometricType.touchId
            ? LucideIcons.fingerprint300
            : LucideIcons.scanFace300;
        expect(find.byIcon(icon), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        expect(tester.getCenter(button).dx, closeTo(width / 2, .01));
        // The existing emblem has a 1px border; its entire interior is tappable.
        expect(
          tester.getRect(button),
          tester
              .getRect(find.byKey(const ValueKey('app-protection-emblem')))
              .deflate(1),
        );
        final label = tester.element(button).l10n.text(controller.unlockLabel);
        expect(find.text(label), findsNothing);
        expect(tester.widget<IconButton>(button).tooltip, label);
        expect(controller.message, isNotNull);
        expect(
          find.text(tester.element(button).l10n.text(controller.message!)),
          findsOneWidget,
        );
        final semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(button),
          matchesSemantics(
            tooltip: label,
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
          ),
        );
        semantics.dispose();

        authenticator.pending = Completer<BiometricAuthenticationResult>();
        await tester.tap(button);
        await tester.pump();
        expect(find.text('protected content'), findsNothing);
        authenticator.pending.complete(BiometricAuthenticationResult.success);
        await tester.pumpAndSettle();
        expect(find.text('protected content'), findsOneWidget);
        controller.lockForBackground();
        await tester.pumpAndSettle();
        expect(find.text('protected content'), findsNothing);
        expect(tester.widget<IconButton>(button).onPressed, isNotNull);
        expect(controller.message, isNull);
        expect(tester.takeException(), isNull);
        if (_preview) {
          await _savePreview(tester, '$width-${type.name}-${brightness.name}');
        }
      });
    }
  }

  testWidgets('Android retains the existing labelled retry button', (
    tester,
  ) async {
    final authenticator = _PendingAuthenticator();
    final controller = AppProtectionController(authenticator: authenticator);
    addTearDown(controller.dispose);
    final initialized = controller.initialize();
    await pumpGate(tester, controller, platform: TargetPlatform.android);
    authenticator.pending.complete(BiometricAuthenticationResult.cancelled);
    await initialized;
    await tester.pump();
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('使用 Face ID 解锁'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-protection-unlock-icon')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

class _PendingAuthenticator implements BiometricAuthenticator {
  _PendingAuthenticator({this.type = DeviceBiometricType.faceId});

  final DeviceBiometricType type;
  Completer<BiometricAuthenticationResult> pending = Completer();
  int calls = 0;

  @override
  Future<DeviceBiometricType> getAvailableType() async => type;

  @override
  Future<BiometricAuthenticationResult> authenticate({
    required String localizedReason,
  }) {
    calls++;
    return pending.future;
  }
}

Future<void> _savePreview(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('app-protection-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/app-protection-previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
