import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../config/ispace_tls_trust.dart';
import 'desktop_download_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class NativeActions {
  const NativeActions({
    MethodChannel channel = const MethodChannel('ispace/native_actions'),
    http.Client Function()? previewClientFactory,
    Future<Directory> Function()? temporaryDirectoryProvider,
    DesktopDownloadService desktopDownloads = const DesktopDownloadService(),
  }) : _channel = channel,
       _previewClientFactory = previewClientFactory,
       _temporaryDirectoryProvider = temporaryDirectoryProvider,
       _desktopDownloads = desktopDownloads;

  final MethodChannel _channel;
  final http.Client Function()? _previewClientFactory;
  final Future<Directory> Function()? _temporaryDirectoryProvider;
  final DesktopDownloadService _desktopDownloads;

  /// iSpace desktop downloads are staged privately, then published only while
  /// the initiating account/page is still active. Mobile channels are unchanged.
  Future<String?> downloadDesktopFile({
    required String url,
    required String filename,
    required bool Function() isActive,
    String cookieHeader = '',
    String cookieOrigin = '',
  }) async {
    if (!DesktopDownloadService.supported) {
      throw UnsupportedError('Desktop only');
    }
    if (!isActive()) return null;
    final uri = Uri.tryParse(url);
    if (!_isHttpUri(uri) ||
        uri!.userInfo.isNotEmpty ||
        (cookieHeader.isNotEmpty && !urlsHaveSameOrigin(url, cookieOrigin))) {
      throw const FormatException('Invalid download source');
    }
    final temporary =
        await (_temporaryDirectoryProvider ?? getTemporaryDirectory)();
    final staging = await temporary.createTemp('bnbu-desktop-download-');
    try {
      final path = await _downloadFileForDesktop(
        uri,
        filename: safeAttachmentFileName(filename),
        cookieHeader: cookieHeader,
        cookieOrigin: cookieOrigin,
        destinationDirectory: staging,
        isActive: isActive,
      );
      return await _desktopDownloads.save(
        sourcePath: path,
        fileName: File(path).uri.pathSegments.last,
        isActive: isActive,
      );
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<String> getMailAttachmentCacheDirectory() async {
    if (!_usesNativeChannel) {
      final temporaryDirectory = await getTemporaryDirectory();
      final cacheDirectory = Directory(
        _joinPath(temporaryDirectory.path, 'bnbu-mail-attachments'),
      );
      await cacheDirectory.create(recursive: true);
      return cacheDirectory.path;
    }
    final path = await _channel.invokeMethod<String>(
      'getMailAttachmentCacheDir',
    );
    if (path == null || path.trim().isEmpty) {
      throw PlatformException(
        code: 'cache_directory_unavailable',
        message: '邮件附件缓存目录不可用。',
      );
    }
    return path;
  }

  Future<Object?> downloadFile({
    required String url,
    required String filename,
    required String title,
    String cookieHeader = '',
    String cookieOrigin = '',
  }) {
    final uri = Uri.tryParse(url.trim());
    if (!_isHttpUri(uri) || uri!.userInfo.isNotEmpty) {
      throw const FormatException('只能下载有效的 HTTP(S) 文件。');
    }
    final normalizedCookieHeader = cookieHeader.trim();
    final normalizedCookieOrigin = cookieOrigin.trim();
    if (normalizedCookieHeader.isNotEmpty &&
        (normalizedCookieOrigin.isEmpty ||
            !urlsHaveSameOrigin(uri.toString(), normalizedCookieOrigin))) {
      throw const FormatException('下载 Cookie 只能发送到其原始同源地址。');
    }
    final safeFilename = safeAttachmentFileName(filename);
    if (!_usesNativeChannel) {
      return _downloadFileForDesktop(
        uri,
        filename: safeFilename,
        cookieHeader: normalizedCookieHeader,
        cookieOrigin: normalizedCookieOrigin,
      );
    }
    return _channel.invokeMethod<Object?>('downloadFile', {
      'url': uri.toString(),
      'filename': safeFilename,
      'title': title.trim(),
      if (normalizedCookieHeader.isNotEmpty)
        'cookieHeader': normalizedCookieHeader,
      if (normalizedCookieOrigin.isNotEmpty)
        'cookieOrigin': normalizedCookieOrigin,
    });
  }

  Future<String> cachePreviewFile({
    required String url,
    required String filename,
    String cookieHeader = '',
    String cookieOrigin = '',
    bool Function()? isActive,
  }) async {
    final uri = Uri.tryParse(url);
    if (!_isHttpUri(uri) ||
        uri!.userInfo.isNotEmpty ||
        (cookieHeader.isNotEmpty && !urlsHaveSameOrigin(url, cookieOrigin))) {
      throw const FormatException('Invalid preview source');
    }
    final root = Directory(
      '${(await (_temporaryDirectoryProvider ?? getTemporaryDirectory)()).path}/bnbu-file-preview',
    );
    await root.create(recursive: true);
    await for (final entity in root.list()) {
      if (entity is Directory &&
          (await entity.stat()).modified.isBefore(
            DateTime.now().subtract(const Duration(days: 1)),
          )) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          /* A previous preview may still be in use. */
        }
      }
    }
    final destination = await root.createTemp('file-');
    try {
      return await _downloadFileForDesktop(
        uri,
        filename: safeAttachmentFileName(filename),
        cookieHeader: cookieHeader,
        cookieOrigin: cookieOrigin,
        destinationDirectory: destination,
        maximumDownloadBytes: 64 * 1024 * 1024,
        isActive: isActive,
      );
    } catch (_) {
      await destination.delete(recursive: true);
      rethrow;
    }
  }

  Future<bool> canPreviewFile(String path) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('canPreviewFile', {
            'path': path,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> shareLocalFile({
    required String path,
    required String filename,
    required String mimeType,
  }) => _channel.invokeMethod<void>('shareLocalFile', {
    'path': path,
    'filename': safeAttachmentFileName(filename),
    'mimeType': mimeType,
  });

  Future<void> openFile({required String path, required String mimeType}) {
    if (!_usesNativeChannel) {
      return _launchDesktopUri(
        Uri.file(path),
        errorCode: 'file_open_failed',
        errorMessage: '系统无法打开这个文件。',
      );
    }
    return _channel.invokeMethod<void>('openFile', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  Future<void> clearWebSession() {
    if (!_usesNativeChannel) {
      return Future<void>.value();
    }
    return _channel.invokeMethod<void>('clearWebSession');
  }

  Future<void> openExternalUrl(String url) {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (scheme != 'https' && scheme != 'http')) {
      throw const FormatException('只能打开有效的 HTTP(S) 外部链接。');
    }
    if (!_usesNativeChannel) {
      return _launchDesktopUri(
        uri,
        errorCode: 'external_url_failed',
        errorMessage: '系统无法打开这个链接。',
      );
    }
    return _channel.invokeMethod<void>('openExternalUrl', {
      'url': uri.toString(),
    });
  }

  bool get _usesNativeChannel {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _launchDesktopUri(
    Uri uri, {
    required String errorCode,
    required String errorMessage,
  }) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw PlatformException(code: errorCode, message: errorMessage);
    }
  }

  Future<String> _downloadFileForDesktop(
    Uri initialUri, {
    required String filename,
    required String cookieHeader,
    required String cookieOrigin,
    Directory? destinationDirectory,
    int maximumDownloadBytes = 1024 * 1024 * 1024,
    bool Function()? isActive,
  }) async {
    const maximumRedirects = 6;
    final client = _previewClientFactory?.call() ?? http.Client();
    final schoolContext = createBnbuSchoolSecurityContext([
      'https://bnbu.edu.cn',
    ]);
    final schoolClient = schoolContext == null
        ? null
        : IOClient(HttpClient(context: schoolContext));
    var currentUri = initialUri;
    final startedWithHttps = initialUri.scheme.toLowerCase() == 'https';
    http.StreamedResponse? response;

    try {
      for (
        var redirectCount = 0;
        redirectCount <= maximumRedirects;
        redirectCount++
      ) {
        if (isActive != null && !isActive()) {
          throw StateError('Download cancelled');
        }
        final request = http.Request('GET', currentUri)
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['Accept'] = '*/*';
        if (cookieHeader.isNotEmpty &&
            urlsHaveSameOrigin(currentUri.toString(), cookieOrigin)) {
          request.headers['Cookie'] = cookieHeader;
        }
        final schoolHost =
            currentUri.host == 'bnbu.edu.cn' ||
            currentUri.host.endsWith('.bnbu.edu.cn');
        final transport =
            currentUri.scheme == 'https' && schoolHost && schoolClient != null
            ? schoolClient
            : client;
        response = await transport
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (!_isRedirectStatus(response.statusCode)) {
          break;
        }
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null || location.trim().isEmpty) {
          throw PlatformException(
            code: 'invalid_download_redirect',
            message: '下载地址返回了无效跳转。',
          );
        }
        final redirectedUri = currentUri.resolve(location.trim());
        if (!_isHttpUri(redirectedUri) || redirectedUri.userInfo.isNotEmpty) {
          throw PlatformException(
            code: 'invalid_download_redirect',
            message: '下载地址跳转到了不受支持的目标。',
          );
        }
        if (startedWithHttps && redirectedUri.scheme.toLowerCase() != 'https') {
          throw PlatformException(
            code: 'insecure_download_redirect',
            message: 'HTTPS 下载不能降级到不安全连接。',
          );
        }
        currentUri = redirectedUri;
        response = null;
        if (redirectCount == maximumRedirects) {
          throw PlatformException(
            code: 'too_many_download_redirects',
            message: '下载地址跳转次数过多。',
          );
        }
      }

      final completedResponse = response;
      if (completedResponse == null || completedResponse.statusCode != 200) {
        final statusCode = completedResponse?.statusCode;
        await completedResponse?.stream.drain<void>();
        throw PlatformException(
          code: 'download_failed',
          message: statusCode == null ? '文件下载失败。' : '文件下载失败（HTTP $statusCode）。',
        );
      }
      final contentLength = completedResponse.contentLength;
      if (contentLength != null && contentLength > maximumDownloadBytes) {
        await completedResponse.stream.listen((_) {}).cancel();
        throw PlatformException(
          code: 'download_too_large',
          message: '文件超过当前下载大小上限。',
        );
      }
      final contentType =
          completedResponse.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.startsWith('text/html') &&
          !_looksLikeHtmlFilename(filename)) {
        await completedResponse.stream.drain<void>();
        throw PlatformException(
          code: 'unexpected_html_download',
          message: '下载返回了登录页或网页，未保存为目标文件。',
        );
      }

      final downloadsDirectory =
          destinationDirectory ??
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      await downloadsDirectory.create(recursive: true);
      final destination = await _availableDestination(
        downloadsDirectory,
        resolvedDownloadFilename(
          suggested: filename,
          disposition: completedResponse.headers['content-disposition'],
          contentType: contentType,
        ),
      );
      final temporaryFile = File(
        '${destination.path}.part-${DateTime.now().microsecondsSinceEpoch}',
      );
      var receivedBytes = 0;
      final sink = temporaryFile.openWrite();
      try {
        await for (final chunk in completedResponse.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (isActive != null && !isActive()) {
            throw StateError('Download cancelled');
          }
          receivedBytes += chunk.length;
          if (receivedBytes > maximumDownloadBytes) {
            throw PlatformException(
              code: 'download_too_large',
              message: '文件超过当前下载大小上限。',
            );
          }
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        // IOClient may transparently decompress gzip. Content-Length then
        // describes the encoded body, not the bytes exposed by this stream.
        final encoding = completedResponse.headers['content-encoding']
            ?.trim()
            .toLowerCase();
        if (contentLength != null &&
            (encoding == null || encoding == 'identity') &&
            receivedBytes != contentLength) {
          throw PlatformException(
            code: 'incomplete_download',
            message: '文件下载不完整，请重试。',
          );
        }
        if (isActive != null && !isActive()) {
          throw StateError('Download cancelled');
        }
        await temporaryFile.rename(destination.path);
        return destination.path;
      } catch (_) {
        await sink.close();
        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
        rethrow;
      }
    } on TimeoutException {
      throw PlatformException(
        code: 'download_timeout',
        message: '文件下载超时，请检查网络后重试。',
      );
    } finally {
      client.close();
      schoolClient?.close();
    }
  }
}

