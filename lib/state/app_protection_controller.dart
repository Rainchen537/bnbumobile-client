import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DeviceBiometricType { faceId, touchId, biometric, unavailable }

enum BiometricAuthenticationResult { success, cancelled, unavailable, failure }

abstract interface class BiometricAuthenticator {
  Future<DeviceBiometricType> getAvailableType();

  Future<BiometricAuthenticationResult> authenticate({
    required String localizedReason,
  });
}

class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator({
    LocalAuthentication? localAuthentication,
    TargetPlatform? platform,
  }) : _localAuthentication = localAuthentication ?? LocalAuthentication(),
       _platform = platform ?? defaultTargetPlatform;

  final LocalAuthentication _localAuthentication;
  final TargetPlatform _platform;

  static bool supportsPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  }

  @override
  Future<DeviceBiometricType> getAvailableType() async {
    if (kIsWeb || !supportsPlatform(_platform)) {
      return DeviceBiometricType.unavailable;
    }
    try {
      final biometrics = await _localAuthentication.getAvailableBiometrics();
      if (_platform == TargetPlatform.iOS) {
        if (biometrics.contains(BiometricType.face)) {
          return DeviceBiometricType.faceId;
        }
        if (biometrics.contains(BiometricType.fingerprint)) {
          return DeviceBiometricType.touchId;
        }
      } else if (biometrics.isNotEmpty) {
        // Android deliberately reports only weak/strong classifications on
        // many devices, so do not guess whether the enrolled method is face
        // or fingerprint recognition.
        return DeviceBiometricType.biometric;
      }
    } catch (_) {
      return DeviceBiometricType.unavailable;
    }
    return DeviceBiometricType.unavailable;
  }

  @override
  Future<BiometricAuthenticationResult> authenticate({
    required String localizedReason,
  }) async {
    if (kIsWeb || !supportsPlatform(_platform)) {
      return BiometricAuthenticationResult.unavailable;
    }
    try {
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? BiometricAuthenticationResult.success
          : BiometricAuthenticationResult.cancelled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiometricAuthenticationResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          BiometricAuthenticationResult.unavailable,
        _ => BiometricAuthenticationResult.failure,
      };
    } catch (_) {
      return BiometricAuthenticationResult.failure;
    }
  }
}

class AppProtectionController extends ChangeNotifier {
  AppProtectionController({
    BiometricAuthenticator? authenticator,
    Future<SharedPreferences> Function()? preferencesLoader,
    String Function()? localizedAuthenticationReason,
  }) : _authenticator = authenticator ?? LocalBiometricAuthenticator(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _localizedAuthenticationReason =
           localizedAuthenticationReason ?? (() => defaultAuthenticationReason);

  static const enabledPreferenceKey = 'ios_biometric_app_protection_enabled';
  static const defaultAuthenticationReason = '验证身份以解锁 BNBU.ME';

  final BiometricAuthenticator _authenticator;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final String Function() _localizedAuthenticationReason;

  DeviceBiometricType _availableType = DeviceBiometricType.unavailable;
  bool _enabled = false;
  bool _isLocked = true;
  bool _isRestoring = true;
  bool _isAuthenticating = false;
  bool _isDisposed = false;
  String? _message;

  DeviceBiometricType get availableType => _availableType;
  bool get enabled => _enabled;
  bool get isLocked => _isLocked;
  bool get isRestoring => _isRestoring;
  bool get isAuthenticating => _isAuthenticating;
  String? get message => _message;
  bool get shouldShowGate => _isRestoring || (_enabled && _isLocked);

  String get settingLabel => switch (_availableType) {
    DeviceBiometricType.faceId => 'Face ID 保护',
    DeviceBiometricType.touchId => 'Touch ID 保护',
    DeviceBiometricType.biometric => '生物识别保护',
    DeviceBiometricType.unavailable => '生物识别保护',
  };

  String get unlockLabel => switch (_availableType) {
    DeviceBiometricType.faceId => '使用 Face ID 解锁',
    DeviceBiometricType.touchId => '使用 Touch ID 解锁',
    DeviceBiometricType.biometric => '使用生物识别解锁',
    DeviceBiometricType.unavailable => '验证身份',
  };

  Future<void> initialize() async {
    final results = await Future.wait<Object>([
      _preferencesLoader(),
      _authenticator.getAvailableType(),
    ]);
    if (_isDisposed) return;

    final preferences = results[0] as SharedPreferences;
    _availableType = results[1] as DeviceBiometricType;
    _enabled = preferences.getBool(enabledPreferenceKey) ?? false;
    _isLocked = _enabled;
    _isRestoring = false;
    _message = null;
    notifyListeners();

    if (_enabled) {
      await authenticate();
    }
  }

  Future<String?> setEnabled(bool value) async {
    if (_isRestoring || value == _enabled) return null;

    if (_availableType == DeviceBiometricType.unavailable) {
      _availableType = await _authenticator.getAvailableType();
      if (_isDisposed) return '身份验证未完成，设置未更改。';
      notifyListeners();
    }
    if (_availableType == DeviceBiometricType.unavailable) {
      return '此设备尚未设置 Face ID 或 Touch ID。';
    }

    final result = await _performAuthentication();
    if (result != BiometricAuthenticationResult.success) {
      return _messageForResult(result, settingChange: true);
    }

    final preferences = await _preferencesLoader();
    await preferences.setBool(enabledPreferenceKey, value);
    if (_isDisposed) return null;
    _enabled = value;
    _isLocked = false;
    _message = null;
    notifyListeners();
    return null;
  }

  void lockForBackground() {
    if (_isRestoring || !_enabled || _isLocked) return;
    _isLocked = true;
    _message = null;
    notifyListeners();
  }

  Future<void> handleResumed() async {
    if (!_isRestoring && _enabled && _isLocked) {
      await authenticate();
    }
  }

  Future<void> authenticate() async {
    if (_isRestoring || !_enabled || !_isLocked || _isAuthenticating) return;
    final result = await _performAuthentication();
    if (_isDisposed) return;
    if (result == BiometricAuthenticationResult.success) {
      _isLocked = false;
      _message = null;
    } else {
      _isLocked = true;
      _message = _messageForResult(result);
    }
    notifyListeners();
  }

  Future<BiometricAuthenticationResult> _performAuthentication() async {
    if (_isAuthenticating) {
      return BiometricAuthenticationResult.cancelled;
    }
    _isAuthenticating = true;
    _message = null;
    notifyListeners();
    final result = await _authenticator.authenticate(
      localizedReason: _localizedAuthenticationReason(),
    );
    if (_isDisposed) return result;
    _isAuthenticating = false;
    notifyListeners();
    return result;
  }

  String? _messageForResult(
    BiometricAuthenticationResult result, {
    bool settingChange = false,
  }) {
    final suffix = settingChange ? '，设置未更改。' : '。';
    return switch (result) {
      BiometricAuthenticationResult.success => null,
      BiometricAuthenticationResult.cancelled => '未完成身份验证$suffix',
      BiometricAuthenticationResult.unavailable =>
        'Face ID 或 Touch ID 当前不可用$suffix',
      BiometricAuthenticationResult.failure => '身份验证失败，请重试$suffix',
    };
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
