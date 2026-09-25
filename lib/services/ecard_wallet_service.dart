import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'network_retry.dart';
import 'sync/device_session_provider.dart';

const ecardWalletConsentVersion = 'wallet-ecard.v1';
const ecardWalletMaxPassBytes = 1024 * 1024;

enum EcardWalletResult { added, alreadyPresent, closed }

enum EcardWalletError {
  unavailable,
  sessionChanged,
  invalidCard,
  network,
  busy,
  layoutUnavailable,
}

class EcardWalletException implements Exception {
  const EcardWalletException(this.reason);
  final EcardWalletError reason;
}

/// Already-resolved eCard values. No credentials, school client, disk cache,
/// residence, inferred identity or AI context belongs in this export.
class EcardWalletCard {
  const EcardWalletCard({
    required this.fullName,
    required this.chineseName,
    required this.englishName,
    required this.studentId,
    required this.department,
    required this.identity,
    this.photo,
  });
  final String fullName;
  final String chineseName;
  final String englishName;
  final String studentId;
  final String department;
  final String identity;
  final Uint8List? photo;

  Map<String, Object?> toWire(Uint8List? preparedPhoto) => {
    'full_name': fullName,
    'chinese_name': chineseName,
    'english_name': englishName,
    'student_id': studentId,
    'department': department,
    'identity': identity,
    'photo_base64': preparedPhoto == null ? null : base64Encode(preparedPhoto),
  };
}

class EcardWalletPass {
  const EcardWalletPass(this.bytes, this.passType, this.serial);
  final Uint8List bytes;
  final String passType;
  final String serial;
}

abstract interface class EcardWalletPlatform {
  Future<bool> isAvailable();
  Future<Uint8List> preparePortrait(Uint8List photo);
  Future<EcardWalletResult> present(EcardWalletPass pass);
  Future<void> dismiss();
}

class NativeEcardWalletPlatform implements EcardWalletPlatform {
  NativeEcardWalletPlatform({
    MethodChannel channel = const MethodChannel('bnbu/ecard_wallet'),
    bool? supported,
  }) : _channel = channel,
       _supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  final MethodChannel _channel;
  final bool _supported;
  final String _presentationId = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<bool> isAvailable() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Uint8List> preparePortrait(Uint8List photo) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'preparePortrait',
      photo,
    );
    if (result == null || result.isEmpty || result.length > 256 * 1024) {
      throw const EcardWalletException(EcardWalletError.invalidCard);
    }
    return result;
  }

  @override
  Future<EcardWalletResult> present(EcardWalletPass pass) async {
    final result = await _channel.invokeMethod<String>('present', {
      'presentationId': _presentationId,
      'bytes': pass.bytes,
      'passType': pass.passType,
      'serial': pass.serial,
    });
    return switch (result) {
      'added' => EcardWalletResult.added,
      'alreadyPresent' => EcardWalletResult.alreadyPresent,
      'closed' => EcardWalletResult.closed,
      _ => throw const EcardWalletException(EcardWalletError.invalidCard),
    };
  }

  @override
  Future<void> dismiss() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('dismiss', {
        'presentationId': _presentationId,
      });
    } on MissingPluginException {
      // Older binaries have no Wallet presentation to dismiss.
    } on PlatformException {
      // Never expose a native error containing private pass data.
    }
  }
}

abstract interface class EcardWalletIssuer {
  Future<String> availability(String owner, bool Function() isCurrent);
  Future<EcardWalletPass> issue({
    required String owner,
    required Map<String, Object?> card,
    required DateTime acceptedAt,
    required String expectedPassType,
    required bool Function() isCurrent,
  });
  void cancel();
}

