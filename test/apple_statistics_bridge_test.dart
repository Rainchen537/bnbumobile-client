import 'package:bnbu_me/services/apple_statistics_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('statistics-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('native observation carries only owner and consent context', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readDelivered');
      expect(call.arguments, {'owner': 'a' * 64, 'since_ms': 1789000000000});
      return [
        {'notification_id': 'fixture', 'stage': 'displayed'},
      ];
    });
    final bridge = AppleStatisticsBridge(channel: channel);
    expect(
      (await bridge.readDelivered(
        owner: 'a' * 64,
        consentAt: DateTime.fromMillisecondsSinceEpoch(1789000000000),
      )).length,
      1,
    );
    bridge.dispose(); // no visibility handler was registered
  });
  test(
    'stale visibility snapshots cannot undo the latest native edge',
    () async {
      const codec = StandardMethodCodec();
      Future<void> event(Object? value) async {
        await messenger.handlePlatformMessage(
          'statistics-test',
          codec.encodeMethodCall(MethodCall('visibilityChanged', value)),
          (_) {},
        );
      }

      messenger.setMockMethodCallHandler(channel, (_) async {
        await event({'revision': 2, 'visible': true});
        return {'revision': 1, 'visible': false};
      });
      final values = <bool>[];
      final bridge = AppleStatisticsBridge(channel: channel);
      await bridge.watchVisibility(values.add);
      await event({'revision': 2, 'visible': false});
      await event({'revision': 3, 'visible': false});
      await event({'revision': 'invalid', 'visible': true});
      expect(values, [true, false]);
      bridge.dispose();
      await event({'revision': 4, 'visible': true});
      expect(values, [true, false]);
    },
  );
}