/// Prefer the server filename; extensionless resource endpoints are not files'
/// real names. Sanitize all untrusted names before using them on disk.
String resolvedDownloadFilename({
  required String suggested,
  String? disposition,
  String contentType = '',
}) {
  String? responseName;
  final extended = RegExp(
    r"filename\*\s*=\s*UTF-8'[^']*'([^;\r\n]+)",
    caseSensitive: false,
  ).firstMatch(disposition ?? '');
  if (extended != null) {
    try {
      responseName = Uri.decodeComponent(
        extended.group(1)!.trim().replaceAll('"', ''),
      );
    } on FormatException {
      /* Fall back to the plain filename. */
    }
  }
  responseName ??= RegExp(
    r'filename\s*=\s*(?:"([^"]+)"|([^;\r\n]+))',
    caseSensitive: false,
  ).firstMatch(disposition ?? '')?.group(1);
  responseName ??= RegExp(
    r'filename\s*=\s*([^;"\r\n]+)',
    caseSensitive: false,
  ).firstMatch(disposition ?? '')?.group(1);
  var name = safeAttachmentFileName(responseName ?? suggested);
  const extensions = {
    'application/pdf': '.pdf',
    'application/zip': '.zip',
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'text/plain': '.txt',
    'text/csv': '.csv',
    'application/msword': '.doc',
    'application/vnd.ms-excel': '.xls',
    'application/vnd.ms-powerpoint': '.ppt',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        '.docx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        '.xlsx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        '.pptx',
  };
  final extension =
      extensions[contentType.split(';').first.trim().toLowerCase()];
  if (extension != null &&
      (!name.contains('.') ||
          RegExp(r'\.(php|aspx?|bin)$', caseSensitive: false).hasMatch(name))) {
    name = name.replaceFirst(
      RegExp(r'\.(php|aspx?|bin)$', caseSensitive: false),
      '',
    );
    name = '$name$extension';
  }
  return name;
}

