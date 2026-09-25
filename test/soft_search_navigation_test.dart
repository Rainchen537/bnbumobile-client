import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/theme/campus_reference_theme.dart';
import 'package:bnbu_me/widgets/bnbu_reveal_search.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../tool/home_navigation_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'soft search owns full slot, dismisses safely and keeps result taps',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var opened = 0;
      var composed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([focus, controller]),
              builder: (context, _) => Column(
                children: [
                  BnbuRevealSearch(
                    controller: controller,
                    focusNode: focus,
                    onChanged: (_) {},
                    softMode: true,
                    controlKey: const ValueKey('soft'),
                    trailingAction: IconButton(
                      onPressed: () => composed++,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  Expanded(
                    child: BnbuSoftSearchBody(
                      active: focus.hasFocus && controller.text.isEmpty,
                      onDismiss: focus.unfocus,
                      child: Column(
                        children: [
                          TextFieldTapRegion(
                            child: TextButton(
                              onPressed: () => opened++,
                              child: const Text('result'),
                            ),
                          ),
                          const Expanded(
                            child: SizedBox.expand(key: ValueKey('blank')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('soft'));
      await tester.tap(find.byIcon(Icons.add));
      expect(composed, 1);
      expect(focus.hasFocus, isFalse);
      await tester.tapAt(Offset(12, tester.getCenter(field).dy));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tester.getSize(field).width, 800);
      final decoration = tester.widget<TextField>(field).decoration!;
      expect(
        decoration.focusedBorder!.borderSide.color,
        isNot(AppTheme.light.colorScheme.primary),
      );
      await tester.tapAt(tester.getCenter(find.text('result')));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(focus.hasFocus, isFalse);
      expect(tester.getSize(field).width, 100);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'query');
      await tester.pumpAndSettle();
      await tester.tap(find.text('result'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(controller.text, 'query');
      await tester.tap(find.byKey(const ValueKey('blank')));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(tester.getSize(field).width, 100);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'home service stack survives resize and tab changes in dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        final session = HomeNavigationFixture();
        final shell = RootShellController();
        final mail = MailAssistantIntentController();
        final ta = TaCourseController(sessionController: session);
        addTearDown(() {
          ta.dispose();
          mail.dispose();
          shell.dispose();
          session.dispose();
          tester.view.reset();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: RootShellPage(
              controller: session,
              shellController: shell,
              taCourseController: ta,
              mailIntentController: mail,
              pageOverrideBuilder: (tab) => tab == AppTab.home
                  ? const _ServicePage(depth: 0)
                  : Text('tab-${tab.name}'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rail = find.byKey(const ValueKey('root-side-navigation'));
        final colors = CampusReferenceTheme.of(tester.element(rail));
        expect(
          tester.widget<Material>(rail).color,
          dark ? CampusReferenceTheme.navy : colors.surface,
        );
        await tester.tap(find.text('open-1'));
        await tester.pumpAndSettle();
        expect(rail, findsOneWidget);
        expect(find.text('page-1'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('nested-search')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('page-1'), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('nested-search'))).width,
          100,
        );

        expect(tester.getTopLeft(find.byType(_ServicePage)).dx, 72);
        await tester.tap(find.text('open-2'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('root-side-navigation-destination-邮箱')),
        );
        await tester.pumpAndSettle();
        expect(find.text('tab-mail'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('root-side-navigation-destination-首页')),
        );
        await tester.pumpAndSettle();
        expect(find.text('page-2'), findsOneWidget);
        for (final width in [390.0, 900.0, 1440.0, 390.0]) {
          tester.view.physicalSize = Size(width, 900);
          await tester.pumpAndSettle();
          expect(find.text('page-2'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('root-bottom-navigation')),
            findsNothing,
          );
          expect(rail, width >= 700 ? findsOneWidget : findsNothing);
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('page-1'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('page-0'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('root-bottom-navigation')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _ServicePage extends StatefulWidget {
  const _ServicePage({required this.depth});
  final int depth;
  @override
  State<_ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<_ServicePage> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('page-${widget.depth}')),
    body: Column(
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _ServicePage(depth: widget.depth + 1),
            ),
          ),
          child: Text('open-${widget.depth + 1}'),
        ),
        if (widget.depth > 0)
          BnbuRevealSearch(
            controller: controller,
            onChanged: (_) {},
            softMode: true,
            controlKey: const ValueKey('nested-search'),
          ),
      ],
    ),
  );
}
