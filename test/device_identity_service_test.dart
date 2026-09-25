import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/device_identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/device_identity');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android 同一实体设备在不同安装中生成相同匿名标识', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getPlatformIdentity');
          return 'android-scoped-identity-1234';
        });

    final firstInstall = SecurePhysicalDeviceIdentityProvider(
      channel: channel,
      platformProvider: () => 'android',
    );
    final secondInstall = SecurePhysicalDeviceIdentityProvider(
      channel: channel,
      platformProvider: () => 'android',
    );

    final first = await firstInstall.resolve(
      legacyInstallationId: 'legacy-installation-0000000000000001',
    );
    final second = await secondInstall.resolve();

    expect(first, second);
    expect(first, hasLength(64));
    expect(first, isNot(contains('android-scoped-identity')));
  });
}