bool _isRedirectStatus(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

bool _looksLikeHtmlFilename(String filename) {
  final normalized = filename.toLowerCase();
  return normalized.endsWith('.html') || normalized.endsWith('.htm');
}

Future<File> _availableDestination(Directory directory, String filename) async {
  final initial = File(_joinPath(directory.path, filename));
  if (!await initial.exists()) {
    return initial;
  }
  final dotIndex = filename.lastIndexOf('.');
  final hasExtension = dotIndex > 0 && dotIndex < filename.length - 1;
  final baseName = hasExtension ? filename.substring(0, dotIndex) : filename;
  final extension = hasExtension ? filename.substring(dotIndex) : '';
  for (var suffix = 2; suffix <= 999; suffix++) {
    final candidate = File(
      _joinPath(directory.path, '$baseName ($suffix)$extension'),
    );
    if (!await candidate.exists()) {
      return candidate;
    }
  }
  throw PlatformException(
    code: 'download_destination_unavailable',
    message: '下载目录中存在过多同名文件。',
  );
}

String _joinPath(String parent, String child) {
  final separator = Platform.pathSeparator;
  return parent.endsWith(separator)
      ? '$parent$child'
      : '$parent$separator$child';
}

String downloadedFileDisplayName(Object? result, {required String fallback}) {
  final normalizedFallback = fallback.trim();
  if (result is! String || result.trim().isEmpty) {
    return normalizedFallback;
  }
  final raw = result.trim();
  final parsed = Uri.tryParse(raw);
  if (parsed?.scheme.toLowerCase() == 'content') {
    return normalizedFallback;
  }
  final normalizedPath = raw.replaceAll('\\', '/');
  final lastSegment = normalizedPath.split('/').last.trim();
  if (lastSegment.isEmpty) {
    return normalizedFallback;
  }
  return Uri.decodeComponent(lastSegment);
}

String safeAttachmentFileName(String rawName) {
  final trimmed = rawName.trim();
  final withoutPath = trimmed.split(RegExp(r'[/\\]')).last.trim();
  final sanitized = withoutPath.replaceAll(RegExp(r'[:*?"<>|\x00-\x1F]'), '_');
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
    return 'attachment.bin';
  }
  return sanitized;
}

