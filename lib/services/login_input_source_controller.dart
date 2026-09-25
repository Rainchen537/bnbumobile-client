import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LoginInputSourceController {
  const LoginInputSourceController({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const channelName = 'ispace/login_input_source';

  final MethodChannel _channel;

  bool get _usesNativeInputSource =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<bool> activateEnglishKeyboard() async {
    if (!_usesNativeInputSource) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('activateEnglishKeyboard') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> restorePreviousKeyboard() async {
    if (!_usesNativeInputSource) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('restorePreviousKeyboard') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
