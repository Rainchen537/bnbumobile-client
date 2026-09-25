import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'network_retry.dart';

/// Shared public directory snapshots. Credentials and private endpoints never
/// enter this client; page instances share disk, in-flight requests and updates.
class PublicDirectoryCache extends http.BaseClient {
  PublicDirectoryCache({
    http.Client? client,
    Future<Directory> Function()? directory,
  }) : _client = client ?? createAppHttpClient(),
       _directory = directory ?? getApplicationSupportDirectory;
  static final shared = PublicDirectoryCache();
  final revision = ValueNotifier<int>(0);
  final http.Client _client;
  final Future<Directory> Function() _directory;
  final Map<String, Future<http.Response>> _pending = {};
  final Map<String, http.Response> _memory = {};
  final Map<String, DateTime> _checked = {};
  static const maxBytes = 4 * 1024 * 1024;
  Future<File> _file(Uri uri) async => File(
    '${(await _directory()).path}/public-directory-v1/${sha256.convert(utf8.encode(uri.toString()))}.json',
  );
  bool _allowed(http.BaseRequest r) =>
      r.method == 'GET' &&
      r.url.scheme == 'https' &&
      r.url.userInfo.isEmpty &&
      !r.headers.keys.any(
        (k) => ['authorization', 'cookie'].contains(k.toLowerCase()),
      ) &&
      const {
        '/v1/directory/public/organizations',
        '/v1/directory/public/teachers',
        '/v1/directory/public/contacts',
      }.contains(r.url.path);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_allowed(request)) return _client.send(request);
    final key = request.url.toString();
    var cached = _memory[key];
    if (cached == null) {
      try {
        final file = await _file(request.url);
        if (await file.length() <= maxBytes) {
          final raw = await file.readAsBytes();
          jsonDecode(utf8.decode(raw));
          cached = http.Response.bytes(
            raw,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
          _memory[key] = cached;
        }
      } on Object {
        /* Cache misses preserve the live request path. */
      }
    }
    final fresh = _checked[key];
    if (cached != null) {
      if (fresh == null ||
          DateTime.now().difference(fresh) > const Duration(minutes: 5)) {
        unawaited(_refresh(request.url).catchError((Object _) => cached!));
      }
      return http.StreamedResponse(
        Stream.value(cached.bodyBytes),
        200,
        headers: cached.headers,
      );
    }
    final response = await _refresh(request.url);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }

  Future<http.Response> refreshPublic(Uri uri) {
    if (!_allowed(http.Request('GET', uri))) {
      throw ArgumentError('Not a public directory URL');
    }
    return _refresh(uri);
  }

  Future<http.Response> _refresh(Uri uri) =>
      _pending[uri.toString()] ??= _download(uri).whenComplete(() {
        _pending.remove(uri.toString());
      });
  Future<http.Response> _download(Uri uri) async {
    final key = uri.toString();
    _checked[key] = DateTime.now();
    final response = await (() async {
      final stream = await _client.send(
        http.Request('GET', uri)..followRedirects = false,
      );
      final data = <int>[];
      await for (final part in stream.stream) {
        if (data.length + part.length > maxBytes) {
          throw const FormatException('Directory too large');
        }
        data.addAll(part);
      }
      return http.Response.bytes(
        data,
        stream.statusCode,
        headers: stream.headers,
      );
    })().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return response;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map ||
        !(decoded['items'] is List || decoded['organizations'] is List)) {
      throw const FormatException('Invalid directory');
    }
    final changed = _memory[key]?.body != response.body;
    _memory[key] = response;
    if (_memory.length > 64) {
      final oldest = _memory.keys.first;
      _memory.remove(oldest);
      _checked.remove(oldest);
    }
    try {
      final file = await _file(uri);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(file.path);
      final files = await file.parent
          .list()
          .where((f) => f.path.endsWith('.json'))
          .cast<File>()
          .toList();
      if (files.length > 64) {
        final dated = <(File, DateTime)>[];
        for (final f in files) {
          dated.add((f, await f.lastModified()));
        }
        dated.sort((a, b) => a.$2.compareTo(b.$2));
        for (final f in dated.take(dated.length - 64)) {
          await f.$1.delete();
        }
      }
    } on Object {
      /* A disk error must not discard a valid public response. */
    }
    if (changed) revision.value++;
    return response;
  }

  @override
  void close() {
    /* Shared application lifetime. */
  }
}
