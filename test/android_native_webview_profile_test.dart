import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android ephemeral WebViews do not retain ProfileStore handles', () {
    final source = File(
      'android/app/src/main/kotlin/me/bnbu/app/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('WebViewCompat.setProfile(view, profileName)'));
    expect(
      source,
      isNot(contains('ProfileStore.getInstance().getOrCreateProfile')),
    );
    expect(source, contains('NativeWebProfileCleanup.schedule(profileName)'));
    expect(source, contains('catch (_: IllegalStateException)'));
  });
}
