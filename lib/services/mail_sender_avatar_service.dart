import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';

import '../config/ispace_tls_trust.dart';
import 'campus_directory_service.dart';
import 'campus_contact_index.dart';
import 'network_retry.dart';

abstract interface class MailSenderAvatarService {
  Future<Uint8List?> loadThumbnail(String sender);

  void dispose();
}

class IoMailSenderAvatarService implements MailSenderAvatarService {
  static final IoMailSenderAvatarService sharedPortraitCache =
      IoMailSenderAvatarService();
  IoMailSenderAvatarService({
    CampusDirectoryService? directoryService,
    http.Client? imageClient,
    Future<Directory> Function()? cacheDirectoryLoader,
    DateTime Function()? now,
    Future<void> Function(Duration delay)? retryDelay,
    Future<Uint8List?> Function(Uint8List source)? thumbnailCompressor,
  }) : _directoryService = directoryService ?? RemoteCampusDirectoryService(),
       _ownsDirectoryService = directoryService == null,
       _imageClient =
           imageClient ??
           createAppHttpClient(
             securityContext: createBnbuSchoolSecurityContext(const <String>[
               'https://staff.bnbu.edu.cn',
               'https://gs.bnbu.edu.cn',
             ]),
           ),
       _ownsImageClient = imageClient == null,
       _cacheDirectoryLoader = cacheDirectoryLoader ?? _defaultCacheDirectory,
       _now = now ?? DateTime.now,
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _thumbnailCompressor =
           thumbnailCompressor ?? _compressThumbnailInBackground;

  static const int thumbnailDimension = 96;
  static const int maximumSourceBytes = 2 * 1024 * 1024;
  static const int maximumThumbnailBytes = 96 * 1024;
  static const Duration cacheLifetime = Duration(days: 30);
  static const Duration missingCacheLifetime = Duration(hours: 2);
  static const int maximumConcurrentLoads = 4;
  static const int maximumMemoryEntries = 48;

  final CampusDirectoryService _directoryService;
  final bool _ownsDirectoryService;
  final http.Client _imageClient;
  final bool _ownsImageClient;
  final Future<Directory> Function() _cacheDirectoryLoader;
  final DateTime Function() _now;
  final Future<void> Function(Duration delay) _retryDelay;
  final Future<Uint8List?> Function(Uint8List source) _thumbnailCompressor;
  final Map<String, Future<Uint8List?>> _pending = {};
  final revision = ValueNotifier<int>(0);
  final LinkedHashMap<String, Uint8List> _memoryThumbnails = LinkedHashMap();
  final Queue<Completer<void>> _loadWaiters = Queue<Completer<void>>();
  int _activeLoads = 0;

  Future<File> _portraitFile(String url, int dimension) async {
    final directory = await _cacheDirectoryLoader();
    await directory.create(recursive: true);
    final hash = sha256.convert(utf8.encode('$dimension\u0000$url'));
    return File('${directory.path}/photo_$hash.bin');
  }

  /// Disk checkpoints keep short app sessions moving past cached portraits.
  Future<bool> hasCachedTeacherPortrait(String photoUrl) async {
    if (!_isAllowedPhotoUrl(photoUrl)) return false;
    try {
      final file = await _portraitFile(photoUrl, 96);
      final stat = await file.stat();
      return stat.type == FileSystemEntityType.file &&
          stat.size > 0 &&
          stat.size <= maximumThumbnailBytes &&
          _now().difference(stat.modified) <= cacheLifetime &&
          _validCachedPortrait(await file.readAsBytes());
    } on FileSystemException {
      return false;
    }
  }

