import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../secure_storage_options.dart';

/// Shared encrypted, atomic records for sync intent and account preferences.
/// A failed/corrupt read is an error, never an empty record that can overwrite cloud data.
class AccountSyncStorage {
  AccountSyncStorage({
    Future<Directory> Function()? directory,
    Future<SecretKey> Function()? key,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _key = key ?? _deviceKey;
  static final shared = AccountSyncStorage();
  static Future<SecretKey>? _keyFuture;
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: macOsSecureStorageOptions,
  );
  final Future<Directory> Function() _directory;
  final Future<SecretKey> Function() _key;
  final _cipher = AesGcm.with256bits();
  final Map<String, Future<void>> _queues = {};
  static String account(String owner) {
    final normalized = owner.trim().toLowerCase();
    for (final suffix in ['@mail.bnbu.edu.cn', '@bnbu.edu.cn']) {
      if (normalized.endsWith(suffix)) {
        return normalized.substring(0, normalized.length - suffix.length);
      }
    }
    return normalized;
  }

  static Future<SecretKey> _deviceKey() => _keyFuture ??= (() async {
    try {
      const name = 'bnbu.account-sync.key.v1';
      final encoded = await _secure.read(key: name);
      if (encoded != null) {
        final bytes = base64Decode(encoded);
        if (bytes.length != 32) throw const FormatException('Invalid sync key');
        return SecretKey(bytes);
      }
      final key = await AesGcm.with256bits().newSecretKey();
      await _secure.write(
        key: name,
        value: base64Encode(await key.extractBytes()),
      );
      return key;
    } catch (_) {
      _keyFuture = null;
      rethrow;
    }
  })();
  String _id(String owner, String domain) =>
      sha256.convert(utf8.encode('${account(owner)}\u0000$domain')).toString();
  Future<File> _file(String id) async =>
      File('${(await _directory()).path}/account-sync-v1/$id.bin');
  Future<Map<String, dynamic>?> read(String owner, String domain) async {
    final id = _id(owner, domain);
    await _queues[id];
    final file = await _file(id);
    if (!await file.exists()) return null;
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('Sync record too large');
    }
    final bytes = await _cipher.decrypt(
      SecretBox.fromConcatenation(
        await file.readAsBytes(),
        nonceLength: 12,
        macLength: 16,
      ),
      secretKey: await _key(),
      aad: utf8.encode(id),
    );
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  }

  Future<void> write(String owner, String domain, Map<String, dynamic> value) {
    return _write(owner, domain, value);
  }

  /// Local sensitive choices can revoke an in-flight write on session change.
  /// Existing sync callers retain their original write contract.
  Future<void> writeIfCurrent(
    String owner,
    String domain,
    Map<String, dynamic> value, {
    required bool Function() isCurrent,
  }) => _write(owner, domain, value, isCurrent: isCurrent);

  Future<void> _write(
    String owner,
    String domain,
    Map<String, dynamic> value, {
    bool Function()? isCurrent,
  }) {
    void check() {
      if (isCurrent?.call() == false) throw StateError('Stale account write');
    }

    check();
    final id = _id(owner, domain);
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > 6 * 1024 * 1024) {
      throw const FormatException('Sync record too large');
    }
    final task = (_queues[id] ?? Future<void>.value()).then((_) async {
      check();
      final file = await _file(id);
      await file.parent.create(recursive: true);
      final box = await _cipher.encrypt(
        bytes,
        secretKey: await _key(),
        aad: utf8.encode(id),
      );
      final temp = File('${file.path}.tmp');
      check();
      try {
        await temp.writeAsBytes(box.concatenation(), flush: true);
        check();
        await temp.rename(file.path);
      } catch (_) {
        if (await temp.exists()) await temp.delete();
        rethrow;
      }
    });
    _queues[id] = task.catchError((Object _) {});
    return task;
  }
}
