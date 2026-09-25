import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../config/ispace_tls_trust.dart';
import 'native_actions.dart';
import 'network_retry.dart';

class CourseArchiveEntry {
  const CourseArchiveEntry({
    required this.url,
    required this.sectionName,
    required this.moduleName,
    required this.fileName,
    required this.expectedBytes,
    this.displayName = '',
  });

  final String displayName;
  final String url;
  final String sectionName;
  final String moduleName;
  final String fileName;
  final int expectedBytes;
}

class CourseArchiveProgress {
  const CourseArchiveProgress({
    required this.completedFiles,
    required this.totalFiles,
    required this.currentFileName,
  });

  final int completedFiles;
  final int totalFiles;
  final String currentFileName;
}

class CourseArchiveResult {
  const CourseArchiveResult({
    required this.path,
    required this.fileName,
    required this.fileCount,
    required this.totalBytes,
    this.failures = const [],
    this.completedFileNames = const [],
  });

  final String path;
  final String fileName;
  final int fileCount;
  final int totalBytes;
  final List<CourseArchiveFailure> failures;
  final List<String> completedFileNames;
}

class CourseArchiveFailure {
  const CourseArchiveFailure({required this.entry, required this.message});
  final CourseArchiveEntry entry;
  final String message;
}

abstract interface class CourseArchiveBuilder {
  Future<CourseArchiveResult> build({
    required String cacheDirectory,
    required String archiveName,
    required String baseUrl,
    required String cookieHeader,
    required List<CourseArchiveEntry> entries,
    required bool Function() sessionIsActive,
    void Function(CourseArchiveProgress progress)? onProgress,
  });
}

abstract interface class CourseArchiveFileFetcher {
  Future<int> fetch({
    required Uri url,
    required Uri origin,
    required String cookieHeader,
    required File destination,
    required int remainingBytes,
    required bool Function() sessionIsActive,
  });
}

class CourseArchiveService implements CourseArchiveBuilder {
  CourseArchiveService({
    CourseArchiveFileFetcher? fileFetcher,
    this.maxTotalBytes = 512 * 1024 * 1024,
    this.continueOnFileError = false,
  }) : _fileFetcher = fileFetcher ?? SecureCourseArchiveFileFetcher();

  final CourseArchiveFileFetcher _fileFetcher;
  final int maxTotalBytes;
  // Opt-in for the manual picker; the existing AI handoff stays fail-closed.
  final bool continueOnFileError;
  final _cachedFiles = <String, (File, int)>{};
  Directory? _cache;
  bool Function()? _cacheLease;
  bool _building = false;
  bool _disposed = false;

  String _cacheKey(CourseArchiveEntry entry) =>
      '${entry.url}\n${entry.expectedBytes}';

