import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/timeline_detail_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/pages/timeline_detail_page.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';

import '../tool/home_navigation_fixtures.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'online text creation at $width preserves cancel and explicit draft save',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.reset);
        final session = _AssignmentSession();
        addTearDown(session.dispose);
        final outcomes = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: TimelineDetailPage(
              controller: session,
              item: session.detail.item,
              initialDetail: session.detail,
              initialOnlineTextDraft: '已准备的草稿',
              onAssignmentOutcome: outcomes.add,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final open = find.widgetWithText(FilledButton, '保存在线文本草稿');
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(find.byType(BnbuCreationForm), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '已准备的草稿',
        );
        await tester.enterText(find.byType(TextField), '取消的改动');
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        expect(session.saved, isEmpty);
        expect(outcomes, isEmpty);
        await tester.tap(open);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '明确保存的作业草稿');
        await tester.tap(find.text('保存草稿'));
        await tester.pumpAndSettle();
        expect(session.saved, ['明确保存的作业草稿']);
        expect(outcomes, ['assignment_draft_saved']);
        expect(find.byType(BnbuCreationForm), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

class _AssignmentSession extends HomeNavigationFixture {
  final saved = <String>[];
  final detail = TimelineDetailData(
    item: TimelineItem(
      id: 1,
      title: 'Reading task',
      activityState: '',
      activityType: 'assign',
      moduleName: 'assign',
      description: '',
      courseName: 'Example Course',
      courseId: 1,
      instanceId: 1,
      url: 'https://offline.example.test/assignment',
      sortTime: null,
      formattedTime: '',
      isOverdue: false,
    ),
    type: TimelineDetailType.assignment,
    assignmentId: 1,
    assignmentName: 'Reading task',
    supportsOnlineTextSubmission: true,
    submissionDrafts: true,
    canEditSubmission: true,
    submissionsEnabled: true,
  );

  @override
  Future<TimelineDetailData> loadTimelineDetail(TimelineItem item) async =>
      detail;

  @override
  Future<AssignmentSubmissionOutcome> submitAssignmentOnlineText({
    required int assignmentId,
    required String text,
  }) async {
    saved.add(text);
    return const AssignmentSubmissionOutcome(
      status: 'draft',
      draftSaved: true,
      finalSubmitted: false,
    );
  }
}
