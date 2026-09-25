import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class EcardBrightnessController {
  Future<void> begin();

  Future<void> end();
}

class PlatformEcardBrightnessController implements EcardBrightnessController {
  PlatformEcardBrightnessController({
    MethodChannel channel = const MethodChannel(_channelName),
    bool? supported,
  }) : _channel = channel,
       _supported =
           supported ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.iOS ||
                   defaultTargetPlatform == TargetPlatform.android));

  static const _channelName = 'ispace/ecard_brightness';

  final MethodChannel _channel;
  final bool _supported;

  @override
  Future<void> begin() => _invoke('begin');

  @override
  Future<void> end() => _invoke('end');

  Future<void> _invoke(String method) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>(method);
    } on MissingPluginException {
      // Older installs and unsupported test hosts keep the system brightness.
    } on PlatformException {
      // Brightness is a convenience; eCard must remain usable if it fails.
    }
  }
}