  /// Directory profiles already identify the photo; no email lookup is needed.
  Future<Uint8List?> loadTeacherPortrait(
    String photoUrl, {
    int dimension = 96,
    bool refresh = false,
  }) {
    if (!_isAllowedPhotoUrl(photoUrl)) return Future.value();
    final size = dimension <= 96 ? 96 : 320;
    final key = 'photo:$size:$photoUrl';
    final memory = _memoryThumbnails.remove(key);
    if (memory != null && !refresh) {
      _memoryThumbnails[key] = memory;
      return Future.value(memory);
    }
    final pendingKey = refresh ? '$key:refresh' : key;
    return _pending[pendingKey] ??=
        (() async {
          final file = await _portraitFile(photoUrl, size);
          final cached = await _readFreshFile(file, cacheLifetime);
          if (cached != null && !refresh) {
            _rememberThumbnail(key, cached);
            return cached;
          }
          if (!refresh) {
            final stale = await _rememberStale(key, file);
            if (stale != null) {
              unawaited(
                loadTeacherPortrait(
                  photoUrl,
                  dimension: size,
                  refresh: true,
                ).catchError((Object _) => null),
              );
              return stale;
            }
          }
          return _withLoadSlot(() async {
            try {
              final source = await _downloadPhoto(photoUrl);
              final portrait = size == 96
                  ? await _thumbnailCompressor(source)
                  : await _compressPortraitInBackground(source, 320);
              if (portrait == null || portrait.length > maximumThumbnailBytes) {
                return _rememberStale(key, file);
              }
              await _publishBytes(file, portrait);
              _rememberThumbnail(key, portrait);
              revision.value++;
              return portrait;
            } catch (_) {
              return _rememberStale(key, file);
            }
          });
        })().whenComplete(() {
          _pending.remove(pendingKey);
        });
  }

  @override
  Future<Uint8List?> loadThumbnail(String sender) {
    final email = _officialEmailFromSender(sender);
    if (email == null) {
      return Future<Uint8List?>.value();
    }
    final memoryThumbnail = _memoryThumbnails.remove(email);
    if (memoryThumbnail != null) {
      _memoryThumbnails[email] = memoryThumbnail;
      return Future<Uint8List?>.value(memoryThumbnail);
    }
    return _pending[email] ??= _loadThumbnail(email).whenComplete(() {
      _pending.remove(email);
    });
  }

  Future<Uint8List?> _loadThumbnail(String email) async {
    final cacheDirectory = await _cacheDirectoryLoader();
    await cacheDirectory.create(recursive: true);
    final cacheKey = sha256.convert(email.codeUnits).toString();
    final thumbnailFile = File('${cacheDirectory.path}/$cacheKey.png');
    final missingFile = File('${cacheDirectory.path}/$cacheKey.missing');

    final freshThumbnail = await _readFreshFile(thumbnailFile, cacheLifetime);
    if (freshThumbnail != null && freshThumbnail.isNotEmpty) {
      _rememberThumbnail(email, freshThumbnail);
      return freshThumbnail;
    }
    if (await _isFresh(missingFile, missingCacheLifetime)) {
      return null;
    }

    return (() async {
      try {
        final lookup = await _withLoadSlot(() => _findTeacherPhotoUrl(email));
        if (lookup.photoUrl == null) {
          if (lookup.definitiveMissing) {
            await _publishBytes(missingFile, Uint8List(0));
          }
          return _rememberStale(email, thumbnailFile);
        }
        final photoFile = await _portraitFile(lookup.photoUrl!, 96);
        final thumbnail = await loadTeacherPortrait(lookup.photoUrl!);
        if (thumbnail == null ||
            thumbnail.isEmpty ||
            thumbnail.length > maximumThumbnailBytes) {
          return _rememberStale(email, thumbnailFile);
        }
        await _publishBytes(thumbnailFile, thumbnail);
        await _publishBytes(photoFile, thumbnail);
        if (await missingFile.exists()) {
          await missingFile.delete();
        }
        _rememberThumbnail(email, thumbnail);
        return thumbnail;
      } catch (_) {
        return _rememberStale(email, thumbnailFile);
      }
    })();
  }

  Future<_TeacherPhotoLookup> _findTeacherPhotoUrl(String email) async {
    if (_ownsDirectoryService) {
      final index = CampusContactIndex.shared;
      await index.loadLocal();
      for (final teacher in index.teachers) {
        if (teacher.email.trim().toLowerCase() == email &&
            _isAllowedPhotoUrl(teacher.photoUrl)) {
          return _TeacherPhotoLookup.found(teacher.photoUrl);
        }
      }
    }
    try {
      final organizations = await _directoryService.loadOrganizations();
      for (final organization in organizations) {
        for (final teacher in organization.embeddedStaff) {
          if (teacher.email.trim().toLowerCase() == email &&
              _isAllowedPhotoUrl(teacher.photoUrl)) {
            return _TeacherPhotoLookup.found(teacher.photoUrl);
          }
        }
      }
    } catch (_) {
      // The central teacher index may still contain this sender.
    }

    try {
      final page = await _directoryService.loadTeachers(
        query: email,
        limit: 10,
      );
      for (final teacher in page.items) {
        if (teacher.email.trim().toLowerCase() == email &&
            _isAllowedPhotoUrl(teacher.photoUrl)) {
          return _TeacherPhotoLookup.found(teacher.photoUrl);
        }
      }
      return const _TeacherPhotoLookup.missing();
    } catch (_) {
      return const _TeacherPhotoLookup.unavailable();
    }
  }

