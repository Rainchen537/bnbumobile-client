import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/pages/duoduo_campus_wall_page.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'blocked links reject unsafe URLs and open once after confirmation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger = tester.binding.defaultBinaryMessenger;
      const actions = MethodChannel('ispace/native_actions');
      final opened = <String>[];
      messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(actions, (call) async {
        if (call.method == 'openExternalUrl') {
          opened.add((call.arguments as Map)['url'] as String);
        }
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        messenger.setMockMethodCallHandler(actions, null);
      });
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const DuoduoCampusWallPage()),
      );
      await tester.pump();
      final view = tester.widget<NativeMirrorWebView>(
        find.byType(NativeMirrorWebView),
      );
      expect(view.session.cookies, isEmpty);
      expect(view.participatesInSessionCleanup, isFalse);
      expect(view.persistentProfileName, 'handsbnbu_duoduo');
      final blocked = view.onNavigationBlocked!;
      for (final url in [
        'javascript://example.org/alert(1)',
        'file://example.org/path',
        'https://user:pass@example.org',
        '${AppConfig.duoduoWebBaseUrl}/resource',
      ]) {
        blocked(url);
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      }
      const target = 'https://example.org/path?private=synthetic';
      blocked(target);
      blocked(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('private=synthetic'), findsNothing);
      expect(opened, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, isEmpty);
      blocked(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, [target]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
