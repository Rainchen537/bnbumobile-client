import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/academic_calendar_page.dart';
import 'package:bnbu_me/services/academic_calendar_service.dart';
import 'package:bnbu_me/theme/app_theme.dart';

void main() {
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('calendar text tabs switch and expose selection at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AcademicCalendarPage(
            repository: _CalendarRepository(),
            pdfBuilder: (_, document, bytes) => Text(document.title),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('academic-calendar-selector'));
      expect(
        find.descendant(of: selector, matching: find.byType(Icon)),
        findsNothing,
      );
      final button = find.widgetWithText(TextButton, '课程计划');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text('Class Schedule for S1 of AY2026-27.pdf'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('calendar page switches PDFs and hides the history link', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AcademicCalendarPage(
          repository: _CalendarRepository(),
          pdfBuilder: (context, document, bytes) =>
              Center(child: Text(document.title, key: ValueKey(document.kind))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('校历'), findsOneWidget);
    expect(find.text('本学期校历'), findsOneWidget);
    expect(find.text('课程计划'), findsOneWidget);
    expect(
      find.text('Academic Calendar for S1 of AY2026-27.pdf'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('academic-calendar-history-link')),
      findsNothing,
    );

    await tester.tap(find.text('课程计划'));
    await tester.pumpAndSettle();
    expect(find.text('Class Schedule for S1 of AY2026-27.pdf'), findsOneWidget);

    expect(find.text('查询往年校历'), findsNothing);
  });

  testWidgets('refresh replaces PDF state when the official URL is unchanged', (
    tester,
  ) async {
    final repository = _RefreshingCalendarRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AcademicCalendarPage(
          repository: repository,
          pdfBuilder: (context, document, bytes) => _StatefulPdfProbe(bytes),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PDF byte 1'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
    expect(find.text('PDF byte 9'), findsOneWidget);
    expect(find.text('PDF byte 1'), findsNothing);
  });
  testWidgets('refresh keeps selected course plan and file actions', (
    tester,
  ) async {
    final repository = _RefreshingCalendarRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AcademicCalendarPage(
          repository: repository,
          pdfBuilder: (context, document, bytes) => _StatefulPdfProbe(bytes),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程计划'));
    await tester.pumpAndSettle();
    expect(find.text('PDF byte 2'), findsOneWidget);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('保存或分享'), findsOneWidget);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(repository.loadCount, 2);
    expect(find.text('PDF byte 10'), findsOneWidget);
    expect(find.text('PDF byte 9'), findsNothing);
  });
}

class _CalendarRepository implements AcademicCalendarRepository {
  @override
  Future<AcademicCalendarSnapshot> load() async {
    return AcademicCalendarSnapshot(
      bundle: fallbackAcademicCalendarBundle,
      academicCalendarBytes: Uint8List.fromList([1]),
      classScheduleBytes: Uint8List.fromList([2]),
    );
  }
}

class _RefreshingCalendarRepository implements AcademicCalendarRepository {
  int loadCount = 0;

  @override
  Future<AcademicCalendarSnapshot> load() async {
    loadCount++;
    return AcademicCalendarSnapshot(
      bundle: fallbackAcademicCalendarBundle,
      academicCalendarBytes: Uint8List.fromList([loadCount == 1 ? 1 : 9]),
      classScheduleBytes: Uint8List.fromList([loadCount == 1 ? 2 : 10]),
    );
  }
}

class _StatefulPdfProbe extends StatefulWidget {
  const _StatefulPdfProbe(this.bytes);

  final Uint8List bytes;

  @override
  State<_StatefulPdfProbe> createState() => _StatefulPdfProbeState();
}

class _StatefulPdfProbeState extends State<_StatefulPdfProbe> {
  late final int _firstByte = widget.bytes.first;

  @override
  Widget build(BuildContext context) => Text('PDF byte $_firstByte');
}
