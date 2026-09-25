import 'dart:async';

import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_adaptive_modal.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/home_navigation_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final tab in [AppTab.home, AppTab.schedule]) {
    for (final (platform, glass) in [
      (TargetPlatform.iOS, false),
      (TargetPlatform.iOS, true),
      (TargetPlatform.android, false),
    ]) {
      testWidgets('transient routes preserve ${tab.name} root geometry '
          '$platform glass=$glass', (tester) async {
        final (context, _) = await _mount(tester, tab, platform, glass: glass);
        final navigator = Navigator.of(context);
        final navigation = find.byKey(
          const ValueKey('root-bottom-navigation'),
          skipOffstage: false,
        );
        final probe = find.byKey(
          const ValueKey('navigation-probe'),
          skipOffstage: false,
        );
        final navigationBounds = tester.getRect(navigation);
        final contentBounds = tester.getRect(probe);
        final extendsBody = _root(tester).extendBody;
        Future<void> stableTransition() async {
          for (var frame = 0; frame < 25; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(navigation, findsOneWidget);
            expect(tester.getRect(navigation), navigationBounds);
            expect(tester.getRect(probe), contentBounds);
            expect(_root(tester).extendBody, extendsBody);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        for (final kind in ['sheet', 'dialog', 'menu']) {
          if (kind == 'sheet') {
            unawaited(
              showBnbuAdaptiveModal<void>(
                context: context,
                builder: (_, _) =>
                    const SizedBox(height: 160, child: Text('Popup')),
              ),
            );
          } else if (kind == 'dialog') {
            unawaited(
              showDialog<void>(
                context: context,
                useRootNavigator: false,
                builder: (_) => const AlertDialog(content: Text('Popup')),
              ),
            );
          } else {
            unawaited(
              showMenu<void>(
                context: context,
                useRootNavigator: false,
                position: const RelativeRect.fromLTRB(20, 100, 20, 100),
                items: const [PopupMenuItem(child: Text('Popup'))],
              ),
            );
          }
          await stableTransition();
          expect(navigator.canPop(), isTrue);
          await tester.binding.handlePopRoute();
          await stableTransition();
          expect(navigator.canPop(), isFalse);
        }

        unawaited(navigator.push<void>(_page('Detail')));
        await tester.pumpAndSettle();
        expect(navigation, findsNothing);
        final detailContext = tester.element(find.text('Detail'));
        unawaited(
          showDialog<void>(
            context: detailContext,
            useRootNavigator: false,
            builder: (_) => const AlertDialog(content: Text('Nested popup')),
          ),
        );
        await tester.pumpAndSettle();
        expect(navigation, findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Nested popup'), findsNothing);
        expect(find.text('Detail'), findsOneWidget);
        expect(navigation, findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(navigator.canPop(), isFalse);
        expect(tester.getRect(navigation), navigationBounds);
        expect(tester.getRect(probe), contentBounds);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('page removal and replacement beneath popups update page depth', (
    tester,
  ) async {
    final (context, _) = await _mount(tester, AppTab.home, TargetPlatform.iOS);
    final navigator = Navigator.of(context);
    final bar = find.byKey(const ValueKey('root-bottom-navigation'));
    final detail = _page('Detail');
    unawaited(navigator.push<void>(detail));
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('Detail')),
        useRootNavigator: false,
        builder: (_) => const AlertDialog(content: Text('Popup')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.removeRoute(detail);
    await tester.pumpAndSettle();
    expect(bar, findsOneWidget);
    expect(navigator.canPop(), isTrue);
    expect(find.text('Popup'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    unawaited(navigator.push<void>(_page('First')));
    await tester.pumpAndSettle();
    unawaited(navigator.pushReplacement<void, void>(_page('Replacement')));
    await tester.pumpAndSettle();
    expect(bar, findsNothing);
    expect(find.text('Replacement'), findsOneWidget);
    unawaited(
      navigator.pushReplacement<void, void>(
        DialogRoute<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Replacement popup')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(bar, findsOneWidget);
    expect(navigator.canPop(), isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive content stack does not consume another tab back', (
    tester,
  ) async {
    final (context, shell) = await _mount(
      tester,
      AppTab.home,
      TargetPlatform.iOS,
    );
    final navigator = Navigator.of(context);
    unawaited(navigator.push<void>(_page('Detail')));
    await tester.pumpAndSettle();
    shell.selectTab(AppTab.schedule);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isTrue);
    shell.selectTab(AppTab.home);
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isFalse);
  });
}

MaterialPageRoute<void> _page(String title) => MaterialPageRoute<void>(
  builder: (_) => Scaffold(body: Center(child: Text(title))),
);

Scaffold _root(WidgetTester tester) => tester.widget<Scaffold>(
  find.byKey(const ValueKey('root-compact-scaffold'), skipOffstage: false),
);

Future<(BuildContext, RootShellController)> _mount(
  WidgetTester tester,
  AppTab tab,
  TargetPlatform platform, {
  bool glass = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 62, bottom: 34);
  final session = HomeNavigationFixture();
  final shell = RootShellController()..selectTab(tab);
  final mail = MailAssistantIntentController();
  final ta = TaCourseController(sessionController: session);
  final appearance = AppThemeModeController(
    liquidGlassSupportLoader: () async => true,
  );
  await appearance.restore();
  await appearance.setLiquidGlassEnabled(glass);
  late BuildContext contentContext;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    ta.dispose();
    mail.dispose();
    shell.dispose();
    session.dispose();
    appearance.dispose();
    tester.view.reset();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: platform),
      builder: (context, child) =>
          BnbuLiquidGlassScope(controller: appearance, child: child!),
      home: RootShellPage(
        controller: session,
        shellController: shell,
        taCourseController: ta,
        mailIntentController: mail,
        pageOverrideBuilder: (current) => current == tab
            ? Builder(
                builder: (context) {
                  contentContext = context;
                  return const SizedBox.expand(
                    key: ValueKey('navigation-probe'),
                  );
                },
              )
            : const SizedBox(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (contentContext, shell);
}
