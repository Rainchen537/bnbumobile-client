import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_options.dart';

abstract interface class PhysicalDeviceIdentityProvider {
  Future<String> resolve({String? legacyInstallationId});
}

/// Returns an app-scoped, pseudonymous physical-device identity.
///
/// Android derives the value from ANDROID_ID, which remains stable when the
/// same signed app is uninstalled and installed again for the same OS user.
/// Other platforms keep a random identifier in their system credential store;
/// on Apple platforms that means Keychain rather than the app sandbox.
/// Neither the native value nor a hardware serial number is sent to the server.
class SecurePhysicalDeviceIdentityProvider
    implements PhysicalDeviceIdentityProvider {
  SecurePhysicalDeviceIdentityProvider({
    MethodChannel? channel,
    FlutterSecureStorage? secureStorage,
    String? Function()? platformProvider,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(mOptions: macOsSecureStorageOptions),
       _platformProvider = platformProvider ?? _currentPlatform;

  static const _channelName = 'ispace/device_identity';
  static const _storageKey = 'bnbu.physical_device_identity.v1';
  static final _identityPattern = RegExp(r'^[0-9A-Za-z_-]{32,128}$');
  static Future<String>? _secureIdentityCreation;

  final MethodChannel _channel;
  final FlutterSecureStorage _secureStorage;
  final String? Function() _platformProvider;
  Future<String>? _resolvedIdentity;

  @override
  Future<String> resolve({String? legacyInstallationId}) async {
    final cached = _resolvedIdentity;
    if (cached != null) {
      return cached;
    }
    final pending = _resolveOnce(legacyInstallationId: legacyInstallationId);
    _resolvedIdentity = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_resolvedIdentity, pending)) {
        _resolvedIdentity = null;
      }
      rethrow;
    }
  }

  Future<String> _resolveOnce({String? legacyInstallationId}) async {
    final platform = _platformProvider();
    if (platform == 'android') {
      final androidIdentity = await _androidIdentity();
      if (androidIdentity != null) {
        return androidIdentity;
      }
    }

    final stored = await _readStoredIdentity();
    if (stored != null) {
      return stored;
    }

    final pending = _secureIdentityCreation ??= _createAndPersistIdentity(
      legacyInstallationId,
    );
    try {
      return await pending;
    } finally {
      if (identical(_secureIdentityCreation, pending)) {
        _secureIdentityCreation = null;
      }
    }
  }

  Future<String> _createAndPersistIdentity(String? legacyInstallationId) async {
    final stored = await _readStoredIdentity();
    if (stored != null) {
      return stored;
    }
    final legacy = legacyInstallationId?.trim();
    final identity = legacy != null && _identityPattern.hasMatch(legacy)
        ? legacy
        : _createRandomIdentity();
    await _writeStoredIdentity(identity);
    return identity;
  }

  Future<String?> _androidIdentity() async {
    try {
      final raw = (await _channel.invokeMethod<String>(
        'getPlatformIdentity',
      ))?.trim();
      if (raw == null || raw.isEmpty || raw == '9774d56d682e549c') {
        return null;
      }
      return sha256
          .convert(utf8.encode('bnbu.physical-device.v1|android|$raw'))
          .toString();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FlutterError {
      return null;
    } on StateError {
      return null;
    }
  }

  Future<String?> _readStoredIdentity() async {
    try {
      final stored = (await _secureStorage.read(key: _storageKey))?.trim();
      return stored != null && _identityPattern.hasMatch(stored)
          ? stored
          : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FlutterError {
      return null;
    } on StateError {
      return null;
    }
  }

  Future<void> _writeStoredIdentity(String identity) async {
    try {
      await _secureStorage.write(key: _storageKey, value: identity);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } on FlutterError {
      return;
    } on StateError {
      return;
    }
  }

  static String? _currentPlatform() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      _ => null,
    };
  }
}

class FixedPhysicalDeviceIdentityProvider
    implements PhysicalDeviceIdentityProvider {
  const FixedPhysicalDeviceIdentityProvider(this.identity);

  final String identity;

  @override
  Future<String> resolve({String? legacyInstallationId}) async => identity;
}

String _createRandomIdentity() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}
