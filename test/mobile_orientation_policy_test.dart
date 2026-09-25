import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iPhone is portrait-only while iPad keeps all orientations', () {
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    final phoneBlock = RegExp(
      r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(info)!.group(1)!;
    final ipadBlock = RegExp(
      r'<key>UISupportedInterfaceOrientations~ipad</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(info)!.group(1)!;

    expect(phoneBlock, contains('UIInterfaceOrientationPortrait'));
    expect(phoneBlock, isNot(contains('UIInterfaceOrientationLandscape')));
    expect(ipadBlock, contains('UIInterfaceOrientationPortrait'));
    expect(ipadBlock, contains('UIInterfaceOrientationLandscapeLeft'));
    expect(ipadBlock, contains('UIInterfaceOrientationLandscapeRight'));
  });

  test('Android locks phones to portrait without locking tablets', () {
    final source = File(
      'android/app/src/main/kotlin/me/bnbu/app/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(source, contains('smallestScreenWidthDp < 600'));
    expect(source, contains('SCREEN_ORIENTATION_PORTRAIT'));
    expect(manifest, isNot(contains('android:screenOrientation="portrait"')));
  });
}
