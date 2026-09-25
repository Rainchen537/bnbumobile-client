import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'macOS app icon uses the platform safe area and rounded transparency',
    () {
      final iconFile = File(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      );
      final icon = image.decodePng(iconFile.readAsBytesSync());

      expect(icon, isNotNull);
      expect(icon!.width, 1024);
      expect(icon.height, 1024);
      expect(icon.numChannels, 4);
      expect(icon.getPixel(0, 0).a, 0);
      expect(icon.getPixel(1023, 0).a, 0);
      expect(icon.getPixel(0, 1023).a, 0);
      expect(icon.getPixel(1023, 1023).a, 0);
      expect(icon.getPixel(512, 512).a, 255);

      var minX = icon.width;
      var maxX = -1;
      var minY = icon.height;
      var maxY = -1;
      for (var y = 0; y < icon.height; y += 1) {
        for (var x = 0; x < icon.width; x += 1) {
          if (icon.getPixel(x, y).a == 0) {
            continue;
          }
          minX = x < minX ? x : minX;
          maxX = x > maxX ? x : maxX;
          minY = y < minY ? y : minY;
          maxY = y > maxY ? y : maxY;
        }
      }

      expect(maxX - minX + 1, inInclusiveRange(822, 824));
      expect(maxY - minY + 1, inInclusiveRange(822, 824));
      expect(minX, inInclusiveRange(100, 101));
      expect(minY, inInclusiveRange(100, 101));
    },
  );
}
