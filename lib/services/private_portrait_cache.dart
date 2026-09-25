import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'secure_storage_options.dart';

/// Private Portal photo bytes only, isolated from public campus artwork.
class PrivatePortraitCache {
  PrivatePortraitCache({
    Future<Directory> Function()? directory,
    Future<SecretKey> Function()? key,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _key = key ?? _deviceKey;
  static final shared = PrivatePortraitCache();
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: macOsSecureStorageOptions,
  );
  static Future<SecretKey>? _keyFuture;
  static Future<SecretKey> _deviceKey() => _keyFuture ??=
      (() async {
        const name = 'bnbu.private-portrait.key.v1';
        final stored = await _storage.read(key: name);
        if (stored != null) {
          final bytes = base64Decode(stored);
          if (bytes.length != 32) {
            throw const FormatException('Invalid image key');
          }
          return SecretKey(bytes);
        }
        final key = await AesGcm.with256bits().newSecretKey();
        await _storage.write(
          key: name,
          value: base64Encode(await key.extractBytes()),
        );
        return key;
      })().catchError((Object error) {
        _keyFuture = null;
        throw error;
      });
  final Future<Directory> Function() _directory;
  final Future<SecretKey> Function() _key;
  Future<void> _queue = Future.value();
  final _cipher = AesGcm.with256bits();
  String _owner(String owner) =>
      sha256.convert(utf8.encode(owner.trim().toLowerCase())).toString();
  Future<File> _file(String owner) async => File(
    '${(await _directory()).path}/private-portrait-v1/${_owner(owner)}.bin',
  );
  Future<T?> _serial<T>(Future<T?> Function() action) {
    final result = _queue.then((_) async {
      try {
        return await action();
      } on Object {
        return null;
      }
    });
    _queue = result.then((_) {});
    return result;
  }

  Future<Uint8List?> load(String owner, String source) => _serial(() async {
    final file = await _file(owner);
    if (await file.length() > 5 * 1024 * 1024 + 64) return null;
    return Uint8List.fromList(
      await _cipher.decrypt(
        SecretBox.fromConcatenation(
          await file.readAsBytes(),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: await _key(),
        aad: utf8.encode('${_owner(owner)}:$source'),
      ),
    );
  });
  Future<void> save(String owner, String source, Uint8List bytes) async {
    await _serial<void>(() async {
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) return;
      final file = await _file(owner);
      await file.parent.create(recursive: true);
      final box = await _cipher.encrypt(
        bytes,
        secretKey: await _key(),
        aad: utf8.encode('${_owner(owner)}:$source'),
      );
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(box.concatenation(), flush: true);
      await temporary.rename(file.path);
    });
  }

  Future<void> clear(String owner) async {
    await _serial<void>(() async {
      final file = await _file(owner);
      if (await file.exists()) await file.delete();
    });
  }
}
