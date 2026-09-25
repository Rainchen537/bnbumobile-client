import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../secure_storage_options.dart';

/// An installation marker and a device-only secret must both survive. Old
/// hardware identifiers and legacy enrollment records are never imported.
class MeInstallationStore {
  static const secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: macOsSecureStorageOptions,
  );
  static Future<String>? _pending;
  static String randomSecret() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  static Future<String> marker() => _pending ??= _load().catchError((Object e) {
    _pending = null;
    throw e;
  });

  static Future<String> _load() async {
    if (Platform.isIOS) {
      final value = await const MethodChannel(
        'bnbu/me_identity',
      ).invokeMethod<String>('installationMarker');
      if (value == null || value.length < 32) throw StateError('设备身份存储不可用');
      return value;
    }
    final root = await getApplicationSupportDirectory();
    final file = File('${root.path}/me-installation-v1');
    if (await file.exists()) {
      final value = await file.readAsString();
      if (RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return value;
      throw StateError('设备身份存储损坏，请重新绑定 ME 账户');
    }
    final value = randomSecret();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
    return value;
  }
}
