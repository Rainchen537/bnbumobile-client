import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS and iPadOS opt in to system background fetch', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(appDelegate, contains('setMinimumBackgroundFetchInterval'));
    expect(appDelegate, contains('performFetchWithCompletionHandler'));
    expect(appDelegate, contains('ispace/mail_radar_background'));
    expect(infoPlist, contains('<string>fetch</string>'));
  });

  test('macOS keeps the process alive after its last window closes', () {
    final appDelegate = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(
      appDelegate,
      contains('applicationShouldTerminateAfterLastWindowClosed'),
    );
    expect(appDelegate, contains('return false'));
    expect(appDelegate, contains('applicationShouldHandleReopen'));
    expect(appDelegate, contains('mainFlutterWindow?.makeKeyAndOrderFront'));
  });
}
