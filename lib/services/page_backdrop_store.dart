import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import 'network_retry.dart';

/// Public artwork shared across pages. A process takes one immutable snapshot;
/// downloaded manifests are staged atomically for the next process launch.
class PageBackdropStore extends ChangeNotifier {
  PageBackdropStore({
    http.Client? client,
    Future<Directory> Function()? directory,
    Uri? manifestUri,
  }) : _client = client ?? createAppHttpClient(),
       _directory = directory ?? getApplicationSupportDirectory,
       manifestUri = manifestUri ?? AppConfig.pageBackdropManifestUrl;
  static final shared = PageBackdropStore();
  static const defaults = {
    'directory/light': 'assets/me_life/header-campus.png',
    'directory/dark': 'assets/me_life/header-campus-dark.png',
    'me-life/light': 'assets/me_life/header-campus.png',
    'me-life/dark': 'assets/me_life/header-campus-dark.png',
    'user/light': 'assets/user/user_header_light.png',
    'user/dark': 'assets/user/user_header.jpeg',
  };
  static const maxBytes = 5 * 1024 * 1024;
  final http.Client _client;
  final Future<Directory> Function() _directory;
  final Uri manifestUri;
  final _images = <String, Uint8List>{};
  Map<String, dynamic> _active = {};
  Map<String, dynamic>? _staged;
  Future<void>? _local, _refresh, _start;
  Uint8List? bytesFor(String slot) => _images[slot];
  double? opacityFor(String slot) =>
      (_active[slot]?['opacity'] as num?)?.toDouble();
  int activeVersion = 0;
  int get stagedVersion => (_staged?['version'] as int?) ?? activeVersion;

  Future<Directory> _root() async => Directory(
    '${(await _directory()).path}/page-backdrops-v1/${sha256.convert(utf8.encode(manifestUri.toString()))}',
  );
  Future<void> start() => _start ??= () async {
    await loadLocal();
    await checkForUpdate();
  }();
  Future<void> loadLocal() => _local ??= _loadLocal();
  Future<void> _loadLocal() async {
    try {
      final root = await _root();
      final pointer = File('${root.path}/next.json');
      if (await pointer.length() > 16384) return;
      final value = _parse(await pointer.readAsBytes());
      final slots = value['slots'] as Map<String, dynamic>;
      for (final slot in slots.keys) {
        final hash = slots[slot]['sha256'] as String?;
        if (hash == null) continue;
        try {
          _images[slot] = await _readVerified(root, hash);
        } on Object {
          /* Only this invalid slot falls back to its bundled image. */
        }
      }
      _active = slots;
      activeVersion = value['version'] as int;
      // A damaged local slot must be eligible for downloading again.
      if (slots.entries.every(
        (e) => e.value['sha256'] == null || _images.containsKey(e.key),
      )) {
        _staged = value;
      }
      notifyListeners();
    } on Object {
      /* Missing or malformed cache leaves all bundled defaults. */
    }
  }

  Map<String, dynamic> _parse(List<int> raw) {
    final value = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    if (value['schema_version'] != 1 ||
        value['version'] is! int ||
        (value['version'] as int) < 0) {
      throw const FormatException('Invalid artwork version');
    }
    final slots = value['slots'] as Map<String, dynamic>;
    if (slots.length != defaults.length ||
        !slots.keys.every(defaults.containsKey)) {
      throw const FormatException('Invalid artwork slots');
    }
    for (final slot in slots.values) {
      final hash = slot['sha256'];
      final opacity = slot['opacity'];
      if (opacity != null &&
          (opacity is! num ||
              !opacity.isFinite ||
              opacity < 0 ||
              opacity > 1)) {
        throw const FormatException('Invalid opacity');
      }
      if (hash == null) {
        if (slot['image'] != null) {
          throw const FormatException('Unexpected image');
        }
        continue;
      }
      if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const FormatException('Invalid hash');
      }
      final expected = '/v1/public/page-backgrounds/photos/$hash';
      if (slot['image'] != expected) {
        throw const FormatException('Invalid image source');
      }
    }
    return value;
  }

  Future<Uint8List> _readVerified(Directory root, String hash) async {
    final file = File('${root.path}/$hash.image');
    if (await file.length() > maxBytes) {
      throw const FormatException('Oversized artwork');
    }
    final data = await file.readAsBytes();
    if (sha256.convert(data).toString() != hash) {
      throw const FormatException('Artwork hash mismatch');
    }
    await _validateImage(data);
    return data;
  }

  Future<void> checkForUpdate() =>
      _refresh ??= _check().whenComplete(() => _refresh = null);
  Future<void> _check() async {
    await loadLocal();
    try {
      final next = _parse(await _get(manifestUri, 16384));
      if (_staged != null && next['version'] == _staged!['version']) return;
      if ((next['version'] as int) < stagedVersion) return;
      final root = await _root();
      await root.create(recursive: true);
      final slots = next['slots'] as Map<String, dynamic>;
      final keep = <String>{};
      for (final slot in slots.values) {
        final hash = slot['sha256'] as String?;
        if (hash == null || !keep.add(hash)) continue;
        try {
          await _readVerified(root, hash);
          continue;
        } on Object {
          /* Fetch missing/invalid content. */
        }
        final data = await _get(
          manifestUri.resolve(slot['image'] as String),
          maxBytes,
        );
        if (sha256.convert(data).toString() != hash) {
          throw const FormatException('Artwork hash mismatch');
        }
        await _validateImage(data);
        final temporary = File('${root.path}/$hash.tmp');
        await temporary.writeAsBytes(data, flush: true);
        await temporary.rename('${root.path}/$hash.image');
      }
      final pointer = File('${root.path}/next.tmp');
      await pointer.writeAsString(jsonEncode(next), flush: true);
      await pointer.rename('${root.path}/next.json');
      _staged = next;
    } on Object {
      /* Failed staging never replaces the last complete manifest. */
    } finally {
      // Keep only the active/complete-next snapshots, even after partial failure.
      try {
        final keep = <String>{
          ..._active.values.map((s) => s['sha256']).whereType<String>(),
          ...((_staged?['slots'] as Map?)?.values ?? [])
              .map((s) => s['sha256'])
              .whereType<String>(),
        };
        final root = await _root();
        await for (final file in root.list()) {
          if (file is File &&
              file.path.endsWith('.image') &&
              !keep.any((hash) => file.path.endsWith('/$hash.image'))) {
            await file.delete();
          }
        }
      } on Object {
        /* Cleanup failure does not affect the complete snapshot. */
      }
    }
  }

  Future<Uint8List> _get(Uri uri, int limit) async {
    if (uri.scheme != 'https' ||
        uri.origin != manifestUri.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443)) {
      throw const FormatException('Invalid artwork source');
    }
    return (() async {
      final response = await _client.send(
        http.Request('GET', uri)..followRedirects = false,
      );
      if (response.statusCode != 200 || (response.contentLength ?? 0) > limit) {
        throw const FormatException('Artwork unavailable');
      }
      final data = BytesBuilder();
      await for (final chunk in response.stream) {
        if (data.length + chunk.length > limit) {
          throw const FormatException('Artwork too large');
        }
        data.add(chunk);
      }
      return data.takeBytes();
    })().timeout(const Duration(seconds: 12));
  }

  Future<void> _validateImage(Uint8List data) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(data);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > 16000000) {
        throw const FormatException('Artwork dimensions');
      }
      final codec = await descriptor.instantiateCodec(targetWidth: 1920);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
