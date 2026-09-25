import 'dart:io';

import 'package:flutter/services.dart';

abstract final class IosPlatformCapabilities {
  static const MethodChannel _channel = MethodChannel(
    'ispace/platform_capabilities',
  );

  static Future<bool> supportsLiquidGlass() async {
    if (!Platform.isIOS) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('supportsLiquidGlass') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
