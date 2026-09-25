import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:bnbu_me/services/credential_store.dart';
import 'package:bnbu_me/models/mail_login_settings.dart';
import 'package:bnbu_me/services/secure_storage_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/credential_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FlutterSecureStoragePlatform originalSecureStoragePlatform;

  setUp(() {
    originalSecureStoragePlatform = FlutterSecureStoragePlatform.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    FlutterSecureStoragePlatform.instance = originalSecureStoragePlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'macOS release migrates the old plugin service to the stable service',
    () async {
      final platform = _ServiceAwareSecureStoragePlatform();
      FlutterSecureStoragePlatform.instance = platform;
      platform.writeValue(
        service: macOsLegacyReleaseSecureStorageAccountName,
        key: 'bnbu.credentials.v1',
        value: jsonEncode(<String, String>{
          'username': 'student',
          'password': 'secret',
        }),
      );

      final store = SecureCredentialStore(
        secureStorage: const FlutterSecureStorage(
          mOptions: MacOsOptions(
            accountName: macOsReleaseSecureStorageAccountName,
            usesDataProtectionKeychain: false,
          ),
        ),
        legacyChannel: channel,
        useNativeAndroidStore: false,
        migrateLegacyMacOsStore: true,
      );

      final loaded = await store.load();

      expect(loaded?.username, 'student');
      expect(loaded?.password, 'secret');
      expect(
        platform.readValue(
          service: macOsReleaseSecureStorageAccountName,
          key: 'bnbu.credentials.v1',
        ),
        isNotNull,
      );
      expect(
        platform.readValue(
          service: macOsLegacyReleaseSecureStorageAccountName,
          key: 'bnbu.credentials.v1',
        ),
        isNull,
      );
    },
  );

  test(
    'atomic secure record round-trips independent mail settings and clears both',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureCredentialStore(
        legacyChannel: channel,
        useNativeAndroidStore: false,
        migrateLegacyMacOsStore: false,
      );
      await store.save(
        const StoredCredentials(
          username: 'fixture',
          password: ' 学校 ',
          mail: MailLoginSettings(password: ' 邮件 ', skipped: true),
        ),
      );
      final restored = await store.load();
      expect(restored?.password, ' 学校 ');
      expect(restored?.mail.password, ' 邮件 ');
      expect(restored?.mail.skipped, isTrue);
      await store.clear();
      expect(await store.load(), isNull);
    },
  );

  test(
    'legacy macOS logout tombstone prevents credential resurrection',
    () async {
      final platform = _ServiceAwareSecureStoragePlatform();
      FlutterSecureStoragePlatform.instance = platform;
      platform
        ..writeValue(
          service: macOsLegacyReleaseSecureStorageAccountName,
          key: 'bnbu.credentials.v1',
          value: '{"username":"student","password":"secret"}',
        )
        ..writeValue(
          service: macOsLegacyReleaseSecureStorageAccountName,
          key: 'bnbu.credentials.logout.v1',
          value: 'true',
        );

      final store = SecureCredentialStore(
        secureStorage: const FlutterSecureStorage(
          mOptions: MacOsOptions(
            accountName: macOsReleaseSecureStorageAccountName,
            usesDataProtectionKeychain: false,
          ),
        ),
        legacyChannel: channel,
        useNativeAndroidStore: false,
        migrateLegacyMacOsStore: true,
      );

      expect(await store.load(), isNull);
      expect(
        platform.readValue(
          service: macOsLegacyReleaseSecureStorageAccountName,
          key: 'bnbu.credentials.v1',
        ),
        isNull,
      );
    },
  );

  test(
    'valid primary credentials survive obsolete-copy cleanup failure',
    () async {
      final platform = _ServiceAwareSecureStoragePlatform(
        failingDeleteService: macOsLegacyReleaseSecureStorageAccountName,
      );
      FlutterSecureStoragePlatform.instance = platform;
      platform.writeValue(
        service: macOsReleaseSecureStorageAccountName,
        key: 'bnbu.credentials.v1',
        value: '{"username":"student","password":"secret"}',
      );

      final store = SecureCredentialStore(
        secureStorage: const FlutterSecureStorage(
          mOptions: MacOsOptions(
            accountName: macOsReleaseSecureStorageAccountName,
            usesDataProtectionKeychain: false,
          ),
        ),
        legacyChannel: channel,
        useNativeAndroidStore: false,
        migrateLegacyMacOsStore: true,
      );

      final loaded = await store.load();
      expect(loaded?.username, 'student');
      expect(loaded?.password, 'secret');
    },
  );

  test('native Android store saves and loads one combined record', () async {
    String? primaryRecord;
    var logoutBlocked = true;

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'writeSecureCredentials':
          primaryRecord = (call.arguments as Map)['value'] as String;
          return true;
        case 'readSecureCredentials':
          return primaryRecord;
        case 'clearLegacySecureCredentials':
        case 'clearLegacyCredentials':
          return true;
        case 'readLogoutTombstone':
          return logoutBlocked;
        case 'setLogoutTombstone':
          logoutBlocked = (call.arguments as Map)['blocked'] as bool;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );
    await store.save(
      const StoredCredentials(username: 'student', password: 'secret'),
    );

    expect(logoutBlocked, isFalse);
    final loaded = await store.load();
    expect(loaded?.username, 'student');
    expect(loaded?.password, 'secret');
  });

  test('logout tombstone prevents restore after a failed clear', () async {
    String? primaryRecord = '{"username":"student","password":"secret"}';
    var logoutBlocked = false;
    var failSecureClear = true;

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readSecureCredentials':
          return primaryRecord;
        case 'clearSecureCredentials':
          if (failSecureClear) {
            failSecureClear = false;
            throw PlatformException(code: 'clear_failed');
          }
          primaryRecord = null;
          return true;
        case 'clearLegacyCredentials':
          return true;
        case 'readLogoutTombstone':
          return logoutBlocked;
        case 'setLogoutTombstone':
          logoutBlocked = (call.arguments as Map)['blocked'] as bool;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );

    await expectLater(store.clear(), throwsA(isA<PlatformException>()));
    expect(logoutBlocked, isTrue);
    expect(primaryRecord, isNotNull);

    expect(await store.load(), isNull);
    expect(primaryRecord, isNull);
    expect(logoutBlocked, isTrue);
  });

  test('legacy cleanup failure does not leave a new login blocked', () async {
    String? primaryRecord;
    var logoutBlocked = true;
    var failLegacyCleanup = true;

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'writeSecureCredentials':
          primaryRecord = (call.arguments as Map)['value'] as String;
          return true;
        case 'readSecureCredentials':
          return primaryRecord;
        case 'clearLegacySecureCredentials':
          if (failLegacyCleanup) {
            failLegacyCleanup = false;
            throw PlatformException(code: 'cleanup_failed');
          }
          return true;
        case 'clearLegacyCredentials':
          return true;
        case 'readLogoutTombstone':
          return logoutBlocked;
        case 'setLogoutTombstone':
          logoutBlocked = (call.arguments as Map)['blocked'] as bool;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );

    await expectLater(
      store.save(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(logoutBlocked, isFalse);
    expect(primaryRecord, isNotNull);

    final loaded = await store.load();
    expect(loaded?.username, 'student');
    expect(loaded?.password, 'secret');
  });

  test('present but malformed combined records are not downgraded', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readLogoutTombstone':
          return false;
        case 'readSecureCredentials':
          return 'not-json';
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );

    await expectLater(
      store.load(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'credential_record_corrupt',
        ),
      ),
    );
  });
}

class _ServiceAwareSecureStoragePlatform extends FlutterSecureStoragePlatform {
  _ServiceAwareSecureStoragePlatform({this.failingDeleteService});

  final String? failingDeleteService;
  final Map<String, Map<String, String>> _values = {};

  void writeValue({
    required String service,
    required String key,
    required String value,
  }) {
    (_values[service] ??= {})[key] = value;
  }

  String? readValue({required String service, required String key}) {
    return _values[service]?[key];
  }

  String _service(Map<String, String> options) {
    return options['accountName'] ?? 'missing-service';
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _values[_service(options)]?.containsKey(key) ?? false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    if (_service(options) == failingDeleteService) {
      throw PlatformException(code: 'delete_failed');
    }
    _values[_service(options)]?.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.remove(_service(options));
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _values[_service(options)]?[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map<String, String>.from(_values[_service(options)] ?? const {});

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    writeValue(service: _service(options), key: key, value: value);
  }
}
