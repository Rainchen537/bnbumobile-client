import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/timeline_detail_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/upload_file_payload.dart';
import 'package:bnbu_me/pages/timeline_detail_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/assignment_file_drop_zone.dart';

void main() {
  Future<void> native(String method, Object arguments) async {
    // desktop_drop interprets positions using the host OS, even when a test
    // overrides TargetPlatform. Windows and Android send physical pixels.
    if ((Platform.isWindows || Platform.isAndroid) &&
        (method == 'entered' || method == 'updated')) {
      final pixelRatio = TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .views
          .single
          .devicePixelRatio;
      arguments = (arguments as List<double>)
          .map((coordinate) => coordinate * pixelRatio)
          .toList();
    }
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'desktop_drop',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('persistent bar accepts only its bounds on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var received = 0;
      var picks = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 350,
                child: AssignmentFileDropZone(
                  enabled: true,
                  onFiles: (files) => received += files.length,
                  onPickFiles: () => picks++,
                  child: const Text('Submit'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('assignment-file-drop-zone'));
      final rect = tester.getRect(target);
      expect(find.text('点击选择或拖入文件'), findsOneWidget);
      expect(rect.height, greaterThanOrEqualTo(160));
      expect(rect.width, 350);
      expect(find.byType(OverlayPortal), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.center);
      await tester.pumpAndSettle();
      expect(
        find.text('松手上传'),
        findsNothing,
        reason: 'Mouse hover is not a file drag',
      );
      expect(tester.getRect(target), rect);
      await mouse.removePointer();
      for (final point in [
        rect.topLeft + const Offset(8, 8),
        rect.topRight + const Offset(-8, 8),
        rect.bottomLeft + const Offset(8, -8),
        rect.bottomRight + const Offset(-8, -8),
      ]) {
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }
      expect(picks, 4, reason: 'All corners open the file picker');
      await native('entered', [10.0, 10.0]);
      await tester.pumpAndSettle();
      expect(find.text('松手上传'), findsNothing);
      expect(tester.getRect(target), rect);
      await native('performOperation', ['/tmp/outside.txt']);
      expect(received, 0);
      for (final point in [
        rect.center,
        rect.topLeft + const Offset(8, 8),
        rect.topRight + const Offset(-8, 8),
        rect.bottomLeft + const Offset(8, -8),
        rect.bottomRight + const Offset(-8, -8),
      ]) {
        final before = received;
        await native('entered', [10.0, 10.0]);
        await native('updated', [point.dx, point.dy]);
        await tester.pumpAndSettle();
        expect(find.text('松手上传'), findsOneWidget);
        expect(tester.getRect(target), rect);
        await native('performOperation', ['/tmp/inside.txt']);
        await tester.pumpAndSettle();
        expect(received, before + 1);
        expect(find.text('点击选择或拖入文件'), findsOneWidget);
        expect(find.bySemanticsLabel('点击选择或拖入文件'), findsOneWidget);
        expect(tester.getRect(target), rect);
      }
      await native('entered', [rect.center.dx, rect.center.dy]);
      await tester.pumpAndSettle();
      await native('updated', [10.0, 10.0]);
      await tester.pumpAndSettle();
      expect(find.text('松手上传'), findsNothing);
      await native('performOperation', ['/tmp/left-bar.txt']);
      expect(received, 5);
      await native('entered', [rect.center.dx, rect.center.dy]);
      await native('exited', []);
      await tester.pumpAndSettle();
      expect(find.text('点击选择或拖入文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'bar keeps layout across languages, scaling and widths on $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final width in [390.0, 720.0, 900.0, 1440.0]) {
          await tester.binding.setSurfaceSize(Size(width, 600));
          for (final locale in [
            const Locale('zh', 'CN'),
            const Locale('zh', 'TW'),
            const Locale('en'),
          ]) {
            for (final scale in [1.0, 2.0]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: AppTheme.dark,
                  locale: locale,
                  supportedLocales: BnbuLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    BnbuLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: const Scaffold(
                        body: Padding(
                          padding: EdgeInsets.all(24),
                          child: AssignmentFileDropZone(
                            enabled: true,
                            onFiles: _ignore,
                            onPickFiles: _pick,
                            child: Text('Submit'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final target = find.byKey(
                const ValueKey('assignment-file-drop-zone'),
              );
              final rect = tester.getRect(target);
              expect(rect.width, closeTo(width - 48, .01));
              expect(rect.height, greaterThanOrEqualTo(160));
              expect(rect.height, lessThan(300));
              await native('entered', [rect.center.dx, rect.center.dy]);
              await tester.pumpAndSettle();
              expect(tester.getRect(target), rect);
              expect(
                find.text(BnbuLocalizations(locale).text('松手上传')),
                findsOneWidget,
              );
              await native('exited', []);
              await tester.pumpAndSettle();
              expect(tester.getRect(target), rect);
              expect(tester.takeException(), isNull);
            }
          }
        }
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets(
      'drop zone preserves picker at width $width and stops under dialog',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var received = 0;
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 350,
                  child: AssignmentFileDropZone(
                    enabled: true,
                    onFiles: (files) => received += files.length,
                    onPickFiles: _pick,
                    child: OutlinedButton(
                      onPressed: () {},
                      child: const Text('Choose File'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final point = tester.getCenter(
          find.byKey(const ValueKey('assignment-file-drop-zone')),
        );
        await native('entered', [point.dx, point.dy]);
        await tester.pumpAndSettle();
        expect(find.text('松手上传'), findsOneWidget);
        await native('performOperation', ['/tmp/synthetic.txt']);
        await tester.pumpAndSettle();
        expect(received, 1);
        expect(find.text('Choose File'), findsOneWidget);
        await native('entered', [point.dx, point.dy]);
        await tester.pumpAndSettle();
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const AlertDialog(content: Text('Front dialog')),
        );
        await tester.pumpAndSettle();
        await native('entered', [point.dx, point.dy]);
        await native('performOperation', ['/tmp/should-not-enter.txt']);
        await tester.pumpAndSettle();
        expect(received, 1);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('drag cancellation, disable and disposal on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var enabled = true;
      var received = 0;
      var clicks = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en'),
          supportedLocales: BnbuLocalizations.supportedLocales,
          localizationsDelegates: const [
            BnbuLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 350,
                      child: AssignmentFileDropZone(
                        enabled: enabled,
                        onFiles: (files) => received += files.length,
                        onPickFiles: () => clicks++,
                        child: const Text('Submit'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('assignment-file-drop-zone'));
      final rect = tester.getRect(panel);
      await tester.tap(panel);
      await tester.pumpAndSettle();
      expect(clicks, 1);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(clicks, 2, reason: 'Keyboard activation must remain available');
      await native('entered', [rect.center.dx, rect.center.dy]);
      await tester.pumpAndSettle();
      expect(find.text('Release to upload'), findsOneWidget);
      expect(tester.getRect(panel), rect);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.text('Release to upload'), findsNothing);
      await tester.tap(panel);
      await native('performOperation', ['/tmp/disabled.txt']);
      expect(received, 0);
      expect(clicks, 2);
      update(() => enabled = true);
      await tester.pumpAndSettle();
      expect(find.text('Release to upload'), findsNothing);
      await native('entered', [rect.center.dx, rect.center.dy]);
      await tester.pumpAndSettle();
      expect(find.text('Release to upload'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await native('performOperation', ['/tmp/disposed.txt']);
      await tester.pumpAndSettle();
      expect(received, 0);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('iOS and Android keep file picker without a native drop target', (
    tester,
  ) async {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        const MaterialApp(
          home: AssignmentFileDropZone(
            enabled: true,
            onFiles: _ignore,
            onPickFiles: _pick,
            child: Text('Picker'),
          ),
        ),
      );
      expect(find.byType(DropTarget), findsNothing);
      expect(find.text('Picker'), findsOneWidget);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'real assignment page stages a native file without submitting; removal and logout clear it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('bnbu-drop-widget-'),
      );
      final file = File(
        '${dir!.path}${Platform.pathSeparator}Synthetic report.txt',
      );
      await tester.runAsync(
        () => file.writeAsString('Synthetic attachment only.'),
      );
      addTearDown(() => dir.delete(recursive: true));
      final controller = _Controller();
      addTearDown(controller.dispose);
      final item = TimelineItem(
        id: 42,
        title: 'Synthetic Assignment',
        activityState: 'Due',
        activityType: 'assign',
        moduleName: 'assign',
        description: '',
        courseName: 'Synthetic Course',
        courseId: 7,
        instanceId: 42,
        url: '',
        sortTime: DateTime.utc(2026),
        formattedTime: '',
        isOverdue: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          supportedLocales: BnbuLocalizations.supportedLocales,
          localizationsDelegates: const [
            BnbuLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TimelineDetailPage(
            controller: controller,
            item: item,
            initialDetail: TimelineDetailData(
              item: item,
              type: TimelineDetailType.assignment,
              assignmentId: 42,
              canEditSubmission: true,
              supportsFileSubmission: true,
              maxFileSubmissions: 2,
              maxSubmissionSizeBytes: 100,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Click to choose or drop files'), findsOneWidget);
      Future<void> drop() async {
        final point = tester.getCenter(
          find.byKey(const ValueKey('assignment-file-drop-zone')),
        );
        await native('entered', [point.dx, point.dy]);
        await native('performOperation_macos', [
          {'path': file.path, 'isDirectory': false},
        ]);
        for (var attempt = 0; attempt < 40; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
          if (find.text('Synthetic report.txt').evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();
      }

      await drop();
      expect(find.text('Synthetic report.txt'), findsOneWidget);
      expect(controller.submissions, 0);
      await drop();
      expect(find.text('Synthetic report.txt'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove file'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic report.txt'), findsNothing);
      await drop();
      controller.expire();
      await tester.pumpAndSettle();
      expect(find.text('Synthetic report.txt'), findsNothing);
      expect(
        tester.widget<DropTarget>(find.byType(DropTarget)).enable,
        isFalse,
      );
      expect(controller.submissions, 0);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

void _ignore(List<DropItem> _) {}
void _pick() {}

class _Lease implements AppSessionLease {
  @override
  String get owner => 'synthetic';
  @override
  bool isActive = true;
}

class _Controller extends AppSessionController {
  final lease = _Lease();
  int submissions = 0;
  @override
  AppSessionLease? captureSessionLease() => lease;
  @override
  Future<AssignmentSubmissionOutcome> submitAssignmentFiles({
    required int assignmentId,
    required List<UploadFilePayload> files,
  }) async {
    submissions++;
    return const AssignmentSubmissionOutcome(
      status: 'draft',
      draftSaved: true,
      finalSubmitted: false,
    );
  }

  void expire() {
    lease.isActive = false;
    notifyListeners();
  }
}
