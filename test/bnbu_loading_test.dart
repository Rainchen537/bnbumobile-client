import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/widgets/bnbu_loading.dart';
import 'package:bnbu_me/widgets/schedule_scroll_physics.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';
import 'package:bnbu_me/theme/app_theme.dart';

void main() {
  testWidgets(
    'background update keeps rows still and yields to a pull gesture',
    (tester) async {
      final updating = ValueNotifier(false);
      addTearDown(updating.dispose);
      final completion = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BnbuLoadingRegion(
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: updating,
                    builder: (_, value, _) => BnbuUpdateProgress(active: value),
                  ),
                  Expanded(
                    child: BnbuRefreshIndicator(
                      onRefresh: () => completion.future,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(
                            height: 100,
                            child: Text('Existing content'),
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
      final resting = tester.getRect(find.text('Existing content'));
      updating.value = true;
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.getRect(find.text('Existing content')), resting);
      await tester.drag(find.byType(ListView), const Offset(0, 35));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      completion.complete();
      updating.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.getRect(find.text('Existing content')), resting);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('bare refresh completes and releases scrolling at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final completion = Completer<void>();
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BnbuRefreshIndicator(
              onRefresh: () {
                refreshes++;
                return completion.future;
              },
              child: ListView(
                physics: const ScheduleScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                children: const [SizedBox(height: 120, child: Text('内容'))],
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 650));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(refreshes, 1);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      completion.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'global states are unboxed and inline loading fits small bounds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Column(
              children: [
                BnbuEmptyState(title: '暂无内容'),
                BnbuErrorState(),
                BnbuLoadingState(),
                SizedBox.square(dimension: 12, child: BnbuActivityIndicator()),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(BnbuSurfaceCard), findsNothing);
      final spinners = tester.widgetList<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator),
      );
      expect(spinners.last.radius, 6);
      expect(tester.takeException(), isNull);
    },
  );
}
