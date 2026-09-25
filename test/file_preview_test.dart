import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/file_preview_page.dart';
import 'package:bnbu_me/widgets/file_preview_frame.dart';

void main() {
  test('short PDF stays at the top and larger pages retain bounded pan', () {
    expect(
      filePreviewCenter(
        const Offset(200, 250),
        const Size(400, 800),
        const Size(400, 500),
        1,
      ),
      const Offset(200, 400),
    );
    expect(
      filePreviewCenter(
        const Offset(-10, 3000),
        const Size(400, 800),
        const Size(600, 2000),
        1,
      ),
      const Offset(200, 1600),
    );
  });

  testWidgets(
    'preview keeps its route while share fails and never opens automatically',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('bnbu-preview-test-');
      final file = File('${dir.path}/test.bin')..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => dir.deleteSync(recursive: true));
      final calls = <MethodCall>[];
      const channel = MethodChannel('ispace/native_actions');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'shareLocalFile') {
              throw PlatformException(code: 'no_presenter');
            }
            return false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FilePreviewPage(
            path: file.path,
            title: 'test.bin',
            mimeType: 'application/octet-stream',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存或分享').last);
      await tester.pumpAndSettle();
      expect(calls.single.method, 'shareLocalFile');
      expect((calls.single.arguments as Map)['path'], file.path);
      expect(find.byType(FilePreviewPage), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('shared header has native geometry at $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: FilePreviewAppBar(
              title: 'a very long document file name.pdf',
              onShare: () {},
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(AppBar)).height,
        FilePreviewMetrics.toolbarHeight,
      );
      expect(find.byTooltip('更多'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
