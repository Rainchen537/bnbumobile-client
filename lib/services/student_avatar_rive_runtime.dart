import 'package:rive/rive.dart';

class StudentAvatarRiveRuntime {
  StudentAvatarRiveRuntime._();

  static Future<bool>? _initialization;

  static bool get isReady => RiveNative.isInitialized;

  static Future<bool> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<bool> _initialize() async {
    try {
      return await RiveNative.init();
    } catch (_) {
      return false;
    }
  }
}
