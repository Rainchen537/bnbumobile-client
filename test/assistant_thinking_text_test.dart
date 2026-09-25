import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/assistant_thinking_text.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('thinking highlights only active visible text, dark=$dark', (
      tester,
    ) async {
      Widget scene({
        bool active = true,
        bool reduce = false,
        bool ticker = true,
      }) => MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: TickerMode(
            enabled: ticker,
            child: Scaffold(
              body: AssistantThinkingText(text: '正在读取课程', active: active),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene());
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.text('正在读取课程'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
      final before = tester.getRect(find.text('正在读取课程'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(find.text('正在读取课程')), before);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(scene(active: false));
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(scene(reduce: true));
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      await tester.pumpWidget(scene(ticker: false));
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      await tester.pumpWidget(scene());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(ShaderMask), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