class RemoteEcardWalletIssuer implements EcardWalletIssuer {
  RemoteEcardWalletIssuer({
    http.Client Function()? clientFactory,
    DeviceSessionProvider? devices,
    String? baseUrl,
  }) : _clientFactory = clientFactory ?? createAppHttpClient,
       _devices = devices ?? DeviceSessionProvider(),
       _baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       );
  final http.Client Function() _clientFactory;
  final DeviceSessionProvider _devices;
  final String _baseUrl;
  final _activeClients = <http.Client>{};
  static final _passType = RegExp(r'^pass\.[A-Za-z0-9.-]{3,180}$');
  static final _serial = RegExp(r'^[a-f0-9]{64}$');

  @override
  void cancel() {
    for (final client in _activeClients.toList()) {
      client.close();
    }
    _activeClients.clear();
  }

  void _check(bool Function() isCurrent) {
    if (!isCurrent()) {
      throw const EcardWalletException(EcardWalletError.sessionChanged);
    }
  }

  Future<(Uint8List, Map<String, String>)> _request({
    required String owner,
    required bool Function() isCurrent,
    required String method,
    required String suffix,
    required String contentType,
    required int limit,
    Map<String, Object?>? body,
  }) async {
    _check(isCurrent);
    // Existing device bearer only; never enroll or read school credentials here.
    final token = await _devices.token(owner);
    _check(isCurrent);
    final request =
        http.Request(method, Uri.parse('$_baseUrl/v1/wallet/ecard$suffix'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Accept': contentType,
          });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
      if (request.bodyBytes.length > 384 * 1024) {
        throw const EcardWalletException(EcardWalletError.invalidCard);
      }
    }
    final client = _clientFactory();
    _activeClients.add(client);
    try {
      return await (() async {
        _check(isCurrent);
        final response = await client.send(request);
        _check(isCurrent);
        if (response.statusCode != 200) {
          await response.stream.listen((_) {}).cancel();
          if (response.statusCode == 401) {
            await _devices.invalidate(owner, token, origin: _baseUrl);
          }
          throw EcardWalletException(
            response.statusCode == 422 || response.statusCode == 413
                ? EcardWalletError.invalidCard
                : response.statusCode == 503 ||
                      response.statusCode == 404 ||
                      response.statusCode == 403
                ? EcardWalletError.unavailable
                : EcardWalletError.network,
          );
        }
        if (response.headers['content-type']?.split(';').first.trim() !=
                contentType ||
            (response.contentLength ?? 0) > limit) {
          await response.stream.listen((_) {}).cancel();
          throw const EcardWalletException(EcardWalletError.invalidCard);
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          _check(isCurrent);
          if (bytes.length + chunk.length > limit) {
            throw const EcardWalletException(EcardWalletError.invalidCard);
          }
          bytes.add(chunk);
        }
        _check(isCurrent);
        if (response.contentLength != null &&
            response.contentLength != bytes.length) {
          throw const EcardWalletException(EcardWalletError.invalidCard);
        }
        return (bytes.takeBytes(), response.headers);
      })().timeout(const Duration(seconds: 20));
    } finally {
      _activeClients.remove(client);
      client.close();
    }
  }

  @override
  Future<String> availability(String owner, bool Function() isCurrent) async {
    final (bytes, _) = await _request(
      owner: owner,
      isCurrent: isCurrent,
      method: 'GET',
      suffix: '/availability',
      contentType: 'application/json',
      limit: 4096,
    );
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['available'] != true ||
        value['consent_version'] != ecardWalletConsentVersion ||
        value['pass_type_identifier'] is! String ||
        !_passType.hasMatch(value['pass_type_identifier'] as String)) {
      throw const EcardWalletException(EcardWalletError.unavailable);
    }
    if (value['supports_gender_omission'] != true ||
        value['layout_version'] is! int ||
        value['layout_version'] != 2 ||
        value['barcode_version'] is! int ||
        value['barcode_version'] != 2) {
      throw const EcardWalletException(EcardWalletError.layoutUnavailable);
    }
    return value['pass_type_identifier'] as String;
  }

  @override
  Future<EcardWalletPass> issue({
    required String owner,
    required Map<String, Object?> card,
    required DateTime acceptedAt,
    required String expectedPassType,
    required bool Function() isCurrent,
  }) async {
    final (bytes, headers) = await _request(
      owner: owner,
      isCurrent: isCurrent,
      method: 'POST',
      suffix: '',
      contentType: 'application/vnd.apple.pkpass',
      limit: ecardWalletMaxPassBytes,
      body: {
        'consent_version': ecardWalletConsentVersion,
        'consent': true,
        'accepted_at': acceptedAt.toUtc().toIso8601String(),
        'card': card,
      },
    );
    final serial = headers['x-wallet-serial'] ?? '';
    if (headers['x-wallet-pass-type'] != expectedPassType ||
        !_serial.hasMatch(serial) ||
        bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4b) {
      throw const EcardWalletException(EcardWalletError.invalidCard);
    }
    return EcardWalletPass(bytes, expectedPassType, serial);
  }
}

/// One explicit export, no persistent consent flag, retry queue or background job.
class EcardWalletFlow {
  EcardWalletFlow({EcardWalletPlatform? platform, EcardWalletIssuer? issuer})
    : platform = platform ?? NativeEcardWalletPlatform(),
      _issuer = issuer ?? RemoteEcardWalletIssuer();
  final EcardWalletPlatform platform;
  final EcardWalletIssuer _issuer;
  int _generation = 0;
  bool _busy = false;

  void cancel() {
    _generation++;
    _issuer.cancel();
    unawaited(platform.dismiss());
  }

  Future<EcardWalletResult> add({
    required String owner,
    required EcardWalletCard card,
    required bool Function() isCurrent,
    required Future<bool> Function() confirm,
  }) async {
    if (_busy) throw const EcardWalletException(EcardWalletError.busy);
    _busy = true;
    final generation = _generation;
    bool active() => generation == _generation && isCurrent();
    void check() {
      if (!active()) {
        throw const EcardWalletException(EcardWalletError.sessionChanged);
      }
    }

    try {
      check();
      if (!RegExp(r'^[0-9]{5,32}$').hasMatch(card.studentId)) {
        throw const EcardWalletException(EcardWalletError.invalidCard);
      }
      if (!await platform.isAvailable()) {
        throw const EcardWalletException(EcardWalletError.unavailable);
      }
      check();
      final passType = await _issuer.availability(owner, active);
      check();
      if (!await confirm()) return EcardWalletResult.closed;
      check();
      final acceptedAt = DateTime.now().toUtc();
      final photo = card.photo == null
          ? null
          : await platform.preparePortrait(card.photo!);
      check();
      final pass = await _issuer.issue(
        owner: owner,
        card: card.toWire(photo),
        acceptedAt: acceptedAt,
        expectedPassType: passType,
        isCurrent: active,
      );
      check();
      final result = await platform.present(pass);
      check();
      return result;
    } on EcardWalletException {
      rethrow;
    } catch (_) {
      // Native/network exceptions may embed private data; never forward them.
      check();
      throw const EcardWalletException(EcardWalletError.network);
    } finally {
      _busy = false;
    }
  }
}
