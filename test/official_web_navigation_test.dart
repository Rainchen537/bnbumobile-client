import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/pages/official_web_page.dart';
import 'package:bnbu_me/pages/web_mirror_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lease implements AppSessionLease {
  bool active = true;
  @override
  bool get isActive => active;
  @override
  String get owner => 'synthetic-navigation';
}

class _Session extends AppSessionController {
  final lease = _Lease();
  final prepared = <OfficialWebTarget>[];
  int resets = 0;
  int ispacePreparations = 0;
  @override
  bool get isLoggedIn => true;
  @override
  String get username => lease.owner;
  @override
  AppSessionLease captureSessionLease() => lease;
  @override
  Future<void> resetOfficialWebSession(OfficialWebTarget target) async {
    resets++;
  }

  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession(
    OfficialWebTarget target,
  ) async {
    prepared.add(target);
    final origin = target == OfficialWebTarget.portal
        ? AppConfig.bnbuPortalBaseUrl
        : AppConfig.bnbuMisBaseUrl;
    return WebSessionSnapshot(
      baseUrl: origin,
      cookies: [
        WebSessionCookie(
          name: '${target.name}-session',
          value: 'synthetic',
          domain: Uri.parse(origin).host,
          path: '/',
          hostOnly: true,
          secure: true,
          httpOnly: true,
        ),
      ],
      useEphemeralSession: true,
    );
  }

  @override
  Future<WebSessionSnapshot> prepareWebSession() async {
    ispacePreparations++;
    return WebSessionSnapshot(
      baseUrl: AppConfig.ispaceBaseUrl,
      cookies: const [],
    );
  }
}

void main() {
  for (final destination in [
    'mis',
    'mis-sso',
    'ispace',
    'unknown',
    'expired',
    'portal-login',
  ]) {
    testWidgets('Portal routes $destination with isolated session recovery', (
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
            title: 'Portal',
            url: AppConfig.bnbuPortalBaseUrl,
            controller: session,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final portalId = ids.single;
      final originalCallback = tester
          .widget<NativeMirrorWebView>(find.byType(NativeMirrorWebView))
          .onNavigationBlocked!;
      Future<void> event(String method, Object? value) =>
          messenger.handlePlatformMessage(
            'ispace/native_webview/$portalId',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, value),
            ),
            (_) {},
          );
      final url = switch (destination) {
        'mis' => '${AppConfig.bnbuMisBaseUrl}/mis/usr/index.do',
        'mis-sso' =>
          '${AppConfig.bnbuSsoBaseUrl}/auth/sso/ssoLogin?service=${AppConfig.bnbuMisServiceId}',
        'unknown' => 'https://evil.example/path?private=synthetic',
        'expired' => AppConfig.bnbuMisBaseUrl,
        'portal-login' => '${AppConfig.bnbuSsoBaseUrl}/',
        _ => '${AppConfig.ispaceBaseUrl}/my/',
      };
      if (destination == 'expired') session.lease.active = false;
      await event('navigationBlocked', url);
      await event('navigationBlocked', url); // native/new-window duplicate
      if (destination != 'portal-login') {
        await event('authenticationRequired', null);
      } // A blocked new-window callback supplies only its destination URL.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(session.resets, destination == 'portal-login' ? 1 : 0);
      if (destination == 'unknown' || destination == 'expired') {
        expect(session.prepared, [OfficialWebTarget.portal]);
        expect(session.ispacePreparations, 0);
        expect(find.byType(WebMirrorPage), findsNothing);
        if (destination == 'unknown') {
          expect(find.text('该链接暂不支持在应用内打开。'), findsOneWidget);
          expect(find.textContaining('private=synthetic'), findsNothing);
          await tester.pump(const Duration(seconds: 5));
        }
      } else if (destination == 'portal-login') {
        originalCallback(url); // Old view event after the new generation.
        await tester.pump();
        expect(session.resets, 1);
        expect(session.prepared, [
          OfficialWebTarget.portal,
          OfficialWebTarget.portal,
        ]);
      } else if (destination == 'ispace') {
        expect(find.byType(WebMirrorPage), findsOneWidget);
        expect(session.ispacePreparations, 1);
        expect(session.prepared, [OfficialWebTarget.portal]);
      } else {
        expect(session.prepared, [
          OfficialWebTarget.portal,
          OfficialWebTarget.mis,
        ]);
        final visible = tester
            .widgetList<NativeMirrorWebView>(find.byType(NativeMirrorWebView))
            .singleWhere(
              (view) => view.session.baseUrl == AppConfig.bnbuMisBaseUrl,
            );
        expect(visible.session.allowedOrigins, [AppConfig.bnbuMisBaseUrl]);
        expect(visible.session.cookies.single.name, 'mis-session');
        expect(
          visible.session.cookies.single.domain,
          Uri.parse(AppConfig.bnbuMisBaseUrl).host,
        );
        await tester.pump(const Duration(milliseconds: 400));
        Navigator.of(tester.element(find.byType(NativeMirrorWebView))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(session.prepared, [
          OfficialWebTarget.portal,
          OfficialWebTarget.mis,
        ]);
        final portal = find.byWidgetPredicate(
          (widget) =>
              widget is NativeMirrorWebView &&
              widget.session.baseUrl == AppConfig.bnbuPortalBaseUrl,
        );
        expect(
          tester
              .widget<NativeMirrorWebView>(portal)
              .session
              .cookies
              .single
              .name,
          'portal-session',
        );
        expect(ModalRoute.of(tester.element(portal))!.isCurrent, isTrue);
        session.lease.active = false;
        await event('navigationBlocked', url);
        await event('authenticationRequired', null);
        await tester.pump();
        expect(session.prepared, [
          OfficialWebTarget.portal,
          OfficialWebTarget.mis,
        ]);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
