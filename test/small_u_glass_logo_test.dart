import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/widgets/small_u_glass_logo.dart';

void main() {
  test(
    'native glass is confined to the bundled knot alpha, with accessible fallback',
    () {
      final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(source, contains('withId: "ispace/small_u_glass_logo"'));
      expect(source, contains('material.mask = materialMask'));
      expect(source, contains('UIGlassEffect(style: .clear)'));
      expect(
        source,
        contains(
          'UIAccessibility.reduceTransparencyStatusDidChangeNotification',
        ),
      );
      expect(
        source,
        contains(
          'UIAccessibility.darkerSystemColorsStatusDidChangeNotification',
        ),
      );
      expect(source, contains('assets/branding/small_u_light.png'));
    },
  );

  testWidgets(
    'native knot keeps transparent gestures and updates appearance without moving',
    (tester) async {
      final params = <Map<Object?, Object?>>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final args = call.arguments as Map;
          expect(args['viewType'], 'ispace/small_u_glass_logo');
          params.add(
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map<Object?, Object?>,
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.square(
                dimension: 56,
                child: SmallUNativeGlassLogo(dark: dark),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(params.last, {'dark': dark, 'logoExtent': 44.0});
        expect(tester.getSize(find.byType(UiKitView)), const Size.square(56));
        expect(
          tester.widget<UiKitView>(find.byType(UiKitView)).hitTestBehavior,
          PlatformViewHitTestBehavior.transparent,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
