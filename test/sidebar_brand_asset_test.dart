import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'sidebar brand has real transparent background and visible content',
    () async {
      final asset = await rootBundle.load('assets/branding/sidebar_logo.png');
      final codec = await ui.instantiateImageCodec(asset.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var transparent = 0;
      var solid = 0;
      for (var i = 3; i < data.lengthInBytes; i += 4) {
        final alpha = data.getUint8(i);
        if (alpha == 0) transparent++;
        if (alpha >= 250) solid++;
      }
      expect(transparent, greaterThan(image.width * image.height * .35));
      expect(solid, greaterThan(image.width * image.height * .15));
      for (final xy in [
        (0, 0),
        (image.width - 1, 0),
        (0, image.height - 1),
        (image.width - 1, image.height - 1),
      ]) {
        expect(data.getUint8((xy.$2 * image.width + xy.$1) * 4 + 3), 0);
      }
      image.dispose();
      codec.dispose();
    },
  );
}
