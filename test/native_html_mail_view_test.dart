import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/widgets/native_html_mail_view.dart';

void main() {
  testWidgets(
    'Android mail header ignores resize scrolls until the user reverses drag',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      int? viewId;
      final changes = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          if (call.method == 'create') {
            viewId = (call.arguments as Map)['id'] as int;
            return 1;
          }
          if (call.method == 'resize') {
            final args = call.arguments as Map;
            return {'width': args['width'], 'height': args['height']};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeHtmlMailView(
              htmlContent: '<p>Synthetic scrollable mail</p>',
              onCollapsedChanged: changes.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(viewId, isNotNull);
      Future<void> scroll(bool collapsed) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'ispace/native_webview/$viewId',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('mailScrollStateChanged', {'collapsed': collapsed}),
          ),
          (_) {},
        );
        await tester.pump();
      }

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(NativeHtmlMailView)),
      );
      await gesture.moveBy(const Offset(0, -40));
      await scroll(true);
      expect(changes, [true]);
      // Collapsing the sender header enlarges a short WebView and clamps its
      // scrollY back to zero, even while the finger still moves upward.
      await scroll(false);
      await gesture.moveBy(const Offset(0, -40));
      expect(changes, [true]);
      // A deliberate downward drag must still reveal the header at scrollY=0,
      // where WebView cannot produce another scroll-position change.
      await gesture.moveBy(const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      await gesture.up();
      await tester.pumpWidget(const SizedBox.shrink());
      await scroll(true);
      expect(changes, [true, false]);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('desktop mail view allows the initial local HTML navigation', () {
    final action = NavigationAction(
      request: URLRequest(url: WebUri('https://mail.bnbu.edu.cn/')),
      isForMainFrame: true,
      navigationType: NavigationType.OTHER,
    );

    expect(
      desktopHtmlMailNavigationPolicy(action),
      NavigationActionPolicy.ALLOW,
    );
  });

  test('desktop mail view keeps activated web links outside the view', () {
    final action = NavigationAction(
      request: URLRequest(url: WebUri('https://www.bnbu.edu.cn/notice')),
      isForMainFrame: true,
      navigationType: NavigationType.LINK_ACTIVATED,
    );

    expect(
      desktopHtmlMailNavigationPolicy(action),
      NavigationActionPolicy.CANCEL,
    );
  });

  testWidgets(
    'unsupported platform uses readable HTML fallback without warning',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeHtmlMailView(
              htmlContent: '<script>bad()</script><h1>课程通知</h1><p>周五提交。</p>',
            ),
          ),
        ),
      );
      debugDefaultTargetPlatformOverride = null;

      expect(find.textContaining('课程通知'), findsOneWidget);
      expect(find.textContaining('周五提交'), findsOneWidget);
      expect(find.textContaining('当前平台暂不支持'), findsNothing);
      expect(find.textContaining('bad()'), findsNothing);
    },
  );

  testWidgets('mail detail fallback prefers the parsed plain-text body', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativeHtmlMailView(
            htmlContent: '<p>HTML body</p>',
            fallbackText: '安全正文',
          ),
        ),
      ),
    );
    debugDefaultTargetPlatformOverride = null;

    expect(find.text('安全正文'), findsOneWidget);
    expect(find.textContaining('HTML body'), findsNothing);
  });
}