  Future<Uint8List> _downloadPhoto(String url) async {
    final uri = Uri.parse(url);
    if (!_isAllowedPhotoUri(uri)) {
      throw const FormatException('Unsupported teacher portrait URL');
    }
    final response = await _sendPhotoRequest(uri);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Teacher portrait returned HTTP ${response.statusCode}',
      );
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.startsWith('image/')) {
      throw const FormatException('Teacher portrait is not an image');
    }
    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > maximumSourceBytes) {
      throw const FormatException('Teacher portrait is too large');
    }
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream) {
      received += chunk.length;
      if (received > maximumSourceBytes) {
        throw const FormatException('Teacher portrait is too large');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<http.StreamedResponse> _sendPhotoRequest(Uri initialUri) async {
    var uri = initialUri;
    for (var redirect = 0; redirect <= 3; redirect++) {
      final response = await retryNetworkOperation<http.StreamedResponse>(
        () => _imageClient
            .send(
              http.Request('GET', uri)
                ..followRedirects = false
                ..headers['Accept'] = 'image/*',
            )
            .timeout(const Duration(seconds: 12)),
        shouldRetryResult: (result) => isTransientHttpStatus(result.statusCode),
        delay: _retryDelay,
      );
      if (!response.isRedirect) {
        return response;
      }
      final location = response.headers['location'];
      await response.stream.drain<void>();
      if (location == null || redirect == 3) {
        throw const HttpException('Invalid teacher portrait redirect');
      }
      uri = uri.resolve(location);
      if (!_isAllowedPhotoUri(uri)) {
        throw const FormatException('Unsupported teacher portrait redirect');
      }
    }
    throw const HttpException('Too many teacher portrait redirects');
  }

  Future<T> _withLoadSlot<T>(Future<T> Function() operation) async {
    await _acquireLoadSlot();
    try {
      return await operation();
    } finally {
      _releaseLoadSlot();
    }
  }

  Future<void> _acquireLoadSlot() async {
    if (_activeLoads < maximumConcurrentLoads) {
      _activeLoads++;
      return;
    }
    final waiter = Completer<void>();
    _loadWaiters.add(waiter);
    await waiter.future;
  }

  void _releaseLoadSlot() {
    if (_loadWaiters.isNotEmpty) {
      // Transfer the occupied slot directly to the oldest waiter.
      _loadWaiters.removeFirst().complete();
    } else {
      _activeLoads--;
    }
  }

  Future<Uint8List?> _rememberStale(String email, File file) async {
    final stale = await _readStaleThumbnail(file);
    if (stale != null) {
      _rememberThumbnail(email, stale);
    }
    return stale;
  }

  void _rememberThumbnail(String email, Uint8List thumbnail) {
    _memoryThumbnails.remove(email);
    _memoryThumbnails[email] = thumbnail;
    while (_memoryThumbnails.length > maximumMemoryEntries) {
      _memoryThumbnails.remove(_memoryThumbnails.keys.first);
    }
  }

  Future<Uint8List?> _readFreshFile(File file, Duration lifetime) async {
    if (!await _isFresh(file, lifetime)) {
      return null;
    }
    try {
      final bytes = await file.readAsBytes();
      return _validCachedPortrait(bytes) ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readStaleThumbnail(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return _validCachedPortrait(bytes) ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  bool _validCachedPortrait(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumThumbnailBytes) return false;
    try {
      final decoder = image.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      return info != null &&
          info.width > 0 &&
          info.height > 0 &&
          info.width <= 320 &&
          info.height <= 320 &&
          decoder!.decodeFrame(0) != null;
    } on Object {
      return false;
    }
  }

  Future<bool> _isFresh(File file, Duration lifetime) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return false;
      }
      return _now().difference(stat.modified) <= lifetime;
    } catch (_) {
      return false;
    }
  }

  Future<void> _publishBytes(File destination, Uint8List bytes) async {
    final temporary = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(destination.path);
      } on FileSystemException {
        if (await destination.exists()) {
          await destination.delete();
        }
        await temporary.rename(destination.path);
      }
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  void dispose() {
    if (_ownsDirectoryService) {
      _directoryService.dispose();
    }
    if (_ownsImageClient) {
      _imageClient.close();
    }
  }

  static Future<Directory> _defaultCacheDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/mail_teacher_avatars_v1');
  }
}

