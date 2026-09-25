import 'package:flutter/services.dart';

/// Only OS-observed Notification Center entries, never pending requests.
class AppleStatisticsBridge {
  AppleStatisticsBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bnbu/apple_statistics');

  final MethodChannel _channel;
  int _visibilityRevision = -1;
  bool _watching = false;

  Future<List<Map<String, dynamic>>> readDelivered({
    required String owner,
    required DateTime consentAt,
  }) async {
    final values = await _channel.invokeListMethod<dynamic>('readDelivered', {
      'owner': owner,
      'since_ms': consentAt.millisecondsSinceEpoch,
    });
    return (values ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<void> watchVisibility(void Function(bool) changed) async {
    _watching = true;
    void accept(dynamic raw) {
      if (!_watching) return;
      if (raw is! Map || raw['visible'] is! bool || raw['revision'] is! int) {
        return;
      }
      final revision = raw['revision'] as int;
      if (revision <= _visibilityRevision) return;
      _visibilityRevision = revision;
      changed(raw['visible'] as bool);
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'visibilityChanged') accept(call.arguments);
    });
    accept(await _channel.invokeMethod<dynamic>('getVisibility'));
  }

  void dispose() {
    if (_watching) _channel.setMethodCallHandler(null);
    _watching = false;
  }
}
