import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_notice.dart';

void main() {
  testWidgets('global notice enters from the top-right and auto dismisses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('草稿已保存'))),
                child: const Text('显示通知'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示通知'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final notice = find.byKey(const ValueKey('bnbu-notice'));
    expect(notice, findsOneWidget);
    expect(tester.getTopRight(notice).dx, greaterThan(1170));
    expect(tester.getTopRight(notice).dy, lessThan(140));
    expect(find.text('草稿已保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 160));
    expect(notice, findsNothing);
  });

  testWidgets('a new notice replaces the currently visible notice', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    BnbuToast.show(hostContext, '第一条');
    await tester.pump();
    BnbuToast.show(hostContext, '第二条', kind: BnbuToastKind.warning);
    await tester.pump();

    expect(find.byKey(const ValueKey('bnbu-notice')), findsOneWidget);
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
  });
}
