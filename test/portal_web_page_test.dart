import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/pages/official_web_page.dart';
import 'package:bnbu_me/services/portal_presentation.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lease implements AppSessionLease {
  @override
  bool get isActive => true;
  @override
  String get owner => 'synthetic-portal-layout';
}

class _Session extends AppSessionController {
  final lease = _Lease();
  @override
  bool get isLoggedIn => true;
  @override
  String get username => lease.owner;
  @override
  AppSessionLease captureSessionLease() => lease;
  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession(
    OfficialWebTarget target,
  ) async => WebSessionSnapshot(
    baseUrl: AppConfig.bnbuPortalBaseUrl,
    cookies: [
      WebSessionCookie(
        name: 'portal-session',
        value: 'synthetic',
        domain: Uri.parse(AppConfig.bnbuPortalBaseUrl).host,
        path: '/',
        hostOnly: true,
        secure: true,
        httpOnly: true,
      ),
    ],
    useEphemeralSession: true,
  );
}

void main() {
  test(
    'bundled Portal adapter carries only the origin, theme and labels',
    () async {
      final adapter = await PortalPresentation.load();
      final script = adapter.script(
        portal: Uri.parse('${AppConfig.bnbuPortalBaseUrl}/wui/index.html'),
        enabled: false,
        dark: true,
      );
      expect(script, contains('"origin":"${AppConfig.bnbuPortalBaseUrl}"'));
      expect(script, contains('"enabled":false'));
      expect(script, contains('"dark":true'));
      expect(
        adapter.script(
          portal: Uri.parse(AppConfig.bnbuPortalBaseUrl),
          enabled: true,
          dark: false,
          localizations: const BnbuLocalizations(
            Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          ),
        ),
        contains('我的申請'),
      );
      // The adapter is presentation only: no cookie, storage, network or
      // document mutation API may appear anywhere in the shipped script.
      for (final forbidden in [
        'document.cookie',
        'localStorage',
        'sessionStorage',
        'fetch(',
        'XMLHttpRequest',
        '.submit(',
        'requestSubmit(',
        'innerHTML =',
        'outerHTML',
        'eval(',
      ]) {
        expect(script, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );

  test('the Portal adapter restores the document it changed', () async {
    final adapter = await PortalPresentation.load();
    final script = adapter.script(
      portal: Uri.parse(AppConfig.bnbuPortalBaseUrl),
      enabled: true,
      dark: false,
    );
    // An explicit off switch is what makes '查看原版' meaningful, so the
    // adapter must own an undo path rather than only adding classes.
    expect(script, contains('undoLayout'));
    expect(script, contains("removeAttribute('class')"));
  });

  testWidgets('only the Portal presentation offers the phone-layout toggle', (
    tester,
  ) async {
    final session = _Session();
    addTearDown(session.dispose);
    for (final (presentation, expectsToggle) in [
      (OfficialWebPresentation.portalLayout, true),
      (OfficialWebPresentation.original, false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: OfficialWebPage(
            title: '统一门户',
            url: AppConfig.bnbuPortalBaseUrl,
            controller: session,
            presentation: presentation,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byTooltip('查看原版'),
        expectsToggle ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a reflowed Portal page keeps the original page reachable', (
    tester,
  ) async {
    final session = _Session();
    final ids = <int>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        ids.add((call.arguments as Map)['id'] as int);
      }
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OfficialWebPage(
          title: '统一门户',
          url: AppConfig.bnbuPortalBaseUrl,
          controller: session,
          presentation: OfficialWebPresentation.portalLayout,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final view = tester.widget<NativeMirrorWebView>(
      find.byType(NativeMirrorWebView),
    );
    // The adapter needs the controller, but the session stays the school's own
    // single-origin ephemeral one.
    expect(view.controller, isNotNull);
    expect(view.onPageFinished, isNotNull);
    expect(view.session.allowedOrigins, [AppConfig.bnbuPortalBaseUrl]);
    expect(view.session.allowedDomains, isEmpty);
    expect(view.session.useEphemeralSession, isTrue);
    expect(view.onSessionCookiesChanged, isNotNull);

    await tester.tap(find.byTooltip('查看原版'));
    await tester.pump();
    expect(find.byTooltip('手机排版'), findsOneWidget);
    await tester.tap(find.byTooltip('手机排版'));
    await tester.pump();
    expect(find.byTooltip('查看原版'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });
}
