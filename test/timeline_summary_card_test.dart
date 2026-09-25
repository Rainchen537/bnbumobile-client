import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/timeline_summary_card.dart';

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 900.0]) {
      testWidgets(
        'deadline stays at the right, course fills space $dark/$width',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          for (final scale in [1.0, 2.0]) {
            for (final home in [false, true]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Scaffold(
                      body: Builder(
                        builder: (context) => BnbuTimelineSummaryCard(
                          item: _item,
                          deadlineLabel: 'Sep 9, 23:59',
                          statusLabel: 'Due in 3 hours',
                          accentColor: timelineSummaryAccentColor(
                            _item,
                            context.bnbuTheme,
                            now: DateTime.utc(2026, 9, 9),
                          ),
                          showIspaceLabel: home,
                          onTap: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final time = tester.getRect(
                find.byKey(const ValueKey('timeline-summary-time-1')),
              );
              expect(time.right, closeTo(width - 12, 0.01));
              expect(find.text('Sep 9, 23:59'), findsOneWidget);
              if (scale == 1) {
                final course = tester.getRect(find.text(_item.courseName));
                expect(course.right, closeTo(time.left - 8, 0.01));
                expect((course.center.dy - time.center.dy).abs(), lessThan(1));
              }
              final timeText = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: find.byKey(const ValueKey('timeline-summary-time-1')),
                  matching: find.byType(RichText),
                ),
              );
              expect(timeText.didExceedMaxLines, isFalse);
              expect(tester.takeException(), isNull);
            }
          }
        },
      );
    }
  }
}

final _item = TimelineItem(
  id: 1,
  title: 'Assignment: Accessible Campus Interfaces',
  courseName: 'Human Computer Interaction and Inclusive Interface Design',
  courseId: 1,
  instanceId: 1,
  moduleName: 'assign',
  activityType: 'assign',
  activityState: 'Pending',
  description: '',
  url: '',
  formattedTime: '',
  sortTime: DateTime.utc(2026, 9, 9, 15, 59),
  isOverdue: false,
);
