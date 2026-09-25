import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS exposes a fail-closed Liquid Glass capability channel', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final service = File(
      'lib/services/ios_platform_capabilities.dart',
    ).readAsStringSync();

    expect(delegate, contains('ispace/platform_capabilities'));
    expect(delegate, contains('case "supportsLiquidGlass":'));
    expect(delegate, contains('if #available(iOS 26.0, *)'));
    expect(service, contains("'supportsLiquidGlass'"));
    expect(service, contains('return false;'));
  });
}
