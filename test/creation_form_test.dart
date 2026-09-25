import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_adaptive_modal.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';
import 'package:bnbu_me/widgets/bnbu_notice.dart' show BnbuToast;

void main() {
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool oldNotice = false,
    String actionLabel = '保存',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showBnbuCreationModal<String>(
                  context: context,
                  maxWidth: 640,
                  maxHeight: 660,
                  contentKey: const ValueKey('creation-modal'),
                  builder: (modalContext, presentation) => BnbuCreationForm(
                    title: '新建固定日程',
                    avoidKeyboard: !presentation.isDialog,
                    action: BnbuCreationAction(
                      label: actionLabel,
                      onPressed: () => Navigator.pop(modalContext, 'saved'),
                    ),
                    child: BnbuCreationGroup(
                      children: [
                        TextFormField(
                          key: const ValueKey('creation-name'),
                          decoration: BnbuCreationStyle.input(
                            context,
                            hint: '名称',
                          ),
                        ),
                        for (var i = 0; i < 24; i++)
                          SizedBox(
                            height: 52,
                            child: Center(child: Text('字段 $i')),
                          ),
                      ],
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    if (oldNotice) {
      BnbuToast.show(tester.element(find.text('打开')), '已开启提醒');
      await tester.pump();
      expect(find.byKey(const ValueKey('bnbu-notice')), findsOneWidget);
    }
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'phone header keeps a long save label apart from the title at large type',
    (tester) async {
      await mount(tester, scale: 2, actionLabel: '保存评价');
      final title = tester.getRect(find.text('新建固定日程'));
      final action = tester.getRect(find.byType(BnbuCreationAction));
      expect(
        tester
            .widget<BnbuCreationAction>(find.byType(BnbuCreationAction))
            .fontSize,
        16,
      );
      expect(title.right, lessThanOrEqualTo(action.left));
      expect(
        tester
            .getRect(find.byType(BnbuCreationHeader))
            .contains(action.topLeft),
        isTrue,
      );
      await tester.tap(find.text('保存评价'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'previous page notice cannot intercept the new form save action',
    (tester) async {
      await mount(tester, oldNotice: true);
      expect(find.byKey(const ValueKey('bnbu-notice')), findsNothing);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone creation sheet has no grabber space and header drag still dismisses',
    (tester) async {
      await mount(tester);
      final sheet = find.byType(BottomSheet);
      expect(tester.widget<BottomSheet>(sheet).showDragHandle, isFalse);
      final surface = tester.getRect(
        find.byKey(const ValueKey('creation-modal')),
      );
      final header = tester.getRect(find.byType(BnbuCreationHeader));
      expect(header.top - surface.top, closeTo(4, .1));
      final originalTop = header.top;
      await tester.drag(find.text('字段 2'), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(BnbuCreationHeader)).top,
        closeTo(originalTop, .1),
      );
      await tester.fling(
        find.byType(BnbuCreationHeader),
        const Offset(0, 650),
        1600,
      );
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone sheets retain outside-tap dismissal', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBnbuCreationModal<void>(
                context: context,
                builder: (modalContext, _) => BnbuCreationForm(
                  title: '标记地点',
                  action: BnbuCreationAction(label: '保存', onPressed: () {}),
                  child: const BnbuCreationGroup(
                    children: [SizedBox(height: 100)],
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('explicitly protected sheets keep their dismissal policy', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBnbuAdaptiveModal<void>(
                context: context,
                barrierDismissible: false,
                enableDrag: false,
                builder: (_, presentation) => BnbuModalFrame(
                  presentation: presentation,
                  title: '保存草稿',
                  child: const SizedBox(height: 100),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 40));
    await tester.fling(find.text('保存草稿'), const Offset(0, 300), 1400);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'wide creation uses the same grouped form and scrolls at large type',
    (tester) async {
      await mount(tester, width: 1440, scale: 2);
      expect(find.byType(BottomSheet), findsNothing);
      final dialog = tester.getRect(
        find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      );
      expect(dialog.width, 640);
      expect(dialog.height, lessThanOrEqualTo(660));
      expect(dialog.center.dx, closeTo(720, .1));
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -650),
      );
      await tester.pumpAndSettle();
      expect(find.text('保存').hitTestable(), findsOneWidget);
      expect(find.byTooltip('关闭').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
    },
  );
}
