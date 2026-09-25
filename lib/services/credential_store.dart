import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_options.dart';
import '../models/mail_login_settings.dart';

class StoredCredentials {
  const StoredCredentials({
    required this.username,
    required this.password,
    this.mail = const MailLoginSettings(),
  });

  final String username;
  final String password;
  final MailLoginSettings mail;
}

abstract interface class CredentialStore {
  Future<void> save(StoredCredentials credentials);

  Future<StoredCredentials?> load();

  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({
    FlutterSecureStorage? secureStorage,
    FlutterSecureStorage? legacyMacOsSecureStorage,
    MethodChannel? legacyChannel,
    bool? useNativeAndroidStore,
    bool? migrateLegacyMacOsStore,
  }) : _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(migrateWithBackup: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
             mOptions: macOsSecureStorageOptions,
           ),
       _legacyMacOsSecureStorage =
           legacyMacOsSecureStorage ??
           const FlutterSecureStorage(
             mOptions: macOsLegacyReleaseSecureStorageOptions,
           ),
       _legacyChannel =
           legacyChannel ?? const MethodChannel('ispace/credential_store'),
       _useNativeAndroidStore =
           useNativeAndroidStore ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _migrateLegacyMacOsStore =
           migrateLegacyMacOsStore ??
           (!kIsWeb &&
               kReleaseMode &&
               defaultTargetPlatform == TargetPlatform.macOS);

  static const String _credentialsKey = 'bnbu.credentials.v1';
  static const String _legacyUsernameKey = 'bnbu.credentials.username';
  static const String _legacyPasswordKey = 'bnbu.credentials.password';
  static const String _logoutTombstoneKey = 'bnbu.credentials.logout.v1';

  final FlutterSecureStorage _secureStorage;
  final FlutterSecureStorage _legacyMacOsSecureStorage;
  final MethodChannel _legacyChannel;
  final bool _useNativeAndroidStore;
  final bool _migrateLegacyMacOsStore;

  @override
  Future<void> save(StoredCredentials credentials) async {
    final username = credentials.username.trim();
    if (username.isEmpty || credentials.password.isEmpty) {
      throw ArgumentError('Username and password must not be empty.');
    }

    final encoded = _encodeCredentials(credentials);
    await _writePrimaryRecord(encoded);
    await _setLogoutBlocked(false);
    await _cleanupLegacyCopies();
  }

  @override
  Future<StoredCredentials?> load() async {
    if (await _isLogoutBlocked()) {
      await _deleteAllCredentialCopies();
      return null;
    }

    final primaryRaw = await _readPrimaryRecord();
    if (primaryRaw != null) {
      final saved = _decodeCredentials(primaryRaw, source: 'primary');
      await _cleanupLegacyCopiesBestEffort();
      return saved;
    }

    if (_migrateLegacyMacOsStore) {
      final legacyCombined = await _legacyMacOsSecureStorage.read(
        key: _credentialsKey,
      );
      if (legacyCombined != null) {
        final saved = _decodeCredentials(
          legacyCombined,
          source: 'legacy macOS combined',
        );
        await _writePrimaryRecord(_encodeCredentials(saved));
        await _cleanupLegacyMacOsStoreBestEffort();
        return saved;
      }

      final legacySplit = await _loadLegacySecureCredentialsFrom(
        _legacyMacOsSecureStorage,
      );
      if (legacySplit != null) {
        await _writePrimaryRecord(_encodeCredentials(legacySplit));
        await _cleanupLegacyMacOsStoreBestEffort();
        return legacySplit;
      }
    }

    if (_useNativeAndroidStore) {
      final pluginCombined = await _secureStorage.read(key: _credentialsKey);
      if (pluginCombined != null) {
        final saved = _decodeCredentials(
          pluginCombined,
          source: 'legacy combined',
        );
        await _writePrimaryRecord(_encodeCredentials(saved));
        await _cleanupLegacyCopies();
        return saved;
      }
    }

    final splitCredentials = await _loadLegacySecureCredentials();
    if (splitCredentials != null) {
      await _writePrimaryRecord(_encodeCredentials(splitCredentials));
      await _cleanupLegacyCopies();
      return splitCredentials;
    }

    final legacy = await _readLegacyCredentials();
    if (legacy == null) {
      return null;
    }

    await _writePrimaryRecord(_encodeCredentials(legacy));
    await _cleanupLegacyCopies();
    return legacy;
  }

  @override
  Future<void> clear() async {
    var didFail = false;
    try {
      await _setLogoutBlocked(true);
    } catch (_) {
      didFail = true;
    }
    try {
      await _deleteAllCredentialCopies();
    } catch (_) {
      didFail = true;
    }
    if (didFail) {
      throw PlatformException(
        code: 'credential_clear_failed',
        message: 'One or more credential records could not be cleared.',
      );
    }
  }

