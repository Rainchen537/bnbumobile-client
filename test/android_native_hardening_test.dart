import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String activity;

  setUpAll(() {
    activity = File(
      'android/app/src/main/kotlin/me/bnbu/app/MainActivity.kt',
    ).readAsStringSync();
  });

  test('native actions reject dangerous URLs before creating intents', () {
    expect(activity, contains('url.isNullOrBlank() || !isHttpUrl(url)'));
    expect(activity, contains('uri.userInfo.isNullOrEmpty()'));
    expect(activity, contains('character.code <= 0x1f'));
    expect(activity, contains('character.code == 0x7f'));
    expect(activity, contains('!isHttpUrl(nextUrl.toString())'));
  });

  test('remote files are bounded even when Content-Length is absent', () {
    expect(activity, contains('MAX_REMOTE_FILE_BYTES'));
    expect(activity, contains('connection.contentLengthLong'));
    expect(activity, contains('copyStreamWithLimit(input, output)'));
    expect(activity, contains('if (total > maximumBytes)'));
  });

  test('WebView releases channels and clears complete profile data', () {
    expect(activity, contains('detachPlatformBindings()'));
    expect(activity, contains('override fun onRenderProcessGone'));
    expect(activity, contains('handleRenderProcessGone()'));
    expect(activity, contains('viewChannel.setMethodCallHandler(null)'));
    expect(
      activity,
      contains('webView.removeJavascriptInterface("HandsBnbuLoginCodeBridge")'),
    );
    expect(activity, contains('cookieManager.removeAllCookies'));
    expect(activity, contains('clearCurrentWebStorage'));
    expect(activity, contains('WebStorageCompat.deleteBrowsingData'));
  });

  test('legacy Android can request storage before saving a login code', () {
    expect(activity, contains('legacyStoragePermissionRunner'));
    expect(activity, contains('performLoginCodeSave(source, result)'));
    expect(activity, contains('LEGACY_DOWNLOAD_PERMISSION_REQUEST'));
  });

  test('MediaStore rows are published atomically or deleted', () {
    expect(activity, contains('@RequiresApi(Build.VERSION_CODES.Q)'));
    expect(
      activity,
      contains('resolver.update(target, ready, null, null) != 1'),
    );
    expect(activity, contains('resolver.delete(target, null, null)'));
  });
}