Uint8List? compressMailAvatarThumbnail(Uint8List source, {int dimension = 96}) {
  final decoder = image.findDecoderForData(source);
  final information = decoder?.startDecode(source);
  if (decoder == null ||
      information == null ||
      information.width <= 0 ||
      information.height <= 0 ||
      information.width * information.height > 16 * 1024 * 1024) {
    return null;
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    return null;
  }
  final oriented = image.bakeOrientation(decoded);
  final cropSize = oriented.width < oriented.height
      ? oriented.width
      : oriented.height;
  final cropped = image.copyCrop(
    oriented,
    x: (oriented.width - cropSize) ~/ 2,
    y: (oriented.height - cropSize) ~/ 2,
    width: cropSize,
    height: cropSize,
  );
  final thumbnail = image.copyResize(
    cropped,
    width: dimension <= 96 ? 96 : 320,
    height: dimension <= 96 ? 96 : 320,
    interpolation: image.Interpolation.linear,
  );
  return dimension <= 96
      ? image.encodePng(thumbnail, level: 6)
      : image.encodeJpg(thumbnail, quality: 85);
}

Future<Uint8List?> _compressThumbnailInBackground(Uint8List source) {
  return Isolate.run(() => compressMailAvatarThumbnail(source));
}

Future<Uint8List?> _compressPortraitInBackground(
  Uint8List source,
  int dimension,
) => Isolate.run(
  () => compressMailAvatarThumbnail(source, dimension: dimension),
);

String? _officialEmailFromSender(String sender) {
  final match = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+').firstMatch(sender);
  if (match == null) {
    return null;
  }
  final email = match.group(0)!.toLowerCase();
  final domain = email.substring(email.lastIndexOf('@') + 1);
  if (domain == 'mail.bnbu.edu.cn') {
    return null;
  }
  if (domain != 'bnbu.edu.cn' && !domain.endsWith('.bnbu.edu.cn')) {
    return null;
  }
  return email;
}

bool _isAllowedPhotoUrl(String value) {
  return value.isNotEmpty && _isAllowedPhotoUri(Uri.tryParse(value));
}

bool _isAllowedPhotoUri(Uri? uri) {
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  if (uri.host == 'staff.bnbu.edu.cn') {
    return !uri.hasQuery;
  }
  const publicRosterHosts = {
    'gs.bnbu.edu.cn',
    'ias.bnbu.edu.cn',
    'ar.bnbu.edu.cn',
    'hro.bnbu.edu.cn',
    'ido.bnbu.edu.cn',
    'ctl.bnbu.edu.cn',
    'fbm.bnbu.edu.cn',
    'fhss.bnbu.edu.cn',
    'fst.bnbu.edu.cn',
    'scc.bnbu.edu.cn',
    'sai.bnbu.edu.cn',
    'sge.bnbu.edu.cn',
    'www.bnbu.edu.cn',
  };
  if (!publicRosterHosts.contains(uri.host) ||
      !const {
        '/virtual_attach_file.vsb',
        '/graduate/virtual_attach_file.vsb',
        '/en/virtual_attach_file.vsb',
        '/boc/virtual_attach_file.vsb',
        '/lc/virtual_attach_file.vsb',
      }.contains(uri.path)) {
    return false;
  }
  final query = uri.queryParameters;
  return query.keys.every(const {'afc', 'oid', 'e'}.contains) &&
      (query['afc']?.isNotEmpty ?? false) &&
      RegExp(r'^\d+$').hasMatch(query['oid'] ?? '') &&
      const {'.jpg', '.jpeg', '.png'}.contains(query['e']?.toLowerCase());
}

class _TeacherPhotoLookup {
  const _TeacherPhotoLookup.found(this.photoUrl) : definitiveMissing = false;

  const _TeacherPhotoLookup.missing()
    : photoUrl = null,
      definitiveMissing = true;

  const _TeacherPhotoLookup.unavailable()
    : photoUrl = null,
      definitiveMissing = false;

  final String? photoUrl;
  final bool definitiveMissing;
}