  String _encodeCredentials(StoredCredentials credentials) {
    return jsonEncode(<String, Object>{
      'username': credentials.username.trim(),
      'password': credentials.password,
      if (credentials.mail.password != null ||
          credentials.mail.skipped ||
          credentials.mail.needsPassword)
        'mail': credentials.mail.toJson(),
    });
  }

  StoredCredentials _decodeCredentials(String raw, {required String source}) {
    if (raw.trim().isEmpty) {
      throw PlatformException(
        code: 'credential_record_corrupt',
        message: 'The $source credential record is empty.',
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Credential record is not an object.');
      }
      final credentials = _credentialsFromMap(decoded.cast<dynamic, dynamic>());
      if (credentials == null) {
        throw const FormatException('Credential fields are incomplete.');
      }
      return credentials;
    } on FormatException catch (error) {
      throw PlatformException(
        code: 'credential_record_corrupt',
        message: 'The $source credential record is invalid: ${error.message}',
      );
    }
  }

  Future<String?> _readPrimaryRecord() {
    if (_useNativeAndroidStore) {
      return _legacyChannel.invokeMethod<String>('readSecureCredentials');
    }
    return _secureStorage.read(key: _credentialsKey);
  }

  Future<void> _writePrimaryRecord(String value) async {
    if (_useNativeAndroidStore) {
      final written = await _legacyChannel.invokeMethod<bool>(
        'writeSecureCredentials',
        <String, Object>{'value': value},
      );
      if (written != true) {
        throw PlatformException(
          code: 'credential_write_failed',
          message: 'Unable to durably write secure credentials.',
        );
      }
      return;
    }
    await _secureStorage.write(key: _credentialsKey, value: value);
  }

  Future<void> _deletePrimaryRecord() async {
    if (_useNativeAndroidStore) {
      final cleared = await _legacyChannel.invokeMethod<bool>(
        'clearSecureCredentials',
      );
      if (cleared != true) {
        throw PlatformException(
          code: 'credential_clear_failed',
          message: 'Unable to durably clear secure credentials.',
        );
      }
      return;
    }
    await _secureStorage.delete(key: _credentialsKey);
  }

  Future<StoredCredentials?> _loadLegacySecureCredentials() async {
    return _loadLegacySecureCredentialsFrom(_secureStorage);
  }

  Future<StoredCredentials?> _loadLegacySecureCredentialsFrom(
    FlutterSecureStorage storage,
  ) async {
    final values = await Future.wait([
      storage.read(key: _legacyUsernameKey),
      storage.read(key: _legacyPasswordKey),
    ]);
    if (values[0] == null && values[1] == null) {
      return null;
    }
    final credentials = _credentialsFromMap(<String, dynamic>{
      'username': values[0],
      'password': values[1],
    });
    if (credentials == null) {
      throw PlatformException(
        code: 'legacy_credential_record_corrupt',
        message: 'Legacy secure credential fields are incomplete.',
      );
    }
    return credentials;
  }

  Future<StoredCredentials?> _readLegacyCredentials() async {
    try {
      final raw = await _legacyChannel.invokeMethod<dynamic>(
        'readLegacyCredentials',
      );
      if (raw == null) {
        return null;
      }
      if (raw is! Map) {
        throw PlatformException(
          code: 'legacy_credential_record_corrupt',
          message: 'Legacy credential data has an invalid format.',
        );
      }
      final credentials = _credentialsFromMap(raw.cast<dynamic, dynamic>());
      if (credentials == null) {
        throw PlatformException(
          code: 'legacy_credential_record_corrupt',
          message: 'Legacy credential fields are incomplete.',
        );
      }
      return credentials;
    } on MissingPluginException {
      return null;
    }
  }

  StoredCredentials? _credentialsFromMap(Map<dynamic, dynamic> data) {
    final rawUsername = data['username'];
    final rawPassword = data['password'];
    if (rawUsername is! String || rawPassword is! String) {
      return null;
    }
    final username = rawUsername.trim();
    if (username.isEmpty || rawPassword.isEmpty) {
      return null;
    }
    return StoredCredentials(
      username: username,
      password: rawPassword,
      mail: MailLoginSettings.fromJson(data['mail']),
    );
  }

  Future<void> _cleanupLegacyCopies() async {
    var didFail = false;
    if (_useNativeAndroidStore) {
      try {
        final cleared = await _legacyChannel.invokeMethod<bool>(
          'clearLegacySecureCredentials',
        );
        if (cleared != true) {
          didFail = true;
        }
      } catch (_) {
        didFail = true;
      }
    } else {
      for (final key in <String>[_legacyUsernameKey, _legacyPasswordKey]) {
        try {
          await _secureStorage.delete(key: key);
        } catch (_) {
          didFail = true;
        }
      }
    }
    try {
      await _clearLegacyCredentials();
    } catch (_) {
      didFail = true;
    }
    if (_migrateLegacyMacOsStore) {
      try {
        await _deleteLegacyMacOsCredentials();
        await _legacyMacOsSecureStorage.delete(key: _logoutTombstoneKey);
      } catch (_) {
        didFail = true;
      }
    }
    if (didFail) {
      throw PlatformException(
        code: 'legacy_credential_cleanup_failed',
        message: 'One or more legacy credential records remain.',
      );
    }
  }