  Future<void> _clearCache() async {
    final directory = _cache;
    _cache = null;
    _cachedFiles.clear();
    _cacheLease = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> discardCachedFiles() async {
    if (_building) throw StateError('Cannot reset an active archive build.');
    await _clearCache();
  }

  void dispose() {
    _disposed = true;
    if (_fileFetcher is SecureCourseArchiveFileFetcher) {
      _fileFetcher.dispose();
    }
    if (!_building) {
      unawaited(
        _clearCache().catchError((Object _) {
          // Only owned temporary files are involved; never surface filesystem paths.
        }),
      );
    }
  }

  @override
  Future<CourseArchiveResult> build({
    required String cacheDirectory,
    required String archiveName,
    required String baseUrl,
    required String cookieHeader,
    required List<CourseArchiveEntry> entries,
    required bool Function() sessionIsActive,
    void Function(CourseArchiveProgress progress)? onProgress,
  }) async {
    if (_disposed || _building) {
      throw const CourseArchiveException('下载已取消。');
    }
    final origin = Uri.tryParse(baseUrl.trim());
    if (origin == null ||
        origin.scheme.toLowerCase() != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty) {
      throw const CourseArchiveException('iSpace 下载地址无效。');
    }
    if (cookieHeader.trim().isEmpty) {
      throw const CourseArchiveException('iSpace 下载会话无效。');
    }
    if (entries.isEmpty) {
      throw const CourseArchiveException('没有可打包的课程文件。');
    }
    for (final entry in entries) {
      final uri = Uri.tryParse(entry.url.trim());
      if (uri == null || !_sameOrigin(uri, origin)) {
        throw const CourseArchiveException('课程文件的下载地址不安全。');
      }
    }
    _building = true;
    bool active() => !_disposed && sessionIsActive();

    final root = Directory(
      '${Directory(cacheDirectory).path}/course_archives/'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    final safeArchiveName = _safePathSegment(archiveName, fallback: '课程课件');
    final zipFileName = '$safeArchiveName.zip';
    final partialZip = File('${root.path}/$zipFileName.partial');
    final finalZip = File('${root.path}/$zipFileName');
    final encoder = ZipFileEncoder();
    var encoderOpened = false;
    var totalBytes = 0;
    var completed = 0;
    final usedArchivePaths = <String>{};
    final failures = <CourseArchiveFailure>[];
    final completedFileNames = <String>[];
    var keepCache = false;

    try {
      if (!active()) throw const CourseArchiveException('下载已取消。');
      if (_cacheLease != null && !_cacheLease!()) await _clearCache();
      final allowedKeys = entries.map(_cacheKey).toSet();
      for (final key in _cachedFiles.keys.toList()) {
        if (!allowedKeys.contains(key)) {
          final removed = _cachedFiles.remove(key)!.$1;
          if (await removed.exists()) await removed.delete();
        }
      }
      await root.create(recursive: true);
      _cache ??= await Directory('${root.path}/files').create(recursive: true);
      _cacheLease ??= sessionIsActive;
      encoder.create(partialZip.path);
      encoderOpened = true;
      for (var index = 0; index < entries.length; index++) {
        if (!active()) {
          throw const CourseArchiveException('登录状态已变化，已停止打包。');
        }
        final entry = entries[index];
        final uri = Uri.parse(entry.url.trim());
        onProgress?.call(
          CourseArchiveProgress(
            completedFiles: index,
            totalFiles: entries.length,
            currentFileName: entry.fileName,
          ),
        );
        final key = _cacheKey(entry);
        var cached = _cachedFiles[key];
        if (cached != null && !await cached.$1.exists()) cached = null;
        final localFile =
            cached?.$1 ??
            File(
              '${_cache!.path}/${DateTime.now().microsecondsSinceEpoch}-$index.download',
            );
        int byteCount;
        try {
          byteCount =
              cached?.$2 ??
              await _fetchWithRetry(
                url: uri,
                origin: origin,
                cookieHeader: cookieHeader,
                destination: localFile,
                remainingBytes: maxTotalBytes - totalBytes,
                sessionIsActive: active,
              );
        } on CourseArchiveException catch (error) {
          if (!continueOnFileError || error.fatal || !active()) rethrow;
          if (await localFile.exists()) await localFile.delete();
          failures.add(
            CourseArchiveFailure(entry: entry, message: error.message),
          );
          onProgress?.call(
            CourseArchiveProgress(
              completedFiles: index + 1,
              totalFiles: entries.length,
              currentFileName: entry.fileName,
            ),
          );
          continue;
        }
        _cachedFiles[key] = (localFile, byteCount);
        totalBytes += byteCount;
        if (totalBytes > maxTotalBytes) {
          throw const CourseArchiveException('课程文件总大小超过 512 MB。');
        }
        final archivePath = _uniqueArchivePath(entry, usedArchivePaths);
        await encoder.addFile(localFile, archivePath);
        completed++;
        completedFileNames.add(entry.fileName);
        onProgress?.call(
          CourseArchiveProgress(
            completedFiles: index + 1,
            totalFiles: entries.length,
            currentFileName: entry.fileName,
          ),
        );
      }
      if (!active()) {
        throw const CourseArchiveException('登录状态已变化，已停止打包。');
      }
      if (completed == 0) {
        throw CourseArchiveException(
          '没有文件下载成功，请重试失败项。',
          failures: List.unmodifiable(failures),
        );
      }
      await encoder.close();
      encoderOpened = false;
      if (!active()) {
        throw const CourseArchiveException('登录状态已变化，已停止打包。');
      }
      final published = failures.isEmpty
          ? finalZip
          : File('${root.path}/$safeArchiveName-partial.zip');
      await partialZip.rename(published.path);
      if (!active()) {
        await published.delete();
        throw const CourseArchiveException('登录状态已变化，已停止打包。');
      }
      keepCache = continueOnFileError && failures.isNotEmpty;
      return CourseArchiveResult(
        path: published.path,
        fileName: published.uri.pathSegments.last,
        fileCount: completed,
        totalBytes: totalBytes,
        failures: List.unmodifiable(failures),
        completedFileNames: List.unmodifiable(completedFileNames),
      );
    } on CourseArchiveException {
      rethrow;
    } catch (_) {
      throw const CourseArchiveException('课程文件打包失败，请稍后重试。');
    } finally {
      if (encoderOpened) {
        try {
          await encoder.close();
        } catch (_) {
          // The partial archive is removed below.
        }
      }
      if (await partialZip.exists()) {
        await partialZip.delete();
      }
      if (!keepCache || !active()) await _clearCache();
      _building = false;
    }
  }

  Future<int> _fetchWithRetry({
    required Uri url,
    required Uri origin,
    required String cookieHeader,
    required File destination,
    required int remainingBytes,
    required bool Function() sessionIsActive,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _fileFetcher.fetch(
          url: url,
          origin: origin,
          cookieHeader: cookieHeader,
          destination: destination,
          remainingBytes: remainingBytes,
          sessionIsActive: sessionIsActive,
        );
      } catch (error) {
        final transient =
            error is SocketException ||
            error is TimeoutException ||
            error is HttpException ||
            (error is CourseArchiveException && error.retryable);
        if (transient &&
            continueOnFileError &&
            attempt == 0 &&
            sessionIsActive()) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        if (error is CourseArchiveException) rethrow;
        if (transient) throw const CourseArchiveException('文件下载暂时失败，请重试。');
        rethrow;
      }
    }
  }

  String _uniqueArchivePath(CourseArchiveEntry entry, Set<String> usedPaths) {
    final section = _safePathSegment(entry.sectionName, fallback: '未分类章节');
    final module = _safePathSegment(entry.moduleName, fallback: '课程资料');
    final rawFile = safeAttachmentFileName(entry.fileName);
    var candidate = '$section/$module/$rawFile';
    var suffix = 2;
    while (!usedPaths.add(candidate.toLowerCase())) {
      final dot = rawFile.lastIndexOf('.');
      final stem = dot > 0 ? rawFile.substring(0, dot) : rawFile;
      final extension = dot > 0 ? rawFile.substring(dot) : '';
      candidate = '$section/$module/$stem ($suffix)$extension';
      suffix++;
    }
    return candidate;
  }

  String _safePathSegment(String value, {required String fallback}) {
    final normalized = value
        .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (normalized.isEmpty || normalized == '.' || normalized == '..') {
      return fallback;
    }
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }
}

class SecureCourseArchiveFileFetcher implements CourseArchiveFileFetcher {
  SecureCourseArchiveFileFetcher({
    HttpClient? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client,
       _ownsClient = client == null;

  HttpClient? _client;
  bool _disposed = false;
  final bool _ownsClient;
  final Duration requestTimeout;

  @override
  Future<int> fetch({
    required Uri url,
    required Uri origin,
    required String cookieHeader,
    required File destination,
    required int remainingBytes,
    required bool Function() sessionIsActive,
  }) async {
    if (_disposed) {
      throw const CourseArchiveException('下载已取消。');
    }
    if (remainingBytes <= 0) {
      throw const CourseArchiveException('课程文件总大小超过 512 MB。', fatal: true);
    }
    var current = url;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      if (!sessionIsActive()) {
        throw const CourseArchiveException('登录状态已变化，已停止下载。');
      }
      if (!_sameOrigin(current, origin)) {
        throw const CourseArchiveException('下载跳转离开了 iSpace，已阻止。', fatal: true);
      }
      final client = _client ??= createAppDartHttpClient(
        securityContext: createIsSpaceSecurityContext(origin.toString()),
      );
      final request = await client.getUrl(current).timeout(requestTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(requestTimeout);
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.listen((_) {}).cancel();
        if (location == null || redirectCount == 5) {
          throw const CourseArchiveException('课程文件下载跳转无效。');
        }
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.listen((_) {}).cancel();
        throw CourseArchiveException(
          response.statusCode == 401 || response.statusCode == 403
              ? '文件访问被拒绝，请检查登录状态或课程权限。'
              : '文件暂时不可用，请稍后重试。',
          retryable: response.statusCode == 429 || response.statusCode >= 500,
        );
      }
      final declaredLength = response.contentLength;
      if (declaredLength > remainingBytes) {
        await response.listen((_) {}).cancel();
        throw const CourseArchiveException('课程文件总大小超过 512 MB。', fatal: true);
      }

      final mime = response.headers.contentType?.mimeType.toLowerCase();
      if (mime == 'text/html' || mime == 'application/xhtml+xml') {
        final probe = <int>[];
        await for (final chunk in response.timeout(requestTimeout)) {
          probe.addAll(chunk.take(8192 - probe.length));
          if (probe.length >= 8192) break;
        }
        throw CourseArchiveException(
          _looksLikeLoginHtml(probe)
              ? 'iSpace 登录状态已失效，请重新登录。'
              : '文件链接返回了网页，无法作为课件下载。',
        );
      }
      final sink = destination.openWrite();
      final htmlProbe = <int>[];
      var received = 0;
      try {
        await for (final chunk in response.timeout(requestTimeout)) {
          if (!sessionIsActive()) {
            throw const CourseArchiveException('登录状态已变化，已停止下载。');
          }
          received += chunk.length;
          if (received > remainingBytes) {
            throw const CourseArchiveException(
              '课程文件总大小超过 512 MB。',
              fatal: true,
            );
          }
          if (htmlProbe.length < 8192) {
            htmlProbe.addAll(chunk.take(8192 - htmlProbe.length));
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0) {
        throw const CourseArchiveException('课程文件内容为空。');
      }
      if (_looksLikeLoginHtml(htmlProbe)) {
        throw const CourseArchiveException('iSpace 登录状态已失效，请重新登录。');
      }
      return received;
    }
    throw const CourseArchiveException('课程文件下载跳转过多。');
  }

  bool _looksLikeLoginHtml(List<int> probe) {
    final text = utf8.decode(probe, allowMalformed: true).toLowerCase();
    return (text.contains('<form') &&
            (text.contains('type="password"') ||
                text.contains("type='password'"))) ||
        text.contains('/login/index.php') ||
        text.contains('统一身份认证');
  }

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  void dispose() {
    _disposed = true;
    if (_ownsClient) {
      _client?.close(force: true);
    }
  }
}

bool _sameOrigin(Uri first, Uri second) {
  int effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      effectivePort(first) == effectivePort(second) &&
      first.userInfo.isEmpty;
}

class CourseArchiveException implements Exception {
  const CourseArchiveException(
    this.message, {
    this.fatal = false,
    this.retryable = false,
    this.failures = const [],
  });

  final String message;
  final bool fatal;
  final bool retryable;
  final List<CourseArchiveFailure> failures;

  @override
  String toString() => message;
}