String mailAttachmentCacheFileName({
  required String accountId,
  required String mailbox,
  required int messageUid,
  required String partId,
  required String originalName,
  String? messageId,
  int? mailboxUidValidity,
}) {
  final scope = jsonEncode(<String>[
    accountId.trim().toLowerCase(),
    mailbox.trim().toLowerCase(),
    mailboxUidValidity?.toString() ?? '',
    messageId?.trim() ?? '',
    messageUid.toString(),
    partId,
  ]);
  final digest = sha256.convert(utf8.encode(scope)).toString().substring(0, 24);
  final prefix = '${digest}_';
  final availableBytes = 240 - utf8.encode(prefix).length;
  final displayName = _truncateFileNameToUtf8Bytes(
    safeAttachmentFileName(originalName),
    availableBytes,
  );
  return '$prefix$displayName';
}

String _truncateFileNameToUtf8Bytes(String fileName, int maxBytes) {
  if (utf8.encode(fileName).length <= maxBytes) {
    return fileName;
  }

  final dotIndex = fileName.lastIndexOf('.');
  final hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1;
  final extension = hasExtension ? fileName.substring(dotIndex) : '';
  final extensionBytes = utf8.encode(extension).length;
  if (extensionBytes >= maxBytes) {
    return _truncateUtf8(fileName, maxBytes);
  }

  final baseName = hasExtension ? fileName.substring(0, dotIndex) : fileName;
  final truncatedBase = _truncateUtf8(baseName, maxBytes - extensionBytes);
  return '$truncatedBase$extension';
}

String _truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) {
    return '';
  }
  final buffer = StringBuffer();
  var byteCount = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final characterBytes = utf8.encode(character).length;
    if (byteCount + characterBytes > maxBytes) {
      break;
    }
    buffer.write(character);
    byteCount += characterBytes;
  }
  return buffer.toString();
}

bool urlsHaveSameOrigin(String first, String second) {
  final left = Uri.tryParse(first.trim());
  final right = Uri.tryParse(second.trim());
  if (!_isHttpUri(left) || !_isHttpUri(right)) {
    return false;
  }
  return left!.scheme.toLowerCase() == right!.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      _effectiveUriPort(left) == _effectiveUriPort(right);
}

bool _isHttpUri(Uri? uri) {
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

int _effectiveUriPort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => -1,
  };
}