  Future<void> _deleteAllCredentialCopies() async {
    var didFail = false;
    try {
      await _deletePrimaryRecord();
    } catch (_) {
      didFail = true;
    }
    if (!_useNativeAndroidStore) {
      for (final key in <String>[_legacyUsernameKey, _legacyPasswordKey]) {
        try {
          await _secureStorage.delete(key: key);
        } catch (_) {
          didFail = true;
        }
      }
    }
    if (_migrateLegacyMacOsStore) {
      try {
        await _deleteLegacyMacOsCredentials();
      } catch (_) {
        didFail = true;
      }
    }
    try {
      await _clearLegacyCredentials();
    } catch (_) {
      didFail = true;
    }
    if (didFail) {
      throw PlatformException(
        code: 'credential_clear_failed',
        message: 'One or more credential records could not be cleared.',
      );
    }
  }

  Future<bool> _isLogoutBlocked() async {
    if (_useNativeAndroidStore) {
      return await _legacyChannel.invokeMethod<bool>('readLogoutTombstone') ??
          false;
    }

    final secureBlocked =
        await _secureStorage.read(key: _logoutTombstoneKey) != null;
    final legacyMacOsBlocked =
        _migrateLegacyMacOsStore &&
        await _legacyMacOsSecureStorage.read(key: _logoutTombstoneKey) != null;
    if (!_usesNativeIosLogoutTombstone) {
      return secureBlocked || legacyMacOsBlocked;
    }
    try {
      final nativeBlocked =
          await _legacyChannel.invokeMethod<bool>('readLogoutTombstone') ??
          false;
      return secureBlocked || nativeBlocked;
    } on MissingPluginException {
      return secureBlocked;
    }
  }

  bool get _usesNativeIosLogoutTombstone =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _setLogoutBlocked(bool blocked) async {
    if (_useNativeAndroidStore) {
      final updated = await _legacyChannel.invokeMethod<bool>(
        'setLogoutTombstone',
        <String, Object>{'blocked': blocked},
      );
      if (updated != true) {
        throw PlatformException(
          code: 'logout_tombstone_failed',
          message: 'Unable to durably update logout state.',
        );
      }
      return;
    }

    Object? firstError;
    if (_usesNativeIosLogoutTombstone) {
      try {
        final updated = await _legacyChannel.invokeMethod<bool>(
          'setLogoutTombstone',
          <String, Object>{'blocked': blocked},
        );
        if (updated != true) {
          throw PlatformException(
            code: 'logout_tombstone_failed',
            message: 'Unable to durably update native logout state.',
          );
        }
      } on MissingPluginException {
        // Older iOS builds only persisted the Keychain tombstone.
      } catch (error) {
        firstError = error;
      }
    }

    try {
      if (blocked) {
        await _secureStorage.write(key: _logoutTombstoneKey, value: 'true');
      } else {
        await _secureStorage.delete(key: _logoutTombstoneKey);
      }
    } catch (error) {
      firstError ??= error;
    }
    if (_migrateLegacyMacOsStore) {
      try {
        if (blocked) {
          await _legacyMacOsSecureStorage.write(
            key: _logoutTombstoneKey,
            value: 'true',
          );
        } else {
          await _legacyMacOsSecureStorage.delete(key: _logoutTombstoneKey);
        }
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw firstError;
    }
  }

  Future<void> _clearLegacyCredentials() async {
    try {
      final cleared = await _legacyChannel.invokeMethod<bool>(
        'clearLegacyCredentials',
      );
      if (cleared != true) {
        throw PlatformException(
          code: 'legacy_clear_failed',
          message: 'Unable to durably clear legacy credentials.',
        );
      }
    } on MissingPluginException {
      // Legacy native storage only exists on Android and iOS.
    }
  }

  Future<void> _deleteLegacyMacOsCredentials() async {
    for (final key in <String>[
      _credentialsKey,
      _legacyUsernameKey,
      _legacyPasswordKey,
    ]) {
      await _legacyMacOsSecureStorage.delete(key: key);
    }
  }

  Future<void> _cleanupLegacyMacOsStoreBestEffort() async {
    try {
      await _deleteLegacyMacOsCredentials();
      await _legacyMacOsSecureStorage.delete(key: _logoutTombstoneKey);
    } catch (_) {
      // The stable primary record is already durable. A later save/logout
      // retries cleanup without blocking this launch's session restore.
    }
  }

  Future<void> _cleanupLegacyCopiesBestEffort() async {
    try {
      await _cleanupLegacyCopies();
    } catch (_) {
      // A valid primary record must remain usable even if obsolete copies
      // cannot be removed in this process. Save/logout retries cleanup.
    }
  }
}
