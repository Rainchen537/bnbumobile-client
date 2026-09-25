import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'network_retry.dart';

/// Public artwork only; no school session, cookies or authenticated client.
/// Immutable files and a validated pointer preserve the previous offline copy.
class OfficialCampusMapStore extends ChangeNotifier {
  OfficialCampusMapStore({
    http.Client? client,
    Future<Directory> Function()? directory,
  }) : _client = client ?? createAppHttpClient(),
       _directory = directory ?? getApplicationSupportDirectory;
  static final shared = OfficialCampusMapStore();
  static const imageUrl = 'https://www.bnbu.edu.cn/images/shouhuiditu2025.jpg';
  static const bundledAsset = 'assets/campus/official-map.jpg';
  static const maxBytes = 16 * 1024 * 1024;
  final http.Client _client;
  final Future<Directory> Function() _directory;
  Uint8List? bytes;
  String? _path;
  String? _hash;
  DateTime? _checkedAt;
  Future<void>? _local;
  Future<void>? _refresh;
  bool _disposed = false;

  Future<Directory> _root() async =>
      Directory('${(await _directory()).path}/official-campus-map-v1');
  Future<void> loadLocal() => _local ??= _loadLocal();
  Future<void> _loadLocal() async {
    try {
      final root = await _root();
      final pointer = File('${root.path}/current');
      final hash = (await pointer.readAsString()).trim();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) return;
      final file = File('${root.path}/$hash.jpg');
      if (await file.length() > maxBytes) return;
      final data = await file.readAsBytes();
      if (sha256.convert(data).toString() != hash) return;
      await _validate(data);
      if (_disposed) return;
      bytes = data;
      _hash = hash;
      _path = file.path;
      _checkedAt = await pointer.lastModified();
      if (!_disposed) notifyListeners();
    } on Object {
      // Bundled map is immediately available even without writable storage.
    }
  }

  Future<void> refresh({bool force = false}) =>
      _refresh ??= _update(force).whenComplete(() => _refresh = null);

  Future<void> _update(bool force) async {
    await loadLocal();
    if (_disposed) return;
    if (!force &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < const Duration(days: 1)) {
      return;
    }
    try {
      final data = await _download().timeout(const Duration(seconds: 20));
      await _validate(data);
      if (_disposed) return;
      final hash = sha256.convert(data).toString();
      final root = await _root();
      await root.create(recursive: true);
      final path = '${root.path}/$hash.jpg';
      if (hash != _hash || !await File(path).exists()) {
        final temporary = File('$path.tmp');
        await temporary.writeAsBytes(data, flush: true);
        await temporary.rename(path);
      }
      final pointer = File('${root.path}/current.tmp');
      await pointer.writeAsString(hash, flush: true);
      await pointer.rename('${root.path}/current');
      _path = path;
      _checkedAt = DateTime.now();
      if (!_disposed && hash != _hash) {
        bytes = data;
        _hash = hash;
        notifyListeners();
      }
    } on Object {
      // Failed refresh never clears either the visible map or valid cache.
    }
  }

  Future<Uint8List> _download() async {
    final response = await _client.send(
      http.Request('GET', Uri.parse(imageUrl))..followRedirects = false,
    );
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > maxBytes) {
      throw const FormatException('Map unavailable');
    }
    final builder = BytesBuilder();
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      if (builder.length + chunk.length > maxBytes) {
        throw const FormatException('Map too large');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _validate(Uint8List data) async {
    // The official source and exported filename both promise JPEG.
    if (data.length < 4 ||
        data[0] != 0xff ||
        data[1] != 0xd8 ||
        data[data.length - 2] != 0xff ||
        data.last != 0xd9) {
      throw const FormatException('Invalid map image');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(data);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > 40000000) {
          throw const FormatException('Map dimensions');
        }
        final codec = await descriptor.instantiateCodec(targetWidth: 1400);
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  /// Saves exactly the local version being shown; sharing never makes a request.
  Future<String> localPath() async {
    await loadLocal();
    if (_path != null && await File(_path!).exists()) return _path!;
    final root = await _root();
    await root.create(recursive: true);
    final data =
        bytes ?? (await rootBundle.load(bundledAsset)).buffer.asUint8List();
    final file = File('${root.path}/bundled-map.jpg');
    await file.writeAsBytes(data, flush: true);
    return file.path;
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
