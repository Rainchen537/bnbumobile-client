import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/official_campus_map_page.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';

void main() {
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('map image fills the available canvas at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final image = MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: OfficialCampusMapPage(image: image)),
      );
      await tester.runAsync(
        () => precacheImage(
          image,
          tester.element(find.byType(OfficialCampusMapPage)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NativeMirrorWebView), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final rendered = tester.widget<Image>(find.byType(Image));
      expect(rendered.fit, BoxFit.contain);
      final rotation = tester.widget<RotatedBox>(find.byType(RotatedBox));
      expect(rotation.quarterTurns, width == 390 ? 1 : 0);
      expect(tester.getSize(find.byType(RotatedBox)).width, width);
      expect(
        find.ancestor(
          of: find.byType(AppBar),
          matching: find.byType(RotatedBox),
        ),
        findsNothing,
      );
      expect(rendered.semanticLabel, '官方校园地图');
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.scaleEnabled, isTrue);
      expect(viewer.panEnabled, isTrue);
      expect(viewer.maxScale, 8);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed image offers retry without opening a webpage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OfficialCampusMapPage(
          image: NetworkImage('https://map.example/invalid.jpg'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('内容暂不可用，重试'), findsOneWidget);
    final original = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .key;
    await tester.tap(find.text('内容暂不可用，重试'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).key,
      isNot(original),
    );
    expect(find.byType(NativeMirrorWebView), findsNothing);
  });
}
