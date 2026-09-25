import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/campus_landmark.dart';
import '../models/me_life_presentation.dart';
import '../models/landmark_review.dart';
import 'network_retry.dart';

/// Public operator-authored content only; never uses the school HTTP clients.
class CampusLandmarkStore extends ChangeNotifier {
  CampusLandmarkStore({
    http.Client? client,
    Future<Directory> Function()? directory,
    String? baseUrl,
    bool photoDiagnostics = const bool.fromEnvironment(
      'ME_LIFE_PHOTO_DIAGNOSTICS',
    ),
  }) : _client = client ?? createAppHttpClient(),
       _photoDiagnostics = photoDiagnostics,
       _directory = directory ?? getApplicationSupportDirectory,
       baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       );
  static final shared = CampusLandmarkStore();
  final http.Client _client;
  final Future<Directory> Function() _directory;
  final String baseUrl;
  final bool _photoDiagnostics;
  final List<Map<String, Object?>> _photoEvents = [];
  Future<void> _diagnosticWrites = Future.value();
  LandmarkCatalog? catalog;
  List<String> _rankedIds = const [];
  List<CampusLandmark> get rankedLandmarks {
    final items = catalog?.landmarks ?? const <CampusLandmark>[];
    if (_rankedIds.isEmpty) return items;
    final byId = {for (final item in items) item.id: item};
    return [
      for (final id in _rankedIds)
        if (byId.containsKey(id)) byId[id]!,
      for (final item in items)
        if (!_rankedIds.contains(item.id)) item,
    ];
  }

  bool refreshing = false, failed = false;
  int presentationEpoch = 0;
  final Map<String, LifeUnitPresentation> _presentations = {};
  final Map<String, Future<LifeUnitPresentation>> _presentationRequests = {};
  final Map<String, Future<CommunityPolicy>> _policyRequests = {};
  final _publicReads = _LandmarkWorkPool(4);
  final _photoDownloads = _LandmarkWorkPool(3);
  Future<void>? _local, _refresh;
  Future<void> _cacheWrites = Future.value();
  final Map<String, Future<File?>> _photos = {};
  bool _disposed = false;

  Future<Directory> _root() async => Directory(
    '${(await _directory()).path}/campus-landmarks-v1-${sha256.convert(utf8.encode(baseUrl)).toString().substring(0, 16)}',
  );
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadLocal() => _local ??= _loadLocal();
  Future<void> _loadLocal() async {
    try {
      final file = File('${(await _root()).path}/catalog.json');
      if (await file.length() > 2 * 1024 * 1024) return;
      final next = LandmarkCatalog.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      catalog = next;
      _notify();
    } on Object {
      /* A damaged cache is a cache miss. */
    }
  }

  Future<void> refresh() =>
      _refresh ??= _refreshCatalog().whenComplete(() => _refresh = null);
  Future<void> _refreshCatalog() async {
    await loadLocal();
    refreshing = true;
    failed = false;
    _notify();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/v1/public/landmarks'),
      )..followRedirects = false;
      if (catalog != null) {
        request.headers['If-None-Match'] = '"landmarks-${catalog!.version}"';
      }
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 304 && catalog != null) {
        await response.stream.drain<void>().timeout(
          const Duration(seconds: 12),
        );
        return;
      }
      final bytes = await _read(response, 2 * 1024 * 1024);
      final next = LandmarkCatalog.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
      if (catalog != null && next.version < catalog!.version) return;
      if (catalog?.version != next.version) _rankedIds = const [];
      try {
        await _write('catalog.json', bytes);
      } on Object {
        /* Display verified data even if storage is full. */
      }
      catalog = next;
    } on Object {
      failed = true;
    } finally {
      if (!failed) {
        await _refreshRanking();
        presentationEpoch++;
        _presentations.clear();
        _presentationRequests.clear();
      }
      refreshing = false;
      _notify();
    }
  }

  Future<void> _refreshRanking() async {
    final version = catalog?.version;
    if (version == null) return;
    try {
      final response = await _client
          .send(
            http.Request(
              'GET',
              Uri.parse('$baseUrl/v2/public/landmarks/ranking'),
            )..followRedirects = false,
          )
          .timeout(const Duration(seconds: 12));
      final result =
          jsonDecode(utf8.decode(await _read(response, 64 * 1024)))
              as Map<String, dynamic>;
      final ids = List<String>.from(result['ids'] as List);
      final current = catalog!.landmarks.map((i) => i.id).toSet();
      if (catalog?.version == version &&
          result['version'] == version &&
          ids.length == current.length &&
          ids.toSet().length == ids.length &&
          current.containsAll(ids)) {
        _rankedIds = List.unmodifiable(ids);
      }
    } on Object {
      // Older servers/offline sessions retain the last valid order.
    }
  }

  Future<LifeUnitPresentation> presentation(String id, int cursor) {
    _validateId(id);
    final key = '$id:$cursor';
    final cached = _presentations.remove(key);
    if (cached != null) {
      _presentations[key] = cached;
      return Future.value(cached);
    }
    final pending = _presentationRequests[key];
    if (pending != null) return pending;
    late final Future<LifeUnitPresentation> request;
    request = _publicReads
        .run(() async {
          if (_disposed) throw StateError('disposed');
          final response = await _client
              .send(
                http.Request(
                  'GET',
                  Uri.parse(
                    '$baseUrl/v2/public/landmarks/$id/spotlight?cursor=$cursor',
                  ),
                )..followRedirects = false,
              )
              .timeout(const Duration(seconds: 12));
          return LifeUnitPresentation.fromJson(
            jsonDecode(utf8.decode(await _read(response, 128 * 1024)))
                as Map<String, dynamic>,
          );
        })
        .then((result) {
          // A refresh or policy revocation may have invalidated this request.
          if (!_disposed && identical(_presentationRequests[key], request)) {
            if (_presentations.length >= 80) {
              _presentations.remove(_presentations.keys.first);
            }
            _presentations[key] = result;
          }
          return result;
        })
        .whenComplete(() {
          if (identical(_presentationRequests[key], request)) {
            _presentationRequests.remove(key);
          }
        });
    _presentationRequests[key] = request;
    return request;
  }

  void _validateId(String id) {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id)) {
      throw const FormatException('id');
    }
  }

  void _invalidatePresentation(String id) {
    _presentations.removeWhere((key, _) => key.startsWith('$id:'));
    _presentationRequests.removeWhere((key, _) => key.startsWith('$id:'));
  }

  Future<CommunityPolicy> presentationPolicy(String id) {
    _validateId(id);
    return _policyRequests.putIfAbsent(
      id,
      () => _publicReads
          .run(() async {
            try {
              if (_disposed) throw StateError('disposed');
              final response = await _client
                  .send(
                    http.Request(
                      'GET',
                      Uri.parse(
                        '$baseUrl/v2/public/community/policy?topic=landmark:$id',
                      ),
                    )..followRedirects = false,
                  )
                  .timeout(const Duration(seconds: 12));
              final policy = CommunityPolicy.fromJson(
                jsonDecode(utf8.decode(await _read(response, 16 * 1024)))
                    as Map<String, dynamic>,
              );
              if (!policy.readComments || !policy.readRatings) {
                _invalidatePresentation(id);
              }
              return policy;
            } catch (_) {
              _invalidatePresentation(id);
              rethrow;
            }
          })
          .whenComplete(() {
            _policyRequests.remove(id);
          }),
    );
  }

  Future<Uint8List> _read(http.StreamedResponse response, int limit) async {
    if (response.statusCode != 200 || response.isRedirect) {
      await response.stream
          .take(1)
          .drain<void>()
          .timeout(const Duration(seconds: 12));
      throw const FormatException('HTTP');
    }
    return (() async {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > limit) {
          throw const FormatException('size');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    })().timeout(const Duration(seconds: 15));
  }

  Future<File> _write(String name, List<int> bytes) async {
    final root = await _root();
    await root.create(recursive: true);
    final target = File('${root.path}/$name');
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    return temp.rename(target.path);
  }

  Future<File?> photo(LandmarkPhoto photo, {bool full = false}) {
    final key = '${photo.id}-${full ? 'full' : 'thumb'}';
    return _photos.putIfAbsent(key, () {
      final result = _loadPhoto(photo.id, full);
      // Only coalesce in-flight work. Flutter owns the bounded decoded image cache.
      unawaited(result.whenComplete(() => _photos.remove(key)));
      return result;
    });
  }

  Future<File?> _loadPhoto(String id, bool full) async {
    var stage = 'cache_lookup';
    int? status, byteCount;
    void mark(String value) => stage = value;
    try {
      final name = '$id-${full ? 'full' : 'thumb'}.jpg';
      final cached = File('${(await _root()).path}/$name');
      if (await cached.exists() && await cached.length() <= 3 * 1024 * 1024) {
        final bytes = await cached.readAsBytes();
        try {
          await _validatePhoto(bytes, id, full, onStage: mark);
          stage = 'cache_touch';
          await cached.setLastModified(DateTime.now());
          return cached;
        } on Object {
          await cached.delete();
        }
      }
      return await _photoDownloads.run(() async {
        if (_disposed) return null;
        stage = 'request';
        final response = await _client
            .send(
              http.Request(
                'GET',
                Uri.parse(
                  '$baseUrl/v1/public/landmarks/photos/$id/${full ? 'full' : 'thumb'}',
                ),
              )..followRedirects = false,
            )
            .timeout(const Duration(seconds: 12));
        status = response.statusCode;
        stage = 'response_body';
        final bytes = await _read(response, 3 * 1024 * 1024);
        byteCount = bytes.length;
        await _validatePhoto(bytes, id, full, onStage: mark);
        // Only publication/eviction is serialized. Disk hits never wait for HTTP.
        final write = _cacheWrites.then((_) async {
          stage = 'cache_write';
          final file = await _write(name, bytes);
          stage = 'cache_trim';
          await _trimCache(except: file.path);
          await _recordPhotoEvent(id, full, 'complete', status, byteCount);
          return file;
        });
        _cacheWrites = write.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        );
        return write;
      });
    } on Object catch (error) {
      await _recordPhotoEvent(id, full, stage, status, byteCount, error);
      return null;
    }
  }

  // Opt-in, device-local and bounded. Never record exception text, paths,
  // request headers, account information, or response bodies.
  Future<void> _recordPhotoEvent(
    String id,
    bool full,
    String stage,
    int? status,
    int? byteCount, [
    Object? error,
  ]) async {
    if (!_photoDiagnostics) return;
    final event = <String, Object?>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'photo_id': id,
      'size': full ? 'full' : 'thumb',
      'stage': stage,
      'http_status': status,
      'bytes': byteCount,
      'error': error == null
          ? null
          : error is FileSystemException
          ? 'filesystem'
          : error is SocketException
          ? 'socket'
          : error is TimeoutException
          ? 'timeout'
          : error is FormatException
          ? 'format'
          : error is StateError
          ? 'state'
          : 'other',
      if (error is FileSystemException) 'os_code': error.osError?.errorCode,
    };
    _photoEvents.add(event);
    if (_photoEvents.length > 40) _photoEvents.removeAt(0);
    final body = utf8.encode(
      jsonEncode({'version': 1, 'events': _photoEvents}),
    );
    final pending = _diagnosticWrites.then((_) async {
      await _write('photo-diagnostics.json', body);
    });
    _diagnosticWrites = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    await _diagnosticWrites;
  }

  Future<void> _validatePhoto(
    Uint8List bytes,
    String id,
    bool full, {
    void Function(String)? onStage,
  }) async {
    onStage?.call('hash');
    if (full && sha256.convert(bytes).toString() != id) {
      throw const FormatException('hash');
    }
    onStage?.call('image_buffer');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      onStage?.call('image_descriptor');
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        onStage?.call('image_dimensions');
        if (descriptor.width > 1920 || descriptor.height > 1920) {
          throw const FormatException('dimensions');
        }
        onStage?.call('image_codec');
        final codec = await descriptor.instantiateCodec(
          targetWidth: 1,
          targetHeight: 1,
        );
        try {
          onStage?.call('image_frame');
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

  Future<void> _trimCache({required String except}) async {
    final files = <({File file, FileStat stat})>[];
    await for (final entity in (await _root()).list()) {
      if (entity is File && entity.path.endsWith('.jpg')) {
        files.add((file: entity, stat: await entity.stat()));
      }
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var bytes = files.fold<int>(0, (sum, f) => sum + f.stat.size);
    for (final f in files) {
      if (bytes <= 128 * 1024 * 1024) break;
      if (f.file.path == except) continue;
      await f.file.delete();
      bytes -= f.stat.size;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}

/// Bounded FIFO work without retaining failures in the queue.
class _LandmarkWorkPool {
  _LandmarkWorkPool(this.limit);
  final int limit;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() work) async {
    if (_active >= limit) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await work();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}
