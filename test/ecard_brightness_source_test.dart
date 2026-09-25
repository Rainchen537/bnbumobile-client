import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS eCard brightness session saves and restores the original value',
    () {
      final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

      expect(source, contains('name: "ispace/ecard_brightness"'));
      expect(
        source,
        contains('ecardOriginalBrightness = UIScreen.main.brightness'),
      );
      expect(source, contains('UIScreen.main.brightness = 1'));
      expect(source, contains('UIScreen.main.brightness = originalBrightness'));
      expect(source, contains('applicationWillResignActive'));
      expect(source, contains('applicationWillTerminate'));
    },
  );

  test('Android eCard brightness changes only the current app window', () {
    final source = File(
      'android/app/src/main/kotlin/me/bnbu/app/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(source, contains('"ispace/ecard_brightness"'));
    expect(
      source,
      contains('ecardOriginalBrightness = attributes.screenBrightness'),
    );
    expect(source, contains('attributes.screenBrightness = 1.0f'));
    expect(
      source,
      contains('attributes.screenBrightness = originalBrightness'),
    );
    expect(source, contains('override fun onPause()'));
    expect(source, contains('override fun onDestroy()'));
    expect(manifest, isNot(contains('android.permission.WRITE_SETTINGS')));
  });
}
