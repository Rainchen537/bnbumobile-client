import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/ta_course_manager_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TA editor adapts between compact sheet and wide dialog', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessionController = AppSessionController();
    final taController = TaCourseController(
      sessionController: sessionController,
    );
    addTearDown(sessionController.dispose);
    addTearDown(taController.dispose);

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TaCourseManagerPage(controller: taController),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAt(const Size(390, 844));
    await tester.tap(find.text('新建日程'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ta-course-editor-modal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
      findsNothing,
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey('ta-course-editor-modal'))),
    ).pop();
    await tester.pumpAndSettle();

    await pumpAt(const Size(900, 900));
    await tester.tap(find.text('新建日程'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('ta-course-editor-modal')),
      findsOneWidget,
    );
    final dialogRect = tester.getRect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
    );
    expect(dialogRect.width, lessThanOrEqualTo(680));
    expect(dialogRect.height, lessThanOrEqualTo(720));
    expect(dialogRect.center.dx, closeTo(450, 0.1));
    expect(dialogRect.center.dy, closeTo(450, 0.1));
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.byKey(const ValueKey('ta-course-editor-save')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ta-course-editor-modal')), findsNothing);
  });
}
